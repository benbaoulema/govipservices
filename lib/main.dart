import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:govipservices/app/app.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/firebase/firebase_env.dart';
import 'package:govipservices/firebase/firebase_options_dev.dart';
import 'package:govipservices/firebase/firebase_options_prod.dart';
import 'package:govipservices/features/notifications/presentation/fcm_service.dart';
import 'package:govipservices/features/travel/presentation/services/go_radar_reminder_service.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeAppConfig.initialize();
  bool firebaseReady = false;
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
    } else {
      final AppEnvironment env = AppEnvironment.current;
      final FirebaseOptions options = switch (env) {
        AppEnvironment.dev => DevFirebaseOptions.currentPlatform,
        AppEnvironment.prod => ProdFirebaseOptions.currentPlatform,
      };
      await Firebase.initializeApp(
        options: options,
      );
    }
    firebaseReady = true;
  } catch (error, stackTrace) {
    debugPrint('Firebase init skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  // Initialise le service de rappels GO Radar (timezone + plugin)
  unawaited(
    GoRadarReminderService.instance.initialize().catchError(
      (Object error) => debugPrint('GoRadarReminder init skipped: $error'),
    ),
  );

  VoyageBookingService.useCloudFunction = true;
  runApp(const GoVipApp());
  if (firebaseReady) {
    unawaited(
      FcmService.instance.initialize().catchError((Object error, StackTrace stackTrace) {
        debugPrint('FCM init skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
  }
}
