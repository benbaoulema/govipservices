enum TripDetailAccessMode {
  traveler,
  owner,
  supportOnly,
}

class TripDetailArgs {
  const TripDetailArgs({
    required this.tripId,
    required this.from,
    required this.to,
    this.effectiveDepartureDate,
    this.accessMode = TripDetailAccessMode.traveler,
  });

  final String tripId;
  final String from;
  final String to;
  final String? effectiveDepartureDate;
  final TripDetailAccessMode accessMode;
}

class TripStopModel {
  const TripStopModel({
    required this.id,
    required this.address,
    required this.estimatedTime,
    required this.priceFromDeparture,
    this.lat,
    this.lng,
    this.bookable = true,
  });

  final String id;
  final String address;
  final String estimatedTime;
  final int priceFromDeparture;
  final double? lat;
  final double? lng;
  final bool bookable;
}

class DriverInfoModel {
  const DriverInfoModel({
    required this.name,
    required this.contactPhone,
  });

  final String name;
  final String contactPhone;
}

class VehicleInfoModel {
  const VehicleInfoModel({
    required this.model,
    required this.photoUrl,
  });

  final String model;
  final String photoUrl;
}

class TripOptionsModel {
  const TripOptionsModel({
    required this.hasLuggageSpace,
    required this.allowsPets,
  });

  final bool hasLuggageSpace;
  final bool allowsPets;
}

class TripDetailModel {
  const TripDetailModel({
    required this.id,
    required this.trackNum,
    required this.ownerUid,
    required this.departurePlace,
    required this.arrivalPlace,
    required this.departureDate,
    required this.departureTime,
    required this.arrivalEstimatedTime,
    required this.tripFrequency,
    required this.pricePerSeat,
    required this.currency,
    required this.seats,
    required this.driver,
    required this.vehicle,
    required this.options,
    required this.intermediateStops,
    required this.status,
    this.isBus = false,
    this.segmentOccupancy = const <String, int>{},
    this.segmentPoints = const <String>[],
  });

  final String id;
  final String trackNum;
  final String ownerUid;
  final String departurePlace;
  final String arrivalPlace;
  final String departureDate;
  final String departureTime;
  final String arrivalEstimatedTime;
  final String tripFrequency;
  final int pricePerSeat;
  final String currency;
  final int seats;
  final DriverInfoModel driver;
  final VehicleInfoModel vehicle;
  final TripOptionsModel options;
  final List<TripStopModel> intermediateStops;
  final String status;
  final bool isBus;
  final Map<String, int> segmentOccupancy;
  final List<String> segmentPoints;
}

class TripRouteNode {
  const TripRouteNode({
    required this.kind,
    required this.address,
    required this.time,
    required this.priceFromDeparture,
    this.lat,
    this.lng,
    this.bookable = true,
  });

  final String kind;
  final String address;
  final String time;
  final int priceFromDeparture;
  final double? lat;
  final double? lng;
  final bool bookable;

  TripRouteNode copyWith({
    String? kind,
    String? address,
    String? time,
    int? priceFromDeparture,
    double? lat,
    double? lng,
    bool? bookable,
  }) {
    return TripRouteNode(
      kind: kind ?? this.kind,
      address: address ?? this.address,
      time: time ?? this.time,
      priceFromDeparture: priceFromDeparture ?? this.priceFromDeparture,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      bookable: bookable ?? this.bookable,
    );
  }
}

class TripSegmentModel {
  const TripSegmentModel({
    required this.departureIndex,
    required this.arrivalIndex,
    required this.departureNode,
    required this.arrivalNode,
    required this.segmentPrice,
  });

  final int departureIndex;
  final int arrivalIndex;
  final TripRouteNode departureNode;
  final TripRouteNode arrivalNode;
  final int segmentPrice;

  TripSegmentModel copyWith({
    int? departureIndex,
    int? arrivalIndex,
    TripRouteNode? departureNode,
    TripRouteNode? arrivalNode,
    int? segmentPrice,
  }) {
    return TripSegmentModel(
      departureIndex: departureIndex ?? this.departureIndex,
      arrivalIndex: arrivalIndex ?? this.arrivalIndex,
      departureNode: departureNode ?? this.departureNode,
      arrivalNode: arrivalNode ?? this.arrivalNode,
      segmentPrice: segmentPrice ?? this.segmentPrice,
    );
  }
}
