import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

class BookingDetailPage extends StatefulWidget {
  const BookingDetailPage({
    super.key,
    required this.booking,
  });

  final VoyageBookingDocument booking;

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  final VoyageBookingService _bookingService = VoyageBookingService();

  late VoyageBookingDocument _booking;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  bool get _canCancel {
    final String status = _booking.status.trim().toLowerCase();
    return status != 'cancelled' && status != 'rejected' && status != 'refused';
  }

  Future<void> _cancelBooking() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Annuler la réservation'),
          content: const Text('Voulez-vous vraiment annuler cette réservation ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Retour'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      await _bookingService.cancelBookingById(
        bookingId: _booking.id,
        tripId: _booking.tripId,
        requestedSeats: _booking.requestedSeats,
      );
      if (!mounted) return;
      final VoyageBookingDocument updated = _copyBookingWithStatus(_booking, 'cancelled');
      setState(() {
        _booking = updated;
      });
      Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Annulation impossible pour le moment.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String statusLabel = _bookingStatusLabel(_booking.status);
    final String totalPrice = '${_booking.totalPrice} ${_booking.tripCurrency.isEmpty ? 'XOF' : _booking.tripCurrency}';

    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Réservation'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _canCancel && !_isCancelling ? _cancelBooking : null,
            icon: _isCancelling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(_canCancel ? 'Annuler la réservation' : 'Réservation non annulable'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _BookingHeroCard(
            departure: _booking.tripDeparturePlace,
            arrival: _booking.tripArrivalPlace,
            statusLabel: statusLabel,
            trackNum: _booking.trackNum,
          ),
          const SizedBox(height: 16),
          _BookingSection(
            title: 'Voyage',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _BookingInfoChip(icon: Icons.calendar_today_rounded, label: _booking.tripDepartureDate),
                _BookingInfoChip(icon: Icons.schedule_rounded, label: _booking.tripDepartureTime),
                _BookingInfoChip(icon: Icons.event_seat_rounded, label: '${_booking.requestedSeats} place${_booking.requestedSeats > 1 ? 's' : ''}'),
                _BookingInfoChip(icon: Icons.payments_outlined, label: totalPrice),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _BookingSection(
            title: 'Contact',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BookingLine(label: 'Conducteur', value: _booking.tripDriverName),
                const SizedBox(height: 10),
                _BookingLine(label: 'Téléphone', value: _booking.tripContactPhone),
                if (_booking.tripVehicleModel.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _BookingLine(label: 'Véhicule', value: _booking.tripVehicleModel),
                ],
              ],
            ),
          ),
          if (_booking.tripIntermediateStops.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BookingSection(
              title: 'Arrêts intermédiaires',
              child: Column(
                children: [
                  for (int i = 0; i < _booking.tripIntermediateStops.length; i++) ...[
                    _IntermediateStopTile(stop: _booking.tripIntermediateStops[i]),
                    if (i < _booking.tripIntermediateStops.length - 1) const Divider(height: 18),
                  ],
                ],
              ),
            ),
          ],
          if (_booking.travelers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BookingSection(
              title: 'Passagers',
              child: Column(
                children: [
                  for (int i = 0; i < _booking.travelers.length; i++) ...[
                    _TravelerTile(traveler: _booking.travelers[i], index: i + 1),
                    if (i < _booking.travelers.length - 1) const Divider(height: 18),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _bookingStatusLabel(String raw) {
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

VoyageBookingDocument _copyBookingWithStatus(VoyageBookingDocument booking, String status) {
  return VoyageBookingDocument.fromMap(
    booking.id,
    <String, dynamic>{
      ...booking.toMap(),
      'status': status,
    },
  );
}

class _BookingHeroCard extends StatelessWidget {
  const _BookingHeroCard({
    required this.departure,
    required this.arrival,
    required this.statusLabel,
    required this.trackNum,
  });

  final String departure;
  final String arrival;
  final String statusLabel;
  final String trackNum;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Ref: $trackNum',
                  style: const TextStyle(
                    color: Color(0xFF1F4B5F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Color(0xFF1F4B5F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            departure,
            style: const TextStyle(
              color: Color(0xFF16313C),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Icon(
            Icons.south_rounded,
            color: Color(0xFF1F4B5F),
          ),
          const SizedBox(height: 6),
          Text(
            arrival,
            style: const TextStyle(
              color: Color(0xFF5D7480),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingSection extends StatelessWidget {
  const _BookingSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF16313C),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BookingInfoChip extends StatelessWidget {
  const _BookingInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E4EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1F4B5F)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF16313C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingLine extends StatelessWidget {
  const _BookingLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5D7480),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '-' : value.trim(),
            style: const TextStyle(
              color: Color(0xFF16313C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _IntermediateStopTile extends StatelessWidget {
  const _IntermediateStopTile({
    required this.stop,
  });

  final Map<String, dynamic> stop;

  @override
  Widget build(BuildContext context) {
    final String address = (stop['address'] ?? '').toString().trim();
    final String estimatedTime = (stop['estimatedTime'] ?? '').toString().trim();
    final String priceFromDeparture = (stop['priceFromDeparture'] ?? '').toString().trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.place_outlined, color: Color(0xFF1F4B5F), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                address.isEmpty ? 'Arret' : address,
                style: const TextStyle(
                  color: Color(0xFF16313C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (estimatedTime.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  estimatedTime,
                  style: const TextStyle(
                    color: Color(0xFF5D7480),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (priceFromDeparture.isNotEmpty)
          Text(
            '$priceFromDeparture XOF',
            style: const TextStyle(
              color: Color(0xFF1F4B5F),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _TravelerTile extends StatelessWidget {
  const _TravelerTile({
    required this.traveler,
    required this.index,
  });

  final VoyageBookingTraveler traveler;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFEAF2F5),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Color(0xFF1F4B5F),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                traveler.name.trim().isEmpty ? 'Passager' : traveler.name.trim(),
                style: const TextStyle(
                  color: Color(0xFF16313C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (traveler.contact.trim().isNotEmpty)
                Text(
                  traveler.contact.trim(),
                  style: const TextStyle(
                    color: Color(0xFF5D7480),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
