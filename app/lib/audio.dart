import 'dart:async';
import 'package:flutter/services.dart';
import 'kokoro.dart';
import 'models.dart';

class Speech {
  static const channel = MethodChannel('com.jonlimx.ngsl_go/speech');
  static KokoroWorker? _worker;
  static Future<Map<String, dynamic>>? _preparing;
  static int _generation = 0;
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'interrupted') {
        ++_generation;
        try {
          await _worker?.cancel();
        } catch (_) {
          /* native playback has stopped */
        }
      }
    });
  }

  /// Injection point for playback/routing tests; production always uses Kokoro.
  static Future<String> Function(String text, String accent) synthesize =
      _render;

  static Future<Map<String, dynamic>> voiceStatus({
    bool refresh = false,
  }) async {
    try {
      final raw = await channel
          .invokeMapMethod<String, dynamic>('voiceStatus')
          .timeout(const Duration(seconds: 5));
      return Map<String, dynamic>.from(raw ?? {});
    } on MissingPluginException {
      throw const ContentException('请在安卓平板上检查 Kokoro 离线语音。');
    } on PlatformException catch (e) {
      throw ContentException(e.message ?? '暂时无法检查 Kokoro 离线语音。');
    } on TimeoutException {
      throw const ContentException('Kokoro 语音检查超时，请重试。');
    }
  }

  static Future<Map<String, dynamic>> prepareVoices() =>
      _preparing ??= () async {
        try {
          final paths = await channel
              .invokeMapMethod<String, dynamic>('prepareKokoro')
              .timeout(const Duration(minutes: 3));
          if (paths?['model'] is! String || paths?['audio'] is! String) {
            throw const ContentException('安装包的 Kokoro 模型不完整，请重新运行安装脚本。');
          }
          return Map<String, dynamic>.from(paths!);
        } on MissingPluginException {
          throw const ContentException('请在安卓平板上使用 Kokoro 朗读。');
        } on PlatformException catch (e) {
          _preparing = null;
          throw ContentException(e.message ?? 'Kokoro 离线语音准备失败，请检查存储空间。');
        } catch (_) {
          rethrow;
        } finally {
          _preparing = null;
        }
      }();

  static Future<String> _render(String text, String accent) async {
    if (_worker == null) {
      final token = _generation;
      final paths = await prepareVoices();
      if (token != _generation) throw StateError('Speech cancelled');
      _worker ??= KokoroWorker(
        modelDirectory: paths['model'],
        audioDirectory: paths['audio'],
        version: paths['version'],
      );
    }
    return _worker!.render(text, accent);
  }

  static Future<void> play(
    String text,
    String accent, {
    String? asset,
    double speed = 1,
    void Function(String message)? onProgress,
  }) async {
    _listen();
    final token = ++_generation;
    try {
      await _worker?.cancel();
      if (token != _generation) return;
      if (asset != null && asset.isNotEmpty) {
        onProgress?.call('正在准备播放…');
        await channel
            .invokeMethod('play', {
              'text': text,
              'accent': accent,
              'asset': asset,
              'speed': speed,
            })
            .timeout(const Duration(seconds: 45));
        return;
      }
      if (text.trim().isEmpty || text.length > 15000) {
        throw const ContentException('这段文字暂时无法朗读。');
      }
      final nativeToken = await channel.invokeMethod<int>('beginSpeech');
      if (token != _generation) return;
      onProgress?.call('正在加载离线模型并生成语音，首次使用可能较慢，请稍候…');
      final file = await synthesize(text.trim(), accent);
      if (token != _generation) return;
      onProgress?.call('语音已生成，正在准备播放…');
      await channel
          .invokeMethod('playFile', {
            'path': file,
            'token': nativeToken,
            'speed': speed,
            'text': text,
            'accent': accent,
          })
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      if (token != _generation) return;
      await stop();
      throw const ContentException('Kokoro 朗读准备超时，首次加载可能较慢，请重试。');
    } on PlatformException catch (e) {
      if (token != _generation) return;
      throw ContentException(e.message ?? '朗读暂时无法播放，请重试。');
    } on MissingPluginException {
      throw const ContentException('请在安卓平板上使用朗读。');
    } on ContentException {
      rethrow;
    } catch (_) {
      if (token != _generation) return;
      throw const ContentException('Kokoro 朗读未能生成，请重试；首次使用请先在设置中准备离线语音。');
    }
  }

  static Future<void> stop() async {
    ++_generation;
    await _worker?.cancel();
    try {
      await channel.invokeMethod('stop');
    } on PlatformException {
      /* lifecycle cleanup */
    } on MissingPluginException {
      /* widget tests */
    }
  }
}
