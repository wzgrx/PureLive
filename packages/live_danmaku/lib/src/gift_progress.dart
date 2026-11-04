import 'package:live_core/live_core.dart';

/// Monotonic explicit gift-group snapshots, scoped to one connection run.
/// Used only by protocols whose group id identifies one cumulative delivery.
final class GiftSnapshotGate {
  /// A bounded recent-group window; ordinary reconnects retain the same gate.
  new({this.capacity = 512}) : assert(capacity > 0, 'capacity must be positive');

  /// Maximum groups retained.
  final int capacity;
  final Map<String, int> _totals = {};

  /// Current bounded group count.
  int get length => _totals.length;

  /// Drop repeated, terminating or out-of-order snapshots of a known total.
  bool accept(LiveMessage message) {
    final gift = message.gift;
    if (message.type != LiveMessageType.gift || gift == null || gift.comboKey.isEmpty) return true;
    final total = gift.comboTotal ?? gift.count;
    final before = _totals.remove(gift.comboKey);
    _totals[gift.comboKey] = before != null && before > total ? before : total;
    while (_totals.length > capacity) {
      _totals.remove(_totals.keys.first);
    }
    return before == null || total > before;
  }

  /// A new broadcast must never inherit the previous one's groups.
  void clear() => _totals.clear();
}
