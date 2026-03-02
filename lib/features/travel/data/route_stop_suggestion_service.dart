import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:govipservices/features/travel/data/ci_route_hubs.dart';

class SuggestedRouteStop {
  const SuggestedRouteStop({
    required this.id,
    required this.address,
    required this.etaMinutesFromDeparture,
    required this.priceFromDeparture,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String address;
  final int etaMinutesFromDeparture;
  final double priceFromDeparture;
  final double lat;
  final double lng;
}

class RoutePathPoint {
  const RoutePathPoint({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;
}

class RouteStopSuggestionResult {
  const RouteStopSuggestionResult({
    required this.totalMinutes,
    required this.stops,
    required this.pathPoints,
    required this.usedDirectionsApi,
    this.directionsStatus,
    this.directionsErrorMessage,
  });

  final int totalMinutes;
  final List<SuggestedRouteStop> stops;
  final List<RoutePathPoint> pathPoints;
  final bool usedDirectionsApi;
  final String? directionsStatus;
  final String? directionsErrorMessage;
}

class RouteStopSuggestionService {
  const RouteStopSuggestionService();

  Future<RouteStopSuggestionResult> suggest({
    required double departureLat,
    required double departureLng,
    required double arrivalLat,
    required double arrivalLng,
    required DateTime departureDateTime,
    required double pricePerSeat,
    required String currency,
    required String googleMapsApiKey,
    List<RouteHub>? hubs,
  }) async {
    final List<RouteHub> hubsList = hubs ?? ciRouteHubs;
    final double totalDistanceKm = _haversineKm(
      departureLat,
      departureLng,
      arrivalLat,
      arrivalLng,
    );
    if (totalDistanceKm < 2.0) {
      return const RouteStopSuggestionResult(
        totalMinutes: 0,
        stops: <SuggestedRouteStop>[],
        pathPoints: <RoutePathPoint>[],
        usedDirectionsApi: false,
        directionsStatus: 'SKIPPED_SHORT_TRIP',
      );
    }

    final _DirectionsData directionsData = await _fetchDirectionsData(
      departureLat: departureLat,
      departureLng: departureLng,
      arrivalLat: arrivalLat,
      arrivalLng: arrivalLng,
      departureDateTime: departureDateTime,
      apiKey: googleMapsApiKey,
    );

    final int fallbackMinutes = (((totalDistanceKm / 55.0) * 60).round().clamp(20, 16 * 60)) as int;
    final int totalMinutes = directionsData.totalMinutes > 0 ? directionsData.totalMinutes : fallbackMinutes;
    final bool usedDirections = directionsData.totalMinutes > 0;
    final int totalTrafficSeconds = totalMinutes * 60;
    final List<_RouteNode> routeNodes = directionsData.nodes.length >= 2
        ? directionsData.nodes
        : <_RouteNode>[
            _RouteNode(lat: departureLat, lng: departureLng, cumulativeTrafficSeconds: 0),
            _RouteNode(
              lat: arrivalLat,
              lng: arrivalLng,
              cumulativeTrafficSeconds: totalTrafficSeconds,
            ),
          ];
    final bool isLongTrip = totalMinutes >= 150 || totalDistanceKm >= 180;

    final _Bounds expandedBounds = _expandBounds(
      _getBounds(<_LatLng>[
        _LatLng(lat: departureLat, lng: departureLng),
        _LatLng(lat: arrivalLat, lng: arrivalLng),
      ]),
      latPad: 1.2,
      lngPad: 1.5,
    );
    final List<RouteHub> boundedHubs =
        hubsList.where((RouteHub hub) => _inBounds(hub, expandedBounds)).toList();
    final List<RouteHub> candidateHubs = boundedHubs.isEmpty ? hubsList : boundedHubs;

    List<_CandidateStop> candidates = _collectCandidates(
      hubs: candidateHubs,
      departureLat: departureLat,
      departureLng: departureLng,
      arrivalLat: arrivalLat,
      arrivalLng: arrivalLng,
      totalDistanceKm: totalDistanceKm,
      routeNodes: routeNodes,
      totalTrafficSeconds: totalTrafficSeconds,
      strict: true,
    );
    if (candidates.isEmpty) {
      candidates = _collectCandidates(
        hubs: hubsList,
        departureLat: departureLat,
        departureLng: departureLng,
        arrivalLat: arrivalLat,
        arrivalLng: arrivalLng,
        totalDistanceKm: totalDistanceKm,
        routeNodes: routeNodes,
        totalTrafficSeconds: totalTrafficSeconds,
        strict: false,
      );
    }

    candidates.sort((a, b) => a.score.compareTo(b.score));
    final List<_CandidateStop> filteredByEta = candidates
        .where((c) {
          final int eta = c.etaMinutesFromDeparture;
          return eta > 3 && eta < totalMinutes - 3;
        })
        .toList(growable: false);

    final List<_CandidateStop> deduped = <_CandidateStop>[];
    for (final _CandidateStop candidate in filteredByEta) {
      final int eta = candidate.etaMinutesFromDeparture;
      _CandidateStop? previous;
      for (final _CandidateStop existing in deduped) {
        final int dedupEta = existing.etaMinutesFromDeparture;
        if ((dedupEta - eta).abs() < 8) {
          previous = existing;
          break;
        }
      }
      if (previous == null) {
        deduped.add(candidate);
        continue;
      }
      if (_candidateScore(candidate, isLongTrip) < _candidateScore(previous, isLongTrip)) {
        final int previousIndex = deduped.indexOf(previous);
        deduped[previousIndex] = candidate;
      }
    }

    const int maxSuggestions = 12;
    final List<List<_CandidateStop>> buckets = List<List<_CandidateStop>>.generate(
      maxSuggestions,
      (_) => <_CandidateStop>[],
    );
    for (final _CandidateStop candidate in deduped) {
      final int bucketIndex = (((candidate.etaMinutesFromDeparture / math.max(1, totalMinutes)) * maxSuggestions)
              .floor()
              .clamp(0, maxSuggestions - 1)) as int;
      buckets[bucketIndex].add(candidate);
    }

    final List<_CandidateStop> distributed = <_CandidateStop>[];
    for (final List<_CandidateStop> bucket in buckets) {
      if (bucket.isNotEmpty) {
        distributed.add(bucket.first);
      }
    }

    if (distributed.length < maxSuggestions) {
      for (final _CandidateStop candidate in deduped) {
        if (distributed.any((d) => d.hub.id == candidate.hub.id)) continue;
        distributed.add(candidate);
        if (distributed.length >= maxSuggestions) break;
      }
    }

    distributed.sort((a, b) => a.progress.compareTo(b.progress));
    final List<_CandidateStop> selected = distributed.take(maxSuggestions).toList(growable: false);

    final List<SuggestedRouteStop> stops = selected
        .map((candidate) {
          final int eta = (candidate.etaMinutesFromDeparture.clamp(1, totalMinutes - 1)) as int;
          final double priceRaw = (pricePerSeat * candidate.progress) * 0.8;
          return SuggestedRouteStop(
            id: candidate.hub.id,
            address: candidate.hub.address,
            etaMinutesFromDeparture: eta,
            priceFromDeparture: _normalizePrice(priceRaw, currency),
            lat: candidate.hub.lat,
            lng: candidate.hub.lng,
          );
        })
        .toList(growable: false);

    return RouteStopSuggestionResult(
      totalMinutes: totalMinutes,
      stops: stops,
      pathPoints: routeNodes
          .map((node) => RoutePathPoint(lat: node.lat, lng: node.lng))
          .toList(growable: false),
      usedDirectionsApi: usedDirections,
      directionsStatus: directionsData.status,
      directionsErrorMessage: directionsData.errorMessage,
    );
  }

  Future<_DirectionsData> _fetchDirectionsData({
    required double departureLat,
    required double departureLng,
    required double arrivalLat,
    required double arrivalLng,
    required DateTime departureDateTime,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      debugPrint('[stops/service] API key empty');
      return const _DirectionsData(
        totalMinutes: 0,
        nodes: <_RouteNode>[],
        status: 'API_KEY_EMPTY',
      );
    }

    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$departureLat,$departureLng',
        'destination': '$arrivalLat,$arrivalLng',
        'mode': 'driving',
        'departure_time': '${departureDateTime.toUtc().millisecondsSinceEpoch ~/ 1000}',
        'traffic_model': 'best_guess',
        'key': apiKey,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();
      final String? errorMessage = (json['error_message'] as String?)?.trim();
      debugPrint('[stops/service] directions status=$status error=$errorMessage');
      if (status != 'OK') {
        return _DirectionsData(
          totalMinutes: 0,
          nodes: const <_RouteNode>[],
          status: status.isEmpty ? 'UNKNOWN' : status,
          errorMessage: errorMessage,
        );
      }

      final List<dynamic> routes = (json['routes'] as List<dynamic>? ?? <dynamic>[]);
      if (routes.isEmpty) {
        debugPrint('[stops/service] directions: no routes');
        return const _DirectionsData(
          totalMinutes: 0,
          nodes: <_RouteNode>[],
          status: 'NO_ROUTES',
        );
      }
      final Map<String, dynamic>? route0 = routes.first as Map<String, dynamic>?;
      final List<dynamic> legs = (route0?['legs'] as List<dynamic>? ?? <dynamic>[]);
      if (legs.isEmpty) {
        debugPrint('[stops/service] directions: no legs');
        return const _DirectionsData(
          totalMinutes: 0,
          nodes: <_RouteNode>[],
          status: 'NO_LEGS',
        );
      }
      final Map<String, dynamic>? leg0 = legs.first as Map<String, dynamic>?;
      final Map<String, dynamic>? durationTraffic = leg0?['duration_in_traffic'] as Map<String, dynamic>?;
      final Map<String, dynamic>? duration = leg0?['duration'] as Map<String, dynamic>?;
      final int totalTrafficSeconds =
          ((durationTraffic?['value'] as num?) ?? (duration?['value'] as num?) ?? 0).toInt();
      if (totalTrafficSeconds <= 0) {
        debugPrint('[stops/service] directions: no duration');
        return const _DirectionsData(
          totalMinutes: 0,
          nodes: <_RouteNode>[],
          status: 'NO_DURATION',
        );
      }
      final int totalBaseSeconds = ((duration?['value'] as num?) ?? totalTrafficSeconds).toInt();
      final List<_RouteNode> nodes = _buildRouteNodesForLeg(
        leg0: leg0,
        totalBaseSeconds: totalBaseSeconds <= 0 ? totalTrafficSeconds : totalBaseSeconds,
        totalTrafficSeconds: totalTrafficSeconds,
      );
      return _DirectionsData(
        totalMinutes: (totalTrafficSeconds / 60).round(),
        nodes: nodes,
        status: status,
        errorMessage: errorMessage,
      );
    } catch (error) {
      debugPrint('[stops/service] directions exception: $error');
      return _DirectionsData(
        totalMinutes: 0,
        nodes: const <_RouteNode>[],
        status: 'HTTP_EXCEPTION',
        errorMessage: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  double _normalizePrice(double value, String currency) {
    if (value <= 0) return 0;
    if (currency.toUpperCase() == 'XOF') {
      return ((((value / 500).floor() * 500).toDouble()).clamp(0, 1000000) as num).toDouble();
    }
    return value.roundToDouble();
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const double earthKm = 6371.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLng = _degToRad(lng2 - lng1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthKm * c;
  }

  double _degToRad(double value) => value * (math.pi / 180.0);

  _XY _toXY(double lat, double lng, double refLat, double refLng) {
    const double kmPerDegLat = 110.574;
    final double kmPerDegLng = 111.320 * math.cos(_degToRad(refLat));
    return _XY(
      x: (lng - refLng) * kmPerDegLng,
      y: (lat - refLat) * kmPerDegLat,
    );
  }

  _Projection _projectOnSegment(_XY a, _XY b, _XY p) {
    final double abx = b.x - a.x;
    final double aby = b.y - a.y;
    final double apx = p.x - a.x;
    final double apy = p.y - a.y;
    final double ab2 = (abx * abx) + (aby * aby);
    if (ab2 <= 0.000001) {
      return _Projection(t: 0, distanceKm: math.sqrt(apx * apx + apy * apy));
    }
    final double tRaw = ((apx * abx) + (apy * aby)) / ab2;
    final double t = (tRaw.clamp(0.0, 1.0) as num).toDouble();
    final double cx = a.x + (abx * t);
    final double cy = a.y + (aby * t);
    final double dx = p.x - cx;
    final double dy = p.y - cy;
    final double d = math.sqrt((dx * dx) + (dy * dy));
    return _Projection(t: t, distanceKm: d);
  }

  _Bounds _getBounds(List<_LatLng> points) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final _LatLng p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    return _Bounds(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  _Bounds _expandBounds(_Bounds b, {required double latPad, required double lngPad}) {
    return _Bounds(
      minLat: b.minLat - latPad,
      maxLat: b.maxLat + latPad,
      minLng: b.minLng - lngPad,
      maxLng: b.maxLng + lngPad,
    );
  }

  bool _inBounds(RouteHub hub, _Bounds b) {
    return hub.lat >= b.minLat &&
        hub.lat <= b.maxLat &&
        hub.lng >= b.minLng &&
        hub.lng <= b.maxLng;
  }

  double _candidateScore(_CandidateStop candidate, bool isLongTrip) {
    final double priorityBoost = isLongTrip && candidate.hub.priority == 1 ? -0.5 : 0;
    return ((candidate.hub.priority + priorityBoost) * 100) +
        (candidate.lineDistanceKm * 2) +
        (candidate.kindRank * 5);
  }

  List<_CandidateStop> _collectCandidates({
    required List<RouteHub> hubs,
    required double departureLat,
    required double departureLng,
    required double arrivalLat,
    required double arrivalLng,
    required double totalDistanceKm,
    required List<_RouteNode> routeNodes,
    required int totalTrafficSeconds,
    required bool strict,
  }) {
    final List<_CandidateStop> out = <_CandidateStop>[];
    final double maxCorridor = strict
        ? math.min(30, math.max(8, totalDistanceKm * 0.12))
        : math.min(70, math.max(20, totalDistanceKm * 0.35));

    for (final RouteHub hub in hubs) {
      final _RouteProjection projection = _bestProjectionOnRoute(
        hubLat: hub.lat,
        hubLng: hub.lng,
        routeNodes: routeNodes,
        totalTrafficSeconds: totalTrafficSeconds,
        refLat: departureLat,
        refLng: departureLng,
      );
      final double progress = projection.progress;
      final double lateralDistanceKm = projection.lineDistanceKm;
      final double distToStart = _haversineKm(hub.lat, hub.lng, departureLat, departureLng);
      final double distToEnd = _haversineKm(hub.lat, hub.lng, arrivalLat, arrivalLng);

      if (strict) {
        if (progress <= 0.05 || progress >= 0.95) continue;
        if (distToStart <= 5 || distToEnd <= 5) continue;
      } else {
        if (progress <= 0.02 || progress >= 0.98) continue;
      }
      if (lateralDistanceKm > maxCorridor) continue;

      final int kindRank = hub.kind == 'city' ? 1 : (hub.kind == 'junction' ? 2 : 3);
      final double score = lateralDistanceKm + (hub.priority - 1) * 1.3 + kindRank * 0.2;
      out.add(
        _CandidateStop(
          hub: hub,
          score: score,
          progress: progress,
          etaMinutesFromDeparture: projection.etaMinutesFromDeparture,
          lineDistanceKm: lateralDistanceKm,
          kindRank: kindRank,
        ),
      );
    }
    return out;
  }

  _RouteProjection _bestProjectionOnRoute({
    required double hubLat,
    required double hubLng,
    required List<_RouteNode> routeNodes,
    required int totalTrafficSeconds,
    required double refLat,
    required double refLng,
  }) {
    if (routeNodes.length < 2) {
      return const _RouteProjection(
        lineDistanceKm: 9999,
        progress: 0,
        etaMinutesFromDeparture: 0,
      );
    }
    double bestDistance = double.infinity;
    double bestProgress = 0;
    int bestEtaMinutes = 0;
    final _XY p = _toXY(hubLat, hubLng, refLat, refLng);

    for (int i = 0; i < routeNodes.length - 1; i++) {
      final _RouteNode a = routeNodes[i];
      final _RouteNode b = routeNodes[i + 1];
      final _XY ax = _toXY(a.lat, a.lng, refLat, refLng);
      final _XY bx = _toXY(b.lat, b.lng, refLat, refLng);
      final _Projection segProjection = _projectOnSegment(ax, bx, p);
      if (segProjection.distanceKm < bestDistance) {
        final double t = segProjection.t;
        final int trafficSeconds = (a.cumulativeTrafficSeconds +
                ((b.cumulativeTrafficSeconds - a.cumulativeTrafficSeconds) * t))
            .round();
        bestDistance = segProjection.distanceKm;
        bestProgress =
            (((trafficSeconds / math.max(1, totalTrafficSeconds)).clamp(0.0, 1.0)) as num).toDouble();
        bestEtaMinutes = (trafficSeconds / 60).round();
      }
    }

    return _RouteProjection(
      lineDistanceKm: bestDistance,
      progress: bestProgress,
      etaMinutesFromDeparture: bestEtaMinutes,
    );
  }

  List<_RouteNode> _buildRouteNodesForLeg({
    required Map<String, dynamic>? leg0,
    required int totalBaseSeconds,
    required int totalTrafficSeconds,
  }) {
    final List<_RouteNode> nodes = <_RouteNode>[];
    if (leg0 == null) return nodes;

    int cumulativeTrafficSeconds = 0;
    final List<dynamic> steps = (leg0['steps'] as List<dynamic>? ?? <dynamic>[]);
    for (final dynamic stepDynamic in steps) {
      if (stepDynamic is! Map<String, dynamic>) continue;
      final int stepBaseSeconds =
          ((stepDynamic['duration'] as Map<String, dynamic>?)?['value'] as num? ?? 0).toInt();
      final int stepTrafficSeconds = totalBaseSeconds > 0
          ? math.max(1, ((stepBaseSeconds / totalBaseSeconds) * totalTrafficSeconds).round())
          : stepBaseSeconds;

      final String encoded = ((stepDynamic['polyline'] as Map<String, dynamic>?)?['points'] as String? ?? '');
      List<_LatLng> path = _decodePolyline(encoded);
      if (path.isEmpty) {
        final _LatLng? start = _readLatLng(stepDynamic['start_location']);
        final _LatLng? end = _readLatLng(stepDynamic['end_location']);
        if (start != null) path.add(start);
        if (end != null) path.add(end);
      }
      if (path.length < 2) {
        cumulativeTrafficSeconds += stepTrafficSeconds;
        continue;
      }

      double stepDistance = 0;
      for (int i = 0; i < path.length - 1; i++) {
        stepDistance += _haversineKm(path[i].lat, path[i].lng, path[i + 1].lat, path[i + 1].lng);
      }

      double covered = 0;
      for (int i = 0; i < path.length; i++) {
        if (i > 0) {
          covered += _haversineKm(path[i - 1].lat, path[i - 1].lng, path[i].lat, path[i].lng);
        }
        final double ratio = stepDistance > 0 ? covered / stepDistance : (i == path.length - 1 ? 1.0 : 0.0);
        final int nodeTraffic = cumulativeTrafficSeconds + (stepTrafficSeconds * ratio).round();
        final _RouteNode node = _RouteNode(
          lat: path[i].lat,
          lng: path[i].lng,
          cumulativeTrafficSeconds: nodeTraffic,
        );
        if (nodes.isEmpty || nodes.last.lat != node.lat || nodes.last.lng != node.lng) {
          nodes.add(node);
        }
      }
      cumulativeTrafficSeconds += stepTrafficSeconds;
    }

    return nodes;
  }

  _LatLng? _readLatLng(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final num? lat = value['lat'] as num?;
    final num? lng = value['lng'] as num?;
    if (lat == null || lng == null) return null;
    return _LatLng(lat: lat.toDouble(), lng: lng.toDouble());
  }

  List<_LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return <_LatLng>[];
    final List<_LatLng> poly = <_LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(_LatLng(lat: lat / 1e5, lng: lng / 1e5));
    }
    return poly;
  }
}

class _XY {
  const _XY({required this.x, required this.y});
  final double x;
  final double y;
}

class _Projection {
  const _Projection({
    required this.t,
    required this.distanceKm,
  });
  final double t;
  final double distanceKm;
}

class _CandidateStop {
  const _CandidateStop({
    required this.hub,
    required this.score,
    required this.progress,
    required this.etaMinutesFromDeparture,
    required this.lineDistanceKm,
    required this.kindRank,
  });
  final RouteHub hub;
  final double score;
  final double progress;
  final int etaMinutesFromDeparture;
  final double lineDistanceKm;
  final int kindRank;
}

class _LatLng {
  const _LatLng({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

class _Bounds {
  const _Bounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}

class _RouteNode {
  const _RouteNode({
    required this.lat,
    required this.lng,
    required this.cumulativeTrafficSeconds,
  });
  final double lat;
  final double lng;
  final int cumulativeTrafficSeconds;
}

class _RouteProjection {
  const _RouteProjection({
    required this.lineDistanceKm,
    required this.progress,
    required this.etaMinutesFromDeparture,
  });
  final double lineDistanceKm;
  final double progress;
  final int etaMinutesFromDeparture;
}

class _DirectionsData {
  const _DirectionsData({
    required this.totalMinutes,
    required this.nodes,
    required this.status,
    this.errorMessage,
  });
  final int totalMinutes;
  final List<_RouteNode> nodes;
  final String status;
  final String? errorMessage;
}
