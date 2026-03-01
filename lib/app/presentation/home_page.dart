import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';

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
  HomeMode _activeMode = HomeMode.travel;
  int _travelIndex = 0;
  int _parcelsIndex = 0;

  static const List<HomeMenuItem> _travelItems = [
    HomeMenuItem(
      title: 'Ajouter trajet',
      subtitle: 'Publier un nouveau trajet',
      route: AppRoutes.travelAddTrip,
      icon: Icons.add_road_outlined,
    ),
    HomeMenuItem(
      title: 'Reserver',
      subtitle: 'Trouver une place disponible',
      route: AppRoutes.travelBookTrip,
      icon: Icons.event_seat_outlined,
    ),
    HomeMenuItem(
      title: 'Mes trajet',
      subtitle: 'Gerer vos trajets',
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
      title: 'Expedier',
      subtitle: 'Creer et suivre un envoi',
      route: AppRoutes.parcelsShipPackage,
      icon: Icons.local_shipping_outlined,
    ),
    HomeMenuItem(
      title: 'Vip shopping',
      subtitle: 'Demander un achat assiste',
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
  Widget build(BuildContext context) {
    final bool isTravel = _activeMode == HomeMode.travel;
    final Color accent = isTravel ? const Color(0xFF0B5FFF) : const Color(0xFF0A5C36);
    final List<HomeMenuItem> items = _activeItems;

    return Scaffold(
      appBar: AppBar(title: const Text('GoVIP Services')),
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
                          selectedColor: const Color(0xFF0B5FFF),
                          onTap: () => _selectMode(HomeMode.travel),
                        ),
                      ),
                      Expanded(
                        child: _ModeButton(
                          label: 'Colis',
                          selected: !isTravel,
                          selectedColor: const Color(0xFF0A5C36),
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
                          ? 'Publiez un trajet, reservez rapidement et restez connecte avec vos voyageurs.'
                          : 'Choisissez le service adapte: expedition, shopping VIP ou proposition de transport.',
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Actions principales',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                          ),
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
