import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';

enum _BookingDateChoice { today, tomorrow, custom }

class BookTripPage extends StatefulWidget {
  const BookTripPage({super.key});

  @override
  State<BookTripPage> createState() => _BookTripPageState();
}

class _BookTripPageState extends State<BookTripPage> {
  static const String _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

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
    _showMessage('Depart renseigne depuis votre position.');
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
          'Autorisez la localisation pour pre-remplir votre depart.',
          icon: Icons.lock_outline,
        );
        return;
      }

      final String? resolvedAddress = await _resolveCurrentLocationAddress();
      if (resolvedAddress == null) {
        _showMessage(
          'Impossible de recuperer votre position actuelle.',
          icon: Icons.error_outline,
        );
        return;
      }
      await _applyCurrentLocationAsDeparture(resolvedAddress);
    } catch (_) {
      _showMessage(
        'Impossible de recuperer votre position actuelle.',
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
      _showMessage('Renseignez un depart valide.', icon: Icons.edit_location_alt_outlined);
      await _goToStep(0);
      return;
    }

    if (arrival.length < 3) {
      _showMessage('Renseignez une arrivee valide.', icon: Icons.pin_drop_outlined);
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
        'Erreur lors de la recherche des trajets. Verifiez votre connexion.',
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
                              'Aucun trajet trouve pour ce jour.\nEssayez une autre arrivee ou une autre date.',
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
                          ),
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
      backgroundColor: const Color(0xFFF6F8FF),
      appBar: AppBar(
        title: const Text('Reserver'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF0FF),
              Color(0xFFF6F8FF),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
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
                        ),
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
                        child: _StepCard(
                          icon: Icons.trip_origin_rounded,
                          title: 'Depart',
                          subtitle: '',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AddressAutocompleteField(
                                controller: _departureController,
                                focusNode: _departureFocusNode,
                                labelText: 'Adresse de depart',
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
                      ),
                      _buildAnimatedStepCard(
                        index: 1,
                        child: _StepCard(
                          icon: Icons.flag_circle_outlined,
                          title: 'Arrivee',
                          subtitle: '',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AddressAutocompleteField(
                                controller: _arrivalController,
                                focusNode: _arrivalFocusNode,
                                labelText: 'Adresse d arrivee',
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
                                'Date choisie: ${_formatSelectedDateLabel()}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF5B647A),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
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
                      backgroundColor: const Color(0xFF0B5FFF),
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
                          : (_currentStep == 0 ? 'Continuer vers arrivee' : 'Rechercher des trajets'),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _lastResults.isEmpty
                      ? const SizedBox(height: 0)
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '${_lastResults.length} resultat(s) trouves lors de la derniere recherche.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF5B647A),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
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
          colors: [Color(0xFF0B5FFF), Color(0xFF1F8BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B5FFF).withOpacity(0.26),
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
            '1. Depart  2. Arrivee + date',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProgressStep(
                  label: 'Depart',
                  selected: currentStep == 0,
                  onTap: () => onStepTap(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProgressStep(
                  label: 'Arrivee',
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
              color: selected ? const Color(0xFF0B5FFF) : Colors.white,
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
        border: Border.all(color: const Color(0xFFE8EDFB)),
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
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: const Color(0xFF0B5FFF)),
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
      color: selected ? const Color(0xFF0B5FFF) : const Color(0xFFF1F4FD),
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
              color: selected ? Colors.white : const Color(0xFF19233E),
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
    return name.isEmpty ? 'Conducteur non renseigne' : name;
  }

  String _vehicleLabel() {
    final String vehicle = (trip.raw['vehicleModel'] ?? '').toString().trim();
    return vehicle.isEmpty ? 'Vehicule non renseigne' : vehicle;
  }

  @override
  Widget build(BuildContext context) {
    final String departureTime =
        (trip.departureTime ?? '').trim().isEmpty ? '--:--' : (trip.departureTime ?? '').trim();
    final String arrivalTime = _arrivalTimeLabel();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4EAFB)),
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
                      SizedBox(
                        width: 54,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              departureTime,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F1A35),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              arrivalTime,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F1A35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 16,
                        child: Column(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF0B5FFF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 20,
                              color: const Color(0xFFCAD6EE),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF8FA5CF),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip.departurePlace,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A2747),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              trip.arrivalPlace,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A2747),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _priceLabel(),
                    style: const TextStyle(
                      color: Color(0xFF0B5FFF),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE4EAFB)),
            const SizedBox(height: 10),
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
                      fontWeight: FontWeight.w600,
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
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF223253),
                    ),
                  ),
                ),
                if (trip.seats != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${trip.seats} pl.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5B6C90),
                    ),
                  ),
                ],
              ],
            ),
                if (trip.trackNum != null && trip.trackNum!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ref: ${trip.trackNum}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5B647A),
                          fontWeight: FontWeight.w600,
                        ),
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
