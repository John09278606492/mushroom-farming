import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/logic/alerts.dart';
import 'package:mushroom_farm/logic/notices.dart';

void main() {
  final t0 = DateTime(2026, 11, 22, 8);
  const offline = FarmAlert(Severity.critical, 'Controller offline', 'old');
  const humid = FarmAlert(Severity.warning, 'Humidity is low', '80%');
  const info = FarmAlert(Severity.info, 'Something minor', '');

  test('announces a new problem once while it lasts', () {
    final tr = AlertTracker();
    expect(tr.update([offline], t0).map((n) => n.title), ['Controller offline']);
    expect(tr.update([offline], t0.add(const Duration(seconds: 1))), isEmpty);
    expect(tr.update([offline], t0.add(const Duration(minutes: 30))), isEmpty);
  });

  test('ignores info-level alerts', () {
    expect(AlertTracker().update([info], t0), isEmpty);
  });

  test('announces recovery of a critical problem', () {
    final tr = AlertTracker()..update([offline], t0);
    final out = tr.update([], t0.add(const Duration(minutes: 1)));
    expect(out.single.title, 'Controller back online');
    expect(out.single.resolved, isTrue);
  });

  test('warnings clear silently and do not repeat within the cooldown', () {
    final tr = AlertTracker()..update([humid], t0);
    expect(tr.update([], t0.add(const Duration(minutes: 1))), isEmpty);
    expect(tr.update([humid], t0.add(const Duration(minutes: 2))), isEmpty);
    tr.update([], t0.add(const Duration(minutes: 3)));
    expect(tr.update([humid], t0.add(const Duration(minutes: 15))).single.title, 'Humidity is low');
  });

  test('a critical problem that returns right after recovery is announced again', () {
    final tr = AlertTracker()..update([offline], t0);
    tr.update([], t0.add(const Duration(minutes: 1)));
    expect(tr.update([offline], t0.add(const Duration(minutes: 2))).single.title, 'Controller offline');
  });
}
