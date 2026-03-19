import 'package:cloud_firestore/cloud_firestore.dart';

class CreateParcelRequestInput {
  const CreateParcelRequestInput({
    required this.serviceId,
    required this.providerUid,
    required this.providerName,
    required this.providerPhone,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterContact,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryAddress,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.price,
    required this.currency,
    required this.priceSource,
    required this.vehicleLabel,
    this.receiverName = '',
    this.receiverContactPhone = '',
  });

  final String serviceId;
  final String providerUid;
  final String providerName;
  final String providerPhone;
  final String requesterUid;
  final String requesterName;
  final String requesterContact;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String deliveryAddress;
  final double deliveryLat;
  final double deliveryLng;
  final double price;
  final String currency;
  final String priceSource;
  final String vehicleLabel;
  final String receiverName;
  final String receiverContactPhone;
}

class ParcelRequestDocument {
  const ParcelRequestDocument({
    required this.id,
    required this.trackNum,
    required this.serviceId,
    required this.providerUid,
    required this.providerName,
    required this.requesterUid,
    required this.requesterName,
    required this.requesterContact,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.price,
    required this.currency,
    required this.vehicleLabel,
    required this.status,
    this.pickupLat = 0,
    this.pickupLng = 0,
    this.deliveryLat = 0,
    this.deliveryLng = 0,
    this.receiverName = '',
    this.receiverContactPhone = '',
    this.createdAt,
    this.courierLat,
    this.courierLng,
  });

  final String id;
  final String trackNum;
  final String serviceId;
  final String providerUid;
  final String providerName;
  final String requesterUid;
  final String requesterName;
  final String requesterContact;
  final String pickupAddress;
  final String deliveryAddress;
  final double price;
  final String currency;
  final String vehicleLabel;
  final String status;
  final double pickupLat;
  final double pickupLng;
  final double deliveryLat;
  final double deliveryLng;
  final String receiverName;
  final String receiverContactPhone;
  final Timestamp? createdAt;
  final double? courierLat;
  final double? courierLng;

  factory ParcelRequestDocument.fromMap(String id, Map<String, dynamic> map) {
    final Map<String, dynamic>? pickupLatLng =
        map['pickupLatLng'] as Map<String, dynamic>?;
    final Map<String, dynamic>? deliveryLatLng =
        map['deliveryLatLng'] as Map<String, dynamic>?;

    return ParcelRequestDocument(
      id: id,
      trackNum: (map['trackNum'] as String? ?? '').trim(),
      serviceId: (map['serviceId'] as String? ?? '').trim(),
      providerUid: (map['providerUid'] as String? ?? '').trim(),
      providerName: (map['providerName'] as String? ?? '').trim(),
      requesterUid: (map['requesterUid'] as String? ?? '').trim(),
      requesterName: (map['requesterName'] as String? ?? '').trim(),
      requesterContact: (map['requesterContact'] as String? ?? '').trim(),
      pickupAddress: (map['pickupCityAddress'] as String? ?? '').trim(),
      deliveryAddress: (map['deliveryAddress'] as String? ?? '').trim(),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] as String? ?? '').trim(),
      vehicleLabel: (map['vehicleLabel'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? '').trim(),
      pickupLat: (pickupLatLng?['lat'] as num?)?.toDouble() ?? 0,
      pickupLng: (pickupLatLng?['lng'] as num?)?.toDouble() ?? 0,
      deliveryLat: (deliveryLatLng?['lat'] as num?)?.toDouble() ?? 0,
      deliveryLng: (deliveryLatLng?['lng'] as num?)?.toDouble() ?? 0,
      receiverName: (map['receiverName'] as String? ?? '').trim(),
      receiverContactPhone:
          (map['receiverContactPhone'] as String? ?? '').trim(),
      createdAt: map['createdAt'] as Timestamp?,
      courierLat: (map['courierLat'] as num?)?.toDouble(),
      courierLng: (map['courierLng'] as num?)?.toDouble(),
    );
  }
}
