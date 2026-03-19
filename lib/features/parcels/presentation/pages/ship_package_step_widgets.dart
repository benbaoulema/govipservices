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

/// Statut simplifié côté sender (différent de _RunStatus qui est côté livreur).
enum _SenderRequestStatus {
  pending,      // provider_notified
  accepted,     // accepted
  enRoute,      // en_route_to_pickup
  pickedUp,     // picked_up
  delivered;    // delivered

  static _SenderRequestStatus fromFirestore(String? value) {
    switch (value) {
      case 'accepted':           return _SenderRequestStatus.accepted;
      case 'en_route_to_pickup': return _SenderRequestStatus.enRoute;
      case 'picked_up':          return _SenderRequestStatus.pickedUp;
      case 'delivered':          return _SenderRequestStatus.delivered;
      default:                   return _SenderRequestStatus.pending;
    }
  }

  bool get isFinal => this == _SenderRequestStatus.delivered;
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
    status: _SenderRequestStatus.pickedUp,
    icon: '📦',
    label: 'Colis récupéré',
    sublabel: 'Votre colis est en route vers la destination.',
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
    this.etaText,
  });

  final ParcelServiceMatch match;
  final String trackNum;
  final _SenderRequestStatus status;
  final VoidCallback onClose;
  final ScrollController scrollController;
  final String? etaText;

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

  int get _currentIndex =>
      _kStatusSteps.indexWhere((s) => s.status == widget.status);

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom + 24;
    return Expanded(
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
        children: <Widget>[
          _CourierProgressTrack(status: widget.status),
          const SizedBox(height: 12),
          _DriverCard(
            match: widget.match,
            trackNum: widget.trackNum,
            etaText: widget.etaText,
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
                  isCurrent && !widget.status.isFinal ? _pulseAnim : null,
            );
          }),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: widget.status.isFinal
                ? FilledButton.icon(
                    onPressed: widget.onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Fermer',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  )
                : OutlinedButton(
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
      case _SenderRequestStatus.pickedUp:  return 0.72;
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
  });
  final ParcelServiceMatch match;
  final String trackNum;
  final String? etaText;

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
                  '${match.price.toStringAsFixed(0)} ${match.currency}',
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
