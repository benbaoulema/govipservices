import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/notifications/data/firestore_notifications_repository.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';

class ParcelRequestService {
  ParcelRequestService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _notificationsRepository = FirestoreNotificationsRepository(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  final FirebaseFirestore _firestore;
  final FirestoreNotificationsRepository _notificationsRepository;

  Future<ParcelRequestDocument> createRequest(
    CreateParcelRequestInput input,
  ) async {
    final String? inputError = validateCreateParcelRequestInput(input);
    if (inputError != null) throw Exception(inputError);

    final DocumentReference<Map<String, dynamic>> requestRef =
        _firestore.collection('demands').doc();
    final String trackNum = _generateTrackingNumber();

    await requestRef.set(<String, dynamic>{
      'trackNum': trackNum,
      'domain': 'parcel',
      'serviceId': input.serviceId.trim(),
      'providerUid': input.providerUid.trim(),
      'providerName': input.providerName.trim(),
      'providerPhone': input.providerPhone.trim(),
      'requesterUid': input.requesterUid.trim(),
      'requesterName': input.requesterName.trim(),
      'requesterContact': input.requesterContact.trim(),
      'pickupCityAddress': input.pickupAddress.trim(),
      'pickupLatLng': <String, dynamic>{
        'lat': input.pickupLat,
        'lng': input.pickupLng,
      },
      'deliveryAddress': input.deliveryAddress.trim(),
      'deliveryLatLng': <String, dynamic>{
        'lat': input.deliveryLat,
        'lng': input.deliveryLng,
      },
      'receiverName': input.receiverName.trim(),
      'receiverContactPhone': input.receiverContactPhone.trim(),
      'price': input.price,
      'currency': input.currency.trim().isEmpty ? 'XOF' : input.currency.trim(),
      'priceSource': input.priceSource.trim(),
      'vehicleLabel': input.vehicleLabel.trim(),
      'status': 'provider_notified',
      'source': 'mobile',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notificationsRepository.createNotification(
      CreateAppNotificationInput(
        userId: input.providerUid,
        domain: 'parcel',
        type: 'parcel_request_created',
        title: 'Nouvelle demande colis',
        body:
            '${input.requesterName.trim().isEmpty ? 'Un client' : input.requesterName.trim()} souhaite une livraison.',
        entityType: 'demand',
        entityId: requestRef.id,
        data: <String, dynamic>{
          'demandId': requestRef.id,
          'demandTrackNum': trackNum,
          'serviceId': input.serviceId.trim(),
          'providerUid': input.providerUid.trim(),
          'requesterUid': input.requesterUid.trim(),
          'pickupAddress': input.pickupAddress.trim(),
          'deliveryAddress': input.deliveryAddress.trim(),
        },
      ),
    );

    return ParcelRequestDocument(
      id: requestRef.id,
      trackNum: trackNum,
      serviceId: input.serviceId.trim(),
      providerUid: input.providerUid.trim(),
      providerName: input.providerName.trim(),
      requesterUid: input.requesterUid.trim(),
      requesterName: input.requesterName.trim(),
      requesterContact: input.requesterContact.trim(),
      pickupAddress: input.pickupAddress.trim(),
      deliveryAddress: input.deliveryAddress.trim(),
      price: input.price,
      currency: input.currency.trim().isEmpty ? 'XOF' : input.currency.trim(),
      vehicleLabel: input.vehicleLabel.trim(),
      status: 'provider_notified',
      createdAt: null,
    );
  }

  Stream<List<ParcelRequestDocument>> watchPendingRequestsForProviderUid(
    String providerUid,
  ) {
    final String normalizedProviderUid = providerUid.trim();
    if (normalizedProviderUid.isEmpty) {
      return Stream<List<ParcelRequestDocument>>.value(
        const <ParcelRequestDocument>[],
      );
    }

    return _firestore
        .collection('demands')
        .where('domain', isEqualTo: 'parcel')
        .where('providerUid', isEqualTo: normalizedProviderUid)
        .where('status', isEqualTo: 'provider_notified')
        .snapshots()
        .map((snapshot) {
      final List<ParcelRequestDocument> requests = snapshot.docs
          .map((doc) => ParcelRequestDocument.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      requests.sort((a, b) {
        final int bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        final int aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime);
      });
      return requests;
    });
  }

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    final String normalizedRequestId = requestId.trim();
    final String normalizedStatus = status.trim().toLowerCase();
    if (normalizedRequestId.isEmpty || normalizedStatus.isEmpty) return;

    await _firestore.collection('demands').doc(normalizedRequestId).set(
      <String, dynamic>{
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<ParcelRequestDocument?> watchRequestById(String requestId) {
    final String id = requestId.trim();
    if (id.isEmpty) return const Stream<ParcelRequestDocument?>.empty();
    return _firestore
        .collection('demands')
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists && snap.data() != null
            ? ParcelRequestDocument.fromMap(snap.id, snap.data()!)
            : null);
  }

  Future<void> updateCourierLocation({
    required String requestId,
    required double lat,
    required double lng,
  }) async {
    final String id = requestId.trim();
    if (id.isEmpty) return;
    await _firestore.collection('demands').doc(id).set(
      <String, dynamic>{
        'courierLat': lat,
        'courierLng': lng,
        'courierUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<ParcelRequestDocument?> fetchRequestById(String requestId) async {
    final String normalizedRequestId = requestId.trim();
    if (normalizedRequestId.isEmpty) return null;

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('demands').doc(normalizedRequestId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return ParcelRequestDocument.fromMap(snapshot.id, snapshot.data()!);
  }

  String _generateTrackingNumber() {
    final int stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
    return 'COL$stamp';
  }
}

String? validateCreateParcelRequestInput(CreateParcelRequestInput input) {
  if (input.serviceId.trim().isEmpty) {
    return 'Service colis introuvable.';
  }
  if (input.providerUid.trim().isEmpty) {
    return 'Livreur introuvable.';
  }
  if (input.requesterUid.trim().isEmpty) {
    return 'Demandeur introuvable.';
  }
  if (input.pickupAddress.trim().isEmpty ||
      input.deliveryAddress.trim().isEmpty) {
    return 'Les adresses de depart et d arrivee sont obligatoires.';
  }
  return null;
}
