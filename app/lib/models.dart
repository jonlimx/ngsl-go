import 'dart:math';

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String nextDay(String day, int days) {
  final date = DateTime.parse(day);
  return dayKey(DateTime(date.year, date.month, date.day + days));
}

class Vocabulary {
  const Vocabulary(
    this.id,
    this.word,
    this.rank,
    this.pos,
    this.chinese,
    this.english,
    this.referenceIpa,
    this.forms,
    this.content,
  );
  factory Vocabulary.fromJson(Map<String, dynamic> j) => Vocabulary(
    j['id'],
    j['word'],
    j['rank'],
    j['pos'],
    j['chinese'],
    j['english'],
    j['referenceIpa'],
    List<String>.from(j['forms'] ?? []),
    Map<String, dynamic>.from(j['content'] ?? {}),
  );
  final String id, word, pos, chinese, english, referenceIpa;
  final int rank;
  final List<String> forms;
  final Map<String, dynamic> content;
}

class Learner {
  Learner(
    this.id,
    this.name,
    this.child,
    this.dailyNew,
    this.topic,
    this.accent,
  );
  factory Learner.fromJson(Map<String, dynamic> j) => Learner(
    j['id'],
    j['name'],
    j['child'],
    j['dailyNew'] ?? 5,
    j['topic'] ?? 'mixed',
    j['accent'] ?? 'uk',
  );
  final String id, name, topic, accent;
  final bool child;
  final int dailyNew;
}

enum Recall { again, hard, good, easy }

bool isUnlearned(dynamic progress) =>
    progress == null ||
    progress['status'] == null ||
    progress['status'] == 'new';

List<Vocabulary> screeningCandidates(
  List<Vocabulary> words,
  Map<String, dynamic> progress,
) =>
    (words
        .where(
          (w) =>
              isUnlearned(progress[w.id]) &&
              progress[w.id]?['screened'] != true,
        )
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank)));

Map<String, dynamic> scheduleReview(
  Map<String, dynamic> previous,
  Recall recall,
  String today,
) {
  final old = (previous['interval'] as num?)?.toInt() ?? 0;
  final interval = switch (recall) {
    Recall.again => 0,
    Recall.hard => max(1, (old * 1.3).round()),
    Recall.good => old == 0 ? 1 : min(120, max(old + 1, (old * 2.2).round())),
    Recall.easy => old == 0 ? 3 : min(180, max(old + 2, old * 3)),
  };
  return {
    ...previous,
    'status': 'learning',
    'interval': interval,
    'due': nextDay(today, interval),
    'lastSeen': today,
    'reviews': ((previous['reviews'] as num?)?.toInt() ?? 0) + 1,
    'lastRecall': recall.name,
  };
}

Map<String, dynamic> createDailyPlan(
  List<Vocabulary> words,
  Map<String, dynamic> progress,
  int newCount,
  String today,
) {
  final due =
      words.where((w) {
        final p = progress[w.id] as Map?;
        return p != null &&
            p['status'] == 'learning' &&
            (p['due'] as String? ?? today).compareTo(today) <= 0;
      }).toList()..sort(
        (a, b) => (progress[a.id]['due'] as String).compareTo(
          progress[b.id]['due'] as String,
        ),
      );
  final fresh = words
      .where((w) => progress[w.id] == null || progress[w.id]['status'] == 'new')
      .take(newCount);
  return {
    'date': today,
    'wordIds': [...due.map((w) => w.id), ...fresh.map((w) => w.id)],
    'newIds': fresh.map((w) => w.id).toList(),
    'done': <String>[],
  };
}

class ContentException implements Exception {
  const ContentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Structure is checked separately from semantic quality. A valid schema is not
/// evidence that every phrase is natural; generation instructions require review.
Map<String, dynamic> validateStory(
  Map<String, dynamic> j,
  List<Vocabulary> targets,
) {
  String text(dynamic value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw ContentException('故事中的$field不完整，请重新生成。');
    }
    return value.trim();
  }

  text(j['title'], '标题');
  final paragraphs = j['paragraphs'];
  if (paragraphs is! List || paragraphs.isEmpty || paragraphs.length > 12) {
    throw const ContentException('故事段落不完整，请重新生成。');
  }
  final buffer = StringBuffer();
  for (final p in paragraphs) {
    if (p is! Map) throw const ContentException('故事格式不完整，请重试。');
    buffer.writeln(text(p['english'], '英文'));
    text(p['chinese'], '中文翻译');
  }
  final story = buffer.toString().toLowerCase();
  final count = RegExp(
    r"[a-z]+(?:['’-][a-z]+)*",
    caseSensitive: false,
  ).allMatches(story).length;
  if (count < 60 || count > 420) throw const ContentException('故事篇幅不合适，请重新生成。');
  final items = j['words'];
  if (items is! List || items.length != targets.length) {
    throw const ContentException('部分目标词没有完整返回，请重试。');
  }
  final remaining = targets.map((w) => w.id).toSet();
  for (final raw in items) {
    if (raw is! Map || !remaining.remove(raw['id'])) {
      throw const ContentException('故事的目标词发生重复或遗漏，请重试。');
    }
    final target = targets.firstWhere((w) => w.id == raw['id']);
    final surface = text(raw['surface'], '目标词');
    final forms = {
      target.word.toLowerCase(),
      ...target.forms.map((f) => f.toLowerCase()),
    };
    bool containsTarget(String value) => forms.any(
      (form) => RegExp(
        '(?<![a-z])${RegExp.escape(form)}(?![a-z])',
      ).hasMatch(value.toLowerCase()),
    );
    if (!forms.contains(surface.toLowerCase()) ||
        !RegExp(
          '(?<![a-z])${RegExp.escape(surface.toLowerCase())}(?![a-z])',
        ).hasMatch(story)) {
      throw ContentException('故事中缺少 ${target.word} 的正确词形，请重试。');
    }
    for (final key in [
      'chinese',
      'english',
      'ukIpa',
      'usIpa',
      'exampleEnglish',
      'exampleChinese',
    ]) {
      text(raw[key], key);
    }
    if (!containsTarget(raw['exampleEnglish'])) {
      throw ContentException('${target.word} 的例句没有使用目标词，请重试。');
    }
    final collocations = raw['collocations'];
    if (collocations is! List ||
        collocations.length < 2 ||
        collocations.length > 3) {
      throw ContentException('${target.word} 的搭配不完整，请重试。');
    }
    for (final c in collocations) {
      if (c is! Map) throw const ContentException('搭配内容不完整，请重试。');
      text(c['english'], '搭配');
      text(c['chinese'], '搭配解释');
      if (!containsTarget(c['english'])) {
        throw ContentException('${target.word} 的搭配与目标词不一致，请重试。');
      }
    }
    final exercise = raw['exercise'];
    if (exercise is! Map) throw const ContentException('回忆练习不完整，请重试。');
    final prompt = text(exercise['prompt'], '题目');
    final answer = text(exercise['answer'], '答案');
    text(exercise['chinese'], '提示');
    if (RegExp('___').allMatches(prompt).length != 1 ||
        !forms.contains(answer.toLowerCase())) {
      throw const ContentException('回忆题的空格或答案不正确，请重试。');
    }
    final completed = prompt
        .replaceFirst('___', answer)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (!story.replaceAll(RegExp(r'\s+'), ' ').contains(completed)) {
      throw const ContentException('回忆题与故事内容不一致，请重试。');
    }
  }
  if (remaining.isNotEmpty) throw const ContentException('目标词不完整，请重试。');
  text(j['speakingPrompt'], '表达练习');
  return j;
}
