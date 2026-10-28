import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:flutter/foundation.dart';

import 'auth_keep_alive.dart';
import 'oauth_loopback.dart';
import 'package:url_launcher/url_launcher.dart';

/// OAuth client for eligible ChatGPT plan usage in NGSL Go.
///
/// Credentials are kept in the operating system's secure storage. Authorization
/// returns through the loopback callback required by ChatGPT plan registration.
class ChatGptPlanAuthService {
  ChatGptPlanAuthService({FlutterSecureStorage? storage, http.Client? client})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          ),
      _client = client ?? http.Client();

  static final ChatGptPlanAuthService instance = ChatGptPlanAuthService();

  static const _sessionStorageKey = 'ngsl_chatgpt_plan_session';
  static const _registrationStorageKey = 'ngsl_chatgpt_registration';
  static const _hostIdStorageKey = 'ngsl_chatgpt_plan_host_id';
  static const _authorizeEndpoint =
      'https://auth.openai.com/api/accounts/authorize';
  static const _tokenEndpoint =
      'https://auth.openai.com/api/accounts/oauth/token';
  static const _jwksEndpoint = 'https://auth.openai.com/.well-known/jwks.json';
  static const _oidcConfigurationEndpoint =
      'https://auth.openai.com/.well-known/openid-configuration';
  static const _apiBaseUrl = 'https://api.openai.com/v1';
  static const _issuer = 'https://auth.openai.com';
  static const _requiredScopes = <String>{
    'openid',
    'profile',
    'email',
    'offline_access',
    'resource.invoke',
    'chatgpt.tokens.use.direct',
  };
  static const _authTimeout = Duration(minutes: 5);
  static const _networkTimeout = Duration(seconds: 30);

  final FlutterSecureStorage _storage;
  final http.Client _client;
  Future<String>? _refreshing;
  Future<List<String>>? _modelListRequest;
  Future<void> _credentialOperations = Future.value();
  int _sessionEpoch = 0;
  bool _signingOut = false;

  Future<bool> get hasSession async => (await _readSession()) != null;
  Future<String?> get connectedEmail async =>
      (await _readSession())?['email']?.toString();

  final connectionStage = ValueNotifier<ChatGptConnectionStage>(
    ChatGptConnectionStage.idle,
  );
  final _keepAlive = AuthKeepAlive();
  OAuthLoopbackAttempt? _pendingCallback;
  Completer<Never>? _cancelSignIn;
  bool _isSigningIn = false;

  void submitCallbackLink(String text) {
    final pending = _pendingCallback;
    if (pending == null ||
        connectionStage.value != ChatGptConnectionStage.waiting) {
      throw const ChatGptPlanAuthException('没有等待中的登录，请先点击连接 ChatGPT。');
    }
    try {
      pending.acceptManualReturn(text);
    } on OAuthCallbackException catch (e) {
      throw ChatGptPlanAuthException(e.message);
    }
  }

  void cancelSignIn() {
    final cancel = _cancelSignIn;
    if (cancel == null || cancel.isCompleted) return;
    ++_sessionEpoch;
    cancel.completeError(const ChatGptPlanAuthException('已取消连接。'));
  }

  Future<void> signIn() async {
    if (_signingOut || _isSigningIn) {
      throw const ChatGptPlanAuthException('正在处理账号连接，请稍后再试。');
    }
    _isSigningIn = true;
    final cancel = Completer<Never>();
    _cancelSignIn = cancel;
    unawaited(cancel.future.then<void>((_) {}, onError: (Object _) {}));
    Future<T> active<T>(Future<T> operation) =>
        Future.any<T>([operation, cancel.future]);
    OAuthLoopbackAttempt? callback;
    try {
      connectionStage.value = ChatGptConnectionStage.preparing;
      final epoch = ++_sessionEpoch;
      _refreshing = null;
      final previousSession = await active(_readSession());
      final registration = previousSession ?? await active(_readRegistration());
      final state = _randomUrlSafe(32);
      callback = await OAuthLoopbackAttempt.start(state);
      _pendingCallback = callback;
      final redirectUri = callback.redirectUri;
      final nonce = _randomUrlSafe(32);
      final verifier = _randomUrlSafe(64);
      final challenge = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      final hostId = await active(_getOrCreateHostId());
      final isRegistration = registration == null;
      final clientId = isRegistration
          ? 'dynamic_agent_client'
          : registration['client_id']!.toString();
      final query = <String, String>{
        'client_id': clientId,
        'ext_agent_host_id': hostId,
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'scope': _requiredScopes.join(' '),
        'resource': _apiBaseUrl,
        'state': state,
        'nonce': nonce,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
      };
      if (isRegistration) {
        query['agent_name_hint'] = 'NGSL Go';
      } else {
        final idToken = previousSession?['id_token']?.toString();
        final email = registration['email']?.toString();
        if (idToken != null && idToken.isNotEmpty) {
          query['id_token_hint'] = idToken;
        }
        if (email != null && email.isNotEmpty) {
          query['login_hint'] = email;
        }
      }

      final authorizationUri = Uri.parse(
        _authorizeEndpoint,
      ).replace(queryParameters: query);
      // Start while the activity is foreground, before handing off to the browser.
      await active(_keepAlive.start());
      connectionStage.value = ChatGptConnectionStage.waiting;
      final launched = await active(
        launchUrl(
          authorizationUri,
          mode: Platform.isIOS
              ? LaunchMode.inAppBrowserView
              : LaunchMode.externalApplication,
        ),
      );
      if (!launched) {
        throw const ChatGptPlanAuthException('无法打开系统浏览器。');
      }

      final params = await active(callback.result.timeout(_authTimeout));
      connectionStage.value = ChatGptConnectionStage.exchanging;
      await callback.close();
      if ((params['state'] ?? '') != state) {
        throw const ChatGptPlanAuthException('ChatGPT 登录状态校验失败，请重新连接。');
      }
      final callbackError = params['error'];
      if (callbackError != null && callbackError.isNotEmpty) {
        throw ChatGptPlanAuthException(
          'ChatGPT 授权未完成：${params['error_description'] ?? callbackError}',
        );
      }
      final code = params['code'] ?? '';
      if (code.isEmpty) {
        throw const ChatGptPlanAuthException('ChatGPT 回调没有返回授权码。');
      }

      final callbackClientId = params['client_id'];
      if (!isRegistration &&
          callbackClientId != null &&
          callbackClientId != clientId) {
        throw const ChatGptPlanAuthException('ChatGPT 返回的客户端与当前账号不匹配，请重新连接。');
      }

      final issuedClientId = isRegistration
          ? (callbackClientId ?? '')
          : clientId;
      if (issuedClientId.isEmpty || issuedClientId == 'dynamic_agent_client') {
        throw const ChatGptPlanAuthException(
          'ChatGPT 没有完成应用注册，请确认此客户端有 ChatGPT plan usage 权限。',
        );
      }

      final tokenResponse = await active(
        _exchangeAuthorizationCode(
          clientId: issuedClientId,
          code: code,
          verifier: verifier,
          redirectUri: redirectUri,
        ),
      );
      final session = await active(
        _validatedSession(
          tokenResponse,
          clientId: issuedClientId,
          expectedNonce: nonce,
          hostId: hostId,
        ),
      );
      if (!isRegistration && session['subject'] != registration['subject']) {
        throw const ChatGptPlanAuthException(
          '登录的 ChatGPT 账号与已连接账号不同，请重新选择原账号。',
        );
      }
      await _saveSession(session, expectedEpoch: epoch);
      connectionStage.value = ChatGptConnectionStage.connected;
    } on OAuthCallbackException catch (e) {
      throw ChatGptPlanAuthException(e.message);
    } on SocketException {
      throw const ChatGptPlanAuthException('无法建立登录连接，请确认 VPN 正常并重试。');
    } on TimeoutException {
      throw const ChatGptPlanAuthException(
        '连接超时。请重新登录；若浏览器回调页打不开，可返回这里粘贴完整链接。',
      );
    } finally {
      _pendingCallback = null;
      _cancelSignIn = null;
      try {
        await callback?.close();
      } finally {
        try {
          await _keepAlive.stop();
        } catch (_) {
          /* Native service also expires. */
        }
        _isSigningIn = false;
        connectionStage.value = ChatGptConnectionStage.idle;
      }
    }
  }

  Future<bool> signOut() async {
    if (_signingOut) return false;
    cancelSignIn();
    _signingOut = true;
    ++_sessionEpoch;
    _refreshing = null;
    var remoteRevocationConfirmed = false;
    try {
      final session = await _readSession();
      if (session == null) return true;
      await _saveRegistration(session);
      final configurationResponse = await _client
          .get(Uri.parse(_oidcConfigurationEndpoint))
          .timeout(_networkTimeout);
      if (configurationResponse.statusCode >= 200 &&
          configurationResponse.statusCode < 300) {
        final configuration =
            jsonDecode(configurationResponse.body) as Map<String, dynamic>;
        final endpoint = configuration['revocation_endpoint']?.toString();
        final refreshToken = session['refresh_token']?.toString() ?? '';
        final clientId = session['client_id']?.toString() ?? '';
        if (endpoint != null &&
            refreshToken.isNotEmpty &&
            clientId.isNotEmpty) {
          final response = await _client
              .post(
                Uri.parse(endpoint),
                headers: {
                  HttpHeaders.contentTypeHeader:
                      'application/x-www-form-urlencoded; charset=utf-8',
                },
                body: {
                  'token': refreshToken,
                  'token_type_hint': 'refresh_token',
                  'client_id': clientId,
                },
              )
              .timeout(_networkTimeout);
          remoteRevocationConfirmed = response.statusCode == HttpStatus.ok;
        }
      }
    } catch (_) {
      // Clear local credentials on sign-out even if the device is offline.
    } finally {
      try {
        await _updateCredentials(
          () => _storage.delete(key: _sessionStorageKey),
        );
      } finally {
        _modelListRequest = null;
        _signingOut = false;
      }
    }
    return remoteRevocationConfirmed;
  }

  Future<String> getValidAccessToken() async {
    final epoch = _sessionEpoch;
    if (_signingOut) {
      throw const ChatGptPlanAuthException('正在退出 ChatGPT 账号。');
    }
    final session = await _readSession();
    if (session == null || epoch != _sessionEpoch || _signingOut) {
      throw const ChatGptPlanAuthException('请先登录 ChatGPT 并授权使用订阅额度。');
    }

    final expiresAt = int.tryParse(session['expires_at_ms']?.toString() ?? '');
    final accessToken = session['access_token']?.toString() ?? '';
    if (expiresAt != null &&
        expiresAt > DateTime.now().millisecondsSinceEpoch + 60000 &&
        accessToken.isNotEmpty) {
      return accessToken;
    }
    return _refreshAccessToken(session, epoch);
  }

  Future<List<String>> getAvailableModels() {
    return _modelListRequest ??= _loadAvailableModels().whenComplete(() {
      _modelListRequest = null;
    });
  }

  Future<List<String>> _loadAvailableModels() async {
    final token = await getValidAccessToken();
    final response = await _client
        .get(
          Uri.parse('$_apiBaseUrl/models'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatGptPlanAuthException(
        '无法读取 ChatGPT 账号可用模型（HTTP ${response.statusCode}）。',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (decoded['models'] as List?) ?? const [];
    return models
        .whereType<Map<String, dynamic>>()
        .where((item) => item['visibility'] == 'list')
        .map((item) => item['slug']?.toString() ?? '')
        .where((slug) => slug.isNotEmpty)
        .toList(growable: false);
  }

  Future<String> _refreshAccessToken(Map<String, dynamic> current, int epoch) {
    if (_refreshing != null) return _refreshing!;
    late final Future<String> request;
    request = _performTokenRefresh(current, epoch).whenComplete(() {
      if (identical(_refreshing, request)) _refreshing = null;
    });
    return _refreshing = request;
  }

  Future<String> _performTokenRefresh(
    Map<String, dynamic> current,
    int epoch,
  ) async {
    final refreshToken = current['refresh_token']?.toString() ?? '';
    final clientId = current['client_id']?.toString() ?? '';
    if (refreshToken.isEmpty || clientId.isEmpty) {
      throw const ChatGptPlanAuthException('ChatGPT 登录已失效，请重新连接账号。');
    }

    final response = await _client
        .post(
          Uri.parse(_tokenEndpoint),
          headers: {
            HttpHeaders.contentTypeHeader:
                'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: {
            'grant_type': 'refresh_token',
            'client_id': clientId,
            'refresh_token': refreshToken,
            'resource': _apiBaseUrl,
          },
        )
        .timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ChatGptPlanAuthException('ChatGPT 会话已过期，请重新连接账号。');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token']?.toString() ?? '';
    final nextRefreshToken = body['refresh_token']?.toString() ?? refreshToken;
    final expiresIn =
        int.tryParse(body['expires_in']?.toString() ?? '') ?? 3600;
    final grantedScopes = body['scope'] == null
        ? ((current['scopes'] as List?) ?? const [])
              .map((scope) => scope.toString())
              .toSet()
        : body['scope']
              .toString()
              .split(RegExp(r'\s+'))
              .where((scope) => scope.isNotEmpty)
              .toSet();
    if (accessToken.isEmpty) {
      throw const ChatGptPlanAuthException('ChatGPT 刷新会话没有返回访问令牌。');
    }
    if (!grantedScopes.contains('chatgpt.tokens.use.direct')) {
      throw const ChatGptPlanAuthException('当前 ChatGPT 会话没有使用订阅额度的权限，请重新连接账号。');
    }

    final updated = <String, dynamic>{
      ...current,
      'access_token': accessToken,
      'refresh_token': nextRefreshToken,
      'scopes': grantedScopes.toList()..sort(),
      'expires_at_ms':
          '${DateTime.now().millisecondsSinceEpoch + expiresIn * 1000}',
    };
    await _saveSession(updated, expectedEpoch: epoch);
    if (epoch != _sessionEpoch || _signingOut) {
      throw const ChatGptPlanAuthException('账号状态已改变，请重新连接。');
    }
    return accessToken;
  }

  Future<Map<String, dynamic>> _exchangeAuthorizationCode({
    required String clientId,
    required String code,
    required String verifier,
    required Uri redirectUri,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_tokenEndpoint),
          headers: {
            HttpHeaders.contentTypeHeader:
                'application/x-www-form-urlencoded; charset=utf-8',
          },
          body: {
            'grant_type': 'authorization_code',
            'client_id': clientId,
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirectUri.toString(),
            'resource': _apiBaseUrl,
          },
        )
        .timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatGptPlanAuthException(
        'ChatGPT 授权码交换失败（HTTP ${response.statusCode}）。',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _validatedSession(
    Map<String, dynamic> tokenResponse, {
    required String clientId,
    required String expectedNonce,
    required String hostId,
  }) async {
    final grantedScopes = (tokenResponse['scope']?.toString() ?? '')
        .split(RegExp(r'\s+'))
        .where((scope) => scope.isNotEmpty)
        .toSet();
    if (!grantedScopes.contains('chatgpt.tokens.use.direct')) {
      throw const ChatGptPlanAuthException('登录成功，但 ChatGPT 没有授予“使用订阅额度”权限。');
    }

    final idToken = tokenResponse['id_token']?.toString() ?? '';
    final accessToken = tokenResponse['access_token']?.toString() ?? '';
    final refreshToken = tokenResponse['refresh_token']?.toString() ?? '';
    if (idToken.isEmpty || accessToken.isEmpty || refreshToken.isEmpty) {
      throw const ChatGptPlanAuthException('ChatGPT 授权响应缺少必要的会话信息。');
    }

    final jwksResponse = await _client
        .get(Uri.parse(_jwksEndpoint))
        .timeout(_networkTimeout);
    if (jwksResponse.statusCode < 200 || jwksResponse.statusCode >= 300) {
      throw const ChatGptPlanAuthException('无法验证 ChatGPT 登录凭证。');
    }
    final jwks = JsonWebKeySet.fromJson(
      jsonDecode(jwksResponse.body) as Map<String, dynamic>,
    );
    final keyStore = JsonWebKeyStore()..addKeySet(jwks);
    final idTokenJwt = JsonWebToken.unverified(idToken);
    if (!await idTokenJwt.verify(
      keyStore,
      allowedArguments: const ['RS256', 'ES256'],
    )) {
      throw const ChatGptPlanAuthException('ChatGPT 登录凭证签名校验失败。');
    }

    final claims = idTokenJwt.claims.toJson();
    final audience = idTokenJwt.claims.audience ?? const <String>[];
    final expiry = int.tryParse(claims['exp']?.toString() ?? '') ?? 0;
    if (claims['iss'] != _issuer ||
        !audience.contains(clientId) ||
        expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 ||
        claims['nonce'] != expectedNonce ||
        (claims['sub']?.toString().isNotEmpty ?? false) == false) {
      throw const ChatGptPlanAuthException('ChatGPT 登录凭证校验失败。');
    }

    final expiresIn =
        int.tryParse(tokenResponse['expires_in']?.toString() ?? '') ?? 3600;
    return {
      'client_id': clientId,
      'email': claims['email']?.toString() ?? '',
      'subject': claims['sub']?.toString() ?? '',
      'id_token': idToken,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'scopes': grantedScopes.toList()..sort(),
      'ext_agent_host_id': hostId,
      'expires_at_ms':
          '${DateTime.now().millisecondsSinceEpoch + expiresIn * 1000}',
    };
  }

  Future<String> _getOrCreateHostId() async {
    final saved = await _storage.read(key: _hostIdStorageKey);
    if (saved != null && saved.isNotEmpty) return saved;

    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final raw = hex.join();
    final hostId =
        'urn:uuid:${raw.substring(0, 8)}-${raw.substring(8, 12)}-${raw.substring(12, 16)}-${raw.substring(16, 20)}-${raw.substring(20)}';
    await _storage.write(key: _hostIdStorageKey, value: hostId);
    return hostId;
  }

  String _randomUrlSafe(int byteCount) {
    final bytes = List<int>.generate(
      byteCount,
      (_) => Random.secure().nextInt(256),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<Map<String, dynamic>?> _readSession() async {
    final raw = await _storage.read(key: _sessionStorageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          ['client_id', 'access_token', 'refresh_token'].any(
            (key) =>
                decoded[key] is! String || (decoded[key] as String).isEmpty,
          ) ||
          int.tryParse(decoded['expires_at_ms']?.toString() ?? '') == null ||
          decoded['scopes'] is! List ||
          !(decoded['scopes'] as List).contains('chatgpt.tokens.use.direct')) {
        return null;
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readRegistration() async {
    final raw = await _storage.read(key: _registrationStorageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(
    Map<String, dynamic> session, {
    required int expectedEpoch,
  }) => _updateCredentials(() async {
    if (expectedEpoch != _sessionEpoch || _signingOut) {
      throw const ChatGptPlanAuthException('账号状态已改变，请重新连接。');
    }
    await _storage.write(key: _sessionStorageKey, value: jsonEncode(session));
    await _saveRegistration(session);
    _modelListRequest = null;
  });

  Future<void> _updateCredentials(Future<void> Function() operation) {
    final pending = _credentialOperations.then((_) => operation());
    _credentialOperations = pending.catchError((Object _) {});
    return pending;
  }

  Future<void> _saveRegistration(Map<String, dynamic> session) async {
    final registration = <String, dynamic>{
      'client_id': session['client_id'],
      'subject': session['subject'],
      'email': session['email'],
    };
    await _storage.write(
      key: _registrationStorageKey,
      value: jsonEncode(registration),
    );
  }
}

class ChatGptPlanAuthException implements Exception {
  const ChatGptPlanAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ChatGptConnectionStage { idle, preparing, waiting, exchanging, connected }
