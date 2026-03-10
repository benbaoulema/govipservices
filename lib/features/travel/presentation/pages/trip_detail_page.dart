import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/data/trip_detail_repository_impl.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_cubit.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_state.dart';

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
        child: switch (state.status) {
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
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({required this.cubit});

  final TripDetailCubit cubit;

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
                  'Choisir un autre depart',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selectionnez un point de montee intermediaire.',
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
                  'Choisir une autre arrivee',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selectionnez un point de descente intermediaire.',
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
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: _travelAccentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _travelAccentDark,
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Réservation confirmée',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Votre demande pour $passengerCount passager(s) a été envoyée avec succès.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _travelAccentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Numéro de réservation',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B647A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      booking.trackNum,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _travelAccentDark,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  Navigator.of(context, rootNavigator: true)
                      .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
                },
                child: const Text('OK'),
              ),
            ),
          ],
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final TripDetailState state = cubit.state;
    final TripDetailModel trip = state.trip!;
    final TripSegmentModel segment = state.segment!;
    final bool hidePrice = _shouldHidePrice(segment);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _animateSection(TripSegmentCard(
            dateLabel: _formatFrDate(cubit.displayDate),
            frequencyLabel: cubit.frequencyLabel,
            seats: trip.seats,
            segment: segment,
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
          const SizedBox(height: 14),
          _animateSection(TripBookingPanel(
            selectedSeats: state.selectedSeats,
            maxSeats: trip.seats < 1 ? 1 : trip.seats,
            currency: trip.currency,
            total: cubit.totalFare,
            hidePrice: hidePrice,
            canBook: cubit.isBookable,
            onIncrement: cubit.incrementSeats,
            onDecrement: cubit.decrementSeats,
            onBook: () {
              _onBookPressed(context);
            },
          ), delayMs: 300),
        ],
      ),
    );
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
          segmentFrom: widget.segment.departureNode.address,
          segmentTo: widget.segment.arrivalNode.address,
          segmentPrice: widget.segment.segmentPrice,
          travelers: travelers,
        ),
      );
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
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
        title: const Text('Passagers'),
        leading: IconButton(
          onPressed: () {
            _dismissKeyboard();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.close_rounded),
        ),
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
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DialogInfoChip(
                              icon: Icons.event_seat_outlined,
                              label: '${widget.selectedSeats} place(s)',
                            ),
                            if (!widget.hidePrice)
                              _DialogInfoChip(
                                icon: Icons.payments_outlined,
                                label: '${widget.totalFare} ${widget.trip.currency}',
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
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
                            color: _travelAccentSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Connectez-vous pour pré-remplir vos informations.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF315A58),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                child: TextButton(
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
                        ),
                      if (!widget.isLoggedIn) const SizedBox(height: 12),
                      const Text(
                        'Informations voyageurs',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF10233E),
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
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FFFE),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _travelSurfaceBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Passager ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10233E),
                                  ),
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
                                    fillColor: Colors.white,
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
                                    fillColor: Colors.white,
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
                          ),
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
            color: Colors.white,
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
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogInfoChip extends StatelessWidget {
  const _DialogInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class TripDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TripDetailAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
    super.key,
  });

  final String dateLabel;
  final String frequencyLabel;
  final int seats;
  final TripSegmentModel segment;

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
                        'Heure estimee: ${node.time}',
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
                          label: const Text('Changer depart'),
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
                          label: const Text('Changer arrivee'),
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
          Row(
            children: [
              IconButton(onPressed: canDec ? onDecrement : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$selectedSeats', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(onPressed: canInc ? onIncrement : null, icon: const Icon(Icons.add_circle_outline)),
              const Spacer(),
              if (!hidePrice)
                Text('$total $currency', style: const TextStyle(fontWeight: FontWeight.w800, color: _travelAccentDark)),
            ],
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
