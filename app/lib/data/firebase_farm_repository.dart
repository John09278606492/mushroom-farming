import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';

import '../models/farm_models.dart';
import 'farm_repository.dart';

/// The real farm, through Firebase Realtime Database (docs/firebase-schema.md).
class FirebaseFarmRepository implements FarmRepository {
  FirebaseFarmRepository({this.farmId = 'farm1', FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;

  final String farmId;
  final FirebaseDatabase _db;

  DatabaseReference get _root => _db.ref(farmId);

  @override
  String get farmName => farmId;

  @override
  bool get isDemo => false;

  @override
  Stream<LiveData> watchLive() =>
      _root.child('live').onValue.map((e) => LiveData.fromMap(e.snapshot.value));

  @override
  Stream<ControlState> watchControl() =>
      _root.child('control').onValue.map((e) => ControlState.fromMap(e.snapshot.value));

  @override
  Stream<Setpoints> watchSetpoints() =>
      _root.child('setpoints').onValue.map((e) => Setpoints.fromMap(e.snapshot.value));

  @override
  Stream<ScheduleTable> watchSchedules() =>
      _root.child('schedules').onValue.map((e) => parseSchedules(e.snapshot.value));

  @override
  Stream<List<HistoryPoint>> watchHistory(Duration range) {
    final since = DateTime.now().subtract(range).millisecondsSinceEpoch;
    return _root
        .child('history')
        .orderByChild('ts')
        .startAt(since)
        .onValue
        .map((e) {
      final points = <HistoryPoint>[];
      for (final child in e.snapshot.children) {
        final p = HistoryPoint.fromMap(child.value);
        if (p != null) points.add(p);
      }
      points.sort((a, b) => a.ts.compareTo(b.ts));
      return points;
    });
  }

  @override
  Stream<CameraShot?> watchCamera() =>
      _root.child('camera/latest').onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return null;
        final ts = v['ts'];
        final image = v['image'];
        if (ts is! num || image is! String || image.isEmpty) return null;
        try {
          // Tolerate a "data:image/jpeg;base64," prefix.
          final b64 = image.contains(',') ? image.split(',').last : image;
          return CameraShot(
            ts: DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
            jpeg: base64Decode(b64),
          );
        } on FormatException {
          return null;
        }
      });

  @override
  Stream<HarvestResult?> watchHarvest() => _root
      .child('harvest/latest')
      .onValue
      .map((e) => HarvestResult.fromMap(e.snapshot.value));

  @override
  Stream<List<Batch>> watchBatches() => _root.child('batches').onValue.map((e) {
        final list = <Batch>[];
        for (final child in e.snapshot.children) {
          final b = Batch.fromMap(child.key ?? '', child.value);
          if (b != null) list.add(b);
        }
        list.sort((a, b) => b.pinnedAt.compareTo(a.pinnedAt));
        return list;
      });

  @override
  Stream<bool> watchConnection() =>
      _db.ref('.info/connected').onValue.map((e) => e.snapshot.value == true);

  @override
  Future<void> setMode(FarmMode mode) => _root.child('control').update({
        'mode': mode.name,
        // The controller acts when this time changes, so a tap is never
        // missed and an old value is never replayed after a reboot.
        'modeAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

  @override
  Future<void> setDevice(DeviceId device, bool on) => _root.child('control').update({
        'devices/${device.key}': on,
        'at/${device.key}': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

  @override
  Future<void> saveSetpoints(Setpoints sp) {
    final error = sp.validate();
    if (error != null) throw ArgumentError(error);
    return _root.child('setpoints').set({...sp.toMap(), 'updatedAt': ServerValue.timestamp});
  }

  @override
  Future<void> saveSchedule(ScheduleDevice device, int slot, Schedule? schedule) {
    RangeError.checkValueInInterval(slot, 0, maxScheduleSlots - 1, 'slot');
    final ref = _root.child('schedules/${device.key}/$slot');
    return schedule == null ? ref.remove() : ref.set(schedule.toMap(device));
  }

  @override
  Future<void> startBatch() => _root.child('batches').push().set({
        'pinnedAt': ServerValue.timestamp,
        'notes': '',
      });

  @override
  Future<void> finishBatch(String batchId, {double? weightG, String notes = ''}) =>
      _root.child('batches/$batchId').update({
        'harvestedAt': ServerValue.timestamp,
        'weightG': weightG,
        'notes': notes,
      });

  @override
  void dispose() {}
}
