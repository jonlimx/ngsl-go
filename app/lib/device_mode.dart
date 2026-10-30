import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'models.dart';
import 'network_policy.dart';

enum DeviceDisplayMode { automatic, standard, eink }

class DeviceIdentity {
  const DeviceIdentity({
    this.brand = '',
    this.manufacturer = '',
    this.models = const [],
    this.features = const [],
  });
  factory DeviceIdentity.fromJson(Map<String, dynamic> json) => DeviceIdentity(
    brand: json['brand'] as String? ?? '',
    manufacturer: json['manufacturer'] as String? ?? '',
    models: List<String>.from(json['models'] ?? []),
    features: List<String>.from(json['features'] ?? []),
  );
  final String brand, manufacturer;
  final List<String> models, features;
  bool get eink {
    // Match marketed model names across spacing/punctuation and vendor fields.
    // Do not classify by resolution, screen size, or a generic Android brand.
    final names = models.map(
      (s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''),
    );
    return names.any((s) => s.contains('ocean5pro')) ||
        features.any(
          (s) => const {
            'android.hardware.eink',
            'android.hardware.epd',
            'android.hardware.e_ink',
          }.contains(s.toLowerCase()),
        );
  }

  String get description =>
      models.where((s) => s.trim().isNotEmpty).firstOrNull ?? '未读取到设备型号';
}

class DeviceModeController extends ChangeNotifier {
  DeviceModeController({
    Future<DeviceIdentity> Function()? detect,
    Future<void> Function(bool)? applyNative,
  }) : _detect = detect ?? _readIdentity,
       _applyNative = applyNative ?? _configureNative;
  static final instance = DeviceModeController();
  static const channel = MethodChannel('com.jonlimx.ngsl_go/device');
  final Future<DeviceIdentity> Function() _detect;
  final Future<void> Function(bool) _applyNative;
  DeviceDisplayMode mode = DeviceDisplayMode.automatic;
  DeviceIdentity identity = const DeviceIdentity();
  String? notice;
  Directory? _directory;
  Future<void> _writes = Future.value();
  bool get eink => switch (mode) {
    DeviceDisplayMode.automatic => identity.eink,
    DeviceDisplayMode.standard => false,
    DeviceDisplayMode.eink => true,
  };
  File get _file => File('${_directory!.path}/device_settings.json');

  static Future<DeviceIdentity> _readIdentity() async {
    if (!Platform.isAndroid) return const DeviceIdentity();
    final result = await channel
        .invokeMapMethod<String, dynamic>('deviceInfo')
        .timeout(const Duration(seconds: 5));
    return DeviceIdentity.fromJson(Map<String, dynamic>.from(result ?? {}));
  }

  static Future<void> _configureNative(bool offline) async {
    if (!Platform.isAndroid) return;
    await channel
        .invokeMethod<void>('setOffline', offline)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> load(Directory directory) async {
    _directory = directory;
    try {
      identity = await _detect();
    } catch (_) {
      notice = '暂时无法识别设备，可手动选择显示模式。';
    }
    if (await _file.exists()) {
      var recovered = false;
      for (final file in [_file, File('${_file.path}.bak')]) {
        try {
          final data = jsonDecode(await file.readAsString());
          if (data['version'] != 1) throw const FormatException();
          mode = DeviceDisplayMode.values.byName(data['mode'] as String);
          recovered = true;
          break;
        } catch (_) {
          /* Preserve both files; learning data is never opened. */
        }
      }
      if (!recovered) notice = '设备模式设置暂时无法读取，已按设备识别；可重新选择模式。';
    }
    NetworkPolicy.configure(offline: eink);
    await _applyNative(eink);
    notifyListeners();
  }

  Future<void> setMode(DeviceDisplayMode next) {
    final result = _writes.catchError((_) {}).then((_) async {
      // Disable transport before any await or notification can expose a stale UI.
      final previous = mode;
      mode = next;
      NetworkPolicy.configure(offline: eink);
      try {
        await _applyNative(eink);
        if (_directory != null) {
          await _directory!.create(recursive: true);
          final pending = File('${_file.path}.pending');
          await pending.writeAsString(
            jsonEncode({'version': 1, 'mode': next.name}),
            flush: true,
          );
          if (await _file.exists()) await _file.copy('${_file.path}.bak');
          await pending.rename(_file.path);
        }
      } catch (_) {
        mode = previous;
        NetworkPolicy.configure(offline: eink);
        // Native starts offline and only permits login after this handshake.
        try {
          await _applyNative(eink);
        } catch (_) {
          /* remains fail-closed */
        }
        notifyListeners();
        throw const ContentException('设备模式未能保存，请重试。学习记录不受影响。');
      }
      notice = null;
      notifyListeners();
    });
    _writes = result;
    return result;
  }
}

class DeviceModeScope extends InheritedNotifier<DeviceModeController> {
  const DeviceModeScope({
    super.key,
    required DeviceModeController controller,
    required super.child,
  }) : super(notifier: controller);
  static DeviceModeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeviceModeScope>()?.notifier ??
      DeviceModeController.instance;
  static bool isEink(BuildContext context) => of(context).eink;
}
