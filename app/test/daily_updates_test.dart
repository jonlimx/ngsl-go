import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/audio.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';
import 'memory_learning_test.dart' show MemoryUiFixture;
import 'study_store_test.dart' show words;

final catalog = List.generate(
  120,
  (i) => Vocabulary('u$i', 'update$i', i + 1, 'noun', '词$i', 'a word', '', [
    'update$i',
  ], {}),
);

void main() {
  group('daily updates', () {
    late Directory directory;
    late StudyStore store;
    late String id;
    var now = DateTime(2026, 10, 28, 10);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ngsl_daily_');
      now = DateTime(2026, 10, 28, 10);
      store = StudyStore(directory, clock: () => now);
      id = await store.createLearner('学习者', false);
      await store.ensurePlan(id, catalog);
    });
    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'increasing new words extends a started plan and preserves evidence across restart',
      () async {
        await store.review(id, 'u0', Recall.good, store.today);
        await store.introduce(id, 'u1', store.today);
        final previousProgress = jsonEncode(store.progress(id));
        final practice = jsonEncode(store.plan(id)!['practice']['u1']);
        await store.configure(id, dailyNew: 60, words: catalog);
        expect(store.plan(id)!['newIds'], hasLength(60));
        expect(store.plan(id)!['wordIds'].toSet(), hasLength(60));
        expect(store.plan(id)!['done'], ['u0']);
        expect(jsonEncode(store.progress(id)), previousProgress);
        expect(jsonEncode(store.plan(id)!['practice']['u1']), practice);
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        expect(loaded.plan(id)!['newIds'], hasLength(60));
        expect(loaded.plan(id)!['done'], ['u0']);
        loaded.dispose();
      },
    );

    test(
      'reducing quota keeps todays task and uses new quota tomorrow',
      () async {
        await store.configure(id, dailyNew: 20, words: catalog);
        final plan = jsonEncode(store.plan(id));
        await store.configure(id, dailyNew: 3, words: catalog);
        expect(jsonEncode(store.plan(id)), plan);
        now = now.add(const Duration(days: 1));
        await store.ensurePlan(id, catalog);
        expect(store.plan(id)!['newIds'], hasLength(3));
      },
    );

    test(
      'extension uses captured learner without changing screening',
      () async {
        await store.markKnown(id, ['u6', 'u7'], true, words: catalog);
        final screened = jsonEncode(store.progress(id));
        final other = await store.createLearner('另一个', true);
        await store.ensurePlan(other, catalog);
        final otherBefore = jsonEncode(store.profile(other));
        await store.configure(id, dailyNew: 60, words: catalog);
        expect(store.plan(id)!['wordIds'], isNot(contains('u6')));
        expect(store.plan(id)!['wordIds'], isNot(contains('u7')));
        expect(
          store.plan(id)!['wordIds'].length,
          lessThanOrEqualTo(dailyWordBudget),
        );
        expect(jsonEncode(store.progress(id)), screened);
        expect(jsonEncode(store.profile(other)), otherBefore);
      },
    );

    test(
      'upgraded cards use bundled contextual examples while preserving saved story material',
      () async {
        await store.saveWordContent(id, 'u0', {
          'exampleEnglish': 'I like this word.',
          'exampleChinese': '我喜欢这个词。',
          'english': 'old definition',
          'chinese': '旧释义',
        });
        final oldCache = jsonEncode(store.profile(id)['wordContent']);
        final word = Vocabulary(
          'u0',
          'update0',
          1,
          'noun',
          '新释义',
          'new definition',
          '',
          [],
          {
            'offlineCardVersion': 'original-b1-b2-v1',
            'exampleEnglish':
                'Although the timetable had changed, the team checked the update carefully before deciding when to leave.',
            'exampleChinese': '虽然时间表变了，团队还是在决定出发时间前仔细核对了更新。',
            'collocations': [
              {'english': 'an update', 'chinese': '一次更新'},
              {'english': 'the latest update', 'chinese': '最新更新'},
            ],
          },
        );
        final content = store.content(id, word);
        expect(content['exampleEnglish'], word.content['exampleEnglish']);
        expect(content['english'], word.english);
        expect(content['chinese'], word.chinese);
        expect(jsonEncode(store.profile(id)['wordContent']), oldCache);
      },
    );

    test(
      'an explicit increase appends the selected quota even after a review-heavy plan is complete',
      () async {
        await store.configure(id, dailyNew: 60, words: catalog);
        for (final wordId in List<String>.from(store.plan(id)!['wordIds'])) {
          await store.review(id, wordId, Recall.good, store.today);
        }
        now = now.add(const Duration(days: 1));
        await store.ensurePlan(id, catalog);
        expect(store.plan(id)!['wordIds'], hasLength(80));
        expect(store.plan(id)!['newIds'], hasLength(20));
        for (final wordId in List<String>.from(store.plan(id)!['wordIds'])) {
          await store.review(id, wordId, Recall.good, store.today);
        }
        final progress = jsonEncode(store.progress(id));
        final done = List<String>.from(store.plan(id)!['done']);
        await store.configure(id, dailyNew: 60, words: catalog);
        expect(store.plan(id)!['newIds'], hasLength(60));
        expect(store.plan(id)!['wordIds'], hasLength(120));
        expect(store.plan(id)!['done'], done);
        expect(jsonEncode(store.progress(id)), progress);
      },
    );

    test(
      'forecast includes today and pauses at zero without calling it complete mastery',
      () async {
        await store.configure(id, dailyNew: 60, words: catalog);
        var forecast = learningForecast(
          catalog,
          store.progress(id),
          store.plan(id),
          60,
          store.today,
        );
        expect(forecast.days, 2);
        expect(forecast.finish, '2026-10-29');
        await store.review(id, 'u0', Recall.good, store.today);
        forecast = learningForecast(
          catalog,
          store.progress(id),
          store.plan(id),
          60,
          store.today,
        );
        expect(forecast.remaining, 119);
        expect(forecast.finish, '2026-10-29');
        expect(
          learningForecast(
            catalog,
            store.progress(id),
            store.plan(id),
            0,
            store.today,
          ).finish,
          isNull,
        );
        expect(learningForecast([], {}, null, 60, store.today).days, 0);
      },
    );

    test(
      'successful same-day repetition preserves schedule and completion and logs separately',
      () async {
        await store.review(id, 'u0', Recall.good, store.today);
        final progress = jsonEncode(store.progress(id));
        final plan = jsonEncode(store.plan(id));
        final other = await store.createLearner('另一个', true);
        await store.repeatToday(
          id,
          'u0',
          Recall.good,
          skill: MemorySkill.listening,
          planDay: store.today,
        );
        expect(jsonEncode(store.progress(id)), progress);
        expect(jsonEncode(store.plan(id)), plan);
        expect(store.progress(other), isEmpty);
        expect(store.practiceLog(id).last['kind'], 'sameDayPractice');
        expect(store.practiceLog(id).last['delayed'], false);
      },
    );

    test(
      'failed repetition returns familiar word to learning without erasing todays completion',
      () async {
        await store.markFamiliar(id, 'u0', true);
        final plan = jsonEncode(store.plan(id));
        await store.repeatToday(
          id,
          'u0',
          Recall.again,
          skill: MemorySkill.meaning,
          planDay: store.today,
        );
        expect(store.progress(id)['u0']['status'], 'learning');
        expect(store.progress(id)['u0']['due'], store.today);
        expect(jsonEncode(store.plan(id)), plan);
        await expectLater(
          store.repeatToday(
            id,
            'u0',
            Recall.good,
            skill: MemorySkill.meaning,
            planDay: store.today,
          ),
          throwsA(isA<ContentException>()),
        );
        now = now.add(const Duration(minutes: 2));
        await store.repeatToday(
          id,
          'u0',
          Recall.good,
          skill: MemorySkill.meaning,
          planDay: store.today,
        );
        expect(store.plan(id)!['done'], contains('u0'));
        expect(store.practiceLog(id).last['independent'], true);
      },
    );

    test(
      'repetition rejects unfinished words and a previous-day route',
      () async {
        await expectLater(
          store.repeatToday(
            id,
            'u0',
            Recall.good,
            skill: MemorySkill.meaning,
            planDay: store.today,
          ),
          throwsA(isA<ContentException>()),
        );
        await store.review(id, 'u0', Recall.good, store.today);
        final day = store.today;
        now = now.add(const Duration(days: 1));
        await expectLater(
          store.repeatToday(
            id,
            'u0',
            Recall.good,
            skill: MemorySkill.meaning,
            planDay: day,
          ),
          throwsA(isA<ContentException>()),
        );
      },
    );
  });

  testWidgets(
    'completed words can be practised again instead of showing an empty session',
    (tester) async {
      final fixture = await MemoryUiFixture.create(
        tester,
        child: false,
        size: const Size(1280, 800),
      );
      await tester.runAsync(
        () => fixture.store.review(
          fixture.id,
          'w0',
          Recall.good,
          fixture.store.today,
        ),
      );
      final before = jsonEncode(fixture.store.plan(fixture.id));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: ReviewPage(
            store: fixture.store,
            learner: fixture.store.active!,
            words: [
              const Vocabulary('w0', 'word0', 1, 'noun', '词0', 'a word', '', [
                'word0',
              ], {}),
            ],
            date: fixture.store.today,
            repeat: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('再练今日单词'), findsOneWidget);
      expect(find.byKey(const ValueKey('listen-cue')), findsOneWidget);
      expect(jsonEncode(fixture.store.plan(fixture.id)), before);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'speech settings show bundled Kokoro and expose preparation without system voices',
    (tester) async {
      final fixture = await MemoryUiFixture.create(
        tester,
        child: false,
        size: const Size(1280, 800),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (call) async {
            if (call.method == 'voiceStatus') {
              return {
                'ready': true,
                'bundled': true,
                'engine': 'Kokoro',
                'initializing': false,
                'engineCount': 1,
                'english': 2,
                'uk': 0,
                'us': 2,
              };
            }
            if (call.method == 'installVoices') return '已打开文字转语音设置。';
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SettingsPanel(
              store: fixture.store,
              learner: fixture.store.active!,
              words: catalog,
              onProfiles: () {},
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('voice-status')),
        450,
      );
      expect(find.textContaining('Kokoro 离线模型已准备'), findsOneWidget);
      expect(find.textContaining('英音 Emma / 美音 Heart'), findsOneWidget);
      expect(find.text('准备离线语音'), findsOneWidget);
      expect(find.text('检查 Kokoro 模型'), findsOneWidget);
      await tester.ensureVisible(find.text('检查 Kokoro 模型'));
      await tester.tap(find.text('检查 Kokoro 模型'));
      await tester.pumpAndSettle();
      expect(find.text('检查完成：离线模型已就绪，可以试听。'), findsOneWidget);
      final generated = Completer<String>();
      final originalSynthesize = Speech.synthesize;
      Speech.synthesize = (_, _) => generated.future;
      addTearDown(() => Speech.synthesize = originalSynthesize);
      await tester.ensureVisible(find.text('试听英语例句'));
      await tester.tap(find.text('试听英语例句'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('正在准备试听…'), findsOneWidget);
      expect(find.textContaining('正在加载离线模型并生成语音'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '正在准备试听…')).onPressed, isNull);
      generated.complete('/tmp/preview.wav');
      await tester.pumpAndSettle();
      expect(find.text('试听已开始播放。'), findsOneWidget);
      expect(find.text('打开系统语音设置'), findsNothing);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'changing the quota updates todays work and the forecast immediately',
    (tester) async {
      final fixture = await MemoryUiFixture.create(tester);
      final learner = fixture.store.active!;
      final fullCatalog = [words.first, ...catalog.skip(1)];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SettingsPanel(
              store: fixture.store,
              learner: learner,
              words: fullCatalog,
              onProfiles: () {},
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('还有 120 个新词'), findsOneWidget);
      final field = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      await tester.runAsync(() async {
        await fixture.store.createLearner('另一个', true);
        field.onChanged!(60);
        await fixture.store.ensurePlan(fixture.id, fullCatalog);
      });
      await tester.pumpAndSettle();
      expect(fixture.store.plan(fixture.id)!['wordIds'], hasLength(60));
      expect(find.textContaining('约 2 天，预计 2026-10-29'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'Kokoro preparation errors become actionable messages and missing packs are rejected',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (call) async {
            if (call.method == 'voiceStatus') {
              throw PlatformException(code: 'NO_ENGINE', message: '请选择可用语音引擎。');
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(Speech.channel, null),
      );
      await expectLater(Speech.voiceStatus(), throwsA(isA<ContentException>()));
      await expectLater(
        Speech.prepareVoices(),
        throwsA(isA<ContentException>()),
      );
    },
  );
}
