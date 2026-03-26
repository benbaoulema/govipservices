import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:scratcher/scratcher.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';

const Color _kGold = Color(0xFFD97706);
const Color _kFoil = Color(0xFFCBA135);
const Color _kTeal = Color(0xFF0F766E);

/// Sheet lancement — fonctionne en mode authentifié et non-authentifié.
/// [card] est null quand l'utilisateur n'est pas connecté.
Future<void> showScratchLaunchSheet(
  BuildContext context, {
  UserScratchCard? card,
  required bool isAuthenticated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ScratchLaunchSheet(
      card: card,
      isAuthenticated: isAuthenticated,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _ScratchLaunchSheet extends StatefulWidget {
  const _ScratchLaunchSheet({
    required this.isAuthenticated,
    this.card,
  });
  final UserScratchCard? card;
  final bool isAuthenticated;

  @override
  State<_ScratchLaunchSheet> createState() => _ScratchLaunchSheetState();
}

class _ScratchLaunchSheetState extends State<_ScratchLaunchSheet> {
  final GlobalKey<ScratcherState> _scratcherKey = GlobalKey<ScratcherState>();

  bool _scratchStarted = false;
  bool _loading = false;
  bool _revealed = false;
  bool _showAuthCta = false;
  RevealResult? _result;

  void _onScratchStart() {
    if (!widget.isAuthenticated) {
      setState(() => _showAuthCta = true);
      return;
    }
    setState(() => _scratchStarted = true);
  }

  Future<void> _onThreshold() async {
    if (!widget.isAuthenticated || _loading || _revealed) return;
    setState(() => _loading = true);

    _scratcherKey.currentState?.reveal(
      duration: const Duration(milliseconds: 4000),
    );
    await Future.delayed(const Duration(milliseconds: 4000));
    if (!mounted) return;

    RevealResult? result;
    try {
      result = await ScratchService.instance.revealCard(widget.card!.id);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;

    setState(() {
      _loading = false;
      _revealed = true;
      _result = result;
    });

    Timer(const Duration(seconds: 10), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  bool get _isNothing => _result == null || _result!.isNothing;

  String get _titleKey {
    if (_showAuthCta) return 'cta';
    if (_revealed) return _isNothing ? 'nothing' : 'win';
    return 'default';
  }

  String get _titleText {
    if (_showAuthCta) return 'Réveille ta récompense';
    if (_revealed) return _isNothing ? 'Pas de chance cette fois' : '🎉 Vous avez gagné !';
    return 'Votre carte à gratter';
  }

  Color get _titleColor {
    if (_showAuthCta) return const Color(0xFF0F766E);
    if (_revealed && !_isNothing) return const Color(0xFFD97706);
    return const Color(0xFF1E293B);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, 32 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Header : pill + bouton fermer
          Row(
            children: <Widget>[
              const Spacer(),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF1F5F9),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Titre
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              key: ValueKey<String>(_titleKey),
              _titleText,
              style: TextStyle(
                color: _titleColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Carte ou CTA auth
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _showAuthCta
                ? const _AuthCtaCard(key: ValueKey('cta'))
                : _revealed
                    ? _RevealedCard(key: const ValueKey('revealed'), result: _result)
                    : _ScratchableCard(
                        key: const ValueKey('scratch'),
                        scratcherKey: _scratcherKey,
                        loading: _loading,
                        scratchStarted: _scratchStarted,
                        onScratchStart: _onScratchStart,
                        onThreshold: _onThreshold,
                      ),
          ),
          const SizedBox(height: 10),
          // Sous-texte fermeture auto
          AnimatedOpacity(
            opacity: _revealed ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: Text(
              'Fermeture automatique dans 10 secondes.',
              style: TextStyle(
                color: const Color(0xFF64748B).withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte grattable ───────────────────────────────────────────────────────────

class _ScratchableCard extends StatelessWidget {
  const _ScratchableCard({
    super.key,
    required this.scratcherKey,
    required this.loading,
    required this.scratchStarted,
    required this.onScratchStart,
    required this.onThreshold,
  });

  final GlobalKey<ScratcherState> scratcherKey;
  final bool loading;
  final bool scratchStarted;
  final VoidCallback onScratchStart;
  final VoidCallback onThreshold;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Scratcher(
            key: scratcherKey,
            brushSize: 44,
            threshold: 60,
            color: _kFoil,
            onChange: (double p) {
              if (p > 0) onScratchStart();
            },
            onThreshold: onThreshold,
            child: _CardBase(
              child: loading ? const _LoadingDots() : const _HintContent(),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: (scratchStarted || loading) ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 350),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: const _GratteOverlay(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Carte révélée ─────────────────────────────────────────────────────────────

class _RevealedCard extends StatelessWidget {
  const _RevealedCard({super.key, this.result});
  final RevealResult? result;

  bool get _isNothing => result == null || result!.isNothing;

  @override
  Widget build(BuildContext context) {
    return _CardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (!_isNothing) ...<Widget>[
            Text(
              result!.rewardLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (result!.rewardValue != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${result!.rewardValue!.toStringAsFixed(0)} XOF',
                style: TextStyle(
                  color: _kGold.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ] else
            Text(
              'Aucune récompense',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05);
  }
}

// ── CTA connexion (non-authentifié) ──────────────────────────────────────────

class _AuthCtaCard extends StatelessWidget {
  const _AuthCtaCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0F766E), Color(0xFF0D5C56)],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x2A000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.lock_open_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const Spacer(),
            const Text(
              'Crée un compte\npour révéler ta récompense',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.25,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _CtaButton(
                    label: 'Créer un compte',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed(AppRoutes.authSignup);
                    },
                    filled: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CtaButton(
                    label: 'Se connecter',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed(AppRoutes.authLogin);
                    },
                    filled: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04);
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.onTap,
    required this.filled,
  });
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: filled ? Colors.white : Colors.transparent,
          border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: filled ? const Color(0xFF0F766E) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.back_hand_outlined,
              color: Colors.white.withValues(alpha: 0.85),
              size: 32,
            ),
            const SizedBox(height: 10),
            const Text(
              'GRATTE-MOI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Base card ─────────────────────────────────────────────────────────────────

class _CardBase extends StatelessWidget {
  const _CardBase({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1A2540), Color(0xFF0D3352)],
        ),
        boxShadow: <BoxShadow>[
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
            child: _circle(150, 0.05),
          ),
          Positioned(
            bottom: -50, left: -20,
            child: _circle(130, 0.04),
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

  Widget _circle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      );
}

// ── Widgets utilitaires ───────────────────────────────────────────────────────

class _GvipBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const Color gold = Color(0xFFD4AF37);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withValues(alpha: 0.45)),
        color: gold.withValues(alpha: 0.1),
      ),
      child: const Text(
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

class _HintContent extends StatelessWidget {
  const _HintContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(
          'Votre récompense',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
