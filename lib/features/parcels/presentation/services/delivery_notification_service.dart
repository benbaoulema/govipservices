import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:govipservices/features/parcels/presentation/services/delivery_live_activity_service.dart';

const String _kChannelId = 'delivery_ongoing';
const int _kNotifId = 8001;

class DeliveryNotificationService {
  DeliveryNotificationService._();

  static final DeliveryNotificationService instance =
      DeliveryNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> showForDriver({
    required String requestId,
    required String status,
    required String trackNum,
    required String pickupAddress,
    required String deliveryAddress,
    String? etaText,
  }) async {
    if (status == 'delivered') {
      await cancel();
      return;
    }

    final String title = _driverTitle(status);
    final String body = _body(title, etaText, trackNum);

    if (Platform.isIOS) {
      await DeliveryLiveActivityService.instance.show(
        requestId: requestId,
        trackNum: trackNum,
        role: 'driver',
        status: status,
        title: title,
        body: body,
        pickupAddress: pickupAddress,
        deliveryAddress: deliveryAddress,
        etaText: etaText,
      );
      return;
    }

    if (!Platform.isAndroid) return;
    await _show(title: title, body: body);
  }

  Future<void> showForSender({
    required String requestId,
    required String status,
    required String trackNum,
    required String pickupAddress,
    required String deliveryAddress,
    String? etaText,
  }) async {
    if (status == 'delivered') {
      await cancel();
      return;
    }

    final String title = _senderTitle(status);
    final String body = _body(title, etaText, trackNum);

    if (Platform.isIOS) {
      await DeliveryLiveActivityService.instance.show(
        requestId: requestId,
        trackNum: trackNum,
        role: 'sender',
        status: status,
        title: title,
        body: body,
        pickupAddress: pickupAddress,
        deliveryAddress: deliveryAddress,
        etaText: etaText,
      );
      return;
    }

    if (!Platform.isAndroid) return;
    await _show(title: title, body: body);
  }

  Future<void> cancel() async {
    if (Platform.isIOS) {
      await DeliveryLiveActivityService.instance.cancelAll();
      return;
    }
    if (!Platform.isAndroid) return;
    await _plugin.cancel(_kNotifId);
  }

  Future<void> _show({required String title, required String body}) async {
    await _plugin.show(
      _kNotifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          'Course en cours',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          onlyAlertOnce: true,
          color: Color(0xFF0F766E),
          icon: '@mipmap/ic_launcher',
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }

  String _body(String title, String? etaText, String trackNum) {
    final StringBuffer buffer = StringBuffer();
    if (trackNum.isNotEmpty) {
      buffer.write('Ref $trackNum');
    }
    if (etaText != null && etaText.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' · ');
      buffer.write(etaText);
    }
    return buffer.isEmpty ? title : buffer.toString();
  }

  String _driverTitle(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'En route vers le colis';
      case 'en_route_to_pickup':
      case 'en_route':
        return 'Direction le point de retrait';
      case 'picked_up':
        return 'Colis recupere · En livraison';
      default:
        return 'Course en cours';
    }
  }

  String _senderTitle(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'Livreur en route';
      case 'en_route_to_pickup':
      case 'en_route':
        return 'Livreur en chemin';
      case 'picked_up':
        return 'Colis recupere · En livraison';
      default:
        return 'Course en cours';
    }
  }
}
