import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/data/trip_detail_repository_impl.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/domain/repositories/trip_detail_repository.dart';
import 'package:govipservices/features/travel/domain/usecases/trip_detail_usecases.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_cubit.dart';
import 'package:govipservices/features/travel/presentation/state/trip_detail_state.dart';

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
      backgroundColor: const Color(0xFFF6F8FF),
      appBar: const TripDetailAppBar(),
      body: SafeArea(
        child: switch (state.status) {
          TripDetailStatus.initial || TripDetailStatus.loading => const TripLoadingSkeleton(),
          TripDetailStatus.error => TripErrorStateWidget(
              message: state.errorMessage ?? 'Erreur inconnue.',
              onRetry: cubit.load,
              actionLabel: 'Reessayer',
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

  Future<void> _onBookPressed(BuildContext context) async {
    final BuildContext rootContext = context;
    final TripDetailState state = cubit.state;
    final TripDetailModel? trip = state.trip;
    if (trip == null || state.segment == null) return;
    final TripSegmentModel segment = state.segment!;
    final VoyageBookingService bookingService = VoyageBookingService();
    final User? authUser = FirebaseAuth.instance.currentUser;
    final List<String> passengerNames = List<String>.filled(state.selectedSeats, '');
    String requesterName = authUser?.displayName?.trim() ?? '';
    String requesterContact = '';
    final ValueNotifier<String?> errorText = ValueNotifier<String?>(null);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirmer la reservation',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text('${segment.departureNode.address} -> ${segment.arrivalNode.address}'),
                  const SizedBox(height: 6),
                  Text('Date: ${cubit.displayDate}'),
                  const SizedBox(height: 6),
                  Text('Places: ${state.selectedSeats}'),
                  const SizedBox(height: 6),
                  Text(
                    'Total: ${cubit.totalFare} ${trip.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B5FFF)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nom des passagers',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (value) => requesterName = value.trim(),
                    decoration: const InputDecoration(
                      labelText: 'Votre nom',
                      hintText: 'Nom complet',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    keyboardType: TextInputType.phone,
                    onChanged: (value) => requesterContact = value.trim(),
                    decoration: const InputDecoration(
                      labelText: 'Votre contact',
                      hintText: 'Telephone',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: passengerNames.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return TextField(
                          textInputAction: index == passengerNames.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                          onChanged: (value) {
                            passengerNames[index] = value.trim();
                          },
                          decoration: InputDecoration(
                            labelText: 'Passager ${index + 1}',
                            hintText: 'Nom complet',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: errorText,
                    builder: (_, error, __) {
                      if (error == null) return const SizedBox(height: 10);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final List<String> passengers = passengerNames
                            .map((name) => name.trim())
                            .toList(growable: false);
                        final bool hasEmpty = passengers.any((name) => name.isEmpty);
                        if (hasEmpty) {
                          errorText.value = 'Veuillez saisir le nom de chaque passager.';
                          return;
                        }
                        if (requesterName.trim().isEmpty || requesterContact.trim().isEmpty) {
                          errorText.value = 'Veuillez saisir votre nom et votre contact.';
                          return;
                        }

                        final List<VoyageBookingTraveler> travelers = passengers
                            .map((name) => VoyageBookingTraveler(name: name, contact: requesterContact.trim()))
                            .toList(growable: false);

                        bookingService
                            .createBooking(
                              CreateVoyageBookingInput(
                                tripId: trip.id,
                                requestedSeats: state.selectedSeats,
                                requesterUid: authUser?.uid,
                                requesterTrackNum: '',
                                requesterName: requesterName.trim(),
                                requesterContact: requesterContact.trim(),
                                requesterEmail: authUser?.email,
                                segmentFrom: segment.departureNode.address,
                                segmentTo: segment.arrivalNode.address,
                                segmentPrice: segment.segmentPrice,
                                travelers: travelers,
                              ),
                            )
                            .then((_) {
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(rootContext)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Demande envoyee pour ${passengers.length} passager(s). Contact partage apres confirmation.',
                                    ),
                                  ),
                                );
                            })
                            .catchError((error) {
                              errorText.value = error.toString().replaceFirst('Exception: ', '');
                            });
                      },
                      child: const Text('Confirmer et envoyer'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      errorText.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TripDetailState state = cubit.state;
    final TripDetailModel trip = state.trip!;
    final TripSegmentModel segment = state.segment!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TripSegmentCard(
            dateLabel: cubit.displayDate,
            frequencyLabel: cubit.frequencyLabel,
            seats: trip.seats,
            segment: segment,
          ),
          const SizedBox(height: 12),
          TripTimelineWidget(segment: segment),
          const SizedBox(height: 12),
          TripFareCard(
            unitFare: segment.segmentPrice,
            currency: trip.currency,
            seats: state.selectedSeats,
            total: cubit.totalFare,
          ),
          const SizedBox(height: 12),
          TripDriverCard(driver: trip.driver),
          const SizedBox(height: 12),
          TripVehicleCard(vehicle: trip.vehicle),
          const SizedBox(height: 12),
          TripOptionsChips(options: trip.options),
          const SizedBox(height: 14),
          TripBookingPanel(
            selectedSeats: state.selectedSeats,
            maxSeats: trip.seats < 1 ? 1 : trip.seats,
            currency: trip.currency,
            total: cubit.totalFare,
            canBook: cubit.isBookable,
            onIncrement: cubit.incrementSeats,
            onDecrement: cubit.decrementSeats,
            onBook: () {
              _onBookPressed(context);
            },
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
      title: const Text('Detail du trajet'),
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
        border: Border.all(color: const Color(0xFFE4EAFB)),
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
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  frequencyLabel,
                  style: const TextStyle(
                    color: Color(0xFF0B5FFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$seats place(s)',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF53658D)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${segment.departureNode.address} -> ${segment.arrivalNode.address}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F1A35)),
          ),
        ],
      ),
    );
  }
}

class TripTimelineWidget extends StatelessWidget {
  const TripTimelineWidget({required this.segment, super.key});

  final TripSegmentModel segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAFB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(segment.departureNode.time.isEmpty ? '--:--' : segment.departureNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                Text(segment.arrivalNode.time.isEmpty ? '--:--' : segment.arrivalNode.time,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0B5FFF), shape: BoxShape.circle)),
                Container(width: 2, height: 22, color: const Color(0xFFCAD6EE)),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF8FA5CF), shape: BoxShape.circle)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(segment.departureNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(segment.arrivalNode.address, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
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
        border: Border.all(color: const Color(0xFFE4EAFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tarif', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Prix segment: $unitFare $currency', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Total ($seats place(s)): $total $currency', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B5FFF))),
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
        border: Border.all(color: const Color(0xFFE4EAFB)),
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
                  driver.name.isEmpty ? 'Conducteur non renseigne' : driver.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Contact partage apres confirmation',
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
        border: Border.all(color: const Color(0xFFE4EAFB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vehicle.model.isEmpty ? 'Vehicule non renseigne' : vehicle.model,
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
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF3E568A)),
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
        border: Border.all(color: const Color(0xFFE4EAFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reservation', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(onPressed: canDec ? onDecrement : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$selectedSeats', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(onPressed: canInc ? onIncrement : null, icon: const Icon(Icons.add_circle_outline)),
              const Spacer(),
              Text('$total $currency', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0B5FFF))),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canBook ? onBook : null,
              child: const Text('Reserver'),
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
