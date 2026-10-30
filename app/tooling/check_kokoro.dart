// An opt-in real-model smoke check, separate from fast Flutter unit tests.
// dart run tooling/check_kokoro.dart /path/to/kokoro-multi-lang-v1_0
import 'dart:io';
import 'package:ngsl_go/kokoro.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the Kokoro model directory');
  final directory = await Directory.systemTemp.createTemp('ngsl_kokoro_');
  final worker = KokoroWorker(
    modelDirectory: args.single,
    audioDirectory: directory.path,
  );
  try {
    const text =
        'Although the weather changed, we continued our walk around the lake before returning to the village.';
    final watch = Stopwatch()..start();
    final uk = File(await worker.render(text, 'uk'));
    final us = File(await worker.render(text, 'us'));
    for (final file in [uk, us]) {
      final bytes = await file.readAsBytes();
      if (bytes.length <= 44 || String.fromCharCodes(bytes.take(4)) != 'RIFF') {
        throw StateError('Invalid generated WAV');
      }
    }
    if (uk.path == us.path) {
      throw StateError('Accent cache keys collided');
    }
    final modified = us.lastModifiedSync();
    if (await worker.render(text, 'us') != us.path ||
        us.lastModifiedSync() != modified) {
      throw StateError('Audio was not reused from cache');
    }
    final cancelled = worker
        .render(List.filled(10, text).join(' '), 'us')
        .then((_) => false, onError: (_) => true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await worker.cancel();
    if (!await cancelled) {
      throw StateError('Cancelled generation was not discarded');
    }
    stdout.writeln(
      'Kokoro real model: UK/US WAV generation, separate accent caches, cache reuse and cancellation passed (${watch.elapsedMilliseconds} ms).',
    );
  } finally {
    await worker.dispose();
    await directory.delete(recursive: true);
  }
}
