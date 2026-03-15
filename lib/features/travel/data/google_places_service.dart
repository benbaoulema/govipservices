import 'dart:convert';
import 'dart:io';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

class PlaceDetailsResult {
  const PlaceDetailsResult({
    required this.placeId,
    required this.address,
    this.lat,
    this.lng,
  });

  final String placeId;
  final String address;
  final double? lat;
  final double? lng;
}

class GooglePlacesAutocompleteService {
  GooglePlacesAutocompleteService({
    required this.apiKey,
    this.language = 'fr',
  });

  final String apiKey;
  final String language;

  Future<List<PlaceSuggestion>> getSuggestions({
    required String input,
    required String sessionToken,
    List<String> countries = const <String>['ci', 'fr'],
    String? types = 'geocode',
  }) async {
    if (apiKey.isEmpty || input.trim().isEmpty) {
      return const <PlaceSuggestion>[];
    }

    final String components = countries.map((country) => 'country:$country').join('|');
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': input.trim(),
        'key': apiKey,
        'language': language,
        'sessiontoken': sessionToken,
        if (types != null && types.trim().isNotEmpty) 'types': types.trim(),
        if (components.isNotEmpty) 'components': components,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String payload = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json = jsonDecode(payload) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();

      if (status == 'OK') {
        final List<dynamic> predictions = (json['predictions'] as List<dynamic>? ?? <dynamic>[]);
        return predictions
            .map((item) {
              final Map<String, dynamic> value = item as Map<String, dynamic>;
              final String placeId = value['place_id'] as String? ?? '';
              final String description = value['description'] as String? ?? '';
              if (placeId.isEmpty || description.isEmpty) return null;
              return PlaceSuggestion(placeId: placeId, description: description);
            })
            .whereType<PlaceSuggestion>()
            .toList(growable: false);
      }

      if (status == 'ZERO_RESULTS') {
        return const <PlaceSuggestion>[];
      }

      final String errorMessage = json['error_message'] as String? ?? 'Google Places request failed.';
      throw HttpException('$status: $errorMessage');
    } finally {
      client.close(force: true);
    }
  }

  Future<PlaceDetailsResult?> getPlaceDetails({
    required String placeId,
    required String sessionToken,
  }) async {
    if (apiKey.isEmpty || placeId.trim().isEmpty) {
      return null;
    }

    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId.trim(),
        'key': apiKey,
        'language': language,
        'fields': 'place_id,formatted_address,geometry/location,name',
        'sessiontoken': sessionToken,
      },
    );

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String payload = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> json = jsonDecode(payload) as Map<String, dynamic>;
      final String status = (json['status'] as String? ?? '').toUpperCase();

      if (status != 'OK') {
        if (status == 'ZERO_RESULTS' || status == 'NOT_FOUND') {
          return null;
        }
        final String errorMessage = json['error_message'] as String? ?? 'Google Place Details request failed.';
        throw HttpException('$status: $errorMessage');
      }

      final Map<String, dynamic>? result = json['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final String resolvedPlaceId = result['place_id'] as String? ?? placeId;
      final String address =
          (result['formatted_address'] as String?) ??
          (result['name'] as String?) ??
          '';
      final Map<String, dynamic>? geometry = result['geometry'] as Map<String, dynamic>?;
      final Map<String, dynamic>? location = geometry?['location'] as Map<String, dynamic>?;
      final double? lat = (location?['lat'] as num?)?.toDouble();
      final double? lng = (location?['lng'] as num?)?.toDouble();

      return PlaceDetailsResult(
        placeId: resolvedPlaceId,
        address: address,
        lat: lat,
        lng: lng,
      );
    } finally {
      client.close(force: true);
    }
  }
}
