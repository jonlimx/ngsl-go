import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/audio.dart';
import 'package:ngsl_go/main.dart';
import 'memory_learning_test.dart' show MemoryUiFixture;
import 'vocabulary_features_test.dart' show bundledWords;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'common definitions, idioms and meaning-specific forms work offline',
    () async {
      final words = await bundledWords();
      expect(words, hasLength(2809));
      expect(words.every((w) => w.senses.isNotEmpty), isTrue);
      final present = words.firstWhere((w) => w.word == 'present');
      expect(present.senses.map((s) => s.pos).toSet(), {'noun', 'adj', 'verb'});
      expect(present.phrases.map((p) => p.phrase), contains('at present'));
    for (final phrase in present.phrases) {
      expect(phrase.ukAudio, isNotNull);
      expect(phrase.usAudio, isNotNull);
      expect(await File(phrase.ukAudio!).exists(), isTrue);
      expect(await File(phrase.usAudio!).exists(), isTrue);
    }
      expect(present.matchesQuery(' AT PRESENT '), isTrue);
      expect(present.matchesQuery('出席'), isTrue);
      final noun = present.senses.firstWhere((s) => s.pos == 'noun');
      final verb = present.senses.firstWhere((s) => s.pos == 'verb');
      expect(noun.ukIpa, '/ˈprezənt/');
      expect(verb.ukIpa, '/prɪˈzent/');
      expect(noun.ukWordAudio, isNot(verb.ukWordAudio));
      for (final sense in present.senses) {
        for (final path in [
          sense.ukAudio,
          sense.usAudio,
          sense.ukWordAudio,
          sense.usWordAudio,
        ]) {
          expect(path, isNotNull);
          expect(await File(path!).exists(), isTrue);
        }
      }
      final lead = words.firstWhere((w) => w.word == 'lead');
      final metal = lead.senses.firstWhere((s) => s.id == 'metal');
      final clue = lead.senses.firstWhere((s) => s.id == 'clue');
      expect(metal.ukIpa, '/led/');
      expect(clue.ukIpa, '/liːd/');
      expect(metal.ukWordAudio, isNot(clue.ukWordAudio));
      final lie = words.firstWhere((w) => w.word == 'lie');
      final rest = lie.senses.firstWhere((s) => s.id == 'rest-or-position');
      expect(
        rest.inflections.firstWhere((f) => f['label'] == '过去分词')['forms'],
        ['lain'],
      );
      expect(lie.teachingForms, contains('lied'));
      expect(lie.teachingForms, isNot(contains('lain')));
    },
  );

  for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
    testWidgets('present card expands meanings and at present at $size', (
      tester,
    ) async {
      final fixture = await MemoryUiFixture.create(tester, size: size);
      final words = await tester.runAsync(bundledWords);
      final present = words!.firstWhere((w) => w.word == 'present');
      final before = fixture.store.progress(fixture.id);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: WordCard(
                word: present,
                content: present.content,
                store: fixture.store,
                learnerId: fixture.id,
                accent: 'uk',
                onError: (message) => fail(message),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('常见义项'), findsOneWidget);
      final verb = find.byKey(const ValueKey('sense-ngsl12:present-show'));
      await tester.ensureVisible(verb);
      await tester.tap(
        find.descendant(of: verb, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          present.senses.firstWhere((s) => s.id == 'show').exampleEnglish,
        ),
        findsOneWidget,
      );
      final phrase = find.byKey(
        const ValueKey('phrase-ngsl12:present-at present-目前；现在'),
      );
      await tester.ensureVisible(phrase);
      await tester.tap(
        find.descendant(of: phrase, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(present.phrases.first.exampleEnglish), findsOneWidget);
      expect(fixture.store.progress(fixture.id), before);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    });
  }

  group('Kokoro playback routing', () {
    final calls = <MethodCall>[];
    var token = 0;
    late Future<String> Function(String, String) original;
    setUp(() {
      calls.clear();
      original = Speech.synthesize;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, (call) async {
            calls.add(call);
            if (call.method == 'beginSpeech') return ++token;
            if (call.method == 'stop') ++token;
            return null;
          });
    });
    tearDown(() async {
      await Speech.stop();
      Speech.synthesize = original;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Speech.channel, null);
    });

    test('word assets play directly and sentences use local Kokoro', () async {
      Speech.synthesize = (text, accent) async {
        expect(text, 'A complete example.');
        expect(accent, 'us');
        return '/local/cache/example.wav';
      };
      await Speech.play('present', 'uk', asset: 'assets/audio/word.mp3');
      expect(calls.map((c) => c.method), ['play']);
      calls.clear();
      await Speech.play(' A complete example. ', 'us', speed: 0.85);
      expect(calls.map((c) => c.method), ['beginSpeech', 'playFile']);
      expect(calls.last.arguments['path'], '/local/cache/example.wav');
      expect(calls.last.arguments['token'], token);
      expect(calls.last.arguments['speed'], 0.85);
    });

    test('leaving a page prevents late generated audio from playing', () async {
      final started = Completer<void>();
      final generated = Completer<String>();
      Speech.synthesize = (_, _) {
        started.complete();
        return generated.future;
      };
      final playing = Speech.play(
        'A story that is still being generated.',
        'uk',
      );
      await started.future;
      await Speech.stop();
      generated.complete('/local/cache/late.wav');
      await playing;
      expect(calls.map((c) => c.method), ['beginSpeech', 'stop']);
    });

    test('a newer request wins when synthesis finishes out of order', () async {
      final started = Completer<void>();
      final older = Completer<String>();
      Speech.synthesize = (text, _) {
        if (text == 'First.') {
          started.complete();
          return older.future;
        }
        return Future.value('/local/cache/new.wav');
      };
      final first = Speech.play('First.', 'uk');
      await started.future;
      await Speech.play('Second.', 'us');
      older.complete('/local/cache/old.wav');
      await first;
      expect(
        calls
            .where((c) => c.method == 'playFile')
            .map((c) => c.arguments['path']),
        ['/local/cache/new.wav'],
      );
    });
  });
}
