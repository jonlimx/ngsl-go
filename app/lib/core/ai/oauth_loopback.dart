import 'dart:async';
import 'dart:io';

/// One authorization attempt. Browser and manual return share the same checks.
class OAuthLoopbackAttempt {
  OAuthLoopbackAttempt._(this._server, this.state) {
    // Browser launch may still be pending when a callback arrives.
    unawaited(result.then<void>((_) {}, onError: (Object _) {}));
    _server.listen(
      _handleRequest,
      onError: (Object _) {
        if (!_result.isCompleted) {
          _result.completeError(const OAuthCallbackException('登录回调监听中断，请重试。'));
        }
      },
    );
  }

  static Future<OAuthLoopbackAttempt> start(String state) async =>
      OAuthLoopbackAttempt._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false),
        state,
      );

  final HttpServer _server;
  final String state;
  final _result = Completer<Map<String, String>>();
  bool _closed = false;
  bool _claimed = false;
  Future<Map<String, String>> get result => _result.future;
  Uri get redirectUri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/auth/callback',
  );

  void acceptManualReturn(String text) {
    if (text.length > 8192) {
      throw const OAuthCallbackException('回调链接过长，请重新复制浏览器地址栏的链接。');
    }
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.scheme != redirectUri.scheme ||
        uri.host != redirectUri.host ||
        uri.port != redirectUri.port ||
        uri.path != redirectUri.path ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const OAuthCallbackException('请粘贴本次登录后浏览器地址栏里的完整链接。');
    }
    try {
      _complete(_validate(uri));
    } on FormatException {
      throw const OAuthCallbackException('回调链接格式不正确，请重新复制完整链接。');
    }
  }

  Map<String, String> _validate(Uri uri) {
    if (_closed || _claimed || _result.isCompleted) {
      throw const OAuthCallbackException('本次回调已处理，请等待连接结果或重新连接。');
    }
    final all = uri.queryParametersAll;
    for (final key in ['state', 'code', 'client_id', 'error']) {
      if ((all[key]?.length ?? 0) > 1) {
        throw const OAuthCallbackException('回调链接格式不正确，请重新连接。');
      }
    }
    final params = uri.queryParameters;
    if (params['state'] != state) {
      // Another app's / old browser tab's callback must not kill this attempt.
      throw const OAuthCallbackException('这不是本次 NGSL Go 登录的链接，请检查浏览器标签页。');
    }
    if ((params['error'] ?? '').isEmpty && (params['code'] ?? '').isEmpty) {
      throw const OAuthCallbackException('链接没有包含授权结果，请完成浏览器登录后再复制。');
    }
    _claimed = true;
    return params;
  }

  void _complete(Map<String, String> params) {
    if (_closed || _result.isCompleted) return;
    if ((params['error'] ?? '').isNotEmpty) {
      _result.completeError(
        const OAuthCallbackException('ChatGPT 授权未完成，请重新连接并允许授权。'),
      );
    } else {
      _result.complete(params);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    Map<String, String>? accepted;
    final response = request.response;
    response.headers
      ..contentType = ContentType.html
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Content-Security-Policy', "default-src 'none'");
    try {
      if (request.method != 'GET' ||
          request.connectionInfo?.remoteAddress.isLoopback != true ||
          request.uri.path != redirectUri.path) {
        response.statusCode = HttpStatus.notFound;
      } else {
        accepted = _validate(request.uri);
        response.write(
          '<!doctype html><html><meta charset="utf-8"><title>NGSL Go</title><body>授权信息已收到。请返回 NGSL Go 等待连接结果。</body></html>',
        );
      }
    } on OAuthCallbackException {
      response.statusCode = HttpStatus.badRequest;
      response.write(
        '<!doctype html><html><meta charset="utf-8"><body>此登录链接已失效或不属于当前连接。请返回 NGSL Go 检查。</body></html>',
      );
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Browser may disconnect. */
      }
      // Flush the browser response before signIn closes the listening server.
      if (accepted != null) _complete(accepted);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }
}

class OAuthCallbackException implements Exception {
  const OAuthCallbackException(this.message);
  final String message;
}
