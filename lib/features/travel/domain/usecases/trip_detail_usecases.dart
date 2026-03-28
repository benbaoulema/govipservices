import 'dart:convert';
import 'dart:io';

import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';

class GetTripDetailUseCase {
  const GetTripDetailUseCase(this._repository);

  final TripDetailRepository _repository;

  Future<TripDetailModel?> call(String tripId) {
    return _repository.getTripDetailById(tripId);
  }
}

class BuildTripRouteNodesUseCase {
  const BuildTripRouteNodesUseCase();

  List<TripRouteNode> call(TripDetailModel trip) {
    final List<TripRouteNode> stops = trip.intermediateStops
        .map(
          (s) => TripRouteNode(
            kind: 'stop',
            address: s.address,
            time: s.estimatedTime,
            priceFromDeparture: s.priceFromDeparture < 0 ? 0 : s.priceFromDeparture,
            lat: s.lat,
            lng: s.lng,
            bookable: s.bookable,
          ),
        )
        .toList(growable: false);

    return <TripRouteNode>[
      TripRouteNode(
        kind: 'departure',
        address: trip.departurePlace,
        time: trip.departureTime,
        priceFromDeparture: 0,
      ),
      ...stops,
      TripRouteNode(
        kind: 'arrival',
        address: trip.arrivalPlace,
        time: trip.arrivalEstimatedTime,
        priceFromDeparture: trip.pricePerSeat < 0 ? 0 : trip.pricePerSeat,
      ),
    ];
  }
}

class ResolveTripSegmentUseCase {
  const ResolveTripSegmentUseCase();

  TripSegmentModel? call({
    required List<TripRouteNode> nodes,
    required String from,
    required String to,
  }) {
    if (nodes.isEmpty) return null;
    final int depIndex = from.trim().isEmpty ? 0 : _findNodeIndex(nodes, from);
    if (depIndex < 0) return null;

    final int arrIndex = to.trim().isEmpty ? nodes.length - 1 : _findNodeIndex(nodes, to, afterIndex: depIndex);
    if (arrIndex < 0 || arrIndex <= depIndex) return null;

    final TripRouteNode fromNode = nodes[depIndex];
    final TripRouteNode toNode = nodes[arrIndex];
    final int segmentPrice = (toNode.priceFromDeparture - fromNode.priceFromDeparture).clamp(0, 1 << 30);

    return TripSegmentModel(
      departureIndex: depIndex,
      arrivalIndex: arrIndex,
      departureNode: fromNode,
      arrivalNode: toNode,
      segmentPrice: segmentPrice,
    );
  }

  int _findNodeIndex(List<TripRouteNode> nodes, String query, {int afterIndex = -1}) {
    for (int i = 0; i < nodes.length; i++) {
      if (i <= afterIndex) continue;
      if (_matchesAddressQuery(query, nodes[i].address)) return i;
    }
    return -1;
  }

  List<String> _addressTokens(String address) {
    final List<String> out = <String>[];
    final String first = _normalize(_cityToken(address));
    if (first.isNotEmpty && !out.contains(first)) out.add(first);
    for (final String part in address.split(',')) {
      final String token = _normalize(part);
      if (token.isNotEmpty && !out.contains(token)) out.add(token);
    }
    return out;
  }

  bool _matchesAddressQuery(String queryAddress, String candidateAddress) {
    final List<String> queryTokens = _addressTokens(queryAddress);
    final List<String> candidateTokens = _addressTokens(candidateAddress);
    if (queryTokens.isEmpty) return true;
    if (candidateTokens.isEmpty) return false;

    for (final String q in queryTokens) {
      for (final String c in candidateTokens) {
        if (_similarToken(c, q)) return true;
      }
    }
    return false;
  }

  bool _similarToken(String a, String b) {
    final String left = _normalizeLoose(a);
    final String right = _normalizeLoose(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (_isGenericGeoToken(left) || _isGenericGeoToken(right)) return false;

    if (left == right) return true;

    if (left.length >= 4 && right.length >= 4) {
      if (left.startsWith(right) || right.startsWith(left)) return true;
    }

    final Set<String> leftWords = left.split(' ').where((w) => w.length >= 4).toSet();
    final Set<String> rightWords = right.split(' ').where((w) => w.length >= 4).toSet();
    if (leftWords.isNotEmpty && rightWords.isNotEmpty) {
      for (final String lw in leftWords) {
        if (rightWords.contains(lw)) return true;
      }
    }
    return false;
  }

  String _cityToken(String address) => (address.split(',').first).trim();

  String _normalize(String value) {
    String s = value.toLowerCase().trim();
    const Map<String, String> map = <String, String>{
      'a': '\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5',
      'c': '\u00E7',
      'e': '\u00E8\u00E9\u00EA\u00EB',
      'i': '\u00EC\u00ED\u00EE\u00EF',
      'n': '\u00F1',
      'o': '\u00F2\u00F3\u00F4\u00F5\u00F6',
      'u': '\u00F9\u00FA\u00FB\u00FC',
      'y': '\u00FD\u00FF',
    };
    map.forEach((ascii, chars) {
      for (final String ch in chars.split('')) {
        s = s.replaceAll(ch, ascii);
      }
    });
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeLoose(String value) {
    return value
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isGenericGeoToken(String value) {
    final String v = _normalizeLoose(value);
    return v.isEmpty ||
        v == 'ci' ||
        v == 'cote d ivoire' ||
        v == 'cote divoire' ||
        v == 'ivory coast';
  }
}

class ComputeSegmentFareUseCase {
  const ComputeSegmentFareUseCase();

  int call(TripSegmentModel segment, int seats) {
    final int safeSeats = seats < 1 ? 1 : seats;
    return segment.segmentPrice * safeSeats;
  }
}

class ComputeSegmentArrivalTimeUseCase {
  const ComputeSegmentArrivalTimeUseCase();

  Future<String?> call({
    required TripSegmentModel segment,
  }) async {
    if (segment.departureNode.kind != 'stop' || segment.arrivalNode.kind != 'stop') return null;
    final double? depLat = segment.departureNode.lat;
    final double? depLng = segment.departureNode.lng;
    final double? arrLat = segment.arrivalNode.lat;
    final double? arrLng = segment.arrivalNode.lng;
    if (depLat == null || depLng == null || arrLat == null || arrLng == null) return null;
    if (RuntimeAppConfig.googleMapsApiKey.trim().isEmpty) return null;

    final int? durationMin = await _fetchDirectionsMinutes(
      originLat: depLat,
      originLng: depLng,
      destinationLat: arrLat,
      destinationLng: arrLng,
    );
    if (durationMin == null || durationMin <= 0) return null;
    return _addMinutesToTime(segment.departureNode.time, durationMin);
  }

  Future<int?> _fetchDirectionsMinutes({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$originLat,$originLng',
        'destination': '$destinationLat,$destinationLng',
        'mode': 'driving',
        'departure_time': '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
        'traffic_model': 'best_guess',
        'key': RuntimeAppConfig.googleMapsApiKey,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();
      if (status != 'OK') return null;

      final List<dynamic> routes = (json['routes'] as List<dynamic>? ?? <dynamic>[]);
      if (routes.isEmpty) return null;
      final Map<String, dynamic>? route0 = routes.first as Map<String, dynamic>?;
      final List<dynamic> legs = (route0?['legs'] as List<dynamic>? ?? <dynamic>[]);
      if (legs.isEmpty) return null;
      final Map<String, dynamic>? leg0 = legs.first as Map<String, dynamic>?;
      final Map<String, dynamic>? durationTraffic = leg0?['duration_in_traffic'] as Map<String, dynamic>?;
      final Map<String, dynamic>? duration = leg0?['duration'] as Map<String, dynamic>?;
      final int totalSeconds =
          ((durationTraffic?['value'] as num?) ?? (duration?['value'] as num?) ?? 0).toInt();
      if (totalSeconds <= 0) return null;
      return (totalSeconds / 60).round();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _addMinutesToTime(String hhmm, int minutesToAdd) {
    final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (match == null) return null;
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    final DateTime base = DateTime(2000, 1, 1, hour, minute);
    final DateTime next = base.add(Duration(minutes: minutesToAdd));
    final String h = next.hour.toString().padLeft(2, '0');
    final String m = next.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class TripFrequencyLabelMapper {
  const TripFrequencyLabelMapper();

  String label(String frequency) {
    switch (frequency.trim()) {
      case 'daily':
        return 'Quotidien';
      case 'weekly':
        return 'Hebdo';
      case 'monthly':
        return 'Mensuel';
      case 'none':
      default:
        return 'Ponctuel';
    }
  }
}
