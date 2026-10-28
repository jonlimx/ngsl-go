import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/audio.dart';
import 'package:ngsl_go/store.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/screening.dart';
import 'study_store_test.dart' show words;

void main() {
  testWidgets(
    'tablet onboarding offers separate learner profiles without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(Speech.channel, null),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ngsl_ui_'),
      ))!;
      final store = StudyStore(dir);
      await tester.pumpWidget(VocabularyApp(store: store, words: words));
      expect(find.text('创建学习者'), findsOneWidget);
      await tester.tap(find.text('创建学习者'));
      await tester.pumpAndSettle();
      expect(find.text('成人'), findsOneWidget);
      expect(find.text('儿童'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );

  for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('tablet navigation, word cards and learner identity at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(Speech.channel, null),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ngsl_ui_'),
      ))!;
      late StudyStore store;
      await tester.runAsync(() async {
        store = StudyStore(dir);
        await store.load();
        final id = await store.createLearner('爸爸', false);
        await store.ensurePlan(id, words);
      });
      await tester.pumpWidget(VocabularyApp(store: store, words: words));
      await tester.pumpAndSettle();
      await tester.tap(find.text(size.width >= 900 ? '词库与筛选' : '词库'));
      await tester.pumpAndSettle();
      expect(find.text('选择本页'), findsOneWidget);
      expect(find.text('快速筛词 · 每批 100 词'), findsOneWidget);
      expect(find.text('爸爸'), findsOneWidget);
      expect(find.text('word0'), findsOneWidget);
      await tester.tap(find.text('word0'));
      await tester.pumpAndSettle();
      expect(find.text('爸爸 · 词卡'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text(size.width >= 900 ? '我的故事' : '故事'));
      await tester.pumpAndSettle();
      expect(find.text('还没有故事'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }

  for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('quick screening browses, saves, undoes and resumes at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ngsl_screen_ui_'),
      ))!;
      final store = StudyStore(dir);
      final catalog = List.generate(
        105,
        (i) => Vocabulary(
          'q$i',
          'quick$i',
          i + 1,
          'noun',
          '中文$i',
          'word',
          '',
          [],
          {},
        ),
      );
      late String id;
      await tester.runAsync(() async {
        id = await store.createLearner('爸爸', false);
      });
      Widget app() => MaterialApp(
        theme: appTheme(),
        home: ScreeningPage(
          store: store,
          learner: store.active!,
          words: catalog,
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      FilledButton submit() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '跳过 99 词，保留 1 词 · 下一批'),
      );
      await tester.tap(find.byKey(const ValueKey('screen-q0')));
      await tester.pump();
      expect(submit().onPressed, isNull);
      await tester.tap(find.text('显示释义'));
      await tester.pumpAndSettle();
      expect(find.text('中文0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('screen-q99')),
        450,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('screening-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      // The last tile may be built in the cache before reaching the bottom.
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('screening-grid')),
      );
      grid.controller!.jumpTo(grid.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(submit().onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('跳过 99 词，保留 1 词 · 下一批'));
        await store.ensurePlan(id, catalog);
      });
      await tester.pumpAndSettle();
      expect(store.progress(id)['q0']['status'], 'new');
      expect(store.progress(id)['q99']['status'], 'known');
      expect(find.text('quick100'), findsOneWidget);
      expect(find.textContaining('还有 5 词未筛'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('撤销上一批'));
        await store.ensurePlan(id, catalog);
      });
      await tester.pumpAndSettle();
      expect(store.progress(id), isEmpty);
      expect(find.text('quick0'), findsOneWidget);
      // Keep an entire batch, then reopen: exceptions must not be screened again.
      await tester.tap(find.text('本批都不熟'));
      grid.controller!.jumpTo(grid.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('跳过 0 词，保留 100 词 · 下一批'));
        await store.ensurePlan(id, catalog);
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('quick100'), findsOneWidget);
      expect(find.text('quick0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    });
  }
}
