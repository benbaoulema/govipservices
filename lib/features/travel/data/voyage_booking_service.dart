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
    final DocumentReference<Map<String, dynamic>> bookingRef = _firestore.collection('voyageBookings').doc();

    late final Map<String, dynamic> bookingMap;
    final String duplicateKey = buildVoyageBookingDuplicateKey(input);
    final DocumentReference<Map<String, dynamic>> lockRef =
        _firestore.collection('voyageBookingLocks').doc(duplicateKey);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> tripSnap = await transaction.get(tripRef);
      if (!tripSnap.exists || tripSnap.data() == null) {
        throw Exception('Trajet introuvable.');
      }
      final Map<String, dynamic> trip = tripSnap.data()!;

      final DocumentSnapshot<Map<String, dynamic>> lockSnap = await transaction.get(lockRef);
      if (lockSnap.exists) {
        throw Exception('Reservation deja enregistree (doublon).');
      }

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
      transaction.set(lockRef, <String, dynamic>{
        'bookingId': bookingRef.id,
        'tripId': input.tripId,
        'requesterUid': (input.requesterUid ?? '').trim(),
        'requesterContact': input.requesterContact.trim(),
        'duplicateKey': duplicateKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    final Map<String, dynamic> merged = <String, dynamic>{
      ...bookingMap,
      'createdAt': null,
      'updatedAt': null,
    };
    return VoyageBookingDocument.fromMap(bookingRef.id, merged);
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
  if (input.requesterContact.trim().isEmpty) {
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
    return 'Trajet non disponible a la reservation.';
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

String buildVoyageBookingDuplicateKey(CreateVoyageBookingInput input) {
  final String requesterIdentity = (input.requesterUid ?? '').trim().isNotEmpty
      ? (input.requesterUid ?? '').trim()
      : input.requesterContact.trim();
  final String travelersSignature = input.travelers
      .map((t) => '${_normalizeKeyPart(t.name)}:${_normalizeKeyPart(t.contact)}')
      .join('|');

  return <String>[
    _normalizeKeyPart(input.tripId),
    _normalizeKeyPart(input.segmentFrom),
    _normalizeKeyPart(input.segmentTo),
    _normalizeKeyPart(requesterIdentity),
    input.requestedSeats.toString(),
    travelersSignature,
  ].join('::');
}

String _normalizeKeyPart(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
