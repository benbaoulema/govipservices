import 'dart:async';
import 'dart:collection';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';

const Color _travelAccentDark = Color(0xFF0F766E);

class GlobalBookingRequestListener extends StatefulWidget {
  const GlobalBookingRequestListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<GlobalBookingRequestListener> createState() =>
      _GlobalBookingRequestListenerState();
}

class _GlobalBookingRequestListenerState
    extends State<GlobalBookingRequestListener> {
  final VoyageBookingService _bookingService = VoyageBookingService();
  final Queue<VoyageBookingDocument> _pendingQueue = Queue<VoyageBookingDocument>();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<VoyageBookingDocument>>? _bookingSubscription;
  Set<String> _knownBookingIds = <String>{};
  bool _hasPrimedBookings = false;
  bool _isDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
    );
    _handleAuthChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  void _handleAuthChanged(User? user) {
    _bookingSubscription?.cancel();
    _knownBookingIds = <String>{};
    _hasPrimedBookings = false;
    _pendingQueue.clear();

    final String uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _bookingSubscription = _bookingService
        .watchPendingBookingsForOwnerUid(uid)
        .listen(_handlePendingBookingsChanged);
  }

  void _handlePendingBookingsChanged(List<VoyageBookingDocument> bookings) {
    final List<VoyageBookingDocument> newBookings = _hasPrimedBookings
        ? bookings
            .where((booking) => !_knownBookingIds.contains(booking.id))
            .toList(growable: false)
        : const <VoyageBookingDocument>[];

    _knownBookingIds = bookings.map((booking) => booking.id).toSet();
    _hasPrimedBookings = true;

    if (newBookings.isEmpty) return;

    for (final VoyageBookingDocument booking in newBookings) {
      _pendingQueue.add(booking);
    }
    _showNextPopupIfIdle();
  }

  void _showNextPopupIfIdle() {
    if (_isDialogVisible || _pendingQueue.isEmpty) return;

    final BuildContext? dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null) return;

    final VoyageBookingDocument booking = _pendingQueue.removeFirst();
    _isDialogVisible = true;

    showDialog<void>(
      context: dialogContext,
      barrierDismissible: true,
      builder: (modalContext) {
        return _GlobalBookingPopup(
          booking: booking,
          onAccept: () => _handleBookingAction(
            modalContext,
            booking,
            'accepted',
          ),
          onReject: () => _handleBookingAction(
            modalContext,
            booking,
            'rejected',
          ),
          onViewDetail: () => _openTripDetail(modalContext, booking),
        );
      },
    ).whenComplete(() {
      _isDialogVisible = false;
      _showNextPopupIfIdle();
    });
  }

  Future<void> _handleBookingAction(
    BuildContext modalContext,
    VoyageBookingDocument booking,
    String status,
  ) async {
    Navigator.of(modalContext).pop();

    final BuildContext? appContext = rootNavigatorKey.currentContext;
    try {
      await _bookingService.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (appContext == null || !appContext.mounted) return;
      ScaffoldMessenger.of(appContext)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              status == 'accepted'
                  ? 'Réservation acceptée.'
                  : 'Réservation refusée.',
            ),
          ),
        );
    } catch (_) {
      if (appContext == null || !appContext.mounted) return;
      ScaffoldMessenger.of(appContext)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF991B1B),
            content: Text('Mise à jour impossible pour le moment.'),
          ),
        );
    }
  }

  Future<void> _openTripDetail(
    BuildContext modalContext,
    VoyageBookingDocument booking,
  ) async {
    Navigator.of(modalContext).pop();
    final NavigatorState? navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    await navigator.pushNamed(
      AppRoutes.travelTripDetail,
      arguments: TripDetailArgs(
        tripId: booking.tripId,
        from: booking.segmentFrom,
        to: booking.segmentTo,
        effectiveDepartureDate: booking.tripDepartureDate,
        accessMode: TripDetailAccessMode.owner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _GlobalBookingPopup extends StatelessWidget {
  const _GlobalBookingPopup({
    required this.booking,
    required this.onAccept,
    required this.onReject,
    required this.onViewDetail,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF0F766E),
              Color(0xFF14B8A6),
            ],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Nouvelle réservation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                booking.requesterName.isEmpty
                    ? 'Un passager a réservé ce trajet.'
                    : '${booking.requesterName} a réservé ce trajet.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${booking.segmentFrom} -> ${booking.segmentTo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Réf: ${booking.trackNum}',
                      style: const TextStyle(
                        color: Color(0xFFE6FFFB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _PopupMetaPill(
                          icon: Icons.event_seat_rounded,
                          label:
                              '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
                        ),
                        _PopupMetaPill(
                          icon: Icons.payments_outlined,
                          label: '${booking.totalPrice} ${booking.tripCurrency}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.42)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Refuser'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _travelAccentDark,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accepter'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onViewDetail,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Voir détail'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.86),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Plus tard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopupMetaPill extends StatelessWidget {
  const _PopupMetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
