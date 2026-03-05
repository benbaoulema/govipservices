import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:govipservices/features/user/models/firestore_datetime_converter.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/user/models/user_role.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

@freezed
class AppUser with _$AppUser {
  const factory AppUser({
    @JsonKey(includeFromJson: false, includeToJson: false) String? id,
    required String uid,
    String? email,
    String? displayName,
    UserRole? role,
    UserPhone? phone,
    String? photoURL,
    String? materialPhotoUrl,
    String? service,
    bool? isServiceProvider,
    @FirestoreDateTimeConverter() DateTime? createdAt,
    @FirestoreDateTimeConverter() DateTime? updatedAt,
    @Default(false) bool archived,
    Map<String, dynamic>? meta,
  }) = _AppUser;

  factory AppUser.fromJson(Map<String, dynamic> json) => _$AppUserFromJson(json);

  static AppUser? fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic>? data = doc.data();
    if (data == null) return null;
    final AppUser parsed = AppUser.fromJson(data).copyWith(id: doc.id);
    if (!data.containsKey('archived') || data['archived'] == null) {
      return parsed.copyWith(archived: false);
    }
    return parsed;
  }
}

extension AppUserFirestoreMapper on AppUser {
  Map<String, dynamic> toFirestoreJson() {
    final Map<String, dynamic> json = toJson();
    // Ensure nested freezed models are encoded to plain maps for Firestore.
    json['phone'] = phone?.toJson();
    json['archived'] = json['archived'] ?? false;
    return json;
  }
}
