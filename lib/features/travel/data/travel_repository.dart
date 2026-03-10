import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/travel_service.dart';

class TripSearchResult {
  const TripSearchResult({
    required this.id,
    required this.departurePlace,
    required this.arrivalPlace,
    required this.departureDate,
    this.departureTime,
    this.driverName,
    this.contactPhone,
    this.trackNum,
    this.seats,
    this.pricePerSeat,
    this.currency,
    this.tripFrequency = 'none',
    this.isFrequentTrip = false,
    this.effectiveDepartureDate,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String departurePlace;
  final String arrivalPlace;
  final String departureDate;
  final String? departureTime;
  final String? driverName;
  final String? contactPhone;
  final String? trackNum;
  final int? seats;
  final double? pricePerSeat;
  final String? currency;
  final String tripFrequency;
  final bool isFrequentTrip;
  final String? effectiveDepartureDate;
  final Map<String, dynamic> raw;
}

class TravelRepository implements TravelService {
  TravelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  final FirebaseFirestore _firestore;

  @override
  Future<PublishedTripResult> addTrip(Map<String, dynamic> payload) async {
    final CollectionReference<Map<String, dynamic>> tripsRef = _firestore.collection('voyageTrips');
    final String dedupeKey = _buildDedupeKey(payload);

    final QuerySnapshot<Map<String, dynamic>> duplicateQuery = await tripsRef
        .where('dedupeKey', isEqualTo: dedupeKey)
        .limit(1)
        .get();
    if (duplicateQuery.docs.isNotEmpty) {
      final QueryDocumentSnapshot<Map<String, dynamic>> existing = duplicateQuery.docs.first;
      final String existingStatus = (existing.data()['status'] as String?) ?? 'published';
      if (existingStatus != 'cancelled') {
        return PublishedTripResult(
          id: existing.id,
          trackNum: (existing.data()['trackNum'] as String?) ?? generateVoyageTrackNum(),
          wasCreated: false,
        );
      }
    }

    final DocumentReference<Map<String, dynamic>> tripRef = tripsRef.doc();
    final String trackNum = generateVoyageTrackNum();

    await tripRef.set(
      <String, dynamic>{
        ...payload,
        'dedupeKey': dedupeKey,
        'status': payload['status'] ?? 'published',
        'trackNum': trackNum,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return PublishedTripResult(
      id: tripRef.id,
      trackNum: trackNum,
      wasCreated: true,
    );
  }

  @override
  Future<void> bookTrip() async {}

  @override
  Future<void> loadMyTrips() async {}

  @override
  Future<void> loadMessages() async {}

  Future<List<TripSearchResult>> searchAvailableTrips({
    required String departureQuery,
    required String arrivalQuery,
    required DateTime departureDate,
    int limit = 300,
  }) async {
    final String date = _formatApiDate(departureDate);
    final String normalizedDeparture = normalizeAddressSearch(departureQuery);
    final String normalizedArrival = normalizeAddressSearch(arrivalQuery);

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('status', isEqualTo: 'published')
        .limit(limit)
        .get();

    final List<TripSearchResult> results = <TripSearchResult>[];
    final List<TripSearchResult> trips = snapshot.docs.map(_tripFromDoc).whereType<TripSearchResult>().toList(growable: false);
    for (final TripSearchResult trip in trips) {
      final String rawDepartureDate = trip.departureDate;
      final TripFrequency frequency = safeTripFrequency(
        trip.tripFrequency,
        isFrequentTripFallback: trip.isFrequentTrip,
      );
      final bool matchesDate = matchesTripForSearchDate(
        tripDepartureDate: rawDepartureDate,
        searchDate: date,
        tripFrequency: frequency,
      );
      if (!matchesDate) continue;

      final _TripCardSegmentView? segment = buildTripCardSegmentView(
        trip: trip,
        departureQuery: normalizedDeparture,
        arrivalQuery: normalizedArrival,
      );
      if (segment == null) continue;

      final _RouteNode fromNode = segment.fromNode;
      final _RouteNode toNode = segment.toNode;
      final String currency = (trip.currency == 'EUR') ? 'EUR' : 'XOF';
      final String baseDepartureTime = fromNode.time.isEmpty ? (trip.departureTime ?? '') : fromNode.time;
      final String? segmentArrivalTime = await _computeIntermediateSegmentArrivalTime(
        fromNode: fromNode,
        toNode: toNode,
        departureTime: baseDepartureTime,
      );

      final Map<String, dynamic> raw = <String, dynamic>{
        ...trip.raw,
        'isIntermediateDeparture': fromNode.kind == 'stop',
        'isIntermediateArrival': toNode.kind == 'stop',
      };
      if (segmentArrivalTime != null && segmentArrivalTime.isNotEmpty) {
        raw['arrivalEstimatedTime'] = segmentArrivalTime;
      }

      results.add(
        TripSearchResult(
          id: trip.id,
          departurePlace: fromNode.address.isEmpty ? trip.departurePlace : fromNode.address,
          arrivalPlace: toNode.address.isEmpty ? trip.arrivalPlace : toNode.address,
          departureDate: date,
          departureTime: baseDepartureTime,
          driverName: trip.driverName,
          contactPhone: trip.contactPhone,
          trackNum: trip.trackNum,
          seats: trip.seats,
          pricePerSeat: segment.segmentPrice.toDouble(),
          currency: currency,
          tripFrequency: trip.tripFrequency,
          isFrequentTrip: trip.isFrequentTrip,
          effectiveDepartureDate: date,
          raw: raw,
        ),
      );
    }

    results.sort((a, b) {
      final String ad = a.effectiveDepartureDate ?? a.departureDate;
      final String bd = b.effectiveDepartureDate ?? b.departureDate;
      final int dateCmp = ad.compareTo(bd);
      if (dateCmp != 0) return dateCmp;
      final String at = a.departureTime ?? '99:99';
      final String bt = b.departureTime ?? '99:99';
      return at.compareTo(bt);
    });

    return results;
  }

  Future<List<TripSearchResult>> fetchFeaturedProTrips({int limit = 6}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('status', isEqualTo: 'published')
        .limit(limit * 3)
        .get();

    final List<TripSearchResult> trips = snapshot.docs
        .map(_tripFromDoc)
        .whereType<TripSearchResult>()
        .where((TripSearchResult trip) => (trip.seats ?? 0) > 0)
        .toList(growable: false);

    trips.sort((a, b) {
      final bool aPro = a.raw['isBus'] == true;
      final bool bPro = b.raw['isBus'] == true;
      if (aPro != bPro) return aPro ? -1 : 1;

      final double aPrice = a.pricePerSeat ?? 0;
      final double bPrice = b.pricePerSeat ?? 0;
      final int priceCompare = aPrice.compareTo(bPrice);
      if (priceCompare != 0) return priceCompare;

      final String aTime = a.departureTime ?? '99:99';
      final String bTime = b.departureTime ?? '99:99';
      return aTime.compareTo(bTime);
    });

    return trips.take(limit).toList(growable: false);
  }

  Future<String?> _computeIntermediateSegmentArrivalTime({
    required _RouteNode fromNode,
    required _RouteNode toNode,
    required String departureTime,
  }) async {
    if (fromNode.kind != 'stop' || toNode.kind != 'stop') return null;
    if (fromNode.lat == null || fromNode.lng == null || toNode.lat == null || toNode.lng == null) {
      return null;
    }
    if (departureTime.trim().isEmpty) return null;

    final int? minutes = await _fetchDirectionsMinutes(
      originLat: fromNode.lat!,
      originLng: fromNode.lng!,
      destinationLat: toNode.lat!,
      destinationLng: toNode.lng!,
    );
    if (minutes == null || minutes <= 0) return null;
    return _addMinutesToTime(departureTime, minutes);
  }

  Future<int?> _fetchDirectionsMinutes({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    if (_googleMapsApiKey.trim().isEmpty) return null;
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$originLat,$originLng',
        'destination': '$destinationLat,$destinationLng',
        'mode': 'driving',
        'departure_time': '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
        'traffic_model': 'best_guess',
        'key': _googleMapsApiKey,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();
      if (status != 'OK') return null;

      final List<dynamic> routes = (json['routes'] as List<dynamic>? ?? <dynamic>[]);
      if (routes.isEmpty) return null;
      final Map<String, dynamic>? route0 = routes.first as Map<String, dynamic>?;
      final List<dynamic> legs = (route0?['legs'] as List<dynamic>? ?? <dynamic>[]);
      if (legs.isEmpty) return null;
      final Map<String, dynamic>? leg0 = legs.first as Map<String, dynamic>?;
      final Map<String, dynamic>? durationTraffic = leg0?['duration_in_traffic'] as Map<String, dynamic>?;
      final Map<String, dynamic>? duration = leg0?['duration'] as Map<String, dynamic>?;
      final int totalSeconds =
          ((durationTraffic?['value'] as num?) ?? (duration?['value'] as num?) ?? 0).toInt();
      if (totalSeconds <= 0) return null;
      return (totalSeconds / 60).round();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _addMinutesToTime(String hhmm, int minutesToAdd) {
    final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (match == null) return null;
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    final DateTime base = DateTime(2000, 1, 1, hour, minute);
    final DateTime next = base.add(Duration(minutes: minutesToAdd));
    final String h = next.hour.toString().padLeft(2, '0');
    final String m = next.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _buildDedupeKey(Map<String, dynamic> payload) {
    final String departure = (payload['departurePlace'] as String? ?? '').trim().toLowerCase();
    final String arrival = (payload['arrivalPlace'] as String? ?? '').trim().toLowerCase();
    final String date = (payload['departureDate'] as String? ?? '').trim();
    final String time = (payload['departureTime'] as String? ?? '').trim();
    final String driver = (payload['driverName'] as String? ?? '').trim().toLowerCase();
    final String phone = (payload['contactPhone'] as String? ?? '').trim().toLowerCase();
    final String seats = (payload['seats'] ?? '').toString();
    final String price = (payload['pricePerSeat'] ?? '').toString();
    final String currency = (payload['currency'] as String? ?? '').trim().toUpperCase();
    return '$departure|$arrival|$date|$time|$driver|$phone|$seats|$price|$currency';
  }

  TripSearchResult? _tripFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    final String departurePlace = (data['departurePlace'] as String? ?? '').trim();
    final String arrivalPlace = (data['arrivalPlace'] as String? ?? '').trim();
    final String departureDate = (data['departureDate'] as String? ?? '').trim();
    final String departureTime = (data['departureTime'] as String? ?? '').trim();
    if (departurePlace.isEmpty || arrivalPlace.isEmpty || departureDate.isEmpty || departureTime.isEmpty) {
      return null;
    }
    final bool isFrequent = data['isFrequentTrip'] == true;
    final String rawFrequency = _safeString(data['tripFrequency']);
    final TripFrequency parsedFrequency = safeTripFrequency(
      rawFrequency,
      isFrequentTripFallback: isFrequent,
    );

    return TripSearchResult(
      id: doc.id,
      departurePlace: departurePlace,
      arrivalPlace: arrivalPlace,
      departureDate: departureDate,
      departureTime: departureTime,
      driverName: (data['driverName'] as String?)?.trim(),
      contactPhone: (data['contactPhone'] as String?)?.trim(),
      trackNum: (data['trackNum'] as String?)?.trim(),
      seats: _toInt(data['seats']),
      pricePerSeat: _toDouble(data['pricePerSeat']),
      currency: (data['currency'] as String?)?.trim().toUpperCase(),
      tripFrequency: _tripFrequencyToRaw(parsedFrequency),
      isFrequentTrip: isFrequent || parsedFrequency != TripFrequency.none,
      raw: data,
    );
  }

  String _formatApiDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  String _safeString(Object? value) => value is String ? value.trim() : '';
}

enum TripFrequency { none, daily, weekly, monthly }

TripFrequency parseTripFrequency(String? value) {
  switch ((value ?? '').trim()) {
    case 'daily':
      return TripFrequency.daily;
    case 'weekly':
      return TripFrequency.weekly;
    case 'monthly':
      return TripFrequency.monthly;
    case 'none':
    default:
      return TripFrequency.none;
  }
}

TripFrequency safeTripFrequency(dynamic raw, {required bool isFrequentTripFallback}) {
  final String v = (raw ?? '').toString().trim();
  if (v == 'daily' || v == 'weekly' || v == 'monthly' || v == 'none') {
    return parseTripFrequency(v);
  }
  return isFrequentTripFallback ? TripFrequency.weekly : TripFrequency.none;
}

String _tripFrequencyToRaw(TripFrequency value) {
  switch (value) {
    case TripFrequency.daily:
      return 'daily';
    case TripFrequency.weekly:
      return 'weekly';
    case TripFrequency.monthly:
      return 'monthly';
    case TripFrequency.none:
      return 'none';
  }
}

class _ParsedIsoDate {
  const _ParsedIsoDate(this.year, this.month, this.day, this.utcDate);
  final int year;
  final int month;
  final int day;
  final DateTime utcDate;
}

_ParsedIsoDate? _parseIsoDateStrict(String value) {
  final String raw = value.trim();
  final Match? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (m == null) return null;

  final int? year = int.tryParse(m.group(1)!);
  final int? month = int.tryParse(m.group(2)!);
  final int? day = int.tryParse(m.group(3)!);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12) return null;

  final DateTime dt = DateTime.utc(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;

  return _ParsedIsoDate(year, month, day, dt);
}

int _diffDaysUtc(DateTime a, DateTime b) {
  return b.difference(a).inMilliseconds ~/ 86400000;
}

int _daysInMonth(int year, int month) {
  return DateTime.utc(year, month + 1, 0).day;
}

int _diffMonths(_ParsedIsoDate a, _ParsedIsoDate b) {
  return (b.year - a.year) * 12 + (b.month - a.month);
}

bool matchesTripForSearchDate({
  required String tripDepartureDate,
  required String searchDate,
  TripFrequency tripFrequency = TripFrequency.none,
}) {
  final _ParsedIsoDate? start = _parseIsoDateStrict(tripDepartureDate);
  final _ParsedIsoDate? target = _parseIsoDateStrict(searchDate);
  if (start == null || target == null) return false;

  if (tripFrequency == TripFrequency.none) {
    return start.year == target.year && start.month == target.month && start.day == target.day;
  }

  final int dayGap = _diffDaysUtc(start.utcDate, target.utcDate);
  if (dayGap < 0) return false;

  if (tripFrequency == TripFrequency.daily) return true;
  if (tripFrequency == TripFrequency.weekly) return dayGap % 7 == 0;

  final int monthGap = _diffMonths(start, target);
  if (monthGap < 0) return false;
  final int expectedDay = start.day <= _daysInMonth(target.year, target.month)
      ? start.day
      : _daysInMonth(target.year, target.month);
  return target.day == expectedDay;
}

class _RouteNode {
  const _RouteNode({
    required this.kind,
    required this.city,
    required this.time,
    required this.priceFromDeparture,
    required this.address,
    this.lat,
    this.lng,
  });

  final String kind;
  final String city;
  final String time;
  final int priceFromDeparture;
  final String address;
  final double? lat;
  final double? lng;
}

class _TripCardSegmentView {
  const _TripCardSegmentView({
    required this.fromNode,
    required this.toNode,
    required this.segmentPrice,
  });

  final _RouteNode fromNode;
  final _RouteNode toNode;
  final int segmentPrice;
}

String cityToken(String address) => (address.split(',').first).trim();

String normalizeAddressSearch(String value) {
  String s = value.toLowerCase().trim();
  const Map<String, String> map = <String, String>{
    'a': 'àáâãäå',
    'c': 'ç',
    'e': 'èéêë',
    'i': 'ìíîï',
    'n': 'ñ',
    'o': 'òóôõö',
    'u': 'ùúûü',
    'y': 'ýÿ',
  };
  map.forEach((ascii, chars) {
    for (final String ch in chars.split('')) {
      s = s.replaceAll(ch, ascii);
    }
  });
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

List<String> _addressTokens(String address) {
  final List<String> out = <String>[];
  final String first = normalizeAddressSearch(cityToken(address));
  if (first.isNotEmpty && !out.contains(first)) out.add(first);
  for (final String part in address.split(',')) {
    final String token = normalizeAddressSearch(part);
    if (token.isNotEmpty && !out.contains(token)) out.add(token);
  }
  return out;
}

String _normalizeLoose(String value) {
  return value
      .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isGenericGeoToken(String value) {
  final String v = _normalizeLoose(value);
  return v.isEmpty ||
      v == 'ci' ||
      v == 'cote d ivoire' ||
      v == 'cote divoire' ||
      v == 'ivory coast';
}

bool _similarToken(String a, String b) {
  final String left = _normalizeLoose(a);
  final String right = _normalizeLoose(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (_isGenericGeoToken(left) || _isGenericGeoToken(right)) return false;

  // Strong match: exact normalized token.
  if (left == right) return true;

  // Prefix match only for meaningful strings (e.g. "napi" <-> "napie").
  if (left.length >= 4 && right.length >= 4) {
    if (left.startsWith(right) || right.startsWith(left)) return true;
  }

  // Word-level exact match to support queries typed with extra words.
  final Set<String> leftWords = left.split(' ').where((w) => w.length >= 4).toSet();
  final Set<String> rightWords = right.split(' ').where((w) => w.length >= 4).toSet();
  if (leftWords.isNotEmpty && rightWords.isNotEmpty) {
    for (final String lw in leftWords) {
      if (rightWords.contains(lw)) return true;
    }
  }
  return false;
}

bool matchesAddressQuery(String queryAddress, String candidateAddress) {
  final List<String> queryTokens = _addressTokens(queryAddress);
  final List<String> candidateTokens = _addressTokens(candidateAddress);
  if (queryTokens.isEmpty) return true;
  if (candidateTokens.isEmpty) return false;

  for (final String q in queryTokens) {
    for (final String c in candidateTokens) {
      if (_similarToken(c, q)) return true;
    }
  }
  return false;
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.'));
}

List<_RouteNode> buildRouteNodes(
  TripSearchResult trip, {
  List<Map<String, dynamic>> intermediateStops = const <Map<String, dynamic>>[],
}) {
  final List<_RouteNode> stops = intermediateStops.map((s) {
    final String address = (s['address'] ?? '').toString().trim();
    return _RouteNode(
      kind: 'stop',
      city: cityToken(address),
      time: (s['estimatedTime'] ?? '').toString().trim(),
      priceFromDeparture: ((s['priceFromDeparture'] ?? 0) as num).toInt().clamp(0, 1 << 30),
      address: address,
      lat: _toDoubleOrNull(s['lat']),
      lng: _toDoubleOrNull(s['lng']),
    );
  }).toList(growable: false);

  return <_RouteNode>[
    _RouteNode(
      kind: 'departure',
      city: cityToken(trip.departurePlace),
      time: (trip.departureTime ?? '').trim(),
      priceFromDeparture: 0,
      address: trip.departurePlace,
      lat: _toDoubleOrNull(trip.raw['departureLat']),
      lng: _toDoubleOrNull(trip.raw['departureLng']),
    ),
    ...stops,
    _RouteNode(
      kind: 'arrival',
      city: cityToken(trip.arrivalPlace),
      time: '',
      priceFromDeparture: (trip.pricePerSeat ?? 0).toInt().clamp(0, 1 << 30),
      address: trip.arrivalPlace,
      lat: _toDoubleOrNull(trip.raw['arrivalLat']),
      lng: _toDoubleOrNull(trip.raw['arrivalLng']),
    ),
  ];
}

int findNodeIndexByQuery(List<_RouteNode> nodes, String queryAddress, {int afterIndex = -1}) {
  if (queryAddress.isEmpty) return -1;
  for (int i = 0; i < nodes.length; i++) {
    if (i <= afterIndex) continue;
    if (matchesAddressQuery(queryAddress, nodes[i].address)) return i;
  }
  return -1;
}

_TripCardSegmentView? buildTripCardSegmentView({
  required TripSearchResult trip,
  required String departureQuery,
  required String arrivalQuery,
}) {
  final List<Map<String, dynamic>> intermediateStops =
      (trip.raw['intermediateStops'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

  final List<_RouteNode> nodes = buildRouteNodes(
    trip,
    intermediateStops: intermediateStops,
  ).where((n) => n.address.trim().isNotEmpty).toList(growable: false);
  if (nodes.isEmpty) return null;

  final int depIndex = departureQuery.isNotEmpty ? findNodeIndexByQuery(nodes, departureQuery) : 0;
  if (depIndex < 0) return null;

  final int arrIndex = arrivalQuery.isNotEmpty
      ? findNodeIndexByQuery(nodes, arrivalQuery, afterIndex: depIndex)
      : nodes.length - 1;
  if (arrIndex < 0 || arrIndex <= depIndex) return null;

  final _RouteNode fromNode = nodes[depIndex];
  final _RouteNode toNode = nodes[arrIndex];
  final int segmentPrice = (toNode.priceFromDeparture - fromNode.priceFromDeparture).clamp(0, 1 << 30);

  return _TripCardSegmentView(
    fromNode: fromNode,
    toNode: toNode,
    segmentPrice: segmentPrice,
  );
}

/// Numero de suivi sur 8 chiffres.
/// Logique web: Date.now() + entropy(00..99), puis on garde les 8 derniers caracteres.
String generateTrackingNumber() {
  final int nowMs = DateTime.now().millisecondsSinceEpoch;
  final int entropy = Random().nextInt(100);
  final String mixed = '$nowMs$entropy';
  return mixed.substring(mixed.length - 8);
}

/// Wrapper metier voyage (comme sur Next.js).
String generateVoyageTrackNum() => generateTrackingNumber();
