import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/travel/data/transport_company_repository.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/data/trip_search_service.dart' show normalize;
import 'package:govipservices/features/travel/domain/models/transport_company.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/shared/services/location_service.dart';

enum _BookingDateChoice { today, tomorrow, custom }

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);
const Color _travelPageBg = Color(0xFFF2FFFC);
const Color _travelPageBgAlt = Color(0xFFE6FFFA);
const Color _travelSurfaceBorder = Color(0xFFD8F3EE);

class BookTripPage extends StatefulWidget {
  const BookTripPage({super.key});

  @override
  State<BookTripPage> createState() => _BookTripPageState();
}

class _BookTripPageState extends State<BookTripPage> {
  String get _googleMapsApiKey => RuntimeAppConfig.googleMapsApiKey;

  final TravelRepository _travelRepository = TravelRepository();
  final TransportCompanyRepository _companyRepo = TransportCompanyRepository();

  List<TransportCompany> _companies = const <TransportCompany>[];
  Set<String> _selectedCompanyIds = const <String>{};

  final TextEditingController _departureController = TextEditingController();
  final TextEditingController _arrivalController = TextEditingController();
  final PageController _pageController = PageController();

  int _currentStep = 0;
  bool _isAutoAdvancingToArrival = false;
  bool _isFetchingLocation = false;
  bool _isSearchingTrips = false;
  _BookingDateChoice _dateChoice = _BookingDateChoice.today;
  DateTime? _customDate;
  List<TripSearchResult> _lastResults = const <TripSearchResult>[];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _prefillDepartureIfReady();
  }

  void _prefillDepartureIfReady() {
    final String? cached = LocationService.instance.cachedAddress;
    if (cached != null && _departureController.text.isEmpty) {
      _departureController.text = cached;
    }
  }


  Future<void> _loadCompanies() async {
    try {
      final List<TransportCompany> list = await _companyRepo.fetchEnabled();
      if (!mounted) return;
      setState(() {
        _companies = list;
      });
      debugPrint('[BookTrip] ${list.length} compagnies chargées: ${list.map((c) => c.name).join(', ')}');
    } catch (e) {
      debugPrint('[BookTrip] Erreur chargement compagnies: $e');
    }
  }

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToStep(int step) async {
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubicEmphasized,
    );
    if (!mounted) return;
    setState(() => _currentStep = step);
  }

  DateTime get _selectedDate {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (_dateChoice == _BookingDateChoice.today) {
      return today;
    }
    if (_dateChoice == _BookingDateChoice.tomorrow) {
      return today.add(const Duration(days: 1));
    }
    return _customDate ?? today;
  }

  void _showMessage(String message, {IconData icon = Icons.info_outline}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  Future<void> _useCurrentLocationForDeparture() async {
    if (_isFetchingLocation) return;
    setState(() => _isFetchingLocation = true);
    try {
      final String? address = (await LocationService.instance.getCurrent())?.address;
      if (!mounted) return;
      if (address == null) {
        _showMessage(
          'Impossible de récupérer votre position actuelle.',
          icon: Icons.error_outline,
        );
        return;
      }
      _departureController.text = address;
      _departureController.selection = TextSelection.collapsed(offset: address.length);
      _showMessage('Départ renseigné depuis votre position.');
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Impossible de récupérer votre position actuelle.',
        icon: Icons.error_outline,
      );
    } finally {
      if (!mounted) return;
      setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _selectDateChoice(_BookingDateChoice choice) async {
    if (choice != _BookingDateChoice.custom) {
      setState(() {
        _dateChoice = choice;
      });
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime initialDate = _customDate ?? today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      locale: const Locale('fr', 'FR'),
      helpText: 'Choisir une date',
    );

    if (picked == null || !mounted) return;
    setState(() {
      _customDate = picked;
      _dateChoice = _BookingDateChoice.custom;
    });
  }

  Future<void> _openDepartureSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddressSheet(
        title: 'Départ',
        hint: 'Ex: Cocody, Abidjan',
        controller: _departureController,
        apiKey: _googleMapsApiKey,
        onGps: _useCurrentLocationForDeparture,
        isFetchingGps: _isFetchingLocation,
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (_departureController.text.trim().length >= 3 && _currentStep == 0) {
      if (!_isAutoAdvancingToArrival) {
        _isAutoAdvancingToArrival = true;
        await _goToStep(1);
        _isAutoAdvancingToArrival = false;
      }
    }
  }

  Future<void> _openArrivalSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddressSheet(
        title: 'Arrivée',
        hint: 'Ex: Plateau, Abidjan',
        controller: _arrivalController,
        apiKey: _googleMapsApiKey,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _submitSearch() async {
    final String departure = _departureController.text.trim();
    final String arrival = _arrivalController.text.trim();

    if (departure.length < 3) {
      _showMessage('Renseignez un départ valide.', icon: Icons.edit_location_alt_outlined);
      return;
    }

    if (arrival.length < 3) {
      _showMessage('Renseignez une arrivée valide.', icon: Icons.pin_drop_outlined);
      return;
    }

    setState(() {
      _isSearchingTrips = true;
    });

    try {
      List<TripSearchResult> results = await _travelRepository.searchAvailableTrips(
        departureQuery: departure,
        arrivalQuery: arrival,
        departureDate: _selectedDate,
      );
      if (_selectedCompanyIds.isNotEmpty) {
        final List<String> selectedNames = _companies
            .where((c) => _selectedCompanyIds.contains(c.id))
            .map((c) => c.name)
            .toList();
        results = results.where((trip) => _tripMatchesAnyCompany(trip.driverName, selectedNames)).toList();
      }
      if (!mounted) return;
      setState(() {
        _lastResults = results;
      });
      await _showSearchResultsBottomSheet(results);
    } catch (_) {
      _showMessage(
        'Erreur lors de la recherche des trajets. Vérifiez votre connexion.',
        icon: Icons.error_outline,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSearchingTrips = false;
      });
    }
  }

  Future<void> _showSearchResultsBottomSheet(List<TripSearchResult> results) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${results.length} trajet(s) disponible(s)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Aucun trajet trouvé pour ce jour.\nEssayez une autre arrivée ou une autre date.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF5B647A),
                                  ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          itemBuilder: (context, index) => _TripResultTile(
                            trip: results[index],
                            onTap: () {
                              final TripSearchResult trip = results[index];
                              Navigator.of(context).pop();
                              Navigator.of(this.context).pushNamed(
                                AppRoutes.travelTripDetail,
                                arguments: TripDetailArgs(
                                  tripId: trip.id,
                                  from: trip.departurePlace,
                                  to: trip.arrivalPlace,
                                  effectiveDepartureDate: trip.effectiveDepartureDate,
                                ),
                              );
                            },
                          )
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: 40 * index), duration: 220.ms)
                              .slideY(begin: 0.08, end: 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemCount: results.length,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _tripMatchesAnyCompany(String? driverName, List<String> companyNames) {
    if (driverName == null || driverName.isEmpty) return false;
    final String dn = normalize(driverName);
    for (final String name in companyNames) {
      final String cn = normalize(name);
      if (cn.isEmpty) continue;
      if (dn.contains(cn) || cn.contains(dn)) return true;
    }
    return false;
  }

  String _labelForChoice(_BookingDateChoice choice) {
    switch (choice) {
      case _BookingDateChoice.today:
        return "Aujourd'hui";
      case _BookingDateChoice.tomorrow:
        return 'Demain';
      case _BookingDateChoice.custom:
        final DateTime date = _selectedDate;
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    }
  }

  String _formatSelectedDateLabel() {
    final DateTime date = _selectedDate;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _travelPageBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_travelPageBgAlt, _travelPageBg, Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                // Bouton retour
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: _travelSurfaceBorder),
                        boxShadow: [
                          BoxShadow(
                            color: _travelAccent.withValues(alpha: 0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _travelAccentDark),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Hero
                _TopHero(
                  currentStep: _currentStep,
                  onStepTap: _goToStep,
                ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.08, end: 0),
                // Compagnies
                if (_companies.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _CompanyChipRow(
                    companies: _companies,
                    selectedIds: _selectedCompanyIds,
                    onToggle: (String id) => setState(() {
                      if (id == '__tous__') {
                        _selectedCompanyIds = const <String>{};
                      } else {
                        final Set<String> next = Set<String>.from(_selectedCompanyIds);
                        if (next.contains(id)) {
                          next.remove(id);
                        } else {
                          next.add(id);
                        }
                        _selectedCompanyIds = next;
                      }
                    }),
                  ),
                ],
                SizedBox(height: _companies.isNotEmpty ? 14 : 14),
                // Step cards
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (int index) => setState(() => _currentStep = index),
                    children: <Widget>[
                      // Step 0 — Départ
                      _StepCard(
                        icon: Icons.trip_origin_rounded,
                        title: 'Départ',
                        child: _AddressLureField(
                          value: _departureController.text.trim(),
                          hint: 'Ex: Cocody, Abidjan',
                          icon: Icons.my_location_rounded,
                          onTap: _openDepartureSheet,
                        ),
                      ).animate().fadeIn(delay: 40.ms, duration: 300.ms).slideY(begin: 0.08, end: 0),
                      // Step 1 — Arrivée + date
                      _StepCard(
                        icon: Icons.flag_circle_outlined,
                        title: 'Arrivée',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _AddressLureField(
                              value: _arrivalController.text.trim(),
                              hint: 'Ex: Plateau, Abidjan',
                              icon: Icons.flag_rounded,
                              onTap: _openArrivalSheet,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
                                for (final _BookingDateChoice choice in _BookingDateChoice.values) ...<Widget>[
                                  if (choice != _BookingDateChoice.values.first) const SizedBox(width: 8),
                                  Expanded(
                                    child: _DateChoiceChip(
                                      label: _labelForChoice(choice),
                                      selected: _dateChoice == choice,
                                      onTap: () => _selectDateChoice(choice),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Date choisie : ${_formatSelectedDateLabel()}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF5B647A),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 90.ms, duration: 300.ms).slideY(begin: 0.08, end: 0),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: _travelAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isSearchingTrips
                        ? null
                        : _currentStep == 0
                            ? (_departureController.text.trim().length >= 3 ? () => _goToStep(1) : null)
                            : _submitSearch,
                    icon: _isSearchingTrips
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_currentStep == 0 ? Icons.arrow_forward_rounded : Icons.search_rounded),
                    label: Text(
                      _isSearchingTrips
                          ? 'Recherche en cours...'
                          : (_currentStep == 0 ? 'Continuer vers arrivée' : 'Rechercher des trajets'),
                    ),
                  ),
                ).animate().fadeIn(delay: 120.ms, duration: 260.ms).slideY(begin: 0.12, end: 0),
                if (_lastResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${_lastResults.length} résultat(s) trouvé(s) lors de la dernière recherche.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF5B647A),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.18, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopHero extends StatelessWidget {
  const _TopHero({required this.currentStep, required this.onStepTap});
  final int currentStep;
  final ValueChanged<int> onStepTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_travelAccentDark, _travelAccent],
        ),
        boxShadow: [
          BoxShadow(
            color: _travelAccent.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre voyage commence ici',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '1. Départ  2. Arrivée + date',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _ProgressStep(label: 'Départ', selected: currentStep == 0, onTap: () => onStepTap(0))),
              const SizedBox(width: 8),
              Expanded(child: _ProgressStep(label: 'Arrivée', selected: currentStep == 1, onTap: () => onStepTap(1))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? _travelAccentDark : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14387B).withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _travelAccent, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AddressLureField extends StatelessWidget {
  const _AddressLureField({
    required this.value,
    required this.hint,
    required this.icon,
    required this.onTap,
  });
  final String value;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasValue = value.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: hasValue ? const Color(0xFFF0FDF9) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasValue ? _travelAccent.withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: hasValue ? _travelAccentDark : const Color(0xFFCBD5E1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? value : hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                ),
              ),
            ),
            Icon(
              hasValue ? Icons.edit_rounded : Icons.search_rounded,
              size: 16,
              color: hasValue ? _travelAccent : const Color(0xFFCBD5E1),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChoiceChip extends StatelessWidget {
  const _DateChoiceChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _travelAccent : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}


class _AddressSheet extends StatefulWidget {
  const _AddressSheet({
    required this.title,
    required this.hint,
    required this.controller,
    required this.apiKey,
    this.onGps,
    this.isFetchingGps = false,
  });
  final String title;
  final String hint;
  final TextEditingController controller;
  final String apiKey;
  final VoidCallback? onGps;
  final bool isFetchingGps;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height - 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(999)),
                ),
              ),
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 14),
              AddressAutocompleteField(
                controller: widget.controller,
                focusNode: _focus,
                labelText: widget.title,
                hintText: widget.hint,
                apiKey: widget.apiKey,
                onChanged: (_) {},
                onSuggestionSelected: (_) => Navigator.of(context).maybePop(),
              ),
              if (widget.onGps != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _travelAccentDark,
                      side: const BorderSide(color: _travelSurfaceBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: widget.isFetchingGps ? null : () {
                      widget.onGps!();
                      Navigator.of(context).maybePop();
                    },
                    icon: widget.isFetchingGps
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(widget.isFetchingGps ? 'Localisation...' : 'Utiliser ma position'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TripResultTile extends StatelessWidget {
  const _TripResultTile({
    required this.trip,
    this.onTap,
  });

  final TripSearchResult trip;
  final VoidCallback? onTap;

  String _priceLabel() {
    final double? value = trip.pricePerSeat;
    if (value == null) return '-';
    final String currency = (trip.currency == null || trip.currency!.isEmpty) ? 'XOF' : trip.currency!;
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)} $currency';
  }

  bool _shouldHidePrice() {
    final bool isIntermediateDeparture = trip.raw['isIntermediateDeparture'] == true;
    final bool isIntermediateArrival = trip.raw['isIntermediateArrival'] == true;
    final double value = trip.pricePerSeat ?? 0;
    return isIntermediateDeparture && isIntermediateArrival && value == 0;
  }

  String _arrivalTimeLabel() {
    final Map<String, dynamic> raw = trip.raw;
    final List<String> candidates = <String>[
      (raw['arrivalEstimatedTime'] ?? '').toString().trim(),
      (raw['arrivalTime'] ?? '').toString().trim(),
      (raw['estimatedArrivalTime'] ?? '').toString().trim(),
    ];
    for (final String value in candidates) {
      if (value.isNotEmpty) return value;
    }
    return '--:--';
  }

  String _driverLabel() {
    final String name = (trip.driverName ?? '').trim();
    return name.isEmpty ? 'Conducteur non renseigné' : name;
  }

  String _vehicleLabel() {
    final String vehicle = (trip.raw['vehicleModel'] ?? '').toString().trim();
    return vehicle.isEmpty ? 'Véhicule non renseigné' : vehicle;
  }

  @override
  Widget build(BuildContext context) {
    final String departureTime =
        (trip.departureTime ?? '').trim().isEmpty ? '--:--' : (trip.departureTime ?? '').trim();
    final String arrivalTime = _arrivalTimeLabel();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _travelSurfaceBorder),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFF4FFFC),
                Color(0xFFE8FFFA),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _travelAccent.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 54,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _travelSurfaceBorder),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  departureTime,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F1A35),
                                  ),
                                ),
                                Text(
                                  arrivalTime,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F1A35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 18,
                            child: SizedBox(
                              height: 60,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _travelAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: _travelAccent.withValues(alpha: 0.35),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 2,
                                  height: 24,
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Color(0xFF7DE6D9), Color(0xFFB7D9D4)],
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF8FB7B1),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 60,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trip.departurePlace,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10233E),
                                        ),
                                      ),
                                      Text(
                                        trip.arrivalPlace,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10233E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!_shouldHidePrice())
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_travelAccentDark, _travelAccent],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _travelAccent.withValues(alpha: 0.24),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Prix',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _priceLabel(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _travelSurfaceBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF516186)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _driverLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF223253),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.directions_car_outlined, size: 16, color: Color(0xFF516186)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _vehicleLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF223253),
                              ),
                            ),
                          ),
                          if (trip.seats != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: _travelAccentSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${trip.seats} pl.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _travelAccentDark,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (trip.trackNum != null && trip.trackNum!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.confirmation_number_outlined, size: 15, color: Color(0xFF6C7C94)),
                      const SizedBox(width: 6),
                      Text(
                        'Ref: ${trip.trackNum}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF5B647A),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyChipRow extends StatelessWidget {
  const _CompanyChipRow({
    required this.companies,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<TransportCompany> companies;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selectedIds.isEmpty;
    // "Tous" + compagnies
    final int count = companies.length + 1;

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            // Chip "Tous"
            return GestureDetector(
              onTap: () => onToggle('__tous__'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: allSelected ? _travelAccent : const Color(0xFFD8F3EE),
                    width: allSelected ? 2.5 : 1.5,
                  ),
                  color: allSelected
                      ? _travelAccent.withValues(alpha: 0.10)
                      : Colors.white,
                  boxShadow: allSelected
                      ? [
                          BoxShadow(
                            color: _travelAccent.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: Text(
                    'Tous',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: allSelected ? _travelAccentDark : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            );
          }

          final TransportCompany company = companies[index - 1];
          final bool isSelected = selectedIds.contains(company.id);

          return GestureDetector(
            onTap: () => onToggle(company.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? _travelAccent : const Color(0xFFD8F3EE),
                  width: isSelected ? 2.5 : 1.5,
                ),
                color: isSelected
                    ? _travelAccent.withValues(alpha: 0.07)
                    : Colors.white,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _travelAccent.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (company.imageUrl != null)
                      Image.network(
                        company.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                                alpha: company.imageUrl != null ? 0.55 : 0.0),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: Text(
                          company.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: company.imageUrl != null
                                ? Colors.white
                                : (isSelected
                                    ? _travelAccentDark
                                    : const Color(0xFF0F172A)),
                            shadows: company.imageUrl != null
                                ? const [Shadow(blurRadius: 4, color: Colors.black54)]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: _travelAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 12, color: Colors.white),
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
