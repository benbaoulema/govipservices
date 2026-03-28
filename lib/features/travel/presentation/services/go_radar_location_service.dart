import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';

/// Service GPS automatique pour GO Radar.
///
/// Toutes les [intervalMinutes] minutes, capture la position GPS une seule fois
/// et l'envoie silencieusement à Firestore — économique en batterie et en écritures.
/// Survit à la fermeture de la page (app minimisée) mais s'arrête quand
/// l'app est tuée ou quand [stop] est appelé explicitement.
class GoRadarLocationService {
  GoRadarLocationService._();

  static final GoRadarLocationService instance = GoRadarLocationService._();

  final GoRadarRepository _repo = GoRadarRepository();

  Timer? _timer;
  String? _sessionId;

  bool get isRunning => _timer != null;
  String? get currentSessionId => _sessionId;

  /// Démarre le suivi GPS périodique pour [sessionId].
  /// [intervalMinutes] : intervalle entre deux envois (défaut 10 min).
  void start({
    required String sessionId,
    int intervalMinutes = 10,
  }) {
    stop(); // annule tout timer précédent
    _sessionId = sessionId;

    // Envoi immédiat au démarrage
    _pushPosition();

    // Puis toutes les [intervalMinutes] minutes
    _timer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => _pushPosition(),
    );
  }

  Future<void> _pushPosition() async {
    if (_sessionId == null) return;
    try {
      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await _repo.pushLocationUpdate(
        sessionId: _sessionId!,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (_) {
      // Échec GPS ou réseau → on ignore, on réessaiera au prochain tick
    }
  }

  /// Arrête le suivi GPS.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _sessionId = null;
  }
}
