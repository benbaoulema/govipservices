class PublishedTripResult {
  const PublishedTripResult({
    required this.id,
    required this.trackNum,
    this.wasCreated = true,
    this.alertCount = 0,
  });

  final String id;
  final String trackNum;
  final bool wasCreated;
  final int alertCount;
}

abstract class TravelService {
  Future<PublishedTripResult> addTrip(Map<String, dynamic> payload);
  Future<void> bookTrip();
  Future<void> loadMyTrips();
  Future<void> loadMessages();
}
