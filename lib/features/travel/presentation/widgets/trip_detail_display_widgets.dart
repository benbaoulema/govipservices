import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);
const Color _travelSurfaceBorder = Color(0xFFD8F3EE);

class TripDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TripDetailAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      title: const Text('Détail du trajet'),
      elevation: 0,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class TripSegmentCard extends StatelessWidget {
  const TripSegmentCard({
    required this.dateLabel,
    required this.frequencyLabel,
    required this.seats,
    required this.segment,
    required this.canPickDate,
    required this.showNotice,
    required this.noticeText,
    this.onPickDate,
    super.key,
  });

  final String dateLabel;
  final String frequencyLabel;
  final int seats;
  final TripSegmentModel segment;
  final bool canPickDate;
  final bool showNotice;
  final String noticeText;
  final VoidCallback? onPickDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPickDate)
                GestureDetector(
                  onTap: onPickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _travelAccentDark.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 14, color: _travelAccentDark),
                        const SizedBox(width: 5),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _travelAccentDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 15, color: _travelAccentDark),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  dateLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A2747)),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _travelAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  frequencyLabel,
                  style: const TextStyle(
                    color: _travelAccentDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$seats place(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF53658D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Disponible(s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A8CA8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showNotice) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF9A3412)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      noticeText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _IntermediateStopOption extends StatelessWidget {
  const _IntermediateStopOption({
    required this.node,
    required this.isSelected,
    required this.onTap,
  });

  final TripRouteNode node;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? _travelAccentSoft : const Color(0xFFF8FFFD),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected ? _travelAccent : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _travelAccent.withValues(alpha: 0.24)),
                ),
                child: Icon(
                  isSelected ? Icons.check_rounded : Icons.place_outlined,
                  size: 18,
                  color: isSelected ? Colors.white : _travelAccentDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.address,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (node.time.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Heure estimée : ${node.time}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5B647A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                isSelected ? 'Selectionne' : 'Choisir',
                style: TextStyle(
                  color: isSelected ? _travelAccentDark : _travelAccent,
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

class TripTimelineWidget extends StatelessWidget {
  const TripTimelineWidget({
    required this.segment,
    this.showAlternativeDepartures = false,
    this.onOpenAlternativeDepartures,
    this.showAlternativeArrivals = false,
    this.onOpenAlternativeArrivals,
    super.key,
  });

  final TripSegmentModel segment;
  final bool showAlternativeDepartures;
  final VoidCallback? onOpenAlternativeDepartures;
  final bool showAlternativeArrivals;
  final VoidCallback? onOpenAlternativeArrivals;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.departureNode.time.isEmpty ? '--:--' : segment.departureNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    segment.arrivalNode.time.isEmpty ? '--:--' : segment.arrivalNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: _travelAccent, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: const Color(0xFFCAD6EE)),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF8FA5CF), shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(segment.departureNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (showAlternativeDepartures && onOpenAlternativeDepartures != null) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: onOpenAlternativeDepartures,
                          icon: const Icon(Icons.alt_route_rounded, size: 16),
                          label: const Text('Changer départ'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _travelAccentDark,
                            side: const BorderSide(color: _travelSurfaceBorder),
                            backgroundColor: _travelAccentSoft.withValues(alpha: 0.35),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAlternativeArrivals && onOpenAlternativeArrivals != null) ...[
                        OutlinedButton.icon(
                          onPressed: onOpenAlternativeArrivals,
                          icon: const Icon(Icons.location_on_outlined, size: 16),
                          label: const Text('Changer arrivée'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _travelAccentDark,
                            side: const BorderSide(color: _travelSurfaceBorder),
                            backgroundColor: _travelAccentSoft.withValues(alpha: 0.35),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(segment.arrivalNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TripFareCard extends StatelessWidget {
  const TripFareCard({
    required this.unitFare,
    required this.currency,
    required this.seats,
    required this.total,
    super.key,
  });

  final int unitFare;
  final String currency;
  final int seats;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tarif', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Prix: $unitFare $currency', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Total ($seats place(s)): $total $currency', style: const TextStyle(fontWeight: FontWeight.w800, color: _travelAccentDark)),
        ],
      ),
    );
  }
}

class TripDriverCard extends StatelessWidget {
  const TripDriverCard({required this.driver, super.key});

  final DriverInfoModel driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.name.isEmpty ? 'Conducteur non renseigné' : driver.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Contact partagé après confirmation',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B647A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TripVehicleCard extends StatelessWidget {
  const TripVehicleCard({required this.vehicle, super.key});

  final VehicleInfoModel vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vehicle.model.isEmpty ? 'Véhicule non renseigné' : vehicle.model,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class TripOptionsChips extends StatelessWidget {
  const TripOptionsChips({required this.options, super.key});

  final TripOptionsModel options;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      _OptionChip(
        icon: Icons.luggage_outlined,
        label: options.hasLuggageSpace ? 'Bagages autorises' : 'Sans bagage',
      ),
      _OptionChip(
        icon: Icons.pets_outlined,
        label: options.allowsPets ? 'Animaux autorises' : 'Sans animaux',
      ),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _travelAccentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _travelAccentDark),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class TripBookingPanel extends StatelessWidget {
  const TripBookingPanel({
    required this.selectedSeats,
    required this.maxSeats,
    required this.currency,
    required this.total,
    required this.hidePrice,
    required this.canBook,
    required this.onIncrement,
    required this.onDecrement,
    required this.onBook,
    super.key,
  });

  final int selectedSeats;
  final int maxSeats;
  final String currency;
  final int total;
  final bool hidePrice;
  final bool canBook;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final bool canDec = selectedSeats > 1;
    final bool canInc = selectedSeats < maxSeats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Réservation', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FFFD),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _travelSurfaceBorder),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Places',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5B647A),
                    ),
                  ),
                ),
                _SeatAdjustButton(
                  icon: Icons.remove_rounded,
                  onTap: canDec ? onDecrement : null,
                ),
                Container(
                  width: 48,
                  alignment: Alignment.center,
                  child: Text(
                    '$selectedSeats',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF10233E),
                    ),
                  ),
                ),
                _SeatAdjustButton(
                  icon: Icons.add_rounded,
                  onTap: canInc ? onIncrement : null,
                ),
                if (!hidePrice) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$total $currency',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _travelAccentDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canBook ? onBook : null,
              child: const Text('Réserver'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatAdjustButton extends StatelessWidget {
  const _SeatAdjustButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Material(
      color: enabled ? _travelAccentSoft : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: enabled ? _travelAccentDark : const Color(0xFF9AA7B8),
          ),
        ),
      ),
    );
  }
}

class TripErrorStateWidget extends StatelessWidget {
  const TripErrorStateWidget({
    required this.message,
    required this.onRetry,
    required this.actionLabel,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Color(0xFF8D1F1F)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class TripLoadingSkeleton extends StatelessWidget {
  const TripLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SkeletonBox(height: 90),
        SizedBox(height: 12),
        _SkeletonBox(height: 110),
        SizedBox(height: 12),
        _SkeletonBox(height: 88),
        SizedBox(height: 12),
        _SkeletonBox(height: 70),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF8),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

/// Shows a bottom sheet to pick an intermediate departure or arrival stop.
/// Used internally by [_SuccessBodyState] in trip_detail_page.dart.
void showIntermediateStopSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<MapEntry<int, TripRouteNode>> stops,
  required int selectedIndex,
  required Future<void> Function(int nodeIndex) onSelect,
}) {
  showModalBottomSheet<void>(
    context: context,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF5B647A)),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: stops.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final MapEntry<int, TripRouteNode> entry = stops[index];
                    final bool isSelected = entry.key == selectedIndex;
                    return _IntermediateStopOption(
                      node: entry.value,
                      isSelected: isSelected,
                      onTap: () async {
                        await onSelect(entry.key);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
