import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/data/trip_detail_repository_impl.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';
import 'package:govipservices/features/travel/data/additional_service_repository.dart';
import 'package:govipservices/features/travel/domain/models/additional_service_models.dart';
import 'package:govipservices/features/travel/presentation/pages/booking_confirmation_page.dart';
import 'package:govipservices/features/travel/presentation/pages/edit_trip_page.dart';
import 'package:govipservices/features/travel/presentation/pages/voyage_ticket_page.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_cubit.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_state.dart';
import 'package:govipservices/features/travel/presentation/widgets/owner_bookings_widgets.dart';
import 'package:govipservices/features/travel/presentation/widgets/trip_detail_display_widgets.dart';

const Color _travelAccent = Color(0xFF14B8A6);

String _formatFrDate(String raw) {
  final Match? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return raw;
  final String year = match.group(1)!;
  final String month = match.group(2)!;
  final String day = match.group(3)!;
  return '$day-$month-$year';
}

class TripDetailPage extends StatefulWidget {
  const TripDetailPage({
    required this.args,
    this.repository,
    super.key,
  });

  final TripDetailArgs args;
  final TripDetailRepository? repository;

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  late final TripDetailCubit _cubit;

  @override
  void initState() {
    super.initState();
    final TripDetailRepository repository = widget.repository ?? TripDetailRepositoryImpl();
    _cubit = TripDetailCubit(
      args: widget.args,
      getTripDetail: GetTripDetailUseCase(repository),
      buildTripRouteNodes: const BuildTripRouteNodesUseCase(),
      resolveTripSegment: const ResolveTripSegmentUseCase(),
      computeSegmentArrivalTime: const ComputeSegmentArrivalTimeUseCase(),
      computeSegmentFare: const ComputeSegmentFareUseCase(),
      frequencyLabelMapper: const TripFrequencyLabelMapper(),
    )..load();
  }

  @override
  void dispose() {
    _cubit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cubit,
      builder: (context, _) => TripDetailView(cubit: _cubit),
    );
  }
}

class TripDetailView extends StatelessWidget {
  const TripDetailView({required this.cubit, super.key});

  final TripDetailCubit cubit;

  @override
  Widget build(BuildContext context) {
    final TripDetailState state = cubit.state;

    return Scaffold(
      backgroundColor: _travelAccent,
      appBar: const TripDetailAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -36,
              right: -18,
              child: _DetailLiquidOrb(
                size: 148,
                color: Color(0x26FFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(-14, 18),
                durationMs: 5200,
              ),
            ),
            const Positioned(
              top: 220,
              left: -34,
              child: _DetailLiquidOrb(
                size: 126,
                color: Color(0x1AFFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(16, -14),
                durationMs: 6100,
              ),
            ),
            const Positioned(
              bottom: 120,
              right: -24,
              child: _DetailLiquidOrb(
                size: 118,
                color: Color(0x16FFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(-10, -12),
                durationMs: 5600,
              ),
            ),
            switch (state.status) {
              TripDetailStatus.initial || TripDetailStatus.loading => const TripLoadingSkeleton(),
              TripDetailStatus.error => TripErrorStateWidget(
                  message: state.errorMessage ?? 'Erreur inconnue.',
                  onRetry: cubit.load,
                  actionLabel: 'R\u00E9essayer',
                ),
              TripDetailStatus.invalidSegment => TripErrorStateWidget(
                  message: state.errorMessage ?? 'Segment invalide.',
                  onRetry: () => Navigator.of(context).pop(),
                  actionLabel: 'Retour',
                ),
              TripDetailStatus.success => _SuccessBody(cubit: cubit),
            },
          ],
        ),
      ),
    );
  }
}

class _DetailLiquidOrb extends StatelessWidget {
  const _DetailLiquidOrb({
    required this.size,
    required this.color,
    required this.beginOffset,
    required this.endOffset,
    required this.durationMs,
  });

  final double size;
  final Color color;
  final Offset beginOffset;
  final Offset endOffset;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .move(
            begin: beginOffset,
            end: endOffset,
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeInOutSine,
          )
          .scaleXY(
            begin: 0.98,
            end: 1.03,
            duration: Duration(milliseconds: durationMs + 700),
            curve: Curves.easeInOut,
          ),
    );
  }
}

class _SuccessBody extends StatefulWidget {
  const _SuccessBody({required this.cubit});

  final TripDetailCubit cubit;

  @override
  State<_SuccessBody> createState() => _SuccessBodyState();
}

class _SuccessBodyState extends State<_SuccessBody> {
  final VoyageBookingService _bookingService = VoyageBookingService();
  final AdditionalServiceRepository _additionalServiceRepo =
      const AdditionalServiceRepository();
  List<VoyageBookingDocument> _ownerBookings = const <VoyageBookingDocument>[];
  StreamSubscription<List<VoyageBookingDocument>>? _ownerBookingsSubscription;
  String? _inlineBusyBookingId;
  List<AdditionalServiceDocument> _additionalServices =
      const <AdditionalServiceDocument>[];

  TripDetailCubit get cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _primeOwnerBookings();
    _fetchAdditionalServices();
  }

  Future<void> _fetchAdditionalServices() async {
    try {
      final List<AdditionalServiceDocument> services =
          await _additionalServiceRepo.fetchAll();
      if (mounted) setState(() => _additionalServices = services);
    } catch (_) {
      // Silencieux — les options seront toutes visibles en cas d'erreur
    }
  }

  void _primeOwnerBookings() {
    final TripDetailModel? trip = cubit.state.trip;
    final bool shouldLoad = trip != null &&
        (cubit.accessMode == TripDetailAccessMode.owner ||
            cubit.accessMode == TripDetailAccessMode.supportOnly);
    if (!shouldLoad) return;
    _ownerBookingsSubscription ??= _bookingService
        .watchBookingsByTripId(trip.id)
        .listen(_handleOwnerBookingsChanged);
  }

  void _handleOwnerBookingsChanged(List<VoyageBookingDocument> bookings) {
    if (mounted) {
      setState(() {
        _ownerBookings = bookings;
      });
    } else {
      _ownerBookings = bookings;
    }
  }

  @override
  void dispose() {
    _ownerBookingsSubscription?.cancel();
    super.dispose();
  }

  bool _shouldHidePrice(TripSegmentModel segment) {
    final bool isIntermediateDeparture = segment.departureNode.kind == 'stop';
    final bool isIntermediateArrival = segment.arrivalNode.kind == 'stop';
    return isIntermediateDeparture && isIntermediateArrival && segment.segmentPrice == 0;
  }

  Widget _animateSection(Widget child, {int delayMs = 0}) {
    return child
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs), duration: 280.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  bool get _isOwnerMode => cubit.accessMode == TripDetailAccessMode.owner;
  bool get _isSupportOnlyMode => cubit.accessMode == TripDetailAccessMode.supportOnly;
  bool get _showsManagementPanel => _isOwnerMode || _isSupportOnlyMode;

  Future<void> _refreshDetail() async {
    await cubit.load();
  }

  void _showInfoMessage(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFF991B1B) : const Color(0xFF0F766E),
          content: Text(message),
        ),
      );
  }

  Future<void> _showSupportDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRelatedBookings(BuildContext context, TripDetailModel trip) async {
    showRelatedBookingsSheet(
      context,
      bookings: _ownerBookings,
      onBookingsChanged: (next) => setState(() => _ownerBookings = next),
    );
  }

  Future<void> _handleEditTrip(BuildContext context, TripDetailModel trip) async {
    if (_isSupportOnlyMode) {
      await _showSupportDialog(
        context,
        title: 'Modification via support',
        message:
            'Ce trajet a été retrouvé via son numéro de suivi. Pour le modifier, veuillez contacter le support.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditTripPage(tripId: trip.id),
      ),
    );
    await cubit.load();
  }

  Future<void> _handleDeleteTrip(BuildContext context, TripDetailModel trip) async {
    if (_isSupportOnlyMode) {
      await _showSupportDialog(
        context,
        title: 'Suppression via support',
        message:
            'Ce trajet a été retrouvé via son numéro de suivi. Pour le supprimer, veuillez contacter le support.',
      );
      return;
    }

    final List<VoyageBookingDocument> bookings = _ownerBookings;
    final bool hasAcceptedBooking = bookings.any((booking) {
      final String status = booking.status.trim().toLowerCase();
      return status == 'accepted' || status == 'approved' || status == 'confirmed';
    });

    if (hasAcceptedBooking) {
      await _showSupportDialog(
        context,
        title: 'Suppression bloquée',
        message:
            'Au moins une réservation acceptée est associée à ce trajet. Veuillez contacter le support.',
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Supprimer ce trajet ?'),
          content: Text(
            bookings.isEmpty
                ? 'Ce trajet sera supprimé de vos trajets publiés.'
                : 'Ce trajet sera supprimé. ${bookings.length} réservation(s) liée(s) resteront consultables pour suivi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !context.mounted) return;

    await TravelRepository().cancelTripById(trip.id);
    if (!context.mounted) return;
    _showInfoMessage(context, 'Trajet supprimé.');
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  List<MapEntry<int, TripRouteNode>> _availableDepartureStops(List<TripRouteNode> nodes, TripSegmentModel segment) {
    return nodes.asMap().entries.where((entry) {
      final int index = entry.key;
      final TripRouteNode node = entry.value;
      return node.kind == 'stop' && node.bookable && index < segment.arrivalIndex;
    }).toList(growable: false);
  }

  List<MapEntry<int, TripRouteNode>> _availableArrivalStops(List<TripRouteNode> nodes, TripSegmentModel segment) {
    return nodes.asMap().entries.where((entry) {
      final int index = entry.key;
      final TripRouteNode node = entry.value;
      return node.kind == 'stop' && node.bookable && index > segment.departureIndex;
    }).toList(growable: false);
  }

  Future<void> _showDepartureOptions(
    BuildContext context, {
    required List<TripRouteNode> nodes,
    required TripSegmentModel segment,
  }) async {
    final List<MapEntry<int, TripRouteNode>> stops = _availableDepartureStops(nodes, segment);
    if (stops.isEmpty) return;
    showIntermediateStopSheet(
      context,
      title: 'Choisir un autre départ',
      subtitle: 'Sélectionnez un point de montée intermédiaire.',
      stops: stops,
      selectedIndex: segment.departureIndex,
      onSelect: cubit.selectDepartureNode,
    );
  }

  Future<void> _showArrivalOptions(
    BuildContext context, {
    required List<TripRouteNode> nodes,
    required TripSegmentModel segment,
  }) async {
    final List<MapEntry<int, TripRouteNode>> stops = _availableArrivalStops(nodes, segment);
    if (stops.isEmpty) return;
    showIntermediateStopSheet(
      context,
      title: 'Choisir une autre arrivée',
      subtitle: 'Sélectionnez un point de descente intermédiaire.',
      stops: stops,
      selectedIndex: segment.arrivalIndex,
      onSelect: cubit.selectArrivalNode,
    );
  }

  Future<String> _resolveConnectedUserPhone(User? authUser) async {
    if (authUser == null) return '';
    final String authPhone = (authUser.phoneNumber ?? '').trim();
    if (authPhone.isNotEmpty) return authPhone;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final Map<String, dynamic>? phone = data['phone'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['phone'] as Map<String, dynamic>)
          : null;
      final String countryCode = (phone?['countryCode'] as String?)?.trim() ?? '';
      final String number = (phone?['number'] as String?)?.trim() ?? '';
      final String fullPhone = [countryCode, number].where((part) => part.isNotEmpty).join(' ').trim();
      if (fullPhone.isNotEmpty) return fullPhone;
      return (data['contactPhone'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _showBookingSuccessDialog(
    BuildContext context, {
    required VoyageBookingDocument booking,
    required int passengerCount,
  }) async {
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VoyageTicketPage(booking: booking),
      ),
    );
  }

  Future<void> _onBookPressed(BuildContext context) async {
    final BuildContext rootContext = context;
    final TripDetailState state = cubit.state;
    final TripDetailModel? trip = state.trip;
    if (trip == null || state.segment == null) return;
    final TripSegmentModel segment = state.segment!;
    final bool hidePrice = _shouldHidePrice(segment);
    final VoyageBookingService bookingService = VoyageBookingService();
    final User? authUser = FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = authUser != null;
    final String initialPassengerPhone = isLoggedIn ? await _resolveConnectedUserPhone(authUser) : '';
    final List<TextEditingController> passengerNameControllers = List<TextEditingController>.generate(
      state.selectedSeats,
      (int index) => TextEditingController(
        text: index == 0 ? (authUser?.displayName?.trim() ?? '') : '',
      ),
      growable: false,
    );
    final List<TextEditingController> passengerContactControllers = List<TextEditingController>.generate(
      state.selectedSeats,
      (int index) => TextEditingController(
        text: index == 0 ? initialPassengerPhone : '',
      ),
      growable: false,
    );

    try {
      final VoyageBookingDocument? createdBooking = await Navigator.of(context).push<VoyageBookingDocument>(
        MaterialPageRoute<VoyageBookingDocument>(
          fullscreenDialog: true,
          builder: (_) => BookingConfirmationPage(
            trip: trip,
            segment: segment,
            displayDate: cubit.displayDate,
            totalFare: cubit.totalFare,
            selectedSeats: state.selectedSeats,
            hidePrice: hidePrice,
            isLoggedIn: isLoggedIn,
            authUser: authUser,
            bookingService: bookingService,
            passengerNameControllers: passengerNameControllers,
            passengerContactControllers: passengerContactControllers,
            additionalServices: _additionalServices,
            onLoginRequested: () async {
              Navigator.of(rootContext).pop();
              await Future<void>.delayed(const Duration(milliseconds: 120));
              await Navigator.of(rootContext).pushNamed(AppRoutes.authLogin);
              if (!rootContext.mounted) return;
              if (FirebaseAuth.instance.currentUser != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!rootContext.mounted) return;
                  _onBookPressed(rootContext);
                });
              }
            },
          ),
        ),
      );
      if (!rootContext.mounted || createdBooking == null) return;
      await _showBookingSuccessDialog(
        rootContext,
        booking: createdBooking,
        passengerCount: state.selectedSeats,
      );
    } finally {
      for (final TextEditingController c in passengerNameControllers) {
        c.dispose();
      }
      for (final TextEditingController c in passengerContactControllers) {
        c.dispose();
      }
    }
  }

  Future<void> _setInlineBookingStatus(
    BuildContext context,
    VoyageBookingDocument booking,
    String status,
  ) async {
    setState(() {
      _inlineBusyBookingId = booking.id;
    });
    try {
      await _bookingService.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (!context.mounted) return;
      _showInfoMessage(
        context,
        status == 'accepted' ? 'Réservation acceptée.' : 'Réservation refusée.',
      );
    } catch (_) {
      if (!context.mounted) return;
      _showInfoMessage(
        context,
        'Mise à jour impossible pour le moment.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _inlineBusyBookingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _primeOwnerBookings();
    final TripDetailState state = cubit.state;
    final TripDetailModel trip = state.trip!;
    final TripSegmentModel segment = state.segment!;
    final bool hidePrice = _shouldHidePrice(segment);
    final List<VoyageBookingDocument> pendingBookings = _ownerBookings
        .where((booking) => booking.status.trim().toLowerCase() == 'pending')
        .toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshDetail,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _animateSection(TripSegmentCard(
                    dateLabel: _formatFrDate(cubit.displayDate),
                    frequencyLabel: cubit.frequencyLabel,
                    seats: state.availableSeats ?? trip.seats,
                    segment: segment,
                    canPickDate: cubit.canSelectTravelDate,
                    showNotice: cubit.showAutoAdjustedDateNotice,
                    noticeText: cubit.autoAdjustedDateMessage,
                    onPickDate: () => _pickTravelDate(context),
                  ), delayMs: 20),
                  const SizedBox(height: 12),
                  _animateSection(
                    TripTimelineWidget(
                      segment: segment,
                      showAlternativeDepartures: _availableDepartureStops(state.nodes, segment).isNotEmpty,
                      onOpenAlternativeDepartures: () => _showDepartureOptions(
                        context,
                        nodes: state.nodes,
                        segment: segment,
                      ),
                      showAlternativeArrivals: _availableArrivalStops(state.nodes, segment).isNotEmpty,
                      onOpenAlternativeArrivals: () => _showArrivalOptions(
                        context,
                        nodes: state.nodes,
                        segment: segment,
                      ),
                    ),
                    delayMs: 70,
                  ),
                  const SizedBox(height: 12),
                  if (!hidePrice) ...[
                    _animateSection(TripFareCard(
                      unitFare: segment.segmentPrice,
                      currency: trip.currency,
                      seats: state.selectedSeats,
                      total: cubit.totalFare,
                    ), delayMs: 120),
                    const SizedBox(height: 12),
                  ],
                  _animateSection(TripDriverCard(driver: trip.driver), delayMs: 160),
                  const SizedBox(height: 12),
                  _animateSection(TripVehicleCard(vehicle: trip.vehicle), delayMs: 210),
                  const SizedBox(height: 12),
                  _animateSection(TripOptionsChips(options: trip.options), delayMs: 250),
                  if (_showsManagementPanel && pendingBookings.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _animateSection(
                      InlineBookingsPanel(
                        bookings: pendingBookings.take(3).toList(growable: false),
                        busyBookingId: _inlineBusyBookingId,
                        onAccept: (booking) => _setInlineBookingStatus(
                          context,
                          booking,
                          'accepted',
                        ),
                        onReject: (booking) => _setInlineBookingStatus(
                          context,
                          booking,
                          'rejected',
                        ),
                        onViewAll: () => _showRelatedBookings(context, trip),
                      ),
                      delayMs: 285,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_showsManagementPanel)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: TripOwnerActionsCard(
                supportOnly: _isSupportOnlyMode,
                reservationCount: _ownerBookings.length,
                onEdit: () => _handleEditTrip(context, trip),
                onDelete: () => _handleDeleteTrip(context, trip),
                onViewBookings: () => _showRelatedBookings(context, trip),
              ),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE8EDF5))),
              boxShadow: [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 12,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TripBookingPanel(
                  selectedSeats: state.selectedSeats,
                  maxSeats: (state.availableSeats ?? trip.seats) < 1
                      ? 1
                      : (state.availableSeats ?? trip.seats),
                  currency: trip.currency,
                  total: cubit.totalFare,
                  hidePrice: hidePrice,
                  canBook: cubit.isBookable,
                  onIncrement: cubit.incrementSeats,
                  onDecrement: cubit.decrementSeats,
                  onBook: () => _onBookPressed(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickTravelDate(BuildContext context) async {
    final TripDetailModel? trip = cubit.state.trip;
    if (trip == null || !cubit.canSelectTravelDate) return;
    final DateTime now = DateTime.now();
    final DateTime initialDate = DateTime.tryParse(cubit.displayDate) ?? now;
    final DateTime firstDate = DateTime(now.year, now.month, now.day);
    final DateTime lastDate = firstDate.add(const Duration(days: 365));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      selectableDayPredicate: cubit.isSelectableTravelDate,
      helpText: 'Choisir la date du voyage',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );
    if (picked == null) return;
    await cubit.selectTravelDate(picked);
  }
}
