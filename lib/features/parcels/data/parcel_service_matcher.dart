import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_service_match.dart';

class ParcelServiceMatcher {
  ParcelServiceMatcher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Livreur considéré "proche" du départ s'il est dans ce rayon
  static const double _nearbyThresholdMeters = 8000; // 8 km

  // Degrés de latitude correspondants au seuil de proximité
  // 1° lat ≈ 111 km   →   8 km ≈ 0.072°
  static const double _nearbyDelta = 0.072;   // bounding box ~8 km

  final FirebaseFirestore _firestore;

  Future<List<ParcelServiceMatch>> findMatches({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    int limit = 3,
  }) async {
    // ── Requête 1 : livreurs proches (≤ 8 km) ─────────────────────────────
    // Filtre Firestore sur ownerLat (range) + filtre Dart sur ownerLng.
    // Firestore n'autorise qu'un seul champ de range, donc on filtre le lng
    // côté client (les documents ramenés restent limités à la bande lat).
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> nearbyDocs =
        await _queryByLatBand(
      pickupLat: pickupLat,
      delta: _nearbyDelta,
    );

    // ── Requête 2 : tous les services actifs (sans filtre géo) ────────────
    // Permet de trouver les livreurs intercités (ex: déclaré Adjamé→Yamoussoukro
    // mais actuellement à Tingrela). Le matching de zone est fait côté client.
    final Set<String> nearbyIds =
        nearbyDocs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id).toSet();

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> allServiceDocs =
        await _queryAllSearchable();

    // Union sans doublons : les docs proches ont priorité
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> allDocs =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in nearbyDocs)
        d.id: d,
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in allServiceDocs)
        if (!nearbyIds.contains(d.id)) d.id: d,
    };

    // ── Mapping + filtrage ─────────────────────────────────────────────────
    final List<ParcelServiceMatch> matches = allDocs.values
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              _mapServiceToMatch(
            doc: doc,
            pickupAddress: pickupAddress,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            deliveryAddress: deliveryAddress,
            deliveryLat: deliveryLat,
            deliveryLng: deliveryLng,
          ),
        )
        .whereType<ParcelServiceMatch>()
        .where((ParcelServiceMatch m) => m.priorityRank <= 3) // exclure rank 4
        .toList(growable: true);

    matches.sort((ParcelServiceMatch a, ParcelServiceMatch b) {
      final int byRank = a.priorityRank.compareTo(b.priorityRank);
      if (byRank != 0) return byRank;
      return a.distanceToPickupMeters.compareTo(b.distanceToPickupMeters);
    });

    return matches.take(limit).toList(growable: false);
  }

  /// Requête Firestore filtrée sur une bande de latitude autour du pickup.
  /// Le filtre lng est appliqué côté Dart pour rester dans le carré.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryByLatBand({
    required double pickupLat,
    required double delta,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _firestore
        .collection('services')
        .where('status', isEqualTo: 'active')
        .where('search.isSearchable', isEqualTo: true)
        .where('search.ownerLat', isGreaterThanOrEqualTo: pickupLat - delta)
        .where('search.ownerLat', isLessThanOrEqualTo: pickupLat + delta)
        .get();
    return snap.docs;
  }

  /// Tous les services actifs et searchables, sans filtre géographique.
  /// Utilisé pour détecter les livreurs intercités (déclarent une zone couverte
  /// mais sont physiquement loin au moment de la recherche).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryAllSearchable() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _firestore
        .collection('services')
        .where('status', isEqualTo: 'active')
        .where('search.isSearchable', isEqualTo: true)
        .get();
    return snap.docs;
  }

  ParcelServiceMatch? _mapServiceToMatch({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
  }) {
    final Map<String, dynamic> data = doc.data();
    final Map<String, dynamic> search =
        data['search'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['search'] as Map<String, dynamic>)
            : <String, dynamic>{};

    final double? ownerLat = (search['ownerLat'] as num?)?.toDouble();
    final double? ownerLng = (search['ownerLng'] as num?)?.toDouble();
    if (ownerLat == null || ownerLng == null) return null;

    final double distanceToPickupMeters = Geolocator.distanceBetween(
      ownerLat,
      ownerLng,
      pickupLat,
      pickupLng,
    );

    final bool isNearby = distanceToPickupMeters <= _nearbyThresholdMeters;

    // ── Zone coverage ────────────────────────────────────────────────────────
    final _MatchedZonePrice? zonePrice = _findZonePrice(
      priceZones: data['priceZones'] as List<dynamic>?,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress,
    );
    final bool isZoneCovered = zonePrice != null;

    // ── Ranking ──────────────────────────────────────────────────────────────
    // Rank 1 : proche ET couvre la zone  → tarif prestataire
    // Rank 2 : couvre la zone, quelle que soit la distance (intercité OK)  → tarif prestataire
    // Rank 3 : proche mais ne couvre pas la zone  → tarif GoVIP
    // Rank 4 : ni proche ni zone  → exclu
    final int priorityRank;
    if (isZoneCovered && isNearby) {
      priorityRank = 1;
    } else if (isZoneCovered) {
      priorityRank = 2;
    } else if (isNearby) {
      priorityRank = 3;
    } else {
      priorityRank = 4; // filtré en amont
    }

    final _PlatformPrice fallbackPrice = _estimatePlatformPrice(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
    );

    final Map<String, dynamic> typeVehicule =
        data['typeVehicule'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                data['typeVehicule'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};

    final String? ownerCity =
        (search['ownerCity'] as String?)?.trim().isNotEmpty == true
            ? (search['ownerCity'] as String).trim()
            : null;

    return ParcelServiceMatch(
      serviceId: doc.id,
      ownerUid: '${data['ownerUid'] ?? ''}'.trim(),
      title: '${data['title'] ?? data['name'] ?? 'Service colis'}'.trim(),
      contactName:
          '${data['contactName'] ?? data['name'] ?? 'Prestataire'}'.trim(),
      contactPhone: '${data['contactPhone'] ?? ''}'.trim(),
      price: zonePrice?.price ?? fallbackPrice.price,
      currency: zonePrice?.currency ?? fallbackPrice.currency,
      priceSource: isZoneCovered ? 'Tarif prestataire' : 'Tarif GoVIP',
      isZoneCovered: isZoneCovered,
      distanceToPickupMeters: distanceToPickupMeters,
      priorityRank: priorityRank,
      vehicleLabel: '${typeVehicule['name'] ?? 'Véhicule non précisé'}'.trim(),
      ownerCity: ownerCity,
    );
  }

  // ── Zone matching ─────────────────────────────────────────────────────────
  //
  // Logique : le livreur déclare "Je fais Adjamé → Yopougon".
  // On normalise (minuscule + sans accents + sans mots génériques) les noms
  // de zones ET les adresses de départ/arrivée, puis on vérifie que le nom
  // de zone apparaît dans l'adresse correspondante.

  _MatchedZonePrice? _findZonePrice({
    required List<dynamic>? priceZones,
    required String pickupAddress,
    required String deliveryAddress,
  }) {
    if (priceZones == null || priceZones.isEmpty) return null;

    final String pNorm = _normalize(pickupAddress);
    final String dNorm = _normalize(deliveryAddress);

    for (final dynamic rawZone in priceZones) {
      if (rawZone is! Map) continue;
      final Map<String, dynamic> zone =
          Map<String, dynamic>.from(rawZone);

      final String departNorm = _normalize('${zone['departZone'] ?? ''}');
      final String arrivNorm = _normalize('${zone['arrivZone'] ?? ''}');
      final num? rawPrice = zone['price'] as num?;

      if (departNorm.isEmpty || arrivNorm.isEmpty || rawPrice == null) continue;

      // La zone de départ doit apparaître dans l'adresse de collecte
      // La zone d'arrivée doit apparaître dans l'adresse de livraison
      if (_addressContainsZone(pNorm, departNorm) &&
          _addressContainsZone(dNorm, arrivNorm)) {
        return _MatchedZonePrice(
          price: rawPrice.toDouble(),
          currency: '${zone['device'] ?? 'XOF'}'.trim().isEmpty
              ? 'XOF'
              : '${zone['device']}'.trim(),
        );
      }
    }
    return null;
  }

  /// Vérifie si chaque mot du nom de zone (≥ 3 lettres) est présent dans
  /// l'adresse normalisée. Ex : zone="cocody" → cherche "cocody" dans l'adresse.
  bool _addressContainsZone(String normalizedAddress, String normalizedZone) {
    final List<String> zoneWords = normalizedZone
        .split(' ')
        .where((String w) => w.length >= 3)
        .toList(growable: false);
    if (zoneWords.isEmpty) return false;
    return zoneWords.every(normalizedAddress.contains);
  }

  // ── Normalisation ─────────────────────────────────────────────────────────

  static const Map<String, String> _accentMap = <String, String>{
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'ì': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ò': 'o', 'ó': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  String _removeAccents(String s) =>
      s.split('').map((String c) => _accentMap[c] ?? c).join();

  String _normalize(String value) {
    return _removeAccents(value.toLowerCase())
        .replaceAll(RegExp(r'[,\-_/]'), ' ')
        .replaceAll('abidjan', '')
        .replaceAll('cote d ivoire', '')
        .replaceAll('côte d\'ivoire', '')
        .replaceAll('commune de', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Prix estimé GoVIP ─────────────────────────────────────────────────────

  _PlatformPrice _estimatePlatformPrice({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
  }) {
    final double tripMeters = Geolocator.distanceBetween(
      pickupLat,
      pickupLng,
      deliveryLat,
      deliveryLng,
    );
    final double tripKm = tripMeters / 1000;
    final double rawPrice = 1000 + (tripKm * 275);
    final double roundedPrice = (rawPrice / 100).ceil() * 100;
    return _PlatformPrice(price: roundedPrice, currency: 'XOF');
  }
}

class _MatchedZonePrice {
  const _MatchedZonePrice({required this.price, required this.currency});
  final double price;
  final String currency;
}

class _PlatformPrice {
  const _PlatformPrice({required this.price, required this.currency});
  final double price;
  final String currency;
}
