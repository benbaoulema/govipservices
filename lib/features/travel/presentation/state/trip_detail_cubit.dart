import 'package:flutter/foundation.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_state.dart';

class TripDetailCubit extends ChangeNotifier {
  TripDetailCubit({
    required TripDetailArgs args,
    required GetTripDetailUseCase getTripDetail,
    required BuildTripRouteNodesUseCase buildTripRouteNodes,
    required ResolveTripSegmentUseCase resolveTripSegment,
    required ComputeSegmentArrivalTimeUseCase computeSegmentArrivalTime,
    required ComputeSegmentFareUseCase computeSegmentFare,
    required TripFrequencyLabelMapper frequencyLabelMapper,
  })  : _args = args,
        _getTripDetail = getTripDetail,
        _buildTripRouteNodes = buildTripRouteNodes,
        _resolveTripSegment = resolveTripSegment,
        _computeSegmentArrivalTime = computeSegmentArrivalTime,
        _computeSegmentFare = computeSegmentFare,
        _frequencyLabelMapper = frequencyLabelMapper;

  final TripDetailArgs _args;
  final GetTripDetailUseCase _getTripDetail;
  final BuildTripRouteNodesUseCase _buildTripRouteNodes;
  final ResolveTripSegmentUseCase _resolveTripSegment;
  final ComputeSegmentArrivalTimeUseCase _computeSegmentArrivalTime;
  final ComputeSegmentFareUseCase _computeSegmentFare;
  final TripFrequencyLabelMapper _frequencyLabelMapper;

  TripDetailState _state = const TripDetailState();
  TripDetailState get state => _state;
  TripDetailAccessMode get accessMode => _args.accessMode;

  String get displayDate {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return '';
    final String candidate = (_args.effectiveDepartureDate ?? '').trim();
    return candidate.isNotEmpty ? candidate : trip.departureDate;
  }

  String get frequencyLabel {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return 'Ponctuel';
    return _frequencyLabelMapper.label(trip.tripFrequency);
  }

  bool get isBookable {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return false;
    if (_state.status != TripDetailStatus.success) return false;
    if (_state.segment == null) return false;
    final bool published = trip.status.trim() == 'published';
    return published && trip.seats > 0;
  }

  int get totalFare {
    final TripSegmentModel? segment = _state.segment;
    if (segment == null) return 0;
    return _computeSegmentFare(segment, _state.selectedSeats);
  }

  Future<void> load() async {
    _state = _state.copyWith(status: TripDetailStatus.loading, clearError: true);
    notifyListeners();

    try {
      final TripDetailModel? trip = await _getTripDetail(_args.tripId);
      if (trip == null) {
        _state = _state.copyWith(
          status: TripDetailStatus.error,
          errorMessage: 'Trajet introuvable.',
        );
        notifyListeners();
        return;
      }

      final List<TripRouteNode> nodes = _buildTripRouteNodes(trip);
      final TripSegmentModel? segment = _resolveTripSegment(
        nodes: nodes,
        from: _args.from,
        to: _args.to,
      );
      if (segment == null) {
        _state = _state.copyWith(
          status: TripDetailStatus.invalidSegment,
          trip: trip,
          nodes: nodes,
          errorMessage: 'Segment invalide: point de montee/descente introuvable sur ce trajet.',
        );
        notifyListeners();
        return;
      }

      final String? computedArrivalTime = await _computeSegmentArrivalTime(segment: segment);
      final TripSegmentModel finalSegment = computedArrivalTime == null || computedArrivalTime.isEmpty
          ? segment
          : segment.copyWith(
              arrivalNode: segment.arrivalNode.copyWith(time: computedArrivalTime),
            );

      final int maxSeats = trip.seats < 1 ? 1 : trip.seats;
      final int clampedSeats = _state.selectedSeats.clamp(1, maxSeats);
      _state = _state.copyWith(
        status: TripDetailStatus.success,
        trip: trip,
        nodes: nodes,
        segment: finalSegment,
        selectedSeats: clampedSeats,
        clearError: true,
      );
      notifyListeners();
    } catch (_) {
      _state = _state.copyWith(
        status: TripDetailStatus.error,
        errorMessage: 'Erreur lors du chargement du trajet.',
      );
      notifyListeners();
    }
  }

  void incrementSeats() {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return;
    final int max = trip.seats < 1 ? 1 : trip.seats;
    if (_state.selectedSeats >= max) return;
    _state = _state.copyWith(selectedSeats: _state.selectedSeats + 1);
    notifyListeners();
  }

  void decrementSeats() {
    if (_state.selectedSeats <= 1) return;
    _state = _state.copyWith(selectedSeats: _state.selectedSeats - 1);
    notifyListeners();
  }

  void setSeats(int value) {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return;
    final int max = trip.seats < 1 ? 1 : trip.seats;
    final int next = value.clamp(1, max);
    if (next == _state.selectedSeats) return;
    _state = _state.copyWith(selectedSeats: next);
    notifyListeners();
  }

  Future<void> selectDepartureNode(int departureIndex) async {
    final TripSegmentModel? currentSegment = _state.segment;
    final List<TripRouteNode> nodes = _state.nodes;
    if (currentSegment == null || nodes.isEmpty) return;
    if (departureIndex < 0 || departureIndex >= nodes.length) return;
    if (departureIndex >= currentSegment.arrivalIndex) return;

    final TripSegmentModel? nextSegment = _resolveTripSegment(
      nodes: nodes,
      from: nodes[departureIndex].address,
      to: currentSegment.arrivalNode.address,
    );
    if (nextSegment == null) return;

    final String? computedArrivalTime = await _computeSegmentArrivalTime(segment: nextSegment);
    final TripSegmentModel finalSegment = computedArrivalTime == null || computedArrivalTime.isEmpty
        ? nextSegment
        : nextSegment.copyWith(
            arrivalNode: nextSegment.arrivalNode.copyWith(time: computedArrivalTime),
          );

    _state = _state.copyWith(segment: finalSegment);
    notifyListeners();
  }

  Future<void> selectArrivalNode(int arrivalIndex) async {
    final TripSegmentModel? currentSegment = _state.segment;
    final List<TripRouteNode> nodes = _state.nodes;
    if (currentSegment == null || nodes.isEmpty) return;
    if (arrivalIndex < 0 || arrivalIndex >= nodes.length) return;
    if (arrivalIndex <= currentSegment.departureIndex) return;

    final TripSegmentModel? nextSegment = _resolveTripSegment(
      nodes: nodes,
      from: currentSegment.departureNode.address,
      to: nodes[arrivalIndex].address,
    );
    if (nextSegment == null) return;

    final String? computedArrivalTime = await _computeSegmentArrivalTime(segment: nextSegment);
    final TripSegmentModel finalSegment = computedArrivalTime == null || computedArrivalTime.isEmpty
        ? nextSegment
        : nextSegment.copyWith(
            arrivalNode: nextSegment.arrivalNode.copyWith(time: computedArrivalTime),
          );

    _state = _state.copyWith(segment: finalSegment);
    notifyListeners();
  }
}
