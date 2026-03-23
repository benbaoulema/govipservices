class ParcelServiceMatch {
  const ParcelServiceMatch({
    required this.serviceId,
    required this.ownerUid,
    required this.title,
    required this.contactName,
    required this.contactPhone,
    required this.price,
    required this.currency,
    required this.priceSource,
    required this.isZoneCovered,
    required this.distanceToPickupMeters,
    required this.priorityRank,
    required this.vehicleTypeId,
    required this.vehicleLabel,
    this.ownerCity,
  });

  final String serviceId;
  final String ownerUid;
  final String title;
  final String contactName;
  final String contactPhone;
  final double price;
  final String currency;
  final String priceSource;
  final bool isZoneCovered;
  final double distanceToPickupMeters;
  final int priorityRank;
  final String vehicleTypeId;
  final String vehicleLabel;
  /// Ville actuelle du livreur (issue du géocodage inverse lors de la mise en ligne).
  /// Non null uniquement pour les rank 2 (zone couverte mais livreur loin).
  final String? ownerCity;

  bool get isNearby => priorityRank == 1 || priorityRank == 3;
}
