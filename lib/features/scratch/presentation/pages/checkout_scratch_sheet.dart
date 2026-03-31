import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:scratcher/scratcher.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';

// ── Public API ────────────────────────────────────────────────────────────────

Future<RewardConfig?> showCheckoutScratchSheet(
  BuildContext context, {
  required ScratchCampaign campaign,
  bool waveBadge = false,
}) {
  final RewardConfig? reward = _drawReward(campaign.rewardsPool);
  return showModalBottomSheet<RewardConfig?>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _CheckoutScratchSheet(reward: reward, waveBadge: waveBadge),
  );
}

// ── Weighted random ───────────────────────────────────────────────────────────

RewardConfig? _drawReward(List<RewardConfig> pool) {
  final List<RewardConfig> eligible = pool.where((r) => r.weight > 0).toList();
  if (eligible.isEmpty) return null;
  final int total = eligible.fold(0, (acc, r) => acc + r.weight);
  if (total <= 0) return null;
  int rand = Random().nextInt(total);
  for (final RewardConfig r in eligible) {
    rand -= r.weight;
    if (rand < 0) return r;
  }
  return eligible.last;
}

// ── Colors ────────────────────────────────────────────────────────────────────

const Color _kGold = Color(0xFFCBA135);
const Color _kNavy = Color(0xFF0D1B2A);
const Color _kNavyMid = Color(0xFF152536);

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _CheckoutScratchSheet extends StatefulWidget {
  const _CheckoutScratchSheet({required this.reward, this.waveBadge = false});
  final RewardConfig? reward;
  final bool waveBadge;

  @override
  State<_CheckoutScratchSheet> createState() => _CheckoutScratchSheetState();
}

class _CheckoutScratchSheetState extends State<_CheckoutScratchSheet>
    with TickerProviderStateMixin {
  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();
  bool _revealed = false;

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  late final AnimationController _countdownCtrl;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _countdownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _countdownCtrl.dispose();
    super.dispose();
  }

  void _onThreshold() {
    if (_revealed) return;
    setState(() => _revealed = true);
    _scratcherKey.currentState?.reveal(duration: const Duration(milliseconds: 500));
    _countdownCtrl.forward().then((_) {
      if (mounted) Navigator.of(context).pop(widget.reward);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: Container(
          decoration: const BoxDecoration(
            color: _kNavy,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  _buildHeader(),
                  const SizedBox(height: 28),
                  _buildScratchCard(),
                  const SizedBox(height: 20),
                  _buildBottom(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Badge Wave (si paiement Wave)
        if (widget.waveBadge) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF1A56DB).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1A56DB).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(
                    'assets/wave.jpg',
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.waves_rounded,
                      color: Color(0xFF1A56DB),
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Bonus paiement Wave',
                  style: TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kGold.withValues(alpha: 0.35), width: 1.5),
          ),
          child: const Icon(Icons.stars_rounded, color: _kGold, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          widget.waveBadge ? 'Récompense Wave !' : 'Ta surprise t\'attend !',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.waveBadge
              ? 'Gratte et découvre ta réduction sur cette réservation'
              : 'Gratte et découvre ta récompense exclusive',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.45)),
        ),
      ],
    );
  }

  Widget _buildScratchCard() {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 230,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Scratcher(
              key: _scratcherKey,
              brushSize: 46,
              threshold: 40,
              color: _kGold,
              onChange: (value) {
                if (value > 10 && !_revealed) _onThreshold();
              },
              onThreshold: _onThreshold,
              child: _CardContent(reward: widget.reward),
            ),
          ),
        ),
        // Hint "Grattez" sur la couche or — passe les touches au Scratcher
        if (!_revealed)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 14, color: _kNavy.withValues(alpha: 0.45)),
                  const SizedBox(width: 5),
                  Text(
                    'Grattez ici',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kNavy.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottom() {
    if (!_revealed) {
      return Text(
        'Glissez votre doigt sur la carte dorée',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
      );
    }

    final bool hasReward = widget.reward != null && !widget.reward!.isNothing;

    return Column(
      children: [
        Text(
          hasReward
              ? 'Réduction appliquée automatiquement !'
              : 'Pas de chance cette fois...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: hasReward ? _kGold : Colors.white38,
          ),
        ),
        const SizedBox(height: 14),
        AnimatedBuilder(
          animation: _countdownCtrl,
          builder: (context, _) {
            final int remaining = (4 * (1 - _countdownCtrl.value)).ceil().clamp(0, 4);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: 1 - _countdownCtrl.value,
                    strokeWidth: 2,
                    color: Colors.white24,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Fermeture dans ${remaining}s',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── Card content (derrière la couche or) ──────────────────────────────────────

class _CardContent extends StatelessWidget {
  const _CardContent({required this.reward});
  final RewardConfig? reward;

  @override
  Widget build(BuildContext context) {
    final bool hasReward = reward != null && !reward!.isNothing;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasReward
              ? [_kNavy, _kNavyMid, const Color(0xFF0D2137)]
              : [const Color(0xFF1F2937), const Color(0xFF111827)],
        ),
      ),
      child: Stack(
        children: [
          // Points décoratifs dorés
          if (hasReward) ..._starDots(),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icône dans un cercle
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: hasReward
                        ? _kGold.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasReward
                          ? _kGold.withValues(alpha: 0.35)
                          : Colors.white12,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    hasReward ? Icons.emoji_events_rounded : Icons.sentiment_neutral_rounded,
                    color: hasReward ? _kGold : Colors.white24,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  hasReward ? reward!.label : 'Pas de chance',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasReward ? Colors.white : Colors.white30,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),

                if (hasReward && reward!.value != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _kGold.withValues(alpha: 0.45), width: 1.5),
                    ),
                    child: Text(
                      '-${reward!.value!.toStringAsFixed(0)} XOF',
                      style: const TextStyle(
                        color: _kGold,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Petits points dorés dispersés en fond — graine fixe pour cohérence.
  List<Widget> _starDots() {
    final rng = Random(7);
    return List.generate(10, (i) {
      final double x = rng.nextDouble() * 340;
      final double y = rng.nextDouble() * 230;
      final double size = 2.5 + rng.nextDouble() * 4.5;
      final double opacity = 0.1 + rng.nextDouble() * 0.22;
      return Positioned(
        left: x,
        top: y,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        ),
      );
    });
  }
}
