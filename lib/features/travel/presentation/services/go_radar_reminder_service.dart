import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ─── Constantes ───────────────────────────────────────────────────────────────

const String _channelId = 'go_radar_reminder';
const String _channelName = 'GO Radar — Rappels reporter';

// IDs réservés : 9100 à 9139 (40 rappels max planifiables)
const int _baseId = 9100;
const int _maxSlots = 100;

// ─── Service ──────────────────────────────────────────────────────────────────

/// Planifie des notifications locales périodiques pour rappeler au reporter
/// de mettre à jour GO Radar. Fonctionne même si l'app est en arrière-plan.
///
/// Stratégie : on pré-planifie [_maxSlots] notifications espacées de
/// [intervalMinutes] minutes. Ça couvre jusqu'à 40 × 30 min = 20 heures,
/// largement suffisant pour un trajet.
class GoRadarReminderService {
  GoRadarReminderService._();
  static final GoRadarReminderService instance = GoRadarReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── Initialisation ─────────────────────────────────────────────────────────

  Future<void> initialize() => _ensureInitialized();

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    _initialized = true;
  }

  // ── API publique ──────────────────────────────────────────────────────────

  /// Active le rappel toutes les [intervalMinutes] minutes.
  /// Annule les rappels précédents avant de replanifier.
  Future<void> start({required int intervalMinutes}) async {
    await _ensureInitialized();
    await cancelAll();

    await _requestPermissions();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: false,
        color: Color(0xFF0F766E),
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    for (int i = 1; i <= _maxSlots; i++) {
      final tz.TZDateTime scheduledTime = now.add(
        Duration(minutes: intervalMinutes * i),
      );
      await _plugin.zonedSchedule(
        _baseId + i,
        'GO Radar — Mise à jour requise',
        'N\'oublie pas de mettre à jour le statut du voyage !',
        scheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }

    debugPrint(
      '[GoRadarReminder] $_maxSlots rappels planifiés toutes les ${intervalMinutes}min',
    );
  }

  /// Annule tous les rappels GO Radar.
  Future<void> cancelAll() async {
    await _ensureInitialized();
    for (int i = 1; i <= _maxSlots; i++) {
      await _plugin.cancel(_baseId + i);
    }
    debugPrint('[GoRadarReminder] Tous les rappels annulés');
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    // Android : notification + alarmes exactes
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
      return;
    }

    // iOS : demande alert + sound si pas encore accordé
    final IOSFlutterLocalNotificationsPlugin? iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, sound: true);
  }
}
