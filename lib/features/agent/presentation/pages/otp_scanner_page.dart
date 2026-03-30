import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:govipservices/features/agent/data/agent_service.dart';

// ── Page de scan OTP agent ────────────────────────────────────────────────────
//
// Retourne un _OtpScanResult via Navigator.pop() :
//   - success: true + les données du PaymentResult si OTP valide
//   - success: false si annulé
//
// Usage :
//   final result = await Navigator.push<_OtpScanResult>(
//     context, MaterialPageRoute(builder: (_) => const OtpScannerPage()),
//   );

class OtpScannerPage extends StatefulWidget {
  const OtpScannerPage({super.key});

  @override
  State<OtpScannerPage> createState() => _OtpScannerPageState();
}

class _OtpScannerPageState extends State<OtpScannerPage> {
  static const Color _green = Color(0xFF059669);

  final MobileScannerController _scanner = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();

  bool _manualMode = false;
  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String code) async {
    final String clean = code.trim();
    if (clean.length != 6 || !RegExp(r'^\d{6}$').hasMatch(clean)) {
      setState(() => _error = 'Code invalide — 6 chiffres requis.');
      return;
    }
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    await _scanner.stop();

    final String? agentId =
        await AgentService.instance.verifyAndConsumeOtp(clean);

    if (!mounted) return;

    if (agentId == null) {
      await _scanner.start();
      setState(() {
        _processing = false;
        _error = 'Code invalide ou expiré. Demandez un nouveau code à l\'agent.';
      });
      return;
    }

    // OTP valide → retour avec succès
    Navigator.of(context).pop(OtpScanResult(valid: true, agentId: agentId));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing || _manualMode) return;
    final String? raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw != null && raw.isNotEmpty) {
      _handleCode(raw);
    }
  }

  void _submitManual() {
    _handleCode(_manualController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Scanner le code agent',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              Navigator.of(context).pop(const OtpScanResult(valid: false)),
        ),
        actions: [
          IconButton(
            tooltip: 'Flash',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _scanner.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Caméra / scanner ───────────────────────────────────────────
          Expanded(
            child: _manualMode
                ? _ManualEntryView(
                    controller: _manualController,
                    processing: _processing,
                    error: _error,
                    green: _green,
                    onSubmit: _submitManual,
                    onScanMode: () => setState(() {
                      _manualMode = false;
                      _error = null;
                      _scanner.start();
                    }),
                  )
                : Stack(
                    children: [
                      MobileScanner(
                        controller: _scanner,
                        onDetect: _onDetect,
                      ),
                      // Cadre de visée
                      Center(
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            border: Border.all(color: _green, width: 3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      // Label
                      Positioned(
                        bottom: 140,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Pointez vers le QR code de l\'agent',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Erreur
                      if (_error != null)
                        Positioned(
                          bottom: 190,
                          left: 24,
                          right: 24,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade800,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      // Spinner pendant vérification
                      if (_processing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF059669)),
                          ),
                        ),
                    ],
                  ),
          ),

          // ── Bas : saisie manuelle ──────────────────────────────────────
          if (!_manualMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _green),
                  onPressed: () {
                    _scanner.stop();
                    setState(() {
                      _manualMode = true;
                      _error = null;
                    });
                  },
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: const Text(
                    'Saisir manuellement',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Vue saisie manuelle ───────────────────────────────────────────────────────

class _ManualEntryView extends StatelessWidget {
  const _ManualEntryView({
    required this.controller,
    required this.processing,
    required this.error,
    required this.green,
    required this.onSubmit,
    required this.onScanMode,
  });

  final TextEditingController controller;
  final bool processing;
  final String? error;
  final Color green;
  final VoidCallback onSubmit;
  final VoidCallback onScanMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dialpad_rounded, color: Colors.white54, size: 48),
          const SizedBox(height: 20),
          const Text(
            'Saisissez le code à 6 chiffres\naffiché sur le téléphone de l\'agent',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            autofocus: true,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              color: green,
            ),
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: TextStyle(
                fontSize: 36,
                letterSpacing: 10,
                color: Colors.white12,
              ),
              counterText: '',
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: green, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
            onFieldSubmitted: (_) => onSubmit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
              onPressed: processing ? null : onSubmit,
              icon: processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: const Text('Valider'),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            onPressed: onScanMode,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Scanner à la place'),
          ),
        ],
      ),
    );
  }
}

// ── Résultat retourné au parent ───────────────────────────────────────────────

class OtpScanResult {
  const OtpScanResult({required this.valid, this.agentId});
  final bool valid;
  final String? agentId;
}
