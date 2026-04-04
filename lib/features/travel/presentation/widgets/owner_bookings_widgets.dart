import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);
const Color _travelSurfaceBorder = Color(0xFFD8F3EE);

String bookingStatusLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'accepted':
    case 'approved':
    case 'confirmed':
      return 'Acceptée';
    case 'rejected':
    case 'refused':
      return 'Refusée';
    case 'cancelled':
      return 'Annulée';
    case 'pending':
    default:
      return 'En attente';
  }
}

class TripOwnerActionsCard extends StatelessWidget {
  const TripOwnerActionsCard({
    required this.supportOnly,
    required this.reservationCount,
    required this.onEdit,
    required this.onDelete,
    required this.onViewBookings,
    super.key,
  });

  final bool supportOnly;
  final int reservationCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewBookings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            supportOnly ? 'Support' : 'Actions',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OwnerActionIconButton(
                icon: Icons.receipt_long_rounded,
                tooltip: 'Voir les résas',
                count: reservationCount,
                onTap: onViewBookings,
              ),
              const SizedBox(width: 8),
              _OwnerActionIconButton(
                icon: Icons.edit_rounded,
                tooltip: supportOnly ? 'Modifier via support' : 'Modifier',
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _OwnerActionIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: supportOnly ? 'Supprimer via support' : 'Supprimer',
                danger: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerActionIconButton extends StatelessWidget {
  const _OwnerActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.count,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? const Color(0xFFB42318) : _travelAccentDark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: danger ? const Color(0xFFFFE4E0) : _travelAccentSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: count == null ? 8 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InlineBookingsPanel extends StatelessWidget {
  const InlineBookingsPanel({
    required this.bookings,
    required this.busyBookingId,
    required this.onAccept,
    required this.onReject,
    required this.onViewAll,
    super.key,
  });

  final List<VoyageBookingDocument> bookings;
  final String? busyBookingId;
  final ValueChanged<VoyageBookingDocument> onAccept;
  final ValueChanged<VoyageBookingDocument> onReject;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nouvelles réservations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Réagissez immédiatement sans quitter le détail du trajet.',
            style: TextStyle(
              color: Color(0xFF5B647A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < bookings.length; index++) ...[
            _InlineBookingRow(
              booking: bookings[index],
              isBusy: busyBookingId == bookings[index].id,
              onAccept: () => onAccept(bookings[index]),
              onReject: () => onReject(bookings[index]),
            ),
            if (index < bookings.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _InlineBookingRow extends StatelessWidget {
  const _InlineBookingRow({
    required this.booking,
    required this.onAccept,
    required this.onReject,
    this.isBusy = false,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FFFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.requesterName.isEmpty
                      ? 'Demandeur non renseigné'
                      : booking.requesterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _travelAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: _travelAccentDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${booking.segmentFrom} -> ${booking.segmentTo}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Réf: ${booking.trackNum}',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: _travelAccentDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accepter'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFF04438)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Refuser'),
                ),
              ),
              if (isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RelatedBookingCard extends StatelessWidget {
  const _RelatedBookingCard({
    required this.booking,
    required this.onAccept,
    required this.onReject,
    required this.onWrite,
    this.isBusy = false,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onWrite;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.requesterName.isEmpty ? 'Demandeur non renseigné' : booking.requesterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _travelAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  bookingStatusLabel(booking.status),
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Réf: ${booking.trackNum}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${booking.segmentFrom} -> ${booking.segmentTo}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BookingMetaPill(
                icon: Icons.event_seat_rounded,
                label: '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
              ),
              _BookingMetaPill(
                icon: Icons.payments_outlined,
                label: '${booking.totalPrice} ${booking.tripCurrency}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _BookingActionChip(
                label: 'Accepter',
                icon: Icons.check_rounded,
                onTap: isBusy ? null : onAccept,
              ),
              const SizedBox(width: 8),
              _BookingActionChip(
                label: 'Refuser',
                icon: Icons.close_rounded,
                danger: true,
                onTap: isBusy ? null : onReject,
              ),
              const SizedBox(width: 8),
              _BookingActionChip(
                label: 'Ecrire',
                icon: Icons.chat_bubble_outline_rounded,
                onTap: isBusy ? null : onWrite,
              ),
              if (isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingActionChip extends StatelessWidget {
  const _BookingActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? const Color(0xFFB42318) : _travelAccentDark;
    final Color bg = danger ? const Color(0xFFFFE4E0) : _travelAccentSoft;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingMetaPill extends StatelessWidget {
  const _BookingMetaPill({
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF667085)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedBookingsSheetContent extends StatefulWidget {
  const _RelatedBookingsSheetContent({
    required this.initialBookings,
    required this.onBookingsChanged,
  });

  final List<VoyageBookingDocument> initialBookings;
  final ValueChanged<List<VoyageBookingDocument>> onBookingsChanged;

  @override
  State<_RelatedBookingsSheetContent> createState() => _RelatedBookingsSheetContentState();
}

class _RelatedBookingsSheetContentState extends State<_RelatedBookingsSheetContent> {
  final VoyageBookingService _bookingService = VoyageBookingService();
  String? _busyBookingId;
  late List<VoyageBookingDocument> _bookings;

  @override
  void initState() {
    super.initState();
    _bookings = List<VoyageBookingDocument>.from(widget.initialBookings);
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFF991B1B) : const Color(0xFF0F766E),
          content: Text(message),
        ),
      );
  }

  Future<void> _setBookingStatus(VoyageBookingDocument booking, String status) async {
    setState(() {
      _busyBookingId = booking.id;
    });
    try {
      await _bookingService.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (!mounted) return;
      final List<VoyageBookingDocument> next = _bookings
          .map((item) => item.id == booking.id
              ? VoyageBookingDocument(
                  id: item.id,
                  trackNum: item.trackNum,
                  tripId: item.tripId,
                  tripTrackNum: item.tripTrackNum,
                  tripOwnerUid: item.tripOwnerUid,
                  tripOwnerTrackNum: item.tripOwnerTrackNum,
                  tripCurrency: item.tripCurrency,
                  tripDepartureDate: item.tripDepartureDate,
                  tripDepartureTime: item.tripDepartureTime,
                  tripFrequency: item.tripFrequency,
                  tripDeparturePlace: item.tripDeparturePlace,
                  tripArrivalEstimatedTime: item.tripArrivalEstimatedTime,
                  tripArrivalPlace: item.tripArrivalPlace,
                  tripDriverName: item.tripDriverName,
                  tripVehicleModel: item.tripVehicleModel,
                  tripContactPhone: item.tripContactPhone,
                  tripIntermediateStops: item.tripIntermediateStops,
                  requestedSeats: item.requestedSeats,
                  requesterUid: item.requesterUid,
                  requesterTrackNum: item.requesterTrackNum,
                  requesterName: item.requesterName,
                  requesterContact: item.requesterContact,
                  requesterEmail: item.requesterEmail,
                  segmentFrom: item.segmentFrom,
                  segmentTo: item.segmentTo,
                  segmentPrice: item.segmentPrice,
                  totalPrice: item.totalPrice,
                  travelers: item.travelers,
                  unreadForDriver: item.unreadForDriver,
                  unreadForPassenger: item.unreadForPassenger,
                  status: status,
                  createdAt: item.createdAt,
                  updatedAt: item.updatedAt,
                )
              : item)
          .toList(growable: false);
      setState(() {
        _bookings = next;
      });
      widget.onBookingsChanged(next);
      _showMessage(
        status == 'accepted' ? 'Réservation acceptée.' : 'Réservation refusée.',
      );
    } catch (_) {
      _showMessage('Mise à jour impossible pour le moment.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyBookingId = null;
        });
      }
    }
  }

  void _writeToTraveler(VoyageBookingDocument booking) {
    final String target = booking.requesterName.isEmpty ? booking.trackNum : booking.requesterName;
    _showMessage('Conversation avec $target bientôt disponible.');
  }

  @override
  Widget build(BuildContext context) {
    if (_bookings.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Text('Aucune réservation liée à ce trajet.'),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Réservations associées',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_bookings.length} réservation(s) liée(s) à ce trajet.',
            style: const TextStyle(
              color: Color(0xFF5B647A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final VoyageBookingDocument booking = _bookings[index];
                return _RelatedBookingCard(
                  booking: booking,
                  isBusy: _busyBookingId == booking.id,
                  onAccept: () => _setBookingStatus(booking, 'accepted'),
                  onReject: () => _setBookingStatus(booking, 'rejected'),
                  onWrite: () => _writeToTraveler(booking),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the full bookings sheet for a trip owner.
void showRelatedBookingsSheet(
  BuildContext context, {
  required List<VoyageBookingDocument> bookings,
  required ValueChanged<List<VoyageBookingDocument>> onBookingsChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF2FFFC),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: _RelatedBookingsSheetContent(
            initialBookings: bookings,
            onBookingsChanged: onBookingsChanged,
          ),
        ),
      );
    },
  );
}
