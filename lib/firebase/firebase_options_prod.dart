import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'ProdFirebaseOptions are not configured for ${defaultTargetPlatform.name}. '
          'Add options for your platform in lib/firebase/firebase_options_prod.dart.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBYPhJq8rsmf1SQ1LA1bDfIigimXypFNFE',
    appId: '1:1006528966043:ios:204bacfbb51024d93b453e',
    messagingSenderId: '1006528966043',
    projectId: 'domestic-48f40',
    storageBucket: 'domestic-48f40.firebasestorage.app',
    iosBundleId: 'com.govipservices',
  );
}
