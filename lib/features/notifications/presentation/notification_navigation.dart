import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/presentation/pages/booking_detail_page.dart';

class NotificationNavigation {
  NotificationNavigation({
    TravelRepository? travelRepository,
    VoyageBookingService? bookingService,
    ParcelRequestService? parcelRequestService,
  })  : _travelRepository = travelRepository ?? TravelRepository(),
        _bookingService = bookingService ?? VoyageBookingService(),
        _parcelRequestService = parcelRequestService ?? ParcelRequestService();

  final TravelRepository _travelRepository;
  final VoyageBookingService _bookingService;
  final ParcelRequestService _parcelRequestService;

  Future<String?> openFromAppNotification(
    BuildContext context,
    AppNotification notification,
  ) {
    return openFromPayload(context, <String, dynamic>{
      'domain': notification.domain,
      'type': notification.type,
      'entityType': notification.entityType,
      'entityId': notification.entityId,
      ...notification.data,
    });
  }

  Future<String?> openFromPayload(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final String domain = (payload['domain'] as String? ?? '').trim();
    if (domain == 'parcel') {
      return _openParcelRequest(context, payload);
    }
    if (domain != 'travel') {
      return 'Ouverture bientot disponible.';
    }

    final String type = (payload['type'] as String? ?? '').trim();
    final String entityType = (payload['entityType'] as String? ?? '').trim();

    if (type == 'booking_status_updated') {
      return _openBooking(context, payload);
    }
    if (type == 'booking_created' || type == 'booking_cancelled') {
      return _openTrip(context, payload, forceOwnerMode: true);
    }
    if (type == 'trip_updated' || type == 'trip_cancelled') {
      final String bookingId = (payload['bookingId'] as String? ?? '').trim();
      if (bookingId.isNotEmpty) {
        return _openBooking(context, payload);
      }
      return _openTrip(context, payload);
    }

    switch (entityType) {
      case 'booking':
        return _openBooking(context, payload);
      case 'trip':
        return _openTrip(context, payload);
      default:
        return 'Aucune action disponible.';
    }
  }

  Future<String?> _openParcelRequest(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final String requestId =
        '${payload['demandId'] ?? payload['entityId'] ?? ''}'.trim();
    if (requestId.isEmpty) return 'Demande colis introuvable.';

    final ParcelRequestDocument? request =
        await _parcelRequestService.fetchRequestById(requestId);
    if (request == null) return 'Demande colis introuvable.';
    if (!context.mounted) return null;

    final String currentUid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final bool isDriver = request.providerUid == currentUid;

    switch (request.status) {
      case 'provider_notified':
        // GlobalParcelRequestListener gère déjà ce popup côté livreur.
        // Ne pas ouvrir un deuxième popup ici.
        return null;

      case 'accepted':
      case 'en_route_to_pickup':
      case 'picked_up':
        if (isDriver) {
          await Navigator.of(context).pushNamed(
            AppRoutes.parcelsDeliveryRun,
            arguments: request,
          );
        } else {
          await Navigator.of(context).pushNamed(
            AppRoutes.parcelsShipPackage,
            arguments: request.id,
          );
        }
        return null;

      default:
        // delivered / rejected / cancelled → info uniquement
        return 'Cette livraison est terminée.';
    }
  }

  Future<String?> _openBooking(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final String bookingId =
        '${payload['bookingId'] ?? payload['entityId'] ?? ''}'.trim();
    if (bookingId.isEmpty) return 'Réservation introuvable.';

    final VoyageBookingDocument? booking =
        await _bookingService.fetchBookingById(bookingId);
    if (booking == null) return 'Réservation introuvable.';
    if (!context.mounted) return null;

    await Navigator.of(context).push<VoyageBookingDocument>(
      MaterialPageRoute<VoyageBookingDocument>(
        builder: (_) => BookingDetailPage(booking: booking),
      ),
    );
    return null;
  }

  Future<String?> _openTrip(
    BuildContext context,
    Map<String, dynamic> payload, {
    bool forceOwnerMode = false,
  }) async {
    final String tripId =
        '${payload['tripId'] ?? payload['entityId'] ?? ''}'.trim();
    if (tripId.isEmpty) return 'Trajet introuvable.';

    final TripSearchResult? trip = await _travelRepository.fetchTripById(tripId);
    if (trip == null) return 'Trajet introuvable.';
    if (!context.mounted) return null;

    final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String ownerUid = (trip.raw['ownerUid'] as String? ?? '').trim();
    final TripDetailAccessMode accessMode = forceOwnerMode
        ? TripDetailAccessMode.owner
        : currentUid.isNotEmpty && currentUid == ownerUid
            ? TripDetailAccessMode.owner
            : TripDetailAccessMode.traveler;

    await Navigator.of(context).pushNamed(
      AppRoutes.travelTripDetail,
      arguments: TripDetailArgs(
        tripId: trip.id,
        from: trip.departurePlace,
        to: trip.arrivalPlace,
        effectiveDepartureDate: trip.effectiveDepartureDate ?? trip.departureDate,
        accessMode: accessMode,
      ),
    );
    return null;
  }
}



