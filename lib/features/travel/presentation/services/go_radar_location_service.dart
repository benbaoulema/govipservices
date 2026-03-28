import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';

/// Service GPS automatique pour GO Radar.
///
/// Démarre un stream de position dès qu'une session est ouverte et envoie
/// silencieusement les coordonnées à Firestore à chaque déplacement significatif.
/// Survit à la fermeture de la page (app minimisée) mais s'arrête quand
/// l'app est tuée ou quand [stop] est appelé explicitement.
class GoRadarLocationService {
  GoRadarLocationService._();

  static final GoRadarLocationService instance = GoRadarLocationService._();

  final GoRadarRepository _repo = GoRadarRepository();

  StreamSubscription<Position>? _sub;
  String? _sessionId;

  bool get isRunning => _sub != null;
  String? get currentSessionId => _sessionId;

  /// Démarre le suivi GPS pour [sessionId].
  /// [distanceFilter] : distance minimale (mètres) entre deux envois.
  void start({
    required String sessionId,
    int distanceFilter = 20,
  }) {
    stop(); // annule tout stream précédent
    _sessionId = sessionId;

    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen(
      (Position pos) async {
        if (_sessionId == null) return;
        try {
          await _repo.pushLocationUpdate(
            sessionId: _sessionId!,
            lat: pos.latitude,
            lng: pos.longitude,
          );
        } catch (_) {
          // Échec réseau → on ignore silencieusement, on réessaiera au prochain event
        }
      },
      onError: (_) {}, // GPS indisponible temporairement → on continue
      cancelOnError: false,
    );
  }

  /// Arrête le suivi GPS.
  void stop() {
    _sub?.cancel();
    _sub = null;
    _sessionId = null;
  }
}
