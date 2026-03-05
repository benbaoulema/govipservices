// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AppUserImpl _$$AppUserImplFromJson(Map<String, dynamic> json) =>
    _$AppUserImpl(
      uid: json['uid'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      role: $enumDecodeNullable(_$UserRoleEnumMap, json['role']),
      phone: json['phone'] == null
          ? null
          : UserPhone.fromJson(json['phone'] as Map<String, dynamic>),
      photoURL: json['photoURL'] as String?,
      materialPhotoUrl: json['materialPhotoUrl'] as String?,
      service: json['service'] as String?,
      isServiceProvider: json['isServiceProvider'] as bool?,
      createdAt: const FirestoreDateTimeConverter().fromJson(json['createdAt']),
      updatedAt: const FirestoreDateTimeConverter().fromJson(json['updatedAt']),
      archived: json['archived'] as bool? ?? false,
      meta: json['meta'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$AppUserImplToJson(
  _$AppUserImpl instance,
) => <String, dynamic>{
  'uid': instance.uid,
  'email': instance.email,
  'displayName': instance.displayName,
  'role': _$UserRoleEnumMap[instance.role],
  'phone': instance.phone,
  'photoURL': instance.photoURL,
  'materialPhotoUrl': instance.materialPhotoUrl,
  'service': instance.service,
  'isServiceProvider': instance.isServiceProvider,
  'createdAt': const FirestoreDateTimeConverter().toJson(instance.createdAt),
  'updatedAt': const FirestoreDateTimeConverter().toJson(instance.updatedAt),
  'archived': instance.archived,
  'meta': instance.meta,
};

const _$UserRoleEnumMap = {
  UserRole.superAdmin: 'super_admin',
  UserRole.admin: 'admin',
  UserRole.manager: 'manager',
  UserRole.moderator: 'moderator',
  UserRole.support: 'support',
  UserRole.staff: 'staff',
  UserRole.pro: 'pro',
  UserRole.simpleUser: 'simpleUser',
};
