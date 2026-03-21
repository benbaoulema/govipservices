import 'dart:io';

import 'package:flutter/services.dart';

class DeliveryLiveActivityService {
  DeliveryLiveActivityService._();

  static final DeliveryLiveActivityService instance =
      DeliveryLiveActivityService._();

  static const MethodChannel _channel = MethodChannel(
    'govipservices/live_activities',
  );

  Future<void> show({
    required String requestId,
    required String trackNum,
    required String role,
    required String status,
    required String title,
    required String body,
    required String pickupAddress,
    required String deliveryAddress,
    String? etaText,
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('startOrUpdate', <String, dynamic>{
        'requestId': requestId,
        'trackNum': trackNum,
        'role': role,
        'status': status,
        'title': title,
        'body': body,
        'pickupAddress': pickupAddress,
        'deliveryAddress': deliveryAddress,
        'etaText': etaText ?? '',
      });
    } on PlatformException {
      // Keep the Flutter flow resilient if Live Activities are unavailable.
    }
  }

  Future<void> cancelAll() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('endAll');
    } on PlatformException {
      // Ignore unsupported/device-specific failures.
    }
  }
}
