import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Prod Firebase options are not configured for ${defaultTargetPlatform.name}. '
      'Generate with: flutterfire configure --project=<PROD_PROJECT_ID> --out=lib/firebase/firebase_options_prod.dart',
    );
  }
}
