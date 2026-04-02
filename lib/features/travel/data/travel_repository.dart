import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/notifications/data/firestore_notifications_repository.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
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
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationsRepository = FirestoreNotificationsRepository(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  final FirebaseFirestore _firestore;
  final FirestoreNotificationsRepository _notificationsRepository;

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
      alertCount: 0,
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

      final int capacity = trip.seats ?? 0;
      final int segmentAvailableSeats = _computeSegmentAvailableSeats(
        raw: trip.raw,
        fromAddress: fromNode.address.isEmpty ? trip.departurePlace : fromNode.address,
        toAddress: toNode.address.isEmpty ? trip.arrivalPlace : toNode.address,
        capacity: capacity,
      );
      raw['segmentAvailableSeats'] = segmentAvailableSeats;

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

  Future<List<TripSearchResult>> fetchTripsByCompanyName(String companyName, {int limit = 40}) async {
    if (companyName.trim().isEmpty) return const <TripSearchResult>[];
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('status', isEqualTo: 'published')
        .limit(300)
        .get();
    final String cn = normalizeAddressSearch(companyName);
    final List<TripSearchResult> trips = snapshot.docs
        .map(_tripFromDoc)
        .whereType<TripSearchResult>()
        .where((TripSearchResult t) {
          if (t.driverName == null || t.driverName!.isEmpty) return false;
          final String dn = normalizeAddressSearch(t.driverName!);
          return dn.contains(cn) || cn.contains(dn);
        })
        .toList(growable: true);
    trips.sort((a, b) => a.departureDate.compareTo(b.departureDate));
    return trips.take(limit).toList(growable: false);
  }

  Future<List<TripSearchResult>> fetchTripsByOwnerUid(String ownerUid, {int limit = 50}) async {
    final String normalizedUid = ownerUid.trim();
    if (normalizedUid.isEmpty) return const <TripSearchResult>[];

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('ownerUid', isEqualTo: normalizedUid)
        .limit(limit)
        .get();

    final List<TripSearchResult> trips = snapshot.docs
        .map(_tripFromDoc)
        .whereType<TripSearchResult>()
        .toList(growable: false);

    trips.sort((a, b) {
      final String ad = a.departureDate;
      final String bd = b.departureDate;
      final int dateCompare = bd.compareTo(ad);
      if (dateCompare != 0) return dateCompare;
      final String at = a.departureTime ?? '00:00';
      final String bt = b.departureTime ?? '00:00';
      return bt.compareTo(at);
    });

    return trips;
  }

  Future<TripSearchResult?> findTripByTrackNum(String trackNum) async {
    final String normalizedTrackNum = trackNum.trim();
    if (normalizedTrackNum.isEmpty) return null;

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageTrips')
        .where('trackNum', isEqualTo: normalizedTrackNum)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return _tripFromDoc(snapshot.docs.first);
  }

  Future<Map<String, dynamic>?> getTripRawById(String tripId) async {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('voyageTrips').doc(normalizedTripId).get();
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<TripSearchResult?> fetchTripById(String tripId) async {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('voyageTrips').doc(normalizedTripId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return _tripFromData(snapshot.id, snapshot.data()!);
  }

  Future<PublishedTripResult> updateTrip(
    String tripId,
    Map<String, dynamic> payload,
  ) async {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw ArgumentError('tripId must not be empty');
    }

    final DocumentReference<Map<String, dynamic>> tripRef =
        _firestore.collection('voyageTrips').doc(normalizedTripId);
    final DocumentSnapshot<Map<String, dynamic>> existingSnapshot = await tripRef.get();
    final Map<String, dynamic> existing = existingSnapshot.data() ?? <String, dynamic>{};
    final String trackNum =
        (existing['trackNum'] as String?)?.trim().isNotEmpty == true
            ? (existing['trackNum'] as String).trim()
            : generateVoyageTrackNum();
    final Timestamp? createdAt = existing['createdAt'] as Timestamp?;
    final List<String> changedFields = _detectSensitiveTripChanges(
      before: existing,
      after: payload,
    );

    await tripRef.set(
      <String, dynamic>{
        ...payload,
        'dedupeKey': _buildDedupeKey(payload),
        'trackNum': trackNum,
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final int alertCount = changedFields.isEmpty
        ? 0
        : await _createTripUpdateAlerts(
            tripId: normalizedTripId,
            tripTrackNum: trackNum,
            existingTrip: existing,
            updatedPayload: payload,
            changedFields: changedFields,
          );

    return PublishedTripResult(
      id: normalizedTripId,
      trackNum: trackNum,
      wasCreated: false,
      alertCount: alertCount,
    );
  }

  List<String> _detectSensitiveTripChanges({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    final List<String> changed = <String>[];

    void compareStringField(String key) {
      if (_normalizeScalar(before[key]) != _normalizeScalar(after[key])) {
        changed.add(key);
      }
    }

    void compareNumericField(String key) {
      if (_normalizeScalar(before[key]) != _normalizeScalar(after[key])) {
        changed.add(key);
      }
    }

    compareStringField('departurePlace');
    compareStringField('arrivalPlace');
    compareStringField('departureDate');
    compareStringField('departureTime');
    compareNumericField('pricePerSeat');
    compareNumericField('seats');
    compareStringField('vehicleModel');
    compareStringField('contactPhone');
    compareStringField('driverName');

    final String beforeStops = _normalizeStops(before['intermediateStops']);
    final String afterStops = _normalizeStops(after['intermediateStops']);
    if (beforeStops != afterStops) {
      changed.add('intermediateStops');
    }

    return changed;
  }

  Future<int> _createTripUpdateAlerts({
    required String tripId,
    required String tripTrackNum,
    required Map<String, dynamic> existingTrip,
    required Map<String, dynamic> updatedPayload,
    required List<String> changedFields,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> bookingsSnapshot = await _firestore
        .collection('voyageBookings')
        .where('tripId', isEqualTo: tripId)
        .get();

    if (bookingsSnapshot.docs.isEmpty) return 0;

    final CollectionReference<Map<String, dynamic>> alertsRef =
        _firestore.collection('voyageTripAlerts');
    final Map<String, dynamic> oldValues = _extractAlertValues(existingTrip, changedFields);
    final Map<String, dynamic> newValues = _extractAlertValues(updatedPayload, changedFields);
    final String message =
        'Le trajet $tripTrackNum a été modifié. Des réservations liées sont potentiellement impactées.';
    final List<CreateAppNotificationInput> notifications =
        <CreateAppNotificationInput>[];

    final WriteBatch batch = _firestore.batch();
    int count = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> bookingDoc in bookingsSnapshot.docs) {
      final Map<String, dynamic> booking = bookingDoc.data();
      final String requesterUid = _safeString(booking['requesterUid']);
      final DocumentReference<Map<String, dynamic>> alertRef = alertsRef.doc();
      batch.set(alertRef, <String, dynamic>{
        'type': 'trip_updated',
        'status': 'pending',
        'message': message,
        'tripId': tripId,
        'tripTrackNum': tripTrackNum,
        'tripOwnerUid': _safeString(updatedPayload['ownerUid']).isEmpty
            ? _safeString(existingTrip['ownerUid'])
            : _safeString(updatedPayload['ownerUid']),
        'bookingId': bookingDoc.id,
        'bookingTrackNum': _safeString(booking['trackNum']),
        'bookingStatus': _safeString(booking['status']).isEmpty
            ? 'pending'
            : _safeString(booking['status']),
        'requesterUid': _safeString(booking['requesterUid']),
        'requesterName': _safeString(booking['requesterName']),
        'requesterContact': _safeString(booking['requesterContact']),
        'changedFields': changedFields,
        'oldValues': oldValues,
        'newValues': newValues,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      notifications.add(
        CreateAppNotificationInput(
          userId: requesterUid,
          domain: 'travel',
          type: 'trip_updated',
          title: 'Trajet modifié',
          body: 'Un trajet réservé a été mis à jour. Ouvrez-le pour voir les changements.',
          entityType: 'trip',
          entityId: tripId,
          data: <String, dynamic>{
            'tripId': tripId,
            'tripTrackNum': tripTrackNum,
            'bookingId': bookingDoc.id,
            'bookingTrackNum': _safeString(booking['trackNum']),
            'changedFields': changedFields,
            'requesterUid': requesterUid,
          },
        ),
      );
      count++;
    }

    await batch.commit();
    await _notificationsRepository.createNotifications(notifications);
    return count;
  }

  Map<String, dynamic> _extractAlertValues(
    Map<String, dynamic> source,
    List<String> fields,
  ) {
    final Map<String, dynamic> values = <String, dynamic>{};
    for (final String field in fields) {
      if (field == 'intermediateStops') {
        values[field] = (source[field] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false);
      } else {
        values[field] = source[field];
      }
    }
    return values;
  }

  String _normalizeStops(Object? raw) {
    final List<Map<String, dynamic>> stops = (raw as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(
          (stop) => <String, dynamic>{
            'address': _safeString(stop['address']),
            'estimatedTime': _safeString(stop['estimatedTime']),
            'priceFromDeparture': _normalizeScalar(stop['priceFromDeparture']),
            'selected': stop['selected'] != false,
          },
        )
        .toList(growable: false);
    return jsonEncode(stops);
  }

  String _normalizeScalar(Object? value) {
    if (value == null) return '';
    if (value is num) return value.toString();
    if (value is bool) return value ? 'true' : 'false';
    return value.toString().trim();
  }

  Future<void> cancelTripById(String tripId) async {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return;

    final DocumentReference<Map<String, dynamic>> tripRef =
        _firestore.collection('voyageTrips').doc(normalizedTripId);
    final DocumentSnapshot<Map<String, dynamic>> tripSnapshot = await tripRef.get();
    final Map<String, dynamic> trip = tripSnapshot.data() ?? const <String, dynamic>{};

    await _firestore.collection('voyageTrips').doc(normalizedTripId).set(
      <String, dynamic>{
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final QuerySnapshot<Map<String, dynamic>> bookingsSnapshot = await _firestore
        .collection('voyageBookings')
        .where('tripId', isEqualTo: normalizedTripId)
        .get();

    if (bookingsSnapshot.docs.isEmpty) return;

    final String tripTrackNum = _safeString(trip['trackNum']);
    final List<CreateAppNotificationInput> notifications = bookingsSnapshot.docs
        .map((doc) {
          final Map<String, dynamic> booking = doc.data();
          final String requesterUid = _safeString(booking['requesterUid']);
          return CreateAppNotificationInput(
            userId: requesterUid,
            domain: 'travel',
            type: 'trip_cancelled',
            title: 'Trajet annulé',
            body: 'Un trajet réservé a été annulé.',
            entityType: 'trip',
            entityId: normalizedTripId,
            data: <String, dynamic>{
              'tripId': normalizedTripId,
              'tripTrackNum': tripTrackNum,
              'bookingId': doc.id,
              'bookingTrackNum': _safeString(booking['trackNum']),
              'requesterUid': requesterUid,
            },
          );
        })
        .where((input) => input.userId.trim().isNotEmpty)
        .toList(growable: false);

    await _notificationsRepository.createNotifications(notifications);
  }

  Future<String?> _computeIntermediateSegmentArrivalTime({
    required _RouteNode fromNode,
    required _RouteNode toNode,
    required String departureTime,
  }) async {
    // Départ initial → arrêt intermédiaire : utiliser l'heure estimée de l'arrêt
    if (fromNode.kind != 'stop' && toNode.kind == 'stop') {
      return toNode.time.trim().isEmpty ? null : toNode.time.trim();
    }
    // Arrêt intermédiaire → destination finale : garder arrivalEstimatedTime du trajet
    if (toNode.kind != 'stop') return null;
    // Arrêt intermédiaire → arrêt intermédiaire : calculer via Google Maps
    if (fromNode.lat == null || fromNode.lng == null || toNode.lat == null || toNode.lng == null) {
      return toNode.time.trim().isEmpty ? null : toNode.time.trim();
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
    if (RuntimeAppConfig.googleMapsApiKey.trim().isEmpty) return null;
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$originLat,$originLng',
        'destination': '$destinationLat,$destinationLng',
        'mode': 'driving',
        'departure_time': '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
        'traffic_model': 'best_guess',
        'key': RuntimeAppConfig.googleMapsApiKey,
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
    return _tripFromData(doc.id, doc.data());
  }

  TripSearchResult? _tripFromData(String id, Map<String, dynamic> data) {
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
      id: id,
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

int _computeSegmentAvailableSeats({
  required Map<String, dynamic> raw,
  required String fromAddress,
  required String toAddress,
  required int capacity,
}) {
  final Object? occ = raw['segmentOccupancy'];
  if (occ is! Map || occ.isEmpty) return capacity;
  final Map<String, dynamic> occupancy = Map<String, dynamic>.from(occ);

  // Utiliser segmentPoints (array ordonné) pour éviter les problèmes d'ordre Firestore
  final List<String> points = (raw['segmentPoints'] as List<dynamic>? ?? const <dynamic>[])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (points.length < 2) return capacity;

  final int fromIdx = points.indexWhere((p) => p == fromAddress.trim());
  final int toIdx = points.indexWhere((p) => p == toAddress.trim());
  if (fromIdx < 0 || toIdx < 0 || toIdx <= fromIdx) return capacity;

  int maxOccupied = 0;
  for (int i = fromIdx; i < toIdx; i++) {
    final String key = '${points[i]}__${points[i + 1]}';
    final int occupied = (occupancy[key] as num?)?.toInt() ?? 0;
    if (occupied > maxOccupied) maxOccupied = occupied;
  }
  return (capacity - maxOccupied).clamp(0, capacity);
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
          .where((s) => s['bookable'] != false && s['toStop'] == null)
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
