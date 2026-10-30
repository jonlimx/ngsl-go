import 'dart:math';
import 'kokoro_pronunciation.dart';

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String nextDay(String day, int days) {
  final date = DateTime.parse(day);
  return dayKey(DateTime(date.year, date.month, date.day + days));
}

String partOfSpeechLabel(String pos) =>
    const {
      'noun': 'n.',
      'verb': 'v.',
      'adj': 'adj.',
      'adv': 'adv.',
      'pron': 'pron.',
      'det': 'det.',
      'prep': 'prep.',
      'conj': 'conj.',
      'aux': 'aux.',
      'number': 'num.',
      'interjection': 'interj.',
    }[pos] ??
    pos;

class WordSense {
  WordSense.fromJson(Map<String, dynamic> json, {String? word})
    : id = json['id'],
      pos = json['pos'],
      chinese = json['chinese'],
      english = json['english'],
      exampleEnglish = json['exampleEnglish'],
      exampleChinese = json['exampleChinese'],
      pronunciationKey = json['pronunciationKey'] ?? '$word.${json['pos']}',
      ukAudio = json['ukAudio'],
      usAudio = json['usAudio'],
      ukIpa =
          json['ukIpa'] ??
          kokoroPronunciations[json['pronunciationKey'] ??
              '$word.${json['pos']}']?['ukIpa'],
      usIpa =
          json['usIpa'] ??
          kokoroPronunciations[json['pronunciationKey'] ??
              '$word.${json['pos']}']?['usIpa'],
      collocations = List<Map<String, dynamic>>.from(
        (json['collocations'] as List).map(
          (item) => Map<String, dynamic>.from(item),
        ),
      ),
      inflections = [
        for (final row in json['inflections'] as List? ?? [])
          Map<String, dynamic>.from(row),
      ],
      usageNotes = List<String>.from(json['usageNotes'] ?? []);
  final String id, pos, chinese, english, exampleEnglish, exampleChinese;
  final String? ukIpa, usIpa;
  final String? ukAudio, usAudio;
  final String pronunciationKey;
  String? get ukWordAudio => kokoroPronunciations[pronunciationKey]?['ukAudio'];
  String? get usWordAudio => kokoroPronunciations[pronunciationKey]?['usAudio'];
  bool get hasAudioVariant =>
      kokoroPronunciations.containsKey(pronunciationKey);
  final List<Map<String, dynamic>> collocations;
  final List<Map<String, dynamic>> inflections;
  final List<String> usageNotes;
}

class WordPhrase {
  WordPhrase.fromJson(Map<String, dynamic> json)
    : phrase = json['phrase'],
      chinese = json['chinese'],
      english = json['english'],
      exampleEnglish = json['exampleEnglish'],
      exampleChinese = json['exampleChinese'],
      ukAudio = json['ukAudio'],
      usAudio = json['usAudio'];
  final String phrase, chinese, english, exampleEnglish, exampleChinese;
  final String? ukAudio, usAudio;
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
    j['content']?['pos'] ?? j['pos'],
    j['content']?['chinese'] ?? j['chinese'],
    j['content']?['english'] ?? j['english'],
    j['referenceIpa'],
    List<String>.from(j['forms'] ?? []),
    Map<String, dynamic>.from(j['content'] ?? {}),
  );
  final String id, word, pos, chinese, english, referenceIpa;
  final int rank;
  final List<String> forms;
  final Map<String, dynamic> content;

  List<WordSense> get senses => [
    for (final row in content['senses'] as List? ?? [])
      WordSense.fromJson(
        Map<String, dynamic>.from(row),
        word: word.toLowerCase(),
      ),
  ];
  List<WordPhrase> get phrases => [
    for (final row in content['phrases'] as List? ?? [])
      WordPhrase.fromJson(Map<String, dynamic>.from(row)),
  ];
  String get commonMeaning => senses.isEmpty
      ? chinese
      : senses.map((sense) => sense.chinese).toSet().join('；');

  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return [
      word,
      chinese,
      english,
      for (final sense in senses) ...[sense.chinese, sense.english],
      for (final phrase in phrases) ...[
        phrase.phrase,
        phrase.chinese,
        phrase.english,
      ],
    ].any((text) => text.toLowerCase().contains(needle));
  }

  Set<String> get teachingForms {
    final inflections = content['inflections'] as List?;
    if (inflections == null || inflections.isEmpty) {
      if (pos == 'noun') {
        final plural = {
          '$word${word.endsWith('s') ? 'es' : 's'}',
          '${word}es',
          if (word.endsWith('y')) '${word.substring(0, word.length - 1)}ies',
          if (word.endsWith('f')) '${word.substring(0, word.length - 1)}ves',
          if (word.endsWith('fe')) '${word.substring(0, word.length - 2)}ves',
          const {
            'person': 'people',
            'man': 'men',
            'woman': 'women',
            'child': 'children',
            'foot': 'feet',
            'tooth': 'teeth',
            'mouse': 'mice',
            'goose': 'geese',
            'analysis': 'analyses',
            'basis': 'bases',
            'crisis': 'crises',
            'medium': 'media',
            'phenomenon': 'phenomena',
            'criterion': 'criteria',
            'index': 'indices',
            'axis': 'axes',
            'thesis': 'theses',
          }[word],
        };
        return {word, ...forms.where(plural.contains)};
      }
      if (pos.contains('adj') || pos == 'adv') return {word};
      return {word, ...forms};
    }
    return {
      word,
      for (final item in inflections)
        for (final form in item['forms'] as List)
          if (form is String && !form.contains(' ')) form,
    };
  }
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

enum MemorySkill { meaning, listening, production, spelling }

extension MemorySkillLabel on MemorySkill {
  String get label => switch (this) {
    MemorySkill.meaning => '认读',
    MemorySkill.listening => '听懂',
    MemorySkill.production => '表达',
    MemorySkill.spelling => '拼写',
  };
}

Map<String, dynamic> skillProgress(
  Map<String, dynamic> progress,
  MemorySkill skill,
) {
  final memory = progress['memory'] as Map?;
  if (memory != null) {
    return Map<String, dynamic>.from(memory[skill.name] ?? {});
  }
  // Old schedules are evidence for recognition only. Never fabricate evidence
  // for listening, production or spelling when opening an existing profile.
  if (skill == MemorySkill.meaning && (progress['reviews'] as num? ?? 0) > 0) {
    return {
      for (final key in [
        'interval',
        'due',
        'lastSeen',
        'reviews',
        'lastRecall',
      ])
        if (progress[key] != null) key: progress[key],
    };
  }
  return {};
}

MemorySkill nextMemorySkill(Map<String, dynamic> progress, String today) {
  if (progress['memory'] == null) return MemorySkill.meaning;
  final skills = MemorySkill.values.toList();
  for (final skill in skills) {
    final evidence = skillProgress(progress, skill);
    if ((evidence['lastRecall'] == Recall.again.name ||
            evidence['lastRecall'] == Recall.hard.name) &&
        (evidence['due'] as String? ?? today).compareTo(today) <= 0) {
      return skill;
    }
  }
  // Introduce the other retrieval directions on subsequent days, one per word
  // per daily plan. A new direction starts with its own short interval.
  for (final skill in skills) {
    if (skillProgress(progress, skill).isEmpty) return skill;
  }
  skills.sort((a, b) {
    final left = skillProgress(progress, a);
    final right = skillProgress(progress, b);
    final due = (left['due'] as String? ?? today).compareTo(
      right['due'] as String? ?? today,
    );
    if (due != 0) return due;
    final interval = (left['interval'] as num? ?? 0).compareTo(
      right['interval'] as num? ?? 0,
    );
    return interval != 0 ? interval : a.index.compareTo(b.index);
  });
  return skills.first;
}

MemorySkill plannedMemorySkill(
  Map<String, dynamic> plan,
  Map<String, dynamic> progress,
  String wordId,
  String today,
) {
  final name = plan['practice']?[wordId]?['skill'];
  return MemorySkill.values.where((s) => s.name == name).firstOrNull ??
      nextMemorySkill(progress, today);
}

DateTime? practiceReadyAt(
  Map<String, dynamic> plan,
  String wordId, [
  Map<String, dynamic> progress = const {},
]) {
  final scheduled = DateTime.tryParse(
    plan['practice']?[wordId]?['readyAt'] as String? ?? '',
  );
  final saved = DateTime.tryParse(
    progress[wordId]?['readyAt'] as String? ?? '',
  );
  if (scheduled == null) return saved;
  return saved != null && saved.isAfter(scheduled) ? saved : scheduled;
}

String normalizeSpelling(String value) =>
    value.trim().toLowerCase().replaceAll('’', "'").replaceAll('‘', "'");

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
  String today, {
  MemorySkill skill = MemorySkill.meaning,
  bool hinted = false,
}) {
  final prior = skillProgress(previous, skill);
  final old = (prior['interval'] as num?)?.toInt() ?? 0;
  final effective = hinted && recall != Recall.again ? Recall.hard : recall;
  final sameDay = prior['lastSeen'] == today;
  final interval = switch (effective) {
    Recall.again => 0,
    Recall.hard => 1,
    // Initial and same-day recall never establish long-term retention.
    Recall.good =>
      old == 0
          ? 1
          : sameDay
          ? max(1, old)
          : min(120, max(3, (old * 2.2).round())),
    Recall.easy =>
      old == 0
          ? 1
          : sameDay
          ? max(1, old)
          : min(180, max(3, old * 3)),
  };
  final delayed = prior['lastSeen'] != null && !sameDay;
  final independent = effective == Recall.good || effective == Recall.easy;
  final memory = Map<String, dynamic>.from(previous['memory'] ?? {});
  memory[skill.name] = {
    ...prior,
    'interval': interval,
    'due': nextDay(today, interval),
    'lastSeen': today,
    'reviews': ((prior['reviews'] as num?)?.toInt() ?? 0) + 1,
    'lastRecall': effective.name,
    'delayedSuccesses':
        (prior['delayedSuccesses'] as num? ?? 0) +
        (delayed && independent ? 1 : 0),
    'lapses':
        (prior['lapses'] as num? ?? 0) + (effective == Recall.again ? 1 : 0),
  };
  final dueDates = <String>[];
  final intervals = <int>[];
  for (final direction in MemorySkill.values) {
    final evidence = memory[direction.name] as Map?;
    dueDates.add(evidence?['due'] as String? ?? nextDay(today, 1));
    intervals.add((evidence?['interval'] as num?)?.toInt() ?? 1);
  }
  dueDates.sort();
  return {
    ...previous,
    'status': 'learning',
    'memory': memory,
    'interval': intervals.reduce(min),
    'due': dueDates.first,
    'lastSeen': today,
    'reviews': ((previous['reviews'] as num?)?.toInt() ?? 0) + 1,
    'lastRecall': effective.name,
  };
}

Map<String, dynamic> scheduleFamiliarReview(
  Map<String, dynamic> previous,
  Recall recall,
  String today, {
  required MemorySkill skill,
  bool hinted = false,
}) {
  final next = scheduleReview(
    previous,
    recall,
    today,
    skill: skill,
    hinted: hinted,
  );
  final independent =
      !hinted && (recall == Recall.good || recall == Recall.easy);
  if (!independent) {
    next.remove('beforeFamiliar');
    next.remove('familiarInterval');
    return next;
  }
  final old = (previous['familiarInterval'] as num?)?.toInt() ?? 14;
  final interval = min(120, max(21, (old * 1.8).round()));
  return {
    ...next,
    'status': 'familiar',
    'familiarInterval': interval,
    'due': nextDay(today, interval),
  };
}

/* Daily plans keep their existing identities and completed items. New plans
 * use a bounded word budget; overflow remains due in progress for later days. */
const dailyWordBudget = 80;

({int remaining, int? days, String? finish}) learningForecast(
  List<Vocabulary> words,
  Map<String, dynamic> progress,
  Map<String, dynamic>? plan,
  int dailyNew,
  String today,
) {
  final remaining = words.where((w) => isUnlearned(progress[w.id])).length;
  if (remaining == 0) return (remaining: 0, days: 0, finish: today);
  if (dailyNew <= 0) return (remaining: remaining, days: null, finish: null);
  final planned = (plan?['wordIds'] as List? ?? []).toSet();
  final availableToday = words
      .where((w) => planned.contains(w.id) && isUnlearned(progress[w.id]))
      .length;
  final daysAfterToday = ((remaining - availableToday) / dailyNew).ceil();
  return (
    remaining: remaining,
    days: daysAfterToday + 1,
    finish: nextDay(today, daysAfterToday),
  );
}

const maxDailyNew = 60;
const studyGroupSize = 5;

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
            (p['status'] == 'learning' || p['status'] == 'familiar') &&
            (p['due'] as String? ?? today).compareTo(today) <= 0;
      }).toList()..sort((a, b) {
        final order = (progress[a.id]['due'] as String? ?? today).compareTo(
          progress[b.id]['due'] as String? ?? today,
        );
        return order == 0 ? a.rank.compareTo(b.rank) : order;
      });
  final regular = due
      .where((word) => progress[word.id]['status'] != 'familiar')
      .toList();
  final checks = due
      .where((word) => progress[word.id]['status'] == 'familiar')
      .take(2)
      .toList();
  final reviewWords = [...regular, ...checks].take(dailyWordBudget).toList();
  final allowance = min(
    max(0, min(maxDailyNew, newCount)),
    max(0, dailyWordBudget - reviewWords.length),
  );
  final fresh = words
      .where((w) => progress[w.id] == null || progress[w.id]['status'] == 'new')
      .take(allowance)
      .toList();
  final selected = [...reviewWords, ...fresh];
  return {
    'date': today,
    'wordIds': selected.map((w) => w.id).toList(),
    'newIds': fresh.map((w) => w.id).toList(),
    'done': <String>[],
    'deferredReviews': max(0, due.length - reviewWords.length),
    'familiarIds': checks
        .where((w) => reviewWords.contains(w))
        .map((w) => w.id)
        .toList(),
    'practice': {
      for (final word in selected)
        word.id: {
          'skill': nextMemorySkill(
            Map<String, dynamic>.from(progress[word.id] ?? {}),
            today,
          ).name,
          'attempts': 0,
          'readyAt': ?progress[word.id]?['readyAt'],
        },
    },
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
      ...target.teachingForms.map((f) => f.toLowerCase()),
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
