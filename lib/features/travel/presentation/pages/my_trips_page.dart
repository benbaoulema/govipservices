import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/presentation/pages/booking_detail_page.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

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

const Color _reservationsAccent = Color(0xFF1F4B5F);
const Color _reservationsAccentSoft = Color(0xFFEAF2F5);
const Color _reservationsAccentSoftAlt = Color(0xFFF7FAFB);
const Color _reservationsBorder = Color(0xFFD8E4EA);
const Color _reservationsText = Color(0xFF16313C);
const Color _reservationsMuted = Color(0xFF5D7480);

String _departureCountdownLabel({
  required String departureDate,
  required String departureTime,
}) {
  final DateTime? departure = _tryParseDepartureDateTime(
    departureDate: departureDate,
    departureTime: departureTime,
  );
  if (departure == null) {
    return 'Date à confirmer';
  }

  final Duration diff = departure.difference(DateTime.now());
  if (diff.inMinutes <= 0) {
    return 'Départ imminent';
  }

  if (diff.inHours < 24) {
    final int hours = diff.inHours;
    final int minutes = diff.inMinutes.remainder(60);
    if (hours <= 0) {
      return 'Départ dans $minutes min';
    }
    if (minutes == 0) {
      return 'Départ dans $hours h';
    }
    return 'Départ dans $hours h $minutes min';
  }

  final int days = diff.inDays + (diff.inHours.remainder(24) > 0 ? 1 : 0);
  return 'Départ dans $days jour${days > 1 ? 's' : ''}';
}

DateTime? _tryParseDepartureDateTime({
  required String departureDate,
  required String departureTime,
}) {
  final List<String> dateParts = departureDate.trim().split('-');
  if (dateParts.length != 3) {
    return null;
  }

  final int? year = int.tryParse(dateParts[0]);
  final int? month = int.tryParse(dateParts[1]);
  final int? day = int.tryParse(dateParts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }

  final List<String> timeParts = departureTime.trim().split(':');
  final int hour = timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 0 : 0;
  final int minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;

  return DateTime(year, month, day, hour, minute);
}

class MyTripsPage extends StatelessWidget {
  const MyTripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Mes trajets'),
      ),
      body: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: MyTripsView(),
        ),
      ),
    );
  }
}

class MyTripsView extends StatelessWidget {
  const MyTripsView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const Color accent = Color(0xFF14B8A6);

    return DefaultTabController(
      length: 2,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverPersistentHeader(
              pinned: false,
              delegate: _MyTripsIntroHeaderDelegate(
                minExtentValue: 28,
                maxExtentValue: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mes trajets',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10233E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Retrouvez vos trajets publiés et vos réservations au même endroit.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5B6472),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _MyTripsTabsHeaderDelegate(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F5F8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF667085),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Publiés'),
                        Tab(text: 'Réservations'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: const TabBarView(
          children: [
            _PublishedTripsTab(),
            _ReservationsTab(),
          ],
        ),
      ),
    );
  }
}

class _MyTripsIntroHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _MyTripsIntroHeaderDelegate({
    required this.minExtentValue,
    required this.maxExtentValue,
    required this.child,
  });

  final double minExtentValue;
  final double maxExtentValue;
  final Widget child;

  @override
  double get minExtent => minExtentValue;

  @override
  double get maxExtent => maxExtentValue;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double range = (maxExtentValue - minExtentValue).clamp(1, double.infinity);
    final double progress = (shrinkOffset / range).clamp(0, 1);
    final double opacity = 1 - progress;
    final double translateY = -(18 * progress);

    return ClipRect(
      child: SizedBox.expand(
        child: OverflowBox(
          alignment: Alignment.bottomLeft,
          minHeight: 0,
          maxHeight: maxExtentValue,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, translateY),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MyTripsIntroHeaderDelegate oldDelegate) {
    return oldDelegate.minExtentValue != minExtentValue ||
        oldDelegate.maxExtentValue != maxExtentValue ||
        oldDelegate.child != child;
  }
}

class _MyTripsTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _MyTripsTabsHeaderDelegate({
    required this.child,
  });

  final Widget child;

  @override
  double get minExtent => 72;

  @override
  double get maxExtent => 72;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _MyTripsTabsHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _PublishedTripsTab extends StatefulWidget {
  const _PublishedTripsTab();

  @override
  State<_PublishedTripsTab> createState() => _PublishedTripsTabState();
}

class _PublishedTripsTabState extends State<_PublishedTripsTab> {
  final TravelRepository _travelRepository = TravelRepository();
  final TextEditingController _trackNumController = TextEditingController();

  bool _isTrackLookupInProgress = false;
  TripSearchResult? _trackLookupResult;
  bool _showLookupOptions = true;

  @override
  void dispose() {
    _trackNumController.dispose();
    super.dispose();
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).pushNamed(
      AppRoutes.authLogin,
      arguments: <String, dynamic>{
        'returnToCaller': true,
      },
    );
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

  Future<void> _findTripByTrackNum() async {
    final String trackNum = _trackNumController.text.trim();
    if (trackNum.isEmpty) {
      _showMessage('Saisissez un numéro de suivi.', error: true);
      return;
    }

    setState(() {
      _isTrackLookupInProgress = true;
    });

    try {
      final TripSearchResult? trip = await _travelRepository.findTripByTrackNum(trackNum);
      if (!mounted) return;
      if (trip == null) {
        setState(() {
          _trackLookupResult = null;
          _showLookupOptions = true;
        });
        _showMessage('Aucun trajet trouvé pour ce numéro.', error: true);
        return;
      }
      setState(() {
        _trackLookupResult = trip;
        _showLookupOptions = false;
      });
    } catch (_) {
      setState(() {
        _trackLookupResult = null;
        _showLookupOptions = true;
      });
      _showMessage('Recherche impossible pour le moment.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isTrackLookupInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final User? user = snapshot.data;
        if (user == null) {
          return _PublishedTripsGuestState(
            trackNumController: _trackNumController,
            trackLookupResult: _trackLookupResult,
            showLookupOptions: _showLookupOptions,
            isTrackLookupInProgress: _isTrackLookupInProgress,
            onLoginTap: _openLogin,
            onTrackLookup: _findTripByTrackNum,
            onShowLookupOptions: () {
              setState(() {
                _showLookupOptions = true;
              });
            },
            onHideLookupOptions: () {
              setState(() {
                _showLookupOptions = false;
              });
            },
            onTrackItemTap: () {
              final TripSearchResult? trip = _trackLookupResult;
              if (trip == null) return;
              Navigator.of(context).pushNamed(
                AppRoutes.travelTripDetail,
                arguments: TripDetailArgs(
                  tripId: trip.id,
                  from: trip.departurePlace,
                  to: trip.arrivalPlace,
                  effectiveDepartureDate: trip.effectiveDepartureDate ?? trip.departureDate,
                  accessMode: TripDetailAccessMode.supportOnly,
                ),
              );
            },
          );
        }

        return _PublishedTripsSignedInState(
          user: user,
          travelRepository: _travelRepository,
          onOpenTrip: (trip) async {
            await Navigator.of(context).pushNamed(
              AppRoutes.travelTripDetail,
              arguments: TripDetailArgs(
                tripId: trip.id,
                from: trip.departurePlace,
                to: trip.arrivalPlace,
                effectiveDepartureDate: trip.effectiveDepartureDate ?? trip.departureDate,
                accessMode: TripDetailAccessMode.owner,
              ),
            );
          },
        );
      },
    );
  }
}

class _PublishedTripsGuestState extends StatelessWidget {
  const _PublishedTripsGuestState({
    required this.trackNumController,
    required this.trackLookupResult,
    required this.showLookupOptions,
    required this.isTrackLookupInProgress,
    required this.onLoginTap,
    required this.onTrackLookup,
    required this.onShowLookupOptions,
    required this.onHideLookupOptions,
    required this.onTrackItemTap,
  });

  final TextEditingController trackNumController;
  final TripSearchResult? trackLookupResult;
  final bool showLookupOptions;
  final bool isTrackLookupInProgress;
  final VoidCallback onLoginTap;
  final VoidCallback onTrackLookup;
  final VoidCallback onShowLookupOptions;
  final VoidCallback onHideLookupOptions;
  final VoidCallback onTrackItemTap;

  @override
  Widget build(BuildContext context) {
    final bool hasLookupResult = trackLookupResult != null;

    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFF7FBFA),
                Color(0xFFEAF8F5),
              ],
            ),
            border: Border.all(color: const Color(0xFFD9EFEB)),
          ),
          child: const Row(
            children: [
              _IntroIcon(icon: Icons.route_rounded),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trajets publiés',
                      style: TextStyle(
                        color: Color(0xFF10233E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Connectez-vous pour retrouver vos trajets, ou recherchez un trajet avec son numéro de suivi.',
                      style: TextStyle(
                        color: Color(0xFF5B6472),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!hasLookupResult || showLookupOptions) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Option 1',
                  style: TextStyle(
                    color: Color(0xFF14B8A6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connectez-vous pour afficher automatiquement vos trajets publiés.',
                  style: TextStyle(
                    color: Color(0xFF10233E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onLoginTap,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Se connecter'),
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 18),
                const Text(
                  'Option 2',
                  style: TextStyle(
                    color: Color(0xFF14B8A6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retrouvez un trajet avec son numéro de suivi.',
                  style: TextStyle(
                    color: Color(0xFF10233E),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: trackNumController,
                  textInputAction: TextInputAction.search,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => onTrackLookup(),
                  decoration: InputDecoration(
                    labelText: 'Numéro de suivi',
                    hintText: 'Ex: 12345678',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isTrackLookupInProgress ? null : onTrackLookup,
                    icon: isTrackLookupInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: const Text('Retrouver ce trajet'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hasLookupResult) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFCF9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFCDEFE7)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF0F766E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Trajet retrouvé. Touchez la carte ci-dessous pour continuer.',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: showLookupOptions ? onHideLookupOptions : onShowLookupOptions,
                  child: Text(showLookupOptions ? 'Cacher la recherche' : 'Afficher la recherche'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PublishedTripCard(
            trip: trackLookupResult!,
            onTap: onTrackItemTap,
          ),
        ],
      ],
    );
  }
}

class _PublishedTripsSignedInState extends StatefulWidget {
  const _PublishedTripsSignedInState({
    required this.user,
    required this.travelRepository,
    required this.onOpenTrip,
  });

  final User user;
  final TravelRepository travelRepository;
  final ValueChanged<TripSearchResult> onOpenTrip;

  @override
  State<_PublishedTripsSignedInState> createState() => _PublishedTripsSignedInStateState();
}

class _PublishedTripsSignedInStateState extends State<_PublishedTripsSignedInState> {
  late Future<List<TripSearchResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadTrips();
  }

  @override
  void didUpdateWidget(covariant _PublishedTripsSignedInState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _future = _loadTrips();
    }
  }

  Future<List<TripSearchResult>> _loadTrips() {
    return widget.travelRepository.fetchTripsByOwnerUid(widget.user.uid);
  }

  Future<void> _refresh() async {
    final Future<List<TripSearchResult>> next = _loadTrips();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<TripSearchResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                _PublishedIntroCard(),
                SizedBox(height: 16),
                _TripsLoadingCard(),
              ],
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _PublishedIntroCard(),
                const SizedBox(height: 16),
                _InfoStateCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Chargement impossible',
                  description: 'Nous ne pouvons pas récupérer vos trajets pour le moment.',
                  actionLabel: 'Réessayer',
                  onAction: _refresh,
                ),
              ],
            );
          }

          final List<TripSearchResult> trips = snapshot.data ?? const <TripSearchResult>[];
          if (trips.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _PublishedIntroCard(),
                const SizedBox(height: 16),
                const _InfoStateCard(
                  icon: Icons.add_road_rounded,
                  title: 'Aucun trajet publié',
                  description: 'Vos trajets publiés apparaîtront ici dès qu\'ils seront disponibles.',
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount: trips.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) return const _PublishedIntroCard();
              final TripSearchResult trip = trips[index - 1];
              return _PublishedTripCard(
                trip: trip,
                onTap: () => widget.onOpenTrip(trip),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReservationsTab extends StatelessWidget {
  const _ReservationsTab();

  @override
  Widget build(BuildContext context) {
    return const _ReservationsContent();
  }
}

class _ReservationsContent extends StatefulWidget {
  const _ReservationsContent();

  @override
  State<_ReservationsContent> createState() => _ReservationsContentState();
}

class _ReservationsContentState extends State<_ReservationsContent> {
  final VoyageBookingService _bookingService = VoyageBookingService();
  final TextEditingController _trackNumController = TextEditingController();

  bool _isLookupInProgress = false;
  VoyageBookingDocument? _lookupResult;
  bool _showLookupOptions = true;

  @override
  void dispose() {
    _trackNumController.dispose();
    super.dispose();
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).pushNamed(
      AppRoutes.authLogin,
      arguments: <String, dynamic>{
        'returnToCaller': true,
      },
    );
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

  Future<void> _findBookingByTrackNum() async {
    final String trackNum = _trackNumController.text.trim();
    if (trackNum.isEmpty) {
      _showMessage('Saisissez un numéro de réservation.', error: true);
      return;
    }

    setState(() {
      _isLookupInProgress = true;
    });

    try {
      final VoyageBookingDocument? booking = await _bookingService.findBookingByTrackNum(trackNum);
      if (!mounted) return;
      if (booking == null) {
        setState(() {
          _lookupResult = null;
          _showLookupOptions = true;
        });
        _showMessage('Aucune réservation trouvée pour ce numéro.', error: true);
        return;
      }
      setState(() {
        _lookupResult = booking;
        _showLookupOptions = false;
      });
    } catch (_) {
      setState(() {
        _lookupResult = null;
        _showLookupOptions = true;
      });
      _showMessage('Recherche impossible pour le moment.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLookupInProgress = false;
        });
      }
    }
  }

  Future<bool> _openBookingDetail(VoyageBookingDocument booking) async {
    final VoyageBookingDocument? updated = await Navigator.of(context).push<VoyageBookingDocument>(
      MaterialPageRoute<VoyageBookingDocument>(
        builder: (_) => BookingDetailPage(booking: booking),
      ),
    );
    if (!mounted || updated == null) return false;
    setState(() {
      if (_lookupResult?.id == updated.id) {
        _lookupResult = updated;
      }
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final User? user = snapshot.data;
        if (user == null) {
          return _ReservationsGuestState(
            trackNumController: _trackNumController,
            lookupResult: _lookupResult,
            showLookupOptions: _showLookupOptions,
            isLookupInProgress: _isLookupInProgress,
            onLoginTap: _openLogin,
            onLookup: _findBookingByTrackNum,
            onShowLookupOptions: () {
              setState(() {
                _showLookupOptions = true;
              });
            },
            onHideLookupOptions: () {
              setState(() {
                _showLookupOptions = false;
              });
            },
            onBookingTap: () async {
              final VoyageBookingDocument? booking = _lookupResult;
              if (booking == null) return;
              await _openBookingDetail(booking);
            },
          );
        }

        return _ReservationsSignedInState(
          user: user,
          bookingService: _bookingService,
          onBookingTap: (booking) async {
            return _openBookingDetail(booking);
          },
        );
      },
    );
  }
}

class _ReservationsGuestState extends StatelessWidget {
  const _ReservationsGuestState({
    required this.trackNumController,
    required this.lookupResult,
    required this.showLookupOptions,
    required this.isLookupInProgress,
    required this.onLoginTap,
    required this.onLookup,
    required this.onShowLookupOptions,
    required this.onHideLookupOptions,
    required this.onBookingTap,
  });

  final TextEditingController trackNumController;
  final VoyageBookingDocument? lookupResult;
  final bool showLookupOptions;
  final bool isLookupInProgress;
  final VoidCallback onLoginTap;
  final VoidCallback onLookup;
  final VoidCallback onShowLookupOptions;
  final VoidCallback onHideLookupOptions;
  final VoidCallback onBookingTap;

  @override
  Widget build(BuildContext context) {
    final bool hasLookupResult = lookupResult != null;

    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                _reservationsAccentSoftAlt,
                _reservationsAccentSoft,
              ],
            ),
            border: Border.all(color: _reservationsBorder),
          ),
          child: const Row(
            children: [
              _ReservationsIntroIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réservations',
                      style: TextStyle(
                        color: _reservationsText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Retrouvez vos demandes de réservation et leur statut de traitement.',
                      style: TextStyle(
                        color: _reservationsMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!hasLookupResult || showLookupOptions) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Option 1',
                  style: TextStyle(
                    color: _reservationsAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connectez-vous pour retrouver automatiquement vos réservations.',
                  style: TextStyle(
                    color: _reservationsText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onLoginTap,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Se connecter'),
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 18),
                const Text(
                  'Option 2',
                  style: TextStyle(
                    color: _reservationsAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retrouvez une réservation avec son numéro.',
                  style: TextStyle(
                    color: _reservationsText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: trackNumController,
                  textInputAction: TextInputAction.search,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => onLookup(),
                  decoration: InputDecoration(
                    labelText: 'Numéro de réservation',
                    hintText: 'Ex: 12345678',
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isLookupInProgress ? null : onLookup,
                    icon: isLookupInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: const Text('Retrouver cette réservation'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hasLookupResult) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _reservationsAccentSoftAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _reservationsBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: _reservationsAccent,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Réservation retrouvée. Touchez la carte pour continuer.',
                    style: TextStyle(
                      color: _reservationsText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: showLookupOptions ? onHideLookupOptions : onShowLookupOptions,
                  child: Text(showLookupOptions ? 'Cacher' : 'Recherche'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ReservationCard(
            booking: lookupResult!,
            onTap: onBookingTap,
          ),
        ],
      ],
    );
  }
}

class _ReservationsSignedInState extends StatefulWidget {
  const _ReservationsSignedInState({
    required this.user,
    required this.bookingService,
    required this.onBookingTap,
  });

  final User user;
  final VoyageBookingService bookingService;
  final Future<bool> Function(VoyageBookingDocument booking) onBookingTap;

  @override
  State<_ReservationsSignedInState> createState() => _ReservationsSignedInStateState();
}

class _ReservationsSignedInStateState extends State<_ReservationsSignedInState> {
  late Future<List<VoyageBookingDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ReservationsSignedInState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _future = _load();
    }
  }

  Future<List<VoyageBookingDocument>> _load() {
    return widget.bookingService.fetchBookingsByRequesterUid(widget.user.uid);
  }

  Future<void> _refresh() async {
    final Future<List<VoyageBookingDocument>> next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<VoyageBookingDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                _ReservationsIntroCard(),
                SizedBox(height: 16),
                _TripsLoadingCard(),
              ],
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _ReservationsIntroCard(),
                const SizedBox(height: 16),
                _InfoStateCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Chargement impossible',
                  description: 'Nous ne pouvons pas récupérer vos réservations pour le moment.',
                  actionLabel: 'Réessayer',
                  onAction: _refresh,
                ),
              ],
            );
          }

          final List<VoyageBookingDocument> bookings = snapshot.data ?? const <VoyageBookingDocument>[];
          if (bookings.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                _ReservationsIntroCard(),
                SizedBox(height: 16),
                _InfoStateCard(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Aucune réservation',
                  description: 'Vos demandes de réservation apparaîtront ici dès qu’elles seront enregistrées.',
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount: bookings.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) return const _ReservationsIntroCard();
              final VoyageBookingDocument booking = bookings[index - 1];
              return _ReservationCard(
                booking: booking,
                onTap: () async {
                  final bool shouldRefresh = await widget.onBookingTap(booking);
                  if (shouldRefresh && mounted) {
                    await _refresh();
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ReservationsIntroCard extends StatelessWidget {
  const _ReservationsIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            _reservationsAccentSoftAlt,
            _reservationsAccentSoft,
          ],
        ),
        border: Border.all(color: _reservationsBorder),
      ),
      child: const Row(
        children: [
          _ReservationsIntroIcon(),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mes réservations',
                  style: TextStyle(
                    color: _reservationsText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Suivez vos réservations, leur référence et leur état de traitement.',
                  style: TextStyle(
                    color: _reservationsMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationsIntroIcon extends StatelessWidget {
  const _ReservationsIntroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _reservationsAccent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.confirmation_number_outlined,
        color: Colors.white,
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.booking,
    required this.onTap,
  });

  final VoyageBookingDocument booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String displayDeparture = booking.segmentFrom.trim().isEmpty
        ? booking.tripDeparturePlace
        : booking.segmentFrom.trim();
    final String displayArrival = booking.segmentTo.trim().isEmpty
        ? booking.tripArrivalPlace
        : booking.segmentTo.trim();
    final String departureCountdown = _departureCountdownLabel(
      departureDate: booking.tripDepartureDate,
      departureTime: booking.tripDepartureTime,
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _reservationsBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _reservationsAccentSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Réf: ${booking.trackNum}',
                      style: const TextStyle(
                        color: _reservationsAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _reservationsAccentSoftAlt,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _bookingStatusLabel(booking.status),
                      style: const TextStyle(
                        color: _reservationsAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                displayDeparture,
                style: const TextStyle(
                  color: _reservationsText,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Icon(
                Icons.south_rounded,
                color: _reservationsAccent,
                size: 18,
              ),
              const SizedBox(height: 6),
              Text(
                displayArrival,
                style: const TextStyle(
                  color: _reservationsMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReservationMetaPill(
                    icon: Icons.calendar_today_rounded,
                    label: booking.tripDepartureDate,
                  ),
                  _ReservationMetaPill(
                    icon: Icons.schedule_rounded,
                    label: booking.tripDepartureTime,
                  ),
                  _ReservationMetaPill(
                    icon: Icons.timer_outlined,
                    label: departureCountdown,
                  ),
                  _ReservationMetaPill(
                    icon: Icons.event_seat_rounded,
                    label: '${booking.requestedSeats} place${booking.requestedSeats > 1 ? 's' : ''}',
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

class _ReservationMetaPill extends StatelessWidget {
  const _ReservationMetaPill({
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
        color: _reservationsAccentSoftAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _reservationsBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _reservationsAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _reservationsMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishedIntroCard extends StatelessWidget {
  const _PublishedIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF7FBFA),
            Color(0xFFEAF8F5),
          ],
        ),
        border: Border.all(color: const Color(0xFFD9EFEB)),
      ),
      child: const Row(
        children: [
          _IntroIcon(icon: Icons.add_road_rounded),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trajets publiés',
                  style: TextStyle(
                    color: Color(0xFF10233E),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Gérez les trajets que vous avez mis en ligne, leur statut et leurs références.',
                  style: TextStyle(
                    color: Color(0xFF5B6472),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishedTripCard extends StatelessWidget {
  const _PublishedTripCard({
    required this.trip,
    required this.onTap,
  });

  final TripSearchResult trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String date = trip.effectiveDepartureDate ?? trip.departureDate;
    final String time = trip.departureTime ?? '--:--';
    final String trackNum = (trip.trackNum?.trim().isNotEmpty ?? false)
        ? trip.trackNum!.trim()
        : 'Sans référence';
    final int seats = trip.seats ?? 0;
    final String price = trip.pricePerSeat == null
        ? (trip.currency ?? 'XOF')
        : '${trip.pricePerSeat!.toStringAsFixed(0)} ${trip.currency ?? 'XOF'}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Ref: $trackNum',
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    price,
                    style: const TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                trip.departurePlace,
                style: const TextStyle(
                  color: Color(0xFF10233E),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Icon(
                Icons.south_rounded,
                color: Color(0xFF14B8A6),
                size: 18,
              ),
              const SizedBox(height: 6),
              Text(
                trip.arrivalPlace,
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TripMetaPill(
                    icon: Icons.calendar_today_rounded,
                    label: date,
                  ),
                  _TripMetaPill(
                    icon: Icons.schedule_rounded,
                    label: time,
                  ),
                  _TripMetaPill(
                    icon: Icons.event_seat_rounded,
                    label: 'Cap. $seats place${seats > 1 ? 's' : ''}',
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

class _TripMetaPill extends StatelessWidget {
  const _TripMetaPill({
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

class _InfoStateCard extends StatelessWidget {
  const _InfoStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 30,
              color: const Color(0xFF14B8A6),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _TripsLoadingCard extends StatelessWidget {
  const _TripsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _IntroIcon extends StatelessWidget {
  const _IntroIcon({
    required this.icon,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        color: Colors.white,
      ),
    );
  }
}
