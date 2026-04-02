import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/data/trip_recurrence_service.dart';

class TripStopModel {
  const TripStopModel({
    required this.id,
    required this.address,
    required this.estimatedTime,
    required this.priceFromDeparture,
    this.lat,
    this.lng,
    this.bookable = true,
  });

  final String id;
  final String address;
  final String estimatedTime;
  final int priceFromDeparture;
  final double? lat;
  final double? lng;
  final bool bookable;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'address': address,
        'estimatedTime': estimatedTime,
        'priceFromDeparture': priceFromDeparture,
        'lat': lat,
        'lng': lng,
        'bookable': bookable,
      };

  factory TripStopModel.fromMap(Map<String, dynamic> map) {
    return TripStopModel(
      id: _safeString(map['id']).isEmpty ? _safeString(map['address']) : _safeString(map['id']),
      address: _safeString(map['address']),
      estimatedTime: _safeString(map['estimatedTime']),
      priceFromDeparture: _safeInt(map['priceFromDeparture'], 0),
      lat: _safeDouble(map['lat']),
      lng: _safeDouble(map['lng']),
      bookable: map['bookable'] != false,
    );
  }
}

class TripRouteNode {
  const TripRouteNode({
    required this.kind,
    required this.address,
    required this.time,
    required this.priceFromDeparture,
    this.lat,
    this.lng,
  });

  final String kind;
  final String address;
  final String time;
  final int priceFromDeparture;
  final double? lat;
  final double? lng;
}

class TripSegmentModel {
  const TripSegmentModel({
    required this.departureIndex,
    required this.arrivalIndex,
    required this.departureNode,
    required this.arrivalNode,
    required this.segmentPrice,
  });

  final int departureIndex;
  final int arrivalIndex;
  final TripRouteNode departureNode;
  final TripRouteNode arrivalNode;
  final int segmentPrice;
}

class VoyageTripSearchItem {
  const VoyageTripSearchItem({
    required this.id,
    required this.departurePlace,
    required this.arrivalPlace,
    required this.departureDate,
    required this.departureTime,
    required this.pricePerSeat,
    required this.currency,
    required this.seats,
    required this.driverName,
    required this.vehicleModel,
    required this.isBus,
    required this.isFrequentTrip,
    required this.tripFrequency,
    required this.intermediateStops,
    required this.hasLuggageSpace,
    required this.allowsPets,
    required this.status,
    this.trackNum,
    this.arrivalEstimatedTime,
    this.effectiveDepartureDate,
    this.contactPhone,
    this.ownerEmail,
    this.vehiclePhotoUrl,
    this.ownerUid,
    this.ownerTrackNum,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String? trackNum;
  final String departurePlace;
  final String arrivalPlace;
  final String departureDate;
  final String departureTime;
  final String? arrivalEstimatedTime;
  final int pricePerSeat;
  final String currency;
  final int seats;
  final String driverName;
  final String vehicleModel;
  final bool isBus;
  final bool isFrequentTrip;
  final TripFrequency tripFrequency;
  final String? effectiveDepartureDate;
  final String? contactPhone;
  final String? ownerEmail;
  final String? vehiclePhotoUrl;
  final String? ownerUid;
  final String? ownerTrackNum;
  final List<TripStopModel> intermediateStops;
  final bool hasLuggageSpace;
  final bool allowsPets;
  final String status;
  final Map<String, dynamic> raw;

  VoyageTripSearchItem copyWith({
    String? effectiveDepartureDate,
    String? departurePlace,
    String? arrivalPlace,
    String? departureTime,
    String? arrivalEstimatedTime,
    int? pricePerSeat,
  }) {
    return VoyageTripSearchItem(
      id: id,
      trackNum: trackNum,
      departurePlace: departurePlace ?? this.departurePlace,
      arrivalPlace: arrivalPlace ?? this.arrivalPlace,
      departureDate: departureDate,
      departureTime: departureTime ?? this.departureTime,
      arrivalEstimatedTime: arrivalEstimatedTime ?? this.arrivalEstimatedTime,
      pricePerSeat: pricePerSeat ?? this.pricePerSeat,
      currency: currency,
      seats: seats,
      driverName: driverName,
      vehicleModel: vehicleModel,
      isBus: isBus,
      isFrequentTrip: isFrequentTrip,
      tripFrequency: tripFrequency,
      effectiveDepartureDate: effectiveDepartureDate ?? this.effectiveDepartureDate,
      contactPhone: contactPhone,
      ownerEmail: ownerEmail,
      vehiclePhotoUrl: vehiclePhotoUrl,
      ownerUid: ownerUid,
      ownerTrackNum: ownerTrackNum,
      intermediateStops: intermediateStops,
      hasLuggageSpace: hasLuggageSpace,
      allowsPets: allowsPets,
      status: status,
      raw: raw,
    );
  }
}

class TripSearchService {
  TripSearchService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<VoyageTripSearchItem>> searchVoyageTrips({
    String? departureDate,
    int limitCount = 120,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('status', isEqualTo: 'published')
        .limit(limitCount)
        .get();

    List<VoyageTripSearchItem> items = snapshot.docs
        .map((d) => mapTripDoc(d.id, d.data()))
        .whereType<VoyageTripSearchItem>()
        .toList(growable: false);

    return searchVoyageTripsLocal(
      docs: items.map((i) => <String, dynamic>{...i.raw, 'id': i.id}).toList(growable: false),
      departureDate: departureDate,
      limitCount: limitCount,
    );
  }
}

List<VoyageTripSearchItem> searchVoyageTripsLocal({
  required List<Map<String, dynamic>> docs,
  String? departureDate,
  int limitCount = 80,
}) {
  List<VoyageTripSearchItem> items = docs
      .where((d) => _safeString(d['status']) == 'published')
      .take(limitCount)
      .map((d) => mapTripDoc(_safeString(d['id']), d))
      .whereType<VoyageTripSearchItem>()
      .toList(growable: false);

  if (departureDate != null && departureDate.trim().isNotEmpty) {
    final String searchDate = departureDate.trim();
    items = items
        .where(
          (trip) => matchesTripForSearchDate(
            tripDepartureDate: trip.departureDate,
            searchDate: searchDate,
            tripFrequency: trip.tripFrequency,
          ),
        )
        .map((trip) => trip.copyWith(effectiveDepartureDate: searchDate))
        .toList(growable: false);
  }

  items.sort((a, b) {
    final String da = a.effectiveDepartureDate ?? a.departureDate;
    final String db = b.effectiveDepartureDate ?? b.departureDate;
    final int dateCmp = da.compareTo(db);
    if (dateCmp != 0) return dateCmp;
    return a.departureTime.compareTo(b.departureTime);
  });

  return items;
}

VoyageTripSearchItem? mapTripDoc(String id, Map<String, dynamic> raw) {
  final String departurePlace = _safeString(raw['departurePlace']);
  final String arrivalPlace = _safeString(raw['arrivalPlace']);
  final String departureDate = _safeString(raw['departureDate']);
  final String departureTime = _safeString(raw['departureTime']);

  if (departurePlace.isEmpty || arrivalPlace.isEmpty || departureDate.isEmpty || departureTime.isEmpty) {
    return null;
  }

  final bool isFrequent = raw['isFrequentTrip'] == true;
  final TripFrequency freq = safeTripFrequency(raw['tripFrequency'], isFrequentTripFallback: isFrequent);

  final List<dynamic> stopsRaw = raw['intermediateStops'] as List<dynamic>? ?? const <dynamic>[];
  final List<TripStopModel> stops = stopsRaw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((m) => m['toStop'] == null)
      .map(TripStopModel.fromMap)
      .where((s) => s.address.trim().isNotEmpty)
      .toList(growable: false);

  final int price = _safeInt(raw['pricePerSeat'], 0);
  final int seats = _safeInt(raw['seats'], 1);

  return VoyageTripSearchItem(
    id: id,
    trackNum: _safeString(raw['trackNum']).isEmpty ? null : _safeString(raw['trackNum']),
    departurePlace: departurePlace,
    arrivalPlace: arrivalPlace,
    departureDate: departureDate,
    departureTime: departureTime,
    arrivalEstimatedTime: _safeString(raw['arrivalEstimatedTime']).isEmpty
        ? (_safeString(raw['arrivalTime']).isEmpty ? null : _safeString(raw['arrivalTime']))
        : _safeString(raw['arrivalEstimatedTime']),
    pricePerSeat: price < 0 ? 0 : price,
    currency: _safeString(raw['currency']) == 'EUR' ? 'EUR' : 'XOF',
    seats: seats < 1 ? 1 : seats,
    driverName: _safeString(raw['driverName']),
    vehicleModel: _safeString(raw['vehicleModel']),
    isBus: raw['isBus'] == true,
    isFrequentTrip: isFrequent || freq != TripFrequency.none,
    tripFrequency: freq,
    contactPhone: _safeString(raw['contactPhone']).isEmpty ? null : _safeString(raw['contactPhone']),
    ownerEmail: _safeString(raw['ownerEmail']).isEmpty ? null : _safeString(raw['ownerEmail']),
    vehiclePhotoUrl: _safeString(raw['vehiclePhotoUrl']).isEmpty ? null : _safeString(raw['vehiclePhotoUrl']),
    ownerUid: _safeString(raw['ownerUid']).isEmpty ? null : _safeString(raw['ownerUid']),
    ownerTrackNum: _safeString(raw['ownerTrackNum']).isEmpty ? null : _safeString(raw['ownerTrackNum']),
    intermediateStops: stops,
    hasLuggageSpace: raw['hasLuggageSpace'] == true,
    allowsPets: raw['allowsPets'] == true,
    status: _safeString(raw['status']).isEmpty ? 'published' : _safeString(raw['status']),
    raw: raw,
  );
}

List<TripRouteNode> buildTripRouteNodes(VoyageTripSearchItem trip) {
  return <TripRouteNode>[
    TripRouteNode(
      kind: 'departure',
      address: trip.departurePlace,
      time: trip.departureTime,
      priceFromDeparture: 0,
      lat: _safeDouble(trip.raw['departureLat']),
      lng: _safeDouble(trip.raw['departureLng']),
    ),
    ...trip.intermediateStops.where((s) => s.bookable).map(
      (s) => TripRouteNode(
        kind: 'stop',
        address: s.address,
        time: s.estimatedTime,
        priceFromDeparture: s.priceFromDeparture,
        lat: s.lat,
        lng: s.lng,
      ),
    ),
    TripRouteNode(
      kind: 'arrival',
      address: trip.arrivalPlace,
      time: trip.arrivalEstimatedTime ?? '',
      priceFromDeparture: trip.pricePerSeat,
      lat: _safeDouble(trip.raw['arrivalLat']),
      lng: _safeDouble(trip.raw['arrivalLng']),
    ),
  ];
}

TripSegmentModel? resolveTripSegment({
  required List<TripRouteNode> nodes,
  required String from,
  required String to,
}) {
  final int depIndex = from.trim().isEmpty ? 0 : _findNodeIndexByQuery(nodes, from);
  if (depIndex < 0) return null;
  final int arrIndex = to.trim().isEmpty
      ? nodes.length - 1
      : _findNodeIndexByQuery(nodes, to, afterIndex: depIndex);
  if (arrIndex < 0 || arrIndex <= depIndex) return null;

  final TripRouteNode fromNode = nodes[depIndex];
  final TripRouteNode toNode = nodes[arrIndex];
  final int price = (toNode.priceFromDeparture - fromNode.priceFromDeparture).clamp(0, 1 << 30);

  return TripSegmentModel(
    departureIndex: depIndex,
    arrivalIndex: arrIndex,
    departureNode: fromNode,
    arrivalNode: toNode,
    segmentPrice: price,
  );
}

String cityToken(String address) => (address.split(',').first).trim();

String normalize(String value) {
  String s = value.toLowerCase().trim();
  const Map<String, String> map = <String, String>{
    'a': '\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5',
    'c': '\u00E7',
    'e': '\u00E8\u00E9\u00EA\u00EB',
    'i': '\u00EC\u00ED\u00EE\u00EF',
    'n': '\u00F1',
    'o': '\u00F2\u00F3\u00F4\u00F5\u00F6',
    'u': '\u00F9\u00FA\u00FB\u00FC',
    'y': '\u00FD\u00FF',
  };
  map.forEach((ascii, chars) {
    for (final String ch in chars.split('')) {
      s = s.replaceAll(ch, ascii);
    }
  });
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

bool matchesAddressQuery(String queryAddress, String candidateAddress) {
  final List<String> queryTokens = <String>[];
  final List<String> candidateTokens = <String>[];

  final String qFirst = normalize(cityToken(queryAddress));
  if (qFirst.isNotEmpty) queryTokens.add(qFirst);
  for (final String part in queryAddress.split(',')) {
    final String t = normalize(part);
    if (t.isNotEmpty && !queryTokens.contains(t)) queryTokens.add(t);
  }

  final String cFirst = normalize(cityToken(candidateAddress));
  if (cFirst.isNotEmpty) candidateTokens.add(cFirst);
  for (final String part in candidateAddress.split(',')) {
    final String t = normalize(part);
    if (t.isNotEmpty && !candidateTokens.contains(t)) candidateTokens.add(t);
  }

  if (queryTokens.isEmpty) return true;
  if (candidateTokens.isEmpty) return false;

  for (final String q in queryTokens) {
    for (final String c in candidateTokens) {
      if (_similarToken(c, q)) return true;
    }
  }
  return false;
}

int _findNodeIndexByQuery(List<TripRouteNode> nodes, String queryAddress, {int afterIndex = -1}) {
  for (int i = 0; i < nodes.length; i++) {
    if (i <= afterIndex) continue;
    if (matchesAddressQuery(queryAddress, nodes[i].address)) return i;
  }
  return -1;
}

bool _similarToken(String a, String b) {
  final String left = _normalizeLoose(a);
  final String right = _normalizeLoose(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (_isGenericGeoToken(left) || _isGenericGeoToken(right)) return false;
  if (left == right) return true;
  if (left.length >= 4 && right.length >= 4) {
    if (left.startsWith(right) || right.startsWith(left)) return true;
  }

  final Set<String> leftWords = left.split(' ').where((w) => w.length >= 4).toSet();
  final Set<String> rightWords = right.split(' ').where((w) => w.length >= 4).toSet();
  for (final String lw in leftWords) {
    if (rightWords.contains(lw)) return true;
  }
  return false;
}

String _normalizeLoose(String value) {
  return value
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isGenericGeoToken(String value) {
  final String v = _normalizeLoose(value);
  return v.isEmpty || v == 'ci' || v == 'cote d ivoire' || v == 'cote divoire' || v == 'ivory coast';
}

String _safeString(dynamic v) => v is String ? v.trim() : '';

int _safeInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

double? _safeDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}
