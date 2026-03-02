import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/travel_service.dart';

class TravelRepository implements TravelService {
  TravelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
