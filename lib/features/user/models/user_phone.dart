import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_phone.freezed.dart';
part 'user_phone.g.dart';

@freezed
class UserPhone with _$UserPhone {
  const factory UserPhone({
    @JsonKey(
      fromJson: _countryCodeFromJson,
      toJson: _countryCodeToJson,
    )
    required String countryCode,
    required String number,
  }) = _UserPhone;

  factory UserPhone.fromJson(Map<String, dynamic> json) => _$UserPhoneFromJson(json);
}

String _countryCodeFromJson(String raw) => normalizeCountryCode(raw);

String _countryCodeToJson(String raw) => normalizeCountryCode(raw);

String normalizeCountryCode(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return '+';
  return trimmed.startsWith('+') ? trimmed : '+$trimmed';
}
