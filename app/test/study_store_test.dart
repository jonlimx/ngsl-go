import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';

final words = List.generate(
  12,
  (i) => Vocabulary('w$i', 'word$i', i + 1, 'noun', '词$i', 'a word', '/wɜːd/', [
    'word$i',
  ], {}),
);

void main() {
  late Directory directory;
  late StudyStore store;
  var now = DateTime(2026, 10, 27, 10);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ngsl_store_');
    now = DateTime(2026, 10, 27, 10);
    store = StudyStore(directory, clock: () => now);
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'learners isolate known words, plans, reviews and preferences across restart',
    () async {
      final adult = await store.createLearner('爸爸', false);
      await store.markKnown(adult, ['w0', 'w1'], true, words: words);
      await store.configure(adult, dailyNew: 3, accent: 'us');
      await store.ensurePlan(adult, words);
      await store.review(adult, 'w2', Recall.good, store.today);
      final child = await store.createLearner('小雨', true);
      await store.ensurePlan(child, words);
      expect(store.progress(child), isEmpty);
      expect(store.plan(child)!['wordIds'], ['w0', 'w1', 'w2', 'w3', 'w4']);
      expect(store.progress(adult)['w2']['reviews'], 1);
      final loaded = StudyStore(directory, clock: () => now);
      await loaded.load();
      expect(loaded.activeId, child);
      await loaded.switchLearner(adult);
      expect(loaded.active!.accent, 'us');
      expect(loaded.active!.dailyNew, 3);
      expect(loaded.progress(adult)['w0']['status'], 'known');
      expect(loaded.plan(adult)!['done'], ['w2']);
      loaded.dispose();
    },
  );

  test('filtering known words immediately refills an unstarted plan', () async {
    final id = await store.createLearner('我', false);
    await store.ensurePlan(id, words);
    await store.markKnown(
      id,
      ['w0', 'w1', 'w2', 'w3', 'w4'],
      true,
      words: words,
    );
    expect(store.plan(id)!['wordIds'], ['w5', 'w6', 'w7', 'w8', 'w9']);
  });

  test(
    'screening saves exceptions, resumes after restart and isolates learners',
    () async {
      final adult = await store.createLearner('爸爸', false);
      await store.ensurePlan(adult, words);
      await store.review(adult, 'w0', Recall.good, store.today);
      final schedule = store.progress(adult)['w0'];
      await store.markKnown(adult, ['w1'], true);
      final child = await store.createLearner('孩子', true);
      final batch = await store.screenWords(
        adult,
        words,
        words.map((w) => w.id),
        keepLearning: {'w2'},
      );
      expect(batch.count, 10);
      expect(batch.keptCount, 1);
      expect(store.activeId, child);
      expect(store.progress(child), isEmpty);
      expect(store.progress(adult)['w0'], schedule);
      expect(store.plan(adult)!['done'], ['w0']);
      final loaded = StudyStore(directory, clock: () => now);
      await loaded.load();
      expect(loaded.progress(adult)['w2']['status'], 'new');
      expect(loaded.progress(adult)['w3']['status'], 'known');
      expect(screeningCandidates(words, loaded.progress(adult)), isEmpty);
      expect(screeningCandidates(words, loaded.progress(child)), hasLength(12));
      loaded.dispose();
    },
  );

  test(
    'screening refills an unstarted plan and undo restores the exact progress',
    () async {
      final id = await store.createLearner('我', false);
      await store.ensurePlan(id, words);
      final originalPlan = store.plan(id);
      final batch = await store.screenWords(
        id,
        words,
        words.take(5).map((w) => w.id),
        keepLearning: {'w2'},
      );
      expect(store.plan(id)!['wordIds'], ['w2', 'w5', 'w6', 'w7', 'w8']);
      expect(screeningCandidates(words, store.progress(id)).first.id, 'w5');
      await store.undoScreening(batch, words);
      expect(store.progress(id), isEmpty);
      expect(store.plan(id), originalPlan);
    },
  );

  test('undo screening preserves later reviews and edits', () async {
    final id = await store.createLearner('我', false);
    final batch = await store.screenWords(
      id,
      words,
      ['w0', 'w1', 'w2'],
      keepLearning: {'w0'},
    );
    await store.review(id, 'w0', Recall.good, store.today);
    final reviewed = store.progress(id)['w0'];
    await store.markKnown(id, ['w1'], false, words: words);
    final restored = store.progress(id)['w1'];
    await store.undoScreening(batch, words);
    expect(store.progress(id)['w0'], reviewed);
    expect(store.progress(id)['w1'], restored);
    expect(store.progress(id).containsKey('w2'), isFalse);
    expect(store.plan(id)!['done'], ['w0']);
  });

  test('screening supports all-unfamiliar and final partial batches', () async {
    final catalog = List.generate(
      205,
      (i) =>
          Vocabulary('b$i', 'batch$i', i + 1, 'noun', '词', 'word', '', [], {}),
    );
    final id = await store.createLearner('我', false);
    final first = screeningCandidates(
      catalog.reversed.toList(),
      {},
    ).take(100).toList();
    expect(first.first.rank, 1);
    await store.screenWords(
      id,
      catalog,
      first.map((w) => w.id),
      keepLearning: first.map((w) => w.id).toSet(),
    );
    expect(
      store.progress(id).values.every((p) => p['status'] == 'new'),
      isTrue,
    );
    final second = screeningCandidates(catalog, store.progress(id)).take(100);
    expect(second.first.rank, 101);
    await store.screenWords(id, catalog, second.map((w) => w.id));
    expect(screeningCandidates(catalog, store.progress(id)), hasLength(5));
  });

  test(
    'repeated known marking is idempotent and restores the previous schedule',
    () async {
      final id = await store.createLearner('我', false);
      await store.ensurePlan(id, words);
      await store.review(id, 'w0', Recall.good, store.today);
      final original = store.progress(id)['w0'];
      await store.markKnown(id, ['w0'], true);
      await store.markKnown(id, ['w0'], true);
      await store.markKnown(id, ['w0'], false);
      expect(store.progress(id)['w0'], original);
    },
  );

  test(
    'daily plans stay stable and duplicate ratings do not advance intervals',
    () async {
      final id = await store.createLearner('我', false);
      await store.ensurePlan(id, words);
      final ids = store.plan(id)!['wordIds'];
      await store.review(id, 'w0', Recall.good, store.today);
      await store.review(id, 'w0', Recall.easy, store.today);
      await store.configure(id, dailyNew: 10);
      await store.ensurePlan(id, words);
      expect(store.plan(id)!['wordIds'], ids);
      expect(store.progress(id)['w0']['reviews'], 1);
      expect(store.progress(id)['w0']['interval'], 1);
      now = DateTime(2026, 10, 28, 1);
      await store.ensurePlan(id, words);
      expect(store.plan(id)!['wordIds'].first, 'w0');
    },
  );

  test(
    'async story completion saves into its originating learner after switch',
    () async {
      final adult = await store.createLearner('爸爸', false);
      final child = await store.createLearner('小雨', true);
      await store.saveStory(adult, store.today, {
        'title': 'Adult story',
        'paragraphs': [],
        'words': [
          {'id': 'w0', 'exampleEnglish': 'adult context'},
        ],
      });
      expect(store.activeId, child);
      expect(store.stories(child), isEmpty);
      expect(store.content(child, words[0]), isEmpty);
      expect(store.stories(adult).single['title'], 'Adult story');
      expect(store.content(adult, words[0])['exampleEnglish'], 'adult context');
    },
  );

  test('concurrent writes are serialized without dropping progress', () async {
    final id = await store.createLearner('我', false);
    await Future.wait([
      store.markKnown(id, ['w0'], true),
      store.markKnown(id, ['w1'], true),
      store.configure(id, accent: 'us'),
    ]);
    expect(store.progress(id).length, 2);
    final loaded = StudyStore(directory);
    await loaded.load();
    expect(loaded.progress(id).length, 2);
    expect(loaded.active!.accent, 'us');
    loaded.dispose();
  });

  test(
    'corrupt current snapshot recovers previous snapshot without clearing files',
    () async {
      final id = await store.createLearner('我', false);
      await store.markKnown(id, ['w0'], true);
      await store.configure(id, accent: 'us');
      await File('${directory.path}/study.json').writeAsString('{broken');
      final loaded = StudyStore(directory);
      await loaded.load();
      expect(loaded.progress(id)['w0']['status'], 'known');
      expect(loaded.recoveryNotice, isNotNull);
      loaded.dispose();
    },
  );

  test(
    'all corrupt snapshots fail visibly instead of silently erasing learning data',
    () async {
      await File('${directory.path}/study.json').writeAsString('bad');
      expect(store.load(), throwsA(isA<ContentException>()));
      expect(await File('${directory.path}/study.json').readAsString(), 'bad');
    },
  );

  test('due reviews precede fresh words and known words are excluded', () {
    final plan = createDailyPlan(
      words,
      {
        'w0': {'status': 'known'},
        'w1': {'status': 'learning', 'due': '2026-10-25'},
        'w2': {'status': 'learning', 'due': '2026-10-30'},
      },
      2,
      '2026-10-27',
    );
    expect(plan['wordIds'], ['w1', 'w3', 'w4']);
    expect(plan['newIds'], ['w3', 'w4']);
  });

  test(
    'a forgotten word stays unfinished until a later successful recall',
    () async {
      final id = await store.createLearner('我', false);
      await store.ensurePlan(id, words);
      await store.review(id, 'w0', Recall.again, store.today);
      expect(store.plan(id)!['done'], isNot(contains('w0')));
      expect(store.progress(id)['w0']['due'], store.today);
      now = now.add(const Duration(minutes: 2));
      await store.review(id, 'w0', Recall.good, store.today);
      expect(store.plan(id)!['done'], contains('w0'));
      expect(store.progress(id)['w0']['interval'], 1);
    },
  );

  test(
    'restoring an excluded new word makes it eligible for learning again',
    () async {
      final id = await store.createLearner('我', false);
      await store.markKnown(id, ['w0'], true, words: words);
      expect(store.plan(id)!['wordIds'], isNot(contains('w0')));
      await store.markKnown(id, ['w0'], false, words: words);
      expect(store.plan(id)!['wordIds'], contains('w0'));
    },
  );
}
