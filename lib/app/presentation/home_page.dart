import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/notifications/presentation/widgets/notifications_app_bar_button.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/pages/my_trips_page.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

const double _topPanelMaxExtent = 286;

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
  late Future<List<TripSearchResult>> _featuredProTripsFuture;

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
    if (_activeMode == HomeMode.travel && index == 2) {
      return;
    }
    await Navigator.of(context).pushNamed(item.route);
  }

  @override
  void initState() {
    super.initState();
    _featuredProTripsFuture = _loadFeaturedProTrips();
  }

  Future<List<TripSearchResult>> _loadFeaturedProTrips() {
    return _travelRepository.fetchFeaturedProTrips();
  }

  Future<void> _refreshHome() async {
    final Future<List<TripSearchResult>> featuredProTripsFuture = _loadFeaturedProTrips();
    setState(() {
      _featuredProTripsFuture = featuredProTripsFuture;
    });
    await featuredProTripsFuture;
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
    final bool showMyTrips = isTravel && _selectedIndex == 2;
    final Color accent = isTravel ? _travelAccent : _parcelAccent;
    final List<HomeMenuItem> items = _activeItems;
    final List<HomeMenuItem> travelSecondaryItems = _travelItems.sublist(1);
    final double topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 12;
    final double refreshOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('GoVIP Services'),
        actions: [
          const NotificationsAppBarButton(),
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: showMyTrips
            ? Padding(
                key: const ValueKey('my-trips-view'),
                padding: EdgeInsets.fromLTRB(16, topInset, 16, 16),
                child: const MyTripsView(),
              )
            : RefreshIndicator(
                onRefresh: _refreshHome,
                color: accent,
                triggerMode: RefreshIndicatorTriggerMode.anywhere,
                edgeOffset: refreshOffset,
                displacement: 40,
                child: CustomScrollView(
                  key: ValueKey(_activeMode),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, topInset, 16, 0),
                      sliver: SliverPersistentHeader(
                        pinned: false,
                        delegate: _TopPanelHeaderDelegate(
                          minExtentValue: 0,
                          maxExtentValue: _topPanelMaxExtent,
                          child: Column(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF7FBFA),
                                      Color(0xFFEAF6F3),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFFDCEEE9)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
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
                              const SizedBox(height: 10),
                              _HeroPanel(
                                accent: accent,
                                title: isTravel ? 'Voyagez en toute confiance' : 'Expédiez facilement vos colis',
                                description: isTravel
                                    ? 'Publiez un trajet, r\u00E9servez rapidement et restez connect\u00E9 avec vos voyageurs.'
                                    : 'Choisissez le service adapt\u00E9 : exp\u00E9dition, shopping VIP ou proposition de transport.',
                                actionLabel: isTravel ? 'Réserver' : null,
                                onAction: isTravel ? () => _openItem(_travelItems[1], 1) : null,
                              )
                                  .animate()
                                  .fadeIn(duration: 320.ms)
                                  .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 14)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: isTravel
                            ? _FeaturedProTripsSection(
                                future: _featuredProTripsFuture,
                                accent: accent,
                                onOpenTrip: _openFeaturedTrip,
                              )
                                  .animate()
                                  .fadeIn(delay: 80.ms, duration: 260.ms)
                                  .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
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
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButton: isTravel
          ? _PrimaryNavButton(
              icon: Icons.add_rounded,
              label: 'Ajouter',
              accent: accent,
              selected: _selectedIndex == 0,
              onTap: () => _openItem(_travelItems[0], 0),
            )
          : null,
      floatingActionButtonLocation:
          isTravel ? FloatingActionButtonLocation.centerDocked : null,
      bottomNavigationBar: isTravel
          ? _TravelBottomBar(
              items: travelSecondaryItems,
              selectedIndex: _selectedIndex,
              accent: accent,
              onSelected: (index) => _openItem(_travelItems[index + 1], index + 1),
            )
          : SafeArea(
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

class _TravelBottomBar extends StatelessWidget {
  const _TravelBottomBar({
    required this.items,
    required this.selectedIndex,
    required this.accent,
    required this.onSelected,
  });

  final List<HomeMenuItem> items;
  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 86,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 14,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _BottomNavItemButton(
                item: items[0],
                selected: selectedIndex == 1,
                accent: accent,
                onTap: () => onSelected(0),
              ),
            ),
            const SizedBox(width: 84),
            Expanded(
              child: _BottomNavItemButton(
                item: items[1],
                selected: selectedIndex == 2,
                accent: accent,
                onTap: () => onSelected(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryNavButton extends StatelessWidget {
  const _PrimaryNavButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color base = selected ? Color.lerp(accent, Colors.black, 0.08)! : accent;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(base, Colors.white, 0.06)!,
                  Color.lerp(base, Colors.black, 0.12)!,
                ],
              ),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: base.withOpacity(0.30),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItemButton extends StatelessWidget {
  const _BottomNavItemButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final HomeMenuItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? accent : const Color(0xFF667085);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? accent.withOpacity(0.10) : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: foreground, size: 22),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(selectedColor, Colors.white, 0.04)!,
                    Color.lerp(selectedColor, Colors.black, 0.08)!,
                  ],
                )
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(0.28)
                : const Color(0x00000000),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF1F2937),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.25,
          ),
        ),
      ),
    );
  }
}

class _TopPanelHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TopPanelHeaderDelegate({
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
    final double progress = (shrinkOffset / (maxExtentValue == 0 ? 1 : maxExtentValue)).clamp(0, 1);
    final double eased = Curves.easeOutCubic.transform(progress);
    final double opacity = 1 - eased;
    final double translateY = -10 * eased;

    return SizedBox.expand(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: maxExtentValue,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, translateY),
              child: SizedBox(
                height: maxExtentValue,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TopPanelHeaderDelegate oldDelegate) {
    return oldDelegate.minExtentValue != minExtentValue ||
        oldDelegate.maxExtentValue != maxExtentValue ||
        oldDelegate.child != child;
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.accent,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final Color accent;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            const Positioned(
              top: -24,
              right: -10,
              child: _LiquidOrb(
                size: 124,
                color: Color(0x30FFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(-10, 16),
                durationMs: 4800,
              ),
            ),
            const Positioned(
              bottom: -26,
              left: -12,
              child: _LiquidOrb(
                size: 140,
                color: Color(0x1EFFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(14, -14),
                durationMs: 5600,
              ),
            ),
            const Positioned(
              top: 74,
              right: 48,
              child: _LiquidOrb(
                size: 38,
                color: Color(0x26FFFFFF),
                beginOffset: Offset.zero,
                endOffset: Offset(-6, 8),
                durationMs: 3400,
              ),
            ),
            Padding(
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
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 16),
                    _HeroActionButton(
                      label: actionLabel!,
                      onTap: onAction!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidOrb extends StatelessWidget {
  const _LiquidOrb({
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
    return Container(
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
        );
  }
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event_seat_rounded,
                  size: 18,
                  color: Color(0xFF0F766E),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(period: const Duration(milliseconds: 2800)))
          .shimmer(
            duration: 1200.ms,
            delay: 1400.ms,
            color: Colors.white.withOpacity(0.72),
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
              'Compagnies de transport',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Réservez rapidement auprès de compagnies de transport disponibles.',
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
                      'Chargement des compagnies de transport',
                      style: TextStyle(
                        color: Color(0xFF10233E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Nous préparons une sélection adaptée de compagnies disponibles.',
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

class _FeaturedTripCard extends StatefulWidget {
  const _FeaturedTripCard({
    required this.trip,
    required this.accent,
    required this.onTap,
  });

  final TripSearchResult trip;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_FeaturedTripCard> createState() => _FeaturedTripCardState();
}

class _FeaturedTripCardState extends State<_FeaturedTripCard> {
  double _dragOffset = 0;

  String get _priceLabel {
    final double? price = widget.trip.pricePerSeat;
    final String currency = widget.trip.currency ?? 'XOF';
    if (price == null) return currency;
    final bool whole = price == price.roundToDouble();
    final String amount = whole ? price.toInt().toString() : price.toStringAsFixed(0);
    return '$amount $currency';
  }

  String? get _vehiclePhotoUrl {
    final Object? value = widget.trip.raw['vehiclePhotoUrl'];
    if (value is! String) return null;
    final String url = value.trim();
    return url.isEmpty ? null : url;
  }

  @override
  Widget build(BuildContext context) {
    final String driver = (widget.trip.driverName?.trim().isNotEmpty ?? false)
        ? widget.trip.driverName!.trim()
                        : 'Transporteur vérifié';
    final String schedule = widget.trip.departureTime?.trim().isNotEmpty == true
        ? widget.trip.departureTime!.trim()
        : 'Horaire confirmé après validation';
    final int seats = widget.trip.seats ?? 0;
    final String? vehiclePhotoUrl = _vehiclePhotoUrl;
    final double horizontalShift = _dragOffset.clamp(-18, 18);
    final double rotation = horizontalShift / 640;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      transform: Matrix4.identity()
        ..translate(horizontalShift, horizontalShift.abs() * 0.08)
        ..rotateZ(rotation),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragOffset += details.delta.dx * 0.45;
            });
          },
          onHorizontalDragCancel: () => setState(() => _dragOffset = 0),
          onHorizontalDragEnd: (_) => setState(() => _dragOffset = 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF8FFFE),
                    Color.lerp(widget.accent, Colors.white, 0.82)!,
                    Color.lerp(widget.accent, const Color(0xFFE6FFFB), 0.45)!,
                  ],
                ),
                border: Border.all(color: const Color(0xFFD2F5EF)),
                boxShadow: [
                  BoxShadow(
                    color: widget.accent.withOpacity(0.16),
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
                              color: widget.accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              driver,
                              style: TextStyle(
                                color: widget.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _priceLabel,
                            style: TextStyle(
                              color: widget.accent,
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
                                    widget.trip.departurePlace,
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
                                          color: widget.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: widget.accent.withOpacity(0.28),
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
                                                widget.accent.withOpacity(0.9),
                                                widget.accent.withOpacity(0.18),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.trip.arrivalPlace,
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
                                    errorBuilder: (_, __, ___) => _FeaturedTripPhotoFallback(accent: widget.accent),
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return _FeaturedTripPhotoFallback(accent: widget.accent);
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
        ),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .moveY(
          begin: 0,
          end: -4,
          duration: const Duration(milliseconds: 2400),
          curve: Curves.easeInOutSine,
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
              'Aucune compagnie de transport à mettre en avant pour le moment.',
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
