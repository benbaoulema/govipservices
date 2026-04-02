import 'package:cloud_firestore/cloud_firestore.dart';
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
  String? _selectedDisplayDate;
  bool _autoAdjustedToNextDay = false;

  TripDetailState _state = const TripDetailState();
  TripDetailState get state => _state;
  TripDetailAccessMode get accessMode => _args.accessMode;

  String get displayDate {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return '';
    final String manualCandidate = (_selectedDisplayDate ?? '').trim();
    if (manualCandidate.isNotEmpty) return manualCandidate;
    final String candidate = (_args.effectiveDepartureDate ?? '').trim();
    if (candidate.isNotEmpty) return candidate;
    return _defaultDisplayDateForTrip(trip);
  }

  bool get canSelectTravelDate {
    final TripDetailModel? trip = _state.trip;
    return trip != null && trip.tripFrequency.trim() == 'daily';
  }

  bool get showAutoAdjustedDateNotice =>
      canSelectTravelDate && _autoAdjustedToNextDay;

  String get autoAdjustedDateMessage {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return '';
    return 'Le depart de ${trip.departureTime} pour aujourd hui est deja passe. '
        'Nous vous proposons le prochain depart disponible.';
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
    final int effectiveSeats = _state.availableSeats ?? trip.seats;
    return published && effectiveSeats > 0;
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
          errorMessage:
              'Segment invalide: point de montee/descente introuvable sur ce trajet.',
        );
        notifyListeners();
        return;
      }

      final String? computedArrivalTime =
          await _computeSegmentArrivalTime(segment: segment);
      final TripSegmentModel finalSegment =
          computedArrivalTime == null || computedArrivalTime.isEmpty
              ? segment
              : segment.copyWith(
                  arrivalNode: segment.arrivalNode.copyWith(
                    time: computedArrivalTime,
                  ),
                );

      _selectedDisplayDate = _resolveInitialDisplayDate(trip);
      final int effectiveAvailableSeats = await _resolveAvailableSeats(
        tripId: trip.id,
        tripFrequency: trip.tripFrequency,
        effectiveDepartureDate: _selectedDisplayDate ?? '',
        fallbackSeats: trip.seats,
        segmentOccupancy: trip.segmentOccupancy,
        segmentPoints: trip.segmentPoints,
        fromAddress: finalSegment.departureNode.address,
        toAddress: finalSegment.arrivalNode.address,
      );
      final int clampedSeats = _state.selectedSeats.clamp(
        1,
        effectiveAvailableSeats < 1 ? 1 : effectiveAvailableSeats,
      );
      _state = _state.copyWith(
        status: TripDetailStatus.success,
        trip: trip,
        nodes: nodes,
        segment: finalSegment,
        selectedSeats: clampedSeats,
        availableSeats: effectiveAvailableSeats,
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
    final int effective = _state.availableSeats ?? trip.seats;
    final int max = effective < 1 ? 1 : effective;
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
    final int effective = _state.availableSeats ?? trip.seats;
    final int max = effective < 1 ? 1 : effective;
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

    final String? computedArrivalTime =
        await _computeSegmentArrivalTime(segment: nextSegment);
    final TripSegmentModel finalSegment =
        computedArrivalTime == null || computedArrivalTime.isEmpty
            ? nextSegment
            : nextSegment.copyWith(
                arrivalNode: nextSegment.arrivalNode.copyWith(
                  time: computedArrivalTime,
                ),
              );

    final TripDetailModel? trip = _state.trip;
    if (trip == null) return;
    final int availableSeats = await _resolveAvailableSeats(
      tripId: trip.id,
      tripFrequency: trip.tripFrequency,
      effectiveDepartureDate: displayDate,
      fallbackSeats: trip.seats,
      segmentOccupancy: trip.segmentOccupancy,
      segmentPoints: trip.segmentPoints,
      fromAddress: finalSegment.departureNode.address,
      toAddress: finalSegment.arrivalNode.address,
    );
    final int nextSelectedSeats = _state.selectedSeats.clamp(
      1,
      availableSeats < 1 ? 1 : availableSeats,
    );
    _state = _state.copyWith(
      segment: finalSegment,
      availableSeats: availableSeats,
      selectedSeats: nextSelectedSeats,
    );
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

    final String? computedArrivalTime =
        await _computeSegmentArrivalTime(segment: nextSegment);
    final TripSegmentModel finalSegment =
        computedArrivalTime == null || computedArrivalTime.isEmpty
            ? nextSegment
            : nextSegment.copyWith(
                arrivalNode: nextSegment.arrivalNode.copyWith(
                  time: computedArrivalTime,
                ),
              );

    final TripDetailModel? trip = _state.trip;
    if (trip == null) return;
    final int availableSeats = await _resolveAvailableSeats(
      tripId: trip.id,
      tripFrequency: trip.tripFrequency,
      effectiveDepartureDate: displayDate,
      fallbackSeats: trip.seats,
      segmentOccupancy: trip.segmentOccupancy,
      segmentPoints: trip.segmentPoints,
      fromAddress: finalSegment.departureNode.address,
      toAddress: finalSegment.arrivalNode.address,
    );
    final int nextSelectedSeats = _state.selectedSeats.clamp(
      1,
      availableSeats < 1 ? 1 : availableSeats,
    );
    _state = _state.copyWith(
      segment: finalSegment,
      availableSeats: availableSeats,
      selectedSeats: nextSelectedSeats,
    );
    notifyListeners();
  }

  Future<void> selectTravelDate(DateTime pickedDate) async {
    final TripDetailModel? trip = _state.trip;
    if (trip == null || !canSelectTravelDate) return;
    final String? normalized = _normalizeDailyDateSelection(
      trip: trip,
      date: pickedDate,
    );
    if (normalized == null || normalized == displayDate) return;
    _selectedDisplayDate = normalized;
    _autoAdjustedToNextDay = false;
    final int availableSeats = await _resolveAvailableSeats(
      tripId: trip.id,
      tripFrequency: trip.tripFrequency,
      effectiveDepartureDate: normalized,
      fallbackSeats: trip.seats,
      segmentOccupancy: trip.segmentOccupancy,
      segmentPoints: trip.segmentPoints,
      fromAddress: _state.segment?.departureNode.address,
      toAddress: _state.segment?.arrivalNode.address,
    );
    final int nextSelectedSeats = _state.selectedSeats.clamp(
      1,
      availableSeats < 1 ? 1 : availableSeats,
    );
    _state = _state.copyWith(
      availableSeats: availableSeats,
      selectedSeats: nextSelectedSeats,
    );
    notifyListeners();
  }

  bool isSelectableTravelDate(DateTime date) {
    final TripDetailModel? trip = _state.trip;
    if (trip == null) return false;
    if (!canSelectTravelDate) return true;
    return _normalizeDailyDateSelection(trip: trip, date: date) != null;
  }

  String _resolveInitialDisplayDate(TripDetailModel trip) {
    final String argDate = (_args.effectiveDepartureDate ?? '').trim();
    if (argDate.isNotEmpty && trip.tripFrequency.trim() != 'daily') {
      _autoAdjustedToNextDay = false;
      return argDate;
    }
    if (argDate.isNotEmpty && trip.tripFrequency.trim() == 'daily') {
      final DateTime? parsedArgDate = DateTime.tryParse(argDate);
      if (parsedArgDate != null) {
        final String? normalized = _normalizeDailyDateSelection(
          trip: trip,
          date: parsedArgDate,
        );
        if (normalized != null) {
          _autoAdjustedToNextDay = false;
          return normalized;
        }
      }
    }
    return _defaultDisplayDateForTrip(trip);
  }

  String _defaultDisplayDateForTrip(TripDetailModel trip) {
    if (trip.tripFrequency.trim() != 'daily') {
      _autoAdjustedToNextDay = false;
      return trip.departureDate;
    }

    final DateTime now = DateTime.now();
    final _ParsedClock? departureClock = _parseClock(trip.departureTime);
    if (departureClock == null) {
      _autoAdjustedToNextDay = false;
      return _formatIsoDate(now);
    }

    final DateTime todayDeparture = DateTime(
      now.year,
      now.month,
      now.day,
      departureClock.hour,
      departureClock.minute,
    );
    final DateTime chosenDay =
        now.isAfter(todayDeparture) ? now.add(const Duration(days: 1)) : now;
    _autoAdjustedToNextDay = now.isAfter(todayDeparture);
    return _formatIsoDate(chosenDay);
  }

  String? _normalizeDailyDateSelection({
    required TripDetailModel trip,
    required DateTime date,
  }) {
    final _ParsedClock? departureClock = _parseClock(trip.departureTime);
    if (departureClock == null) return null;
    final DateTime candidate = DateTime(
      date.year,
      date.month,
      date.day,
      departureClock.hour,
      departureClock.minute,
    );
    if (!candidate.isAfter(DateTime.now())) return null;
    return _formatIsoDate(candidate);
  }

  _ParsedClock? _parseClock(String raw) {
    final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return _ParsedClock(hour: hour, minute: minute);
  }

  String _formatIsoDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<int> _resolveAvailableSeats({
    required String tripId,
    required String tripFrequency,
    required String effectiveDepartureDate,
    required int fallbackSeats,
    Map<String, int> segmentOccupancy = const <String, int>{},
    List<String> segmentPoints = const <String>[],
    String? fromAddress,
    String? toAddress,
  }) async {
    final String normalizedTripFrequency = tripFrequency.trim().toLowerCase();
    final bool usesOccurrences =
        normalizedTripFrequency != 'none' && effectiveDepartureDate.trim().isNotEmpty;
    Map<String, int> effectiveSegmentOccupancy = Map<String, int>.from(
      segmentOccupancy,
    );

    try {
      if (usesOccurrences) {
        final DocumentSnapshot<Map<String, dynamic>> occurrenceSnapshot =
            await FirebaseFirestore.instance
                .collection('voyageTrips')
                .doc(tripId)
                .collection('occurrences')
                .doc(effectiveDepartureDate)
                .get();
        final Map<String, dynamic>? occurrence = occurrenceSnapshot.data();
        if (occurrence != null) {
          final Map<String, int> occurrenceSegmentOccupancy =
              _parseSegmentOccupancy(occurrence['segmentOccupancy']);
          if (occurrenceSegmentOccupancy.isNotEmpty) {
            effectiveSegmentOccupancy = occurrenceSegmentOccupancy;
          }
          if (effectiveSegmentOccupancy.isEmpty || segmentPoints.length < 2) {
            final Object? rawRemainingSeats = occurrence['remainingSeats'];
            if (rawRemainingSeats is int) return rawRemainingSeats;
            if (rawRemainingSeats is num) return rawRemainingSeats.toInt();
            return int.tryParse('$rawRemainingSeats') ?? fallbackSeats;
          }
        } else if (effectiveSegmentOccupancy.isEmpty || segmentPoints.length < 2) {
          return fallbackSeats;
        }
      } else if (effectiveSegmentOccupancy.isEmpty || segmentPoints.length < 2) {
        return fallbackSeats;
      }
    } catch (_) {
      if (effectiveSegmentOccupancy.isEmpty || segmentPoints.length < 2) {
        return fallbackSeats;
      }
    }

    if (effectiveSegmentOccupancy.isNotEmpty && segmentPoints.length >= 2) {
      final String from = (fromAddress ?? _args.from).trim();
      final String to = (toAddress ?? _args.to).trim();
      final int fromIdx = segmentPoints.indexWhere((p) => p == from);
      final int toIdx = segmentPoints.indexWhere((p) => p == to);
      if (fromIdx >= 0 && toIdx > fromIdx) {
        int maxOccupied = 0;
        for (int i = fromIdx; i < toIdx; i++) {
          final String key = '${segmentPoints[i]}__${segmentPoints[i + 1]}';
          final int occ = effectiveSegmentOccupancy[key] ?? 0;
          if (occ > maxOccupied) maxOccupied = occ;
        }
        return (fallbackSeats - maxOccupied).clamp(0, fallbackSeats);
      }
    }

    return fallbackSeats;
  }

  Map<String, int> _parseSegmentOccupancy(Object? value) {
    if (value is! Map) return const <String, int>{};
    final Map<String, int> result = <String, int>{};
    for (final MapEntry<dynamic, dynamic> entry in value.entries) {
      final String key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      final Object? rawValue = entry.value;
      final int parsed = rawValue is int
          ? rawValue
          : (rawValue is num ? rawValue.toInt() : int.tryParse('$rawValue') ?? 0);
      result[key] = parsed;
    }
    return result;
  }
}

class _ParsedClock {
  const _ParsedClock({
    required this.hour,
    required this.minute,
  });

  final int hour;
  final int minute;
}
