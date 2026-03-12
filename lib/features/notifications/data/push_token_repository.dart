import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _pushInstallationIdKey = 'push_installation_id';

class PushTokenRepository {
  PushTokenRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<String> getOrCreateInstallationId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String existingInstallationId =
        prefs.getString(_pushInstallationIdKey)?.trim() ?? '';
    if (existingInstallationId.isNotEmpty) {
      return existingInstallationId;
    }

    final String nextInstallationId = _firestore.collection('pushInstallations').doc().id;
    await prefs.setString(_pushInstallationIdKey, nextInstallationId);
    return nextInstallationId;
  }

  Future<void> upsertInstallation({
    required String installationId,
    required String token,
    String? userId,
  }) async {
    final String normalizedInstallationId = installationId.trim();
    final String normalizedToken = token.trim();
    final String normalizedUserId = (userId ?? '').trim();
    if (normalizedInstallationId.isEmpty || normalizedToken.isEmpty) return;

    await _firestore
        .collection('pushInstallations')
        .doc(normalizedInstallationId)
        .set(
      <String, dynamic>{
        'installationId': normalizedInstallationId,
        'token': normalizedToken,
        'userId': normalizedUserId,
        'platform': _platformLabel(),
        'enabled': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearUserBinding({
    required String installationId,
  }) async {
    final String normalizedInstallationId = installationId.trim();
    if (normalizedInstallationId.isEmpty) return;

    await _firestore
        .collection('pushInstallations')
        .doc(normalizedInstallationId)
        .set(
      <String, dynamic>{
        'userId': null,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
