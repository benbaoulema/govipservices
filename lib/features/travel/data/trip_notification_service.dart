import 'package:cloud_functions/cloud_functions.dart';

class TripNotificationService {
  TripNotificationService._();
  static final TripNotificationService instance = TripNotificationService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Envoie une notification push à tous les passagers d'un voyage.
  ///
  /// [tripId]  — ID du voyage
  /// [title]   — Titre de la notification
  /// [body]    — Corps du message
  /// [type]    — Type (défaut : `trip_updated`)
  /// [data]    — Données extra optionnelles
  ///
  /// Retourne le nombre de passagers notifiés.
  Future<int> notifyPassengers({
    required String tripId,
    required String title,
    required String body,
    String type = 'trip_updated',
    Map<String, String> data = const {},
  }) async {
    final HttpsCallable callable =
        _functions.httpsCallable('notifyTripPassengers');

    final HttpsCallableResult result = await callable.call(<String, dynamic>{
      'tripId': tripId,
      'title': title,
      'body': body,
      'type': type,
      if (data.isNotEmpty) 'data': data,
    });

    return (result.data['sent'] as num? ?? 0).toInt();
  }
}
