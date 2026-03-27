import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';
import 'package:govipservices/features/travel/data/transport_company_repository.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/transport_company.dart';
import 'package:govipservices/features/travel/presentation/pages/go_radar_update_page.dart';

// ─── Couleurs partagées ───────────────────────────────────────────────────────

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _bg = Color(0xFFF2FFFC);
const Color _surface = Color(0xFFFFFFFF);
const Color _border = Color(0xFFD8F3EE);

// ─── Modèle interne slot de départ ───────────────────────────────────────────

class _DepartureSlot {
  const _DepartureSlot({required this.trip, required this.slotNumber});

  final TripSearchResult trip;
  final int slotNumber; // 1, 2 ou 3

  String get id => '${trip.id}_slot$slotNumber';
}

// ─── Modèle interne route ─────────────────────────────────────────────────────

class _Route {
  const _Route({required this.departure, required this.arrival});
  final String departure;
  final String arrival;

  @override
  bool operator ==(Object other) =>
      other is _Route &&
      other.departure == departure &&
      other.arrival == arrival;

  @override
  int get hashCode => Object.hash(departure, arrival);
}

// ─── Page principale ──────────────────────────────────────────────────────────

class GoRadarReporterPage extends StatefulWidget {
  const GoRadarReporterPage({super.key});

  @override
  State<GoRadarReporterPage> createState() => _GoRadarReporterPageState();
}

class _GoRadarReporterPageState extends State<GoRadarReporterPage> {
  final TransportCompanyRepository _companyRepo = TransportCompanyRepository();
  final TravelRepository _travelRepo = TravelRepository();

  // étape active : 0 = compagnie, 1 = route, 2 = départ
  int _step = 0;

  // données
  List<TransportCompany> _companies = const [];
  bool _loadingCompanies = true;

  TransportCompany? _selectedCompany;
  List<_Route> _routes = const [];
  bool _loadingRoutes = false;

  _Route? _selectedRoute;
  List<_DepartureSlot> _slots = const [];
  bool _loadingDepartures = false;

  _DepartureSlot? _selectedSlot;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  // ── Chargements ──────────────────────────────────────────────────────────────

  Future<void> _loadCompanies() async {
    try {
      final list = await _companyRepo.fetchEnabled();
      if (!mounted) return;
      setState(() {
        _companies = list;
        _loadingCompanies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCompanies = false);
    }
  }

  Future<void> _loadRoutes(TransportCompany company) async {
    setState(() {
      _loadingRoutes = true;
      _routes = const [];
      _selectedRoute = null;
      _slots = const [];
      _selectedSlot = null;
    });
    try {
      final trips = await _travelRepo.fetchTripsByCompanyName(company.name);
      if (!mounted) return;
      final seen = <_Route>{};
      final routes = <_Route>[];
      for (final t in trips) {
        final r = _Route(departure: t.departurePlace, arrival: t.arrivalPlace);
        if (seen.add(r)) routes.add(r);
      }
      setState(() {
        _routes = routes;
        _loadingRoutes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRoutes = false);
    }
  }

  Future<void> _loadDepartures(_Route route) async {
    setState(() {
      _loadingDepartures = true;
      _slots = const [];
      _selectedSlot = null;
    });
    try {
      final trips = await _travelRepo.fetchTripsByCompanyName(
        _selectedCompany!.name,
      );
      if (!mounted) return;
      final filtered = trips
          .where(
            (t) =>
                t.departurePlace == route.departure &&
                t.arrivalPlace == route.arrival,
          )
          .toList();
      filtered.sort((a, b) {
        final at = a.departureTime ?? '';
        final bt = b.departureTime ?? '';
        return at.compareTo(bt);
      });
      // Génère 3 slots par document (même créneau, bus différents)
      final slots = <_DepartureSlot>[
        for (final trip in filtered)
          for (int s = 1; s <= 3; s++)
            _DepartureSlot(trip: trip, slotNumber: s),
      ];
      setState(() {
        _slots = slots;
        _loadingDepartures = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDepartures = false);
    }
  }

  // ── Navigation entre étapes ──────────────────────────────────────────────────

  void _selectCompany(TransportCompany company) {
    setState(() {
      _selectedCompany = company;
      _step = 1;
    });
    _loadRoutes(company);
  }

  void _selectRoute(_Route route) {
    setState(() {
      _selectedRoute = route;
      _step = 2;
    });
    _loadDepartures(route);
  }

  void _selectSlot(_DepartureSlot slot) {
    setState(() => _selectedSlot = slot);
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_step == 2) {
        _step = 1;
        _selectedRoute = null;
        _slots = const [];
        _selectedSlot = null;
      } else if (_step == 1) {
        _step = 0;
        _selectedCompany = null;
        _routes = const [];
      }
    });
  }

  void _confirm() {
    if (_selectedSlot == null) return;
    final trip = _selectedSlot!.trip;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final args = GoRadarSessionArgs(
      tripId: trip.id,
      companyId: _selectedCompany!.id,
      companyName: _selectedCompany!.name,
      departure: trip.departurePlace,
      arrival: trip.arrivalPlace,
      scheduledTime: trip.departureTime ?? '—',
      slotNumber: _selectedSlot!.slotNumber,
      date: date,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoRadarUpdatePage(args: args),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _goBack,
        ),
        title: const Text(
          'GO Radar',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _StepIndicator(step: _step),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: switch (_step) {
          0 => _loadingCompanies
              ? const _LoadingBody(key: ValueKey('loading-companies'))
              : _CompanyStep(
                  key: const ValueKey('step-company'),
                  companies: _companies,
                  onSelect: _selectCompany,
                ),
          1 => _loadingRoutes
              ? const _LoadingBody(key: ValueKey('loading-routes'))
              : _RouteStep(
                  key: const ValueKey('step-route'),
                  company: _selectedCompany!,
                  routes: _routes,
                  onSelect: _selectRoute,
                ),
          2 => _loadingDepartures
              ? const _LoadingBody(key: ValueKey('loading-departures'))
              : _DepartureStep(
                  key: const ValueKey('step-departure'),
                  route: _selectedRoute!,
                  slots: _slots,
                  selected: _selectedSlot,
                  onSelect: _selectSlot,
                  onConfirm: _confirm,
                ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

// ─── Indicateur d'étapes ──────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final int step;

  static const _labels = ['Compagnie', 'Trajet', 'Départ'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: List.generate(_labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // connecteur
            return Expanded(
              child: Container(
                height: 2,
                color: i ~/ 2 < step ? _accent : Colors.grey.shade200,
              ),
            );
          }
          final idx = i ~/ 2;
          final done = idx < step;
          final active = idx == step;
          return _StepDot(
            label: _labels[idx],
            index: idx + 1,
            done: done,
            active: active,
          );
        }),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.index,
    required this.done,
    required this.active,
  });
  final String label;
  final int index;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color bg = done || active ? _accent : Colors.grey.shade200;
    final Color fg = done || active ? Colors.white : Colors.grey.shade400;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? _accentDark : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }
}

// ─── Étape 1 : Compagnie ─────────────────────────────────────────────────────

class _CompanyStep extends StatelessWidget {
  const _CompanyStep({super.key, required this.companies, required this.onSelect});
  final List<TransportCompany> companies;
  final void Function(TransportCompany) onSelect;

  @override
  Widget build(BuildContext context) {
    if (companies.isEmpty) {
      return const _EmptyBody(message: 'Aucune compagnie disponible');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: companies.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = companies[i];
        return _SelectionCard(
          leading: c.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    c.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _CompanyInitial(name: c.name),
                  ),
                )
              : _CompanyInitial(name: c.name),
          title: c.name,
          subtitle: c.contact,
          onTap: () => onSelect(c),
        );
      },
    );
  }
}

class _CompanyInitial extends StatelessWidget {
  const _CompanyInitial({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'C',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _accentDark,
          ),
        ),
      ),
    );
  }
}

// ─── Étape 2 : Trajet ─────────────────────────────────────────────────────────

class _RouteStep extends StatelessWidget {
  const _RouteStep({
    super.key,
    required this.company,
    required this.routes,
    required this.onSelect,
  });
  final TransportCompany company;
  final List<_Route> routes;
  final void Function(_Route) onSelect;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return _EmptyBody(
        message: 'Aucun trajet trouvé pour ${company.name}',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = routes[i];
        return _SelectionCard(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.route_outlined, color: _accentDark, size: 22),
          ),
          title: '${r.departure}  →  ${r.arrival}',
          onTap: () => onSelect(r),
        );
      },
    );
  }
}

// ─── Étape 3 : Départ ─────────────────────────────────────────────────────────

class _DepartureStep extends StatefulWidget {
  const _DepartureStep({
    super.key,
    required this.route,
    required this.slots,
    required this.selected,
    required this.onSelect,
    required this.onConfirm,
  });
  final _Route route;
  final List<_DepartureSlot> slots;
  final _DepartureSlot? selected;
  final void Function(_DepartureSlot) onSelect;
  final VoidCallback onConfirm;

  @override
  State<_DepartureStep> createState() => _DepartureStepState();
}

class _DepartureStepState extends State<_DepartureStep> {
  // clé = departureTime, valeur = expanded ou non
  final Map<String, bool> _expanded = {};

  // Groupe les slots par heure de départ
  Map<String, List<_DepartureSlot>> get _grouped {
    final map = <String, List<_DepartureSlot>>{};
    for (final slot in widget.slots) {
      final key = slot.trip.departureTime ?? '—';
      map.putIfAbsent(key, () => []).add(slot);
    }
    return map;
  }

  void _toggle(String time) {
    setState(() => _expanded[time] = !(_expanded[time] ?? false));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) {
      return const _EmptyBody(message: 'Aucun départ trouvé pour ce trajet');
    }
    final grouped = _grouped;
    final times = grouped.keys.toList();

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            itemCount: times.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final time = times[i];
              final groupSlots = grouped[time]!;
              final isOpen = _expanded[time] ?? false;
              // Vérifie si un slot de ce groupe est sélectionné
              final hasSelection = groupSlots.any(
                (s) => s.id == widget.selected?.id,
              );

              return Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasSelection ? _accent : _border,
                    width: hasSelection ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: [
                    // ── En-tête cliquable ──────────────────────────────
                    InkWell(
                      onTap: () => _toggle(time),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: hasSelection
                                    ? _accent
                                    : _accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.schedule_rounded,
                                size: 20,
                                color: hasSelection
                                    ? Colors.white
                                    : _accentDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Sélectionner le départ de $time',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: hasSelection
                                      ? _accentDark
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (hasSelection)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: _accent,
                                  size: 18,
                                ),
                              ),
                            AnimatedRotation(
                              turns: isOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.grey.shade400,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ── Slots dépliables ──────────────────────────────
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: isOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade100,
                          ),
                          ...groupSlots.map((slot) {
                            final bool isSelected =
                                widget.selected?.id == slot.id;
                            return InkWell(
                              onTap: () => widget.onSelect(slot),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                color: isSelected
                                    ? _accent.withValues(alpha: 0.06)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 52),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? _accent
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Départ ${slot.slotNumber}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? _accentDark
                                              : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_rounded,
                                        color: _accent,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: widget.selected != null ? widget.onConfirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accentDark,
                disabledBackgroundColor: Colors.grey.shade200,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Configurer ce départ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Composants réutilisables ─────────────────────────────────────────────────

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCBD5E1),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
