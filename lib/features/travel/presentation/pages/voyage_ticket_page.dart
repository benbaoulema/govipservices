import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

const Color _travelAccent = Color(0xFF00C4A1);
const Color _travelAccentDark = Color(0xFF007A63);
const Color _travelAccentSoft = Color(0xFFE6FAF7);

class VoyageTicketPage extends StatelessWidget {
  const VoyageTicketPage({required this.booking, super.key});

  final VoyageBookingDocument booking;

  static const String _qrPrefix = 'GVIP-';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: _travelAccentDark,
        foregroundColor: Colors.white,
        title: const Text(
          'Votre billet',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => Navigator.of(context, rootNavigator: true)
                .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
              ),
              child: const Icon(Icons.home_rounded, size: 18, color: Colors.white),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Télécharger PDF',
            onPressed: () => _downloadPdf(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _TicketCard(booking: booking),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _downloadPdf(context),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Télécharger le billet PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _travelAccentDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true)
                      .pushNamedAndRemoveUntil(AppRoutes.home, (r) => false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _travelAccentDark,
                    side: const BorderSide(color: _travelAccentDark),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  child: const Text("Retour à l'accueil"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context) async {
    try {
      final Uint8List pdfBytes = await _buildPdfBytes();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'billet_GVIP_${booking.trackNum}.pdf',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de générer le PDF.')),
      );
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    final pw.Document pdf = pw.Document();

    final String qrData = '$_qrPrefix${booking.trackNum}';
    final String departureDate = _formatDate(booking.tripDepartureDate);
    final String departureTime = booking.tripDepartureTime.isNotEmpty
        ? booking.tripDepartureTime
        : '--:--';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('007A63'),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'GVIP',
                          style: pw.TextStyle(
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Billet de voyage',
                          style: const pw.TextStyle(
                            fontSize: 13,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'N° ${booking.trackNum}',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Statut: ${_statusLabel(booking.status)}',
                          style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Route
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Trajet',
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600)),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('DÉPART',
                                  style: const pw.TextStyle(
                                      fontSize: 9, color: PdfColors.grey)),
                              pw.SizedBox(height: 4),
                              pw.Text(booking.segmentFrom,
                                  style: pw.TextStyle(
                                      fontSize: 13,
                                      fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 4),
                              pw.Text('$departureDate · $departureTime',
                                  style: pw.TextStyle(
                                      fontSize: 11,
                                      color: PdfColor.fromHex('007A63'),
                                      fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                          child: pw.Text('→',
                              style: pw.TextStyle(
                                  fontSize: 20,
                                  color: PdfColor.fromHex('007A63'),
                                  fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('ARRIVÉE',
                                  style: const pw.TextStyle(
                                      fontSize: 9, color: PdfColors.grey)),
                              pw.SizedBox(height: 4),
                              pw.Text(booking.segmentTo,
                                  style: pw.TextStyle(
                                      fontSize: 13,
                                      fontWeight: pw.FontWeight.bold)),
                              if (booking.tripArrivalEstimatedTime.isNotEmpty) ...[
                                pw.SizedBox(height: 4),
                                pw.Text(
                                    'Arrivée estimée: ${booking.tripArrivalEstimatedTime}',
                                    style: const pw.TextStyle(
                                        fontSize: 10, color: PdfColors.grey)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Passagers + QR
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Passagers
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(10)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Passagers (${booking.requestedSeats})',
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey600)),
                          pw.SizedBox(height: 10),
                          ...booking.travelers.map((t) => pw.Padding(
                                padding:
                                    const pw.EdgeInsets.only(bottom: 6),
                                child: pw.Row(
                                  children: [
                                    pw.Text('• ',
                                        style: pw.TextStyle(
                                            color:
                                                PdfColor.fromHex('007A63'),
                                            fontWeight:
                                                pw.FontWeight.bold)),
                                    pw.Expanded(
                                      child: pw.Column(
                                        crossAxisAlignment:
                                            pw.CrossAxisAlignment.start,
                                        children: [
                                          pw.Text(
                                              t.name,
                                              style: pw.TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      pw.FontWeight.bold)),
                                          if (t.contact.isNotEmpty)
                                            pw.Text(
                                                t.contact,
                                                style: const pw.TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        PdfColors.grey)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          pw.SizedBox(height: 12),
                          pw.Text('Chauffeur',
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey600)),
                          pw.SizedBox(height: 6),
                          pw.Text(booking.tripDriverName,
                              style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold)),
                          if (booking.tripVehicleModel.isNotEmpty)
                            pw.Text(booking.tripVehicleModel,
                                style: const pw.TextStyle(
                                    fontSize: 11, color: PdfColors.grey)),
                          if (booking.tripContactPhone.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(booking.tripContactPhone,
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    color: PdfColor.fromHex('007A63'))),
                          ],
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  // QR Code
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(10)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qrData,
                          width: 110,
                          height: 110,
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          booking.trackNum,
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 2),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('GVIP',
                            style: pw.TextStyle(
                                fontSize: 10,
                                color: PdfColor.fromHex('007A63'),
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Services Confort
              if (booking.comfortOptions.isNotEmpty) ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Services Confort',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 8),
                      pw.Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: booking.comfortOptions.map((id) {
                          final String label = _comfortOptionLabel(id);
                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('E6FAF7'),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            ),
                            child: pw.Text(label,
                                style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColor.fromHex('007A63'))),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
              ],

              // Prix
              if (booking.totalPrice > 0)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('E6FAF7'),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total réglé',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('007A63'))),
                      pw.Text(
                        '${booking.totalPrice} ${booking.tripCurrency}',
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('007A63')),
                      ),
                    ],
                  ),
                ),

              pw.Spacer(),
              // Footer
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'GVIP Services · Billet généré automatiquement · Réf. ${booking.trackNum}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String _formatDate(String iso) {
    final DateTime? d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final List<String> months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'pending': return 'En attente';
      case 'accepted':
      case 'approved':
      case 'confirmed': return 'Confirmée';
      case 'cancelled': return 'Annulée';
      case 'rejected':
      case 'refused': return 'Refusée';
      default: return status;
    }
  }
}

String _comfortOptionLabel(String id) {
  if (id.startsWith('gare_maison:')) {
    final String address = id.substring('gare_maison:'.length);
    return 'Gare → $address';
  }
  switch (id) {
    case 'depot_gare':  return 'Dépôt à la gare';
    case 'gare_maison': return 'Gare → Maison';
    case 'smart_food':  return 'Smart food (500 XOF)';
    default:            return id;
  }
}

// ── Ticket Widget (UI Flutter) ─────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.booking});
  final VoyageBookingDocument booking;

  @override
  Widget build(BuildContext context) {
    final String departureDate = VoyageTicketPage._formatDate(booking.tripDepartureDate);
    final String departureTime = booking.tripDepartureTime.isNotEmpty
        ? booking.tripDepartureTime
        : '--:--';
    final String qrData = '${VoyageTicketPage._qrPrefix}${booking.trackNum}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header turquoise
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_travelAccentDark, _travelAccent],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GVIP',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Text(
                        'Billet de voyage',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'N° Réservation',
                      style: TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      booking.trackNum,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        VoyageTicketPage._statusLabel(booking.status),
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Route
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DÉPART', style: TextStyle(fontSize: 10, color: Color(0xFF7A8CA8), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        booking.segmentFrom,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF10233E)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 13, color: _travelAccentDark),
                          const SizedBox(width: 4),
                          Text(departureDate, style: const TextStyle(fontSize: 12, color: _travelAccentDark, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          const Icon(Icons.access_time_rounded, size: 13, color: _travelAccentDark),
                          const SizedBox(width: 4),
                          Text(departureTime, style: const TextStyle(fontSize: 12, color: _travelAccentDark, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      const Icon(Icons.arrow_forward_rounded, color: _travelAccentDark, size: 22),
                      if (booking.tripArrivalEstimatedTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            booking.tripArrivalEstimatedTime,
                            style: const TextStyle(fontSize: 9, color: Color(0xFF7A8CA8)),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('ARRIVÉE', style: TextStyle(fontSize: 10, color: Color(0xFF7A8CA8), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        booking.segmentTo,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF10233E)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Notch separator
          const _TicketNotch(),

          // Passagers
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.groups_rounded,
                  label: 'Passagers (${booking.requestedSeats})',
                ),
                const SizedBox(height: 8),
                ...booking.travelers.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: _travelAccentSoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_rounded, size: 16, color: _travelAccentDark),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                if (t.contact.isNotEmpty)
                                  Text(t.contact,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A8CA8))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 12),
                _SectionTitle(icon: Icons.drive_eta_rounded, label: 'Chauffeur & véhicule'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: _travelAccentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_pin_rounded, size: 20, color: _travelAccentDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(booking.tripDriverName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          if (booking.tripVehicleModel.isNotEmpty)
                            Text(booking.tripVehicleModel,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF5B647A))),
                        ],
                      ),
                    ),
                    if (booking.tripContactPhone.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _travelAccentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_rounded, size: 13, color: _travelAccentDark),
                            const SizedBox(width: 4),
                            Text(booking.tripContactPhone,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _travelAccentDark)),
                          ],
                        ),
                      ),
                  ],
                ),

                if (booking.comfortOptions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(icon: Icons.stars_rounded, label: 'Services Confort'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: booking.comfortOptions.map((id) {
                      final String label = _comfortOptionLabel(id);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _travelAccentSoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _travelAccentDark.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 13, color: _travelAccentDark),
                            const SizedBox(width: 5),
                            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _travelAccentDark)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (booking.totalPrice > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: _travelAccentDark)),
                        Text(
                          '${booking.totalPrice} ${booking.tripCurrency}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _travelAccentDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // QR Code
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FFFE),
              border: Border(top: BorderSide(color: Color(0xFFE6FAF7), width: 1.5)),
            ),
            child: Column(
              children: [
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 140,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: _travelAccentDark,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF10233E),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  booking.trackNum,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Color(0xFF10233E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'GVIP Services',
                  style: TextStyle(fontSize: 11, color: _travelAccentDark, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketNotch extends StatelessWidget {
  const _TicketNotch();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const _HalfCircle(side: Alignment.centerRight),
          Expanded(
            child: LayoutBuilder(builder: (_, constraints) {
              final int count = (constraints.maxWidth / 10).floor();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  count,
                  (_) => Container(width: 5, height: 1.5, color: const Color(0xFFD1E3F0)),
                ),
              );
            }),
          ),
          const _HalfCircle(side: Alignment.centerLeft),
        ],
      ),
    );
  }
}

class _HalfCircle extends StatelessWidget {
  const _HalfCircle({required this.side});
  final Alignment side;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: side,
        widthFactor: 0.5,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4F8),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF7A8CA8)),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF7A8CA8)),
        ),
      ],
    );
  }
}
