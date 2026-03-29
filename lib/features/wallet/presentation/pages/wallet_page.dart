import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/features/wallet/data/wallet_service.dart';
import 'package:govipservices/features/wallet/domain/models/wallet_models.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _accentSoft = Color(0xFFE6FAF7);

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: const HomeAppBarButton(),
          title: const Text('Portefeuille'),
        ),
        body: const Center(child: Text('Connectez-vous pour accéder à votre portefeuille.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Portefeuille'),
        backgroundColor: _accentDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<WalletDocument>(
        stream: WalletService.instance.watchWallet(uid),
        builder: (context, walletSnap) {
          final WalletDocument wallet =
              walletSnap.data ?? WalletDocument.empty(uid);

          return StreamBuilder<List<WalletTransaction>>(
            stream: WalletService.instance.watchTransactions(uid),
            builder: (context, txSnap) {
              final List<WalletTransaction> transactions =
                  txSnap.data ?? const <WalletTransaction>[];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Balance card ────────────────────────────────────────
                  _BalanceCard(
                    balance: wallet.balance,
                    currency: wallet.currency,
                    onRecharge: () => _openRechargeSheet(context, uid),
                    onRetrait: wallet.balance > 0
                        ? () => _openRetraitSheet(context, uid, wallet.balance)
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // ── Transactions ────────────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'Transactions',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10233E),
                      ),
                    ),
                  ),
                  if (txSnap.connectionState == ConnectionState.waiting)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (transactions.isEmpty)
                    _EmptyTransactions()
                  else
                    ...transactions.map((tx) => _TransactionTile(tx: tx)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openRechargeSheet(BuildContext context, String uid) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RechargeSheet(uid: uid),
    );
  }

  Future<void> _openRetraitSheet(BuildContext context, String uid, int balance) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RetraitSheet(uid: uid, balance: balance),
    );
  }
}

// ── Balance Card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.currency,
    required this.onRecharge,
    this.onRetrait,
  });

  final int balance;
  final String currency;
  final VoidCallback onRecharge;
  final VoidCallback? onRetrait;

  @override
  Widget build(BuildContext context) {
    final bool isNegative = balance < 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accentDark, _accent],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x3314B8A6), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                'Solde disponible',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isNegative ? '-' : ''}${balance.abs().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  currency,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (isNegative)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Solde négatif',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRecharge,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white60),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Recharger', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              if (onRetrait != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRetrait,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _accentDark,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('Retirer', style: TextStyle(fontWeight: FontWeight.w700)),
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

String _formatTxDate(DateTime d) {
  const List<String> months = [
    'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
    'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
  ];
  final String h = d.hour.toString().padLeft(2, '0');
  final String m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year} · $h:$m';
}

// ── Transaction Tile ──────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});
  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final bool isCredit = tx.isCredit;
    final Color color = isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final Color bgColor = isCredit ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final IconData icon = _iconForType(tx.type);
    final String dateStr = tx.createdAt != null
        ? _formatTxDate(tx.createdAt!.toDate())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF10233E)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dateStr.isNotEmpty)
                  Text(dateStr, style: const TextStyle(fontSize: 11, color: Color(0xFF7A8CA8))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}${tx.amount.abs()} XOF',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: color,
                ),
              ),
              if (tx.status == 'pending')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('En attente', style: TextStyle(fontSize: 9, color: Color(0xFFD97706), fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'commission':       return Icons.percent_rounded;
      case 'recharge':         return Icons.add_circle_outline_rounded;
      case 'retrait':          return Icons.arrow_upward_rounded;
      case 'reporter_reward':  return Icons.radar_rounded;
      default:                 return Icons.swap_horiz_rounded;
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Aucune transaction',
            style: TextStyle(fontSize: 14, color: Colors.grey[400], fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Recharge Sheet ────────────────────────────────────────────────────────────

class _RechargeSheet extends StatefulWidget {
  const _RechargeSheet({required this.uid});
  final String uid;

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  String? _method; // 'wave' | 'orange_money'
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final String? phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      _phoneController.text = phone;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      _method != null &&
      _amountController.text.trim().isNotEmpty &&
      (int.tryParse(_amountController.text.trim()) ?? 0) > 0 &&
      _phoneController.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    final int amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) return;

    setState(() => _loading = true);
    try {
      await WalletService.instance.requestRecharge(
        uid: widget.uid,
        amount: amount,
        method: _method!,
        phone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _accentDark,
          content: Text('Recharge de $amount XOF enregistrée.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Erreur lors de la recharge. Réessayez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                  width: 40, height: 4,
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
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add_card_rounded, color: _accentDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recharger le portefeuille',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF10233E))),
                        Text('Choisissez un mode de paiement',
                            style: TextStyle(fontSize: 12, color: Color(0xFF7A8CA8))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Montant
              const Text('Montant (XOF)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4A5568))),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ex: 5000',
                  prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),

              // Mode de paiement
              const Text('Mode de paiement',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4A5568))),
              const SizedBox(height: 10),
              _RechargeMethodTile(
                label: 'Wave',
                imagePath: 'assets/wave.jpg',
                color: const Color(0xFF1A56DB),
                selected: _method == 'wave',
                onTap: () => setState(() => _method = 'wave'),
              ),
              const SizedBox(height: 8),
              _RechargeMethodTile(
                label: 'Orange Money',
                imagePath: 'assets/om.png',
                color: const Color(0xFFFF6600),
                selected: _method == 'orange_money',
                onTap: () => setState(() => _method = 'orange_money'),
              ),

              if (_method != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Numéro ${_method == 'wave' ? 'Wave' : 'Orange Money'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4A5568)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Ex: +225 07 00 00 00 00',
                    prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _canConfirm && !_loading ? _confirm : null,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded),
                  label: const Text('Confirmer la recharge'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Retrait Sheet ─────────────────────────────────────────────────────────────

class _RetraitSheet extends StatefulWidget {
  const _RetraitSheet({required this.uid, required this.balance});
  final String uid;
  final int balance;

  @override
  State<_RetraitSheet> createState() => _RetraitSheetState();
}

class _RetraitSheetState extends State<_RetraitSheet> {
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  bool get _canConfirm => _phoneController.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      await WalletService.instance.requestRetrait(
        uid: widget.uid,
        amount: widget.balance,
        wavePhone: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _accentDark,
          content: Text('Demande de retrait de ${widget.balance} XOF envoyée.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: _accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_upward_rounded, color: _accentDark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Retirer via Wave',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF10233E))),
                        Text('Solde disponible : ${widget.balance} XOF',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF7A8CA8))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Montant à retirer (non modifiable — tout le solde)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD1D9E6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: _accentDark, size: 20),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Montant à retirer',
                            style: TextStyle(fontSize: 11, color: Color(0xFF7A8CA8))),
                        Text('${widget.balance} XOF',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF10233E))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Image Wave + champ numéro
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/wave.jpg',
                  width: double.infinity,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Icon(Icons.waves_rounded, color: Color(0xFF1A56DB), size: 36),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Numéro Wave',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4A5568))),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ex: +225 07 00 00 00 00',
                  prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Le montant sera envoyé sur ce numéro Wave après validation.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A56DB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _canConfirm && !_loading ? _confirm : null,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Confirmer le retrait'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RechargeMethodTile extends StatelessWidget {
  const _RechargeMethodTile({
    required this.label,
    required this.imagePath,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String imagePath;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                imagePath, width: 38, height: 38, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 38, height: 38,
                  color: color.withValues(alpha: 0.12),
                  child: Icon(Icons.payment_rounded, color: color, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: selected ? color : const Color(0xFF10233E),
                ),
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
