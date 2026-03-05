// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

AppUser _$AppUserFromJson(Map<String, dynamic> json) {
  return _AppUser.fromJson(json);
}

/// @nodoc
mixin _$AppUser {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? get id => throw _privateConstructorUsedError;
  String get uid => throw _privateConstructorUsedError;
  String? get email => throw _privateConstructorUsedError;
  String? get displayName => throw _privateConstructorUsedError;
  UserRole? get role => throw _privateConstructorUsedError;
  UserPhone? get phone => throw _privateConstructorUsedError;
  String? get photoURL => throw _privateConstructorUsedError;
  String? get materialPhotoUrl => throw _privateConstructorUsedError;
  String? get service => throw _privateConstructorUsedError;
  bool? get isServiceProvider => throw _privateConstructorUsedError;
  @FirestoreDateTimeConverter()
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @FirestoreDateTimeConverter()
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  bool get archived => throw _privateConstructorUsedError;
  Map<String, dynamic>? get meta => throw _privateConstructorUsedError;

  /// Serializes this AppUser to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppUserCopyWith<AppUser> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppUserCopyWith<$Res> {
  factory $AppUserCopyWith(AppUser value, $Res Function(AppUser) then) =
      _$AppUserCopyWithImpl<$Res, AppUser>;
  @useResult
  $Res call({
    @JsonKey(includeFromJson: false, includeToJson: false) String? id,
    String uid,
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
    bool archived,
    Map<String, dynamic>? meta,
  });

  $UserPhoneCopyWith<$Res>? get phone;
}

/// @nodoc
class _$AppUserCopyWithImpl<$Res, $Val extends AppUser>
    implements $AppUserCopyWith<$Res> {
  _$AppUserCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? uid = null,
    Object? email = freezed,
    Object? displayName = freezed,
    Object? role = freezed,
    Object? phone = freezed,
    Object? photoURL = freezed,
    Object? materialPhotoUrl = freezed,
    Object? service = freezed,
    Object? isServiceProvider = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? archived = null,
    Object? meta = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: freezed == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String?,
            uid: null == uid
                ? _value.uid
                : uid // ignore: cast_nullable_to_non_nullable
                      as String,
            email: freezed == email
                ? _value.email
                : email // ignore: cast_nullable_to_non_nullable
                      as String?,
            displayName: freezed == displayName
                ? _value.displayName
                : displayName // ignore: cast_nullable_to_non_nullable
                      as String?,
            role: freezed == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as UserRole?,
            phone: freezed == phone
                ? _value.phone
                : phone // ignore: cast_nullable_to_non_nullable
                      as UserPhone?,
            photoURL: freezed == photoURL
                ? _value.photoURL
                : photoURL // ignore: cast_nullable_to_non_nullable
                      as String?,
            materialPhotoUrl: freezed == materialPhotoUrl
                ? _value.materialPhotoUrl
                : materialPhotoUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            service: freezed == service
                ? _value.service
                : service // ignore: cast_nullable_to_non_nullable
                      as String?,
            isServiceProvider: freezed == isServiceProvider
                ? _value.isServiceProvider
                : isServiceProvider // ignore: cast_nullable_to_non_nullable
                      as bool?,
            createdAt: freezed == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            updatedAt: freezed == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime?,
            archived: null == archived
                ? _value.archived
                : archived // ignore: cast_nullable_to_non_nullable
                      as bool,
            meta: freezed == meta
                ? _value.meta
                : meta // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
          )
          as $Val,
    );
  }

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $UserPhoneCopyWith<$Res>? get phone {
    if (_value.phone == null) {
      return null;
    }

    return $UserPhoneCopyWith<$Res>(_value.phone!, (value) {
      return _then(_value.copyWith(phone: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$AppUserImplCopyWith<$Res> implements $AppUserCopyWith<$Res> {
  factory _$$AppUserImplCopyWith(
    _$AppUserImpl value,
    $Res Function(_$AppUserImpl) then,
  ) = __$$AppUserImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(includeFromJson: false, includeToJson: false) String? id,
    String uid,
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
    bool archived,
    Map<String, dynamic>? meta,
  });

  @override
  $UserPhoneCopyWith<$Res>? get phone;
}

/// @nodoc
class __$$AppUserImplCopyWithImpl<$Res>
    extends _$AppUserCopyWithImpl<$Res, _$AppUserImpl>
    implements _$$AppUserImplCopyWith<$Res> {
  __$$AppUserImplCopyWithImpl(
    _$AppUserImpl _value,
    $Res Function(_$AppUserImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = freezed,
    Object? uid = null,
    Object? email = freezed,
    Object? displayName = freezed,
    Object? role = freezed,
    Object? phone = freezed,
    Object? photoURL = freezed,
    Object? materialPhotoUrl = freezed,
    Object? service = freezed,
    Object? isServiceProvider = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? archived = null,
    Object? meta = freezed,
  }) {
    return _then(
      _$AppUserImpl(
        id: freezed == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String?,
        uid: null == uid
            ? _value.uid
            : uid // ignore: cast_nullable_to_non_nullable
                  as String,
        email: freezed == email
            ? _value.email
            : email // ignore: cast_nullable_to_non_nullable
                  as String?,
        displayName: freezed == displayName
            ? _value.displayName
            : displayName // ignore: cast_nullable_to_non_nullable
                  as String?,
        role: freezed == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as UserRole?,
        phone: freezed == phone
            ? _value.phone
            : phone // ignore: cast_nullable_to_non_nullable
                  as UserPhone?,
        photoURL: freezed == photoURL
            ? _value.photoURL
            : photoURL // ignore: cast_nullable_to_non_nullable
                  as String?,
        materialPhotoUrl: freezed == materialPhotoUrl
            ? _value.materialPhotoUrl
            : materialPhotoUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        service: freezed == service
            ? _value.service
            : service // ignore: cast_nullable_to_non_nullable
                  as String?,
        isServiceProvider: freezed == isServiceProvider
            ? _value.isServiceProvider
            : isServiceProvider // ignore: cast_nullable_to_non_nullable
                  as bool?,
        createdAt: freezed == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        updatedAt: freezed == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime?,
        archived: null == archived
            ? _value.archived
            : archived // ignore: cast_nullable_to_non_nullable
                  as bool,
        meta: freezed == meta
            ? _value._meta
            : meta // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$AppUserImpl implements _AppUser {
  const _$AppUserImpl({
    @JsonKey(includeFromJson: false, includeToJson: false) this.id,
    required this.uid,
    this.email,
    this.displayName,
    this.role,
    this.phone,
    this.photoURL,
    this.materialPhotoUrl,
    this.service,
    this.isServiceProvider,
    @FirestoreDateTimeConverter() this.createdAt,
    @FirestoreDateTimeConverter() this.updatedAt,
    this.archived = false,
    final Map<String, dynamic>? meta,
  }) : _meta = meta;

  factory _$AppUserImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppUserImplFromJson(json);

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? id;
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  @override
  final UserRole? role;
  @override
  final UserPhone? phone;
  @override
  final String? photoURL;
  @override
  final String? materialPhotoUrl;
  @override
  final String? service;
  @override
  final bool? isServiceProvider;
  @override
  @FirestoreDateTimeConverter()
  final DateTime? createdAt;
  @override
  @FirestoreDateTimeConverter()
  final DateTime? updatedAt;
  @override
  @JsonKey()
  final bool archived;
  final Map<String, dynamic>? _meta;
  @override
  Map<String, dynamic>? get meta {
    final value = _meta;
    if (value == null) return null;
    if (_meta is EqualUnmodifiableMapView) return _meta;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'AppUser(id: $id, uid: $uid, email: $email, displayName: $displayName, role: $role, phone: $phone, photoURL: $photoURL, materialPhotoUrl: $materialPhotoUrl, service: $service, isServiceProvider: $isServiceProvider, createdAt: $createdAt, updatedAt: $updatedAt, archived: $archived, meta: $meta)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppUserImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.photoURL, photoURL) ||
                other.photoURL == photoURL) &&
            (identical(other.materialPhotoUrl, materialPhotoUrl) ||
                other.materialPhotoUrl == materialPhotoUrl) &&
            (identical(other.service, service) || other.service == service) &&
            (identical(other.isServiceProvider, isServiceProvider) ||
                other.isServiceProvider == isServiceProvider) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.archived, archived) ||
                other.archived == archived) &&
            const DeepCollectionEquality().equals(other._meta, _meta));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    uid,
    email,
    displayName,
    role,
    phone,
    photoURL,
    materialPhotoUrl,
    service,
    isServiceProvider,
    createdAt,
    updatedAt,
    archived,
    const DeepCollectionEquality().hash(_meta),
  );

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppUserImplCopyWith<_$AppUserImpl> get copyWith =>
      __$$AppUserImplCopyWithImpl<_$AppUserImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppUserImplToJson(this);
  }
}

abstract class _AppUser implements AppUser {
  const factory _AppUser({
    @JsonKey(includeFromJson: false, includeToJson: false) final String? id,
    required final String uid,
    final String? email,
    final String? displayName,
    final UserRole? role,
    final UserPhone? phone,
    final String? photoURL,
    final String? materialPhotoUrl,
    final String? service,
    final bool? isServiceProvider,
    @FirestoreDateTimeConverter() final DateTime? createdAt,
    @FirestoreDateTimeConverter() final DateTime? updatedAt,
    final bool archived,
    final Map<String, dynamic>? meta,
  }) = _$AppUserImpl;

  factory _AppUser.fromJson(Map<String, dynamic> json) = _$AppUserImpl.fromJson;

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? get id;
  @override
  String get uid;
  @override
  String? get email;
  @override
  String? get displayName;
  @override
  UserRole? get role;
  @override
  UserPhone? get phone;
  @override
  String? get photoURL;
  @override
  String? get materialPhotoUrl;
  @override
  String? get service;
  @override
  bool? get isServiceProvider;
  @override
  @FirestoreDateTimeConverter()
  DateTime? get createdAt;
  @override
  @FirestoreDateTimeConverter()
  DateTime? get updatedAt;
  @override
  bool get archived;
  @override
  Map<String, dynamic>? get meta;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppUserImplCopyWith<_$AppUserImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
