import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/models/farm_models.dart';

void main() {
  group('LiveData.fromMap', () {
    test('parses a full firmware payload', () {
      final live = LiveData.fromMap({
        'updatedAt': 1700000000000,
        'temp': 26.4,
        'rh': 88,
        'co2': 750,
        'lowWater': false,
        'waterCutoff': true,
        'mode': 'manual',
        'devices': {'mist': true, 'fan': 1, 'light': false},
        'rssi': -61,
      });
      expect(live.updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(live.rh, 88.0);
      expect(live.co2, 750);
      expect(live.waterCutoff, isTrue);
      expect(live.mode, FarmMode.manual);
      expect(live.deviceOn(DeviceId.mist), isTrue);
      expect(live.deviceOn(DeviceId.fan), isTrue);
      expect(live.deviceOn(DeviceId.refill), isFalse);
    });

    test('treats co2 -1 as no reading and missing cutoff as not installed', () {
      final live = LiveData.fromMap({'updatedAt': 1, 'co2': -1});
      expect(live.co2, isNull);
      expect(live.waterCutoff, isNull);
    });

    test('null or junk gives empty data', () {
      expect(LiveData.fromMap(null).hasData, isFalse);
      expect(LiveData.fromMap('x').hasData, isFalse);
    });

    test('online only when updated within 30 s', () {
      final now = DateTime(2026, 11, 17, 12);
      final live = LiveData(updatedAt: now.subtract(const Duration(seconds: 10)));
      expect(live.isOnline(now), isTrue);
      expect(live.isOnline(now.add(const Duration(seconds: 25))), isFalse);
    });
  });

  group('Setpoints', () {
    test('defaults to fruiting when the node is empty', () {
      expect(Setpoints.fromMap(null), Setpoints.fruiting);
    });

    test('round-trips through toMap', () {
      final sp = Setpoints.spawnRun.copyWith(humOn: 72);
      expect(Setpoints.fromMap(sp.toMap()), sp);
    });

    test('validate catches inverted ranges', () {
      expect(Setpoints.fruiting.validate(), isNull);
      expect(Setpoints.fruiting.copyWith(humOn: 96).validate(), contains('Mist'));
      expect(Setpoints.fruiting.copyWith(co2Off: 900).validate(), contains('Fan'));
      expect(Setpoints.fruiting.copyWith(tempMin: 30).validate(), contains('temperature'));
    });
  });

  group('Schedules', () {
    test('parses Firebase list form with empty slots', () {
      // RTDB turns {0: ..., 2: ...} into [a, null, b].
      final table = parseSchedules({
        'sprinkler': [
          {'enabled': true, 'hour': 8, 'minute': 0, 'durationMin': 3, 'days': List.filled(7, true)},
          null,
          {'enabled': false, 'hour': 14, 'minute': 30, 'durationMin': 5, 'days': [false, true, true, true, true, true, false]},
        ],
        'light': {
          '0': {'enabled': true, 'hour': 6, 'minute': 0, 'durationHr': 12, 'days': List.filled(7, true)},
        },
      });
      final spr = table[ScheduleDevice.sprinkler]!;
      expect(spr[0]!.duration, 3);
      expect(spr[1], isNull);
      expect(spr[2]!.enabled, isFalse);
      expect(spr[2]!.daysLabel, 'Mon–Fri');
      expect(table[ScheduleDevice.light]![0]!.duration, 12);
      expect(table[ScheduleDevice.light]![1], isNull);
    });

    test('toMap uses minutes for sprinkler and hours for light', () {
      final s = Schedule.newFor(ScheduleDevice.light);
      expect(s.toMap(ScheduleDevice.light).containsKey('durationHr'), isTrue);
      expect(s.toMap(ScheduleDevice.sprinkler).containsKey('durationMin'), isTrue);
      expect(Schedule.fromMap(s.toMap(ScheduleDevice.light), ScheduleDevice.light), s);
    });

    test('daysLabel', () {
      final s = Schedule.newFor(ScheduleDevice.sprinkler);
      expect(s.daysLabel, 'Every day');
      expect(s.copyWith(days: [true, false, false, true, false, false, false]).daysLabel, 'Sun, Wed');
    });
  });

  test('Batch day number starts at 1', () {
    final b = Batch(id: 'x', pinnedAt: DateTime(2026, 11, 10, 9));
    expect(b.dayNumber(DateTime(2026, 11, 10, 20)), 1);
    expect(b.dayNumber(DateTime(2026, 11, 15, 10)), 6);
    expect(b.isOpen, isTrue);
  });
}
