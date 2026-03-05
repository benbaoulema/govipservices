import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';

void main() {
  group('Trip detail use cases', () {
    test('calcul segment avec stops', () {
      const ResolveTripSegmentUseCase useCase = ResolveTripSegmentUseCase();

      const List<TripRouteNode> nodes = <TripRouteNode>[
        TripRouteNode(kind: 'departure', address: 'Abidjan, CI', time: '08:00', priceFromDeparture: 0),
        TripRouteNode(kind: 'stop', address: 'Yamoussoukro, CI', time: '10:00', priceFromDeparture: 6000),
        TripRouteNode(kind: 'arrival', address: 'Bouake, CI', time: '12:00', priceFromDeparture: 10000),
      ];

      final TripSegmentModel? segment = useCase(
        nodes: nodes,
        from: 'Yamoussoukro',
        to: 'Bouake',
      );

      expect(segment, isNotNull);
      expect(segment!.segmentPrice, 4000);
      expect(segment.departureIndex, 1);
      expect(segment.arrivalIndex, 2);
    });

    test('cas arrIndex <= depIndex', () {
      const ResolveTripSegmentUseCase useCase = ResolveTripSegmentUseCase();

      const List<TripRouteNode> nodes = <TripRouteNode>[
        TripRouteNode(kind: 'departure', address: 'Abidjan, CI', time: '08:00', priceFromDeparture: 0),
        TripRouteNode(kind: 'arrival', address: 'Bouake, CI', time: '12:00', priceFromDeparture: 10000),
      ];

      final TripSegmentModel? segment = useCase(
        nodes: nodes,
        from: 'Bouake',
        to: 'Abidjan',
      );

      expect(segment, isNull);
    });

    test('affichage frequence', () {
      const TripFrequencyLabelMapper mapper = TripFrequencyLabelMapper();
      expect(mapper.label('none'), 'Ponctuel');
      expect(mapper.label('daily'), 'Quotidien');
      expect(mapper.label('weekly'), 'Hebdo');
      expect(mapper.label('monthly'), 'Mensuel');
      expect(mapper.label('weird'), 'Ponctuel');
    });
  });
}
