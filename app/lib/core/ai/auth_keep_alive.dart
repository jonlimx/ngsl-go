import 'dart:io';
import 'package:flutter/services.dart';

class AuthKeepAlive {
  static const _channel = MethodChannel('com.jonlimx.ngsl_go/auth');
  Future<void> start() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('startLogin');
  }

  Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopLogin');
  }
}
