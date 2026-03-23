import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SafeWakelockService {
  const SafeWakelockService._();

  static Future<void> setEnabled(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Wakelock indisponible: $error');
      debugPrintStack(stackTrace: stackTrace);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Wakelock indisponible: ${error.message ?? error.code}');
      debugPrintStack(stackTrace: stackTrace);
    } catch (error, stackTrace) {
      debugPrint('Echec wakelock: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
