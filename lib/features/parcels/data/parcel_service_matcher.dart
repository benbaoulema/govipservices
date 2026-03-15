import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_service_match.dart';

class ParcelServiceMatcher {
  ParcelServiceMatcher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const double _nearbyThresholdMeters = 5000;
  static const int _queryLimit = 40;

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
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('services')
        .where('status', isEqualTo: 'active')
        .where('search.isSearchable', isEqualTo: true)
        .limit(_queryLimit)
        .get();

    final List<ParcelServiceMatch> matches = snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) => _mapServiceToMatch(
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
        .toList(growable: false);

    matches.sort((ParcelServiceMatch a, ParcelServiceMatch b) {
      final int byRank = a.priorityRank.compareTo(b.priorityRank);
      if (byRank != 0) return byRank;
      final int byDistance =
          a.distanceToPickupMeters.compareTo(b.distanceToPickupMeters);
      if (byDistance != 0) return byDistance;
      return a.price.compareTo(b.price);
    });

    return matches.take(limit).toList(growable: false);
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

    final _MatchedZonePrice? zonePrice = _findZonePrice(
      priceZones: data['priceZones'] as List<dynamic>?,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress,
    );

    final bool isZoneCovered = zonePrice != null;
    final _PlatformPrice fallbackPrice = _estimatePlatformPrice(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
    );

    final int priorityRank = isZoneCovered && isNearby
        ? 1
        : !isZoneCovered && isNearby
            ? 2
            : isZoneCovered
                ? 3
                : 4;

    final Map<String, dynamic> typeVehicule =
        data['typeVehicule'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                data['typeVehicule'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};

    return ParcelServiceMatch(
      serviceId: doc.id,
      ownerUid: '${data['ownerUid'] ?? ''}'.trim(),
      title: '${data['title'] ?? data['name'] ?? 'Service colis'}'.trim(),
      contactName: '${data['contactName'] ?? data['name'] ?? 'Prestataire'}'
          .trim(),
      contactPhone: '${data['contactPhone'] ?? ''}'.trim(),
      price: zonePrice?.price ?? fallbackPrice.price,
      currency: zonePrice?.currency ?? fallbackPrice.currency,
      priceSource: isZoneCovered ? 'Tarif prestataire' : 'Tarif GoVIP',
      isZoneCovered: isZoneCovered,
      distanceToPickupMeters: distanceToPickupMeters,
      priorityRank: priorityRank,
      vehicleLabel: '${typeVehicule['name'] ?? 'Vehicule non precise'}'.trim(),
    );
  }

  _MatchedZonePrice? _findZonePrice({
    required List<dynamic>? priceZones,
    required String pickupAddress,
    required String deliveryAddress,
  }) {
    if (priceZones == null || priceZones.isEmpty) return null;

    final String normalizedPickup = _normalize(pickupAddress);
    final String normalizedDelivery = _normalize(deliveryAddress);

    for (final dynamic rawZone in priceZones) {
      if (rawZone is! Map) continue;
      final Map<String, dynamic> zone = Map<String, dynamic>.from(
        rawZone as Map<dynamic, dynamic>,
      );
      final String departZone = _normalize('${zone['departZone'] ?? ''}');
      final String arrivZone = _normalize('${zone['arrivZone'] ?? ''}');
      final num? rawPrice = zone['price'] as num?;
      if (departZone.isEmpty || arrivZone.isEmpty || rawPrice == null) continue;

      if (_matchesZone(normalizedPickup, departZone) &&
          _matchesZone(normalizedDelivery, arrivZone)) {
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

  bool _matchesZone(String address, String zone) {
    if (address.contains(zone) || zone.contains(address)) return true;
    final List<String> addressParts =
        address.split(' ').where((String part) => part.length >= 4).toList();
    final List<String> zoneParts =
        zone.split(' ').where((String part) => part.length >= 4).toList();
    if (addressParts.isEmpty || zoneParts.isEmpty) return false;
    return zoneParts.any(addressParts.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(',', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('abidjan', '')
        .replaceAll('cote d ivoire', '')
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
    final double tripKilometers = tripMeters / 1000;
    final double rawPrice = 1000 + (tripKilometers * 275);
    final double roundedPrice = (rawPrice / 100).ceil() * 100;
    return _PlatformPrice(price: roundedPrice, currency: 'XOF');
  }
}

class _MatchedZonePrice {
  const _MatchedZonePrice({
    required this.price,
    required this.currency,
  });

  final double price;
  final String currency;
}

class _PlatformPrice {
  const _PlatformPrice({
    required this.price,
    required this.currency,
  });

  final double price;
  final String currency;
}
