import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:govipservices/features/agent/data/agent_service.dart';
import 'package:govipservices/features/agent/domain/models/agent_models.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ── Page principale ───────────────────────────────────────────────────────────

class CashCollectionPage extends StatefulWidget {
  const CashCollectionPage({super.key, required this.agent});

  final Agent agent;

  @override
  State<CashCollectionPage> createState() => _CashCollectionPageState();
}

class _CashCollectionPageState extends State<CashCollectionPage> {
  static const Color _green = Color(0xFF059669);
  static const Color _greenLight = Color(0xFF10B981);

  _Step _step = _Step.codeEntry;
  bool _loading = false;
  String? _error;
  AgentOtp? _otp;

  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final String code = _codeController.text.trim();
    if (code.length != 8) {
      setState(() => _error = 'Le code agent fait 8 chiffres.');
      return;
    }
    // Comparaison locale — l'objet Agent est déjà chargé, pas de round-trip Firestore
    if (code != widget.agent.code) {
      setState(() => _error = 'Code incorrect. Veuillez réessayer.');
      return;
    }
    // Code correct → générer OTP
    await _generateOtp();
  }

  Future<void> _generateOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AgentOtp otp =
          await AgentService.instance.generateOtp(widget.agent.id);
      if (!mounted) return;
      setState(() {
        _otp = otp;
        _step = _Step.otpDisplay;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erreur lors de la génération : $e';
      });
    }
  }

  Future<void> _refresh() => _generateOtp();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Color(0xFF10233E)),
        title: const Text(
          'Encaisser espèces',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF10233E),
          ),
        ),
      ),
      body: SafeArea(
        child: _step == _Step.codeEntry
            ? _CodeEntryView(
                controller: _codeController,
                loading: _loading,
                error: _error,
                agentName: widget.agent.name,
                onConfirm: _verifyCode,
              )
            : _OtpDisplayView(
                otp: _otp!,
                agentName: widget.agent.name,
                onRefresh: _refresh,
                loading: _loading,
                green: _green,
                greenLight: _greenLight,
              ),
      ),
    );
  }
}

enum _Step { codeEntry, otpDisplay }

// ── Vue saisie code ───────────────────────────────────────────────────────────

class _CodeEntryView extends StatelessWidget {
  const _CodeEntryView({
    required this.controller,
    required this.loading,
    required this.error,
    required this.agentName,
    required this.onConfirm,
  });

  final TextEditingController controller;
  final bool loading;
  final String? error;
  final String agentName;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF059669),
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Vérification agent',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF10233E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Bonjour $agentName. Saisissez votre code agent à 8 chiffres pour accéder à la génération de code.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7A90),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: Color(0xFF10233E),
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: const TextStyle(
                fontSize: 24,
                letterSpacing: 6,
                color: Color(0xFFCBD5E1),
              ),
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD1D9E6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF059669), width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            onFieldSubmitted: (_) => onConfirm(),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: loading ? null : onConfirm,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.lock_open_rounded),
              label: const Text('Accéder'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vue affichage OTP ─────────────────────────────────────────────────────────

class _OtpDisplayView extends StatefulWidget {
  const _OtpDisplayView({
    required this.otp,
    required this.agentName,
    required this.onRefresh,
    required this.loading,
    required this.green,
    required this.greenLight,
  });

  final AgentOtp otp;
  final String agentName;
  final VoidCallback onRefresh;
  final bool loading;
  final Color green;
  final Color greenLight;

  @override
  State<_OtpDisplayView> createState() => _OtpDisplayViewState();
}

class _OtpDisplayViewState extends State<_OtpDisplayView> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.otp.expiresAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final Duration r = widget.otp.expiresAt.difference(DateTime.now());
      if (mounted) {
        setState(() => _remaining = r.isNegative ? Duration.zero : r);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _timerLabel {
    if (_remaining.isNegative || _remaining == Duration.zero) return 'Expiré';
    final int min = _remaining.inMinutes;
    final int sec = _remaining.inSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  bool get _expired =>
      _remaining.isNegative || _remaining == Duration.zero;

  double get _progress {
    const int totalSec = 8 * 60;
    final int remaining = _remaining.inSeconds.clamp(0, totalSec);
    return remaining / totalSec;
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.otp.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copié dans le presse-papiers')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Timer ring
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _expired ? Colors.red : widget.green,
                  ),
                ),
              ),
              Text(
                _timerLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _expired ? Colors.red : widget.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(
            _expired
                ? 'Code expiré'
                : 'Code valide — montrez-le au passager',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _expired ? Colors.red : const Color(0xFF10233E),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Le passager doit saisir ou scanner ce code dans l\'app',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7A90)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // QR Code
          AnimatedOpacity(
            opacity: _expired ? 0.3 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: widget.otp.code,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: widget.green,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: const Color(0xFF10233E),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Code chiffres
          GestureDetector(
            onTap: _copyCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: widget.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _expired
                      ? Colors.grey[300]!
                      : widget.green.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.otp.code,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: _expired ? Colors.grey : widget.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.copy_rounded,
                    size: 20,
                    color: _expired ? Colors.grey : widget.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Bouton nouveau code
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: _expired ? Colors.red : widget.green,
                  width: 2,
                ),
                foregroundColor: _expired ? Colors.red : widget.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: widget.loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.green,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text('Générer un nouveau code'),
            ),
          ),
        ],
      ),
    );
  }
}
