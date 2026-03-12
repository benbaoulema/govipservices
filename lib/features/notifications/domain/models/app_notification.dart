import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.installationId,
    required this.domain,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    required this.status,
    required this.createdAt,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String userId;
  final String installationId;
  final String domain;
  final String type;
  final String title;
  final String body;
  final String entityType;
  final String entityId;
  final String status;
  final Timestamp? createdAt;
  final Map<String, dynamic> data;

  bool get isUnread => status == 'unread';

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: (map['userId'] as String? ?? '').trim(),
      installationId: (map['installationId'] as String? ?? '').trim(),
      domain: (map['domain'] as String? ?? 'system').trim(),
      type: (map['type'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
      entityType: (map['entityType'] as String? ?? '').trim(),
      entityId: (map['entityId'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? 'unread').trim(),
      createdAt: map['createdAt'] as Timestamp?,
      data: map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class CreateAppNotificationInput {
  const CreateAppNotificationInput({
    required this.userId,
    this.installationId = '',
    required this.domain,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    this.data = const <String, dynamic>{},
  });

  final String userId;
  final String installationId;
  final String domain;
  final String type;
  final String title;
  final String body;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> data;
}
