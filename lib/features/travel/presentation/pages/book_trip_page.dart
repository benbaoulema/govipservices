import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

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
  final TextEditingController _departureController = TextEditingController();
  final TextEditingController _arrivalController = TextEditingController();
  final FocusNode _departureFocusNode = FocusNode();
  final FocusNode _arrivalFocusNode = FocusNode();
  final PageController _pageController = PageController();

  int _currentStep = 0;
  bool _isFetchingLocation = false;
  bool _isSearchingTrips = false;
  bool _isAutoAdvancingToArrival = false;
  String? _cachedCurrentLocationAddress;
  Future<void>? _locationWarmupFuture;
  _BookingDateChoice _dateChoice = _BookingDateChoice.today;
  DateTime? _customDate;
  List<TripSearchResult> _lastResults = const <TripSearchResult>[];

  @override
  void initState() {
    super.initState();
    _locationWarmupFuture = _warmupCurrentLocationAddress();
  }

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    _departureFocusNode.dispose();
    _arrivalFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
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

  Future<void> _goToStep(int step) async {
    _departureFocusNode.unfocus();
    _arrivalFocusNode.unfocus();
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubicEmphasized,
    );
    if (!mounted) return;
    setState(() {
      _currentStep = step;
    });
    if (step == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _arrivalFocusNode.requestFocus();
      });
    }
  }

  void _handleDepartureChanged(String _) {
    setState(() {});
  }

  Future<void> _handleDepartureConfirmed() async {
    final bool isDepartureValid = _departureController.text.trim().length >= 3;
    if (!isDepartureValid || _currentStep != 0) return;
    await _autoAdvanceToArrival();
  }

  Future<void> _autoAdvanceToArrival() async {
    if (_isAutoAdvancingToArrival) return;
    _isAutoAdvancingToArrival = true;
    try {
      await _goToStep(1);
      if (!mounted) return;
      _arrivalFocusNode.requestFocus();
    } finally {
      _isAutoAdvancingToArrival = false;
    }
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

  Future<void> _warmupCurrentLocationAddress() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      final String? resolvedAddress = await _resolveCurrentLocationAddress();
      if (resolvedAddress == null || !mounted) return;
      _cachedCurrentLocationAddress = resolvedAddress;
    } catch (_) {
      // Silent warmup: best effort only.
    }
  }

  Future<String?> _resolveCurrentLocationAddress() async {
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final List<Placemark> placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );

    final Placemark? first = placemarks.isNotEmpty ? placemarks.first : null;
    final String address = <String?>[
      first?.street,
      first?.subLocality,
      first?.locality,
      first?.country,
    ].whereType<String>().map((part) => part.trim()).where((part) => part.isNotEmpty).join(', ');

    return address.trim().isEmpty
        ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'
        : address;
  }

  Future<void> _applyCurrentLocationAsDeparture(String resolvedAddress) async {
    _departureController.text = resolvedAddress;
    _departureController.selection = TextSelection.collapsed(offset: resolvedAddress.length);
    _cachedCurrentLocationAddress = resolvedAddress;
    _showMessage('D\u00E9part renseign\u00E9 depuis votre position.');
    await _handleDepartureConfirmed();
  }

  Future<void> _useCurrentLocationForDeparture() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true;
    });

    try {
      if (_cachedCurrentLocationAddress == null && _locationWarmupFuture != null) {
        await _locationWarmupFuture;
      }
      if (_cachedCurrentLocationAddress != null) {
        await _applyCurrentLocationAsDeparture(_cachedCurrentLocationAddress!);
        return;
      }

      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(
          'Activez la localisation pour utiliser votre position actuelle.',
          icon: Icons.location_off_outlined,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showMessage(
          'Autorisez la localisation pour pr\u00E9-remplir votre d\u00E9part.',
          icon: Icons.lock_outline,
        );
        return;
      }

      final String? resolvedAddress = await _resolveCurrentLocationAddress();
      if (resolvedAddress == null) {
        _showMessage(
          'Impossible de r\u00E9cup\u00E9rer votre position actuelle.',
          icon: Icons.error_outline,
        );
        return;
      }
      await _applyCurrentLocationAsDeparture(resolvedAddress);
    } catch (_) {
      _showMessage(
        'Impossible de r\u00E9cup\u00E9rer votre position actuelle.',
        icon: Icons.error_outline,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isFetchingLocation = false;
      });
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

  Future<void> _submitSearch() async {
    final String departure = _departureController.text.trim();
    final String arrival = _arrivalController.text.trim();

    if (departure.length < 3) {
      _showMessage('Renseignez un départ valide.', icon: Icons.edit_location_alt_outlined);
      await _goToStep(0);
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
      final List<TripSearchResult> results = await _travelRepository.searchAvailableTrips(
        departureQuery: departure,
        arrivalQuery: arrival,
        departureDate: _selectedDate,
      );
      if (!mounted) return;
      setState(() {
        _lastResults = results;
      });
      await _showSearchResultsBottomSheet(results);
    } catch (_) {
      _showMessage(
        'Erreur lors de la recherche des trajets. V\u00E9rifiez votre connexion.',
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
                              'Aucun trajet trouv\u00E9 pour ce jour.\nEssayez une autre arrivée ou une autre date.',
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

  String _labelForChoice(_BookingDateChoice choice) {
    switch (choice) {
      case _BookingDateChoice.today:
        return 'Aujourd\'hui';
      case _BookingDateChoice.tomorrow:
        return 'Demain';
      case _BookingDateChoice.custom:
        final DateTime date = _selectedDate;
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    }
  }

  String _formatSelectedDateLabel() {
    final DateTime date = _selectedDate;
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String year = date.year.toString();
    return '$day/$month/$year';
  }

  Widget _animateEntrance(Widget child, {int delayMs = 0}) {
    return child
        .animate()
        .fadeIn(delay: Duration(milliseconds: delayMs), duration: 300.ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _buildAnimatedStepCard({
    required int index,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _pageController,
      child: child,
      builder: (context, animatedChild) {
        double page = _currentStep.toDouble();
        if (_pageController.hasClients) {
          page = _pageController.page ?? _pageController.initialPage.toDouble();
        }
        final double distance = (page - index).abs().clamp(0.0, 1.0);
        final double scale = 1 - (0.06 * distance);
        final double opacity = 1 - (0.35 * distance);
        final double translateY = 18 * distance;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: animatedChild,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: _travelPageBg,
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Réserver'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _travelPageBgAlt,
              _travelPageBg,
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: isKeyboardVisible
                      ? const SizedBox.shrink()
                      : _TopHero(
                          currentStep: _currentStep,
                          onStepTap: (step) {
                            _goToStep(step);
                          },
                        ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.08, end: 0),
                ),
                SizedBox(height: isKeyboardVisible ? 6 : 14),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentStep = index);
                      if (index == 1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _arrivalFocusNode.requestFocus();
                        });
                      }
                    },
                    children: [
                      _buildAnimatedStepCard(
                        index: 0,
                        child: _animateEntrance(
                          _StepCard(
                          icon: Icons.trip_origin_rounded,
                          title: 'D\u00E9part',
                          subtitle: '',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AddressAutocompleteField(
                                controller: _departureController,
                                focusNode: _departureFocusNode,
                                labelText: 'Adresse de d\u00E9part',
                                hintText: 'Ex: Cocody, Abidjan',
                                apiKey: _googleMapsApiKey,
                                onChanged: _handleDepartureChanged,
                                onSuggestionSelected: (_) => _handleDepartureConfirmed(),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isFetchingLocation ? null : _useCurrentLocationForDeparture,
                                  icon: _isFetchingLocation
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.my_location_rounded),
                                  label: Text(
                                    _isFetchingLocation
                                        ? 'Localisation en cours...'
                                        : 'Utiliser ma position',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        delayMs: 40,
                        ),
                      ),
                      _buildAnimatedStepCard(
                        index: 1,
                        child: _animateEntrance(
                          _StepCard(
                          icon: Icons.flag_circle_outlined,
                          title: 'Arriv\u00E9e',
                          subtitle: '',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AddressAutocompleteField(
                                controller: _arrivalController,
                                focusNode: _arrivalFocusNode,
                                labelText: 'Adresse d\'arriv\u00E9e',
                                hintText: 'Ex: Plateau, Abidjan',
                                apiKey: _googleMapsApiKey,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _DateChoiceChip(
                                      label: 'Aujourd\'hui',
                                      selected: _dateChoice == _BookingDateChoice.today,
                                      onTap: () => _selectDateChoice(_BookingDateChoice.today),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DateChoiceChip(
                                      label: 'Demain',
                                      selected: _dateChoice == _BookingDateChoice.tomorrow,
                                      onTap: () => _selectDateChoice(_BookingDateChoice.tomorrow),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DateChoiceChip(
                                      label: _dateChoice == _BookingDateChoice.custom
                                          ? _labelForChoice(_BookingDateChoice.custom)
                                          : 'Choisir',
                                      selected: _dateChoice == _BookingDateChoice.custom,
                                      onTap: () => _selectDateChoice(_BookingDateChoice.custom),
                                    ),
                                  ),
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
                        ),
                        delayMs: 90,
                        ),
                      ),
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_currentStep == 0 ? Icons.arrow_forward_rounded : Icons.search_rounded),
                    label: Text(
                      _isSearchingTrips
                          ? 'Recherche en cours...'
                          : (_currentStep == 0 ? 'Continuer vers arriv\u00E9e' : 'Rechercher des trajets'),
                    ),
                  )
                      .animate(target: _isSearchingTrips ? 1 : 0)
                      .scale(begin: const Offset(1, 1), end: const Offset(0.985, 0.985), duration: 180.ms),
                ).animate().fadeIn(delay: 120.ms, duration: 260.ms).slideY(begin: 0.12, end: 0),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _lastResults.isEmpty
                      ? const SizedBox(height: 0)
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${_lastResults.length} r\u00E9sultat(s) trouv\u00E9s lors de la derni\u00E8re recherche.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5B647A),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.18, end: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopHero extends StatelessWidget {
  const _TopHero({
    required this.currentStep,
    required this.onStepTap,
  });

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
            color: _travelAccent.withOpacity(0.22),
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
            '1. D\u00E9part  2. Arriv\u00E9e + date',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProgressStep(
                  label: 'D\u00E9part',
                  selected: currentStep == 0,
                  onTap: () => onStepTap(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProgressStep(
                  label: 'Arriv\u00E9e',
                  selected: currentStep == 1,
                  onTap: () => onStepTap(1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.white.withOpacity(0.2),
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
  const _StepCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool hasSubtitle = subtitle.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _travelSurfaceBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14387B).withOpacity(0.07),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _travelAccentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: _travelAccentDark),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F1A35),
                    ),
                  ),
                ),
              ],
            ),
            if (hasSubtitle) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5B647A),
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChoiceChip extends StatelessWidget {
  const _DateChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _travelAccent : _travelAccentSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : _travelAccentDark,
              fontWeight: FontWeight.w700,
            ),
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
    return name.isEmpty ? 'Conducteur non renseign\u00E9' : name;
  }

  String _vehicleLabel() {
    final String vehicle = (trip.raw['vehicleModel'] ?? '').toString().trim();
    return vehicle.isEmpty ? 'V\u00E9hicule non renseign\u00E9' : vehicle;
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
                color: _travelAccent.withOpacity(0.10),
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
                              color: Colors.white.withOpacity(0.84),
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
                                        color: _travelAccent.withOpacity(0.35),
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
                              color: _travelAccent.withOpacity(0.24),
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
                    color: Colors.white.withOpacity(0.68),
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
