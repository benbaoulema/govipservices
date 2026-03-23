import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_service_match.dart';

class ParcelServiceMatcher {
  ParcelServiceMatcher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const double _nearbyThresholdMeters = 8000;
  static const double _nearbyLatDelta = 0.072;
  static const double _minZoneScore = 0.75;
  static const int _globalSearchLimit = 250;
  static const int _busyCheckCandidateLimit = 24;
  static const double _zoneCoordinateThresholdMeters = 2500;

  static const List<String> _kActiveDeliveryStatuses = <String>[
    'accepted',
    'en_route_to_pickup',
    'en_route',
    'arrived_at_pickup',
    'picked_up',
    'arrived_at_delivery',
  ];

  static const Set<String> _kIgnoredZoneTokens = <String>{
    'rue',
    'avenue',
    'av',
    'bd',
    'boulevard',
    'route',
    'carrefour',
    'quartier',
    'zone',
    'lot',
    'cite',
    'residence',
    'immeuble',
    'appartement',
    'villa',
  };

  static const Map<String, String> _accentMap = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'á': 'a',
    'ã': 'a',
    'À': 'a',
    'Â': 'a',
    'Ä': 'a',
    'Á': 'a',
    'Ã': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'È': 'e',
    'É': 'e',
    'Ê': 'e',
    'Ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ì': 'i',
    'í': 'i',
    'Î': 'i',
    'Ï': 'i',
    'Ì': 'i',
    'Í': 'i',
    'ô': 'o',
    'ö': 'o',
    'ò': 'o',
    'ó': 'o',
    'õ': 'o',
    'Ô': 'o',
    'Ö': 'o',
    'Ò': 'o',
    'Ó': 'o',
    'Õ': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ú': 'u',
    'Ù': 'u',
    'Û': 'u',
    'Ü': 'u',
    'Ú': 'u',
    'ç': 'c',
    'Ç': 'c',
    'ñ': 'n',
    'Ñ': 'n',
  };

  final FirebaseFirestore _firestore;

  /// Mode auto : retourne le livreur disponible le plus proche du pickup.
  /// Pas de scoring de zone — uniquement la distance GPS.
  Future<ParcelServiceMatch?> findNearestAvailableDriver({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    String? vehicleLabel,
  }) async {
    // 1. Cherche d'abord dans la bande lat proche
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
        await _queryByLatBand(pickupLat: pickupLat, delta: _nearbyLatDelta);

    // 2. Si trop peu de résultats, élargit à tous les services
    if (docs.length < 5) {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> global =
          await _queryAllSearchable(limit: _globalSearchLimit);
      final Set<String> ids = docs.map((d) => d.id).toSet();
      docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
        ...docs,
        ...global.where((d) => !ids.contains(d.id)),
      ];
    }

    // 3. Mappe en ParcelServiceMatch (prix fallback, pas de zone scoring)
    final List<ParcelServiceMatch> candidates = docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic> data = doc.data();
          final Map<String, dynamic> search =
              data['search'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(
                      data['search'] as Map<String, dynamic>)
                  : <String, dynamic>{};
          final double? ownerLat = (search['ownerLat'] as num?)?.toDouble();
          final double? ownerLng = (search['ownerLng'] as num?)?.toDouble();
          if (ownerLat == null || ownerLng == null) return null;

          final double distM = Geolocator.distanceBetween(
              ownerLat, ownerLng, pickupLat, pickupLng);
          final _PlatformPrice price = _estimatePlatformPrice(
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            deliveryLat: deliveryLat,
            deliveryLng: deliveryLng,
          );
          final Map<String, dynamic> typeVehicule =
              data['typeVehicule'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(
                      data['typeVehicule'] as Map<String, dynamic>)
                  : <String, dynamic>{};

          return ParcelServiceMatch(
            serviceId: doc.id,
            ownerUid: '${data['ownerUid'] ?? ''}'.trim(),
            title: '${data['title'] ?? data['name'] ?? 'Livreur'}'.trim(),
            contactName:
                '${data['contactName'] ?? data['name'] ?? 'Livreur'}'.trim(),
            contactPhone: '${data['contactPhone'] ?? ''}'.trim(),
            price: price.price,
            currency: price.currency,
            priceSource: 'Tarif GoVIP',
            isZoneCovered: false,
            distanceToPickupMeters: distM,
            priorityRank: 1,
            vehicleLabel:
                '${typeVehicule['name'] ?? ''}'.trim(),
          );
        })
        .whereType<ParcelServiceMatch>()
        .toList(growable: true);

    if (candidates.isEmpty) return null;

    // 4. Filtre par type de véhicule si demandé
    List<ParcelServiceMatch> filtered = candidates;
    if (vehicleLabel != null && vehicleLabel.trim().isNotEmpty) {
      final String lv = vehicleLabel.trim().toLowerCase();
      filtered = candidates
          .where((ParcelServiceMatch m) =>
              m.vehicleLabel.toLowerCase().contains(lv))
          .toList(growable: true);
      if (filtered.isEmpty) return null;
    }

    // 5. Filtre les livreurs occupés
    final List<String> uids =
        filtered.map((ParcelServiceMatch m) => m.ownerUid).toList();
    final Set<String> busyUids = await _fetchBusyProviderUids(uids);
    final List<ParcelServiceMatch> available = filtered
        .where((ParcelServiceMatch m) => !busyUids.contains(m.ownerUid))
        .toList(growable: false);

    if (available.isEmpty) return null;

    // 5. Retourne le plus proche
    available.sort((ParcelServiceMatch a, ParcelServiceMatch b) =>
        a.distanceToPickupMeters.compareTo(b.distanceToPickupMeters));
    return available.first;
  }

  Future<List<ParcelServiceMatch>> findMatches({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    String? pickupPlaceId,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    String? deliveryPlaceId,
    int limit = 3,
  }) async {
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> nearbyDocs =
        await _queryByLatBand(pickupLat: pickupLat, delta: _nearbyLatDelta);

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredNearbyDocs =
        nearbyDocs
            .where(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  _isWithinNearbyBoundingBox(
                doc: doc,
                pickupLat: pickupLat,
                pickupLng: pickupLng,
              ),
            )
            .toList(growable: false);

    final List<_CandidateMatch> nearbyMatches = filteredNearbyDocs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              _mapServiceToCandidate(
            doc: doc,
            pickupAddress: pickupAddress,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupPlaceId: pickupPlaceId,
            deliveryAddress: deliveryAddress,
            deliveryLat: deliveryLat,
            deliveryLng: deliveryLng,
            deliveryPlaceId: deliveryPlaceId,
          ),
        )
        .whereType<_CandidateMatch>()
        .where((_CandidateMatch candidate) => candidate.match.priorityRank <= 3)
        .toList(growable: true);

    final bool shouldQueryGlobal =
        nearbyMatches
                .where(
                  (_CandidateMatch candidate) =>
                      candidate.match.priorityRank <= 2,
                )
                .length <
            limit;

    final Set<String> nearbyIds = filteredNearbyDocs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id)
        .toSet();

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> globalDocs =
        shouldQueryGlobal
            ? await _queryAllSearchable(limit: _globalSearchLimit)
            : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> allDocs =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in filteredNearbyDocs)
        doc.id: doc,
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in globalDocs)
        if (!nearbyIds.contains(doc.id)) doc.id: doc,
    };

    final List<_CandidateMatch> candidates = allDocs.values
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              _mapServiceToCandidate(
            doc: doc,
            pickupAddress: pickupAddress,
            pickupLat: pickupLat,
            pickupLng: pickupLng,
            pickupPlaceId: pickupPlaceId,
            deliveryAddress: deliveryAddress,
            deliveryLat: deliveryLat,
            deliveryLng: deliveryLng,
            deliveryPlaceId: deliveryPlaceId,
          ),
        )
        .whereType<_CandidateMatch>()
        .where((_CandidateMatch candidate) => candidate.match.priorityRank <= 3)
        .toList(growable: true);

    candidates.sort(_compareCandidates);

    final List<_CandidateMatch> busyCheckPool = candidates
        .take(_busyCheckCandidateLimit)
        .toList(growable: false);
    final List<String> candidateUids = busyCheckPool
        .map((_CandidateMatch candidate) => candidate.match.ownerUid)
        .where((String uid) => uid.isNotEmpty)
        .toList(growable: false);
    final Set<String> busyUids = await _fetchBusyProviderUids(candidateUids);

    final List<_CandidateMatch> available = busyUids.isEmpty
        ? candidates
        : candidates
            .where(
              (_CandidateMatch candidate) =>
                  !busyUids.contains(candidate.match.ownerUid),
            )
            .toList(growable: false);

    return available
        .take(limit)
        .map((_CandidateMatch candidate) => candidate.match)
        .toList(growable: false);
  }

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

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryAllSearchable({
    required int limit,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _firestore
        .collection('services')
        .where('status', isEqualTo: 'active')
        .where('search.isSearchable', isEqualTo: true)
        .limit(limit)
        .get();
    return snap.docs;
  }

  _CandidateMatch? _mapServiceToCandidate({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String? pickupPlaceId,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    required String? deliveryPlaceId,
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

    final _MatchedZonePrice? zonePrice = _findZonePrice(
      priceZones: data['priceZones'] as List<dynamic>?,
      pickupAddress: pickupAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      pickupPlaceId: pickupPlaceId,
      deliveryAddress: deliveryAddress,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
      deliveryPlaceId: deliveryPlaceId,
    );
    final bool isZoneCovered = zonePrice != null;

    final int priorityRank;
    if (isZoneCovered && isNearby) {
      priorityRank = 1;
    } else if (isZoneCovered) {
      priorityRank = 2;
    } else if (isNearby) {
      priorityRank = 3;
    } else {
      priorityRank = 4;
    }

    final _PlatformPrice fallbackPrice = _estimatePlatformPrice(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
    );

    final Map<String, dynamic> typeVehicule =
        data['typeVehicule'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['typeVehicule'] as Map<String, dynamic>)
            : <String, dynamic>{};

    final String? ownerCity =
        (search['ownerCity'] as String?)?.trim().isNotEmpty == true
            ? (search['ownerCity'] as String).trim()
            : null;

    return _CandidateMatch(
      match: ParcelServiceMatch(
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
        vehicleLabel: '${typeVehicule['name'] ?? 'Vehicule non precise'}'.trim(),
        ownerCity: ownerCity,
      ),
      zoneScore: zonePrice?.score ?? 0,
      usesProviderPrice: isZoneCovered,
    );
  }

  _MatchedZonePrice? _findZonePrice({
    required List<dynamic>? priceZones,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String? pickupPlaceId,
    required String deliveryAddress,
    required double deliveryLat,
    required double deliveryLng,
    required String? deliveryPlaceId,
  }) {
    if (priceZones == null || priceZones.isEmpty) return null;

    final String normalizedPickup = _normalize(pickupAddress);
    final String normalizedDelivery = _normalize(deliveryAddress);
    _MatchedZonePrice? bestMatch;

    for (final dynamic rawZone in priceZones) {
      if (rawZone is! Map) continue;
      final Map<String, dynamic> zone = Map<String, dynamic>.from(rawZone);

      final String departNorm = _normalize('${zone['departZone'] ?? ''}');
      final String arrivalNorm = _normalize('${zone['arrivZone'] ?? ''}');
      final num? rawPrice = zone['price'] as num?;
      if (departNorm.isEmpty || arrivalNorm.isEmpty || rawPrice == null) {
        continue;
      }

      final double pickupScore = _zoneCoverageScore(
        normalizedAddress: normalizedPickup,
        addressLat: pickupLat,
        addressLng: pickupLng,
        addressPlaceId: pickupPlaceId,
        normalizedZoneLabel: departNorm,
        zoneLatLng: _readLatLngMap(zone['departLatLng']),
        zonePlaceId: zone['departPlaceId'] as String?,
      );
      final double deliveryScore = _zoneCoverageScore(
        normalizedAddress: normalizedDelivery,
        addressLat: deliveryLat,
        addressLng: deliveryLng,
        addressPlaceId: deliveryPlaceId,
        normalizedZoneLabel: arrivalNorm,
        zoneLatLng: _readLatLngMap(zone['arrivLatLng']),
        zonePlaceId: zone['arrivPlaceId'] as String?,
      );
      if (pickupScore < _minZoneScore || deliveryScore < _minZoneScore) {
        continue;
      }

      final _MatchedZonePrice candidate = _MatchedZonePrice(
        price: rawPrice.toDouble(),
        currency: '${zone['device'] ?? 'XOF'}'.trim().isEmpty
            ? 'XOF'
            : '${zone['device']}'.trim(),
        score: (pickupScore + deliveryScore) / 2,
      );
      if (bestMatch == null || candidate.score > bestMatch.score) {
        bestMatch = candidate;
      }
    }

    return bestMatch;
  }

  double _zoneCoverageScore({
    required String normalizedAddress,
    required double addressLat,
    required double addressLng,
    required String? addressPlaceId,
    required String normalizedZoneLabel,
    required Map<String, dynamic>? zoneLatLng,
    required String? zonePlaceId,
  }) {
    final double placeIdScore = _placeIdScore(
      addressPlaceId: addressPlaceId,
      zonePlaceId: zonePlaceId,
    );
    if (placeIdScore > 0) return placeIdScore;

    final double coordinateScore = _zoneCoordinateScore(
      addressLat: addressLat,
      addressLng: addressLng,
      zoneLatLng: zoneLatLng,
    );
    if (coordinateScore > 0) return coordinateScore;

    return _zoneTextScore(
      normalizedAddress: normalizedAddress,
      normalizedZone: normalizedZoneLabel,
    );
  }

  double _placeIdScore({
    required String? addressPlaceId,
    required String? zonePlaceId,
  }) {
    final String addressId = addressPlaceId?.trim() ?? '';
    final String zoneId = zonePlaceId?.trim() ?? '';
    if (addressId.isEmpty || zoneId.isEmpty) return 0;
    return addressId == zoneId ? 1 : 0;
  }

  double _zoneCoordinateScore({
    required double addressLat,
    required double addressLng,
    required Map<String, dynamic>? zoneLatLng,
  }) {
    if (zoneLatLng == null) return 0;

    final double? zoneLat = (zoneLatLng['lat'] as num?)?.toDouble();
    final double? zoneLng = (zoneLatLng['lng'] as num?)?.toDouble();
    if (zoneLat == null || zoneLng == null) return 0;

    final double distance = Geolocator.distanceBetween(
      addressLat,
      addressLng,
      zoneLat,
      zoneLng,
    );
    if (distance > _zoneCoordinateThresholdMeters) return 0;
    if (distance <= 300) return 1;
    if (distance <= 800) return 0.95;
    if (distance <= 1500) return 0.88;
    return 0.8;
  }

  double _zoneTextScore({
    required String normalizedAddress,
    required String normalizedZone,
  }) {
    if (normalizedAddress.isEmpty || normalizedZone.isEmpty) return 0;

    final Set<String> addressTokens = _tokenize(normalizedAddress).toSet();
    final Set<String> zoneTokens = _tokenize(normalizedZone).toSet();
    if (addressTokens.isEmpty || zoneTokens.isEmpty) return 0;

    if (normalizedAddress.contains(normalizedZone)) {
      return 1;
    }

    final int matchingTokens = zoneTokens.where(addressTokens.contains).length;
    if (matchingTokens == 0) return 0;

    final double coverage = matchingTokens / zoneTokens.length;
    if (matchingTokens == zoneTokens.length) return 0.95;
    if (zoneTokens.length >= 3 && matchingTokens >= zoneTokens.length - 1) {
      return 0.82;
    }
    if (zoneTokens.length == 1 && coverage == 1) return 0.9;
    return coverage;
  }

  List<String> _tokenize(String value) {
    return _normalize(value)
        .split(' ')
        .where(
          (String token) =>
              token.length >= 3 && !_kIgnoredZoneTokens.contains(token),
        )
        .toList(growable: false);
  }

  Future<Set<String>> _fetchBusyProviderUids(List<String> ownerUids) async {
    if (ownerUids.isEmpty) return const <String>{};

    final Set<String> busyUids = <String>{};
    for (int i = 0; i < ownerUids.length; i += 30) {
      final List<String> chunk =
          ownerUids.sublist(i, math.min(i + 30, ownerUids.length));
      final QuerySnapshot<Map<String, dynamic>> snap = await _firestore
          .collection('demands')
          .where('providerUid', whereIn: chunk)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final String status = ((doc.data()['status'] as String?) ?? '').trim();
        if (_kActiveDeliveryStatuses.contains(status)) {
          final String uid = ((doc.data()['providerUid'] as String?) ?? '').trim();
          if (uid.isNotEmpty) busyUids.add(uid);
        }
      }
    }
    return busyUids;
  }

  bool _isWithinNearbyBoundingBox({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required double pickupLat,
    required double pickupLng,
  }) {
    final Map<String, dynamic> data = doc.data();
    final Map<String, dynamic> search =
        data['search'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['search'] as Map<String, dynamic>)
            : <String, dynamic>{};

    final double? ownerLat = (search['ownerLat'] as num?)?.toDouble();
    final double? ownerLng = (search['ownerLng'] as num?)?.toDouble();
    if (ownerLat == null || ownerLng == null) return false;

    final double lngDelta = _nearbyLngDelta(pickupLat);
    return (ownerLat - pickupLat).abs() <= _nearbyLatDelta &&
        (ownerLng - pickupLng).abs() <= lngDelta;
  }

  double _nearbyLngDelta(double latitude) {
    final double cosLat = math.cos(latitude.abs() * math.pi / 180);
    final double safeCos = cosLat.abs() < 0.2 ? 0.2 : cosLat.abs();
    return _nearbyLatDelta / safeCos;
  }

  int _compareCandidates(_CandidateMatch a, _CandidateMatch b) {
    final int byRank = a.match.priorityRank.compareTo(b.match.priorityRank);
    if (byRank != 0) return byRank;

    final int byProviderPrice =
        (b.usesProviderPrice ? 1 : 0).compareTo(a.usesProviderPrice ? 1 : 0);
    if (byProviderPrice != 0) return byProviderPrice;

    final int byZoneScore = b.zoneScore.compareTo(a.zoneScore);
    if (byZoneScore != 0) return byZoneScore;

    final int byBucket =
        _distanceBucket(a.match.distanceToPickupMeters).compareTo(
      _distanceBucket(b.match.distanceToPickupMeters),
    );
    if (byBucket != 0) return byBucket;

    return a.match.distanceToPickupMeters.compareTo(
      b.match.distanceToPickupMeters,
    );
  }

  int _distanceBucket(double distanceMeters) {
    if (distanceMeters <= 1000) return 1;
    if (distanceMeters <= 3000) return 2;
    if (distanceMeters <= _nearbyThresholdMeters) return 3;
    if (distanceMeters <= 20000) return 4;
    return 5;
  }

  Map<String, dynamic>? _readLatLngMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (dynamic key, dynamic mapValue) =>
            MapEntry('$key', mapValue),
      );
    }
    return null;
  }

  String _removeAccents(String value) =>
      value.split('').map((String char) => _accentMap[char] ?? char).join();

  String _normalize(String value) {
    return _removeAccents(value.toLowerCase())
        .replaceAll(RegExp(r'[,\-_/()]'), ' ')
        .replaceAll('abidjan', '')
        .replaceAll('cote d ivoire', '')
        .replaceAll("cote d'ivoire", '')
        .replaceAll('commune de', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

class _CandidateMatch {
  const _CandidateMatch({
    required this.match,
    required this.zoneScore,
    required this.usesProviderPrice,
  });

  final ParcelServiceMatch match;
  final double zoneScore;
  final bool usesProviderPrice;
}

class _MatchedZonePrice {
  const _MatchedZonePrice({
    required this.price,
    required this.currency,
    required this.score,
  });

  final double price;
  final String currency;
  final double score;
}

class _PlatformPrice {
  const _PlatformPrice({required this.price, required this.currency});

  final double price;
  final String currency;
}
