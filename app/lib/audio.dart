import 'dart:async';
import 'package:flutter/services.dart';
import 'models.dart';

class Speech {
  static const channel = MethodChannel('com.jonlimx.ngsl_go/speech');
  static Future<void> play(
    String text,
    String accent, {
    String? asset,
    double speed = 1,
  }) async {
    try {
      await channel
          .invokeMethod('play', {
            'text': text,
            'accent': accent,
            'asset': asset,
            'speed': speed,
          })
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      await stop();
      throw const ContentException('朗读准备超时，请检查英语语音包后重试。');
    } on PlatformException catch (e) {
      throw ContentException(e.message ?? '朗读暂时无法播放，请重试。');
    } on MissingPluginException {
      throw const ContentException('请在安卓平板上使用朗读。');
    }
  }

  static Future<void> stop() async {
    try {
      await channel.invokeMethod('stop');
    } on PlatformException {
      /* lifecycle cleanup */
    } on MissingPluginException {
      /* widget tests */
    }
  }
}
