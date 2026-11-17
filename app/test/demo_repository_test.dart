import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/data/demo_farm_repository.dart';
import 'package:mushroom_farm/models/farm_models.dart';
import 'package:mushroom_farm/state/farm_state.dart';

void main() {
  late DateTime now;
  late DemoFarmRepository repo;

  setUp(() {
    now = DateTime(2026, 11, 17, 10, 0, 30);
    repo = DemoFarmRepository(autoTick: false, commandDelay: Duration.zero, clock: () => now);
  });

  tearDown(() => repo.dispose());

  Future<LiveData> latest() => repo.watchLive().first;

  test('starts online in auto mode with a week of history', () async {
    final live = await latest();
    expect(live.isOnline(now), isTrue);
    expect(live.mode, FarmMode.auto);
    final week = await repo.watchHistory(const Duration(days: 7)).first;
    expect(week.length, greaterThan(900));
    final sixHours = await repo.watchHistory(const Duration(hours: 6)).first;
    expect(sixHours.length, lessThan(week.length));
  });

  test('auto mode ignores manual mist command; manual mode obeys it', () async {
    await repo.setMode(FarmMode.auto);
    final before = (await latest()).deviceOn(DeviceId.mist);
    await repo.setDevice(DeviceId.mist, !before);
    expect((await latest()).deviceOn(DeviceId.mist), before);

    await repo.setMode(FarmMode.manual);
    await repo.setDevice(DeviceId.mist, !before);
    expect((await latest()).deviceOn(DeviceId.mist), !before);
  });

  test('sprinkler works in auto mode (schedule device)', () async {
    await repo.setDevice(DeviceId.sprinkler, true);
    expect((await latest()).deviceOn(DeviceId.sprinkler), isTrue);
  });

  test('auto logic turns the fan on when CO2 is high', () async {
    await repo.saveSetpoints(Setpoints.fruiting.copyWith(co2On: 500, co2Off: 450));
    repo.tick();
    expect((await latest()).deviceOn(DeviceId.fan), isTrue);
  });

  test('draining the tank trips the cutoff and blocks the pumps', () async {
    await repo.setMode(FarmMode.manual);
    await repo.setDevice(DeviceId.sprinkler, true);
    repo.drainWater();
    final live = await latest();
    expect(live.waterCutoff, isTrue);
    expect(live.deviceOn(DeviceId.sprinkler), isFalse);
  });

  test('schedule fires at its start minute', () async {
    final s = Schedule.newFor(ScheduleDevice.sprinkler).copyWith(hour: 10, minute: 1, duration: 2);
    await repo.saveSchedule(ScheduleDevice.sprinkler, 4, s);
    now = DateTime(2026, 11, 17, 10, 1, 5);
    repo.tick();
    expect((await latest()).deviceOn(DeviceId.sprinkler), isTrue);
    now = DateTime(2026, 11, 17, 10, 3, 10);
    repo.tick();
    expect((await latest()).deviceOn(DeviceId.sprinkler), isFalse);
  });

  test('rejects invalid setpoints', () {
    expect(() => repo.saveSetpoints(Setpoints.fruiting.copyWith(humOn: 99)), throwsArgumentError);
  });

  test('batches: start and finish', () async {
    final before = await repo.watchBatches().first;
    final open = before.firstWhere((b) => b.isOpen);
    await repo.finishBatch(open.id, weightG: 900);
    var list = await repo.watchBatches().first;
    expect(list.where((b) => b.isOpen), isEmpty);
    expect(list.firstWhere((b) => b.id == open.id).weightG, 900);
    await repo.startBatch();
    list = await repo.watchBatches().first;
    expect(list.where((b) => b.isOpen).length, 1);
  });

  test('FarmState marks a command pending until the controller confirms', () async {
    final state = FarmState(repo, clock: () => now, tickEverySecond: false);
    await pumpEventQueue();
    await state.setMode(FarmMode.manual);
    await pumpEventQueue();
    expect(state.live.mode, FarmMode.manual);
    expect(state.modePending, isFalse);

    final err = await state.setDevice(DeviceId.light, false);
    expect(err, isNull);
    await pumpEventQueue();
    expect(state.isDevicePending(DeviceId.light), isFalse);
    expect(state.live.deviceOn(DeviceId.light), isFalse);
    state.dispose();
  });
}
