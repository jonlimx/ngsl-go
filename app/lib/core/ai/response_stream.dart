import 'dart:async';
import 'dart:convert';
import '../../models.dart';

Future<String> readResponseStream(Stream<List<int>> stream) async {
  final output = StringBuffer();
  final lines = <String>[];
  Map<String, dynamic>? completed;
  var received = 0;
  void consume() {
    if (lines.isEmpty) return;
    final data = lines.join('\n');
    lines.clear();
    if (data == '[DONE]') return;
    final event = jsonDecode(data) as Map<String, dynamic>;
    switch (event['type']) {
      case 'response.output_text.delta':
        output.write(event['delta'] ?? '');
      case 'response.completed':
        final response = event['response'];
        if (response is! Map<String, dynamic> ||
            response['status'] == 'incomplete' ||
            response['status'] == 'failed') {
          throw const ContentException('故事没有完整生成，请重试。');
        }
        completed = response;
      case 'error' || 'response.failed' || 'response.incomplete':
        throw const ContentException('故事没有完整生成，请重试。');
    }
  }

  await for (final line
      in stream
          .timeout(const Duration(seconds: 45))
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    received += line.length;
    if (received > 2000000) throw const ContentException('故事响应过长，请重试。');
    if (line.isEmpty) {
      consume();
    } else if (line.startsWith('data:')) {
      lines.add(line.substring(5).trimLeft());
    }
  }
  consume();
  if (completed == null) throw const ContentException('连接提前结束，故事未保存，请重试。');
  if (output.isNotEmpty) return output.toString();
  final result = StringBuffer();
  for (final item in completed!['output'] as List? ?? []) {
    for (final part in item['content'] as List? ?? []) {
      if (part['type'] == 'output_text') result.write(part['text']);
    }
  }
  if (result.isEmpty) throw const ContentException('ChatGPT 没有返回故事正文，请重试。');
  return result.toString();
}
