import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models.dart';
import '../../network_policy.dart';
import 'response_stream.dart';
import 'chatgpt_plan_auth_service.dart';

class StoryService {
  StoryService({http.Client? client, ChatGptPlanAuthService? auth})
    : client = OfflineAwareClient(client: client),
      auth = auth ?? ChatGptPlanAuthService.instance;
  final http.Client client;
  final ChatGptPlanAuthService auth;
  void cancel() => client.close();

  Future<Map<String, dynamic>> generate({
    required Learner learner,
    required List<Vocabulary> targets,
    required String model,
    required Iterable<String> knownWords,
    required Iterable<String> recentTitles,
  }) async {
    try {
      NetworkPolicy.requireOnline();
      final token = await auth.getValidAccessToken();
      final request =
          http.Request('POST', Uri.parse('https://api.openai.com/v1/responses'))
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
            })
            ..body = jsonEncode({
              'model': model,
              'store': false,
              'stream': true,
              'instructions':
                  '''Create original vocabulary-learning material for a Chinese-speaking ${learner.child ? 'school-age child. Use safe, warm everyday situations, no adult themes or frightening violence' : 'adult learning everyday and workplace English'}. Write a coherent, interesting 130–200 word English story (children: 100–150 words). Include a small problem and a satisfying outcome; do not force unrelated words together. Naturally use every supplied target in its supplied meaning; select its exact surface form from supplied forms. Prefer simple known/background vocabulary and avoid unnecessary extra unknown words. The known-word list is self-reported, not proof of every meaning. Include natural repetition when helpful, not mechanical repetition. Explain only the target sense with short Chinese and simple English. Give two or three genuinely common collocations per word with Chinese meanings; each must contain the target or an allowed form. Give an original natural bilingual example. UK and US IPA must match the target part of speech and meaning, including stress; verify homographs such as record and present. Generate one cloze per target by COPYING ONE EXACT COMPLETE SENTENCE from your story and replacing the target surface form with exactly one ___; its answer is that surface form, no multiple choice. Chinese cloze hint translates the complete sentence. Return paragraph-aligned faithful Chinese translation and one brief Chinese speaking task that asks the learner to use one or two targets in a NEW situation. Internally review grammar, collocations, meaning, translations, all target occurrences and cloze answers before returning JSON. Avoid topics/titles used recently. No markdown in fields. Do not claim the text is a real news event or a dictionary quotation.''',
              'input': [
                {
                  'role': 'user',
                  'content': jsonEncode({
                    'topic': learner.topic,
                    'targets': [
                      for (final w in targets)
                        {
                          'id': w.id,
                          'word': w.word,
                          'partOfSpeech': w.pos,
                          'chinese': w.chinese,
                          'english': w.english,
                          'forms': w.teachingForms.toList(),
                          'referenceIpa': w.referenceIpa,
                          'inflections': w.content['inflections'] ?? [],
                          'wordFamily': w.content['wordFamily'] ?? [],
                          'usageNotes': w.content['usageNotes'] ?? [],
                        },
                    ],
                    'knownWords': knownWords.take(2809).toList(),
                    'recentTitles': recentTitles.take(12).toList(),
                  }),
                },
              ],
              'text': {
                'format': {
                  'type': 'json_schema',
                  'name': 'ngsl_daily_story',
                  'strict': true,
                  'schema': schema(targets.map((w) => w.id).toList()),
                },
              },
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 40));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 15),
        );
        throw ContentException(switch (response.statusCode) {
          401 => 'ChatGPT 连接已过期，请在设置中重新连接。',
          403 => '当前账号暂时不能使用这个模型，请在设置中更换模型或重新连接。',
          429 => 'ChatGPT 使用额度或请求频率已达到限制，请稍后再试。',
          _ => 'ChatGPT 暂时无法生成故事，请稍后重试。',
        });
      }
      final raw = await readResponseStream(
        response.stream,
      ).timeout(const Duration(minutes: 2));
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const ContentException('故事格式不完整，请重试。');
      }
      return validateStory(decoded, targets);
    } on ChatGptPlanAuthException {
      rethrow;
    } on ContentException {
      rethrow;
    } on TimeoutException {
      throw const ContentException('故事生成超时，请重试。已有学习记录不受影响。');
    } on SocketException {
      throw const ContentException('暂时无法联网。可以先复习已保存的单词和故事。');
    } on http.ClientException {
      throw const ContentException('连接已中断或生成已取消，请重试。');
    } on FormatException {
      throw const ContentException('故事内容没有完整返回，请重试。');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> schema(List<String> ids) {
    Map<String, dynamic> object(Map<String, dynamic> properties) => {
      'type': 'object',
      'additionalProperties': false,
      'properties': properties,
      'required': properties.keys.toList(),
    };
    const string = {'type': 'string'};
    final bilingual = object({'english': string, 'chinese': string});
    return object({
      'title': string,
      'paragraphs': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 8,
        'items': bilingual,
      },
      'words': {
        'type': 'array',
        'minItems': ids.length,
        'maxItems': ids.length,
        'items': object({
          'id': {'type': 'string', 'enum': ids},
          'surface': string,
          'chinese': string,
          'english': string,
          'ukIpa': string,
          'usIpa': string,
          'collocations': {
            'type': 'array',
            'minItems': 2,
            'maxItems': 3,
            'items': bilingual,
          },
          'exampleEnglish': string,
          'exampleChinese': string,
          'exercise': object({
            'prompt': string,
            'answer': string,
            'chinese': string,
          }),
        }),
      },
      'speakingPrompt': string,
    });
  }
}
