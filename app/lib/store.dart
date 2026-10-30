import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'models.dart';

class ScreeningUndo {
  ScreeningUndo._(this.learnerId, this._before, this._after);
  final String learnerId;
  final Map<String, dynamic> _before, _after;
  int get count => _after.length;
  int get keptCount => _after.values.where((p) => p['status'] == 'new').length;
}

class StudyStore {
  final _listeners = <void Function()>[];
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notifyListeners() {
    for (final listener in List.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }

  void dispose() => _listeners.clear();
  StudyStore(this.directory, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Directory directory;
  final DateTime Function() clock;
  Map<String, dynamic> _data = {
    'version': 1,
    'activeId': null,
    'learners': [],
    'profiles': {},
    'wordContent': {},
    'model': '',
  };
  Future<void> _pending = Future.value();
  String? recoveryNotice;
  String get today => dayKey(clock());
  String? get activeId => _data['activeId'];
  List<Learner> get learners => (_data['learners'] as List)
      .map((j) => Learner.fromJson(Map<String, dynamic>.from(j)))
      .toList();
  Learner? get active => learners.where((p) => p.id == activeId).firstOrNull;
  String get model => _data['model'] ?? '';
  Map<String, dynamic> profile(String id) =>
      Map<String, dynamic>.from(_data['profiles'][id] ?? {});
  Map<String, dynamic> progress(String id) =>
      Map<String, dynamic>.from(profile(id)['progress'] ?? {});
  List<Map<String, dynamic>> practiceLog(String id) =>
      (profile(id)['practiceLog'] as List? ?? [])
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
  Map<String, dynamic>? plan(String id, [String? day]) {
    final p = profile(id)['plans']?[day ?? today];
    return p == null ? null : Map<String, dynamic>.from(p);
  }

  List<Map<String, dynamic>> stories(String id) =>
      (profile(id)['stories'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s))
          .toList()
          .reversed
          .toList();
  Map<String, dynamic> content(String learnerId, Vocabulary word) => {
    ...word.content,
    ...Map<String, dynamic>.from(
      profile(learnerId)['wordContent']?[word.id] ?? {},
    ),
    for (final key in ['ukIpa', 'usIpa', 'ukAudio', 'usAudio'])
      if (word.content[key] != null) key: word.content[key],
    if (word.content['offlineCardVersion'] != null) ...{
      'english': word.english,
      'chinese': word.chinese,
      for (final key in ['exampleEnglish', 'exampleChinese', 'collocations'])
        key: word.content[key],
    },
  };

  Future<void> saveWordContent(
    String learnerId,
    String wordId,
    Map<String, dynamic> content,
  ) => _mutate((d) {
    final profile = d['profiles'][learnerId];
    if (profile == null) throw const ContentException('学习者不存在，词卡没有保存。');
    profile.putIfAbsent('wordContent', () => <String, dynamic>{});
    profile['wordContent'][wordId] = content;
  });

  Future<void> load() async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/study.json');
    if (!await file.exists()) return;
    for (final candidate in [file, File('${file.path}.bak')]) {
      try {
        final value = jsonDecode(await candidate.readAsString());
        if (value is! Map<String, dynamic> ||
            value['version'] != 1 ||
            value['learners'] is! List ||
            value['profiles'] is! Map ||
            value['wordContent'] is! Map) {
          throw const FormatException();
        }
        for (final learner in value['learners']) {
          Learner.fromJson(Map<String, dynamic>.from(learner));
          if (value['profiles'][learner['id']] is! Map) {
            throw const FormatException();
          }
        }
        _data = value;
        if (candidate.path != file.path) recoveryNotice = '已从本机备份恢复学习记录。';
        notifyListeners();
        return;
      } catch (_) {
        /* Try the previous successfully written snapshot. */
      }
    }
    throw const ContentException('学习记录暂时无法读取。原文件已保留，请勿清除应用数据。');
  }

  Future<void> _mutate(void Function(Map<String, dynamic>) change) {
    final work = _pending.then((_) async {
      final next = jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;
      change(next);
      final file = File('${directory.path}/study.json');
      final temp = File('${file.path}.pending');
      await temp.writeAsString(jsonEncode(next), flush: true);
      // Back up known-good in-memory data, not a possibly corrupted disk file.
      await File(
        '${file.path}.bak',
      ).writeAsString(jsonEncode(_data), flush: true);
      await temp.rename(file.path);
      _data = next;
      notifyListeners();
    });
    _pending = work.catchError((Object _) {});
    return work;
  }

  Future<String> createLearner(String name, bool child) async {
    name = name.trim();
    if (name.isEmpty || name.length > 24) {
      throw const ContentException('请输入 1～24 个字的名字。');
    }
    final id =
        '${clock().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    await _mutate((d) {
      if ((d['learners'] as List).any((p) => p['name'] == name)) {
        throw const ContentException('这个名字已经存在，请换一个名字。');
      }
      d['learners'].add({
        'id': id,
        'name': name,
        'child': child,
        'dailyNew': 5,
        'topic': 'mixed',
        'accent': 'uk',
      });
      d['profiles'][id] = {'progress': {}, 'plans': {}, 'stories': []};
      d['activeId'] = id;
    });
    return id;
  }

  Future<void> switchLearner(String id) => _mutate((d) {
    if (!d['profiles'].containsKey(id)) {
      throw const ContentException('这个学习者不存在。');
    }
    d['activeId'] = id;
  });
  Future<void> configure(
    String id, {
    int? dailyNew,
    String? topic,
    String? accent,
    List<Vocabulary>? words,
  }) => _mutate((d) {
    final row = (d['learners'] as List).firstWhere((p) => p['id'] == id);
    if (dailyNew != null) row['dailyNew'] = dailyNew.clamp(0, maxDailyNew);
    if (topic != null) row['topic'] = topic;
    if (accent != null) row['accent'] = accent;
    if (dailyNew != null && words != null) {
      final profile = d['profiles'][id];
      final plan = profile['plans'][today];
      if (plan == null) {
        profile['plans'][today] = createDailyPlan(
          words,
          Map<String, dynamic>.from(profile['progress']),
          row['dailyNew'],
          today,
        );
      } else {
        final ids = plan['wordIds'] as List;
        final newIds = plan['newIds'] as List;
        // An explicit increase requests that many new words today, even if
        // reviews already filled the automatic daily planning budget.
        final count = row['dailyNew'] as int;
        final candidates = words.where(
          (w) =>
              !ids.contains(w.id) &&
              isUnlearned(profile['progress'][w.id]) &&
              profile['progress'][w.id]?['status'] != 'known',
        );
        for (final word in candidates.take(
          max<int>(0, count - newIds.length),
        )) {
          ids.add(word.id);
          newIds.add(word.id);
          plan.putIfAbsent('practice', () => <String, dynamic>{});
          plan['practice'][word.id] = {
            'skill': MemorySkill.meaning.name,
            'attempts': 0,
          };
        }
      }
    }
  });

  /// Optional same-day practice never clears completion or fabricates delayed
  /// recall. Only a difficulty changes the schedule; success keeps its due date.
  Future<void> repeatToday(
    String id,
    String wordId,
    Recall recall, {
    required MemorySkill skill,
    required String planDay,
    bool hinted = false,
  }) {
    final now = clock();
    final day = dayKey(now);
    return _mutate((d) {
      if (planDay != day) throw const ContentException('日期已变更，请回到今日学习重新开始。');
      final profile = d['profiles'][id];
      final plan = profile?['plans']?[day];
      if (plan == null || !(plan['done'] as List).contains(wordId)) {
        throw const ContentException('请先完成这个词的今日任务，再重新练习。');
      }
      final previous = Map<String, dynamic>.from(
        profile['progress'][wordId] ?? {},
      );
      if (previous['status'] == 'known') return;
      final readyAt = DateTime.tryParse(previous['readyAt'] as String? ?? '');
      if (readyAt != null && now.isBefore(readyAt)) {
        throw const ContentException('先练习其他词，稍后再回忆这个词。');
      }
      final effective = hinted && recall != Recall.again ? Recall.hard : recall;
      final independent = effective == Recall.good || effective == Recall.easy;
      if (!independent) {
        profile['progress'][wordId] = previous['status'] == 'familiar'
            ? scheduleFamiliarReview(previous, effective, day, skill: skill)
            : scheduleReview(previous, effective, day, skill: skill);
        profile['progress'][wordId]['readyAt'] = now
            .add(const Duration(minutes: 1))
            .toIso8601String();
      }
      _logPractice(profile, {
        'wordId': wordId,
        'kind': 'sameDayPractice',
        'skill': skill.name,
        'recall': effective.name,
        'hinted': hinted,
        'independent': independent,
        'delayed': false,
        'at': now.toIso8601String(),
        'planDay': day,
      });
    });
  }

  Future<void> setModel(String value) => _mutate((d) => d['model'] = value);

  Future<({int known, int learning, int skipped})> copyScreening(
    String sourceId,
    String targetId,
    List<Vocabulary> words,
  ) async {
    if (sourceId == targetId) throw const ContentException('请选择另一个学习者。');
    var known = 0, learning = 0, skipped = 0;
    await _mutate((d) {
      final source = d['profiles'][sourceId];
      final target = d['profiles'][targetId];
      if (source == null || target == null) {
        throw const ContentException('学习者不存在。');
      }
      for (final word in words) {
        final original = source['progress'][word.id] as Map?;
        if (original == null ||
            (original['status'] != 'known' && original['screened'] != true)) {
          continue;
        }
        final previous = target['progress'][word.id];
        if (!isUnlearned(previous) || previous?['screened'] == true) {
          skipped++;
          continue;
        }
        final before = Map<String, dynamic>.from(previous ?? {});
        final excluded = original['status'] == 'known';
        target['progress'][word.id] = {
          ...before,
          'status': excluded ? 'known' : 'new',
          'screened': true,
          if (excluded) 'beforeKnown': before,
        };
        if (excluded) {
          known++;
        } else {
          learning++;
        }
      }
      _replanUnstarted(d, targetId, words);
    });
    return (known: known, learning: learning, skipped: skipped);
  }

  Future<void> markFamiliar(String id, String wordId, bool familiar) {
    final now = clock();
    final day = dayKey(now);
    return _mutate((d) {
      final profile = d['profiles'][id];
      var previous = Map<String, dynamic>.from(
        profile['progress'][wordId] ?? {},
      );
      final plan = profile['plans'][day];
      if (familiar) {
        if (previous['status'] == 'familiar') return;
        // A screened word can explicitly opt into low-frequency checking.
        if (previous['status'] == 'known') {
          final screened = previous['screened'] == true;
          previous = Map<String, dynamic>.from(previous['beforeKnown'] ?? {});
          if (screened) previous['screened'] = true;
        }
        final interval = max(
          14,
          min(60, ((previous['interval'] as num? ?? 0) * 2).round()),
        );
        profile['progress'][wordId] = {
          ...previous,
          'beforeFamiliar': previous,
          'status': 'familiar',
          'familiarInterval': interval,
          'familiarSince': day,
          'due': nextDay(day, interval),
        };
        (profile['progress'][wordId] as Map).remove('readyAt');
        if (plan != null &&
            (plan['wordIds'] as List).contains(wordId) &&
            !(plan['done'] as List).contains(wordId)) {
          plan['done'].add(wordId);
          plan['started'] = true;
        }
      } else {
        if (previous['status'] != 'familiar') return;
        final restored = Map<String, dynamic>.from(previous)
          ..remove('beforeFamiliar')
          ..remove('familiarInterval')
          ..remove('familiarSince')
          ..remove('readyAt');
        restored['status'] =
            (previous['reviews'] as num? ?? 0) > 0 ||
                previous['introducedAt'] != null
            ? 'learning'
            : 'new';
        restored['due'] = day;
        profile['progress'][wordId] = restored;
        if (plan != null) {
          if (!(plan['wordIds'] as List).contains(wordId) &&
              (plan['wordIds'] as List).length < dailyWordBudget) {
            plan['wordIds'].add(wordId);
          }
          plan['done'].remove(wordId);
          (plan['practice'] as Map?)?.remove(wordId);
        }
      }
      _logPractice(profile, {
        'kind': 'familiarity',
        'wordId': wordId,
        'familiar': familiar,
        'at': now.toIso8601String(),
      });
    });
  }

  Future<void> markKnown(
    String id,
    Iterable<String> ids,
    bool known, {
    List<Vocabulary>? words,
  }) => _mutate((d) {
    final profile = d['profiles'][id];
    for (final wordId in ids) {
      final previous = Map<String, dynamic>.from(
        profile['progress'][wordId] ?? {},
      );
      if (known) {
        if (previous['status'] == 'known') continue;
        profile['progress'][wordId] = {
          ...previous,
          'beforeKnown': previous,
          'status': 'known',
        };
      } else if (previous['status'] == 'known') {
        final restored = Map<String, dynamic>.from(
          previous['beforeKnown'] ?? {},
        );
        restored.putIfAbsent('status', () => 'new');
        profile['progress'][wordId] = restored;
      }
    }
    // Before learning starts, refill excluded basic words immediately.
    if (words != null) _replanUnstarted(d, id, words);
  });

  /// One atomic batch. Never replace an existing review schedule or known word.
  Future<ScreeningUndo> screenWords(
    String learnerId,
    List<Vocabulary> words,
    Iterable<String> ids, {
    Set<String> keepLearning = const {},
  }) async {
    final requested = ids.toSet();
    final kept = Set<String>.from(keepLearning);
    final before = <String, dynamic>{}, after = <String, dynamic>{};
    await _mutate((d) {
      final profile = d['profiles'][learnerId];
      if (profile == null) throw const ContentException('学习者不存在，筛选没有保存。');
      final progress = profile['progress'] as Map;
      for (final word in words.where((w) => requested.contains(w.id))) {
        final previous = progress[word.id];
        if (!isUnlearned(previous)) continue;
        before[word.id] = previous;
        final old = Map<String, dynamic>.from(previous ?? {});
        final next = kept.contains(word.id)
            ? {...old, 'status': 'new', 'screened': true}
            : {...old, 'status': 'known', 'beforeKnown': old, 'screened': true};
        progress[word.id] = next;
        after[word.id] = next;
      }
      _replanUnstarted(d, learnerId, words);
    });
    return ScreeningUndo._(learnerId, before, after);
  }

  Future<void> undoScreening(ScreeningUndo batch, List<Vocabulary> words) =>
      _mutate((d) {
        final progress = d['profiles'][batch.learnerId]?['progress'] as Map?;
        if (progress == null) throw const ContentException('学习者不存在。');
        for (final id in batch._after.keys) {
          // Do not overwrite learning or other edits made after this batch.
          if (jsonEncode(progress[id]) != jsonEncode(batch._after[id])) {
            continue;
          }
          final previous = batch._before[id];
          if (previous == null) {
            progress.remove(id);
          } else {
            progress[id] = previous;
          }
        }
        _replanUnstarted(d, batch.learnerId, words);
      });

  void _replanUnstarted(
    Map<String, dynamic> data,
    String id,
    List<Vocabulary> words,
  ) {
    final profile = data['profiles'][id];
    final plan = profile['plans'][today];
    final hasStory = (profile['stories'] as List).any(
      (s) => s['date'] == today,
    );
    if ((plan == null ||
            ((plan['done'] as List).isEmpty && plan['started'] != true)) &&
        !hasStory) {
      final learner = (data['learners'] as List).firstWhere(
        (p) => p['id'] == id,
      );
      profile['plans'][today] = createDailyPlan(
        words,
        Map<String, dynamic>.from(profile['progress']),
        learner['dailyNew'],
        today,
      );
    }
  }

  Future<void> ensurePlan(String id, List<Vocabulary> words) => _mutate((d) {
    final profile = d['profiles'][id];
    final learner = (d['learners'] as List).firstWhere((p) => p['id'] == id);
    profile['plans'].putIfAbsent(
      today,
      () => createDailyPlan(
        words,
        Map<String, dynamic>.from(profile['progress']),
        learner['dailyNew'],
        today,
      ),
    );
  });

  /// Exposure is saved separately from retrieval. Closing a new card cannot
  /// turn viewing an answer into a successful review.
  Future<void> introduce(String id, String wordId, String planDay) {
    final now = clock();
    return _mutate((d) {
      final profile = d['profiles'][id];
      final plan = profile?['plans']?[planDay];
      final previous = Map<String, dynamic>.from(
        profile?['progress']?[wordId] ?? {},
      );
      if (plan == null ||
          !(plan['wordIds'] as List).contains(wordId) ||
          !isUnlearned(previous)) {
        return;
      }
      profile['progress'][wordId] = {
        ...previous,
        'status': 'learning',
        'introducedAt': now.toIso8601String(),
        'due': dayKey(now),
        'readyAt': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      plan['started'] = true;
      plan.putIfAbsent('practice', () => <String, dynamic>{});
      plan['practice'][wordId] = {
        'skill': MemorySkill.meaning.name,
        'attempts': 0,
        'readyAt': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      _logPractice(profile, {
        'wordId': wordId,
        'kind': 'exposure',
        'at': now.toIso8601String(),
      });
    });
  }

  void _logPractice(Map profile, Map<String, dynamic> event) {
    profile.putIfAbsent('practiceLog', () => <dynamic>[]);
    (profile['practiceLog'] as List).add(event);
  }

  Future<bool> review(
    String id,
    String wordId,
    Recall recall,
    String planDay, {
    MemorySkill? skill,
    bool hinted = false,
    String? response,
  }) async {
    final now = clock();
    final day = dayKey(now);
    var applied = false;
    await _mutate((d) {
      final profile = d['profiles'][id];
      if (profile['progress'][wordId]?['status'] == 'known') return;
      final p = Map<String, dynamic>.from(profile['progress'][wordId] ?? {});
      // Reopening a completed card must not advance its interval twice.
      final plan = profile['plans'][planDay];
      if (plan == null ||
          !(plan['wordIds'] as List).contains(wordId) ||
          (plan['done'] as List).contains(wordId)) {
        return;
      }
      final direction = plannedMemorySkill(plan, p, wordId, day);
      if (skill != null && skill != direction) {
        throw const ContentException('这张词卡的练习已更新，请返回后继续。');
      }
      final ready = practiceReadyAt(
        Map<String, dynamic>.from(plan),
        wordId,
        Map<String, dynamic>.from(profile['progress']),
      );
      if (ready != null && now.isBefore(ready)) {
        throw const ContentException('先练习其他词，稍后再回忆这个词。');
      }
      final effective = hinted && recall != Recall.again ? Recall.hard : recall;
      final prior = skillProgress(p, direction);
      final independent = effective == Recall.good || effective == Recall.easy;
      profile['progress'][wordId] = p['status'] == 'familiar'
          ? scheduleFamiliarReview(p, effective, day, skill: direction)
          : scheduleReview(p, effective, day, skill: direction);
      plan['started'] = true;
      plan.putIfAbsent('practice', () => <String, dynamic>{});
      final state = Map<String, dynamic>.from(plan['practice'][wordId] ?? {});
      final attempts = (state['attempts'] as num? ?? 0).toInt() + 1;
      plan['practice'][wordId] = {
        ...state,
        'skill': direction.name,
        'attempts': attempts,
        if (!independent)
          'readyAt': now
              .add(Duration(minutes: attempts >= 3 ? 10 : 1))
              .toIso8601String(),
      };
      if (independent) {
        (plan['practice'][wordId] as Map).remove('readyAt');
        (profile['progress'][wordId] as Map).remove('readyAt');
        plan['done'].add(wordId);
      } else {
        profile['progress'][wordId]['readyAt'] =
            plan['practice'][wordId]['readyAt'];
      }
      applied = true;
      _logPractice(profile, {
        'wordId': wordId,
        'kind': 'retrieval',
        'skill': direction.name,
        'recall': effective.name,
        'hinted': hinted,
        'independent': independent,
        'delayed': prior['lastSeen'] != null && prior['lastSeen'] != day,
        'at': now.toIso8601String(),
        'planDay': planDay,
        'response': ?response,
      });
    });
    return applied;
  }

  Future<void> saveStory(
    String id,
    String planDay,
    Map<String, dynamic> story,
  ) => _mutate((d) {
    final profile = d['profiles'][id];
    if (profile == null) throw const ContentException('学习者不存在，故事没有保存。');
    final row = {
      ...story,
      'id': '${clock().microsecondsSinceEpoch}',
      'date': planDay,
      'createdAt': clock().toIso8601String(),
      'practiced': <String>[],
    };
    profile['stories'].add(row);
    for (final w in story['words']) {
      profile.putIfAbsent('wordContent', () => <String, dynamic>{});
      profile['wordContent'][w['id']] = w;
    }
  });
  Future<void> markStoryPractice(String id, String storyId, String wordId) =>
      _mutate((d) {
        final row = (d['profiles'][id]['stories'] as List).firstWhere(
          (s) => s['id'] == storyId,
        );
        if (!(row['practiced'] as List).contains(wordId)) {
          row['practiced'].add(wordId);
        }
      });

  /// Context practice records evidence, not an automatic vocabulary promotion.
  /// Existing story completion marks remain intact and carry no invented score.
  Future<void> recordStoryRecall(
    String id,
    String storyId,
    String wordId,
    Recall recall,
  ) {
    final now = clock();
    return _mutate((d) {
      final profile = d['profiles'][id];
      final row = (profile['stories'] as List).firstWhere(
        (s) => s['id'] == storyId,
      );
      if (!(row['words'] as List).any((w) => w['id'] == wordId)) {
        throw const ContentException('这道练习不属于当前故事。');
      }
      row.putIfAbsent('practiceResults', () => <String, dynamic>{});
      if ((row['practiceResults'] as Map).containsKey(wordId)) return;
      row['practiceResults'][wordId] = {
        'recall': recall.name,
        'at': now.toIso8601String(),
      };
      if (!(row['practiced'] as List).contains(wordId)) {
        row['practiced'].add(wordId);
      }
      _logPractice(profile, {
        'wordId': wordId,
        'kind': 'context',
        'storyId': storyId,
        'recall': recall.name,
        'independent': recall == Recall.good || recall == Recall.easy,
        'at': now.toIso8601String(),
      });
    });
  }
}
