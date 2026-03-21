import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';

enum ParcelHistoryRole { sender, driver }

class ParcelsHistoryPage extends StatefulWidget {
  const ParcelsHistoryPage({
    required this.uid,
    required this.role,
    super.key,
  });

  final String uid;
  final ParcelHistoryRole role;

  @override
  State<ParcelsHistoryPage> createState() => _ParcelsHistoryPageState();
}

class _ParcelsHistoryPageState extends State<ParcelsHistoryPage> {
  static const Color _teal = Color(0xFF0F766E);

  final ParcelRequestService _service = ParcelRequestService();
  late Future<List<ParcelRequestDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.role == ParcelHistoryRole.sender
        ? _service.fetchSenderHistory(widget.uid)
        : _service.fetchDriverHistory(widget.uid);
  }

  String get _title => widget.role == ParcelHistoryRole.sender
      ? 'Mes livraisons'
      : 'Mes courses livreur';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          _title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: FutureBuilder<List<ParcelRequestDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _teal),
            );
          }
          if (snapshot.hasError) {
            return _EmptyState(
              icon: Icons.error_outline_rounded,
              message: 'Impossible de charger l\'historique.',
              onRetry: () => setState(() {
                _future = widget.role == ParcelHistoryRole.sender
                    ? _service.fetchSenderHistory(widget.uid)
                    : _service.fetchDriverHistory(widget.uid);
              }),
            );
          }
          final List<ParcelRequestDocument> items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return _EmptyState(
              icon: Icons.inbox_rounded,
              message: 'Aucune livraison pour le moment.',
            );
          }
          return RefreshIndicator(
            color: _teal,
            onRefresh: () async {
              setState(() {
                _future = widget.role == ParcelHistoryRole.sender
                    ? _service.fetchSenderHistory(widget.uid)
                    : _service.fetchDriverHistory(widget.uid);
              });
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, int i) => _HistoryCard(
                item: items[i],
                role: widget.role,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.role});

  final ParcelRequestDocument item;
  final ParcelHistoryRole role;

  static const Color _teal = Color(0xFF0F766E);

  Color get _statusColor {
    switch (item.status) {
      case 'delivered':
        return const Color(0xFF10B981);
      case 'rejected':
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String get _statusLabel {
    switch (item.status) {
      case 'delivered':
        return 'Livré';
      case 'rejected':
        return 'Refusé';
      case 'cancelled':
        return 'Annulé';
      default:
        return item.status;
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final DateTime dt = ts.toDate().toLocal();
    const List<String> months = <String>[
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatPrice(double value) {
    final int rounded = value.round();
    final String digits = rounded.toString();
    final StringBuffer buf = StringBuffer();
    final int remainder = digits.length % 3;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (i - remainder) % 3 == 0) buf.write('\u202F');
      buf.write(digits[i]);
    }
    return '${buf.toString()} ${item.currency.isEmpty ? 'XOF' : item.currency}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ── En-tête : ref + date + badge statut ─────────────────────
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Réf. ${item.trackNum}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (item.createdAt != null)
                        Text(
                          _formatDate(item.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Trajet ──────────────────────────────────────────────────
            _RouteRow(
              icon: Icons.my_location_outlined,
              label: item.pickupAddress,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: SizedBox(
                height: 10,
                child: VerticalDivider(width: 1, thickness: 1),
              ),
            ),
            _RouteRow(
              icon: Icons.flag_outlined,
              label: item.deliveryAddress,
            ),
            const SizedBox(height: 12),
            // ── Prix + livreur/sender info ───────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  _formatPrice(item.price),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _teal,
                  ),
                ),
                Text(
                  role == ParcelHistoryRole.sender
                      ? item.providerName
                      : item.requesterName,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: const Color(0xFF0F766E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF334155),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── État vide ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[500],
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ],
      ),
    );
  }
}
