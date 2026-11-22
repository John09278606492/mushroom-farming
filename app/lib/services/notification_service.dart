import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/alerts.dart';
import '../logic/notices.dart';

/// Shows farm alerts as phone (or browser) notifications.
///
/// These work while the app is open or in the background. A notification
/// when the app is fully closed needs Firebase Cloud Messaging from a server,
/// which comes with the Firebase setup.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;

  bool _ready = false;
  bool _allowed = false;

  /// The plugin started on this platform.
  bool get ready => _ready;

  /// The phone/browser lets us show notifications.
  bool get allowed => _allowed;

  bool get enabled => _prefs?.getBool('notify.enabled') ?? true;
  bool get criticalOnly => _prefs?.getBool('notify.criticalOnly') ?? false;

  /// Whether a notice will reach the system tray right now.
  bool get canShow => _ready && _allowed && enabled;

  static const _critical = AndroidNotificationDetails(
    'farm_critical',
    'Critical farm problems',
    channelDescription: 'Controller offline, water cut-off, phone offline',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
  );
  static const _warning = AndroidNotificationDetails(
    'farm_warnings',
    'Farm warnings',
    channelDescription: 'Readings out of range, sensors not reading, low water',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _update = AndroidNotificationDetails(
    'farm_updates',
    'Problem fixed',
    channelDescription: 'A serious problem cleared',
    importance: Importance.defaultImportance,
  );
  static const _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentList: true,
    presentSound: true,
  );

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Preferences unavailable: $e');
    }
    try {
      _ready = await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              web: WebInitializationSettings(),
            ),
          ) ??
          false;
      _allowed = await _checkAllowed();
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      _ready = false;
    }
    notifyListeners();
  }

  Future<bool> _checkAllowed() async {
    if (kIsWeb) {
      return _plugin
              .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
              ?.permissionStatus ==
          WebNotificationPermission.granted;
    }
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.areNotificationsEnabled() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final o = await ios.checkPermissions();
      return o?.isEnabled ?? false;
    }
    return false;
  }

  /// Asks the user. In a browser this must follow a tap.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      bool? ok;
      if (kIsWeb) {
        ok = await _plugin
            .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        ok = await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        ok = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      _allowed = ok ?? await _checkAllowed();
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
    notifyListeners();
    return _allowed;
  }

  Future<void> setEnabled(bool v) async {
    await _prefs?.setBool('notify.enabled', v);
    notifyListeners();
    if (v && !_allowed) await requestPermission();
  }

  Future<void> setCriticalOnly(bool v) async {
    await _prefs?.setBool('notify.criticalOnly', v);
    notifyListeners();
  }

  /// Whether [n] passes the user's settings.
  bool wants(Notice n) {
    if (!enabled) return false;
    if (criticalOnly && n.severity != Severity.critical && !n.resolved) return false;
    return true;
  }

  /// Returns true when the notice went to the system tray.
  Future<bool> show(Notice n) async {
    if (!canShow || !wants(n)) return false;
    final android = n.resolved
        ? _update
        : n.severity == Severity.critical
            ? _critical
            : _warning;
    try {
      await _plugin.show(
        // Same problem -> same id, so it replaces instead of stacking.
        id: n.key.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(android: android, iOS: _darwin),
      );
      return true;
    } catch (e) {
      debugPrint('Could not show notification: $e');
      return false;
    }
  }

  Future<bool> showTest() => show(Notice(
        key: 'test',
        severity: Severity.critical,
        title: 'Test notification',
        body: 'Farm alerts will look like this.',
        at: DateTime.now(),
      ));
}
