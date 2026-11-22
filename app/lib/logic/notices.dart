// Turns the changing list of alerts into notification events: one when a
// problem starts, one when a serious problem clears. Pure Dart, unit-tested.

import 'alerts.dart';

class Notice {
  const Notice({
    required this.key,
    required this.severity,
    required this.title,
    required this.body,
    required this.at,
    this.resolved = false,
  });

  /// Stable per problem (the alert title), so the phone replaces an old
  /// notification about the same problem instead of stacking them.
  final String key;
  final Severity severity;
  final String title;
  final String body;
  final DateTime at;

  /// True for "problem is fixed" events.
  final bool resolved;

  @override
  String toString() => '${resolved ? 'resolved' : 'raised'} $severity: $title';
}

/// What to say when a serious problem clears.
const _resolvedText = {
  'Controller offline': ('Controller back online', 'Readings and controls are live again.'),
  'No data from the controller yet': ('Controller connected', 'The first readings arrived.'),
  'Water too low: pumps stopped': ('Water level OK', 'The pumps can run again.'),
  'Phone has no internet': ('Phone back online', 'The app can reach the farm again.'),
};

/// Remembers which alerts were active and reports what changed.
class AlertTracker {
  AlertTracker({this.cooldown = const Duration(minutes: 10)});

  /// A problem that clears and comes back within this time is not announced
  /// again, so a reading wobbling around a threshold does not spam the phone.
  final Duration cooldown;

  final Map<String, FarmAlert> _active = {};
  final Map<String, DateTime> _lastRaised = {};

  List<Notice> update(List<FarmAlert> alerts, DateTime now) {
    final out = <Notice>[];
    final current = {for (final a in alerts) a.title: a};

    for (final a in alerts) {
      if (a.severity.index < Severity.warning.index) continue;
      if (_active.containsKey(a.title)) continue;
      final last = _lastRaised[a.title];
      if (last == null || now.difference(last) >= cooldown) {
        out.add(Notice(key: a.title, severity: a.severity, title: a.title, body: a.message, at: now));
        _lastRaised[a.title] = now;
      }
    }

    for (final old in _active.values) {
      if (current.containsKey(old.title)) continue;
      final text = _resolvedText[old.title];
      if (old.severity == Severity.critical && text != null) {
        out.add(Notice(
          key: old.title,
          severity: Severity.ok,
          title: text.$1,
          body: text.$2,
          at: now,
          resolved: true,
        ));
        // A fresh failure right after recovery is worth announcing.
        _lastRaised.remove(old.title);
      }
    }

    _active
      ..clear()
      ..addAll({
        for (final a in alerts)
          if (a.severity.index >= Severity.warning.index) a.title: a,
      });
    return out;
  }
}
