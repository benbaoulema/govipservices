import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:govipservices/app/presentation/widgets/home_availability_panel.dart';
import 'package:govipservices/features/parcels/data/vehicle_type_repository.dart';
import 'package:govipservices/features/parcels/domain/models/vehicle_type.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/notifications/presentation/widgets/notifications_app_bar_button.dart';
import 'package:govipservices/features/travel/data/transport_company_repository.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/transport_company.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/pages/my_trips_page.dart';
import 'package:govipservices/features/user/data/user_availability_service.dart';
import 'package:govipservices/shared/services/safe_wakelock_service.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';
import 'package:govipservices/features/scratch/presentation/pages/scratch_launch_sheet.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

const double _topPanelMaxExtent = 424;

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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const Color _travelAccent = Color(0xFF14B8A6);
  static const Color _parcelAccent = Color(0xFF0F766E);
  final TravelRepository _travelRepository = TravelRepository();
  final UserAvailabilityService _availabilityService = UserAvailabilityService();
  final VehicleTypeRepository _vehicleTypeRepo = VehicleTypeRepository();
  final TransportCompanyRepository _companyRepo = TransportCompanyRepository();
  HomeMode _activeMode = HomeMode.travel;
  int _travelIndex = 0;
  int _parcelsIndex = 0;
  UserAvailabilitySnapshot _availability = UserAvailabilitySnapshot.offline();
  bool _isUpdatingAvailability = false;
  List<VehicleType> _vehicleTypes = const <VehicleType>[];
  VehicleType? _selectedVehicleType;
  List<TransportCompany> _companies = const <TransportCompany>[];
  bool _companiesLoading = true;
  StreamSubscription<User?>? _authSubscription;
  User? _previousAuthUser;

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
    WidgetsBinding.instance.addObserver(this);
    _loadAvailability();
    _loadVehicleTypes();
    _loadCompanies();
    _syncWakeLock();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScratchCard());
    _previousAuthUser = FirebaseAuth.instance.currentUser;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null && _previousAuthUser == null) {
        _checkScratchCard();
      }
      _previousAuthUser = user;
    });
  }

  Future<void> _checkScratchCard() async {
    try {
      final bool isAuth = FirebaseAuth.instance.currentUser != null;
      if (isAuth) {
        final List<UserScratchCard> cards =
            await ScratchService.instance.fetchPendingCards();
        if (!mounted || cards.isEmpty) return;
        await showScratchLaunchSheet(
          context,
          card: cards.first,
          isAuthenticated: true,
        );
      } else {
        final ScratchCampaign? campaign =
            await ScratchService.instance.fetchActiveCampaign();
        if (!mounted || campaign == null) return;
        await showScratchLaunchSheet(
          context,
          isAuthenticated: false,
        );
      }
    } catch (_) {
      // Non-bloquant
    }
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final List<VehicleType> types =
          await _vehicleTypeRepo.fetchActiveVehicleTypes();
      if (!mounted || types.isEmpty) return;
      setState(() {
        _vehicleTypes = types;
        _selectedVehicleType ??= types.first;
      });
    } catch (_) {
      // Non-bloquant — l'écran fonctionne sans filtre véhicule
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    SafeWakelockService.setEnabled(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAvailabilityPosition();
    }
    _syncWakeLock();
  }

  void _syncWakeLock() {
    final AppLifecycleState? lifecycleState =
        WidgetsBinding.instance.lifecycleState;
    final bool shouldKeepScreenOn =
        _availability.isOnline && lifecycleState == AppLifecycleState.resumed;
    SafeWakelockService.setEnabled(shouldKeepScreenOn);
  }

  Future<void> _loadCompanies() async {
    try {
      final List<TransportCompany> list = await _companyRepo.fetchEnabled();
      if (!mounted) return;
      setState(() {
        _companies = list;
        _companiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _companiesLoading = false);
    }
  }

  Future<void> _openCompanyTrips(TransportCompany company) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CompanyTripsSheet(
        company: company,
        travelRepository: _travelRepository,
        accent: _travelAccent,
        onOpenTrip: _openFeaturedTrip,
      ),
    );
  }

  Future<void> _loadAvailability() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final UserAvailabilitySnapshot availability =
        await _availabilityService.fetchCurrent();
    if (!mounted) return;
    setState(() {
      _availability = availability;
    });
    _syncWakeLock();
  }

  Future<void> _refreshAvailabilityPosition() async {
    if (_isUpdatingAvailability ||
        FirebaseAuth.instance.currentUser == null ||
        !_availability.isOnline) {
      return;
    }

    try {
      final UserAvailabilitySnapshot? refreshed =
          await _availabilityService.refreshIfOnline();
      if (!mounted || refreshed == null) return;
      setState(() {
        _availability = refreshed;
      });
      _syncWakeLock();
    } catch (_) {
      // Keep home resilient if location refresh fails in background.
    }
  }

  Future<void> _refreshHome() async {
    setState(() => _companiesLoading = true);
    await _loadCompanies();
  }

  Future<void> _openAccount() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String route = user == null ? AppRoutes.authLogin : AppRoutes.userAccount;
    await Navigator.of(context).pushNamed(route);
  }

  Future<void> _toggleAvailability(bool nextValue) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await Navigator.of(context).pushNamed(AppRoutes.authLogin);
      await _loadAvailability();
      return;
    }
    if (_isUpdatingAvailability) return;

    setState(() {
      _isUpdatingAvailability = true;
    });

    try {
      final UserAvailabilityScope scope =
          _validatedScopeOrFallback(_defaultAvailabilityScopeForMode());
      if (nextValue && !_canUseScope(scope)) {
        _showScopeUnavailableMessage(scope);
        return;
      }
      final UserAvailabilitySnapshot next = nextValue
          ? await _availabilityService.goOnline(
              scope: scope,
            )
          : await _availabilityService.goOffline();
      if (!mounted) return;
      setState(() {
        _availability = next;
      });
      _syncWakeLock();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvailability = false;
      });
    }
  }

  Future<void> _changeAvailabilityScope(UserAvailabilityScope scope) async {
    if (_isUpdatingAvailability) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await Navigator.of(context).pushNamed(AppRoutes.authLogin);
      return;
    }
    if (!_canUseScope(scope)) {
      _showScopeUnavailableMessage(scope);
      return;
    }
    if (!_availability.isOnline) {
      setState(() {
        _availability = UserAvailabilitySnapshot(
          isOnline: false,
          scope: scope,
          canProvideTravel: _availability.canProvideTravel,
          canProvideParcels: _availability.canProvideParcels,
        );
      });
      _syncWakeLock();
      return;
    }

    setState(() {
      _isUpdatingAvailability = true;
    });

    try {
      final UserAvailabilitySnapshot next =
          await _availabilityService.goOnline(scope: scope);
      if (!mounted) return;
      setState(() {
        _availability = next;
      });
      _syncWakeLock();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isUpdatingAvailability = false;
      });
    }
  }

  UserAvailabilityScope _defaultAvailabilityScopeForMode() {
    return _activeMode == HomeMode.travel
        ? UserAvailabilityScope.travel
        : UserAvailabilityScope.parcels;
  }

  bool get _shouldShowAvailabilityPanel =>
      _availability.canProvideTravel || _availability.canProvideParcels;

  UserAvailabilityScope _validatedScopeOrFallback(UserAvailabilityScope scope) {
    if (_canUseScope(scope)) return scope;
    if (_availability.canProvideTravel) return UserAvailabilityScope.travel;
    if (_availability.canProvideParcels) return UserAvailabilityScope.parcels;
    return scope;
  }

  bool _canUseScope(UserAvailabilityScope scope) {
    switch (scope) {
      case UserAvailabilityScope.travel:
        return _availability.canProvideTravel;
      case UserAvailabilityScope.parcels:
        return _availability.canProvideParcels;
      case UserAvailabilityScope.all:
        return _availability.canProvideTravel &&
            _availability.canProvideParcels;
    }
  }

  void _showScopeUnavailableMessage(UserAvailabilityScope scope) {
    final String message;
    switch (scope) {
      case UserAvailabilityScope.travel:
        message =
            'Publiez d abord un trajet pour pouvoir vous mettre en ligne en voyage.';
        break;
      case UserAvailabilityScope.parcels:
        message =
            'Proposez d abord un service colis pour pouvoir vous mettre en ligne.';
        break;
      case UserAvailabilityScope.all:
        message =
            'Vous devez avoir un trajet publie et un service colis actif pour utiliser Les deux.';
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    final bool isAuthenticated = FirebaseAuth.instance.currentUser != null;
    final bool isTravel = _activeMode == HomeMode.travel;
    final bool showMyTrips = isTravel && _selectedIndex == 2;
    final Color accent = isTravel ? _travelAccent : _parcelAccent;
    final List<HomeMenuItem> items = _activeItems;
    final List<HomeMenuItem> travelSecondaryItems = _travelItems.sublist(1);
    final double topInset = MediaQuery.paddingOf(context).top + kToolbarHeight + 12;
    final double refreshOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final double topPanelExtent =
        _shouldShowAvailabilityPanel ? _topPanelMaxExtent : 286;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('GVIP'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Cartes à gratter',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.scratchCards),
            icon: const Icon(Icons.card_giftcard_rounded),
          ),
          const NotificationsAppBarButton(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: isAuthenticated
                ? IconButton(
                    tooltip: 'Mon compte',
                    onPressed: _openAccount,
                    icon: const Icon(Icons.account_circle_rounded),
                  )
                : _LoginCallToActionButton(
                    onTap: _openAccount,
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
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, topInset, 16, 0),
                      sliver: SliverPersistentHeader(
                        pinned: false,
                        delegate: _TopPanelHeaderDelegate(
                          minExtentValue: 0,
                          maxExtentValue: topPanelExtent,
                          child: Column(
                            children: <Widget>[
                              if (_shouldShowAvailabilityPanel) ...<Widget>[
                                HomeAvailabilityPanel(
                                  availability: _availability,
                                  isBusy: _isUpdatingAvailability,
                                  canTravelProvider:
                                      _availability.canProvideTravel,
                                  canParcelsProvider:
                                      _availability.canProvideParcels,
                                  onToggle: _toggleAvailability,
                                  onScopeSelected: _changeAvailabilityScope,
                                ),
                                const SizedBox(height: 12),
                              ],
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: <Color>[
                                      Color(0xFFF7FBFA),
                                      Color(0xFFEAF6F3),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFFDCEEE9),
                                  ),
                                  boxShadow: <BoxShadow>[
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
                                    children: <Widget>[
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
                                title: isTravel
                                    ? 'Voyagez en toute confiance'
                                    : 'Expediez facilement vos colis',
                                description: isTravel
                                    ? 'Publiez un trajet, reservez rapidement et restez connecte avec vos voyageurs.'
                                    : 'Choisissez le service adapte : expedition, shopping VIP ou proposition de transport.',
                                actionLabel: isTravel ? 'Reserver' : null,
                                onAction: isTravel
                                    ? () => _openItem(_travelItems[1], 1)
                                    : null,
                              )
                                  .animate()
                                  .fadeIn(duration: 320.ms)
                                  .slideY(
                                    begin: 0.05,
                                    end: 0,
                                    curve: Curves.easeOutCubic,
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 14),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: isTravel
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CompaniesSection(
                                    companies: _companies,
                                    isLoading: _companiesLoading,
                                    accent: accent,
                                    onTap: _openCompanyTrips,
                                  ).animate().fadeIn(delay: 80.ms, duration: 260.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
                                  const SizedBox(height: 24),
                                  _ConfortServicesSection(accent: accent)
                                    .animate().fadeIn(delay: 160.ms, duration: 260.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (_vehicleTypes.isNotEmpty) ...<Widget>[
                                    _VehicleChipRow(
                                      types: _vehicleTypes,
                                      selected: _selectedVehicleType,
                                      accent: accent,
                                      onSelect: (v) => setState(
                                        () => _selectedVehicleType = v,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pushNamed(
                                      AppRoutes.parcelsShipPackage,
                                      arguments: <String, dynamic>{
                                        'openAddressSheet': true,
                                        'vehicleTypeId':
                                            _selectedVehicleType?.id,
                                        'vehicleLabel':
                                            _selectedVehicleType?.name,
                                      },
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color:
                                                accent.withValues(alpha: 0.13),
                                            blurRadius: 20,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: accent.withValues(alpha: 0.18),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 18,
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color:
                                                  accent.withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              Icons.local_shipping_outlined,
                                              color: accent,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  'Où livrons-nous ?',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: accent,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Départ • Arrivée',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 16,
                                            color: accent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                                  .animate()
                                  .fadeIn(delay: 80.ms, duration: 280.ms)
                                  .slideY(
                                    begin: 0.06,
                                    end: 0,
                                    curve: Curves.easeOutCubic,
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
      floatingActionButtonLocation: isTravel
          ? FloatingActionButtonLocation.centerDocked
          : null,
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
                destinations: <Widget>[
                  for (final HomeMenuItem item in items)
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

// ─── Companies Section ────────────────────────────────────────────────────────

class _CompaniesSection extends StatelessWidget {
  const _CompaniesSection({
    required this.companies,
    required this.isLoading,
    required this.accent,
    required this.onTap,
  });

  final List<TransportCompany> companies;
  final bool isLoading;
  final Color accent;
  final ValueChanged<TransportCompany> onTap;

  @override
  Widget build(BuildContext context) {
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
          'Explorez les trajets par compagnie.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF5B6472),
          ),
        ),
        const SizedBox(height: 14),
        if (isLoading)
          _CompaniesLoadingRow(accent: accent)
        else if (companies.isEmpty)
          _FeaturedTripsEmpty(accent: accent)
        else
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: companies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => _CompanyCard(
                company: companies[i],
                accent: accent,
                onTap: () => onTap(companies[i]),
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 60 * i), duration: 260.ms)
                  .slideX(begin: 0.06, end: 0),
            ),
          ),
      ],
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.company,
    required this.accent,
    required this.onTap,
  });

  final TransportCompany company;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = company.imageUrl;
    final String initial = company.name.isNotEmpty ? company.name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 210,
        height: 144,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo ou fallback dégradé
              if (imageUrl != null && imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _CompanyCardFallback(initial: initial, accent: accent),
                )
              else
                _CompanyCardFallback(initial: initial, accent: accent),
              // Overlay dégradé bas
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.76),
                      ],
                    ),
                  ),
                ),
              ),
              // Border interne subtile
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
              // Nom centré en bas
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  company.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyCardFallback extends StatelessWidget {
  const _CompanyCardFallback({required this.initial, required this.accent});
  final String initial;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, const Color(0xFF0F4C75), 0.55)!,
            Color.lerp(accent, const Color(0xFF0F766E), 0.3)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cercle décoratif en arrière-plan
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -15,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Icône + initiale
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
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

class _CompaniesLoadingRow extends StatelessWidget {
  const _CompaniesLoadingRow({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => Container(
          width: 210,
          height: 144,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: accent.withValues(alpha: 0.10),
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(duration: 1200.ms, color: Colors.white.withValues(alpha: 0.5)),
      ),
    );
  }
}

// ─── Company Trips Sheet ───────────────────────────────────────────────────────

class _CompanyTripsSheet extends StatefulWidget {
  const _CompanyTripsSheet({
    required this.company,
    required this.travelRepository,
    required this.accent,
    required this.onOpenTrip,
  });

  final TransportCompany company;
  final TravelRepository travelRepository;
  final Color accent;
  final ValueChanged<TripSearchResult> onOpenTrip;

  @override
  State<_CompanyTripsSheet> createState() => _CompanyTripsSheetState();
}

class _CompanyTripsSheetState extends State<_CompanyTripsSheet> {
  List<TripSearchResult> _trips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<TripSearchResult> trips =
          await widget.travelRepository.fetchTripsByCompanyName(widget.company.name);
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = widget.company.imageUrl;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FFFE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              // Header compagnie
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? Image.network(imageUrl, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _CompanyCardFallback(
                                  initial: widget.company.name.isNotEmpty
                                      ? widget.company.name[0].toUpperCase()
                                      : '?',
                                  accent: widget.accent,
                                ))
                            : _CompanyCardFallback(
                                initial: widget.company.name.isNotEmpty
                                    ? widget.company.name[0].toUpperCase()
                                    : '?',
                                accent: widget.accent,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.company.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F1A35),
                            ),
                          ),
                          if (!_loading)
                            Text(
                              _trips.isEmpty
                                  ? 'Aucun trajet disponible'
                                  : '${_trips.length} trajet${_trips.length > 1 ? 's' : ''} disponible${_trips.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.accent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE8F5F2)),
              // Liste trajets
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: widget.accent, strokeWidth: 2.5))
                    : _trips.isEmpty
                        ? _FeaturedTripsEmpty(accent: widget.accent)
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                            itemCount: _trips.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 14),
                            itemBuilder: (context, i) => _FeaturedTripCard(
                              trip: _trips[i],
                              accent: widget.accent,
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onOpenTrip(_trips[i]);
                              },
                            )
                                .animate()
                                .fadeIn(delay: Duration(milliseconds: 40 * i), duration: 220.ms)
                                .slideY(begin: 0.06, end: 0),
                          ),
              ),
            ],
          ),
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

class _LoginCallToActionButton extends StatelessWidget {
  const _LoginCallToActionButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Se connecter',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.1,
            ),
      )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(
            duration: 2400.ms,
            color: const Color(0xFFFFF3BF),
            angle: 0.2,
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

// ── Sélecteur de type de véhicule ────────────────────────────────────────────

class _VehicleChipRow extends StatelessWidget {
  const _VehicleChipRow({
    required this.types,
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  final List<VehicleType> types;
  final VehicleType? selected;
  final Color accent;
  final ValueChanged<VehicleType> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final VehicleType type = types[index];
          final bool isSelected = selected?.id == type.id;
          final String? imageUrl = type.imageUrl;

          return GestureDetector(
            onTap: () => onSelect(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 112,
              height: 82,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? accent : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: isSelected
                        ? accent.withValues(alpha: 0.38)
                        : Colors.black.withValues(alpha: 0.10),
                    blurRadius: isSelected ? 16 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // ── Image de fond ───────────────────────────────────
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            ColoredBox(color: accent.withValues(alpha: 0.12)),
                      )
                    else
                      ColoredBox(color: accent.withValues(alpha: 0.12)),

                    // ── Gradient sombre bas ──────────────────────────────
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: <double>[0.3, 1.0],
                          colors: <Color>[
                            Colors.transparent,
                            Color(0xCC000000),
                          ],
                        ),
                      ),
                    ),

                    // ── Overlay teal si sélectionné ──────────────────────
                    if (isSelected)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),

                    // ── Nom en bas ───────────────────────────────────────
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 7,
                      child: Text(
                        type.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),

                    // ── Badge ✓ en haut à droite si sélectionné ─────────
                    if (isSelected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Confort Services ─────────────────────────────────────────────────────────

enum _ConfortServiceType { taxi, alimentation }

class _ConfortServicesSection extends StatelessWidget {
  const _ConfortServicesSection({required this.accent});
  final Color accent;

  void _openInfo(BuildContext context, _ConfortServiceType type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfortServiceSheet(type: type, accent: accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Services Confort',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Voyagez sereinement de porte à porte.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF5B6472),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ConfortServiceCard(
                type: _ConfortServiceType.taxi,
                accent: accent,
                onTap: () => _openInfo(context, _ConfortServiceType.taxi),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ConfortServiceCard(
                type: _ConfortServiceType.alimentation,
                accent: accent,
                onTap: () => _openInfo(context, _ConfortServiceType.alimentation),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfortServiceCard extends StatelessWidget {
  const _ConfortServiceCard({
    required this.type,
    required this.accent,
    required this.onTap,
  });

  final _ConfortServiceType type;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isTaxi = type == _ConfortServiceType.taxi;

    final IconData icon = isTaxi ? Icons.local_taxi_rounded : Icons.lunch_dining_rounded;
    final String title = isTaxi ? 'Taxi' : 'Alimentation';
    final String subtitle = isTaxi
        ? 'Gare → Domicile\nDomicile → Gare'
        : 'Kit voyageur\nà emporter';
    final List<Color> gradientColors = isTaxi
        ? [const Color(0xFF1A3A5C), const Color(0xFF14B8A6)]
        : [const Color(0xFF7C3A00), const Color(0xFFE67E22)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Cercle décoratif
            Positioned(
              top: -18,
              right: -18,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -24,
              left: -12,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            // Contenu
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            // Badge "En savoir plus"
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  'Info',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfortServiceSheet extends StatelessWidget {
  const _ConfortServiceSheet({required this.type, required this.accent});
  final _ConfortServiceType type;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isTaxi = type == _ConfortServiceType.taxi;

    final String title = isTaxi ? 'Service Taxi' : 'Kit Alimentation';
    final IconData icon = isTaxi ? Icons.local_taxi_rounded : Icons.lunch_dining_rounded;
    final List<Color> gradientColors = isTaxi
        ? [const Color(0xFF1A3A5C), const Color(0xFF14B8A6)]
        : [const Color(0xFF7C3A00), const Color(0xFFE67E22)];

    final List<_InfoRow> rows = isTaxi
        ? const [
            _InfoRow(icon: Icons.trip_origin_rounded, label: 'Départ', value: 'Votre domicile ou un point de rendez-vous'),
            _InfoRow(icon: Icons.directions_transit_rounded, label: 'Arrivée', value: 'La gare routière de votre ville'),
            _InfoRow(icon: Icons.u_turn_left_rounded, label: 'Retour', value: 'De la gare jusqu\'à votre domicile'),
            _InfoRow(icon: Icons.schedule_rounded, label: 'Disponibilité', value: 'En fonction des horaires de départ'),
            _InfoRow(icon: Icons.info_outline_rounded, label: 'Note', value: 'Service disponible prochainement dans votre zone.'),
          ]
        : const [
            _InfoRow(icon: Icons.lunch_dining_rounded, label: 'Contenu', value: 'Eau, snacks, fruits secs et encas pour le trajet'),
            _InfoRow(icon: Icons.add_shopping_cart_rounded, label: 'Commande', value: 'Ajoutez le kit lors de votre réservation'),
            _InfoRow(icon: Icons.local_shipping_rounded, label: 'Livraison', value: 'Remis directement à bord ou en gare'),
            _InfoRow(icon: Icons.info_outline_rounded, label: 'Note', value: 'Service disponible prochainement sur certains trajets.'),
          ];

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FFFE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Infos
          ...rows.map((row) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: gradientColors.last.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(row.icon, size: 18, color: gradientColors.last),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(row.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F1A35))),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
}
