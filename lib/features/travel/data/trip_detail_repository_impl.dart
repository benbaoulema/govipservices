import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';

class TripDetailRepositoryImpl implements TripDetailRepository {
  TripDetailRepositoryImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<TripDetailModel?> getTripDetailById(String tripId) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _firestore.collection('voyageTrips').doc(tripId).get();
    final Map<String, dynamic>? raw = doc.data();
    if (!doc.exists || raw == null) return null;

    final List<dynamic> stopsRaw = raw['intermediateStops'] as List<dynamic>? ?? const <dynamic>[];
    final List<TripStopModel> stops = stopsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((s) => s['toStop'] == null)
        .map(
          (s) => TripStopModel(
            id: _str(s['id']).isEmpty ? _str(s['address']) : _str(s['id']),
            address: _str(s['address']),
            estimatedTime: _str(s['estimatedTime']),
            priceFromDeparture: _int(s['priceFromDeparture'], 0),
            lat: _doubleOrNull(s['lat']),
            lng: _doubleOrNull(s['lng']),
            bookable: s['bookable'] != false,
          ),
        )
        .where((s) => s.address.trim().isNotEmpty)
        .toList(growable: false);

    return TripDetailModel(
      id: doc.id,
      trackNum: _str(raw['trackNum']),
      ownerUid: _str(raw['ownerUid']),
      departurePlace: _str(raw['departurePlace']),
      arrivalPlace: _str(raw['arrivalPlace']),
      departureDate: _str(raw['departureDate']),
      departureTime: _str(raw['departureTime']),
      arrivalEstimatedTime: _str(raw['arrivalEstimatedTime']).isNotEmpty
          ? _str(raw['arrivalEstimatedTime'])
          : _str(raw['arrivalTime']),
      tripFrequency: _str(raw['tripFrequency']).isEmpty ? 'none' : _str(raw['tripFrequency']),
      pricePerSeat: _int(raw['pricePerSeat'], 0),
      currency: _str(raw['currency']).isEmpty ? 'XOF' : _str(raw['currency']),
      seats: _int(raw['seats'], 0),
      driver: DriverInfoModel(
        name: _str(raw['driverName']),
        contactPhone: _str(raw['contactPhone']),
      ),
      vehicle: VehicleInfoModel(
        model: _str(raw['vehicleModel']),
        photoUrl: _str(raw['vehiclePhotoUrl']),
      ),
      options: TripOptionsModel(
        hasLuggageSpace: raw['hasLuggageSpace'] == true,
        allowsPets: raw['allowsPets'] == true,
      ),
      intermediateStops: stops,
      status: _str(raw['status']).isEmpty ? 'published' : _str(raw['status']),
      isBus: raw['isBus'] == true,
      segmentOccupancy: _parseSegmentOccupancy(raw['segmentOccupancy']),
    );
  }

  Map<String, int> _parseSegmentOccupancy(Object? value) {
    if (value is! Map) return const <String, int>{};
    final Map<String, int> result = <String, int>{};
    for (final entry in value.entries) {
      final String key = entry.key.toString();
      final int v = entry.value is int
          ? entry.value as int
          : (entry.value is num ? (entry.value as num).toInt() : 0);
      result[key] = v;
    }
    return result;
  }

  String _str(Object? value) => value is String ? value.trim() : '';

  int _int(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  double? _doubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }
}
