import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/additional_service_models.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/presentation/widgets/booking_comfort_sheet.dart';
import 'package:govipservices/features/travel/presentation/widgets/booking_payment_sheet.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);
const Color _travelSurfaceBorder = Color(0xFFD8F3EE);
const Color _travelPageBg = Color(0xFFF2FFFC);

String _formatFrDate(String raw) {
  final Match? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return raw;
  return '${match.group(3)}-${match.group(2)}-${match.group(1)}';
}

// ── BookingConfirmationPage ──────────────────────────────────────────────────
//
// Full-screen page for passenger data entry, comfort options and payment.
// Returns the created [VoyageBookingDocument] on success, or null on cancel.

class BookingConfirmationPage extends StatefulWidget {
  const BookingConfirmationPage({
    required this.trip,
    required this.segment,
    required this.displayDate,
    required this.totalFare,
    required this.selectedSeats,
    required this.hidePrice,
    required this.isLoggedIn,
    required this.authUser,
    required this.bookingService,
    required this.passengerNameControllers,
    required this.passengerContactControllers,
    required this.onLoginRequested,
    this.additionalServices = const <AdditionalServiceDocument>[],
    super.key,
  });

  final TripDetailModel trip;
  final TripSegmentModel segment;
  final String displayDate;
  final int totalFare;
  final int selectedSeats;
  final bool hidePrice;
  final bool isLoggedIn;
  final User? authUser;
  final VoyageBookingService bookingService;
  final List<TextEditingController> passengerNameControllers;
  final List<TextEditingController> passengerContactControllers;
  final Future<void> Function() onLoginRequested;
  final List<AdditionalServiceDocument> additionalServices;

  @override
  State<BookingConfirmationPage> createState() => _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage> {
  String? _errorText;
  bool _isSubmitting = false;
  final ScrollController _scrollController = ScrollController();
  late final String _submissionKey =
      'booking-${DateTime.now().microsecondsSinceEpoch}-${widget.trip.id}-${widget.selectedSeats}';
  late final List<FocusNode> _nameFocusNodes = List<FocusNode>.generate(
    widget.passengerNameControllers.length,
    (_) => FocusNode(),
    growable: false,
  );
  late final List<FocusNode> _phoneFocusNodes = List<FocusNode>.generate(
    widget.passengerContactControllers.length,
    (_) => FocusNode(),
    growable: false,
  );

  @override
  void initState() {
    super.initState();
    for (final FocusNode node in _nameFocusNodes) {
      node.addListener(_handleFieldFocusChange);
    }
    for (final FocusNode node in _phoneFocusNodes) {
      node.addListener(_handleFieldFocusChange);
    }
  }

  @override
  void dispose() {
    for (final FocusNode node in _nameFocusNodes) {
      node
        ..removeListener(_handleFieldFocusChange)
        ..dispose();
    }
    for (final FocusNode node in _phoneFocusNodes) {
      node
        ..removeListener(_handleFieldFocusChange)
        ..dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFieldFocusChange() {
    final FocusNode? focusedNode = <FocusNode>[
      ..._nameFocusNodes,
      ..._phoneFocusNodes,
    ].cast<FocusNode?>().firstWhere(
          (FocusNode? node) => node?.hasFocus ?? false,
          orElse: () => null,
        );
    if (focusedNode == null || focusedNode.context == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || focusedNode.context == null) return;
      Scrollable.ensureVisible(
        focusedNode.context!,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    });
  }

  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _submit() async {
    final List<String> passengerNames = widget.passengerNameControllers
        .map((c) => c.text.trim())
        .toList(growable: false);
    final List<String> passengerContacts = widget.passengerContactControllers
        .map((c) => c.text.trim())
        .toList(growable: false);

    if (passengerNames.any((name) => name.isEmpty)) {
      setState(() => _errorText = 'Veuillez saisir le nom de chaque passager.');
      return;
    }
    if (!widget.isLoggedIn && passengerContacts.first.isEmpty) {
      setState(() =>
          _errorText = "Le contact du premier passager est obligatoire si vous n'êtes pas connecté.");
      return;
    }

    final List<VoyageBookingTraveler> travelers = List<VoyageBookingTraveler>.generate(
      passengerNames.length,
      (int index) => VoyageBookingTraveler(
        name: passengerNames[index],
        contact: passengerContacts[index],
      ),
      growable: false,
    );

    _dismissKeyboard();

    // Step 1 — Comfort options
    final List<String>? selectedOptions = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConfortOptionsSheet(
        segmentFrom: widget.segment.departureNode.address,
        segmentTo: widget.segment.arrivalNode.address,
        additionalServices: widget.additionalServices,
      ),
    );
    if (selectedOptions == null || !mounted) return;

    // Step 2 — Compute comfort surcharge
    int comfortSurcharge = 0;
    for (final String optId in selectedOptions) {
      final ConfortOption? opt = kConfortOptions.cast<ConfortOption?>().firstWhere(
        (o) => o != null && (o.id == optId || optId.startsWith('${o.id}:')),
        orElse: () => null,
      );
      if (opt?.price != null) comfortSurcharge += opt!.price!;
    }
    final int paymentTotal = widget.totalFare + comfortSurcharge;

    // Step 3 — Pre-fill phone for payment sheet
    final String prefillPhone =
        widget.passengerContactControllers.first.text.trim().isNotEmpty
            ? widget.passengerContactControllers.first.text.trim()
            : (widget.authUser?.phoneNumber ?? '').trim();

    // Step 4 — Fetch eligible rewards (bus trips only)
    List<UserReward> eligibleRewards = const <UserReward>[];
    if (widget.trip.isBus && widget.authUser != null) {
      try {
        eligibleRewards =
            await ScratchService.instance.fetchEligibleRewardsForTransport();
      } catch (e) {
        debugPrint('[Rewards] fetchEligibleRewardsForTransport error: $e');
      }
    }
    if (!mounted) return;

    // Step 5 — Payment sheet
    final PaymentResult? paymentResult = await showModalBottomSheet<PaymentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height -
            kToolbarHeight -
            MediaQuery.of(context).padding.top,
      ),
      builder: (_) => PaymentSheet(
        totalAmount: paymentTotal,
        currency: widget.trip.currency.isEmpty ? 'XOF' : widget.trip.currency,
        userPhone: prefillPhone,
        eligibleRewards: eligibleRewards,
      ),
    );
    if (paymentResult == null || !mounted) return;

    // Step 6 — Create booking
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    try {
      final VoyageBookingDocument booking = await widget.bookingService.createBooking(
        CreateVoyageBookingInput(
          tripId: widget.trip.id,
          requestedSeats: widget.selectedSeats,
          requesterUid: widget.authUser?.uid,
          requesterTrackNum: '',
          requesterName: passengerNames.first,
          requesterContact: passengerContacts.first,
          requesterEmail: widget.authUser?.email,
          idempotencyKey: _submissionKey,
          effectiveDepartureDate: widget.displayDate,
          comfortOptions: selectedOptions,
          appliedRewardIds:
              eligibleRewards.map((r) => r.id).toList(growable: false),
          studentDiscount: paymentResult.studentDiscount,
          checkoutDiscount: paymentResult.checkoutDiscount,
          paymentDiscount: paymentResult.paymentDiscount,
          paymentMethod: paymentResult.paymentMethod,
          segmentFrom: widget.segment.departureNode.address,
          segmentTo: widget.segment.arrivalNode.address,
          segmentPrice: widget.segment.segmentPrice,
          travelers: travelers,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(booking);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: _travelPageBg,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.30)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 15, color: Colors.white),
            ),
          ),
        ),
        title: const Text('Passagers'),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismissKeyboard,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Trip summary header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isKeyboardVisible ? 12 : 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_travelAccentDark, _travelAccent],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.groups_rounded,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Informations passagers',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isKeyboardVisible) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formatFrDate(widget.displayDate),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Résumé',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.14),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.white.withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons
                                                  .airline_seat_recline_normal_rounded,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Expanded(
                                            child: Text(
                                              'Places',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white70),
                                            ),
                                          ),
                                          Text(
                                            '${widget.selectedSeats}',
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!widget.hidePrice) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Total',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white70),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${widget.totalFare} ${widget.trip.currency}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ).animate().fadeIn(duration: 260.ms).slideY(begin: -0.03, end: 0),
              ),
              const SizedBox(height: 12),

              // ── Passenger form ───────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.isLoggedIn)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _travelSurfaceBorder),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x120F766E),
                                  blurRadius: 20,
                                  offset: Offset(0, 8))
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                    color: _travelAccentSoft,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.person_outline_rounded,
                                    color: _travelAccentDark),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Connectez-vous pour pré-remplir vos informations.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF315A58)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: _travelAccentDark,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () {
                                          _dismissKeyboard();
                                          widget.onLoginRequested();
                                        },
                                  child: const Text('Se connecter'),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 260.ms, delay: 40.ms).slideY(begin: 0.04, end: 0),
                      if (!widget.isLoggedIn) const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _travelSurfaceBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 18, color: _travelAccentDark),
                            SizedBox(width: 8),
                            Text(
                              'Informations voyageurs',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Color(0xFF10233E)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...List<Widget>.generate(
                        widget.passengerNameControllers.length,
                        (int index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index ==
                                    widget.passengerNameControllers.length - 1
                                ? 0
                                : 12,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _travelSurfaceBorder),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x120F766E),
                                    blurRadius: 22,
                                    offset: Offset(0, 10))
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                          color: _travelAccentSoft,
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: _travelAccentDark),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Passager ${index + 1}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10233E)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller:
                                      widget.passengerNameControllers[index],
                                  focusNode: _nameFocusNodes[index],
                                  textInputAction: TextInputAction.next,
                                  scrollPadding:
                                      const EdgeInsets.only(bottom: 180),
                                  onTapOutside: (_) => _dismissKeyboard(),
                                  onSubmitted: (_) =>
                                      _phoneFocusNodes[index].requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'Nom complet',
                                    hintText: 'Entrez le nom du passager',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF9FFFE),
                                    prefixIcon: const Icon(
                                        Icons.person_outline_rounded),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelSurfaceBorder)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelSurfaceBorder)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelAccent, width: 1.5)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: widget
                                      .passengerContactControllers[index],
                                  focusNode: _phoneFocusNodes[index],
                                  keyboardType: TextInputType.phone,
                                  textInputAction: index ==
                                          widget.passengerNameControllers
                                                  .length -
                                              1
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  scrollPadding:
                                      const EdgeInsets.only(bottom: 220),
                                  onTapOutside: (_) => _dismissKeyboard(),
                                  onSubmitted: (_) {
                                    if (index ==
                                        widget.passengerNameControllers.length -
                                            1) {
                                      _dismissKeyboard();
                                      return;
                                    }
                                    _nameFocusNodes[index + 1].requestFocus();
                                  },
                                  decoration: InputDecoration(
                                    labelText: index == 0 && !widget.isLoggedIn
                                        ? 'Contact obligatoire'
                                        : 'Téléphone optionnel',
                                    hintText: 'Numéro du passager',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF9FFFE),
                                    prefixIcon:
                                        const Icon(Icons.phone_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelSurfaceBorder)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelSurfaceBorder)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                            color: _travelAccent, width: 1.5)),
                                  ),
                                ),
                              ],
                            ),
                          )
                              .animate()
                              .fadeIn(
                                  duration: 240.ms,
                                  delay: Duration(
                                      milliseconds: 80 + (index * 45)))
                              .slideY(begin: 0.04, end: 0),
                        ),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2F2),
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: const Color(0xFFFFD7D7)),
                          ),
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                                color: Color(0xFFB42318), fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Bottom action bar ────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          decoration: const BoxDecoration(
            color: Color(0xFFF9FFFE),
            border: Border(top: BorderSide(color: _travelSurfaceBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSubmitting) ...[
                const LinearProgressIndicator(
                  minHeight: 6,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  color: _travelAccent,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Réservation en cours...',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B647A)),
                ),
              ],
              if (isKeyboardVisible) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: _travelSurfaceBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _dismissKeyboard,
                    icon: const Icon(Icons.keyboard_hide_rounded),
                    label: const Text('Terminer la saisie'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _travelSurfaceBorder),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x140F766E),
                        blurRadius: 24,
                        offset: Offset(0, 10))
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(
                                color: _travelSurfaceBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isSubmitting
                              ? null
                              : () {
                                  _dismissKeyboard();
                                  Navigator.of(context).pop();
                                },
                          child: const Text('Annuler'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _travelAccent,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          child: Text(
                              _isSubmitting ? 'Traitement...' : 'Confirmer'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
