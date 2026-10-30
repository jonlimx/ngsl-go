import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';
import 'memory_learning_test.dart' show MemoryUiFixture;
import 'study_store_test.dart' show words;

Future<List<Vocabulary>> bundledWords() async =>
    ((jsonDecode(
              await File('assets/content/ngsl.json').readAsString(),
            )['words'])
            as List)
        .map((row) => Vocabulary.fromJson(Map<String, dynamic>.from(row)))
        .toList();

void main() {
  test(
    'every offline example and pattern contains a form valid for its taught sense',
    () async {
      final catalog = await bundledWords();
      final errors = <String>[];
      for (final word in catalog) {
        final content = word.content;
        final texts = [
          content['exampleEnglish'] as String,
          for (final phrase in content['collocations'] as List)
            phrase['english'] as String,
        ];
        for (final text in texts) {
          if (!word.teachingForms.any(
            (form) => RegExp(
              '(?<![a-z])${RegExp.escape(form.toLowerCase())}(?![a-z])',
            ).hasMatch(text.toLowerCase()),
          )) {
            errors.add('${word.id}: $text');
          }
        }
      }
      expect(catalog, hasLength(2809));
      expect(errors, isEmpty);
    },
  );

  test(
    'story forms use the taught sense and exclude unrelated corpus forms',
    () async {
      final catalog = await bundledWords();
      final lie = catalog.firstWhere((w) => w.word == 'lie');
      expect(lie.teachingForms, contains('lied'));
      expect(lie.teachingForms, isNot(contains('lain')));
      final go = catalog.firstWhere((w) => w.word == 'go');
      expect(go.teachingForms, containsAll(['went', 'gone']));
      expect(go.teachingForms, isNot(contains('gonna')));
      expect(
        catalog.firstWhere((w) => w.word == 'found').teachingForms,
        contains('founded'),
      );
      expect(
        catalog.firstWhere((w) => w.word == 'bear').teachingForms,
        isNot(contains('bore')),
      );
      final ground = catalog.firstWhere((w) => w.word == 'ground');
      expect(ground.pos, 'noun');
      expect(ground.teachingForms, isNot(contains('grounded')));
      expect(
        catalog.firstWhere((w) => w.word == 'short').teachingForms,
        isNot(contains('shorted')),
      );
      expect(
        catalog.firstWhere((w) => w.word == 'software').english,
        'programs and instructions used by a computer',
      );
    },
  );

  group('word-card progress and screening', () {
    late Directory directory;
    late StudyStore store;
    late String id;
    var now = DateTime(2026, 10, 28, 10);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ngsl_words_');
      now = DateTime(2026, 10, 28, 10);
      store = StudyStore(directory, clock: () => now);
      id = await store.createLearner('爸爸', false);
      await store.ensurePlan(id, words);
    });
    tearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });

    test(
      'sixty new words are persisted and scheduled without the old twenty-word ceiling',
      () async {
        final catalog = List.generate(
          100,
          (i) => Vocabulary('n$i', 'new$i', i, 'noun', '词', 'word', '', [], {}),
        );
        await store.configure(id, dailyNew: 60);
        now = now.add(const Duration(days: 1));
        await store.ensurePlan(id, catalog);
        expect(store.learners.first.dailyNew, 60);
        expect(store.plan(id)!['newIds'], hasLength(60));
        await store.configure(id, dailyNew: 100);
        expect(store.learners.first.dailyNew, 60);
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        expect(loaded.learners.first.dailyNew, 60);
        loaded.dispose();
      },
    );

    test(
      'manual familiarity preserves evidence and returns as a low-frequency check',
      () async {
        await store.review(id, 'w0', Recall.good, store.today);
        final before = store.progress(id)['w0'];
        await store.markFamiliar(id, 'w0', true);
        final familiar = store.progress(id)['w0'];
        expect(familiar['memory'], before['memory']);
        expect(familiar['reviews'], before['reviews']);
        expect(store.plan(id)!['done'], contains('w0'));
        expect(familiar['due'], '2026-11-11');
        await store.markFamiliar(id, 'w0', true);
        expect(store.progress(id)['w0'], familiar);
        now = DateTime.parse(familiar['due']).add(const Duration(hours: 10));
        await store.ensurePlan(id, words);
        expect(store.plan(id)!['familiarIds'], contains('w0'));
        await store.review(id, 'w0', Recall.good, store.today);
        expect(store.progress(id)['w0']['status'], 'familiar');
        expect(
          store.progress(id)['w0']['due'].compareTo(store.today),
          greaterThan(0),
        );
      },
    );

    test('a failed familiar check resumes ordinary learning', () async {
      await store.markFamiliar(id, 'w0', true);
      now = DateTime(2026, 11, 11, 10);
      await store.ensurePlan(id, words);
      await store.review(id, 'w0', Recall.again, store.today);
      expect(store.progress(id)['w0']['status'], 'learning');
      expect(store.progress(id)['w0']['due'], store.today);
      expect(store.plan(id)!['done'], isNot(contains('w0')));
    });

    test(
      'manual resumption retains new evidence and reopens the word',
      () async {
        await store.review(id, 'w0', Recall.good, store.today);
        await store.markFamiliar(id, 'w0', true);
        final memory = store.progress(id)['w0']['memory'];
        await store.markFamiliar(id, 'w0', false);
        expect(store.progress(id)['w0']['status'], 'learning');
        expect(store.progress(id)['w0']['memory'], memory);
        expect(store.plan(id)!['done'], isNot(contains('w0')));
      },
    );

    test(
      'screening copy preserves donor, receiver learning, stories and settings',
      () async {
        await store.screenWords(
          id,
          words,
          words.map((w) => w.id),
          keepLearning: {'w0', 'w1'},
        );
        await store.review(id, 'w0', Recall.good, store.today);
        final donor = jsonEncode(store.progress(id));
        final target = await store.createLearner('孩子', true);
        await store.configure(target, dailyNew: 3, accent: 'us');
        await store.ensurePlan(target, words);
        await store.review(target, 'w0', Recall.good, store.today);
        final learned = store.progress(target)['w0'];
        await store.saveStory(target, store.today, {
          'title': '保留故事',
          'words': [],
        });
        final result = await store.copyScreening(id, target, words);
        expect(result.known, 10);
        expect(result.learning, 1);
        expect(result.skipped, 1);
        expect(jsonEncode(store.progress(id)), donor);
        expect(store.progress(target)['w0'], learned);
        expect(store.progress(target)['w1']['status'], 'new');
        expect(store.progress(target)['w2']['status'], 'known');
        expect(store.progress(target)['w2']['memory'], isNull);
        expect(store.stories(target).single['title'], '保留故事');
        expect(store.active!.accent, 'us');
        final repeated = await store.copyScreening(id, target, words);
        expect(repeated.known + repeated.learning, 0);
        expect(repeated.skipped, 12);
      },
    );

    test(
      'a completed 2809-word screening round survives update and copying',
      () async {
        final catalog = await bundledWords();
        for (var start = 0; start < catalog.length; start += 100) {
          final batch = catalog.skip(start).take(100).toList();
          await store.screenWords(
            id,
            catalog,
            batch.map((w) => w.id),
            keepLearning: batch
                .where((w) => w.rank % 7 == 0)
                .map((w) => w.id)
                .toSet(),
          );
        }
        final original = jsonEncode(store.progress(id));
        final originalPlan = store.plan(id);
        final loaded = StudyStore(directory, clock: () => now);
        await loaded.load();
        await loaded.configure(id, dailyNew: 60);
        await loaded.ensurePlan(id, catalog);
        expect(jsonEncode(loaded.progress(id)), original);
        expect(loaded.plan(id), originalPlan);
        expect(screeningCandidates(catalog, loaded.progress(id)), isEmpty);
        final target = await loaded.createLearner('接收者', true);
        final result = await loaded.copyScreening(id, target, catalog);
        expect(result.known + result.learning, 2809);
        expect(screeningCandidates(catalog, loaded.progress(target)), isEmpty);
        expect(jsonEncode(loaded.progress(id)), original);
        loaded.dispose();
      },
    );
  });

  for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets(
      'offline definitions, FCE forms and familiarity control at $size',
      (tester) async {
        final fixture = await MemoryUiFixture.create(tester, size: size);
        final catalog = (await tester.runAsync(bundledWords))!;
        final word = catalog.firstWhere((w) => w.word == 'happy');
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: WordCard(
                  word: word,
                  content: word.content,
                  accent: 'uk',
                  onError: (_) {},
                  store: fixture.store,
                  learnerId: fixture.id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('常见义项'), findsOneWidget);
        expect(find.text(word.senses.first.english), findsOneWidget);
        expect(find.text('补充搭配与例句'), findsNothing);
        await tester.runAsync(() async {
          await tester.tap(find.byKey(ValueKey('familiar-${word.id}')));
          await fixture.store.ensurePlan(fixture.id, words);
        });
        await tester.pumpAndSettle();
        expect(
          fixture.store.progress(fixture.id)[word.id]['status'],
          'familiar',
        );
        expect(find.text('恢复常规学习'), findsOneWidget);
        await tester.ensureVisible(find.byKey(ValueKey('fce-${word.id}')));
        await tester.tap(find.text('词形与用法'));
        await tester.pumpAndSettle();
        expect(find.text('happier'), findsOneWidget);
        expect(find.textContaining('happiness'), findsWidgets);
        await tester.ensureVisible(find.text('查看词形答案'));
        await tester.tap(find.text('查看词形答案'));
        await tester.pumpAndSettle();
        expect(find.text('答案：happiness'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      },
    );
  }

  testWidgets(
    'screening copy dialog and sixty-word setting use captured learner IDs',
    (tester) async {
      final fixture = await MemoryUiFixture.create(tester);
      final source = fixture.store.learners.single;
      late String target;
      await tester.runAsync(() async {
        await fixture.store.screenWords(
          fixture.id,
          words,
          words.map((w) => w.id),
          keepLearning: {'w1'},
        );
        target = await fixture.store.createLearner('接收者', true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SettingsPanel(
              store: fixture.store,
              learner: source,
              words: words,
              onProfiles: () {},
              onError: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final setting = tester.widget<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      expect(setting.items!.any((item) => item.value == 60), true);
      await tester.ensureVisible(find.byKey(const ValueKey('copy-screening')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('copy-screening')));
      });
      await tester.pumpAndSettle();
      expect(find.text('复制给'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('复制筛词结果'));
        await Future<void>.delayed(Duration.zero);
        await fixture.store.ensurePlan(target, words);
      });
      await tester.pumpAndSettle();
      expect(
        screeningCandidates(words, fixture.store.progress(target)),
        isEmpty,
      );
      expect(fixture.store.progress(target)['w1']['status'], 'new');
      expect(fixture.store.progress(target)['w0']['status'], 'known');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
