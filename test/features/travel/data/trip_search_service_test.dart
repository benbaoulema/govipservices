import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/data/trip_search_service.dart';

void main() {
  group('trip search parity', () {
    test('tri final recherche date/time', () {
      final List<Map<String, dynamic>> docs = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'b',
          'status': 'published',
          'departurePlace': 'Abidjan, CI',
          'arrivalPlace': 'Yamoussoukro, CI',
          'departureDate': '2026-03-01',
          'departureTime': '09:00',
          'tripFrequency': 'weekly',
          'isFrequentTrip': true,
          'pricePerSeat': 5000,
          'seats': 3,
        },
        <String, dynamic>{
          'id': 'a',
          'status': 'published',
          'departurePlace': 'Abidjan, CI',
          'arrivalPlace': 'Yamoussoukro, CI',
          'departureDate': '2026-03-01',
          'departureTime': '08:00',
          'tripFrequency': 'weekly',
          'isFrequentTrip': true,
          'pricePerSeat': 4500,
          'seats': 2,
        },
      ];

      final List<VoyageTripSearchItem> out = searchVoyageTripsLocal(
        docs: docs,
        departureDate: '2026-03-15',
      );

      expect(out.length, 2);
      expect(out.first.id, 'a');
      expect(out.first.effectiveDepartureDate, '2026-03-15');
      expect(out.last.id, 'b');
    });

    test('segment matching avec stops', () {
      final VoyageTripSearchItem trip = mapTripDoc('t1', <String, dynamic>{
        'departurePlace': 'Abidjan, CI',
        'arrivalPlace': 'Bouake, CI',
        'departureDate': '2026-03-10',
        'departureTime': '08:00',
        'pricePerSeat': 10000,
        'currency': 'XOF',
        'seats': 3,
        'tripFrequency': 'none',
        'status': 'published',
        'intermediateStops': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 's1',
            'address': 'Yamoussoukro, CI',
            'estimatedTime': '10:00',
            'priceFromDeparture': 6000,
          },
        ],
      })!;

      final List<TripRouteNode> nodes = buildTripRouteNodes(trip);
      final TripSegmentModel? segment = resolveTripSegment(
        nodes: nodes,
        from: 'Yamoussoukro',
        to: 'Bouake',
      );

      expect(segment, isNotNull);
      expect(segment!.segmentPrice, 4000);
    });

    test('segment invalid arrIndex <= depIndex', () {
      final VoyageTripSearchItem trip = mapTripDoc('t2', <String, dynamic>{
        'departurePlace': 'Abidjan, CI',
        'arrivalPlace': 'Bouake, CI',
        'departureDate': '2026-03-10',
        'departureTime': '08:00',
        'pricePerSeat': 10000,
        'currency': 'XOF',
        'seats': 3,
        'tripFrequency': 'none',
        'status': 'published',
      })!;

      final TripSegmentModel? segment = resolveTripSegment(
        nodes: buildTripRouteNodes(trip),
        from: 'Bouake',
        to: 'Abidjan',
      );

      expect(segment, isNull);
    });
  });
}
