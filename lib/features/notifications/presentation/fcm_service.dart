import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/features/notifications/data/push_token_repository.dart';
import 'package:govipservices/features/notifications/presentation/notification_navigation.dart';
const String _foregroundChannelId = 'foreground_notifications';
const String _foregroundChannelName = 'Foreground notifications';
const String _driverOrdersChannelId = 'driver_new_orders_v1';
const String _driverOrdersChannelName = 'Nouvelles commandes chauffeur';
const String _driverOrderSoundName = 'driver_order_alert';
const int _maxAndroidNotificationId = 2147483647;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized depending on platform state.
  }
}

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final PushTokenRepository _pushTokenRepository = PushTokenRepository();
  final NotificationNavigation _notificationNavigation = NotificationNavigation();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
    await _initializeLocalNotifications();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _syncCurrentTokenForUser(user);
    });

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      final User? user = FirebaseAuth.instance.currentUser;
      final String installationId =
          await _pushTokenRepository.getOrCreateInstallationId();
      await _syncTokenBinding(
        installationId: installationId,
        token: token,
        currentUserId: user?.uid,
      );
    });

    await _syncCurrentTokenForUser(FirebaseAuth.instance.currentUser);

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleOpenedMessage(initialMessage);
      });
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _initialized = false;
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidInitializationSettings,
        iOS: iosInitializationSettings,
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _handleBackgroundLocalNotificationResponse,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _foregroundChannelId,
        _foregroundChannelName,
        description: 'Displays notifications received while the app is open.',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _driverOrdersChannelId,
        _driverOrdersChannelName,
        description:
            'Alertes prioritaires pour les nouvelles commandes chauffeur.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound(_driverOrderSoundName),
      ),
    );
    // Canal pour la notification persistante de course en cours
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'delivery_ongoing',
        'Course en cours',
        description: 'Suivi de votre livraison en temps réel.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
  }

  Future<void> _syncCurrentTokenForUser(User? user) async {
    final String? token;
    try {
      token = await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
      return;
    }
    if (token == null || token.trim().isEmpty) return;
    final String installationId =
        await _pushTokenRepository.getOrCreateInstallationId();
    await _syncTokenBinding(
      installationId: installationId,
      token: token,
      currentUserId: user?.uid,
    );
  }

  Future<void> _syncTokenBinding({
    required String installationId,
    required String token,
    required String? currentUserId,
  }) async {
    final String normalizedCurrentUserId = (currentUserId ?? '').trim();

    if (normalizedCurrentUserId.isNotEmpty) {
      await _pushTokenRepository.upsertInstallation(
        installationId: installationId,
        token: token,
        userId: normalizedCurrentUserId,
      );
      return;
    }

    await _pushTokenRepository.upsertInstallation(
      installationId: installationId,
      token: token,
    );
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    final BuildContext? context = rootNavigatorKey.currentContext;
    if (context == null) return;

    final String? info = await _notificationNavigation.openFromPayload(
      context,
      message.data,
    );
    if (info != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(info),
          ),
        );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final String title = message.notification?.title?.trim().isNotEmpty == true
        ? message.notification!.title!.trim()
        : '${message.data['title'] ?? ''}'.trim();
    final String body = message.notification?.body?.trim().isNotEmpty == true
        ? message.notification!.body!.trim()
        : '${message.data['body'] ?? ''}'.trim();
    final bool isDriverOrder =
        '${message.data['type'] ?? ''}'.trim() == 'parcel_request_created';

    if (title.isEmpty && body.isEmpty) return;

    await _localNotifications.show(
      _foregroundNotificationId(message),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isDriverOrder ? _driverOrdersChannelId : _foregroundChannelId,
          isDriverOrder ? _driverOrdersChannelName : _foregroundChannelName,
          channelDescription: isDriverOrder
              ? 'Alertes prioritaires pour les nouvelles commandes chauffeur.'
              : 'Displays notifications received while the app is open.',
          importance: isDriverOrder ? Importance.max : Importance.high,
          priority: isDriverOrder ? Priority.max : Priority.high,
          playSound: isDriverOrder,
          enableVibration: isDriverOrder,
          sound: isDriverOrder
              ? const RawResourceAndroidNotificationSound(
                  _driverOrderSoundName,
                )
              : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: isDriverOrder ? '$_driverOrderSoundName.aiff' : null,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  int _foregroundNotificationId(RemoteMessage message) {
    final int seed =
        message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch;
    return seed & _maxAndroidNotificationId;
  }

  Future<void> _openFromPayload(Map<String, dynamic> payload) async {
    final BuildContext? context = rootNavigatorKey.currentContext;
    if (context == null) return;

    final String? info = await _notificationNavigation.openFromPayload(
      context,
      payload,
    );
    if (info != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(info),
          ),
        );
    }
  }

  Future<void> _handleLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    final String? payload = response.payload;
    if (payload == null || payload.trim().isEmpty) return;

    final Object? decoded = jsonDecode(payload);
    if (decoded is! Map) return;

    final Map<String, dynamic> normalizedPayload = decoded.map(
      (key, value) => MapEntry('$key', value),
    );
    await _openFromPayload(normalizedPayload);
  }
}

@pragma('vm:entry-point')
void _handleBackgroundLocalNotificationResponse(NotificationResponse response) {
  FcmService.instance._handleLocalNotificationResponse(response);
}
