import 'package:cloud_firestore/cloud_firestore.dart';

enum AppPlatform { ios, android }

class AppVersion {
  final AppPlatform platform;
  final String version;
  final String buildNumber;
  final String storeUrl;
  final bool forceMajeure;
  final DateTime? updatedAt;

  const AppVersion({
    required this.platform,
    required this.version,
    required this.buildNumber,
    required this.storeUrl,
    required this.forceMajeure,
    this.updatedAt,
  });

  String get firestoreId => platform == AppPlatform.ios ? 'ios' : 'android';

  factory AppVersion.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final platform = doc.id == 'ios' ? AppPlatform.ios : AppPlatform.android;
    return AppVersion(
      platform: platform,
      version: d['version'] ?? '1.0.0',
      buildNumber: d['buildNumber'] ?? '1',
      storeUrl: d['storeUrl'] ?? '',
      forceMajeure: d['forceMajeure'] ?? false,
      updatedAt: d['updatedAt'] is Timestamp
          ? (d['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
