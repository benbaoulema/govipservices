import 'package:cloud_firestore/cloud_firestore.dart';

class VoyageBookingTraveler {
  const VoyageBookingTraveler({
    required this.name,
    required this.contact,
  });

  final String name;
  final String contact;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'contact': contact,
      };

  factory VoyageBookingTraveler.fromMap(Map<String, dynamic> map) {
    return VoyageBookingTraveler(
      name: (map['name'] as String? ?? '').trim(),
      contact: (map['contact'] as String? ?? '').trim(),
    );
  }
}

class CreateVoyageBookingInput {
  const CreateVoyageBookingInput({
    required this.tripId,
    required this.requestedSeats,
    required this.requesterName,
    required this.requesterContact,
    required this.segmentFrom,
    required this.segmentTo,
    required this.segmentPrice,
    required this.travelers,
    this.requesterUid,
    this.requesterTrackNum,
    this.requesterEmail,
    this.idempotencyKey,
    this.effectiveDepartureDate,
    this.comfortOptions = const <String>[],
    this.appliedRewardIds = const <String>[],
    this.studentDiscount = 0,
    this.checkoutDiscount = 0,
  });

  final String tripId;
  final int requestedSeats;
  final String? requesterUid;
  final String? requesterTrackNum;
  final String requesterName;
  final String requesterContact;
  final String? requesterEmail;
  final String? idempotencyKey;
  final String? effectiveDepartureDate;
  final List<String> comfortOptions;
  /// IDs des récompenses appliquées. Le backend met à jour remainingValue.
  final List<String> appliedRewardIds;
  /// Remise étudiante transiente (non persistée en user_rewards).
  final int studentDiscount;
  /// Remise carte à gratter checkout (non persistée en user_rewards).
  final int checkoutDiscount;
  final String segmentFrom;
  final String segmentTo;
  final int segmentPrice;
  final List<VoyageBookingTraveler> travelers;
}

class VoyageBookingDocument {
  const VoyageBookingDocument({
    required this.id,
    required this.trackNum,
    required this.tripId,
    required this.tripTrackNum,
    required this.tripOwnerUid,
    required this.tripOwnerTrackNum,
    required this.tripCurrency,
    required this.tripDepartureDate,
    required this.tripDepartureTime,
    required this.tripFrequency,
    required this.tripDeparturePlace,
    required this.tripArrivalEstimatedTime,
    required this.tripArrivalPlace,
    required this.tripDriverName,
    required this.tripVehicleModel,
    required this.tripContactPhone,
    required this.tripIntermediateStops,
    required this.requestedSeats,
    required this.requesterUid,
    required this.requesterTrackNum,
    required this.requesterName,
    required this.requesterContact,
    required this.requesterEmail,
    required this.segmentFrom,
    required this.segmentTo,
    required this.segmentPrice,
    required this.totalPrice,
    required this.travelers,
    required this.unreadForDriver,
    required this.unreadForPassenger,
    required this.status,
    this.comfortOptions = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String trackNum;
  final String tripId;
  final String tripTrackNum;
  final String tripOwnerUid;
  final String tripOwnerTrackNum;
  final String tripCurrency;
  final String tripDepartureDate;
  final String tripDepartureTime;
  final String tripFrequency;
  final String tripDeparturePlace;
  final String tripArrivalEstimatedTime;
  final String tripArrivalPlace;
  final String tripDriverName;
  final String tripVehicleModel;
  final String tripContactPhone;
  final List<Map<String, dynamic>> tripIntermediateStops;
  final int requestedSeats;
  final String requesterUid;
  final String requesterTrackNum;
  final String requesterName;
  final String requesterContact;
  final String requesterEmail;
  final String segmentFrom;
  final String segmentTo;
  final int segmentPrice;
  final int totalPrice;
  final List<VoyageBookingTraveler> travelers;
  final int unreadForDriver;
  final int unreadForPassenger;
  final String status;
  final List<String> comfortOptions;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'trackNum': trackNum,
      'tripId': tripId,
      'tripTrackNum': tripTrackNum,
      'tripOwnerUid': tripOwnerUid,
      'tripOwnerTrackNum': tripOwnerTrackNum,
      'tripCurrency': tripCurrency,
      'tripDepartureDate': tripDepartureDate,
      'tripDepartureTime': tripDepartureTime,
      'tripFrequency': tripFrequency,
      'tripDeparturePlace': tripDeparturePlace,
      'tripArrivalEstimatedTime': tripArrivalEstimatedTime,
      'tripArrivalPlace': tripArrivalPlace,
      'tripDriverName': tripDriverName,
      'tripVehicleModel': tripVehicleModel,
      'tripContactPhone': tripContactPhone,
      'tripIntermediateStops': tripIntermediateStops,
      'requestedSeats': requestedSeats,
      'requesterUid': requesterUid,
      'requesterTrackNum': requesterTrackNum,
      'requesterName': requesterName,
      'requesterContact': requesterContact,
      'requesterEmail': requesterEmail,
      'segmentFrom': segmentFrom,
      'segmentTo': segmentTo,
      'segmentPrice': segmentPrice,
      'totalPrice': totalPrice,
      'travelers': travelers.map((t) => t.toMap()).toList(growable: false),
      'unreadForDriver': unreadForDriver,
      'unreadForPassenger': unreadForPassenger,
      'status': status,
      'comfortOptions': comfortOptions,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory VoyageBookingDocument.fromMap(String id, Map<String, dynamic> map) {
    final List<dynamic> rawTravelers = map['travelers'] as List<dynamic>? ?? const <dynamic>[];
    return VoyageBookingDocument(
      id: id,
      trackNum: (map['trackNum'] as String? ?? '').trim(),
      tripId: (map['tripId'] as String? ?? '').trim(),
      tripTrackNum: (map['tripTrackNum'] as String? ?? '').trim(),
      tripOwnerUid: (map['tripOwnerUid'] as String? ?? '').trim(),
      tripOwnerTrackNum: (map['tripOwnerTrackNum'] as String? ?? '').trim(),
      tripCurrency: (map['tripCurrency'] as String? ?? '').trim(),
      tripDepartureDate: (map['tripDepartureDate'] as String? ?? '').trim(),
      tripDepartureTime: (map['tripDepartureTime'] as String? ?? '').trim(),
      tripFrequency: (map['tripFrequency'] as String? ?? 'none').trim(),
      tripDeparturePlace: (map['tripDeparturePlace'] as String? ?? '').trim(),
      tripArrivalEstimatedTime: (map['tripArrivalEstimatedTime'] as String? ?? '').trim(),
      tripArrivalPlace: (map['tripArrivalPlace'] as String? ?? '').trim(),
      tripDriverName: (map['tripDriverName'] as String? ?? '').trim(),
      tripVehicleModel: (map['tripVehicleModel'] as String? ?? '').trim(),
      tripContactPhone: (map['tripContactPhone'] as String? ?? '').trim(),
      tripIntermediateStops: (map['tripIntermediateStops'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false),
      requestedSeats: (map['requestedSeats'] as num? ?? 0).toInt(),
      requesterUid: (map['requesterUid'] as String? ?? '').trim(),
      requesterTrackNum: (map['requesterTrackNum'] as String? ?? '').trim(),
      requesterName: (map['requesterName'] as String? ?? '').trim(),
      requesterContact: (map['requesterContact'] as String? ?? '').trim(),
      requesterEmail: (map['requesterEmail'] as String? ?? '').trim(),
      segmentFrom: (map['segmentFrom'] as String? ?? '').trim(),
      segmentTo: (map['segmentTo'] as String? ?? '').trim(),
      segmentPrice: (map['segmentPrice'] as num? ?? 0).toInt(),
      totalPrice: (map['totalPrice'] as num? ?? 0).toInt(),
      travelers: rawTravelers
          .whereType<Map>()
          .map((e) => VoyageBookingTraveler.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      unreadForDriver: (map['unreadForDriver'] as num? ?? 0).toInt(),
      unreadForPassenger: (map['unreadForPassenger'] as num? ?? 0).toInt(),
      status: (map['status'] as String? ?? 'pending').trim(),
      comfortOptions: (map['comfortOptions'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      createdAt: map['createdAt'] as Timestamp?,
      updatedAt: map['updatedAt'] as Timestamp?,
    );
  }
}
