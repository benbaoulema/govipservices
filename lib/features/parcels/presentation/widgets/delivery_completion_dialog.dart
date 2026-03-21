import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:govipservices/app/router/app_routes.dart';

enum DeliveryCompletionRole { driver, sender }

/// Affiche le popup de fin de course et navigue vers l'accueil à la fermeture.
Future<void> showDeliveryCompletionDialog(
  BuildContext context, {
  required String trackNum,
  required double price,
  required String currency,
  required DeliveryCompletionRole role,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => _DeliveryCompletionDialog(
      trackNum: trackNum,
      price: price,
      currency: currency,
      role: role,
    ),
  );
}

class _DeliveryCompletionDialog extends StatelessWidget {
  const _DeliveryCompletionDialog({
    required this.trackNum,
    required this.price,
    required this.currency,
    required this.role,
  });

  final String trackNum;
  final double price;
  final String currency;
  final DeliveryCompletionRole role;

  static const Color _teal = Color(0xFF0F766E);
  static const Color _tealLight = Color(0xFF14B8A6);

  String get _title =>
      role == DeliveryCompletionRole.driver ? 'Course terminée !' : 'Livraison effectuée !';

  String get _amountLabel =>
      role == DeliveryCompletionRole.driver ? 'Montant à encaisser' : 'Montant à régler';

  String get _priceFormatted {
    final int rounded = price.round();
    // Formatter avec séparateur de milliers
    final String digits = rounded.toString();
    final StringBuffer buf = StringBuffer();
    final int remainder = digits.length % 3;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (i - remainder) % 3 == 0) buf.write('\u202F');
      buf.write(digits[i]);
    }
    return '${buf.toString()} ${currency.isEmpty ? 'FCFA' : currency}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: _buildCard(context)
          .animate()
          .scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: 380.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 280.ms),
    );
  }

  Widget _buildCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ── En-tête gradient ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[_teal, _tealLight],
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: <Widget>[
                // Cercle animé avec checkmark
                _AnimatedCheckCircle()
                    .animate()
                    .scale(
                      delay: 200.ms,
                      duration: 400.ms,
                      curve: Curves.elasticOut,
                    ),
                const SizedBox(height: 16),
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 300.ms, duration: 300.ms)
                    .slideY(begin: 0.3, end: 0),
                if (trackNum.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'Réf. $trackNum',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 380.ms, duration: 300.ms),
                ],
              ],
            ),
          ),

          // ── Corps blanc ──────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              children: <Widget>[
                // Label montant
                Text(
                  _amountLabel,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                // Montant en grand
                Text(
                  _priceFormatted,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 450.ms, duration: 350.ms)
                    .scale(
                      delay: 450.ms,
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                      duration: 350.ms,
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(height: 28),
                // Bouton CTA
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _onClose(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Retour à l\'accueil',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 550.ms, duration: 300.ms)
                    .slideY(begin: 0.4, end: 0, delay: 550.ms, duration: 300.ms),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onClose(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (Route<dynamic> route) => false,
    );
  }
}

class _AnimatedCheckCircle extends StatelessWidget {
  const _AnimatedCheckCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF0F766E),
            size: 34,
          ),
        ),
      ),
    );
  }
}
