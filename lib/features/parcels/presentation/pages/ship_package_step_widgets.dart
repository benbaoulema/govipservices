part of 'ship_package_page.dart';

// ── Data classes ───────────────────────────────────────────────────────────────

class _ContactConfirmResult {
  const _ContactConfirmResult({
    required this.senderContact,
    required this.receiverName,
    required this.receiverPhone,
  });
  final String senderContact;
  final String receiverName;
  final String receiverPhone;
}

// ── Waiting for driver sheet ───────────────────────────────────────────────────

/// Statut simplifié côté expéditeur.
///
/// L'expéditeur suit un cycle plus détaillé pour savoir si le livreur est
/// simplement en chemin, déjà arrivé au point de collecte, ou déjà arrivé à
/// destination.
enum _SenderRequestStatus {
  pending,      // provider_notified
  accepted,     // accepted
  enRoute,      // en_route_to_pickup
  arrivedAtPickup, // arrived_at_pickup
  pickedUp,     // picked_up
  arrivedAtDelivery, // arrived_at_delivery
  delivered;    // delivered

  static _SenderRequestStatus fromFirestore(String? value) {
    switch (value) {
      case 'accepted':           return _SenderRequestStatus.accepted;
      case 'en_route_to_pickup': return _SenderRequestStatus.enRoute;
      case 'en_route':           return _SenderRequestStatus.enRoute;
      case 'arrived_at_pickup':  return _SenderRequestStatus.arrivedAtPickup;
      case 'picked_up':          return _SenderRequestStatus.pickedUp;
      case 'arrived_at_delivery':
        return _SenderRequestStatus.arrivedAtDelivery;
      case 'delivered':          return _SenderRequestStatus.delivered;
      default:                   return _SenderRequestStatus.pending;
    }
  }

  String get firestoreValue {
    switch (this) {
      case _SenderRequestStatus.pending:
        return 'provider_notified';
      case _SenderRequestStatus.accepted:
        return 'accepted';
      case _SenderRequestStatus.enRoute:
        return 'en_route_to_pickup';
      case _SenderRequestStatus.arrivedAtPickup:
        return 'arrived_at_pickup';
      case _SenderRequestStatus.pickedUp:
        return 'picked_up';
      case _SenderRequestStatus.arrivedAtDelivery:
        return 'arrived_at_delivery';
      case _SenderRequestStatus.delivered:
        return 'delivered';
    }
  }

  bool get isFinal => this == _SenderRequestStatus.delivered;

  /// L'expéditeur peut annuler tant que le livreur n'est pas arrivé au pickup.
  bool get canSenderCancel {
    switch (this) {
      case _SenderRequestStatus.pending:
      case _SenderRequestStatus.accepted:
      case _SenderRequestStatus.enRoute:
        return true;
      case _SenderRequestStatus.arrivedAtPickup:
      case _SenderRequestStatus.pickedUp:
      case _SenderRequestStatus.arrivedAtDelivery:
      case _SenderRequestStatus.delivered:
        return false;
    }
  }
}

class _StatusStep {
  const _StatusStep({
    required this.status,
    required this.icon,
    required this.label,
    required this.sublabel,
  });
  final _SenderRequestStatus status;
  final String icon;
  final String label;
  final String sublabel;
}

const List<_StatusStep> _kStatusSteps = <_StatusStep>[
  _StatusStep(
    status: _SenderRequestStatus.pending,
    icon: '📨',
    label: 'Demande envoyée',
    sublabel: 'En attente de la réponse du livreur…',
  ),
  _StatusStep(
    status: _SenderRequestStatus.accepted,
    icon: '✅',
    label: 'Demande acceptée',
    sublabel: 'Le livreur a confirmé votre demande.',
  ),
  _StatusStep(
    status: _SenderRequestStatus.enRoute,
    icon: '🏍️',
    label: 'Livreur en route',
    sublabel: 'Il arrive au lieu de récupération.',
  ),
  _StatusStep(
    status: _SenderRequestStatus.arrivedAtPickup,
    icon: '📍',
    label: 'Livreur arrivé',
    sublabel: 'Le livreur est sur place pour récupérer le colis.',
  ),
  _StatusStep(
    status: _SenderRequestStatus.pickedUp,
    icon: '📦',
    label: 'Colis récupéré',
    sublabel: 'Votre colis est en route vers la destination.',
  ),
  _StatusStep(
    status: _SenderRequestStatus.arrivedAtDelivery,
    icon: '🏁',
    label: 'Livreur arrivé à destination',
    sublabel: 'Le livreur est sur place pour remettre le colis.',
  ),
  _StatusStep(
    status: _SenderRequestStatus.delivered,
    icon: '🎉',
    label: 'Livraison effectuée !',
    sublabel: 'Votre colis a bien été remis au destinataire.',
  ),
];

// ── Waiting inline content (embedded in sheet, no modal) ──────────────────────

class _WaitingInlineContent extends StatefulWidget {
  const _WaitingInlineContent({
    required this.match,
    required this.trackNum,
    required this.status,
    required this.onClose,
    required this.scrollController,
    this.onCancel,
    this.onTimeout,
    this.etaText,
    this.overridePrice,
  });

  final ParcelServiceMatch match;
  final String trackNum;
  final _SenderRequestStatus status;
  final VoidCallback onClose;
  final VoidCallback? onCancel;
  final VoidCallback? onTimeout;
  final ScrollController scrollController;
  final String? etaText;
  final double? overridePrice;

  @override
  State<_WaitingInlineContent> createState() => _WaitingInlineContentState();
}

class _WaitingInlineContentState extends State<_WaitingInlineContent>
    with SingleTickerProviderStateMixin {
  static const Color _teal = Color(0xFF0F766E);

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  _SenderRequestStatus get _timelineStatus {
    if (widget.status == _SenderRequestStatus.enRoute) {
      return _SenderRequestStatus.accepted;
    }
    return widget.status;
  }

  int get _currentIndex =>
      _kStatusSteps.indexWhere((s) => s.status == _timelineStatus);

  @override
  Widget build(BuildContext context) {
    // Radar animé quand le driver n'a pas encore répondu
    if (widget.status == _SenderRequestStatus.pending) {
      return _RadarPendingView(
        match: widget.match,
        scrollController: widget.scrollController,
        onCancel: widget.onCancel,
        onTimeout: widget.onTimeout,
      );
    }

    final double bottomPad = MediaQuery.of(context).padding.bottom + 24;
    return Expanded(
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
        children: <Widget>[
          _CourierProgressTrack(status: _timelineStatus),
          const SizedBox(height: 12),
          _DriverCard(
            match: widget.match,
            trackNum: widget.trackNum,
            etaText: widget.etaText,
            overridePrice: widget.overridePrice,
          ),
          const SizedBox(height: 20),
          ...List<Widget>.generate(_kStatusSteps.length, (int i) {
            final _StatusStep step = _kStatusSteps[i];
            final bool isDone = i < _currentIndex;
            final bool isCurrent = i == _currentIndex;
            final bool isLast = i == _kStatusSteps.length - 1;
            return _TimelineRow(
              step: step,
              isDone: isDone,
              isCurrent: isCurrent,
              isLast: isLast,
              pulseAnim:
                  isCurrent && !_timelineStatus.isFinal ? _pulseAnim : null,
            );
          }),
          const SizedBox(height: 20),
          if (widget.status.isFinal)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: widget.onClose,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Fermer',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onClose,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: Color(0xFFE2E8F0), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Masquer',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B))),
                  ),
                ),
                if (widget.onCancel != null &&
                    widget.status.canSenderCancel) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(
                            color: Color(0xFFDC2626), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Annuler',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );

  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _CourierProgressTrack extends StatelessWidget {
  const _CourierProgressTrack({required this.status});
  final _SenderRequestStatus status;

  static double _toProgress(_SenderRequestStatus s) {
    switch (s) {
      case _SenderRequestStatus.pending:   return 0.05;
      case _SenderRequestStatus.accepted:  return 0.22;
      case _SenderRequestStatus.enRoute:   return 0.45;
      case _SenderRequestStatus.arrivedAtPickup: return 0.58;
      case _SenderRequestStatus.pickedUp:  return 0.72;
      case _SenderRequestStatus.arrivedAtDelivery: return 0.9;
      case _SenderRequestStatus.delivered: return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = _toProgress(status);
    const Color teal = Color(0xFF0F766E);
    const double endIconSize = 22;
    const double motoSize   = 26;
    const double trackH     = 4;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints bc) {
              final double w = bc.maxWidth;
              // Track spans between centres of the endpoint icons
              const double pad = endIconSize / 2;
              final double trackW = w - endIconSize;
              final double motoLeft =
                  (pad + trackW * progress - motoSize / 2)
                      .clamp(0.0, w - motoSize);

              return SizedBox(
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // Grey track
                    Positioned(
                      left: pad,
                      right: pad,
                      top: (44 - trackH) / 2 + motoSize * 0.55,
                      child: Container(
                        height: trackH,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    // Teal progress fill
                    Positioned(
                      left: pad,
                      top: (44 - trackH) / 2 + motoSize * 0.55,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeInOut,
                        height: trackH,
                        width: trackW * progress,
                        decoration: BoxDecoration(
                          color: teal,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    // 📦 pickup (left)
                    const Positioned(
                      left: 0,
                      top: 0,
                      child: Text('📦',
                          style: TextStyle(fontSize: endIconSize)),
                    ),
                    // 🏁 delivery (right)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: Text('🏁',
                          style: TextStyle(fontSize: endIconSize)),
                    ),
                    // 🏍️ courier (animated, miroir pour regarder à droite)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeInOut,
                      left: motoLeft,
                      top: 0,
                      child: Transform.scale(
                        scaleX: -1,
                        child: const Text('🏍️',
                            style: TextStyle(fontSize: motoSize)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const <Widget>[
              Text('Départ',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8))),
              Text('Arrivée',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8))),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.match,
    required this.trackNum,
    this.etaText,
    this.overridePrice,
  });
  final ParcelServiceMatch match;
  final String trackNum;
  final String? etaText;
  final double? overridePrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFEFFDF4), Color(0xFFF0FDF4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.12),
            child: Text(
              match.contactName.isNotEmpty
                  ? match.contactName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: Color(0xFF0F766E),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(match.contactName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 2),
                Text(match.vehicleLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    const Icon(Icons.tag_rounded,
                        size: 12, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text(trackNum,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 0.4)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(overridePrice ?? match.price).toStringAsFixed(0)} ${match.currency}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E)),
                ),
              ),
              if (etaText != null) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.schedule_rounded,
                          size: 12, color: Color(0xFFB45309)),
                      const SizedBox(width: 4),
                      Text(
                        etaText!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
    this.pulseAnim,
  });

  final _StatusStep step;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;
  final Animation<double>? pulseAnim;

  static const Color _teal = Color(0xFF0F766E);
  static const Color _slate = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final Color dotColor =
        isDone || isCurrent ? _teal : const Color(0xFFE2E8F0);
    final Color textColor =
        isDone || isCurrent ? const Color(0xFF0F172A) : _slate;
    final Color subColor = isDone || isCurrent ? const Color(0xFF475569) : _slate;

    Widget dot = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDone
            ? _teal
            : isCurrent
                ? _teal.withValues(alpha: 0.12)
                : const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
        border: isCurrent
            ? Border.all(color: _teal, width: 2)
            : Border.all(color: dotColor, width: 1.5),
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : Text(step.icon,
                style: TextStyle(
                    fontSize: isCurrent ? 16 : 14,
                    color: isCurrent ? null : Colors.transparent)),
      ),
    );

    if (pulseAnim != null) {
      dot = AnimatedBuilder(
        animation: pulseAnim!,
        builder: (_, Widget? child) => Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 36 + pulseAnim!.value * 12,
              height: 36 + pulseAnim!.value * 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _teal.withValues(alpha: pulseAnim!.value * 0.08),
              ),
            ),
            child!,
          ],
        ),
        child: dot,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 2),
                dot,
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isDone ? _teal : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: 6,
                bottom: isLast ? 0 : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(step.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor)),
                  const SizedBox(height: 2),
                  Text(step.sublabel,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: subColor)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.currentStep});

  final _ShipStep currentStep;

  @override
  Widget build(BuildContext context) {
    const List<String> labels = <String>[
      'Demande',
      'Choix',
      'Destinataire',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nouvel envoi',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Un parcours simple, étape par étape, pour lancer une demande d\'expédition.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: List<Widget>.generate(labels.length, (int index) {
            final bool isActive = index == currentStep.index;
            final bool isDone = index < currentStep.index;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.12),
                  accentColor.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentColor.withValues(alpha: 0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(icon, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0F766E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShipDetailField extends StatelessWidget {
  const _ShipDetailField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF0F766E), size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF14B8A6),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.canGoBack,
    required this.showContinueAction,
    required this.continueLabel,
    required this.compactContinueAction,
    required this.onBack,
    required this.onContinue,
    required this.isLoading,
  });

  final bool canGoBack;
  final bool showContinueAction;
  final String continueLabel;
  final bool compactContinueAction;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            mainAxisAlignment: compactContinueAction
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (canGoBack) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : onBack,
                    child: const Text('Retour'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (!showContinueAction)
                const SizedBox.shrink()
              else if (compactContinueAction)
                TextButton.icon(
                  onPressed: isLoading ? null : onContinue,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune_rounded, size: 18),
                  label: Text(continueLabel),
                )
              else
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: isLoading ? null : onContinue,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(continueLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Radar pending view ────────────────────────────────────────────────────────

class _RadarPendingView extends StatefulWidget {
  const _RadarPendingView({
    required this.scrollController,
    this.match,
    this.isSearching = false,
    this.onCancel,
    this.onTimeout,
  });

  static const int _kTimeoutSeconds = 30;

  /// null quand on est encore en phase de recherche (pas de driver trouvé)
  final ParcelServiceMatch? match;

  /// true : on cherche un livreur — false : on attend sa réponse
  final bool isSearching;
  final ScrollController scrollController;
  final VoidCallback? onCancel;
  final VoidCallback? onTimeout;

  @override
  State<_RadarPendingView> createState() => _RadarPendingViewState();
}

class _RadarPendingViewState extends State<_RadarPendingView>
    with SingleTickerProviderStateMixin {
  static const Color _teal = Color(0xFF0F766E);

  late final AnimationController _ctrl;
  late int _countdown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _countdown = _RadarPendingView._kTimeoutSeconds;
    // Searching : anneaux plus rapides pour traduire l'activité
    final int ms = widget.isSearching ? 1800 : 2600;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    )..repeat();
    // Countdown seulement en phase waiting (driver trouvé)
    if (!widget.isSearching && widget.onTimeout != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _countdown--);
        if (_countdown <= 0) {
          t.cancel();
          widget.onTimeout!();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildRing(double phase) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final double t = (_ctrl.value + phase) % 1.0;
        final double scale = 0.35 + t * 1.65;
        final double opacity = (0.55 * (1.0 - t)).clamp(0.0, 1.0);
        return Center(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _teal, width: 1.8),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom + 24;
    final bool searching = widget.isSearching;
    final String? name = widget.match?.contactName;
    final String initial =
        (name != null && name.isNotEmpty) ? name[0].toUpperCase() : '';

    return Expanded(
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, 32, 20, bottomPad),
        children: <Widget>[
          // ── Radar ─────────────────────────────────────────────────────────
          SizedBox(
            height: 200,
            child: Stack(
              children: <Widget>[
                _buildRing(0.0),
                _buildRing(0.33),
                _buildRing(0.67),
                Center(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, child) {
                      final double half = _ctrl.value < 0.5
                          ? _ctrl.value * 2
                          : (1.0 - _ctrl.value) * 2;
                      final double pulse =
                          searching ? 1.0 + 0.10 * half : 1.0 + 0.06 * half;
                      return Transform.scale(scale: pulse, child: child);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // Arc countdown (uniquement en mode waiting)
                        if (!searching && widget.onTimeout != null)
                          SizedBox(
                            width: 92,
                            height: 92,
                            child: CircularProgressIndicator(
                              value: _countdown /
                                  _RadarPendingView._kTimeoutSeconds,
                              strokeWidth: 2.5,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _teal,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _teal.withValues(alpha: 0.45),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: searching
                                // Icône générique pendant la recherche
                                ? const Icon(
                                    Icons.two_wheeler_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  )
                                // Initiale du driver une fois trouvé
                                : Text(
                                    initial,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Texte ─────────────────────────────────────────────────────────
          Text(
            searching ? 'Recherche en cours…' : 'En attente de',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: searching ? 20 : 14,
              fontWeight:
                  searching ? FontWeight.w700 : FontWeight.w500,
              color: searching
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF94A3B8),
              letterSpacing: searching ? -0.3 : 0,
            ),
          ),
          if (!searching && name != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            searching
                ? 'Nous cherchons le coursier disponible\nle plus proche de votre départ.'
                : 'Votre demande a été envoyée.\nLe coursier va répondre dans quelques instants.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),

          const SizedBox(height: 36),

          // ── Annuler ───────────────────────────────────────────────────────
          if (widget.onCancel != null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(
                      color: Color(0xFFDC2626), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  searching
                      ? 'Annuler la recherche'
                      : 'Annuler la demande',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mode auto panel ───────────────────────────────────────────────────────────

class _AutoModePanel extends StatelessWidget {
  const _AutoModePanel({
    required this.pickup,
    required this.delivery,
    required this.onOrder,
    this.durationText,
    this.proposedPrice,
    this.onPriceChanged,
    this.isLoading = false,
  });

  final _AddressPoint pickup;
  final _AddressPoint delivery;
  final String? durationText;
  final VoidCallback onOrder;
  final double? proposedPrice;
  final ValueChanged<double>? onPriceChanged;
  final bool isLoading;

  static const Color _teal = Color(0xFF0F766E);

  bool get _hasRoute =>
      pickup.lat != null &&
      pickup.lng != null &&
      delivery.lat != null &&
      delivery.lng != null;

  double get _estimatedPrice {
    if (!_hasRoute) return 0;
    final double distM = Geolocator.distanceBetween(
      pickup.lat!,
      pickup.lng!,
      delivery.lat!,
      delivery.lng!,
    );
    final double raw = 1000 + (distM / 1000 * 275);
    return ((raw / 100).ceil() * 100).toDouble();
  }

  double get _distanceKm {
    if (!_hasRoute) return 0;
    return Geolocator.distanceBetween(
          pickup.lat!,
          pickup.lng!,
          delivery.lat!,
          delivery.lng!,
        ) /
        1000;
  }

  String _formatPrice(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final bool ready = _hasRoute;
    final double price = _estimatedPrice;
    final double km = _distanceKm;

    final Widget panel = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: ready
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFFFFCF7), Color(0xFFF7FAFC)],
                )
              : null,
          color: ready ? null : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ready
                ? const Color(0xFFE7EBF2)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: ready
                  ? const Color(0x140F172A)
                  : const Color(0x0A0F172A),
              blurRadius: ready ? 24 : 12,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: ready
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Ligne départ → arrivée
                  Row(
                    children: <Widget>[
                      const Icon(Icons.my_location_rounded,
                          size: 14, color: _teal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pickup.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 2, bottom: 2),
                    child: Container(
                      width: 2,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9E2EC),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.flag_rounded,
                          size: 14, color: Color(0xFF6D28D9)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          delivery.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Pills distance + durée
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _InfoPill(
                        icon: Icons.straighten_rounded,
                        label: '${km.toStringAsFixed(1)} km',
                      ),
                      if (durationText != null) ...<Widget>[
                        const SizedBox(width: 6),
                        _InfoPill(
                          icon: Icons.schedule_rounded,
                          label: durationText!,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Prix proposé (ajustable)
                  _PriceAdjusterRow(
                    initialPrice: proposedPrice ?? price,
                    currency: 'XOF',
                    onChanged: onPriceChanged ?? (_) {},
                    showLabel: false,
                  ),
                  const SizedBox(height: 16),
                  // Bouton Commander
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0xFF172030), Color(0xFF243247)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x2A0F172A),
                            blurRadius: 16,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: isLoading ? null : onOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(Icons.auto_awesome_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Commander maintenant',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 10),
                  Text(
                    'Renseignez départ et arrivée pour voir le tarif',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
      ),
    );

    return panel;
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ajusteur de prix ──────────────────────────────────────────────────────────

class _PriceAdjusterRow extends StatefulWidget {
  const _PriceAdjusterRow({
    required this.initialPrice,
    required this.currency,
    required this.onChanged,
    this.step = 500.0,
    this.minPrice = 500.0,
    this.showLabel = true,
  });

  final double initialPrice;
  final String currency;
  final ValueChanged<double> onChanged;
  final double step;
  final double minPrice;
  final bool showLabel;

  @override
  State<_PriceAdjusterRow> createState() => _PriceAdjusterRowState();
}

class _PriceAdjusterRowState extends State<_PriceAdjusterRow> {
  static const Color _teal = Color(0xFF0F766E);

  late double _price;
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _price = widget.initialPrice;
    _ctrl = TextEditingController(text: _price.toInt().toString());
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_PriceAdjusterRow old) {
    super.didUpdateWidget(old);
    // Synchronise si la route change et que l'utilisateur n'est pas en train de saisir
    if (old.initialPrice != widget.initialPrice && !_focusNode.hasFocus) {
      _setPrice(widget.initialPrice, notify: false);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commitEdit();
    setState(() => _editing = _focusNode.hasFocus);
  }

  void _setPrice(double v, {bool notify = true}) {
    final double clamped = v.clamp(widget.minPrice, 9999999);
    final double rounded = ((clamped / 100).round() * 100).toDouble();
    setState(() {
      _price = rounded;
      if (!_focusNode.hasFocus) _ctrl.text = rounded.toInt().toString();
    });
    if (notify) widget.onChanged(rounded);
  }

  void _adjust(double delta) => _setPrice(_price + delta);

  void _commitEdit() {
    final String raw = _ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final double? parsed = double.tryParse(raw);
    if (parsed != null && parsed > 0) {
      _setPrice(parsed);
    } else {
      _ctrl.text = _price.toInt().toString();
    }
  }

  String _format(double v) {
    final String s = v.toInt().toString();
    final StringBuffer buf = StringBuffer();
    final int rem = s.length % 3;
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (i - rem) % 3 == 0) buf.write('\u202F');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.showLabel) ...<Widget>[
          const Text(
            'PRIX PROPOSÉ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB2DDD7)),
          ),
          child: Row(
            children: <Widget>[
              _AdjButton(
                icon: Icons.remove_rounded,
                onTap: () => _adjust(-widget.step),
                filled: false,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  behavior: HitTestBehavior.opaque,
                  child: _editing
                      ? TextField(
                          controller: _ctrl,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _teal,
                            letterSpacing: -0.3,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '${_format(_price)} ${widget.currency}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _teal,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                ),
              ),
              _AdjButton(
                icon: Icons.add_rounded,
                onTap: () => _adjust(widget.step),
                filled: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdjButton extends StatelessWidget {
  const _AdjButton({
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  static const Color _teal = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? _teal : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: filled ? null : Border.all(color: const Color(0xFFCBD5E1)),
          boxShadow: filled
              ? <BoxShadow>[
                  BoxShadow(
                    color: _teal.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : const Color(0xFF475569),
        ),
      ),
    );
  }
}
