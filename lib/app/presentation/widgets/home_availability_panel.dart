import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:govipservices/features/user/data/user_availability_service.dart';

class HomeAvailabilityPanel extends StatelessWidget {
  const HomeAvailabilityPanel({
    super.key,
    required this.availability,
    required this.isBusy,
    required this.canTravelProvider,
    required this.canParcelsProvider,
    required this.onToggle,
    required this.onScopeSelected,
  });

  final UserAvailabilitySnapshot availability;
  final bool isBusy;
  final bool canTravelProvider;
  final bool canParcelsProvider;
  final ValueChanged<bool> onToggle;
  final ValueChanged<UserAvailabilityScope> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isOnline = availability.isOnline;
    final Color accent = isOnline
        ? const Color(0xFF12B981)
        : theme.colorScheme.outline;
    final Color secondaryAccent = isOnline
        ? const Color(0xFF0F766E)
        : const Color(0xFF94A3B8);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            isOnline ? const Color(0xFFF0FDF7) : const Color(0xFFF8FAFC),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isOnline ? accent.withOpacity(0.35) : const Color(0xFFE2E8F0),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -28,
              right: -18,
              child: _BackdropBlob(
                size: 138,
                color: accent.withOpacity(0.10),
              ),
            ),
            Positioned(
              bottom: -42,
              left: -20,
              child: _BackdropBlob(
                size: 164,
                color: secondaryAccent.withOpacity(0.08),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AvailabilityPanelPatternPainter(
                    accent: accent.withOpacity(0.10),
                    secondary: secondaryAccent.withOpacity(0.08),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 6,
              child: IgnorePointer(
                child: Opacity(
                  opacity: isOnline ? 0.22 : 0.14,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      accent.withOpacity(isOnline ? 0.92 : 0.55),
                      BlendMode.srcIn,
                    ),
                    child: SvgPicture.asset(
                      'assets/illustrations/vehicle.svg',
                      width: 112,
                      height: 112,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.white.withOpacity(0.76),
                    Colors.white.withOpacity(0.88),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.withOpacity(0.32),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              isOnline
                                  ? 'Disponible maintenant'
                                  : 'Actuellement hors ligne',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isOnline
                                  ? 'Votre position sera utilisee pour signaler votre disponibilite.'
                                  : _availabilityHint(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IgnorePointer(
                        ignoring: isBusy,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: isBusy ? 0.7 : 1,
                          child: Switch.adaptive(
                            value: isOnline,
                            onChanged: onToggle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
      _scopeChip(
        context,
        label: 'Voyage',
        value: UserAvailabilityScope.travel,
        enabled: canTravelProvider,
      ),
      _scopeChip(
        context,
        label: 'Colis',
        value: UserAvailabilityScope.parcels,
        enabled: canParcelsProvider,
      ),
      _scopeChip(
        context,
        label: 'Les deux',
        value: UserAvailabilityScope.all,
        enabled: canTravelProvider && canParcelsProvider,
      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 3,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: isBusy ? 1 : 0,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(999),
                        color: accent,
                        backgroundColor: accent.withOpacity(0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeChip(
    BuildContext context, {
    required String label,
    required UserAvailabilityScope value,
    required bool enabled,
  }) {
    final bool selected = availability.scope == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: isBusy || !enabled ? null : (_) => onScopeSelected(value),
      selectedColor: const Color(0xFFE6FFFA),
      backgroundColor:
          enabled ? Colors.white : const Color(0xFFF8FAFC),
      side: BorderSide(
        color: selected
            ? const Color(0xFF14B8A6)
            : enabled
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFE5E7EB),
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: enabled
                ? const Color(0xFF0F172A)
                : const Color(0xFF94A3B8),
          ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  String _availabilityHint() {
    if (!canTravelProvider && !canParcelsProvider) {
      return 'Publiez un trajet ou proposez un service pour pouvoir vous mettre en ligne.';
    }
    if (!canTravelProvider) {
      return 'Passez en ligne pour vos offres colis et partagez votre position.';
    }
    if (!canParcelsProvider) {
      return 'Passez en ligne pour vos trajets et partagez votre position.';
    }
    return 'Passez en ligne pour partager votre position et recevoir des opportunites.';
  }
}

class _BackdropBlob extends StatelessWidget {
  const _BackdropBlob({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _AvailabilityPanelPatternPainter extends CustomPainter {
  const _AvailabilityPanelPatternPainter({
    required this.accent,
    required this.secondary,
  });

  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent;

    final Paint dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = secondary;

    final Path path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.52,
        size.width * 0.58,
        size.height * 0.62,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.70,
        size.width * 0.94,
        size.height * 0.40,
      );
    canvas.drawPath(path, linePaint);

    for (final Offset point in <Offset>[
      Offset(size.width * 0.12, size.height * 0.70),
      Offset(size.width * 0.36, size.height * 0.56),
      Offset(size.width * 0.60, size.height * 0.62),
      Offset(size.width * 0.88, size.height * 0.46),
    ]) {
      canvas.drawCircle(point, 3.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AvailabilityPanelPatternPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.secondary != secondary;
  }
}
