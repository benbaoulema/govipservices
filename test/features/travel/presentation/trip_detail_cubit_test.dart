import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_cubit.dart';

class _FakeTripDetailRepository implements TripDetailRepository {
  _FakeTripDetailRepository(this._trip);

  final TripDetailModel _trip;

  @override
  Future<TripDetailModel?> getTripDetailById(String tripId) async => _trip;
}

void main() {
  test('cas seats=0 => reservation desactivee', () async {
    const TripDetailModel trip = TripDetailModel(
      id: 't1',
      trackNum: '12345678',
      departurePlace: 'Abidjan, CI',
      arrivalPlace: 'Yamoussoukro, CI',
      departureDate: '2026-03-10',
      departureTime: '08:00',
      arrivalEstimatedTime: '10:00',
      tripFrequency: 'none',
      pricePerSeat: 6000,
      currency: 'XOF',
      seats: 0,
      driver: DriverInfoModel(name: 'Kouame', contactPhone: '0700000000'),
      vehicle: VehicleInfoModel(model: 'Toyota Corolla', photoUrl: ''),
      options: TripOptionsModel(hasLuggageSpace: true, allowsPets: false),
      intermediateStops: <TripStopModel>[],
      status: 'published',
    );

    final TripDetailCubit cubit = TripDetailCubit(
      args: const TripDetailArgs(
        tripId: 't1',
        from: 'Abidjan',
        to: 'Yamoussoukro',
      ),
      getTripDetail: GetTripDetailUseCase(_FakeTripDetailRepository(trip)),
      buildTripRouteNodes: const BuildTripRouteNodesUseCase(),
      resolveTripSegment: const ResolveTripSegmentUseCase(),
      computeSegmentArrivalTime: const ComputeSegmentArrivalTimeUseCase(),
      computeSegmentFare: const ComputeSegmentFareUseCase(),
      frequencyLabelMapper: const TripFrequencyLabelMapper(),
    );

    await cubit.load();

    expect(cubit.state.status.name, 'success');
    expect(cubit.isBookable, isFalse);
    cubit.dispose();
  });
}
