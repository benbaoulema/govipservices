import 'dart:convert';
import 'dart:io';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class ParcelRoutePreviewService {
  const ParcelRoutePreviewService({
    required this.apiKey,
  });

  final String apiKey;

  Future<List<LatLng>> fetchRoutePoints({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
  }) async {
    if (apiKey.trim().isEmpty) {
      return <LatLng>[];
    }

    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$pickupLat,$pickupLng',
        'destination': '$deliveryLat,$deliveryLng',
        'mode': 'driving',
        'language': 'fr',
        'region': 'ci',
        'key': apiKey,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();
      if (status != 'OK') {
        return <LatLng>[];
      }

      final List<dynamic> routes =
          (json['routes'] as List<dynamic>? ?? <dynamic>[]);
      if (routes.isEmpty) return <LatLng>[];

      final Map<String, dynamic>? route0 =
          routes.first as Map<String, dynamic>?;
      final String encoded =
          ((route0?['overview_polyline'] as Map<String, dynamic>?)?['points']
                  as String? ??
              '');
      return _decodePolyline(encoded);
    } catch (_) {
      return <LatLng>[];
    } finally {
      client.close(force: true);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return <LatLng>[];

    final List<LatLng> polyline = <LatLng>[];
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

      polyline.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return polyline;
  }
}
