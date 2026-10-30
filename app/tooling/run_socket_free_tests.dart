// Runs the real test_api LiveTest suites in the Flutter engine without the
// Flutter CLI's WebSocket transport. Keep this adapter tied to pubspec.lock.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'dart:io';
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/runtime.dart';
import 'package:test_api/src/backend/state.dart';
import 'package:test_api/src/backend/suite.dart';
import 'package:test_api/src/backend/suite_platform.dart';
import 'package:test_api/src/backend/test.dart';
import '../test/study_store_test.dart' as stores;
import '../test/story_validation_test.dart' as stories;
import '../test/tablet_ui_test.dart' as tablet;
import '../test/memory_learning_test.dart' as memory;
import '../test/vocabulary_features_test.dart' as vocabulary;
import '../test/daily_updates_test.dart' as updates;
import '../test/common_meanings_test.dart' as meanings;
import '../test/device_mode_test.dart' as device;

Future<void> main() async {
  final declarer = Declarer();
  declarer.declare(() {
    declarer.group('store', stores.main);
    declarer.group('story', stories.main);
    declarer.group('tablet', tablet.main);
    declarer.group('memory', memory.main);
    declarer.group('vocabulary', vocabulary.main);
    declarer.group('updates', updates.main);
    declarer.group('meanings', meanings.main);
    declarer.group('device', device.main);
  });
  final suite = Suite(declarer.build(), SuitePlatform(Runtime.vm));
  var passed = 0, failed = 0;
  Future<void> runGroup(Group group, List<Group> ancestors) async {
    final groups = [...ancestors, group];
    for (final entry in group.entries) {
      if (entry is Group) {
        await runGroup(entry, groups);
      } else if (entry is Test) {
        stdout.writeln('RUN ${entry.name}');
        final live = entry.load(suite, groups: groups);
        live.onMessage.listen((message) => stdout.writeln(message.text));
        live.onError.listen((error) => stderr.writeln(error));
        await live.run();
        if (live.state.result == Result.success) {
          passed++;
          stdout.writeln('PASS ${entry.name}');
        } else {
          failed++;
          stderr.writeln('FAIL ${entry.name}: ${live.errors}');
        }
        await live.close();
      }
    }
  }

  await runGroup(suite.group, []);
  stdout.writeln('Flutter suites: $passed passed, $failed failed');
  exit(failed == 0 ? 0 : 1);
}
