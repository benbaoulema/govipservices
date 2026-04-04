import 'dart:math';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/notifications/data/firestore_notifications_repository.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/wallet/data/wallet_service.dart';

class VoyageBookingService {
  VoyageBookingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationsRepository = FirestoreNotificationsRepository(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  final FirebaseFirestore _firestore;
  final FirestoreNotificationsRepository _notificationsRepository;

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
      final String tripFrequency =
          _normalizedTripFrequency(_toStringSafe(trip['tripFrequency']));
      final String effectiveDepartureDate =
          _resolveEffectiveDepartureDate(input, trip);
      final bool usesOccurrences = tripFrequency != 'none';
      final bool isBus = trip['isBus'] == true;

      final String? tripError = validateVoyageTripForBooking(
        trip: trip,
        requestedSeats: input.requestedSeats,
        effectiveDepartureDate: effectiveDepartureDate,
      );
      if (tripError != null) throw Exception(tripError);

      final int baseCapacity = _toInt(trip['seats'], 0);
      final Map<String, dynamic> tripSegmentOccupancy = _parseSegmentOccupancy(
        trip['segmentOccupancy'],
      );
      final List<String> segmentPoints = (trip['segmentPoints'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final bool usesSegments = tripSegmentOccupancy.isNotEmpty && segmentPoints.length >= 2;
      final DocumentReference<Map<String, dynamic>>? occurrenceRef = usesOccurrences
          ? _occurrenceRef(tripRef, effectiveDepartureDate)
          : null;
      final Map<String, dynamic>? occurrence = occurrenceRef == null
          ? null
          : await _readOccurrence(
              transaction: transaction,
              occurrenceRef: occurrenceRef,
            );
      final Map<String, dynamic> effectiveSegmentOccupancy = usesOccurrences
          ? _resolveOccurrenceSegmentOccupancy(
              occurrence: occurrence,
              fallbackSegmentOccupancy: tripSegmentOccupancy,
            )
          : tripSegmentOccupancy;

      if (usesSegments) {
        final List<String> coveredKeys = _coveredSegmentKeys(
          segmentPoints: segmentPoints,
          segmentOccupancy: effectiveSegmentOccupancy,
          from: input.segmentFrom,
          to: input.segmentTo,
        );
        if (coveredKeys.isEmpty) throw Exception('Ce trajet ne dessert pas ce parcours.');
        _checkSegmentCapacity(
          segmentOccupancy: effectiveSegmentOccupancy,
          coveredKeys: coveredKeys,
          requestedSeats: input.requestedSeats,
          capacity: baseCapacity,
        );
      } else {
        final int availableSeats = usesOccurrences
            ? await _readAvailableSeatsForOccurrence(
                transaction: transaction,
                tripRef: tripRef,
                effectiveDepartureDate: effectiveDepartureDate,
                baseCapacity: baseCapacity,
              )
            : baseCapacity;
        if (availableSeats < input.requestedSeats) {
          throw Exception('Places insuffisantes pour cette date.');
        }
      }
      final int totalPrice = computeVoyageBookingTotalPrice(
        segmentPrice: input.segmentPrice,
        requestedSeats: input.requestedSeats,
      );
      final String bookingTrackNum = _generateTrackingNumber();

      // ── Reward FIFO consumption ────────────────────────────────────────────
      int discountAmount = 0;
      if (input.appliedRewardIds.isNotEmpty && (input.requesterUid ?? '').trim().isNotEmpty) {
        final String uid = input.requesterUid!.trim();
        // Read all reward docs first (reads must precede writes in a transaction)
        final List<DocumentReference<Map<String, dynamic>>> rewardRefs = input.appliedRewardIds
            .map((id) => _firestore.doc('user_rewards/$uid/rewards/$id'))
            .toList(growable: false);
        final List<DocumentSnapshot<Map<String, dynamic>>> rewardSnaps =
            await Future.wait(rewardRefs.map((r) => transaction.get(r)));

        int remaining = totalPrice;
        for (int i = 0; i < rewardSnaps.length; i++) {
          if (remaining <= 0) break;
          final DocumentSnapshot<Map<String, dynamic>> snap = rewardSnaps[i];
          if (!snap.exists || snap.data() == null) continue;
          final Map<String, dynamic> rData = snap.data()!;
          if ((rData['status'] as String? ?? '') != 'available') continue;
          final double effectiveValue =
              (rData['remainingValue'] as num? ?? rData['value'] as num? ?? 0).toDouble();
          if (effectiveValue <= 0) continue;
          final int consumed = effectiveValue.round().clamp(0, remaining);
          discountAmount += consumed;
          remaining -= consumed;
          if (consumed >= effectiveValue.round()) {
            transaction.update(rewardRefs[i], <String, dynamic>{
              'status': 'used',
              'usedAt': FieldValue.serverTimestamp(),
              'remainingValue': 0,
            });
          } else {
            transaction.update(rewardRefs[i], <String, dynamic>{
              'remainingValue': effectiveValue - consumed,
            });
          }
        }
      }

      bookingMap = <String, dynamic>{
        'trackNum': bookingTrackNum,
        'tripId': input.tripId,
        'tripTrackNum': _toStringSafe(trip['trackNum']),
        'tripOwnerUid': _toStringSafe(trip['ownerUid']),
        'tripOwnerTrackNum': _toStringSafe(trip['ownerTrackNum']),
        'tripCurrency': _toStringSafe(trip['currency']).isEmpty ? 'XOF' : _toStringSafe(trip['currency']),
        'tripDepartureDate': effectiveDepartureDate,
        'tripDepartureTime': _toStringSafe(trip['departureTime']),
        'tripFrequency': tripFrequency,
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
        'comfortOptions': input.comfortOptions,
        if (input.appliedRewardIds.isNotEmpty)
          'appliedRewardIds': input.appliedRewardIds,
        if (discountAmount > 0)
          'discountAmount': discountAmount,
        if (input.studentDiscount > 0)
          'studentDiscount': input.studentDiscount,
        if (input.checkoutDiscount > 0)
          'checkoutDiscount': input.checkoutDiscount,
        if (input.paymentDiscount > 0)
          'paymentDiscount': input.paymentDiscount,
        'unreadForDriver': 0,
        'unreadForPassenger': 0,
        'status': isBus ? 'accepted' : 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (usesSegments) {
        final List<String> coveredKeys = _coveredSegmentKeys(
          segmentPoints: segmentPoints,
          segmentOccupancy: effectiveSegmentOccupancy,
          from: input.segmentFrom,
          to: input.segmentTo,
        );
        final Map<String, dynamic> updatedOccupancy = _updatedOccupancy(
          segmentOccupancy: effectiveSegmentOccupancy,
          coveredKeys: coveredKeys,
          seats: input.requestedSeats,
          increment: true,
        );
        if (usesOccurrences && occurrenceRef != null) {
          final int nextRemainingSeats = _computeRemainingSeatsFromOccupancy(
            segmentOccupancy: updatedOccupancy,
            capacity: baseCapacity,
          );
          transaction.set(
            occurrenceRef,
            <String, dynamic>{
              'date': effectiveDepartureDate,
              'capacity': baseCapacity,
              'segmentPoints': segmentPoints,
              'segmentOccupancy': updatedOccupancy,
              'bookedSeats': (baseCapacity - nextRemainingSeats).clamp(0, baseCapacity),
              'remainingSeats': nextRemainingSeats,
              'status': nextRemainingSeats > 0 ? 'active' : 'full',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else {
          transaction.update(tripRef, <String, dynamic>{
            'segmentOccupancy': updatedOccupancy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else if (usesOccurrences) {
        final int availableSeats = await _readAvailableSeatsForOccurrence(
          transaction: transaction,
          tripRef: tripRef,
          effectiveDepartureDate: effectiveDepartureDate,
          baseCapacity: baseCapacity,
        );
        final int nextRemainingSeats = availableSeats - input.requestedSeats;
        transaction.set(
          _occurrenceRef(tripRef, effectiveDepartureDate),
          <String, dynamic>{
            'date': effectiveDepartureDate,
            'capacity': baseCapacity,
            'bookedSeats': (baseCapacity - nextRemainingSeats).clamp(0, baseCapacity),
            'remainingSeats': nextRemainingSeats,
            'status': nextRemainingSeats > 0 ? 'active' : 'full',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        final int availableSeats = baseCapacity;
        transaction.update(tripRef, <String, dynamic>{
          'seats': availableSeats - input.requestedSeats,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(bookingRef, bookingMap);
    });

    final Map<String, dynamic> merged = <String, dynamic>{
      ...bookingMap,
      'createdAt': null,
      'updatedAt': null,
    };
    final VoyageBookingDocument booking =
        VoyageBookingDocument.fromMap(bookingRef.id, merged);
    await _notifyBookingCreated(booking);
    return booking;
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

  Stream<List<VoyageBookingDocument>> watchBookingsByTripId(String tripId) {
    final String normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      return Stream<List<VoyageBookingDocument>>.value(
        const <VoyageBookingDocument>[],
      );
    }

    return _firestore
        .collection('voyageBookings')
        .where('tripId', isEqualTo: normalizedTripId)
        .snapshots()
        .map((snapshot) {
      final List<VoyageBookingDocument> bookings = snapshot.docs
          .map((doc) => VoyageBookingDocument.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      bookings.sort((a, b) {
        final int bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final int aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

        return bookings;
    });
  }

  Stream<List<VoyageBookingDocument>> watchPendingBookingsForOwnerUid(
    String ownerUid,
  ) {
    final String normalizedOwnerUid = ownerUid.trim();
    if (normalizedOwnerUid.isEmpty) {
      return Stream<List<VoyageBookingDocument>>.value(
        const <VoyageBookingDocument>[],
      );
    }

    return _firestore
        .collection('voyageBookings')
        .where('tripOwnerUid', isEqualTo: normalizedOwnerUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final List<VoyageBookingDocument> bookings = snapshot.docs
          .map((doc) => VoyageBookingDocument.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      bookings.sort((a, b) {
        final int bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final int aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });

      return bookings;
    });
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

  Future<VoyageBookingDocument?> fetchBookingById(String bookingId) async {
    final String normalizedBookingId = bookingId.trim();
    if (normalizedBookingId.isEmpty) return null;

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('voyageBookings').doc(normalizedBookingId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return VoyageBookingDocument.fromMap(snapshot.id, snapshot.data()!);
  }

  Future<void> updateBookingStatus({
    required String bookingId,
    required String status,
  }) async {
    final String normalizedBookingId = bookingId.trim();
    final String normalizedStatus = status.trim().toLowerCase();
    if (normalizedBookingId.isEmpty || normalizedStatus.isEmpty) return;

    final DocumentReference<Map<String, dynamic>> bookingRef =
        _firestore.collection('voyageBookings').doc(normalizedBookingId);
    late VoyageBookingDocument booking;

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(bookingRef);
      if (!snapshot.exists || snapshot.data() == null) return;

      booking = VoyageBookingDocument.fromMap(snapshot.id, snapshot.data()!);
      final String previousStatus = booking.status.trim().toLowerCase();
      if (previousStatus == normalizedStatus) return;

      final String normalizedTripId = booking.tripId.trim();
      if (normalizedTripId.isNotEmpty) {
        final DocumentReference<Map<String, dynamic>> tripRef =
            _firestore.collection('voyageTrips').doc(normalizedTripId);
        final DocumentSnapshot<Map<String, dynamic>> tripSnapshot =
            await transaction.get(tripRef);
        if (tripSnapshot.exists && tripSnapshot.data() != null) {
          final String tripFrequency = _normalizedTripFrequency(
            _toStringSafe(tripSnapshot.data()!['tripFrequency']),
          );
          final String tripDepartureDate = booking.tripDepartureDate.trim();
          final bool usesOccurrences = tripFrequency != 'none';
          final Map<String, dynamic> tripSegmentOccupancy = _parseSegmentOccupancy(
            tripSnapshot.data()!['segmentOccupancy'],
          );
          final List<String> tripSegmentPoints = (tripSnapshot.data()!['segmentPoints'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final bool usesSegments =
              tripSegmentOccupancy.isNotEmpty && tripSegmentPoints.length >= 2;

          if (usesOccurrences && tripDepartureDate.isNotEmpty) {
            final DocumentReference<Map<String, dynamic>> occRef =
                _occurrenceRef(tripRef, tripDepartureDate);
            final DocumentSnapshot<Map<String, dynamic>> occSnap =
                await transaction.get(occRef);
            final Map<String, dynamic>? occurrence =
                occSnap.exists && occSnap.data() != null ? occSnap.data()! : null;
            final int capacity = occurrence == null
                ? _toInt(tripSnapshot.data()!['seats'], 0)
                : _toInt(occurrence['capacity'], _toInt(tripSnapshot.data()!['seats'], 0));
            if (usesSegments) {
              final Map<String, dynamic> occurrenceSegmentOccupancy =
                  _resolveOccurrenceSegmentOccupancy(
                occurrence: occurrence,
                fallbackSegmentOccupancy: tripSegmentOccupancy,
              );
              final List<String> coveredKeys = _coveredSegmentKeys(
                segmentPoints: tripSegmentPoints,
                segmentOccupancy: occurrenceSegmentOccupancy,
                from: booking.segmentFrom,
                to: booking.segmentTo,
              );
              if (coveredKeys.isNotEmpty) {
                final bool consumedBefore = _statusConsumesSeat(previousStatus);
                final bool consumedAfter = _statusConsumesSeat(normalizedStatus);
                if (consumedBefore != consumedAfter) {
                  final Map<String, dynamic> updatedOccupancy = _updatedOccupancy(
                    segmentOccupancy: occurrenceSegmentOccupancy,
                    coveredKeys: coveredKeys,
                    seats: booking.requestedSeats,
                    increment: consumedAfter,
                  );
                  final int nextRemaining = _computeRemainingSeatsFromOccupancy(
                    segmentOccupancy: updatedOccupancy,
                    capacity: capacity,
                  );
                  transaction.set(
                    occRef,
                    <String, dynamic>{
                      'date': tripDepartureDate,
                      'capacity': capacity,
                      'segmentPoints': tripSegmentPoints,
                      'segmentOccupancy': updatedOccupancy,
                      'remainingSeats': nextRemaining,
                      'bookedSeats': capacity - nextRemaining,
                      'status': nextRemaining > 0 ? 'active' : 'full',
                      'updatedAt': FieldValue.serverTimestamp(),
                    },
                    SetOptions(merge: true),
                  );
                }
              }
            } else if (occurrence != null) {
              final int currentRemaining = _toInt(occurrence['remainingSeats'], 0);
              final int nextRemaining = _computeAvailableSeatsAfterStatusTransition(
                availableSeats: currentRemaining,
                requestedSeats: booking.requestedSeats,
                previousStatus: previousStatus,
                nextStatus: normalizedStatus,
              ).clamp(0, capacity);
              transaction.set(
                occRef,
                <String, dynamic>{
                  'remainingSeats': nextRemaining,
                  'bookedSeats': capacity - nextRemaining,
                  'status': nextRemaining > 0 ? 'active' : 'full',
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
            }
          } else if (usesSegments) {
            final List<String> coveredKeys = _coveredSegmentKeys(
              segmentPoints: tripSegmentPoints,
              segmentOccupancy: tripSegmentOccupancy,
              from: booking.segmentFrom,
              to: booking.segmentTo,
            );
            if (coveredKeys.isNotEmpty) {
              final bool consumedBefore = _statusConsumesSeat(previousStatus);
              final bool consumedAfter = _statusConsumesSeat(normalizedStatus);
              if (consumedBefore != consumedAfter) {
                final Map<String, dynamic> updatedOccupancy = _updatedOccupancy(
                  segmentOccupancy: tripSegmentOccupancy,
                  coveredKeys: coveredKeys,
                  seats: booking.requestedSeats,
                  increment: consumedAfter,
                );
                transaction.set(
                  tripRef,
                  <String, dynamic>{
                    'segmentOccupancy': updatedOccupancy,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true),
                );
              }
            }
          } else if (!usesOccurrences) {
            final int availableSeats = _toInt(tripSnapshot.data()!['seats'], 0);
            final int nextSeats = _computeAvailableSeatsAfterStatusTransition(
              availableSeats: availableSeats,
              requestedSeats: booking.requestedSeats,
              previousStatus: previousStatus,
              nextStatus: normalizedStatus,
            );

            if (nextSeats != availableSeats) {
              if (nextSeats < 0) {
                throw Exception('Places insuffisantes pour cette mise à jour.');
              }
              transaction.set(
                tripRef,
                <String, dynamic>{
                  'seats': nextSeats,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
            }
          }
        }
      }

      transaction.set(
        bookingRef,
        <String, dynamic>{
          'status': normalizedStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    final DocumentSnapshot<Map<String, dynamic>> updatedSnapshot =
        await bookingRef.get();
    if (!updatedSnapshot.exists || updatedSnapshot.data() == null) return;
    booking = VoyageBookingDocument.fromMap(
      updatedSnapshot.id,
      updatedSnapshot.data()!,
    );

    await _notifyBookingStatusUpdated(
      booking: booking,
      nextStatus: normalizedStatus,
    );

    // Deduct 10% commission when the trip starts
    if (normalizedStatus == 'in_progress' &&
        booking.tripOwnerUid.isNotEmpty &&
        booking.totalPrice > 0) {
      await WalletService.instance.deductCommission(
        driverUid: booking.tripOwnerUid,
        tripTotalPrice: booking.totalPrice,
        bookingTrackNum: booking.trackNum,
      );
    }
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
        throw Exception('Réservation introuvable.');
      }

      final Map<String, dynamic> booking = bookingSnap.data()!;
      final String status = (booking['status'] as String? ?? '').trim().toLowerCase();
      if (status == 'cancelled') {
        return;
      }
      if (status == 'rejected' || status == 'refused') {
        throw Exception('Réservation non annulable.');
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

      final String tripFrequency =
          _normalizedTripFrequency(_toStringSafe(booking['tripFrequency']));
      final String tripDepartureDate = _toStringSafe(booking['tripDepartureDate']);
      final bool usesOccurrences = tripFrequency != 'none';
      final Map<String, dynamic> tripSegmentOccupancy = _parseSegmentOccupancy(
        tripSnap.data()!['segmentOccupancy'],
      );
      final List<String> tripSegmentPoints =
          (tripSnap.data()!['segmentPoints'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
      final bool usesSegments =
          tripSegmentOccupancy.isNotEmpty && tripSegmentPoints.length >= 2;

      if (usesSegments) {
        final String segFrom = _toStringSafe(booking['segmentFrom']);
        final String segTo = _toStringSafe(booking['segmentTo']);
        if (usesOccurrences && tripDepartureDate.isNotEmpty) {
          final DocumentReference<Map<String, dynamic>> occRef =
              _occurrenceRef(tripRef, tripDepartureDate);
          final DocumentSnapshot<Map<String, dynamic>> occSnap =
              await transaction.get(occRef);
          final Map<String, dynamic>? occurrence =
              occSnap.exists && occSnap.data() != null ? occSnap.data()! : null;
          final Map<String, dynamic> occurrenceSegmentOccupancy =
              _resolveOccurrenceSegmentOccupancy(
            occurrence: occurrence,
            fallbackSegmentOccupancy: tripSegmentOccupancy,
          );
          final List<String> coveredKeys = _coveredSegmentKeys(
            segmentPoints: tripSegmentPoints,
            segmentOccupancy: occurrenceSegmentOccupancy,
            from: segFrom,
            to: segTo,
          );
          if (coveredKeys.isNotEmpty) {
            final Map<String, dynamic> updatedOccupancy = _updatedOccupancy(
              segmentOccupancy: occurrenceSegmentOccupancy,
              coveredKeys: coveredKeys,
              seats: requestedSeats,
              increment: false,
            );
            final int capacity = occurrence == null
                ? _toInt(tripSnap.data()!['seats'], 0)
                : _toInt(occurrence['capacity'], _toInt(tripSnap.data()!['seats'], 0));
            final int nextRemaining = _computeRemainingSeatsFromOccupancy(
              segmentOccupancy: updatedOccupancy,
              capacity: capacity,
            );
            transaction.set(
              occRef,
              <String, dynamic>{
                'date': tripDepartureDate,
                'capacity': capacity,
                'segmentPoints': tripSegmentPoints,
                'segmentOccupancy': updatedOccupancy,
                'remainingSeats': nextRemaining,
                'bookedSeats': capacity - nextRemaining,
                'status': nextRemaining > 0 ? 'active' : 'full',
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        } else {
          final List<String> coveredKeys = _coveredSegmentKeys(
            segmentPoints: tripSegmentPoints,
            segmentOccupancy: tripSegmentOccupancy,
            from: segFrom,
            to: segTo,
          );
          if (coveredKeys.isNotEmpty) {
            final Map<String, dynamic> updatedOccupancy = _updatedOccupancy(
              segmentOccupancy: tripSegmentOccupancy,
              coveredKeys: coveredKeys,
              seats: requestedSeats,
              increment: false,
            );
            transaction.update(tripRef, <String, dynamic>{
              'segmentOccupancy': updatedOccupancy,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } else if (usesOccurrences && tripDepartureDate.isNotEmpty) {
        final DocumentReference<Map<String, dynamic>> occRef =
            _occurrenceRef(tripRef, tripDepartureDate);
        final DocumentSnapshot<Map<String, dynamic>> occSnap =
            await transaction.get(occRef);
        if (occSnap.exists && occSnap.data() != null) {
          final int currentRemaining = _toInt(occSnap.data()!['remainingSeats'], 0);
          final int capacity = _toInt(occSnap.data()!['capacity'], 0);
          final int nextRemaining = (currentRemaining + requestedSeats).clamp(0, capacity);
          transaction.set(
            occRef,
            <String, dynamic>{
              'remainingSeats': nextRemaining,
              'bookedSeats': capacity - nextRemaining,
              'status': nextRemaining > 0 ? 'active' : 'full',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } else if (!usesOccurrences) {
        final int availableSeats = _toInt(tripSnap.data()!['seats'], 0);
        final int nextSeats = _computeAvailableSeatsAfterStatusTransition(
          availableSeats: availableSeats,
          requestedSeats: requestedSeats,
          previousStatus: status,
          nextStatus: 'cancelled',
        );
        if (nextSeats != availableSeats) {
          transaction.set(
            tripRef,
            <String, dynamic>{
              'seats': nextSeats,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
    });

    final DocumentSnapshot<Map<String, dynamic>> updatedBookingSnap =
        await bookingRef.get();
    if (!updatedBookingSnap.exists || updatedBookingSnap.data() == null) {
      return;
    }

    final VoyageBookingDocument booking = VoyageBookingDocument.fromMap(
      updatedBookingSnap.id,
      updatedBookingSnap.data()!,
    );
    await _notifyBookingCancelled(booking);
  }

  Future<void> _notifyBookingCreated(VoyageBookingDocument booking) async {
    await _notificationsRepository.createNotification(
      CreateAppNotificationInput(
        userId: booking.tripOwnerUid,
        domain: 'travel',
        type: 'booking_created',
        title: 'Nouvelle réservation',
        body:
            '${booking.requesterName} a réservé ${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}.',
        entityType: 'booking',
        entityId: booking.id,
        data: <String, dynamic>{
          'bookingId': booking.id,
          'bookingTrackNum': booking.trackNum,
          'tripId': booking.tripId,
          'tripTrackNum': booking.tripTrackNum,
        },
      ),
    );
  }

  Future<void> _notifyBookingStatusUpdated({
    required VoyageBookingDocument booking,
    required String nextStatus,
  }) async {
    await _notificationsRepository.createNotification(
      CreateAppNotificationInput(
        userId: booking.requesterUid,
        domain: 'travel',
        type: 'booking_status_updated',
        title: _bookingStatusTitle(nextStatus),
        body: _bookingStatusBody(nextStatus),
        entityType: 'booking',
        entityId: booking.id,
        data: <String, dynamic>{
          'bookingId': booking.id,
          'bookingTrackNum': booking.trackNum,
          'tripId': booking.tripId,
          'tripTrackNum': booking.tripTrackNum,
          'status': nextStatus,
          'requesterUid': booking.requesterUid,
        },
      ),
    );
  }

  Future<void> _notifyBookingCancelled(VoyageBookingDocument booking) async {
    await _notificationsRepository.createNotification(
      CreateAppNotificationInput(
        userId: booking.tripOwnerUid,
        domain: 'travel',
        type: 'booking_cancelled',
        title: 'Réservation annulée',
        body:
            '${booking.requesterName} a annulé sa réservation ${booking.trackNum}.',
        entityType: 'booking',
        entityId: booking.id,
        data: <String, dynamic>{
          'bookingId': booking.id,
          'bookingTrackNum': booking.trackNum,
          'tripId': booking.tripId,
          'tripTrackNum': booking.tripTrackNum,
          'tripOwnerUid': booking.tripOwnerUid,
        },
      ),
    );
  }

  String _normalizedTripFrequency(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'daily':
        return 'daily';
      case 'weekly':
        return 'weekly';
      case 'monthly':
        return 'monthly';
      default:
        return 'none';
    }
  }

  String _resolveEffectiveDepartureDate(
      CreateVoyageBookingInput input, Map<String, dynamic> trip) {
    final String inputDate = (input.effectiveDepartureDate ?? '').trim();
    if (inputDate.isNotEmpty) return inputDate;
    return _toStringSafe(trip['departureDate']);
  }

  Future<int> _readAvailableSeatsForOccurrence({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> tripRef,
    required String effectiveDepartureDate,
    required int baseCapacity,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await transaction.get(_occurrenceRef(tripRef, effectiveDepartureDate));
    if (!snap.exists || snap.data() == null) return baseCapacity;
    return _toInt(snap.data()!['remainingSeats'], baseCapacity);
  }

  Future<Map<String, dynamic>?> _readOccurrence({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> occurrenceRef,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await transaction.get(occurrenceRef);
    if (!snap.exists || snap.data() == null) return null;
    return snap.data();
  }

  DocumentReference<Map<String, dynamic>> _occurrenceRef(
    DocumentReference<Map<String, dynamic>> tripRef,
    String effectiveDepartureDate,
  ) {
    return tripRef.collection('occurrences').doc(effectiveDepartureDate);
  }

  String _toStringSafe(Object? value) => value is String ? value.trim() : '';

  int _toInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  Map<String, dynamic> _parseSegmentOccupancy(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> _resolveOccurrenceSegmentOccupancy({
    required Map<String, dynamic>? occurrence,
    required Map<String, dynamic> fallbackSegmentOccupancy,
  }) {
    final Map<String, dynamic> occurrenceSegmentOccupancy = _parseSegmentOccupancy(
      occurrence?['segmentOccupancy'],
    );
    if (occurrenceSegmentOccupancy.isNotEmpty) return occurrenceSegmentOccupancy;
    return Map<String, dynamic>.from(fallbackSegmentOccupancy);
  }

  int _computeRemainingSeatsFromOccupancy({
    required Map<String, dynamic> segmentOccupancy,
    required int capacity,
  }) {
    int maxOccupied = 0;
    for (final Object? value in segmentOccupancy.values) {
      final int occupied = _toInt(value, 0);
      if (occupied > maxOccupied) maxOccupied = occupied;
    }
    return (capacity - maxOccupied).clamp(0, capacity);
  }

  /// Retourne les clés de tronçons couverts par un segment [from] → [to]
  /// en utilisant segmentPoints (array ordonné) pour éviter les problèmes d'ordre Firestore.
  List<String> _coveredSegmentKeys({
    required List<String> segmentPoints,
    required Map<String, dynamic> segmentOccupancy,
    required String from,
    required String to,
  }) {
    if (segmentPoints.length < 2) return const <String>[];
    final int fromIdx = _findSegmentPointIndex(segmentPoints, from);
    final int toIdx = _findSegmentPointIndex(
      segmentPoints,
      to,
      afterIndex: fromIdx,
    );
    if (fromIdx < 0 || toIdx < 0 || toIdx <= fromIdx) return const <String>[];
    final List<String> covered = <String>[];
    for (int i = fromIdx; i < toIdx; i++) {
      final String key = '${segmentPoints[i]}__${segmentPoints[i + 1]}';
      if (segmentOccupancy.containsKey(key)) covered.add(key);
    }
    return covered;
  }

  /// Vérifie la dispo par tronçon et lève une exception si insuffisant.
  void _checkSegmentCapacity({
    required Map<String, dynamic> segmentOccupancy,
    required List<String> coveredKeys,
    required int requestedSeats,
    required int capacity,
  }) {
    for (final String key in coveredKeys) {
      final int occupied = _toInt(segmentOccupancy[key], 0);
      if (occupied + requestedSeats > capacity) {
        throw Exception('Plus de places disponibles pour ce parcours.');
      }
    }
  }

  /// Incrémente ou décrémente l'occupancy des tronçons couverts.
  Map<String, dynamic> _updatedOccupancy({
    required Map<String, dynamic> segmentOccupancy,
    required List<String> coveredKeys,
    required int seats,
    required bool increment,
  }) {
    final Map<String, dynamic> updated = Map<String, dynamic>.from(segmentOccupancy);
    for (final String key in coveredKeys) {
      final int current = _toInt(updated[key], 0);
      updated[key] = increment ? current + seats : (current - seats).clamp(0, 1 << 30);
    }
    return updated;
  }

  int _findSegmentPointIndex(
    List<String> segmentPoints,
    String query, {
    int afterIndex = -1,
  }) {
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return -1;
    for (int i = 0; i < segmentPoints.length; i++) {
      if (i <= afterIndex) continue;
      if (_matchesAddressQuery(normalizedQuery, segmentPoints[i])) return i;
    }
    return -1;
  }

  bool _matchesAddressQuery(String queryAddress, String candidateAddress) {
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

  List<String> _addressTokens(String address) {
    final List<String> out = <String>[];
    final String first = _normalize(_cityToken(address));
    if (first.isNotEmpty && !out.contains(first)) out.add(first);
    for (final String part in address.split(',')) {
      final String token = _normalize(part);
      if (token.isNotEmpty && !out.contains(token)) out.add(token);
    }
    return out;
  }

  String _cityToken(String address) => (address.split(',').first).trim();

  String _normalize(String value) {
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

  String _normalizeLoose(String value) {
    return _normalize(value)
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

    final Set<String> leftWords =
        left.split(' ').where((w) => w.length >= 4).toSet();
    final Set<String> rightWords =
        right.split(' ').where((w) => w.length >= 4).toSet();
    if (leftWords.isNotEmpty && rightWords.isNotEmpty) {
      for (final String lw in leftWords) {
        if (rightWords.contains(lw)) return true;
      }
    }
    return false;
  }

  bool _isGenericGeoToken(String value) {
    final String v = _normalizeLoose(value);
    return v.isEmpty ||
        v == 'ci' ||
        v == 'cote d ivoire' ||
        v == 'cote divoire' ||
        v == 'ivory coast';
  }
}

int _computeAvailableSeatsAfterStatusTransition({
  required int availableSeats,
  required int requestedSeats,
  required String previousStatus,
  required String nextStatus,
}) {
  final bool consumedBefore = _statusConsumesSeat(previousStatus);
  final bool consumedAfter = _statusConsumesSeat(nextStatus);
  if (consumedBefore == consumedAfter) {
    return availableSeats;
  }
  if (consumedBefore && !consumedAfter) {
    return availableSeats + requestedSeats;
  }
  return availableSeats - requestedSeats;
}

bool _statusConsumesSeat(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pending':
    case 'accepted':
    case 'approved':
    case 'confirmed':
      return true;
    default:
      return false;
  }
}

String _bookingStatusTitle(String status) {
  switch (status.trim().toLowerCase()) {
    case 'accepted':
    case 'approved':
    case 'confirmed':
      return 'Réservation acceptée';
    case 'rejected':
    case 'refused':
      return 'Réservation refusée';
    case 'cancelled':
      return 'Réservation annulée';
    default:
      return 'Mise à jour de réservation';
  }
}

String _bookingStatusBody(String status) {
  switch (status.trim().toLowerCase()) {
    case 'accepted':
    case 'approved':
    case 'confirmed':
      return 'Votre réservation a été acceptée.';
    case 'rejected':
    case 'refused':
      return 'Votre réservation a été refusée.';
    case 'cancelled':
      return 'Votre réservation a été annulée.';
    default:
      return 'Le statut de votre réservation a changé.';
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
    return 'Veuillez préciser votre point de départ et d\'arrivée.';
  }
  return null;
}

String? validateVoyageTripForBooking({
  required Map<String, dynamic> trip,
  required int requestedSeats,
  String? effectiveDepartureDate,
}) {
  final String status = (trip['status'] as String? ?? '').trim();
  if (status != 'published') {
    return 'Trajet non disponible \u00E0 la r\u00E9servation.';
  }
  // For frequent trips the authoritative seat count comes from the occurrence
  // subcollection and is checked after this validation in createBooking.
  // For ponctual trips, trip['seats'] is the definitive count.
  final String freq = (trip['tripFrequency'] as String? ?? '').trim().toLowerCase();
  final bool isFrequent = freq == 'daily' || freq == 'weekly' || freq == 'monthly';
  if (!isFrequent) {
    final int availableSeats = _toIntStatic(trip['seats'], 0);
    if (availableSeats < requestedSeats) {
      return 'Places insuffisantes.';
    }
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
  final String travelersKey = input.travelers
      .map(
        (VoyageBookingTraveler traveler) =>
            '${traveler.name.trim().toLowerCase()}::${traveler.contact.trim()}',
      )
      .join('|');

  return <Object?>[
    input.tripId.trim().toLowerCase(),
    input.requestedSeats,
    (input.requesterUid ?? '').trim().toLowerCase(),
    input.requesterName.trim().toLowerCase(),
    input.requesterContact.trim(),
    input.segmentFrom.trim().toLowerCase(),
    input.segmentTo.trim().toLowerCase(),
    input.segmentPrice,
    (input.effectiveDepartureDate ?? '').trim(),
    travelersKey,
  ].join('##');
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
