enum TripFrequency { none, daily, weekly, monthly }

TripFrequency parseTripFrequency(String? value) {
  switch ((value ?? '').trim()) {
    case 'daily':
      return TripFrequency.daily;
    case 'weekly':
      return TripFrequency.weekly;
    case 'monthly':
      return TripFrequency.monthly;
    case 'none':
    default:
      return TripFrequency.none;
  }
}

TripFrequency safeTripFrequency(dynamic raw, {required bool isFrequentTripFallback}) {
  final String v = (raw ?? '').toString().trim();
  if (v == 'daily' || v == 'weekly' || v == 'monthly' || v == 'none') {
    return parseTripFrequency(v);
  }
  return isFrequentTripFallback ? TripFrequency.weekly : TripFrequency.none;
}

class _ParsedIsoDate {
  const _ParsedIsoDate(this.year, this.month, this.day, this.utcDate);

  final int year;
  final int month;
  final int day;
  final DateTime utcDate;
}

_ParsedIsoDate? _parseIsoDateStrict(String value) {
  final String raw = value.trim();
  final Match? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (m == null) return null;

  final int? year = int.tryParse(m.group(1)!);
  final int? month = int.tryParse(m.group(2)!);
  final int? day = int.tryParse(m.group(3)!);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12) return null;

  final DateTime dt = DateTime.utc(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;

  return _ParsedIsoDate(year, month, day, dt);
}

int _diffDaysUtc(DateTime a, DateTime b) {
  return b.difference(a).inMilliseconds ~/ 86400000;
}

int _daysInMonth(int year, int month) {
  return DateTime.utc(year, month + 1, 0).day;
}

int _diffMonths(_ParsedIsoDate a, _ParsedIsoDate b) {
  return (b.year - a.year) * 12 + (b.month - a.month);
}

bool matchesTripForSearchDate({
  required String tripDepartureDate,
  required String searchDate,
  TripFrequency tripFrequency = TripFrequency.none,
}) {
  final _ParsedIsoDate? start = _parseIsoDateStrict(tripDepartureDate);
  final _ParsedIsoDate? target = _parseIsoDateStrict(searchDate);
  if (start == null || target == null) return false;

  if (tripFrequency == TripFrequency.none) {
    return start.year == target.year &&
        start.month == target.month &&
        start.day == target.day;
  }

  final int dayGap = _diffDaysUtc(start.utcDate, target.utcDate);
  if (dayGap < 0) return false;

  if (tripFrequency == TripFrequency.daily) return true;
  if (tripFrequency == TripFrequency.weekly) return dayGap % 7 == 0;

  final int monthGap = _diffMonths(start, target);
  if (monthGap < 0) return false;
  final int expectedDay = start.day <= _daysInMonth(target.year, target.month)
      ? start.day
      : _daysInMonth(target.year, target.month);
  return target.day == expectedDay;
}
