// Socket-free checks for restricted build environments. The Flutter suite also
// contains tablet widget tests and should run on a normal developer machine.
import 'dart:convert';
import 'dart:io';
import 'package:ngsl_go/core/ai/response_stream.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<void> Function() fn) async {
  var rejected = false;
  try {
    await fn();
  } on ContentException {
    rejected = true;
  }
  check(rejected, 'Expected invalid content to be rejected');
}

Map<String, dynamic> story() => {
  'title': 'A small invitation',
  'paragraphs': [
    {
      'english':
          'Mia decided to accept the invitation. She had never visited the small garden behind her school before. On Saturday morning, she walked there with her brother and met a friendly teacher. They planted flowers together and shared a simple lunch under a tree. When it started to rain, everyone moved inside and drew pictures of the garden. Mia was happy that she had tried something new with her friends.',
      'chinese':
          '米娅决定接受邀请。她以前从未去过学校后面的小花园。周六早上，她和弟弟一起走到那里，遇见了一位友善的老师。他们一起种花，在树下分享了一顿简单的午餐。开始下雨时，大家走进屋里，画起了花园。米娅很高兴自己和朋友们尝试了新事情。',
    },
  ],
  'words': [
    {
      'id': 'accept',
      'surface': 'accept',
      'chinese': '接受',
      'english': 'agree to receive something',
      'ukIpa': '/əkˈsept/',
      'usIpa': '/əkˈsept/',
      'collocations': [
        {'english': 'accept an invitation', 'chinese': '接受邀请'},
        {'english': 'accept an offer', 'chinese': '接受提议'},
      ],
      'exampleEnglish': 'I accept your offer.',
      'exampleChinese': '我接受你的提议。',
      'exercise': {
        'prompt': 'Mia decided to ___ the invitation.',
        'answer': 'accept',
        'chinese': '米娅决定接受邀请。',
      },
    },
  ],
  'speakingPrompt': '说一说你会接受什么邀请。',
};

Future<void> main() async {
  var count = 0;
  Future<void> test(String name, Future<void> Function() body) async {
    await body();
    count++;
    stdout.writeln('PASS $name');
  }

  final words = List.generate(
    12,
    (i) => Vocabulary(
      'w$i',
      'word$i',
      i + 1,
      'noun',
      '词$i',
      'a word',
      '/wɜːd/',
      ['word$i'],
      {},
    ),
  );
  const target = Vocabulary(
    'accept',
    'accept',
    561,
    'verb',
    '接受',
    'agree to receive something',
    '/əkˈsept/',
    ['accept', 'accepted', 'accepting', 'accepts'],
    {},
  );
  var now = DateTime(2026, 10, 27, 10);
  final dir = await Directory.systemTemp.createTemp('ngsl_core_');
  final store = StudyStore(dir, clock: () => now);
  try {
    await store.load();
    final adult = await store.createLearner('爸爸', false);
    await test(
      'skip known words and immediately refill the unstarted plan',
      () async {
        await store.ensurePlan(adult, words);
        await store.markKnown(adult, ['w0', 'w1'], true, words: words);
        check(
          jsonEncode(store.plan(adult)!['wordIds']) ==
              jsonEncode(['w2', 'w3', 'w4', 'w5', 'w6']),
          'Plan did not refill',
        );
      },
    );
    await test('duplicate ratings cannot advance a schedule twice', () async {
      await store.review(adult, 'w2', Recall.good, store.today);
      await store.review(adult, 'w2', Recall.easy, store.today);
      check(
        store.progress(adult)['w2']['reviews'] == 1 &&
            store.progress(adult)['w2']['interval'] == 1,
        'Duplicate rating changed interval',
      );
    });
    await test(
      'known marking is idempotent and restoring preserves the old schedule',
      () async {
        final original = jsonEncode(store.progress(adult)['w2']);
        await store.markKnown(adult, ['w2'], true);
        await store.markKnown(adult, ['w2'], true);
        await store.markKnown(adult, ['w2'], false);
        check(
          jsonEncode(store.progress(adult)['w2']) == original,
          'Restoration changed progress',
        );
      },
    );
    final child = await store.createLearner('小雨', true);
    await test('learners have isolated progress and plans', () async {
      await store.ensurePlan(child, words);
      check(store.progress(child).isEmpty, 'Progress leaked to child');
      check(
        store.plan(child)!['wordIds'].first == 'w0',
        'Child received parent plan',
      );
    });
    await test(
      'story completion after learner switch cannot leak stories or examples',
      () async {
        await store.saveStory(adult, store.today, {
          'title': 'Adult story',
          'paragraphs': [],
          'words': [
            {'id': 'w0', 'exampleEnglish': 'Adult context'},
          ],
        });
        check(
          store.activeId == child && store.stories(child).isEmpty,
          'Story saved into active learner',
        );
        check(
          store.content(child, words[0]).isEmpty &&
              store.content(adult, words[0])['exampleEnglish'] ==
                  'Adult context',
          'Example leaked',
        );
      },
    );
    await test('concurrent profile writes preserve all data', () async {
      await Future.wait([
        store.markKnown(child, ['w0'], true),
        store.markKnown(child, ['w1'], true),
        store.configure(child, accent: 'us'),
      ]);
      check(
        store.progress(child).length == 2 && store.active!.accent == 'us',
        'Lost a concurrent write',
      );
    });
    await test(
      'restart restores the active learner and independent progress',
      () async {
        final loaded = StudyStore(dir, clock: () => now);
        await loaded.load();
        check(
          loaded.activeId == child &&
              loaded.progress(adult)['w2']['reviews'] == 1 &&
              loaded.progress(child).length == 2,
          'Restart lost state',
        );
        loaded.dispose();
      },
    );
    await test('due reviews precede new words on the next day', () async {
      now = DateTime(2026, 10, 28, 1);
      await store.ensurePlan(adult, words);
      check(
        store.plan(adult)!['wordIds'].first == 'w2',
        'Due review not prioritized',
      );
    });
    await test(
      'duplicate profile names fail without poisoning later writes',
      () async {
        await rejects(() async {
          await store.createLearner('爸爸', false);
        });
        await store.configure(child, dailyNew: 0);
        check(store.active!.dailyNew == 0, 'Write queue poisoned');
      },
    );
    await test(
      'a corrupt snapshot recovers the previous successful snapshot',
      () async {
        await File('${dir.path}/study.json').writeAsString('{bad');
        final loaded = StudyStore(dir);
        await loaded.load();
        check(
          loaded.recoveryNotice != null &&
              loaded.progress(adult)['w2']['reviews'] == 1,
          'Recovery failed',
        );
        loaded.dispose();
      },
    );
    await test(
      'all corrupt files fail visibly without resetting learning data',
      () async {
        await File('${dir.path}/study.json.bak').writeAsString('bad');
        final loaded = StudyStore(dir);
        await rejects(loaded.load);
        check(
          await File('${dir.path}/study.json').readAsString() == '{bad',
          'Corrupt file was erased',
        );
        loaded.dispose();
      },
    );
    await test('complete bilingual target-aligned story passes', () async {
      validateStory(story(), [target]);
    });
    await test(
      'absent target forms and cloze sentences are rejected',
      () async {
        final bad = story();
        bad['words'][0]['surface'] = 'accepted';
        await rejects(() async {
          validateStory(bad, [target]);
        });
        final wrong = story();
        wrong['words'][0]['exercise']['prompt'] = 'They ___ my plan.';
        await rejects(() async {
          validateStory(wrong, [target]);
        });
      },
    );
    await test('SSE decodes split UTF-8 and refuses truncated streams', () async {
      final payload = jsonEncode(story());
      final data = utf8.encode(
        'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': payload})}\n\ndata: ${jsonEncode({
          'type': 'response.completed',
          'response': {'status': 'completed'},
        })}\n\n',
      );
      final chunks = [
        for (var i = 0; i < data.length; i += 7)
          data.sublist(i, (i + 7).clamp(0, data.length)),
      ];
      check(
        await readResponseStream(Stream.fromIterable(chunks)) == payload,
        'SSE corrupted UTF-8',
      );
      await rejects(() async {
        await readResponseStream(
          Stream.value(
            utf8.encode(
              'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': payload})}\n\n',
            ),
          ),
        );
      });
    });
    await test(
      'bundled NGSL has exactly 2809 unique ranked bilingual entries',
      () async {
        final json = jsonDecode(
          await File('assets/content/ngsl.json').readAsString(),
        );
        final rows = json['words'] as List;
        check(
          rows.length == 2809 &&
              rows.map((w) => w['id']).toSet().length == 2809,
          'Wrong library size',
        );
        check(
          rows.every(
            (w) =>
                (w['chinese'] as String).isNotEmpty &&
                (w['english'] as String).isNotEmpty,
          ),
          'Missing definitions',
        );
      },
    );
    stdout.writeln('$count core checks passed.');
  } finally {
    store.dispose();
    await dir.delete(recursive: true);
  }
}
