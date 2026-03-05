import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/user/models/user_role.dart';

class UserFirestoreRepository {
  UserFirestoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  Future<void> setUser(String uid, AppUser payload) async {
    _assertUid(uid);
    final AppUser normalized = payload.copyWith(
      uid: uid,
      archived: payload.archived,
      phone: payload.phone == null
          ? null
          : payload.phone!.copyWith(
              countryCode: normalizeCountryCode(payload.phone!.countryCode),
            ),
    );

    final Map<String, dynamic> data = normalized.toFirestoreJson();
    final Map<String, dynamic> write = <String, dynamic>{
      ...data,
      'uid': uid,
      if (normalized.createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      if (!data.containsKey('archived') || data['archived'] == null) 'archived': false,
    };

    await _users.doc(uid).set(write, SetOptions(merge: true));
  }

  Future<AppUser?> getById(String uid) async {
    _assertUid(uid);
    final DocumentSnapshot<Map<String, dynamic>> doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  Future<void> update(String uid, Map<String, dynamic> patch) async {
    _assertUid(uid);
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(patch);

    if (normalized['phone'] is Map<String, dynamic>) {
      final Map<String, dynamic> phone = Map<String, dynamic>.from(normalized['phone'] as Map<String, dynamic>);
      final String? countryCode = phone['countryCode'] as String?;
      if (countryCode != null) {
        phone['countryCode'] = normalizeCountryCode(countryCode);
      }
      normalized['phone'] = phone;
    }

    normalized['updatedAt'] = FieldValue.serverTimestamp();
    await _users.doc(uid).set(normalized, SetOptions(merge: true));
  }

  Future<void> archive(String uid) async {
    _assertUid(uid);
    await _users.doc(uid).set(
      <String, dynamic>{
        'archived': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setPhone(String uid, String countryCode, String number) async {
    _assertUid(uid);
    await _users.doc(uid).set(
      <String, dynamic>{
        'phone': <String, dynamic>{
          'countryCode': normalizeCountryCode(countryCode),
          'number': number,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setRole(String uid, UserRole role) async {
    _assertUid(uid);
    await _users.doc(uid).set(
      <String, dynamic>{
        'role': userRoleToJson(role),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  void _assertUid(String uid) {
    if (uid.trim().isEmpty) {
      throw ArgumentError('uid must not be empty');
    }
  }
}

String buildUiPhone(UserPhone? phone) {
  if (phone == null) return '';
  return '${normalizeCountryCode(phone.countryCode)} ${phone.number}'.trim();
}
