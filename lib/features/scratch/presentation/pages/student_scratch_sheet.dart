import 'dart:math';

import 'package:flutter/material.dart';
import 'package:scratcher/scratcher.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Affiche la carte à gratter étudiante et retourne la récompense tirée,
/// ou null si l'utilisateur ferme sans gratter.
Future<RewardConfig?> showStudentScratchSheet(
  BuildContext context, {
  required ScratchCampaign campaign,
  required String matricule,
}) {
  final RewardConfig? reward = _drawReward(campaign.rewardsPool);
  return showModalBottomSheet<RewardConfig?>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _StudentScratchSheet(reward: reward, matricule: matricule),
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

const Color _kTeal = Color(0xFF00897B);
const Color _kGold = Color(0xFFCBA135);
const Color _kCardBg = Color(0xFF1A3A5C);

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _StudentScratchSheet extends StatefulWidget {
  const _StudentScratchSheet({
    required this.reward,
    required this.matricule,
  });

  final RewardConfig? reward;
  final String matricule;

  @override
  State<_StudentScratchSheet> createState() => _StudentScratchSheetState();
}

class _StudentScratchSheetState extends State<_StudentScratchSheet> {
  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();
  bool _revealed = false;

  void _onThreshold() {
    if (_revealed) return;
    setState(() => _revealed = true);
    _scratcherKey.currentState?.reveal(duration: const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D9E6),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _kTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.school_rounded, color: _kTeal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Carte étudiante',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF10233E)),
                        ),
                        Text(
                          'Matricule : ${widget.matricule}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7A90)),
                        ),
                      ],
                    ),
                  ),
                  // Fermer uniquement après révélation
                  if (_revealed)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(widget.reward),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF6B7A90)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Scratch card
              SizedBox(
                width: double.infinity,
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Scratcher(
                    key: _scratcherKey,
                    brushSize: 40,
                    threshold: 40,
                    color: _kGold,
                    onChange: (value) { if (value > 10 && !_revealed) _onThreshold(); },
                    onThreshold: _onThreshold,
                    child: _CardContent(reward: widget.reward, revealed: _revealed),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (!_revealed)
                Text(
                  'Gratte la carte pour découvrir ta récompense',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).pop(widget.reward),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(
                      widget.reward == null || widget.reward!.isNothing
                          ? 'Continuer'
                          : 'Appliquer ma récompense',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card content (derrière le grattage) ───────────────────────────────────────

class _CardContent extends StatelessWidget {
  const _CardContent({required this.reward, required this.revealed});

  final RewardConfig? reward;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final bool hasReward = reward != null && !reward!.isNothing;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasReward
              ? [_kCardBg, const Color(0xFF0D2137)]
              : [const Color(0xFF374151), const Color(0xFF1F2937)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasReward ? Icons.emoji_events_rounded : Icons.sentiment_neutral_rounded,
              color: hasReward ? _kGold : Colors.white30,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              hasReward ? reward!.label : 'Pas de chance',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasReward ? Colors.white : Colors.white38,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (hasReward && reward!.value != null) ...[
              const SizedBox(height: 4),
              Text(
                'Réduction : ${reward!.value!.toStringAsFixed(0)} XOF',
                style: TextStyle(
                  color: _kGold.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
