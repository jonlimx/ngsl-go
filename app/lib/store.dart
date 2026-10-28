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
  }) => _mutate((d) {
    final row = (d['learners'] as List).firstWhere((p) => p['id'] == id);
    if (dailyNew != null) row['dailyNew'] = dailyNew.clamp(0, 20);
    if (topic != null) row['topic'] = topic;
    if (accent != null) row['accent'] = accent;
  });
  Future<void> setModel(String value) => _mutate((d) => d['model'] = value);

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
    if ((plan == null || (plan['done'] as List).isEmpty) && !hasStory) {
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
  Future<void> review(
    String id,
    String wordId,
    Recall recall,
    String planDay,
  ) => _mutate((d) {
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
    profile['progress'][wordId] = scheduleReview(p, recall, today);
    if (recall != Recall.again) plan['done'].add(wordId);
  });
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
}
