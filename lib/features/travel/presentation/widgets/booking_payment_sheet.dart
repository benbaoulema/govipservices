import 'dart:math';

import 'package:flutter/material.dart';
import 'package:govipservices/features/agent/presentation/pages/otp_scanner_page.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';
import 'package:govipservices/features/scratch/presentation/pages/checkout_scratch_sheet.dart';
import 'package:govipservices/features/scratch/presentation/pages/student_scratch_sheet.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);

// ── Result returned by PaymentSheet ─────────────────────────────────────────

class PaymentResult {
  const PaymentResult({
    this.studentDiscount = 0,
    this.checkoutDiscount = 0,
    this.paymentDiscount = 0,
    this.paymentMethod = '',
  });
  final int studentDiscount;
  final int checkoutDiscount;
  final int paymentDiscount;
  /// 'wave', 'orange_money', 'cash' ou '' si réservation gratuite
  final String paymentMethod;
}

enum PaymentMethod { wave, orangeMoney, cash }

// ── PaymentSheet ─────────────────────────────────────────────────────────────

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    required this.totalAmount,
    required this.currency,
    required this.userPhone,
    this.eligibleRewards = const <UserReward>[],
    super.key,
  });

  final int totalAmount;
  final String currency;
  final String userPhone;
  final List<UserReward> eligibleRewards;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  PaymentMethod? _method;
  late final TextEditingController _phoneController;
  late final TextEditingController _matriculeController;

  bool _isStudent = false;
  bool _loadingStudentCampaign = false;
  int _studentDiscount = 0;
  int _checkoutDiscount = 0;
  int _paymentDiscount = 0;
  bool _paymentScratchTriggered = false;

  int get _totalDiscount =>
      widget.eligibleRewards.fold(0, (acc, r) => acc + r.effectiveValue.round());

  int get _effectiveTotal =>
      (widget.totalAmount -
              _totalDiscount -
              max(_studentDiscount, _checkoutDiscount) -
              _paymentDiscount)
          .clamp(0, widget.totalAmount)
          .toInt();

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.userPhone);
    _matriculeController = TextEditingController()
      ..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _triggerCheckoutScratch());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _matriculeController.dispose();
    super.dispose();
  }

  Future<void> _triggerPaymentScratch() async {
    if (_paymentScratchTriggered) return;
    _paymentScratchTriggered = true;
    try {
      final ScratchCampaign? campaign =
          await ScratchService.instance.fetchCampaignByTrigger('payment_completed');
      if (!mounted || campaign == null || campaign.rewardsPool.isEmpty) return;
      final RewardConfig? reward =
          await showCheckoutScratchSheet(context, campaign: campaign, waveBadge: true);
      if (!mounted) return;
      if (reward != null && !reward.isNothing && reward.value != null) {
        setState(() => _paymentDiscount = reward.value!.round().clamp(0, widget.totalAmount));
      }
    } catch (e) {
      debugPrint('[PaymentScratch] erreur : $e');
    }
  }

  Future<void> _triggerCheckoutScratch() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    try {
      final ScratchCampaign? campaign =
          await ScratchService.instance.fetchCampaignByTrigger('booking_checkout');
      if (!mounted || campaign == null || campaign.rewardsPool.isEmpty) return;
      final RewardConfig? reward = await showCheckoutScratchSheet(context, campaign: campaign);
      if (!mounted) return;
      if (reward != null && !reward.isNothing && reward.value != null) {
        setState(
            () => _checkoutDiscount = reward.value!.round().clamp(0, widget.totalAmount));
      }
    } catch (e) {
      debugPrint('[CheckoutScratch] erreur : $e');
    }
  }

  Future<void> _openCashScanner() async {
    final OtpScanResult? result = await Navigator.of(context).push<OtpScanResult>(
      MaterialPageRoute<OtpScanResult>(
        builder: (_) => const OtpScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || result == null || !result.valid) return;
    Navigator.of(context).pop(PaymentResult(
      studentDiscount: _studentDiscount,
      checkoutDiscount: _checkoutDiscount,
      paymentMethod: 'cash',
    ));
  }

  Future<void> _validateStudent() async {
    final String matricule = _matriculeController.text.trim();
    if (matricule.isEmpty) return;
    setState(() => _loadingStudentCampaign = true);
    try {
      final ScratchCampaign? campaign =
          await ScratchService.instance.fetchStudentCampaign();
      if (!mounted) return;
      if (campaign == null || campaign.rewardsPool.isEmpty) {
        setState(() => _loadingStudentCampaign = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucune campagne étudiante active pour le moment.')),
        );
        return;
      }
      setState(() => _loadingStudentCampaign = false);
      final RewardConfig? reward =
          await showStudentScratchSheet(context, campaign: campaign, matricule: matricule);
      if (!mounted) return;
      if (reward != null && !reward.isNothing && reward.value != null) {
        setState(
            () => _studentDiscount = reward.value!.round().clamp(0, widget.totalAmount));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStudentCampaign = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _buildPriceBreakdown() {
    final bool hasDiscount = _totalDiscount > 0 ||
        _studentDiscount > 0 ||
        _checkoutDiscount > 0 ||
        _paymentDiscount > 0;
    final String cur = widget.currency.isEmpty ? 'XOF' : widget.currency;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1D9E6)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasDiscount ? 'Prix normal' : 'Total à payer',
                style: TextStyle(
                  fontSize: 13,
                  color: hasDiscount ? const Color(0xFF6B7A90) : _travelAccentDark,
                  fontWeight: hasDiscount ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              Text(
                '${widget.totalAmount} $cur',
                style: TextStyle(
                  fontSize: 13,
                  color: hasDiscount ? const Color(0xFF6B7A90) : _travelAccentDark,
                  fontWeight: hasDiscount ? FontWeight.w500 : FontWeight.w700,
                  decoration: hasDiscount ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          if (hasDiscount) ...[
            if (_totalDiscount > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.card_giftcard_rounded,
                        size: 15, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(
                      'Récompenses (${widget.eligibleRewards.length})',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                  Text('-$_totalDiscount $cur',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            if (_studentDiscount > 0 && _checkoutDiscount > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 15, color: Color(0xFF00897B)),
                    const SizedBox(width: 4),
                    const Text('Meilleure réduction',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.w600)),
                  ]),
                  Text('-${max(_studentDiscount, _checkoutDiscount)} $cur',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF00897B),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ] else ...[
              if (_studentDiscount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.school_rounded, size: 15, color: Color(0xFF00897B)),
                      const SizedBox(width: 4),
                      const Text('Réduction étudiante',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF00897B),
                              fontWeight: FontWeight.w600)),
                    ]),
                    Text('-$_studentDiscount $cur',
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
              if (_checkoutDiscount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.confirmation_number_rounded,
                          size: 15, color: Color(0xFF14B8A6)),
                      const SizedBox(width: 4),
                      const Text('Carte à gratter',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF14B8A6),
                              fontWeight: FontWeight.w600)),
                    ]),
                    Text('-$_checkoutDiscount $cur',
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF14B8A6),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ],
            if (_paymentDiscount > 0) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Image.asset(
                      'assets/wave.jpg',
                      width: 16,
                      height: 16,
                      errorBuilder: (_, __, ___) => const Icon(Icons.waves_rounded,
                          size: 14, color: Color(0xFF1A56DB)),
                    ),
                    const SizedBox(width: 6),
                    const Text('Bonus Wave',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1A56DB),
                            fontWeight: FontWeight.w600)),
                  ]),
                  Text('-$_paymentDiscount $cur',
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1A56DB),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Color(0xFFD1D9E6)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total à payer',
                    style: TextStyle(
                        fontSize: 14,
                        color: _travelAccentDark,
                        fontWeight: FontWeight.w800)),
                Text('$_effectiveTotal $cur',
                    style: const TextStyle(
                        fontSize: 14,
                        color: _travelAccentDark,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD1D9E6)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _isStudent,
            activeColor: const Color(0xFF00897B),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text(
              'Je suis élève ou étudiant(e)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10233E)),
            ),
            secondary:
                const Icon(Icons.school_rounded, color: Color(0xFF00897B), size: 22),
            onChanged: _studentDiscount > 0
                ? null
                : (val) => setState(() {
                      _isStudent = val;
                      if (!val) _matriculeController.clear();
                    }),
          ),
          if (_isStudent && _studentDiscount == 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  const Divider(height: 1, color: Color(0xFFD1D9E6)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _matriculeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Numéro matricule',
                      prefixIcon: const Icon(Icons.badge_rounded, size: 18),
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle:
                            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _loadingStudentCampaign
                          ? null
                          : _matriculeController.text.trim().isEmpty
                              ? null
                              : _validateStudent,
                      child: _loadingStudentCampaign
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Valider'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_studentDiscount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF00897B), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Réduction étudiante appliquée : -$_studentDiscount XOF',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF00897B),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: _travelAccentDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _effectiveTotal == 0 ? 'Réservation gratuite' : 'Paiement',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF10233E)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildPriceBreakdown(),
              const SizedBox(height: 20),
              _buildStudentSection(),
              const SizedBox(height: 20),
              if (_effectiveTotal == 0) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _travelAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle:
                          const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).pop(PaymentResult(
                        studentDiscount: _studentDiscount,
                        checkoutDiscount: _checkoutDiscount,
                        paymentDiscount: _paymentDiscount,
                        paymentMethod: '')),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Réserver gratuitement'),
                  ),
                ),
              ] else ...[
                const Text('Choisir le mode de paiement',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4A5568))),
                const SizedBox(height: 10),
                _PaymentMethodTile(
                  label: 'Wave',
                  subtitle: 'Paiement mobile Wave',
                  color: const Color(0xFF1A56DB),
                  imagePath: 'assets/wave.jpg',
                  selected: _method == PaymentMethod.wave,
                  onTap: () {
                    setState(() => _method = PaymentMethod.wave);
                    _triggerPaymentScratch();
                  },
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  label: 'Orange Money',
                  subtitle: 'Paiement mobile Orange',
                  color: const Color(0xFFFF6600),
                  imagePath: 'assets/om.png',
                  icon: Icons.account_balance_wallet_rounded,
                  selected: _method == PaymentMethod.orangeMoney,
                  onTap: () => setState(() => _method = PaymentMethod.orangeMoney),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  label: 'Espèces',
                  subtitle: 'Paiement en cash via agent',
                  color: const Color(0xFF059669),
                  icon: Icons.point_of_sale_rounded,
                  selected: _method == PaymentMethod.cash,
                  onTap: () => setState(() => _method = PaymentMethod.cash),
                ),
                if (_method != null && _method != PaymentMethod.cash) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Numéro ${_method == PaymentMethod.wave ? "Wave" : "Orange Money"}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4A5568)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Ex: +225 07 00 00 00 00',
                      prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _travelAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle:
                            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      onPressed: _phoneController.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(context).pop(PaymentResult(
                              studentDiscount: _studentDiscount,
                              checkoutDiscount: _checkoutDiscount,
                              paymentDiscount: _paymentDiscount,
                              paymentMethod: _method == PaymentMethod.wave ? 'wave' : 'orange_money')),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Payer et Réserver'),
                    ),
                  ),
                ],
                if (_method == PaymentMethod.cash) ...[
                  const SizedBox(height: 20),
                  const Text(
                    "Demandez à l'agent de générer un code, puis scannez-le ou saisissez-le.",
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7A90)),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle:
                            const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      onPressed: _openCashScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scanner le code agent'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── PaymentMethodTile ────────────────────────────────────────────────────────

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.selected,
    required this.onTap,
    this.imagePath,
    this.icon,
  });

  final String label;
  final String subtitle;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? imagePath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : const Color(0xFFD8E4EA),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imagePath != null
                  ? Image.asset(
                      imagePath!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(icon ?? Icons.payment_rounded, color: color, size: 22),
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon ?? Icons.payment_rounded, color: color, size: 22),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: selected ? color : const Color(0xFF10233E))),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A8CA8))),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
