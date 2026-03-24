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
import 'package:govipservices/features/travel/presentation/pages/edit_trip_page.dart';
import 'package:govipservices/features/travel/presentation/pages/voyage_ticket_page.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_cubit.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_state.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/shared/services/location_service.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);
const Color _travelSurfaceBorder = Color(0xFFD8F3EE);
const Color _travelPageBg = Color(0xFFF2FFFC);

String _formatFrDate(String raw) {
  final Match? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return raw;
  final String year = match.group(1)!;
  final String month = match.group(2)!;
  final String day = match.group(3)!;
  return '$day-$month-$year';
}

String _bookingStatusLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'accepted':
    case 'approved':
    case 'confirmed':
      return 'Acceptée';
    case 'rejected':
    case 'refused':
      return 'Refusée';
    case 'cancelled':
      return 'Annulée';
    case 'pending':
    default:
      return 'En attente';
  }
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
  List<VoyageBookingDocument> _ownerBookings = const <VoyageBookingDocument>[];
  StreamSubscription<List<VoyageBookingDocument>>? _ownerBookingsSubscription;
  String? _inlineBusyBookingId;

  TripDetailCubit get cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _primeOwnerBookings();
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
    final List<VoyageBookingDocument> bookings = _ownerBookings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _travelPageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: _RelatedBookingsSheetContent(
              initialBookings: bookings,
              onBookingsChanged: (next) {
                setState(() {
                  _ownerBookings = next;
                });
              },
            ),
          ),
        );
      },
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
      return node.kind == 'stop' && index < segment.arrivalIndex;
    }).toList(growable: false);
  }

  List<MapEntry<int, TripRouteNode>> _availableArrivalStops(List<TripRouteNode> nodes, TripSegmentModel segment) {
    return nodes.asMap().entries.where((entry) {
      final int index = entry.key;
      final TripRouteNode node = entry.value;
      return node.kind == 'stop' && index > segment.departureIndex;
    }).toList(growable: false);
  }

  Future<void> _showDepartureOptions(
    BuildContext context, {
    required List<TripRouteNode> nodes,
    required TripSegmentModel segment,
  }) async {
    final List<MapEntry<int, TripRouteNode>> stops = _availableDepartureStops(nodes, segment);
    if (stops.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _travelPageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choisir un autre départ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sélectionnez un point de montée intermédiaire.',
                  style: TextStyle(
                    color: Color(0xFF5B647A),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: stops.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final MapEntry<int, TripRouteNode> entry = stops[index];
                      final bool isSelected = entry.key == segment.departureIndex;
                      return _IntermediateStopOption(
                        node: entry.value,
                        isSelected: isSelected,
                        onTap: () async {
                          await cubit.selectDepartureNode(entry.key);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showArrivalOptions(
    BuildContext context, {
    required List<TripRouteNode> nodes,
    required TripSegmentModel segment,
  }) async {
    final List<MapEntry<int, TripRouteNode>> stops = _availableArrivalStops(nodes, segment);
    if (stops.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _travelPageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choisir une autre arrivée',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sélectionnez un point de descente intermédiaire.',
                  style: TextStyle(
                    color: Color(0xFF5B647A),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: stops.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final MapEntry<int, TripRouteNode> entry = stops[index];
                      final bool isSelected = entry.key == segment.arrivalIndex;
                      return _IntermediateStopOption(
                        node: entry.value,
                        isSelected: isSelected,
                        onTap: () async {
                          await cubit.selectArrivalNode(entry.key);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
          builder: (_) => _BookingConfirmationDialog(
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
      return;
    } finally {
      for (final TextEditingController c in passengerNameControllers) {
        c.dispose();
      }
      for (final TextEditingController c in passengerContactControllers) {
        c.dispose();
      }
    }

    try {
      final VoyageBookingDocument? createdBooking =
          await showModalBottomSheet<VoyageBookingDocument>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          String? errorText;
          bool isSubmitting = false;
          return StatefulBuilder(
            builder: (context, setModalState) => SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'Confirmer la r\u00E9servation',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('${segment.departureNode.address} -> ${segment.arrivalNode.address}'),
                  const SizedBox(height: 6),
                  Text('Date : ${_formatFrDate(cubit.displayDate)}'),
                  const SizedBox(height: 6),
                  Text('Places: ${state.selectedSeats}'),
                  const SizedBox(height: 6),
                  if (!hidePrice)
                    Text(
                      'Total: ${cubit.totalFare} ${trip.currency}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: _travelAccentDark),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nom des passagers',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (!isLoggedIn)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        const Text(
                          'Connectez-vous pour pr\u00E9-remplir vos informations.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF5B647A)),
                        ),
                        TextButton(
                          onPressed: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.of(context).pop();
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
                          child: const Text('Se connecter'),
                        ),
                      ],
                    ),
                  if (!isLoggedIn) const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: passengerNameControllers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return Column(
                          children: [
                            TextField(
                              controller: passengerNameControllers[index],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Passager ${index + 1} (nom)',
                                hintText: 'Nom complet',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: passengerContactControllers[index],
                              keyboardType: TextInputType.phone,
                              textInputAction: index == passengerNameControllers.length - 1
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: index == 0 && !isLoggedIn
                                    ? 'Passager 1 (contact obligatoire)'
                                    : 'Passager ${index + 1} (contact optionnel)',
                                hintText: 'T\u00E9l\u00E9phone',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (errorText == null)
                    const SizedBox(height: 10)
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  if (isSubmitting) ...[
                    const SizedBox(height: 12),
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
                        color: Color(0xFF5B647A),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                        final List<String> passengerNames = passengerNameControllers
                            .map((TextEditingController c) => c.text.trim())
                            .toList(growable: false);
                        final List<String> passengerContacts = passengerContactControllers
                            .map((TextEditingController c) => c.text.trim())
                            .toList(growable: false);
                        if (passengerNames.any((name) => name.isEmpty)) {
                          setModalState(() {
                            errorText = 'Veuillez saisir le nom de chaque passager.';
                          });
                          return;
                        }
                        if (!isLoggedIn && passengerContacts.first.isEmpty) {
                          setModalState(() {
                            errorText =
                                'Le contact du premier passager est obligatoire si vous n\u2019\u00EAtes pas connect\u00E9.';
                          });
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

                        final String requesterName = passengerNames.first;
                        final String requesterContact = passengerContacts.first;

                        setModalState(() {
                          errorText = null;
                          isSubmitting = true;
                        });

                        try {
                          final VoyageBookingDocument booking = await bookingService.createBooking(
                            CreateVoyageBookingInput(
                              tripId: trip.id,
                              requestedSeats: state.selectedSeats,
                              requesterUid: authUser?.uid,
                              requesterTrackNum: '',
                              requesterName: requesterName,
                              requesterContact: requesterContact,
                              requesterEmail: authUser?.email,
                              effectiveDepartureDate: cubit.displayDate,
                              segmentFrom: segment.departureNode.address,
                              segmentTo: segment.arrivalNode.address,
                              segmentPrice: segment.segmentPrice,
                              travelers: travelers,
                            ),
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop(booking);
                          }
                        } catch (error) {
                          setModalState(() {
                            errorText = error.toString().replaceFirst('Exception: ', '');
                            isSubmitting = false;
                          });
                        }
                      },
                      child: Text(isSubmitting ? 'Traitement...' : 'Confirmer et envoyer'),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          );
        },
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
                      showAlternativeDepartures: trip.intermediateStops.isNotEmpty,
                      onOpenAlternativeDepartures: () => _showDepartureOptions(
                        context,
                        nodes: state.nodes,
                        segment: segment,
                      ),
                      showAlternativeArrivals: trip.intermediateStops.isNotEmpty,
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
                      _InlineBookingsPanel(
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

class _BookingConfirmationDialog extends StatefulWidget {
  const _BookingConfirmationDialog({
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

  @override
  State<_BookingConfirmationDialog> createState() => _BookingConfirmationDialogState();
}

class _BookingConfirmationDialogState extends State<_BookingConfirmationDialog> {
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

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _submit() async {
    final List<String> passengerNames = widget.passengerNameControllers
        .map((TextEditingController c) => c.text.trim())
        .toList(growable: false);
    final List<String> passengerContacts = widget.passengerContactControllers
        .map((TextEditingController c) => c.text.trim())
        .toList(growable: false);

    if (passengerNames.any((name) => name.isEmpty)) {
      setState(() {
        _errorText = 'Veuillez saisir le nom de chaque passager.';
      });
      return;
    }
    if (!widget.isLoggedIn && passengerContacts.first.isEmpty) {
      setState(() {
        _errorText = 'Le contact du premier passager est obligatoire si vous n’êtes pas connecté.';
      });
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

    FocusManager.instance.primaryFocus?.unfocus();

    // Show comfort options sheet before submitting
    final List<String>? selectedOptions = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ConfortOptionsSheet(),
    );
    // null means dismissed without confirming
    if (selectedOptions == null || !mounted) return;

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
                border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
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
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.groups_rounded, color: Colors.white),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Résumé',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.14),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.airline_seat_recline_normal_rounded,
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
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${widget.selectedSeats}',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!widget.hidePrice) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Total',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${widget.totalFare} ${widget.trip.currency}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
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
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _travelAccentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  color: _travelAccentDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Connectez-vous pour pré-remplir vos informations.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF315A58),
                                  ),
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
                                      borderRadius: BorderRadius.circular(12),
                                    ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _travelSurfaceBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 18,
                              color: _travelAccentDark,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Informations voyageurs',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Color(0xFF10233E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...List<Widget>.generate(
                        widget.passengerNameControllers.length,
                        (int index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index == widget.passengerNameControllers.length - 1 ? 0 : 12,
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
                                  offset: Offset(0, 10),
                                ),
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
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: _travelAccentDark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Passager ${index + 1}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF10233E),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: widget.passengerNameControllers[index],
                                  focusNode: _nameFocusNodes[index],
                                  textInputAction: TextInputAction.next,
                                  scrollPadding: const EdgeInsets.only(bottom: 180),
                                  onTapOutside: (_) => _dismissKeyboard(),
                                  onSubmitted: (_) => _phoneFocusNodes[index].requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'Nom complet',
                                    hintText: 'Entrez le nom du passager',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF9FFFE),
                                    prefixIcon: const Icon(Icons.person_outline_rounded),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelSurfaceBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelSurfaceBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelAccent, width: 1.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: widget.passengerContactControllers[index],
                                  focusNode: _phoneFocusNodes[index],
                                  keyboardType: TextInputType.phone,
                                  textInputAction: index == widget.passengerNameControllers.length - 1
                                      ? TextInputAction.done
                                      : TextInputAction.next,
                                  scrollPadding: const EdgeInsets.only(bottom: 220),
                                  onTapOutside: (_) => _dismissKeyboard(),
                                  onSubmitted: (_) {
                                    if (index == widget.passengerNameControllers.length - 1) {
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
                                    prefixIcon: const Icon(Icons.phone_outlined),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelSurfaceBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelSurfaceBorder),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(color: _travelAccent, width: 1.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(
                            duration: 240.ms,
                            delay: Duration(milliseconds: 80 + (index * 45)),
                          ).slideY(begin: 0.04, end: 0),
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
                            border: Border.all(color: const Color(0xFFFFD7D7)),
                          ),
                          child: Text(
                            _errorText!,
                            style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
                    color: Color(0xFF5B647A),
                  ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      offset: Offset(0, 10),
                    ),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: _travelSurfaceBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isSubmitting ? null : _submit,
                          child: Text(_isSubmitting ? 'Traitement...' : 'Confirmer'),
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

class TripDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TripDetailAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
          ),
        ),
      ),
      title: const Text('D\u00E9tail du trajet'),
      elevation: 0,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class TripSegmentCard extends StatelessWidget {
  const TripSegmentCard({
    required this.dateLabel,
    required this.frequencyLabel,
    required this.seats,
    required this.segment,
    required this.canPickDate,
    required this.showNotice,
    required this.noticeText,
    this.onPickDate,
    super.key,
  });

  final String dateLabel;
  final String frequencyLabel;
  final int seats;
  final TripSegmentModel segment;
  final bool canPickDate;
  final bool showNotice;
  final String noticeText;
  final VoidCallback? onPickDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPickDate)
                GestureDetector(
                  onTap: onPickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _travelAccentDark.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 14, color: _travelAccentDark),
                        const SizedBox(width: 5),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _travelAccentDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 15, color: _travelAccentDark),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  dateLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A2747)),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _travelAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  frequencyLabel,
                  style: const TextStyle(
                    color: _travelAccentDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$seats place(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF53658D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Disponible(s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A8CA8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showNotice) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF9A3412)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      noticeText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _IntermediateStopOption extends StatelessWidget {
  const _IntermediateStopOption({
    required this.node,
    required this.isSelected,
    required this.onTap,
  });

  final TripRouteNode node;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? _travelAccentSoft : const Color(0xFFF8FFFD),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected ? _travelAccent : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _travelAccent.withOpacity(0.24)),
                ),
                child: Icon(
                  isSelected ? Icons.check_rounded : Icons.place_outlined,
                  size: 18,
                  color: isSelected ? Colors.white : _travelAccentDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.address,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (node.time.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Heure estimée : ${node.time}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5B647A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                isSelected ? 'Selectionne' : 'Choisir',
                style: TextStyle(
                  color: isSelected ? _travelAccentDark : _travelAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripTimelineWidget extends StatelessWidget {
  const TripTimelineWidget({
    required this.segment,
    this.showAlternativeDepartures = false,
    this.onOpenAlternativeDepartures,
    this.showAlternativeArrivals = false,
    this.onOpenAlternativeArrivals,
    super.key,
  });

  final TripSegmentModel segment;
  final bool showAlternativeDepartures;
  final VoidCallback? onOpenAlternativeDepartures;
  final bool showAlternativeArrivals;
  final VoidCallback? onOpenAlternativeArrivals;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.departureNode.time.isEmpty ? '--:--' : segment.departureNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    segment.arrivalNode.time.isEmpty ? '--:--' : segment.arrivalNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: _travelAccent, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: const Color(0xFFCAD6EE)),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF8FA5CF), shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(segment.departureNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (showAlternativeDepartures && onOpenAlternativeDepartures != null) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: onOpenAlternativeDepartures,
                          icon: const Icon(Icons.alt_route_rounded, size: 16),
                          label: const Text('Changer départ'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _travelAccentDark,
                            side: const BorderSide(color: _travelSurfaceBorder),
                            backgroundColor: _travelAccentSoft.withOpacity(0.35),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(segment.arrivalNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (showAlternativeArrivals && onOpenAlternativeArrivals != null) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: onOpenAlternativeArrivals,
                          icon: const Icon(Icons.location_on_outlined, size: 16),
                          label: const Text('Changer arrivée'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _travelAccentDark,
                            side: const BorderSide(color: _travelSurfaceBorder),
                            backgroundColor: _travelAccentSoft.withOpacity(0.35),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TripFareCard extends StatelessWidget {
  const TripFareCard({
    required this.unitFare,
    required this.currency,
    required this.seats,
    required this.total,
    super.key,
  });

  final int unitFare;
  final String currency;
  final int seats;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tarif', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Prix: $unitFare $currency', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Total ($seats place(s)): $total $currency', style: const TextStyle(fontWeight: FontWeight.w800, color: _travelAccentDark)),
        ],
      ),
    );
  }
}

class TripDriverCard extends StatelessWidget {
  const TripDriverCard({required this.driver, super.key});

  final DriverInfoModel driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.name.isEmpty ? 'Conducteur non renseign\u00E9' : driver.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Contact partag\u00E9 apr\u00E8s confirmation',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B647A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TripVehicleCard extends StatelessWidget {
  const TripVehicleCard({required this.vehicle, super.key});

  final VehicleInfoModel vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vehicle.model.isEmpty ? 'V\u00E9hicule non renseign\u00E9' : vehicle.model,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class TripOptionsChips extends StatelessWidget {
  const TripOptionsChips({required this.options, super.key});

  final TripOptionsModel options;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      _OptionChip(
        icon: Icons.luggage_outlined,
        label: options.hasLuggageSpace ? 'Bagages autorises' : 'Sans bagage',
      ),
      _OptionChip(
        icon: Icons.pets_outlined,
        label: options.allowsPets ? 'Animaux autorises' : 'Sans animaux',
      ),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class TripOwnerActionsCard extends StatelessWidget {
  const TripOwnerActionsCard({
    required this.supportOnly,
    required this.reservationCount,
    required this.onEdit,
    required this.onDelete,
    required this.onViewBookings,
    super.key,
  });

  final bool supportOnly;
  final int reservationCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewBookings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            supportOnly ? 'Support' : 'Actions',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OwnerActionIconButton(
                icon: Icons.receipt_long_rounded,
                tooltip: 'Voir les résas',
                count: reservationCount,
                onTap: onViewBookings,
              ),
              const SizedBox(width: 8),
              _OwnerActionIconButton(
                icon: Icons.edit_rounded,
                tooltip: supportOnly ? 'Modifier via support' : 'Modifier',
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _OwnerActionIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: supportOnly ? 'Supprimer via support' : 'Supprimer',
                danger: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineBookingsPanel extends StatelessWidget {
  const _InlineBookingsPanel({
    super.key,
    required this.bookings,
    required this.busyBookingId,
    required this.onAccept,
    required this.onReject,
    required this.onViewAll,
  });

  final List<VoyageBookingDocument> bookings;
  final String? busyBookingId;
  final ValueChanged<VoyageBookingDocument> onAccept;
  final ValueChanged<VoyageBookingDocument> onReject;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nouvelles réservations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Réagissez immédiatement sans quitter le détail du trajet.',
            style: TextStyle(
              color: Color(0xFF5B647A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < bookings.length; index++) ...[
            _InlineBookingRow(
              booking: bookings[index],
              isBusy: busyBookingId == bookings[index].id,
              onAccept: () => onAccept(bookings[index]),
              onReject: () => onReject(bookings[index]),
            ),
            if (index < bookings.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}


class _InlineBookingRow extends StatelessWidget {
  const _InlineBookingRow({
    required this.booking,
    required this.onAccept,
    required this.onReject,
    this.isBusy = false,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FFFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.requesterName.isEmpty
                      ? 'Demandeur non renseigné'
                      : booking.requesterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _travelAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: _travelAccentDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${booking.segmentFrom} -> ${booking.segmentTo}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Réf: ${booking.trackNum}',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: _travelAccentDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accepter'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    side: const BorderSide(color: Color(0xFFF04438)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Refuser'),
                ),
              ),
              if (isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerActionIconButton extends StatelessWidget {
  const _OwnerActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.count,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? const Color(0xFFB42318) : _travelAccentDark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: danger ? const Color(0xFFFFE4E0) : _travelAccentSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: count == null ? 8 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RelatedBookingCard extends StatelessWidget {
  const _RelatedBookingCard({
    required this.booking,
    required this.onAccept,
    required this.onReject,
    required this.onWrite,
    this.isBusy = false,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onWrite;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.requesterName.isEmpty ? 'Demandeur non renseigné' : booking.requesterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10233E),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _bookingStatusLabel(booking.status),
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Réf: ${booking.trackNum}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${booking.segmentFrom} -> ${booking.segmentTo}',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BookingMetaPill(
                icon: Icons.event_seat_rounded,
                label: '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
              ),
              _BookingMetaPill(
                icon: Icons.payments_outlined,
                label: '${booking.totalPrice} ${booking.tripCurrency}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _BookingActionChip(
                label: 'Accepter',
                icon: Icons.check_rounded,
                onTap: isBusy ? null : onAccept,
              ),
              const SizedBox(width: 8),
              _BookingActionChip(
                label: 'Refuser',
                icon: Icons.close_rounded,
                danger: true,
                onTap: isBusy ? null : onReject,
              ),
              const SizedBox(width: 8),
              _BookingActionChip(
                label: 'Ecrire',
                icon: Icons.chat_bubble_outline_rounded,
                onTap: isBusy ? null : onWrite,
              ),
              if (isBusy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingActionChip extends StatelessWidget {
  const _BookingActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? const Color(0xFFB42318) : _travelAccentDark;
    final Color bg = danger ? const Color(0xFFFFE4E0) : _travelAccentSoft;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingMetaPill extends StatelessWidget {
  const _BookingMetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF667085)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedBookingsSheetContent extends StatefulWidget {
  const _RelatedBookingsSheetContent({
    required this.initialBookings,
    required this.onBookingsChanged,
  });

  final List<VoyageBookingDocument> initialBookings;
  final ValueChanged<List<VoyageBookingDocument>> onBookingsChanged;

  @override
  State<_RelatedBookingsSheetContent> createState() => _RelatedBookingsSheetContentState();
}

class _RelatedBookingsSheetContentState extends State<_RelatedBookingsSheetContent> {
  final VoyageBookingService _bookingService = VoyageBookingService();
  String? _busyBookingId;
  late List<VoyageBookingDocument> _bookings;

  @override
  void initState() {
    super.initState();
    _bookings = List<VoyageBookingDocument>.from(widget.initialBookings);
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
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

  Future<void> _setBookingStatus(VoyageBookingDocument booking, String status) async {
    setState(() {
      _busyBookingId = booking.id;
    });
    try {
      await _bookingService.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (!mounted) return;
      final List<VoyageBookingDocument> next = _bookings
          .map((item) => item.id == booking.id
              ? VoyageBookingDocument(
                  id: item.id,
                  trackNum: item.trackNum,
                  tripId: item.tripId,
                  tripTrackNum: item.tripTrackNum,
                  tripOwnerUid: item.tripOwnerUid,
                  tripOwnerTrackNum: item.tripOwnerTrackNum,
                  tripCurrency: item.tripCurrency,
                  tripDepartureDate: item.tripDepartureDate,
                  tripDepartureTime: item.tripDepartureTime,
                  tripFrequency: item.tripFrequency,
                  tripDeparturePlace: item.tripDeparturePlace,
                  tripArrivalEstimatedTime: item.tripArrivalEstimatedTime,
                  tripArrivalPlace: item.tripArrivalPlace,
                  tripDriverName: item.tripDriverName,
                  tripVehicleModel: item.tripVehicleModel,
                  tripContactPhone: item.tripContactPhone,
                  tripIntermediateStops: item.tripIntermediateStops,
                  requestedSeats: item.requestedSeats,
                  requesterUid: item.requesterUid,
                  requesterTrackNum: item.requesterTrackNum,
                  requesterName: item.requesterName,
                  requesterContact: item.requesterContact,
                  requesterEmail: item.requesterEmail,
                  segmentFrom: item.segmentFrom,
                  segmentTo: item.segmentTo,
                  segmentPrice: item.segmentPrice,
                  totalPrice: item.totalPrice,
                  travelers: item.travelers,
                  unreadForDriver: item.unreadForDriver,
                  unreadForPassenger: item.unreadForPassenger,
                  status: status,
                  createdAt: item.createdAt,
                  updatedAt: item.updatedAt,
                )
              : item)
          .toList(growable: false);
      setState(() {
        _bookings = next;
      });
      widget.onBookingsChanged(next);
      _showMessage(
        status == 'accepted' ? 'Réservation acceptée.' : 'Réservation refusée.',
      );
    } catch (_) {
      _showMessage('Mise à jour impossible pour le moment.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyBookingId = null;
        });
      }
    }
  }

  void _writeToTraveler(VoyageBookingDocument booking) {
    final String target = booking.requesterName.isEmpty ? booking.trackNum : booking.requesterName;
    _showMessage('Conversation avec $target bientôt disponible.');
  }

  @override
  Widget build(BuildContext context) {
    if (_bookings.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Text('Aucune réservation liée à ce trajet.'),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Réservations associées',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_bookings.length} réservation(s) liée(s) à ce trajet.',
            style: const TextStyle(
              color: Color(0xFF5B647A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final VoyageBookingDocument booking = _bookings[index];
                return _RelatedBookingCard(
                  booking: booking,
                  isBusy: _busyBookingId == booking.id,
                  onAccept: () => _setBookingStatus(booking, 'accepted'),
                  onReject: () => _setBookingStatus(booking, 'rejected'),
                  onWrite: () => _writeToTraveler(booking),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _travelAccentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _travelAccentDark),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class TripBookingPanel extends StatelessWidget {
  const TripBookingPanel({
    required this.selectedSeats,
    required this.maxSeats,
    required this.currency,
    required this.total,
    required this.hidePrice,
    required this.canBook,
    required this.onIncrement,
    required this.onDecrement,
    required this.onBook,
    super.key,
  });

  final int selectedSeats;
  final int maxSeats;
  final String currency;
  final int total;
  final bool hidePrice;
  final bool canBook;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final bool canDec = selectedSeats > 1;
    final bool canInc = selectedSeats < maxSeats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _travelSurfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('R\u00E9servation', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FFFD),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _travelSurfaceBorder),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Places',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5B647A),
                    ),
                  ),
                ),
                _SeatAdjustButton(
                  icon: Icons.remove_rounded,
                  onTap: canDec ? onDecrement : null,
                ),
                Container(
                  width: 48,
                  alignment: Alignment.center,
                  child: Text(
                    '$selectedSeats',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF10233E),
                    ),
                  ),
                ),
                _SeatAdjustButton(
                  icon: Icons.add_rounded,
                  onTap: canInc ? onIncrement : null,
                ),
                if (!hidePrice) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _travelAccentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$total $currency',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _travelAccentDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canBook ? onBook : null,
              child: const Text('R\u00E9server'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatAdjustButton extends StatelessWidget {
  const _SeatAdjustButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Material(
      color: enabled ? _travelAccentSoft : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: enabled ? _travelAccentDark : const Color(0xFF9AA7B8),
          ),
        ),
      ),
    );
  }
}

class TripErrorStateWidget extends StatelessWidget {
  const TripErrorStateWidget({
    required this.message,
    required this.onRetry,
    required this.actionLabel,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Color(0xFF8D1F1F)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class TripLoadingSkeleton extends StatelessWidget {
  const TripLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _SkeletonBox(height: 90),
        SizedBox(height: 12),
        _SkeletonBox(height: 110),
        SizedBox(height: 12),
        _SkeletonBox(height: 88),
        SizedBox(height: 12),
        _SkeletonBox(height: 70),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF8),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// ── Comfort Options Sheet ──────────────────────────────────────────────────

class _ConfortOption {
  const _ConfortOption({required this.id, required this.label, required this.icon, this.price});
  final String id;
  final String label;
  final IconData icon;
  final int? price;
}

const List<_ConfortOption> _kConfortOptions = <_ConfortOption>[
  _ConfortOption(id: 'depot_gare',  label: 'Me déposer à la gare',      icon: Icons.directions_car_rounded),
  _ConfortOption(id: 'gare_maison', label: 'De la gare à la maison',    icon: Icons.home_rounded),
  _ConfortOption(id: 'smart_food',  label: 'Smart food (eau + sandwich)', icon: Icons.lunch_dining_rounded, price: 500),
];

class _ConfortOptionsSheet extends StatefulWidget {
  const _ConfortOptionsSheet();

  @override
  State<_ConfortOptionsSheet> createState() => _ConfortOptionsSheetState();
}

class _ConfortOptionsSheetState extends State<_ConfortOptionsSheet> {
  final Set<String> _selected = <String>{};
  // stores home address when gare_maison is selected
  String? _homeAddress;

  Future<void> _handleOptionTap(_ConfortOption opt) async {
    final bool wasSelected = _selected.contains(opt.id);
    if (opt.id == 'gare_maison') {
      if (wasSelected) {
        // deselect and clear address
        setState(() {
          _selected.remove(opt.id);
          _homeAddress = null;
        });
      } else {
        // open address sheet first
        final String? address = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _HomeAddressSheet(),
        );
        if (!mounted) return;
        if (address != null && address.trim().isNotEmpty) {
          setState(() {
            _selected.add(opt.id);
            _homeAddress = address.trim();
          });
        }
      }
    } else {
      setState(() {
        if (wasSelected) { _selected.remove(opt.id); } else { _selected.add(opt.id); }
      });
    }
  }

  List<String> _buildResult() {
    return _selected.map((id) {
      if (id == 'gare_maison' && _homeAddress != null) {
        return 'gare_maison:$_homeAddress';
      }
      return id;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _travelAccentSoft, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.stars_rounded, color: _travelAccentDark, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Services Confort', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF10233E))),
                    Text('Optionnels · Sélectionnez ce dont vous avez besoin', style: TextStyle(fontSize: 12, color: Color(0xFF7A8CA8))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(_kConfortOptions.length, (i) {
            final _ConfortOption opt = _kConfortOptions[i];
            final bool selected = _selected.contains(opt.id);
            final bool isGareMaison = opt.id == 'gare_maison';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _handleOptionTap(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? _travelAccentSoft : const Color(0xFFF8FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: selected ? _travelAccentDark : const Color(0xFFE2E8F0), width: selected ? 1.5 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: selected ? _travelAccentDark : const Color(0xFFE8EDF5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(opt.icon, size: 18, color: selected ? Colors.white : const Color(0xFF5B647A)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(opt.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected ? _travelAccentDark : const Color(0xFF10233E))),
                                if (opt.price != null)
                                  Text('${opt.price} XOF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? _travelAccentDark : const Color(0xFF7A8CA8)))
                                else if (!selected && isGareMaison)
                                  const Text('Adresse requise', style: TextStyle(fontSize: 11, color: Color(0xFF9AA5B4))),
                              ],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: selected
                                ? const Icon(Icons.check_circle_rounded, color: _travelAccentDark, key: ValueKey('checked'))
                                : const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFFD1D9E6), key: ValueKey('unchecked')),
                          ),
                        ],
                      ),
                      // address display
                      if (isGareMaison && selected && _homeAddress != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _travelAccentDark.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 14, color: _travelAccentDark),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _homeAddress!,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF10233E)),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _handleOptionTap(opt),
                                child: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF7A8CA8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _travelAccentDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(_buildResult()),
              child: Text(_selected.isEmpty ? 'Continuer sans option' : 'Continuer (${_selected.length} option${_selected.length > 1 ? "s" : ""})'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home Address Sheet ─────────────────────────────────────────────────────

class _HomeAddressSheet extends StatefulWidget {
  const _HomeAddressSheet();

  @override
  State<_HomeAddressSheet> createState() => _HomeAddressSheetState();
}

class _HomeAddressSheetState extends State<_HomeAddressSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _fetchingGps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _fetchingGps = true);
    try {
      final LocationResult? result = await LocationService.instance.getCurrent();
      if (!mounted) return;
      if (result != null && result.address.isNotEmpty) {
        _controller.text = result.address;
        Navigator.of(context).pop(result.address);
      }
    } finally {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(99)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: _travelAccentSoft, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.home_rounded, color: _travelAccentDark, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adresse de la maison', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF10233E))),
                        Text('Où souhaitez-vous être déposé ?', style: TextStyle(fontSize: 12, color: Color(0xFF7A8CA8))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    AddressAutocompleteField(
                      controller: _controller,
                      focusNode: _focus,
                      labelText: 'Adresse',
                      hintText: 'Ex: Rue de la Paix, Quartier...',
                      apiKey: RuntimeAppConfig.googleMapsApiKey,
                      onChanged: (_) {},
                      onSuggestionSelected: (address) {
                        Navigator.of(context).pop(address);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _travelAccentDark,
                          side: const BorderSide(color: _travelSurfaceBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _fetchingGps ? null : _useGps,
                        icon: _fetchingGps
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(_fetchingGps ? 'Localisation...' : 'Utiliser ma position actuelle'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _travelAccentDark,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _controller.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(context).pop(_controller.text.trim()),
                        child: const Text('Valider cette adresse'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
