import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';
import 'package:govipservices/features/travel/data/transport_company_repository.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/transport_company.dart';
import 'package:govipservices/features/travel/presentation/pages/go_radar_update_page.dart';

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _bg = Color(0xFFF2FFFC);
const Color _surface = Color(0xFFFFFFFF);
const Color _border = Color(0xFFD8F3EE);

class _DepartureSlot {
  const _DepartureSlot({required this.trip, required this.slotNumber});

  final TripSearchResult trip;
  final int slotNumber;

  String get id => '${trip.id}_slot$slotNumber';
}

class _Route {
  const _Route({required this.departure, required this.arrival});

  final String departure;
  final String arrival;

  @override
  bool operator ==(Object other) {
    return other is _Route &&
        other.departure == departure &&
        other.arrival == arrival;
  }

  @override
  int get hashCode => Object.hash(departure, arrival);
}

class GoRadarReporterPage extends StatefulWidget {
  const GoRadarReporterPage({super.key});

  @override
  State<GoRadarReporterPage> createState() => _GoRadarReporterPageState();
}

class _GoRadarReporterPageState extends State<GoRadarReporterPage> {
  final TransportCompanyRepository _companyRepo = TransportCompanyRepository();
  final TravelRepository _travelRepo = TravelRepository();
  final GoRadarRepository _goRadarRepo = GoRadarRepository();

  int _step = 0;
  List<TransportCompany> _companies = const <TransportCompany>[];
  bool _checkingActiveSession = true;
  bool _loadingCompanies = true;
  TransportCompany? _selectedCompany;
  List<_Route> _routes = const <_Route>[];
  bool _loadingRoutes = false;
  _Route? _selectedRoute;
  List<_DepartureSlot> _slots = const <_DepartureSlot>[];
  Set<String> _takenSlotIds = const <String>{};
  bool _loadingDepartures = false;
  _DepartureSlot? _selectedSlot;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final GoRadarSession? activeSession =
          await _goRadarRepo.fetchMyActiveSession();
      if (!mounted) return;
      if (activeSession != null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GoRadarUpdatePage(
              args: GoRadarSessionArgs.fromSession(activeSession),
              initialSession: activeSession,
            ),
          ),
        );
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _checkingActiveSession = false);
      }
    }

    await _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    try {
      final List<TransportCompany> list = await _companyRepo.fetchEnabled();
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
      _routes = const <_Route>[];
      _selectedRoute = null;
      _slots = const <_DepartureSlot>[];
      _takenSlotIds = const <String>{};
      _selectedSlot = null;
    });

    try {
      final List<TripSearchResult> trips =
          await _travelRepo.fetchTripsByCompanyName(company.name);
      if (!mounted) return;
      final Set<_Route> seen = <_Route>{};
      final List<_Route> routes = <_Route>[];
      for (final TripSearchResult trip in trips) {
        final _Route route = _Route(
          departure: trip.departurePlace,
          arrival: trip.arrivalPlace,
        );
        if (seen.add(route)) {
          routes.add(route);
        }
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
      _slots = const <_DepartureSlot>[];
      _takenSlotIds = const <String>{};
      _selectedSlot = null;
    });

    try {
      final List<TripSearchResult> trips = await _travelRepo.fetchTripsByCompanyName(
        _selectedCompany!.name,
      );
      if (!mounted) return;

      final List<TripSearchResult> filtered = trips.where((TripSearchResult trip) {
        return trip.departurePlace == route.departure &&
            trip.arrivalPlace == route.arrival;
      }).toList()
        ..sort((a, b) => (a.departureTime ?? '').compareTo(b.departureTime ?? ''));

      final List<_DepartureSlot> slots = <_DepartureSlot>[
        for (final TripSearchResult trip in filtered)
          for (int slot = 1; slot <= 3; slot++)
            _DepartureSlot(trip: trip, slotNumber: slot),
      ];

      final DateTime now = DateTime.now();
      final String date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final Set<String> takenSlotIds = await _goRadarRepo.fetchTakenSlotIds(
        companyId: _selectedCompany!.id,
        departure: route.departure,
        arrival: route.arrival,
        date: date,
      );

      setState(() {
        _slots = slots;
        _takenSlotIds = takenSlotIds;
        _loadingDepartures = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDepartures = false);
    }
  }

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
    if (_takenSlotIds.contains(slot.id)) return;
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
        _slots = const <_DepartureSlot>[];
        _takenSlotIds = const <String>{};
        _selectedSlot = null;
      } else {
        _step = 0;
        _selectedCompany = null;
        _routes = const <_Route>[];
      }
    });
  }

  Future<void> _confirm() async {
    if (_selectedSlot == null || _confirming) return;

    final TripSearchResult trip = _selectedSlot!.trip;
    final DateTime now = DateTime.now();
    final String date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final GoRadarSessionArgs args = GoRadarSessionArgs(
      tripId: trip.id,
      companyId: _selectedCompany!.id,
      companyName: _selectedCompany!.name,
      departure: trip.departurePlace,
      arrival: trip.arrivalPlace,
      scheduledTime: trip.departureTime ?? '-',
      slotNumber: _selectedSlot!.slotNumber,
      date: date,
      departureLat: (trip.raw['departureLat'] as num?)?.toDouble(),
      departureLng: (trip.raw['departureLng'] as num?)?.toDouble(),
      arrivalLat: (trip.raw['arrivalLat'] as num?)?.toDouble(),
      arrivalLng: (trip.raw['arrivalLng'] as num?)?.toDouble(),
    );

    setState(() => _confirming = true);
    try {
      final Position position = await _getCurrentPosition();
      final GoRadarSession session = await _goRadarRepo.openSession(
        args,
        reporterLat: position.latitude,
        reporterLng: position.longitude,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GoRadarUpdatePage(
            args: args,
            initialSession: session,
            autoStartReminder: true,
          ),
        ),
      );
      if (mounted && _selectedRoute != null) {
        _loadDepartures(_selectedRoute!);
      }
    } on GoRadarException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Impossible d\'ouvrir la session GO Radar.');
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  Future<Position> _getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const GoRadarException(
        'Activez la localisation pour ouvrir une session.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const GoRadarException(
        'Autorisez le GPS pour ouvrir une session GO Radar.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_checkingActiveSession) {
      body = const _LoadingBody(key: ValueKey('checking-session'));
    } else {
      body = switch (_step) {
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
                takenSlotIds: _takenSlotIds,
                selected: _selectedSlot,
                onSelect: _selectSlot,
                onConfirm: _confirm,
                confirming: _confirming,
              ),
        _ => const SizedBox.shrink(),
      };
    }

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
        child: body,
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  static const List<String> _labels = <String>[
    'Compagnie',
    'Trajet',
    'Depart',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: List<Widget>.generate(_labels.length * 2 - 1, (int index) {
          if (index.isOdd) {
            return Expanded(
              child: Container(
                height: 2,
                color: index ~/ 2 < step ? _accent : Colors.grey.shade200,
              ),
            );
          }

          final int stepIndex = index ~/ 2;
          final bool done = stepIndex < step;
          final bool active = stepIndex == step;
          return _StepDot(
            label: _labels[stepIndex],
            index: stepIndex + 1,
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
      children: <Widget>[
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

class _CompanyStep extends StatelessWidget {
  const _CompanyStep({
    super.key,
    required this.companies,
    required this.onSelect,
  });

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
      itemBuilder: (_, int index) {
        final TransportCompany company = companies[index];
        return _SelectionCard(
          leading: company.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    company.imageUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _CompanyInitial(name: company.name),
                  ),
                )
              : _CompanyInitial(name: company.name),
          title: company.name,
          subtitle: company.contact,
          onTap: () => onSelect(company),
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
      return _EmptyBody(message: 'Aucun trajet trouve pour ${company.name}');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, int index) {
        final _Route route = routes[index];
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
          title: '${route.departure} -> ${route.arrival}',
          onTap: () => onSelect(route),
        );
      },
    );
  }
}

class _DepartureStep extends StatefulWidget {
  const _DepartureStep({
    super.key,
    required this.route,
    required this.slots,
    required this.takenSlotIds,
    required this.selected,
    required this.onSelect,
    required this.onConfirm,
    required this.confirming,
  });

  final _Route route;
  final List<_DepartureSlot> slots;
  final Set<String> takenSlotIds;
  final _DepartureSlot? selected;
  final void Function(_DepartureSlot) onSelect;
  final Future<void> Function() onConfirm;
  final bool confirming;

  @override
  State<_DepartureStep> createState() => _DepartureStepState();
}

class _DepartureStepState extends State<_DepartureStep> {
  final Map<String, bool> _expanded = <String, bool>{};

  Map<String, List<_DepartureSlot>> get _grouped {
    final Map<String, List<_DepartureSlot>> grouped =
        <String, List<_DepartureSlot>>{};
    for (final _DepartureSlot slot in widget.slots) {
      final String key = slot.trip.departureTime ?? '-';
      grouped.putIfAbsent(key, () => <_DepartureSlot>[]).add(slot);
    }
    return grouped;
  }

  void _toggle(String time) {
    setState(() => _expanded[time] = !(_expanded[time] ?? false));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slots.isEmpty) {
      return const _EmptyBody(message: 'Aucun depart trouve pour ce trajet');
    }

    final Map<String, List<_DepartureSlot>> grouped = _grouped;
    final List<String> times = grouped.keys.toList();

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            itemCount: times.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, int index) {
              final String time = times[index];
              final List<_DepartureSlot> groupSlots = grouped[time]!;
              final bool isOpen = _expanded[time] ?? false;
              final bool hasSelection = groupSlots.any(
                (_DepartureSlot slot) => slot.id == widget.selected?.id,
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
                  children: <Widget>[
                    InkWell(
                      onTap: () => _toggle(time),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: <Widget>[
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
                                color: hasSelection ? Colors.white : _accentDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Selectionner le depart de $time',
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
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: isOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: <Widget>[
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade100,
                          ),
                          ...groupSlots.map((slot) {
                            final bool isSelected = widget.selected?.id == slot.id;
                            final bool isTaken =
                                widget.takenSlotIds.contains(slot.id);
                            return InkWell(
                              onTap: isTaken ? null : () => widget.onSelect(slot),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                color: isTaken
                                    ? Colors.grey.shade50
                                    : isSelected
                                        ? _accent.withValues(alpha: 0.06)
                                        : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const SizedBox(width: 52),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isTaken
                                            ? Colors.grey.shade300
                                            : isSelected
                                                ? _accent
                                                : Colors.grey.shade300,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            'Depart ${slot.slotNumber}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isTaken
                                                  ? Colors.grey.shade400
                                                  : isSelected
                                                      ? _accentDark
                                                      : const Color(0xFF334155),
                                            ),
                                          ),
                                          if (isTaken)
                                            Text(
                                              'Indisponible aujourd\'hui',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isTaken)
                                      Icon(
                                        Icons.block_rounded,
                                        color: Colors.grey.shade400,
                                        size: 18,
                                      )
                                    else if (isSelected)
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
              onPressed: widget.selected != null && !widget.confirming
                  ? widget.onConfirm
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accentDark,
                disabledBackgroundColor: Colors.grey.shade200,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: widget.confirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Configurer ce depart',
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
          children: <Widget>[
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
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
          children: <Widget>[
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
