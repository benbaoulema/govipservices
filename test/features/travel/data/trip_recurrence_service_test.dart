import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/data/trip_recurrence_service.dart';

void main() {
  group('trip recurrence parity', () {
    test('none exact and non exact', () {
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-10',
          tripFrequency: TripFrequency.none,
        ),
        isTrue,
      );
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-11',
          tripFrequency: TripFrequency.none,
        ),
        isFalse,
      );
    });

    test('daily', () {
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-15',
          tripFrequency: TripFrequency.daily,
        ),
        isTrue,
      );
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-09',
          tripFrequency: TripFrequency.daily,
        ),
        isFalse,
      );
    });

    test('weekly modulo 7', () {
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-24',
          tripFrequency: TripFrequency.weekly,
        ),
        isTrue,
      );
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-03-10',
          searchDate: '2026-03-25',
          tripFrequency: TripFrequency.weekly,
        ),
        isFalse,
      );
    });

    test('monthly day clamp 31 to month end', () {
      expect(
        matchesTripForSearchDate(
          tripDepartureDate: '2026-01-31',
          searchDate: '2026-02-28',
          tripFrequency: TripFrequency.monthly,
        ),
        isTrue,
      );
    });

    test('invalid frequency fallback', () {
      expect(
        safeTripFrequency('weird', isFrequentTripFallback: true),
        TripFrequency.weekly,
      );
      expect(
        safeTripFrequency('weird', isFrequentTripFallback: false),
        TripFrequency.none,
      );
    });
  });
}
