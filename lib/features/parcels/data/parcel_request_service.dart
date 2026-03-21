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

  /// Accepte une demande de manière atomique via transaction.
  /// Retourne false si la demande a déjà été acceptée/refusée ailleurs.
  Future<bool> acceptRequest(String requestId) async {
    final String id = requestId.trim();
    if (id.isEmpty) return false;

    final DocumentReference<Map<String, dynamic>> ref =
        _firestore.collection('demands').doc(id);

    bool accepted = false;
    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await transaction.get(ref);
      if (!snap.exists) return;

      final String currentStatus =
          ((snap.data()?['status'] as String?) ?? '').trim().toLowerCase();

      // N'accepter que si la demande est encore en attente
      if (currentStatus != 'provider_notified') return;

      transaction.set(
        ref,
        <String, dynamic>{
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      accepted = true;
    });

    return accepted;
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

  /// Met à jour le statut ET envoie une notification push au sender (atomic batch).
  Future<void> updateRequestStatusAndNotify({
    required String requestId,
    required String status,
    required String requesterUid,
    required String providerName,
    required String trackNum,
  }) async {
    final String id = requestId.trim();
    final String normalizedStatus = status.trim().toLowerCase();
    if (id.isEmpty || normalizedStatus.isEmpty || requesterUid.trim().isEmpty) {
      return updateRequestStatus(requestId: requestId, status: status);
    }

    final _ParcelStatusNotif? notif = _ParcelStatusNotif.forStatus(
      status: normalizedStatus,
      providerName: providerName.trim(),
      trackNum: trackNum.trim(),
    );

    final WriteBatch batch = _firestore.batch();

    batch.set(
      _firestore.collection('demands').doc(id),
      <String, dynamic>{
        'status': normalizedStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (notif != null) {
      batch.set(
        _firestore.collection('notifications').doc(),
        <String, dynamic>{
          'userId': requesterUid.trim(),
          'installationId': '',
          'domain': 'parcels',
          'type': 'parcel_status_updated',
          'title': notif.title,
          'body': notif.body,
          'entityType': 'demand',
          'entityId': id,
          'status': 'unread',
          'data': <String, dynamic>{'status': normalizedStatus},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();
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

  /// Stream de la course active en tant que livreur (accepted/en_route/picked_up).
  Stream<ParcelRequestDocument?> watchActiveDriverDelivery(String providerUid) {
    final String uid = providerUid.trim();
    if (uid.isEmpty) return Stream<ParcelRequestDocument?>.value(null);
    return _firestore
        .collection('demands')
        .where('providerUid', isEqualTo: uid)
        .where('status', whereIn: <String>['accepted', 'en_route', 'picked_up'])
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : ParcelRequestDocument.fromMap(
                snap.docs.first.id, snap.docs.first.data()));
  }

  /// Stream de la course active en tant qu'expéditeur (accepted/en_route/picked_up).
  Stream<ParcelRequestDocument?> watchActiveSenderDelivery(String requesterUid) {
    final String uid = requesterUid.trim();
    if (uid.isEmpty) return Stream<ParcelRequestDocument?>.value(null);
    return _firestore
        .collection('demands')
        .where('requesterUid', isEqualTo: uid)
        .where('status', whereIn: <String>['accepted', 'en_route', 'picked_up'])
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : ParcelRequestDocument.fromMap(
                snap.docs.first.id, snap.docs.first.data()));
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

/// Titre + corps de la notification push envoyée au sender lors d'un changement de statut.
class _ParcelStatusNotif {
  const _ParcelStatusNotif({required this.title, required this.body});

  final String title;
  final String body;

  static _ParcelStatusNotif? forStatus({
    required String status,
    required String providerName,
    required String trackNum,
  }) {
    final String name = providerName.isNotEmpty ? providerName : 'Votre livreur';
    final String ref = trackNum.isNotEmpty ? ' ($trackNum)' : '';
    switch (status) {
      case 'accepted':
        return _ParcelStatusNotif(
          title: 'Livreur en route 🛵',
          body: '$name a accepté votre demande$ref et se dirige vers vous.',
        );
      case 'en_route':
        return _ParcelStatusNotif(
          title: 'Livreur en chemin 🛵',
          body: '$name se dirige vers le point de retrait$ref.',
        );
      case 'picked_up':
        return _ParcelStatusNotif(
          title: 'Colis récupéré 📦',
          body: '$name a récupéré votre colis$ref et se dirige vers la destination.',
        );
      case 'delivered':
        return _ParcelStatusNotif(
          title: 'Colis livré ✅',
          body: 'Votre colis$ref a été livré avec succès. Merci d\'avoir utilisé GVIP.',
        );
      default:
        return null;
    }
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
