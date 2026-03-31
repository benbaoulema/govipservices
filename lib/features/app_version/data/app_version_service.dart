import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/app_version/domain/entities/app_version.dart';

class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<AppVersion?> fetchCurrent() async {
    final String docId = Platform.isIOS ? 'ios' : 'android';
    try {
      final DocumentSnapshot doc =
          await _db.collection('appVersions').doc(docId).get();
      if (!doc.exists) return null;
      return AppVersion.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }
}
