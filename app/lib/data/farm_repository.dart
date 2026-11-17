import '../models/farm_models.dart';

/// Everything the app reads from and writes to the farm.
///
/// Two implementations:
/// - [FirebaseFarmRepository]: the real farm through Firebase Realtime DB.
/// - [DemoFarmRepository]: a simulated farm for testing and thesis demos.
abstract class FarmRepository {
  /// Shown in the UI, e.g. "farm1" or "Demo farm".
  String get farmName;
  bool get isDemo;

  Stream<LiveData> watchLive();
  Stream<ControlState> watchControl();
  Stream<Setpoints> watchSetpoints();
  Stream<ScheduleTable> watchSchedules();
  Stream<List<HistoryPoint>> watchHistory(Duration range);
  Stream<CameraShot?> watchCamera();
  Stream<HarvestResult?> watchHarvest();
  Stream<List<Batch>> watchBatches();

  /// Whether this phone is connected to the database (not the farm).
  Stream<bool> watchConnection();

  Future<void> setMode(FarmMode mode);
  Future<void> setDevice(DeviceId device, bool on);
  Future<void> saveSetpoints(Setpoints sp);

  /// [schedule] null clears the slot.
  Future<void> saveSchedule(ScheduleDevice device, int slot, Schedule? schedule);

  Future<void> startBatch();
  Future<void> finishBatch(String batchId, {double? weightG, String notes = ''});

  void dispose();
}
