import 'package:govipservices/features/user/data/user_firestore_repository.dart';
import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/user/models/user_role.dart';

Future<void> userRepositoryExample(UserFirestoreRepository repo, String uid) async {
  final AppUser signupPayload = AppUser(
    uid: uid,
    email: 'user@example.com',
    displayName: 'Awa Kone',
    role: UserRole.simpleUser,
    phone: const UserPhone(countryCode: '+225', number: '0700000000'),
    photoURL: null,
    materialPhotoUrl: null,
    service: null,
    isServiceProvider: false,
    createdAt: null,
    updatedAt: null,
    archived: false,
    meta: const <String, dynamic>{
      'authEmailSource': 'firebase_auth',
      'firstName': 'Awa',
      'lastName': 'Kone',
    },
  );

  await repo.setUser(uid, signupPayload);

  final AppUser? user = await repo.getById(uid);
  if (user == null) return;

  await repo.setRole(uid, UserRole.pro);

  final String phoneLabel = buildUiPhone(user.phone); // "+225 0700000000"
  // ignore: avoid_print
  print(phoneLabel);
}
