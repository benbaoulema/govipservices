import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';

enum TripDetailStatus {
  initial,
  loading,
  success,
  error,
  invalidSegment,
}

class TripDetailState {
  const TripDetailState({
    this.status = TripDetailStatus.initial,
    this.trip,
    this.nodes = const <TripRouteNode>[],
    this.segment,
    this.selectedSeats = 1,
    this.availableSeats,
    this.errorMessage,
  });

  final TripDetailStatus status;
  final TripDetailModel? trip;
  final List<TripRouteNode> nodes;
  final TripSegmentModel? segment;
  final int selectedSeats;
  final int? availableSeats;
  final String? errorMessage;

  TripDetailState copyWith({
    TripDetailStatus? status,
    TripDetailModel? trip,
    List<TripRouteNode>? nodes,
    TripSegmentModel? segment,
    int? selectedSeats,
    int? availableSeats,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TripDetailState(
      status: status ?? this.status,
      trip: trip ?? this.trip,
      nodes: nodes ?? this.nodes,
      segment: segment ?? this.segment,
      selectedSeats: selectedSeats ?? this.selectedSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
