import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// A single warm model lives on a background isolate. It never opens learning
/// data and it never downloads anything. Model resources are part of the APK.
class KokoroWorker {
  KokoroWorker({
    required this.modelDirectory,
    required this.audioDirectory,
    this.libraryPath,
    this.version = 'kokoro-multi-lang-v1_0-ngsl-en-1',
  });
  final String modelDirectory, audioDirectory, version;
  final String? libraryPath;
  ReceivePort? _receive;
  Future<SendPort>? _starting;
  final _pending = <int, Completer<String>>{};
  int _sequence = 0;
  Future<void> _controlWrites = Future.value();
  bool _disposed = false;
  File get _control => File('$audioDirectory/active-request');

  Future<void> _activate(String value) =>
      _controlWrites = _controlWrites.catchError((_) {}).then((_) async {
        final pending = File('$audioDirectory/active-request.pending');
        await pending.writeAsString(value, flush: true);
        await pending.rename(_control.path);
      });

  Future<SendPort> _start() => _starting ??= () async {
    if (_disposed) throw StateError('Kokoro worker is closed');
    await Directory(audioDirectory).create(recursive: true);
    final ready = Completer<SendPort>();
    _receive = ReceivePort();
    _receive!.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final result = message as List;
      final completer = _pending.remove(result[1] as int);
      if (completer == null) return;
      if (result[0] == 'done') {
        completer.complete(result[2] as String);
      } else {
        completer.completeError(StateError(result[2] as String));
      }
    });
    await Isolate.spawn(_runKokoro, {
      'reply': _receive!.sendPort,
      'model': modelDirectory,
      'audio': audioDirectory,
      'version': version,
      'library': libraryPath,
    });
    return ready.future.timeout(const Duration(seconds: 20));
  }();

  Future<String> render(String text, String accent) async {
    if (_disposed) throw StateError('Kokoro worker is closed');
    final port = await _start();
    final sequence = ++_sequence;
    await _activate('$sequence');
    if (_disposed || sequence != _sequence) {
      throw StateError('Speech cancelled');
    }
    final result = Completer<String>();
    _pending[sequence] = result;
    port.send([sequence, text, accent == 'us' ? 'us' : 'uk']);
    return result.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        _pending.remove(sequence);
        cancel();
        throw TimeoutException('Kokoro synthesis timed out');
      },
    );
  }

  Future<void> cancel() async {
    ++_sequence;
    if (_starting != null && await Directory(audioDirectory).exists()) {
      await _activate('cancelled');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    // Free the FFI object on its owner isolate after any cancelled generation.
    if (_starting != null) (await _starting!).send('close');
    for (final pending in _pending.values) {
      pending.completeError(StateError('Kokoro worker is closed'));
    }
    _pending.clear();
    _receive?.close();
  }
}

void _runKokoro(Map<String, dynamic> init) {
  final reply = init['reply'] as SendPort;
  final inbox = ReceivePort();
  final model = init['model'] as String;
  final directory = Directory(init['audio'] as String);
  final control = File('${directory.path}/active-request');
  sherpa.OfflineTts? tts;
  String? currentAccent;
  var initialized = false;
  reply.send(inbox.sendPort);
  inbox.listen((request) {
    if (request == 'close') {
      tts?.free();
      inbox.close();
      return;
    }
    final values = request as List;
    final sequence = values[0] as int;
    final text = values[1] as String;
    final accent = values[2] as String;
    bool active() =>
        control.existsSync() && control.readAsStringSync() == '$sequence';
    try {
      if (!active()) throw StateError('Speech cancelled');
      final hash = sha256
          .convert(
            utf8.encode('${init['version']}|sherpa-1.13.8|$accent|$text'),
          )
          .toString();
      final destination = File('${directory.path}/$hash.wav');
      if (destination.existsSync() && destination.lengthSync() > 44) {
        reply.send(['done', sequence, destination.path]);
        return;
      }
      if (!initialized) {
        sherpa.initBindings(init['library'] as String?);
        initialized = true;
      }
      if (currentAccent != accent || tts == null) {
        tts?.free();
        tts = null;
        currentAccent = null;
        final engine = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              kokoro: sherpa.OfflineTtsKokoroModelConfig(
                model: '$model/model.onnx',
                voices: '$model/voices.bin',
                tokens: '$model/tokens.txt',
                dataDir: '$model/espeak-ng-data',
                lexicon:
                    '$model/lexicon-${accent == 'us' ? 'us' : 'gb'}-en.txt',
              ),
              numThreads: 2,
              debug: false,
            ),
            maxNumSenetences: 1,
          ),
        );
        if (engine.numSpeakers < 22 || engine.sampleRate < 8000) {
          engine.free();
          throw StateError('Kokoro model is unavailable');
        }
        tts = engine;
        currentAccent = accent;
      }
      final generated = tts!.generateWithCallback(
        text: text,
        sid: accent == 'us' ? 3 : 21,
        speed: 1,
        callback: (_) => active() ? 1 : 0,
      );
      if (!active()) throw StateError('Speech cancelled');
      if (generated.samples.length < 1200 ||
          generated.samples.any((sample) => !sample.isFinite)) {
        throw StateError('Kokoro returned invalid audio');
      }
      final pending = '${directory.path}/$hash.pending.wav';
      if (!sherpa.writeWave(
        filename: pending,
        samples: generated.samples,
        sampleRate: generated.sampleRate,
      )) {
        throw StateError('Unable to write Kokoro audio');
      }
      File(pending).renameSync(destination.path);
      final cached =
          directory
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort(
              (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
            );
      var bytes = cached.fold<int>(0, (sum, file) => sum + file.lengthSync());
      for (final file in cached) {
        if (bytes <= 150 * 1024 * 1024) break;
        if (file.path == destination.path) continue;
        bytes -= file.lengthSync();
        file.deleteSync();
      }
      reply.send(['done', sequence, destination.path]);
    } catch (error) {
      reply.send(['error', sequence, error.toString()]);
    }
  });
}
