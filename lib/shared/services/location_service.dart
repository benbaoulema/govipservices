import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationResult {
  const LocationResult({required this.address, required this.position});
  final String address;
  final Position position;
}

/// Singleton qui résout la position GPS une seule fois au démarrage de l'app
/// et met le résultat en cache pour toutes les pages qui en ont besoin.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  LocationResult? _cached;
  Future<LocationResult?>? _resolveFuture;

  /// Résultat déjà en cache, ou null si pas encore disponible.
  LocationResult? get cached => _cached;

  /// Adresse mise en cache (raccourci).
  String? get cachedAddress => _cached?.address;

  /// Lance la résolution en arrière-plan au démarrage de l'app.
  /// Idempotent : plusieurs appels ne déclenchent qu'une seule résolution.
  void warmup() {
    _resolveFuture ??= _resolve().then((result) {
      _cached = result;
      return result;
    });
  }

  /// Retourne le résultat mis en cache, ou attend la résolution en cours.
  /// Si aucune résolution n'a été lancée, en lance une maintenant.
  Future<LocationResult?> getCurrent() async {
    if (_cached != null) return _cached;
    warmup();
    return _resolveFuture;
  }

  Future<LocationResult?> _resolve() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final Placemark? first = placemarks.isNotEmpty ? placemarks.first : null;
      final String address = <String?>[
        first?.street,
        first?.subLocality,
        first?.locality,
        first?.country,
      ]
          .whereType<String>()
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(', ');

      final String resolved = address.trim().isEmpty
          ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'
          : address;

      return LocationResult(address: resolved, position: position);
    } catch (e) {
      debugPrint('[LocationService] Erreur résolution position: $e');
      return null;
    }
  }
}
