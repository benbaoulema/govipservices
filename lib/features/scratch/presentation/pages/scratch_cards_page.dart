import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scratcher/scratcher.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';
import 'package:govipservices/features/scratch/presentation/state/scratch_cubit.dart';

const Color _kBg = Color(0xFFF1F5F9);
const Color _kTeal = Color(0xFF0F766E);
const Color _kGold = Color(0xFFD97706);
const Color _kFoil = Color(0xFFCBA135);

class ScratchCardsPage extends StatefulWidget {
  const ScratchCardsPage({super.key});

  @override
  State<ScratchCardsPage> createState() => _ScratchCardsPageState();
}

class _ScratchCardsPageState extends State<ScratchCardsPage> {
  late final ScratchCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ScratchCubit();
    _cubit.addListener(_onChanged);
  }

  @override
  void dispose() {
    _cubit.removeListener(_onChanged);
    _cubit.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final String? err = _cubit.error;
    if (err != null) {
      _cubit.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red[700]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool empty =
        _cubit.pendingCards.isEmpty && _cubit.revealedCards.isEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Cartes à gratter',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _cubit.isLoading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : RefreshIndicator(
              onRefresh: _cubit.load,
              color: _kTeal,
              child: empty
                  ? _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                      children: <Widget>[
                        // Cartes pending (à gratter)
                        ...List<Widget>.generate(
                          _cubit.pendingCards.length,
                          (int i) {
                            final UserScratchCard card = _cubit.pendingCards[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _ScratchCard(
                                key: ValueKey(card.id),
                                card: card,
                                cubit: _cubit,
                                isRevealed: false,
                              )
                                  .animate()
                                  .fadeIn(delay: Duration(milliseconds: i * 100))
                                  .slideY(begin: 0.07),
                            );
                          },
                        ),
                        // Cartes révélées (historique)
                        ...List<Widget>.generate(
                          _cubit.revealedCards.length,
                          (int i) {
                            final UserScratchCard card =
                                _cubit.revealedCards[i];
                            final bool isUsed = card.rewardId != null &&
                                !_cubit.availableRewards
                                    .any((r) => r.id == card.rewardId);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: _ScratchCard(
                                key: ValueKey(card.id),
                                card: card,
                                cubit: _cubit,
                                isRevealed: true,
                                isUsed: isUsed,
                              )
                                  .animate()
                                  .fadeIn(
                                      delay: Duration(
                                          milliseconds:
                                              (_cubit.pendingCards.length + i) *
                                                  100))
                                  .slideY(begin: 0.07),
                            );
                          },
                        ),
                      ],
                    ),
            ),
    );
  }
}

// ── Carte ─────────────────────────────────────────────────────────────────────

class _ScratchCard extends StatefulWidget {
  const _ScratchCard({
    required Key key,
    required this.card,
    required this.cubit,
    required this.isRevealed,
    this.isUsed = false,
  }) : super(key: key);

  final UserScratchCard card;
  final ScratchCubit cubit;
  final bool isRevealed;
  final bool isUsed;

  @override
  State<_ScratchCard> createState() => _ScratchCardState();
}

class _ScratchCardState extends State<_ScratchCard> {
  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();
  bool _localRevealed = false;
  bool _loading = false;
  bool _dismissing = false;
  bool _scratchStarted = false;
  RevealResult? _result;

  bool get _showRevealed => widget.isRevealed || _localRevealed;

  Future<void> _onThreshold() async {
    if (_loading || _localRevealed) return;
    setState(() => _loading = true);

    // Efface le voile restant progressivement
    _scratcherKey.currentState?.reveal(
      duration: const Duration(milliseconds: 5000),
    );
    await Future.delayed(const Duration(milliseconds: 5000));
    if (!mounted) return;

    // Appel API
    final RevealResult? result = await widget.cubit.revealCard(widget.card.id);
    if (!mounted) return;

    setState(() {
      _loading = false;
      _localRevealed = true;
      _result = result;
    });

    // Rien gagné → disparaît après 5 sec
    if (result == null || result.isNothing) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _dismissing = true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await widget.cubit.refresh();
    }
    // Cadeau → reste (historique)
  }

  Future<void> _showRewardSheet() async {
    final String? rewardId = _result?.rewardId ?? widget.card.rewardId;
    if (rewardId == null) return;

    ScratchCampaign? campaign;
    try {
      campaign = await ScratchService.instance
          .fetchCampaignById(widget.card.campaignId);
    } catch (_) {}

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RewardSheet(
        rewardId: rewardId,
        label: _result?.rewardLabel ?? widget.card.rewardLabel ?? '',
        value: _result?.rewardValue ?? widget.card.rewardValue,
        isUsed: widget.isUsed,
        expiresAt: widget.card.expiresAt,
        departureLocation: campaign?.departureLocation,
        arrivalLocation: campaign?.arrivalLocation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _dismissing ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 600),
      child: _showRevealed
          ? GestureDetector(
              onTap: _showRewardSheet,
              child: _CardRevealed(
                card: widget.card,
                result: _result,
                isUsed: widget.isUsed,
              ),
            )
          : Stack(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Scratcher(
                    key: _scratcherKey,
                    brushSize: 44,
                    threshold: 60,
                    color: _kFoil,
                    onChange: (double p) {
                      if (!_scratchStarted && p > 0) {
                        setState(() => _scratchStarted = true);
                      }
                    },
                    onThreshold: _onThreshold,
                    child: _CardBase(
                      child: _loading
                          ? const _LoadingDots()
                          : _HintContent(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: (_scratchStarted || _loading) ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 350),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: const _GratteOverlay(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Carte révélée (sans Scratcher) ────────────────────────────────────────────

class _CardRevealed extends StatelessWidget {
  const _CardRevealed({
    required this.card,
    required this.isUsed,
    this.result,
  });

  final UserScratchCard card;
  final RevealResult? result;
  final bool isUsed;

  String get _label =>
      result?.rewardLabel ?? card.rewardLabel ?? '';

  double? get _value =>
      result?.rewardValue ?? card.rewardValue;

  bool get _isNothing =>
      (result?.isNothing ?? false) ||
      (card.rewardType == 'nothing') ||
      _label.isEmpty;

  @override
  Widget build(BuildContext context) {
    return _CardBase(
      dimmed: isUsed,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxHeight <= 128;
          final double eyebrowFontSize = compact ? 11 : 12;
          final double titleFontSize = compact ? 17 : 20;
          final double valueFontSize = compact ? 13 : 14;
          final double metaFontSize = compact ? 10 : 11;
          final double titleGap = compact ? 4 : 5;
          final double valueTop = compact ? 2 : 4;
          final double metaGap = compact ? 8 : 10;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Text(
                _isNothing
                    ? 'Pas de chance cette fois'
                    : '🎉 Vous avez gagné',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isNothing ? Colors.white38 : _kGold,
                  fontSize: eyebrowFontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: titleGap),
              Text(
                _isNothing ? 'Aucune récompense' : _label,
                style: TextStyle(
                  color: _isNothing ? Colors.white38 : Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: compact ? 1.05 : 1.1,
                ),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!_isNothing) ...<Widget>[
                if (_value != null)
                  Padding(
                    padding: EdgeInsets.only(top: valueTop),
                    child: Text(
                      '${_value!.toStringAsFixed(0)} XOF',
                      style: TextStyle(
                        color: _kGold.withValues(alpha: 0.85),
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                SizedBox(height: metaGap),
                Wrap(
                  spacing: 10,
                  runSpacing: compact ? 4 : 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _StatusBadge(isUsed: isUsed, compact: compact),
                    if (card.expiresAt != null)
                      Text(
                        'Expire ${_fmt(card.expiresAt!)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: metaFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06);
  }
}

// ── Contenu hint (avant grattage) ─────────────────────────────────────────────

class _HintContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        // Ligne décorative or
        Row(
          children: <Widget>[
            Container(width: 20, height: 1, color: const Color(0xFFD4AF37)),
            const SizedBox(width: 8),
            Text(
              'CARTE PRIVILÈGE',
              style: TextStyle(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Titre principal
        const Text(
          'Votre\nrécompense',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        // Instruction grattage
        Row(
          children: <Widget>[
            Icon(
              Icons.back_hand_outlined,
              color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
              size: 13,
            ),
            const SizedBox(width: 6),
            Text(
              'Grattez pour révéler',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Overlay avant grattage ────────────────────────────────────────────────────

class _GratteOverlay extends StatelessWidget {
  const _GratteOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFD4AF37),
            Color(0xFFEDD060),
            Color(0xFFB8860B),
            Color(0xFFD4AF37),
          ],
          stops: <double>[0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -35, right: -35,
            child: _Bubble(size: 110, opacity: 0.18),
          ),
          Positioned(
            bottom: -45, left: -20,
            child: _Bubble(size: 95, opacity: 0.12),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.back_hand_outlined,
                  color: Colors.white.withValues(alpha: 0.85),
                  size: 34,
                ),
                const SizedBox(height: 10),
                const Text(
                  'GRATTE-MOI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.5,
                    shadows: <Shadow>[
                      Shadow(
                        color: Color(0x50000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'pour révéler votre récompense',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fond commun de la carte ───────────────────────────────────────────────────

class _CardBase extends StatelessWidget {
  const _CardBase({required this.child, this.dimmed = false});
  final Widget child;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dimmed
              ? const <Color>[Color(0xFF2D3748), Color(0xFF1A2535)]
              : const <Color>[Color(0xFF1A2540), Color(0xFF0D3352)],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2A000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -40, right: -40,
            child: _Bubble(size: 150, opacity: 0.05),
          ),
          Positioned(
            bottom: -50, left: -20,
            child: _Bubble(size: 130, opacity: 0.04),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _GvipBadge(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

// ── Badge statut ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isUsed, this.compact = false});
  final bool isUsed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isUsed
            ? Colors.white.withValues(alpha: 0.08)
            : _kTeal.withValues(alpha: 0.25),
        border: Border.all(
          color: isUsed
              ? Colors.white.withValues(alpha: 0.15)
              : _kTeal.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        isUsed ? 'Utilisé' : 'Disponible',
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: isUsed
              ? Colors.white38
              : const Color(0xFF5EEAD4),
        ),
      ),
    );
  }
}

// ── Loading dots ──────────────────────────────────────────────────────────────

class _LoadingDots extends StatelessWidget {
  const _LoadingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(3, (int i) {
        return Container(
          margin: const EdgeInsets.only(right: 6),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        )
            .animate(onPlay: (ctrl) => ctrl.repeat())
            .fadeIn(delay: Duration(milliseconds: i * 150))
            .then()
            .fadeOut();
      }),
    );
  }
}

// ── Widgets utilitaires ───────────────────────────────────────────────────────

class _GvipBadge extends StatelessWidget {
  const _GvipBadge();

  @override
  Widget build(BuildContext context) {
    final Color gold = const Color(0xFFD4AF37);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withValues(alpha: 0.45)),
        color: gold.withValues(alpha: 0.1),
      ),
      child: Text(
        'GVIP',
        style: TextStyle(
          color: gold,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

// ── Bottom sheet récompense ───────────────────────────────────────────────────

class _RewardSheet extends StatefulWidget {
  const _RewardSheet({
    required this.rewardId,
    required this.label,
    required this.isUsed,
    this.value,
    this.expiresAt,
    this.departureLocation,
    this.arrivalLocation,
  });

  final String rewardId;
  final String label;
  final double? value;
  final bool isUsed;
  final DateTime? expiresAt;
  final String? departureLocation;
  final String? arrivalLocation;

  @override
  State<_RewardSheet> createState() => _RewardSheetState();
}

class _RewardSheetState extends State<_RewardSheet> {
  @override
  Widget build(BuildContext context) {
    final bool hasValue = widget.value != null;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, 24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Pill
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Icône trophée
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFFD4AF37),
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          // Label
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (hasValue) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '${widget.value!.toStringAsFixed(0)} XOF',
              style: TextStyle(
                color: _kGold.withValues(alpha: 0.85),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Séparateur
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          // Trajet si défini
          if (widget.departureLocation != null && widget.arrivalLocation != null) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.route_rounded, size: 14, color: Colors.white.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
                Text(
                  'Utilisable sur ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    '${widget.departureLocation} → ${widget.arrivalLocation}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Statut + expiration
          Row(
            children: <Widget>[
              _StatusBadge(isUsed: widget.isUsed),
              if (widget.expiresAt != null) ...<Widget>[
                const SizedBox(width: 12),
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 4),
                Text(
                  'Expire le ${_fmt(widget.expiresAt!)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
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

// ── État vide ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: Column(
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 32,
                  color: _kTeal,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Aucune carte disponible',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Effectuez une réservation pour\nobtenir une carte à gratter.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmt(DateTime dt) {
  final List<String> m = <String>[
    'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
    'juil', 'août', 'sep', 'oct', 'nov', 'déc',
  ];
  return '${dt.day} ${m[dt.month - 1]}';
}
