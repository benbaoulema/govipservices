// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_phone.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserPhoneImpl _$$UserPhoneImplFromJson(Map<String, dynamic> json) =>
    _$UserPhoneImpl(
      countryCode: _countryCodeFromJson(json['countryCode'] as String),
      number: json['number'] as String,
    );

Map<String, dynamic> _$$UserPhoneImplToJson(_$UserPhoneImpl instance) =>
    <String, dynamic>{
      'countryCode': _countryCodeToJson(instance.countryCode),
      'number': instance.number,
    };
