import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/audio.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';
import 'package:ngsl_go/study_session.dart';
import 'study_store_test.dart' show words;

void main() {
  test('initial success needs a next-day check, even when rated easy', () {
    final first = scheduleReview({}, Recall.easy, '2026-10-28');
    expect(first['due'], '2026-10-29');
    expect(first['memory']['meaning']['delayedSuccesses'], 0);
    final next = scheduleReview(first, Recall.good, '2026-10-29');
    expect(next['memory']['meaning']['interval'], greaterThan(1));
    expect(next['memory']['meaning']['delayedSuccesses'], 1);
    expect(next['memory'].containsKey('listening'), isFalse);
    // Untrained directions still require their own practice.
    expect(next['interval'], 1);
  });

  test(
    'a lapse or hint cannot erase other skills or extend its own interval',
    () {
      final before = <String, dynamic>{
        'screened': true,
        'memory': {
          'meaning': {
            'interval': 20,
            'due': '2026-10-28',
            'lastSeen': '2026-10-08',
            'reviews': 5,
          },
          'listening': {'interval': 10, 'due': '2026-11-01', 'reviews': 3},
        },
      };
      final hinted = scheduleReview(
        before,
        Recall.easy,
        '2026-10-28',
        hinted: true,
      );
      expect(hinted['memory']['meaning']['interval'], 1);
      expect(hinted['memory']['meaning']['delayedSuccesses'], 0);
      expect(hinted['memory']['listening'], before['memory']!['listening']);
      expect(hinted['screened'], true);
      final forgot = scheduleReview(before, Recall.again, '2026-10-28');
      final retry = scheduleReview(forgot, Recall.good, '2026-10-28');
      expect(retry['memory']['meaning']['interval'], 1);
      expect(retry['memory']['meaning']['delayedSuccesses'], 0);
    },
  );

  test(
    'unfinished difficult directions are retried before adding a new one',
    () {
      final failed = scheduleReview({}, Recall.again, '2026-10-28');
      expect(nextMemorySkill(failed, '2026-10-29'), MemorySkill.meaning);
      final success = scheduleReview(failed, Recall.good, '2026-10-29');
      expect(nextMemorySkill(success, '2026-10-30'), MemorySkill.listening);
    },
  );

  test(
    'a hinted direction due tomorrow does not displace a direction due today',
    () {
      final progress = <String, dynamic>{
        'memory': {
          for (final skill in MemorySkill.values)
            skill.name: {
              'lastRecall': skill == MemorySkill.listening ? 'hard' : 'good',
              'due': skill == MemorySkill.meaning ? '2026-10-28' : '2026-10-29',
              'interval': 1,
            },
        },
      };
      expect(nextMemorySkill(progress, '2026-10-28'), MemorySkill.meaning);
    },
  );

  test('review backlog reduces new words and retains overflow as due', () {
    final catalog = List.generate(
      dailyWordBudget + 20,
      (i) => Vocabulary('b$i', 'word$i', i, 'noun', '词', 'word', '', [], {}),
    );
    final progress = {
      for (var i = 0; i < dailyWordBudget + 5; i++)
        'b$i': {'status': 'learning', 'due': '2026-10-27'},
    };
    final plan = createDailyPlan(catalog, progress, 8, '2026-10-28');
    expect(plan['wordIds'], hasLength(dailyWordBudget));
    expect(plan['newIds'], isEmpty);
    expect(plan['deferredReviews'], 5);
    expect(progress['b24']!['due'], '2026-10-27');
    final smaller = createDailyPlan(
      catalog,
      Map.fromEntries(progress.entries.take(dailyWordBudget - 3)),
      8,
      '2026-10-28',
    );
    expect(smaller['newIds'], hasLength(3));
  });

  test('groups space retries, stop after three attempts and stay finite', () {
    final queue = StudyGroup(['a', 'b', 'c', 'd', 'e', 'f']);
    final plan = <String, dynamic>{'done': <String>[]};
    final now = DateTime(2026, 10, 28);
    expect(queue.pending, hasLength(5));
    for (var round = 0; round < 3; round++) {
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        expect(queue.next(now, plan, {}), id);
        queue.record(id);
      }
    }
    expect(queue.next(now, plan, {}), isNull);
    final single = StudyGroup(['only']);
    single.record('only');
    expect(single.next(now, plan, {}), isNull);
  });

  group('persisted practice', () {
    late Directory directory;
    late StudyStore store;
    late String id;
    var now = DateTime(2026, 10, 28, 10);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ngsl_memory_');
      now = DateTime(2026, 10, 28, 10);
      store = StudyStore(directory, clock: () => now);
      id = await store.createLearner('我', false);
      await store.ensurePlan(id, words);
    });
    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'exposure survives restart without a fabricated review or completed task',
      () async {
        await store.introduce(id, 'w0', store.today);
        await store.markKnown(id, ['w1'], true, words: words);
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        expect(loaded.progress(id)['w0']['reviews'], isNull);
        expect(loaded.progress(id)['w0']['memory'], isNull);
        expect(loaded.plan(id)!['done'], isEmpty);
        expect(loaded.plan(id)!['wordIds'], contains('w0'));
        expect(loaded.practiceLog(id).single['kind'], 'exposure');
        await expectLater(
          loaded.review(id, 'w0', Recall.good, store.today),
          throwsA(isA<ContentException>()),
        );
        now = now.add(const Duration(minutes: 2));
        await loaded.review(id, 'w0', Recall.good, store.today);
        expect(loaded.plan(id)!['done'], contains('w0'));
        expect(loaded.progress(id)['w0']['due'], '2026-10-29');
        loaded.dispose();
      },
    );

    test(
      'hinted success stays unfinished and repeated failures impose a longer pause',
      () async {
        await store.review(id, 'w0', Recall.good, store.today, hinted: true);
        expect(store.plan(id)!['done'], isEmpty);
        expect(store.practiceLog(id).single['independent'], false);
        for (var i = 0; i < 2; i++) {
          now = now.add(const Duration(minutes: 2));
          await store.review(id, 'w0', Recall.again, store.today);
        }
        expect(
          practiceReadyAt(store.plan(id)!, 'w0'),
          now.add(const Duration(minutes: 10)),
        );
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        await expectLater(
          loaded.review(id, 'w0', Recall.good, store.today),
          throwsA(isA<ContentException>()),
        );
        expect(loaded.practiceLog(id), hasLength(3));
        loaded.dispose();
      },
    );

    test(
      'switching learners during queued writes preserves the originating learner',
      () async {
        final child = await store.createLearner('孩子', true);
        final work = store.introduce(id, 'w0', store.today);
        await store.switchLearner(child);
        await work;
        now = now.add(const Duration(minutes: 2));
        await store.review(id, 'w0', Recall.good, store.today);
        expect(store.progress(child), isEmpty);
        expect(store.practiceLog(child), isEmpty);
        expect(store.practiceLog(id), hasLength(2));
        expect(store.activeId, child);
      },
    );

    test(
      'new directions have independent evidence and duplicate ratings are ignored',
      () async {
        await store.review(id, 'w0', Recall.good, store.today);
        final meaning = skillProgress(
          Map<String, dynamic>.from(store.progress(id)['w0']),
          MemorySkill.meaning,
        );
        now = now.add(const Duration(days: 1));
        await store.ensurePlan(id, words);
        expect(
          plannedMemorySkill(
            store.plan(id)!,
            Map<String, dynamic>.from(store.progress(id)['w0']),
            'w0',
            store.today,
          ),
          MemorySkill.listening,
        );
        await store.review(
          id,
          'w0',
          Recall.good,
          store.today,
          skill: MemorySkill.listening,
        );
        await store.review(
          id,
          'w0',
          Recall.easy,
          store.today,
          skill: MemorySkill.listening,
        );
        final current = Map<String, dynamic>.from(store.progress(id)['w0']);
        expect(skillProgress(current, MemorySkill.meaning), meaning);
        expect(
          skillProgress(current, MemorySkill.listening)['delayedSuccesses'],
          0,
        );
        expect(store.practiceLog(id), hasLength(2));
      },
    );

    test(
      'midnight and a fresh daily plan cannot bypass a saved cooldown',
      () async {
        now = DateTime(2026, 10, 28, 23, 59, 50);
        await store.introduce(id, 'w0', store.today);
        now = DateTime(2026, 10, 29, 0, 0, 10);
        await store.ensurePlan(id, words);
        expect(store.plan(id)!['wordIds'], contains('w0'));
        await expectLater(
          store.review(id, 'w0', Recall.good, store.today),
          throwsA(isA<ContentException>()),
        );
        now = now.add(const Duration(minutes: 1));
        await store.review(id, 'w0', Recall.good, store.today);
        expect(store.plan(id)!['done'], contains('w0'));
        expect(store.progress(id)['w0'].containsKey('readyAt'), isFalse);
      },
    );

    test(
      'old snapshots load unchanged and retain schedules, plans, stories and preferences',
      () async {
        final file = File('${directory.path}/study.json');
        final legacy = jsonDecode(await file.readAsString());
        legacy['profiles'][id]['progress']['w0'] = {
          'status': 'learning',
          'interval': 14,
          'due': '2026-10-28',
          'lastSeen': '2026-10-14',
          'reviews': 4,
        };
        legacy['profiles'][id]['plans'][store.today].remove('practice');
        legacy['profiles'][id]['stories'].add({
          'id': 'legacy',
          'title': '保留的故事',
        });
        legacy['learners'][0]['accent'] = 'us';
        await file.writeAsString(jsonEncode(legacy));
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        expect(jsonDecode(await file.readAsString()), legacy);
        expect(loaded.progress(id)['w0']['interval'], 14);
        expect(loaded.active!.accent, 'us');
        expect(loaded.stories(id).single['title'], '保留的故事');
        await loaded.review(id, 'w0', Recall.good, store.today);
        expect(
          loaded.progress(id)['w0']['memory']['meaning']['interval'],
          greaterThan(14),
        );
        expect(
          loaded.progress(id)['w0']['memory'].containsKey('listening'),
          false,
        );
        expect(loaded.progress(id)['w0']['reviews'], 5);
        loaded.dispose();
      },
    );

    test(
      'story self-report is isolated and cannot advance vocabulary schedules',
      () async {
        await store.review(id, 'w0', Recall.good, store.today);
        final before = store.progress(id);
        await store.saveStory(id, store.today, {
          'title': '故事',
          'words': [
            {'id': 'w0'},
          ],
        });
        final story = store.stories(id).single;
        final child = await store.createLearner('孩子', true);
        await store.recordStoryRecall(id, story['id'], 'w0', Recall.again);
        await store.recordStoryRecall(id, story['id'], 'w0', Recall.good);
        expect(store.progress(id), before);
        expect(
          store.practiceLog(id).where((e) => e['kind'] == 'context'),
          hasLength(1),
        );
        expect(
          store.stories(id).single['practiceResults']['w0']['recall'],
          'again',
        );
        expect(store.practiceLog(child), isEmpty);
        expect(store.stories(child), isEmpty);
      },
    );
  });

  for (final child in [false, true]) {
    for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
      testWidgets(
        'same new-word and hinted-recall flow child=$child size=$size',
        (tester) async {
          final fixture = await MemoryUiFixture.create(
            tester,
            size: size,
            child: child,
          );
          await fixture.open(tester);
          expect(find.text('新词 · 先理解，再回忆'), findsOneWidget);
          expect(find.text('独立想起'), findsNothing);
          await tester.runAsync(() async {
            await tester.tap(find.text('学好了，稍后回忆'));
            await fixture.store.ensurePlan(fixture.id, words);
          });
          await tester.pumpAndSettle();
          expect(
            fixture.store.practiceLog(fixture.id).single['kind'],
            'exposure',
          );
          fixture.now = fixture.now.add(const Duration(minutes: 2));
          await fixture.open(tester);
          expect(find.text('认读 · 先回忆，再查看'), findsOneWidget);
          expect(find.text('词0'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('memory-hint-button')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('reveal-memory-answer')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '独立想起'))
                .onPressed,
            isNull,
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('提示后想起'));
            await fixture.store.ensurePlan(fixture.id, words);
          });
          await tester.pumpAndSettle();
          expect(fixture.store.plan(fixture.id)!['done'], isEmpty);
          expect(tester.takeException(), isNull);
          await fixture.close(tester);
        },
      );
    }
  }

  testWidgets(
    'listening prompt conceals spelling until reveal and plays the correct word',
    (tester) async {
      final fixture = await MemoryUiFixture.create(tester);
      await tester.runAsync(() => fixture.seed(MemorySkill.listening));
      final spoken = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (call) async {
            if (call.method == 'play' || call.method == 'playFile') {
              spoken.add(call.arguments['text']);
            }
            return null;
          });
      await fixture.open(tester);
      expect(find.text('word0'), findsNothing);
      expect(find.text('词0'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('listen-cue')));
      await tester.pumpAndSettle();
      expect(spoken, ['word0']);
      expect(find.text('word0'), findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  for (final correct in [true, false]) {
    testWidgets('spelling is checked before recording, correct=$correct', (
      tester,
    ) async {
      final fixture = await MemoryUiFixture.create(tester);
      await tester.runAsync(() => fixture.seed(MemorySkill.spelling));
      await fixture.open(tester);
      expect(find.text('word0'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('spelling-answer')),
        correct ? ' WORD0 ' : 'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('reveal-memory-answer')));
      await tester.pumpAndSettle();
      expect(find.text(correct ? '拼写正确' : '正确拼写：word0'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(correct ? '记录并继续' : '记下了，稍后再练'));
        await fixture.store.ensurePlan(fixture.id, words);
      });
      await tester.pumpAndSettle();
      final event = fixture.store.practiceLog(fixture.id).last;
      expect(event['skill'], 'spelling');
      expect(event['independent'], correct);
      expect(fixture.store.plan(fixture.id)!['done'].contains('w0'), correct);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }
}

class MemoryUiFixture {
  late Directory directory;
  late StudyStore store;
  late String id;
  DateTime now = DateTime(2026, 10, 28, 10);

  static Future<MemoryUiFixture> create(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    bool child = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousRenderer = Speech.synthesize;
    Speech.synthesize = (text, accent) async => '/tmp/ngsl-test-audio.wav';
    addTearDown(() => Speech.synthesize = previousRenderer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Speech.channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, null),
    );
    final fixture = MemoryUiFixture();
    await tester.runAsync(() async {
      fixture.directory = await Directory.systemTemp.createTemp(
        'ngsl_memory_ui_',
      );
      fixture.store = StudyStore(fixture.directory, clock: () => fixture.now);
      fixture.id = await fixture.store.createLearner('学习者', child);
      await fixture.store.configure(fixture.id, dailyNew: 1);
      await fixture.store.ensurePlan(fixture.id, words);
    });
    return fixture;
  }

  Future<void> seed(MemorySkill direction) async {
    for (var i = 0; i < direction.index; i++) {
      await store.review(id, 'w0', Recall.good, store.today);
      now = now.add(const Duration(days: 1));
      await store.ensurePlan(id, words);
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: appTheme(),
        home: ReviewPage(
          store: store,
          learner: store.learners.firstWhere((l) => l.id == id),
          words: words.take(1).toList(),
          date: store.today,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}
