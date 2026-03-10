import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';

enum HomeMode { travel, parcels }

class HomeMenuItem {
  const HomeMenuItem({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _travelAccent = Color(0xFF14B8A6);
  static const Color _parcelAccent = Color(0xFF0F766E);
  final TravelRepository _travelRepository = TravelRepository();
  HomeMode _activeMode = HomeMode.travel;
  int _travelIndex = 0;
  int _parcelsIndex = 0;
  late final Future<List<TripSearchResult>> _featuredProTripsFuture;

  static const List<HomeMenuItem> _travelItems = [
    HomeMenuItem(
      title: 'Ajouter un trajet',
      subtitle: 'Publier un nouveau trajet',
      route: AppRoutes.travelAddTrip,
      icon: Icons.add_road_outlined,
    ),
    HomeMenuItem(
      title: 'R\u00E9server',
      subtitle: 'Trouver une place disponible',
      route: AppRoutes.travelBookTrip,
      icon: Icons.event_seat_outlined,
    ),
    HomeMenuItem(
      title: 'Mes trajets',
      subtitle: 'G\u00E9rer vos trajets',
      route: AppRoutes.travelMyTrips,
      icon: Icons.route_outlined,
    ),
    HomeMenuItem(
      title: 'Messages',
      subtitle: 'Discuter avec passagers et conducteurs',
      route: AppRoutes.travelMessages,
      icon: Icons.chat_bubble_outline,
    ),
  ];

  static const List<HomeMenuItem> _parcelsItems = [
    HomeMenuItem(
      title: 'Exp\u00E9dier',
      subtitle: 'Cr\u00E9er et suivre un envoi',
      route: AppRoutes.parcelsShipPackage,
      icon: Icons.local_shipping_outlined,
    ),
    HomeMenuItem(
      title: 'Vip shopping',
      subtitle: 'Demander un achat assist\u00E9',
      route: AppRoutes.parcelsVipShopping,
      icon: Icons.shopping_bag_outlined,
    ),
    HomeMenuItem(
      title: 'Proposer',
      subtitle: 'Proposer un service de transport',
      route: AppRoutes.parcelsOfferService,
      icon: Icons.volunteer_activism_outlined,
    ),
  ];

  List<HomeMenuItem> get _activeItems =>
      _activeMode == HomeMode.travel ? _travelItems : _parcelsItems;

  int get _selectedIndex =>
      _activeMode == HomeMode.travel ? _travelIndex : _parcelsIndex;

  set _selectedIndex(int value) {
    if (_activeMode == HomeMode.travel) {
      _travelIndex = value;
      return;
    }
    _parcelsIndex = value;
  }

  void _selectMode(HomeMode mode) {
    if (_activeMode == mode) return;

    setState(() {
      _activeMode = mode;
      final itemCount = _activeItems.length;
      if (_selectedIndex >= itemCount) {
        _selectedIndex = 0;
      }
    });
  }

  Future<void> _openItem(HomeMenuItem item, int index) async {
    setState(() {
      _selectedIndex = index;
    });
    await Navigator.of(context).pushNamed(item.route);
  }

  @override
  void initState() {
    super.initState();
    _featuredProTripsFuture = _travelRepository.fetchFeaturedProTrips();
  }

  Future<void> _openAccount() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String route = user == null ? AppRoutes.authLogin : AppRoutes.userAccount;
    await Navigator.of(context).pushNamed(route);
  }

  Future<void> _openFeaturedTrip(TripSearchResult trip) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.travelTripDetail,
      arguments: TripDetailArgs(
        tripId: trip.id,
        from: trip.departurePlace,
        to: trip.arrivalPlace,
        effectiveDepartureDate: trip.effectiveDepartureDate ?? trip.departureDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTravel = _activeMode == HomeMode.travel;
    final Color accent = isTravel ? _travelAccent : _parcelAccent;
    final List<HomeMenuItem> items = _activeItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GoVIP Services'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Mon compte',
              onPressed: _openAccount,
              icon: const Icon(Icons.account_circle_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F5F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ModeButton(
                          label: 'Voyager',
                          selected: isTravel,
                          selectedColor: _travelAccent,
                          onTap: () => _selectMode(HomeMode.travel),
                        ),
                      ),
                      Expanded(
                        child: _ModeButton(
                          label: 'Colis',
                          selected: !isTravel,
                          selectedColor: _parcelAccent,
                          onTap: () => _selectMode(HomeMode.parcels),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: ListView(
                  key: ValueKey(_activeMode),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  children: [
                    _HeroPanel(
                      accent: accent,
                      title: isTravel ? 'Voyagez en toute confiance' : 'Expediez facilement vos colis',
                      description: isTravel
                          ? 'Publiez un trajet, r\u00E9servez rapidement et restez connect\u00E9 avec vos voyageurs.'
                          : 'Choisissez le service adapt\u00E9 : exp\u00E9dition, shopping VIP ou proposition de transport.',
                    )
                        .animate()
                        .fadeIn(duration: 320.ms)
                        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                    const SizedBox(height: 14),
                    if (isTravel) ...[
                      _FeaturedProTripsSection(
                        future: _featuredProTripsFuture,
                        accent: accent,
                        onOpenTrip: _openFeaturedTrip,
                      )
                          .animate()
                          .fadeIn(delay: 80.ms, duration: 260.ms)
                          .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                    ] else ...[
                      Text(
                        'Actions principales',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ).animate().fadeIn(delay: 80.ms, duration: 260.ms),
                      const SizedBox(height: 8),
                      ...items.asMap().entries.map(
                        (entry) {
                          final int index = entry.key;
                          final HomeMenuItem item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ActionTile(
                              item: item,
                              accent: accent,
                              onTap: () => _openItem(item, index),
                            )
                                .animate()
                                .fadeIn(delay: Duration(milliseconds: 120 + (index * 70)), duration: 280.ms)
                                .slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          height: 74,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => _openItem(items[index], index),
          destinations: [
            for (final item in items)
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.icon),
                label: item.title,
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.accent,
    required this.title,
    required this.description,
  });

  final Color accent;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.18)!],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.item,
    required this.accent,
    required this.onTap,
  });

  final HomeMenuItem item;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedProTripsSection extends StatelessWidget {
  const _FeaturedProTripsSection({
    required this.future,
    required this.accent,
    required this.onOpenTrip,
  });

  final Future<List<TripSearchResult>> future;
  final Color accent;
  final ValueChanged<TripSearchResult> onOpenTrip;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TripSearchResult>>(
      future: future,
      builder: (context, snapshot) {
        final List<TripSearchResult> trips = snapshot.data ?? const <TripSearchResult>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trajets transporteur pro',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Une selection plus premium pour reserver rapidement.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5B6472),
              ),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              _FeaturedTripsLoading(accent: accent)
            else if (snapshot.hasError || trips.isEmpty)
              _FeaturedTripsEmpty(accent: accent)
            else
              Column(
                children: [
                  for (int index = 0; index < trips.length; index++) ...[
                    _FeaturedTripCard(
                      trip: trips[index],
                      accent: accent,
                      onTap: () => onOpenTrip(trips[index]),
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 120 + (index * 80)), duration: 300.ms)
                        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                    if (index != trips.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _FeaturedTripsLoading extends StatelessWidget {
  const _FeaturedTripsLoading({
    required this.accent,
  });

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                Color.lerp(accent, Colors.white, 0.88)!,
                const Color(0xFFF8FFFE),
              ],
            ),
            border: Border.all(color: const Color(0xFFDDF4EE)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.route_rounded, color: accent),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(duration: 1300.ms, color: Colors.white.withOpacity(0.7)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chargement des trajets pro',
                      style: TextStyle(
                        color: Color(0xFF10233E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Nous preparons une selection adaptee de trajets disponibles.',
                      style: TextStyle(
                        color: Color(0xFF5B6472),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          minHeight: 6,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          color: accent,
          backgroundColor: accent.withOpacity(0.12),
        ),
        const SizedBox(height: 14),
        const _FeaturedTripsSkeleton(),
      ],
    );
  }
}

class _FeaturedTripCard extends StatelessWidget {
  const _FeaturedTripCard({
    required this.trip,
    required this.accent,
    required this.onTap,
  });

  final TripSearchResult trip;
  final Color accent;
  final VoidCallback onTap;

  String get _priceLabel {
    final double? price = trip.pricePerSeat;
    final String currency = trip.currency ?? 'XOF';
    if (price == null) return currency;
    final bool whole = price == price.roundToDouble();
    final String amount = whole ? price.toInt().toString() : price.toStringAsFixed(0);
    return '$amount $currency';
  }

  String? get _vehiclePhotoUrl {
    final Object? value = trip.raw['vehiclePhotoUrl'];
    if (value is! String) return null;
    final String url = value.trim();
    return url.isEmpty ? null : url;
  }

  @override
  Widget build(BuildContext context) {
    final String driver = (trip.driverName?.trim().isNotEmpty ?? false) ? trip.driverName!.trim() : 'Transporteur verifie';
    final String schedule = trip.departureTime?.trim().isNotEmpty == true ? trip.departureTime!.trim() : 'Horaire confirme apres validation';
    final int seats = trip.seats ?? 0;
    final String? vehiclePhotoUrl = _vehiclePhotoUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF8FFFE),
                Color.lerp(accent, Colors.white, 0.82)!,
                Color.lerp(accent, const Color(0xFFE6FFFB), 0.45)!,
              ],
            ),
            border: Border.all(color: const Color(0xFFD2F5EF)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.16),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SizedBox(
            height: 214,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          driver,
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _priceLabel,
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.departurePlace,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withOpacity(0.28),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 12),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(99),
                                        gradient: LinearGradient(
                                          colors: [
                                            accent.withOpacity(0.9),
                                            accent.withOpacity(0.18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                trip.arrivalPlace,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF374151),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$schedule  •  $seats place${seats > 1 ? 's' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF5B6472),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (vehiclePhotoUrl != null) ...[
                          const SizedBox(width: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox(
                              width: 96,
                              child: Image.network(
                                vehiclePhotoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _FeaturedTripPhotoFallback(accent: accent),
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return _FeaturedTripPhotoFallback(accent: accent);
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 14,
                        color: Color(0xFF5B6472),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          driver,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedTripPhotoFallback extends StatelessWidget {
  const _FeaturedTripPhotoFallback({
    required this.accent,
  });

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(accent, Colors.white, 0.72)!,
            Color.lerp(accent, Colors.black, 0.06)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.directions_bus_rounded,
          size: 34,
          color: Colors.white.withOpacity(0.92),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
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
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6F2EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5B6472)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedTripsSkeleton extends StatelessWidget {
  const _FeaturedTripsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < 2; index++) ...[
          _FeaturedTripSkeletonCard(
            delayMs: index * 120,
          ),
          if (index != 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _FeaturedTripSkeletonCard extends StatelessWidget {
  const _FeaturedTripSkeletonCard({
    required this.delayMs,
  });

  final int delayMs;

  @override
  Widget build(BuildContext context) {
    Widget block({double? width, double height = 12, double radius = 999}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE5F4F1),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Container(
      height: 214,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF6FBFA),
            Color(0xFFEAF7F4),
          ],
        ),
        border: Border.all(color: const Color(0xFFE3F3EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              block(width: 120, height: 28),
              const Spacer(),
              block(width: 74, height: 20),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      block(width: double.infinity, height: 16, radius: 10),
                      const SizedBox(height: 8),
                      block(width: 110, height: 2, radius: 99),
                      const SizedBox(height: 8),
                      block(width: 150, height: 14, radius: 10),
                      const Spacer(),
                      block(width: 140, height: 12, radius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2EE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          block(width: 180, height: 12, radius: 10),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(duration: 220.ms)
        .shimmer(duration: 1450.ms, color: Colors.white.withOpacity(0.75));
  }
}

class _FeaturedTripsEmpty extends StatelessWidget {
  const _FeaturedTripsEmpty({
    required this.accent,
  });

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.route_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Aucun trajet transporteur pro a mettre en avant pour le moment.',
              style: TextStyle(
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
