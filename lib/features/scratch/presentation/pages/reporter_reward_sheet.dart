import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scratcher/scratcher.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';
import 'package:govipservices/features/wallet/data/wallet_service.dart';

// ── Public API ────────────────────────────────────────────────────────────────

Future<RewardConfig?> showReporterRewardSheet(
  BuildContext context, {
  required ScratchCampaign campaign,
  int? tripPrice,
}) {
  final RewardConfig? reward = _drawReward(campaign.rewardsPool, tripPrice);
  return showModalBottomSheet<RewardConfig?>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReporterRewardSheet(reward: reward, tripPrice: tripPrice),
  );
}

// ── Weighted random ───────────────────────────────────────────────────────────

/// Si tripPrice est fourni, la récompense de type 'trip_price' prend sa valeur.
RewardConfig? _drawReward(List<RewardConfig> pool, int? tripPrice) {
  final List<RewardConfig> eligible = pool.where((r) => r.weight > 0).toList();
  if (eligible.isEmpty) return null;
  final int total = eligible.fold(0, (acc, r) => acc + r.weight);
  if (total <= 0) return null;
  int rand = Random().nextInt(total);
  for (final RewardConfig r in eligible) {
    rand -= r.weight;
    if (rand < 0) {
      // Si la récompense est de type trip_price, on remplace la value par tripPrice
      if (r.type == 'trip_price' && tripPrice != null) {
        return RewardConfig(
          id: r.id,
          type: r.type,
          label: r.label,
          weight: r.weight,
          value: tripPrice.toDouble(),
        );
      }
      return r;
    }
  }
  return eligible.last;
}

// ── Colors ────────────────────────────────────────────────────────────────────

const Color _kTeal = Color(0xFF14B8A6);
const Color _kTealDark = Color(0xFF0F766E);
const Color _kNavy = Color(0xFF0D1B2A);
const Color _kNavyMid = Color(0xFF152536);
const Color _kGold = Color(0xFFCBA135);

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _ReporterRewardSheet extends StatefulWidget {
  const _ReporterRewardSheet({required this.reward, this.tripPrice});
  final RewardConfig? reward;
  final int? tripPrice;

  @override
  State<_ReporterRewardSheet> createState() => _ReporterRewardSheetState();
}

class _ReporterRewardSheetState extends State<_ReporterRewardSheet>
    with TickerProviderStateMixin {
  bool _scratchVisible = false;
  bool _revealed = false;
  bool _crediting = false;

  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final AnimationController _switchCtrl;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _switchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _switchCtrl.dispose();
    super.dispose();
  }

  void _onRevealTap() async {
    await _switchCtrl.forward();
    if (mounted) setState(() => _scratchVisible = true);
  }

  void _onThreshold() {
    if (_revealed) return;
    setState(() => _revealed = true);
    _scratcherKey.currentState?.reveal(duration: const Duration(milliseconds: 500));
    _creditWallet();
  }

  Future<void> _creditWallet() async {
    final RewardConfig? reward = widget.reward;
    if (reward == null || reward.isNothing || reward.value == null) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final int amount = reward.effectiveDiscount(totalAmount: widget.tripPrice);
    if (amount <= 0) return;

    setState(() => _crediting = true);
    try {
      await WalletService.instance.creditReporterReward(
        uid: uid,
        amount: amount,
        tripRoute: widget.tripPrice != null ? 'Trajet ${widget.tripPrice} XOF' : 'GO Radar',
      );
    } catch (e) {
      debugPrint('[ReporterReward] wallet credit error: $e');
    } finally {
      if (mounted) setState(() => _crediting = false);
    }
  }

  void _showHowToRecover() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _kNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _kTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.help_outline_rounded, color: _kTeal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Comment récupérer ?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _HowToStep(
                number: '1',
                text: 'Sur l\'accueil, appuie sur l\'icône menu en haut',
                icon: Icons.menu_rounded,
              ),
              const SizedBox(height: 12),
              _HowToStep(
                number: '2',
                text: 'Clique sur "Portefeuille"',
                icon: Icons.account_balance_wallet_rounded,
              ),
              const SizedBox(height: 12),
              _HowToStep(
                number: '3',
                text: 'Appuie sur "Transférer" et entre ton numéro Wave',
                icon: Icons.send_rounded,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Compris !', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: _scratchVisible ? _buildScratchView() : _buildThankYouView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Vue remerciement ────────────────────────────────────────────────────────

  Widget _buildThankYouView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _kTeal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kTeal.withValues(alpha: 0.35), width: 1.5),
          ),
          child: const Icon(Icons.radar_rounded, color: _kTeal, size: 34),
        ),
        const SizedBox(height: 20),
        const Text(
          'Merci pour ta contribution !',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Grâce à toi, les voyageurs ont pu suivre ce trajet en temps réel.\nVoici une récompense pour te remercier.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5), height: 1.5),
        ),
        if (widget.tripPrice != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _kGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Prix du trajet : ${widget.tripPrice} XOF',
              style: const TextStyle(fontSize: 13, color: _kGold, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.card_giftcard_rounded, color: _kGold.withValues(alpha: 0.6), size: 18),
            ),
            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _onRevealTap,
            style: FilledButton.styleFrom(
              backgroundColor: _kTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            icon: const Icon(Icons.stars_rounded, size: 20),
            label: const Text('Obtenir ma récompense'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Plus tard', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3))),
        ),
      ],
    );
  }

  // ── Vue carte à gratter ─────────────────────────────────────────────────────

  Widget _buildScratchView() {
    final bool hasReward = widget.reward != null && !widget.reward!.isNothing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(),
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _kGold.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.stars_rounded, color: _kGold, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ta surprise t\'attend !',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  Text(
                    'Gratte et découvre ta récompense',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Carte à gratter
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Scratcher(
                  key: _scratcherKey,
                  brushSize: 46,
                  threshold: 60,
                  color: _kGold,
                  onChange: (v) { if (v > 60 && !_revealed) _onThreshold(); },
                  onThreshold: _onThreshold,
                  child: _CardContent(reward: widget.reward, tripPrice: widget.tripPrice),
                ),
              ),
            ),
            if (!_revealed)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded, size: 13, color: _kNavy.withValues(alpha: 0.4)),
                      const SizedBox(width: 4),
                      Text(
                        'Grattez ici',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kNavy.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),

        if (!_revealed)
          Text(
            'Glissez votre doigt sur la carte dorée',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3)),
          )
        else ...[
          Text(
            hasReward ? 'Récompense créditée sur ton portefeuille !' : 'Pas de chance cette fois...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: hasReward ? _kGold : Colors.white38,
            ),
          ),
          if (hasReward) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showHowToRecover,
              child: Text(
                'Comment récupérer ma récompense ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _kTeal.withValues(alpha: 0.8),
                  decoration: TextDecoration.underline,
                  decorationColor: _kTeal.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _crediting ? null : () => Navigator.of(context).pop(widget.reward),
              style: FilledButton.styleFrom(
                backgroundColor: hasReward ? _kTealDark : Colors.white10,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: _crediting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(hasReward ? 'Super, merci !' : 'Continuer'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _handle() => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
        ),
      );
}

// ── Step popup ────────────────────────────────────────────────────────────────

class _HowToStep extends StatelessWidget {
  const _HowToStep({required this.number, required this.text, required this.icon});
  final String number;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _kTeal.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kTeal),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75), height: 1.4),
          ),
        ),
      ],
    );
  }
}

// ── Card content ──────────────────────────────────────────────────────────────

class _CardContent extends StatelessWidget {
  const _CardContent({required this.reward, this.tripPrice});
  final RewardConfig? reward;
  final int? tripPrice;

  @override
  Widget build(BuildContext context) {
    final bool hasReward = reward != null && !reward!.isNothing;
    // Pour discount_percent : montant réel = tripPrice * value / 100
    final int? computedAmount = hasReward && reward!.value != null
        ? reward!.effectiveDiscount(totalAmount: tripPrice)
        : null;
    final double? displayValue = computedAmount != null && computedAmount > 0
        ? computedAmount.toDouble()
        : null;

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
          if (hasReward) ..._dots(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: hasReward ? _kGold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasReward ? _kGold.withValues(alpha: 0.35) : Colors.white12,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    hasReward ? Icons.emoji_events_rounded : Icons.sentiment_neutral_rounded,
                    color: hasReward ? _kGold : Colors.white24,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  hasReward ? reward!.label : 'Pas de chance',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasReward ? Colors.white : Colors.white30,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                if (hasReward && displayValue != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: _kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: _kGold.withValues(alpha: 0.45), width: 1.5),
                    ),
                    child: Text(
                      reward!.isPercent
                          ? '${reward!.value!.toStringAsFixed(0)}% = +${displayValue.toStringAsFixed(0)} XOF'
                          : '+${displayValue.toStringAsFixed(0)} XOF',
                      style: const TextStyle(
                        color: _kGold,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Crédité sur ton portefeuille',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _dots() {
    final rng = Random(13);
    return List.generate(10, (i) {
      final double x = rng.nextDouble() * 340;
      final double y = rng.nextDouble() * 220;
      final double size = 2.5 + rng.nextDouble() * 4.5;
      final double opacity = 0.08 + rng.nextDouble() * 0.18;
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
