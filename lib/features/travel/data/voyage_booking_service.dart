import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';

class VoyageBookingService {
  VoyageBookingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<VoyageBookingDocument> createBooking(CreateVoyageBookingInput input) async {
    final String? inputError = validateCreateVoyageBookingInput(input);
    if (inputError != null) throw Exception(inputError);

    final DocumentReference<Map<String, dynamic>> tripRef = _firestore.collection('voyageTrips').doc(input.tripId);
    final String idempotencyKey = (input.idempotencyKey ?? '').trim();
    final DocumentReference<Map<String, dynamic>> bookingRef = idempotencyKey.isEmpty
        ? _firestore.collection('voyageBookings').doc()
        : _firestore.collection('voyageBookings').doc(idempotencyKey);

    late final Map<String, dynamic> bookingMap;

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> bookingSnap = await transaction.get(bookingRef);
      if (bookingSnap.exists && bookingSnap.data() != null) {
        bookingMap = Map<String, dynamic>.from(bookingSnap.data()!);
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> tripSnap = await transaction.get(tripRef);
      if (!tripSnap.exists || tripSnap.data() == null) {
        throw Exception('Trajet introuvable.');
      }
      final Map<String, dynamic> trip = tripSnap.data()!;

      final String? tripError = validateVoyageTripForBooking(
        trip: trip,
        requestedSeats: input.requestedSeats,
      );
      if (tripError != null) throw Exception(tripError);

      final int availableSeats = _toInt(trip['seats'], 0);
      final int totalPrice = computeVoyageBookingTotalPrice(
        segmentPrice: input.segmentPrice,
        requestedSeats: input.requestedSeats,
      );
      final String bookingTrackNum = _generateTrackingNumber();

      bookingMap = <String, dynamic>{
        'trackNum': bookingTrackNum,
        'tripId': input.tripId,
        'tripTrackNum': _toStringSafe(trip['trackNum']),
        'tripOwnerUid': _toStringSafe(trip['ownerUid']),
        'tripOwnerTrackNum': _toStringSafe(trip['ownerTrackNum']),
        'tripCurrency': _toStringSafe(trip['currency']).isEmpty ? 'XOF' : _toStringSafe(trip['currency']),
        'tripDepartureDate': _toStringSafe(trip['departureDate']),
        'tripDepartureTime': _toStringSafe(trip['departureTime']),
        'tripDeparturePlace': _toStringSafe(trip['departurePlace']),
        'tripArrivalEstimatedTime': _toStringSafe(trip['arrivalEstimatedTime']),
        'tripArrivalPlace': _toStringSafe(trip['arrivalPlace']),
        'tripDriverName': _toStringSafe(trip['driverName']),
        'tripVehicleModel': _toStringSafe(trip['vehicleModel']),
        'tripContactPhone': _toStringSafe(trip['contactPhone']),
        'tripIntermediateStops':
            (trip['intermediateStops'] as List<dynamic>? ?? const <dynamic>[]).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false),
        'requestedSeats': input.requestedSeats,
        'requesterUid': (input.requesterUid ?? '').trim(),
        'requesterTrackNum': (input.requesterTrackNum ?? '').trim(),
        'requesterName': input.requesterName.trim(),
        'requesterContact': input.requesterContact.trim(),
        'requesterEmail': (input.requesterEmail ?? '').trim(),
        'segmentFrom': input.segmentFrom.trim(),
        'segmentTo': input.segmentTo.trim(),
        'segmentPrice': input.segmentPrice,
        'totalPrice': totalPrice,
        'travelers': input.travelers.map((t) => t.toMap()).toList(growable: false),
        'unreadForDriver': 0,
        'unreadForPassenger': 0,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      transaction.update(tripRef, <String, dynamic>{
        'seats': availableSeats - input.requestedSeats,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(bookingRef, bookingMap);
    });

    final Map<String, dynamic> merged = <String, dynamic>{
      ...bookingMap,
      'createdAt': null,
      'updatedAt': null,
    };
    return VoyageBookingDocument.fromMap(bookingRef.id, merged);
  }

  Future<List<VoyageBookingDocument>> fetchBookingsByTripId(String tripId) async {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return const <VoyageBookingDocument>[];

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageBookings')
        .where('tripId', isEqualTo: normalizedTripId)
        .get();

    final List<VoyageBookingDocument> bookings = snapshot.docs
        .map((doc) => VoyageBookingDocument.fromMap(doc.id, doc.data()))
        .toList(growable: false);

    bookings.sort((a, b) {
      final int bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final int aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return bookings;
  }

  Future<List<VoyageBookingDocument>> fetchBookingsByRequesterUid(
    String requesterUid, {
    int limit = 50,
  }) async {
    final String normalizedRequesterUid = requesterUid.trim();
    if (normalizedRequesterUid.isEmpty) return const <VoyageBookingDocument>[];

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageBookings')
        .where('requesterUid', isEqualTo: normalizedRequesterUid)
        .limit(limit)
        .get();

    final List<VoyageBookingDocument> bookings = snapshot.docs
        .map((doc) => VoyageBookingDocument.fromMap(doc.id, doc.data()))
        .toList(growable: false);

    bookings.sort((a, b) {
      final int bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final int aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return bookings;
  }

  Future<VoyageBookingDocument?> findBookingByTrackNum(String trackNum) async {
    final String normalizedTrackNum = trackNum.trim();
    if (normalizedTrackNum.isEmpty) return null;

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('voyageBookings')
        .where('trackNum', isEqualTo: normalizedTrackNum)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = snapshot.docs.first;
    return VoyageBookingDocument.fromMap(doc.id, doc.data());
  }

  Future<void> updateBookingStatus({
    required String bookingId,
    required String status,
  }) async {
    final String normalizedBookingId = bookingId.trim();
    final String normalizedStatus = status.trim();
    if (normalizedBookingId.isEmpty || normalizedStatus.isEmpty) return;

    await _firestore.collection('voyageBookings').doc(normalizedBookingId).set(
      <String, dynamic>{
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> cancelBookingById({
    required String bookingId,
    required String tripId,
    required int requestedSeats,
  }) async {
    final String normalizedBookingId = bookingId.trim();
    final String normalizedTripId = tripId.trim();
    if (normalizedBookingId.isEmpty) return;

    final DocumentReference<Map<String, dynamic>> bookingRef = _firestore.collection('voyageBookings').doc(normalizedBookingId);
    final DocumentReference<Map<String, dynamic>> tripRef = _firestore.collection('voyageTrips').doc(normalizedTripId);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> bookingSnap = await transaction.get(bookingRef);
      if (!bookingSnap.exists || bookingSnap.data() == null) {
        throw Exception('Reservation introuvable.');
      }

      final Map<String, dynamic> booking = bookingSnap.data()!;
      final String status = (booking['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'cancelled') {
        return;
      }
      if (status == 'rejected' || status == 'refused') {
        throw Exception('Reservation non annulable.');
      }

      transaction.set(
        bookingRef,
        <String, dynamic>{
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (normalizedTripId.isEmpty || requestedSeats <= 0) {
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> tripSnap = await transaction.get(tripRef);
      if (!tripSnap.exists || tripSnap.data() == null) {
        return;
      }

      final int availableSeats = _toInt(tripSnap.data()!['seats'], 0);
      transaction.set(
        tripRef,
        <String, dynamic>{
          'seats': availableSeats + requestedSeats,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  String _toStringSafe(Object? value) => value is String ? value.trim() : '';

  int _toInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}

String? validateCreateVoyageBookingInput(CreateVoyageBookingInput input) {
  if (input.requestedSeats < 1) {
    return 'Nombre de places invalide.';
  }
  if (input.travelers.length != input.requestedSeats) {
    return 'Le nombre de passagers doit correspondre au nombre de places.';
  }
  if (input.travelers.any((t) => t.name.trim().isEmpty)) {
    return 'Nom passager manquant.';
  }
  if (input.requesterName.trim().isEmpty) {
    return 'Nom du demandeur manquant.';
  }
  final bool isAnonymousRequester = (input.requesterUid ?? '').trim().isEmpty;
  if (isAnonymousRequester && input.requesterContact.trim().isEmpty) {
    return 'Contact du demandeur manquant.';
  }
  if (input.segmentFrom.trim().isEmpty || input.segmentTo.trim().isEmpty) {
    return 'Segment de trajet invalide.';
  }
  return null;
}

String? validateVoyageTripForBooking({
  required Map<String, dynamic> trip,
  required int requestedSeats,
}) {
  final String status = (trip['status'] as String? ?? '').trim();
  if (status != 'published') {
    return 'Trajet non disponible \u00E0 la r\u00E9servation.';
  }
  final int availableSeats = _toIntStatic(trip['seats'], 0);
  if (availableSeats < requestedSeats) {
    return 'Places insuffisantes.';
  }
  return null;
}

int computeVoyageBookingTotalPrice({
  required int segmentPrice,
  required int requestedSeats,
}) {
  final int safeSegmentPrice = segmentPrice < 0 ? 0 : segmentPrice;
  final int safeSeats = requestedSeats < 1 ? 1 : requestedSeats;
  return safeSegmentPrice * safeSeats;
}

int _toIntStatic(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

String _generateTrackingNumber() {
  final int nowMs = DateTime.now().millisecondsSinceEpoch;
  final int entropy = Random().nextInt(100);
  final String mixed = '$nowMs$entropy';
  return mixed.substring(mixed.length - 8);
}
