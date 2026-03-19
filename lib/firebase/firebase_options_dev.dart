import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DevFirebaseOptions are not configured for ${defaultTargetPlatform.name}. '
          'Add options for your platform in lib/firebase/firebase_options_dev.dart.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDnQVLwpz8PMKl9yEMGoRcikHD60J2HEU8',
    appId: '1:144316183618:ios:c3a2d57d9ec38ceba5e9db',
    messagingSenderId: '144316183618',
    projectId: 'govip-dev',
    storageBucket: 'govip-dev.firebasestorage.app',
    iosBundleId: 'com.govipservices',
    iosClientId:
        '144316183618-4orf4trllcmi6c98ovovld17ldlj197e.apps.googleusercontent.com',
  );
}
