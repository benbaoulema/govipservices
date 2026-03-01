import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:govipservices/app/app.dart';
import 'package:govipservices/firebase/firebase_env.dart';
import 'package:govipservices/firebase/firebase_options_dev.dart';
import 'package:govipservices/firebase/firebase_options_prod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  } catch (error, stackTrace) {
    debugPrint('Firebase init skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  runApp(const GoVipApp());
}
