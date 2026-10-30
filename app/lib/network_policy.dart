import 'dart:async';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Device policy, separate from learners and their credentials. Every external
/// HTTP client in this app passes through this gate, including token refresh.
class NetworkPolicy {
  static bool _offline = false;
  static int _revision = 0;
  static final _suspend = <void Function()>{};
  static bool get offline => _offline;
  static int get revision => _revision;

  static void configure({required bool offline}) {
    if (_offline == offline) return;
    _offline = offline;
    ++_revision;
    if (offline) {
      for (final cancel in List.of(_suspend)) {
        cancel();
      }
    }
  }

  static void requireOnline([int? revision]) {
    if (_offline || (revision != null && revision != _revision)) {
      throw const ContentException('墨水屏模式完全离线，已停止联网操作。');
    }
  }

  static void onSuspend(void Function() cancel) => _suspend.add(cancel);
  static void removeOnSuspend(void Function() cancel) =>
      _suspend.remove(cancel);
}

/// Created lazily so opening an offline screen never creates an HTTP client.
/// Closing an active transport aborts its request/stream when mode changes.
class OfflineAwareClient extends http.BaseClient {
  OfflineAwareClient({http.Client? client}) : _injected = client {
    NetworkPolicy.onSuspend(_suspend);
  }
  final http.Client? _injected;
  http.Client? _transport;
  bool _closed = false;

  void _suspend() {
    _transport?.close();
    _transport = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    NetworkPolicy.requireOnline();
    if (_closed) throw http.ClientException('Client is closed', request.url);
    final revision = NetworkPolicy.revision;
    final response = await (_transport ??= _injected ?? http.Client()).send(
      request,
    );
    NetworkPolicy.requireOnline(revision);
    return http.StreamedResponse(
      response.stream.map((bytes) {
        NetworkPolicy.requireOnline(revision);
        return bytes;
      }),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    _closed = true;
    NetworkPolicy.removeOnSuspend(_suspend);
    _suspend();
  }
}
