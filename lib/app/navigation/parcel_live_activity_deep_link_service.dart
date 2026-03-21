import 'package:flutter/services.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';

class ParcelLiveActivityDeepLinkService {
  ParcelLiveActivityDeepLinkService._();

  static final ParcelLiveActivityDeepLinkService instance =
      ParcelLiveActivityDeepLinkService._();

  static const MethodChannel _channel = MethodChannel(
    'govipservices/deep_links',
  );

  final ParcelRequestService _requestService = ParcelRequestService();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onDeepLink') return;
      final String? link = call.arguments as String?;
      await _handleLink(link);
    });

    final String? initialLink =
        await _channel.invokeMethod<String>('getInitialLink');
    await _handleLink(initialLink);
  }

  Future<void> _handleLink(String? link) async {
    if (link == null || link.isEmpty) return;

    final Uri? uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'govipservices') return;
    if (uri.host != 'parcel-tracking') return;

    final String requestId = (uri.queryParameters['requestId'] ?? '').trim();
    final String role = (uri.queryParameters['role'] ?? '').trim();
    if (requestId.isEmpty) return;

    final navigator = rootNavigatorKey.currentState;
    final context = rootNavigatorKey.currentContext;
    if (navigator == null || context == null || !context.mounted) return;

    if (role == 'driver') {
      final ParcelRequestDocument? request =
          await _requestService.fetchRequestById(requestId);
      if (request == null) return;
      await navigator.pushNamed(
        AppRoutes.parcelsDeliveryRun,
        arguments: request,
      );
      return;
    }

    await navigator.pushNamed(
      AppRoutes.parcelsShipPackage,
      arguments: requestId,
    );
  }
}
