import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
import 'package:govipservices/features/notifications/domain/repositories/notifications_repository.dart';

class FirestoreNotificationsRepository implements NotificationsRepository {
  FirestoreNotificationsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection('notifications');

  @override
  Future<void> createNotification(CreateAppNotificationInput input) async {
    final String userId = input.userId.trim();
    final String installationId = input.installationId.trim();
    if (userId.isEmpty && installationId.isEmpty) return;

    await _notificationsRef.add(
      <String, dynamic>{
        'userId': userId,
        'installationId': installationId,
        'domain': input.domain.trim().isEmpty ? 'system' : input.domain.trim(),
        'type': input.type.trim(),
        'title': input.title.trim(),
        'body': input.body.trim(),
        'entityType': input.entityType.trim(),
        'entityId': input.entityId.trim(),
        'status': 'unread',
        'data': input.data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  @override
  Future<void> createNotifications(List<CreateAppNotificationInput> inputs) async {
    if (inputs.isEmpty) return;

    final WriteBatch batch = _firestore.batch();
    for (final CreateAppNotificationInput input in inputs) {
      final String userId = input.userId.trim();
      final String installationId = input.installationId.trim();
      if (userId.isEmpty && installationId.isEmpty) continue;

      final DocumentReference<Map<String, dynamic>> ref = _notificationsRef.doc();
      batch.set(
        ref,
        <String, dynamic>{
          'userId': userId,
          'installationId': installationId,
          'domain': input.domain.trim().isEmpty ? 'system' : input.domain.trim(),
          'type': input.type.trim(),
          'title': input.title.trim(),
          'body': input.body.trim(),
          'entityType': input.entityType.trim(),
          'entityId': input.entityId.trim(),
          'status': 'unread',
          'data': input.data,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    await batch.commit();
  }

  @override
  Future<List<AppNotification>> fetchNotifications(
    String userId, {
    int limit = 50,
  }) {
    final String normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return Future<List<AppNotification>>.value(const <AppNotification>[]);
    }

    return _notificationsRef
        .where('userId', isEqualTo: normalizedUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get()
        .then(
          (snapshot) => snapshot.docs
              .map((doc) => AppNotification.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  @override
  Future<int> fetchUnreadCount(String userId) {
    final String normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return Future<int>.value(0);
    }

    return _notificationsRef
        .where('userId', isEqualTo: normalizedUserId)
        .where('status', isEqualTo: 'unread')
        .get()
        .then((snapshot) => snapshot.docs.length);
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    final String normalizedNotificationId = notificationId.trim();
    if (normalizedNotificationId.isEmpty) return;

    await _notificationsRef.doc(normalizedNotificationId).set(
      <String, dynamic>{
        'status': 'read',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> markAsUnread(String notificationId) async {
    final String normalizedNotificationId = notificationId.trim();
    if (normalizedNotificationId.isEmpty) return;

    await _notificationsRef.doc(normalizedNotificationId).set(
      <String, dynamic>{
        'status': 'unread',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    final String normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _notificationsRef
        .where('userId', isEqualTo: normalizedUserId)
        .where('status', isEqualTo: 'unread')
        .get();

    if (snapshot.docs.isEmpty) return;

    final WriteBatch batch = _firestore.batch();
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snapshot.docs) {
      batch.set(
        doc.reference,
        <String, dynamic>{
          'status': 'read',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}
