// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_phone.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

UserPhone _$UserPhoneFromJson(Map<String, dynamic> json) {
  return _UserPhone.fromJson(json);
}

/// @nodoc
mixin _$UserPhone {
  @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
  String get countryCode => throw _privateConstructorUsedError;
  String get number => throw _privateConstructorUsedError;

  /// Serializes this UserPhone to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserPhone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserPhoneCopyWith<UserPhone> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserPhoneCopyWith<$Res> {
  factory $UserPhoneCopyWith(UserPhone value, $Res Function(UserPhone) then) =
      _$UserPhoneCopyWithImpl<$Res, UserPhone>;
  @useResult
  $Res call({
    @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
    String countryCode,
    String number,
  });
}

/// @nodoc
class _$UserPhoneCopyWithImpl<$Res, $Val extends UserPhone>
    implements $UserPhoneCopyWith<$Res> {
  _$UserPhoneCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserPhone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? countryCode = null, Object? number = null}) {
    return _then(
      _value.copyWith(
            countryCode: null == countryCode
                ? _value.countryCode
                : countryCode // ignore: cast_nullable_to_non_nullable
                      as String,
            number: null == number
                ? _value.number
                : number // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UserPhoneImplCopyWith<$Res>
    implements $UserPhoneCopyWith<$Res> {
  factory _$$UserPhoneImplCopyWith(
    _$UserPhoneImpl value,
    $Res Function(_$UserPhoneImpl) then,
  ) = __$$UserPhoneImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
    String countryCode,
    String number,
  });
}

/// @nodoc
class __$$UserPhoneImplCopyWithImpl<$Res>
    extends _$UserPhoneCopyWithImpl<$Res, _$UserPhoneImpl>
    implements _$$UserPhoneImplCopyWith<$Res> {
  __$$UserPhoneImplCopyWithImpl(
    _$UserPhoneImpl _value,
    $Res Function(_$UserPhoneImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UserPhone
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? countryCode = null, Object? number = null}) {
    return _then(
      _$UserPhoneImpl(
        countryCode: null == countryCode
            ? _value.countryCode
            : countryCode // ignore: cast_nullable_to_non_nullable
                  as String,
        number: null == number
            ? _value.number
            : number // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UserPhoneImpl implements _UserPhone {
  const _$UserPhoneImpl({
    @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
    required this.countryCode,
    required this.number,
  });

  factory _$UserPhoneImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserPhoneImplFromJson(json);

  @override
  @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
  final String countryCode;
  @override
  final String number;

  @override
  String toString() {
    return 'UserPhone(countryCode: $countryCode, number: $number)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserPhoneImpl &&
            (identical(other.countryCode, countryCode) ||
                other.countryCode == countryCode) &&
            (identical(other.number, number) || other.number == number));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, countryCode, number);

  /// Create a copy of UserPhone
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserPhoneImplCopyWith<_$UserPhoneImpl> get copyWith =>
      __$$UserPhoneImplCopyWithImpl<_$UserPhoneImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserPhoneImplToJson(this);
  }
}

abstract class _UserPhone implements UserPhone {
  const factory _UserPhone({
    @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
    required final String countryCode,
    required final String number,
  }) = _$UserPhoneImpl;

  factory _UserPhone.fromJson(Map<String, dynamic> json) =
      _$UserPhoneImpl.fromJson;

  @override
  @JsonKey(fromJson: _countryCodeFromJson, toJson: _countryCodeToJson)
  String get countryCode;
  @override
  String get number;

  /// Create a copy of UserPhone
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserPhoneImplCopyWith<_$UserPhoneImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
