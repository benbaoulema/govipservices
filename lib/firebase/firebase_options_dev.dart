import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Dev Firebase options are not configured for ${defaultTargetPlatform.name}. '
      'Generate with: flutterfire configure --project=<DEV_PROJECT_ID> --out=lib/firebase/firebase_options_dev.dart',
    );
  }
}
