import 'models.dart';

/// A small, finite group. Time-based spacing survives route changes via the
/// daily plan; intervening cards add spacing while this group stays open.
class StudyGroup {
  StudyGroup(Iterable<String> candidates)
    : pending = candidates.take(studyGroupSize).toList();

  final List<String> pending;
  final Map<String, int> _lastTurn = {}, _attempts = {};
  int _turn = 0;
  int recalled = 0, introduced = 0;

  String? next(
    DateTime now,
    Map<String, dynamic> plan,
    Map<String, dynamic> progress,
  ) {
    for (final id in pending) {
      if ((plan['done'] as List).contains(id) ||
          progress[id]?['status'] == 'known' ||
          (_attempts[id] ?? 0) >= 3) {
        continue;
      }
      final last = _lastTurn[id];
      if (last != null && _turn - last < 2) continue;
      final ready = practiceReadyAt(plan, id, progress);
      if (ready == null || !now.isBefore(ready)) return id;
    }
    return null;
  }

  void record(String id, {bool exposure = false, bool complete = false}) {
    _turn++;
    _lastTurn[id] = _turn;
    pending.remove(id);
    if (exposure) {
      introduced++;
    } else {
      _attempts[id] = (_attempts[id] ?? 0) + 1;
    }
    if (complete) {
      recalled++;
    } else {
      pending.add(id);
    }
  }
}
