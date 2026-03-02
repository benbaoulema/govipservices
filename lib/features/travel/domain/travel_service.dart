class PublishedTripResult {
  const PublishedTripResult({
    required this.id,
    required this.trackNum,
    this.wasCreated = true,
  });

  final String id;
  final String trackNum;
  final bool wasCreated;
}

abstract class TravelService {
  Future<PublishedTripResult> addTrip(Map<String, dynamic> payload);
  Future<void> bookTrip();
  Future<void> loadMyTrips();
  Future<void> loadMessages();
}
