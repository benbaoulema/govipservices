import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RuntimeAppConfig {
  RuntimeAppConfig._();

  static const MethodChannel _channel =
      MethodChannel('govipservices/runtime_config');
  static const String _compileTimeGoogleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static String _googleMapsApiKey = _compileTimeGoogleMapsApiKey;

  static String get googleMapsApiKey => _googleMapsApiKey;

  static Future<void> initialize() async {
    if (_googleMapsApiKey.trim().isNotEmpty || kIsWeb) return;

    final TargetPlatform platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return;
    }

    try {
      final String? nativeKey =
          await _channel.invokeMethod<String>('getGoogleMapsApiKey');
      if (nativeKey != null && nativeKey.trim().isNotEmpty) {
        _googleMapsApiKey = nativeKey.trim();
      }
    } catch (error, stackTrace) {
      debugPrint('RuntimeAppConfig init skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
