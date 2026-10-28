import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngsl_go/core/ai/response_stream.dart';
import 'package:ngsl_go/models.dart';

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
Map<String, dynamic> fixture() => {
  'title': 'A small invitation',
  'paragraphs': [
    {
      'english':
          'Mia decided to accept the invitation. She had never visited the small garden behind her school before. On Saturday morning, she walked there with her brother and met a friendly teacher. They planted flowers together and shared a simple lunch under a tree. When it started to rain, everyone moved inside and drew pictures of the garden. Mia was happy that she had tried something new with her friends.',
      'chinese': '米娅决定接受邀请。她和朋友们一起度过了一天。',
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
String event(Map<String, dynamic> json) => 'data: ${jsonEncode(json)}\n\n';

void main() {
  test(
    'complete target-aligned story passes',
    () => expect(validateStory(fixture(), [target])['title'], isNotEmpty),
  );
  test('missing target and invented word form fail', () {
    final missing = fixture();
    missing['words'][0]['surface'] = 'accepted';
    expect(
      () => validateStory(missing, [target]),
      throwsA(isA<ContentException>()),
    );
    final invented = fixture();
    invented['words'][0]['surface'] = 'acceptation';
    expect(
      () => validateStory(invented, [target]),
      throwsA(isA<ContentException>()),
    );
  });
  test('cloze must reconstruct an actual story sentence', () {
    final wrong = fixture();
    wrong['words'][0]['exercise']['prompt'] = 'They will ___ my plan tomorrow.';
    expect(
      () => validateStory(wrong, [target]),
      throwsA(isA<ContentException>()),
    );
  });
  test('incomplete translations or collocations fail', () {
    final wrong = fixture();
    wrong['words'][0]['exampleChinese'] = '';
    expect(
      () => validateStory(wrong, [target]),
      throwsA(isA<ContentException>()),
    );
    final missing = fixture();
    missing['words'][0]['collocations'] = [];
    expect(
      () => validateStory(missing, [target]),
      throwsA(isA<ContentException>()),
    );
  });
  test(
    'SSE handles UTF-8 split across byte chunks and requires completion',
    () async {
      final text = jsonEncode(fixture());
      final bytes = utf8.encode(
        event({'type': 'response.output_text.delta', 'delta': text}) +
            event({
              'type': 'response.completed',
              'response': {'status': 'completed'},
            }),
      );
      final chunks = [
        for (var i = 0; i < bytes.length; i += 7)
          bytes.sublist(i, (i + 7).clamp(0, bytes.length)),
      ];
      expect(await readResponseStream(Stream.fromIterable(chunks)), text);
      expect(
        readResponseStream(
          Stream.value(
            utf8.encode(
              event({'type': 'response.output_text.delta', 'delta': text}),
            ),
          ),
        ),
        throwsA(isA<ContentException>()),
      );
    },
  );
  test(
    'SSE refusal/incomplete response cannot be saved as successful content',
    () async {
      expect(
        readResponseStream(
          Stream.value(utf8.encode(event({'type': 'response.incomplete'}))),
        ),
        throwsA(isA<ContentException>()),
      );
    },
  );
}
