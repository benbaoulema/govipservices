import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';

enum _TripStep {
  departure,
  arrival,
  seats,
  price,
  date,
  time,
  stops,
  driver,
  vehicle,
  comfort,
  review,
}

class _RoutePoint {
  const _RoutePoint({
    required this.address,
    this.lat,
    this.lng,
  });

  final String address;
  final double? lat;
  final double? lng;
}

class _IntermediateStop {
  const _IntermediateStop({
    required this.id,
    required this.address,
    required this.estimatedTime,
    required this.priceFromDeparture,
    this.lat,
    this.lng,
    this.selected = true,
    this.source = 'manual',
  });

  final String id;
  final String address;
  final String estimatedTime;
  final double priceFromDeparture;
  final double? lat;
  final double? lng;
  final bool selected;
  final String source;

  _IntermediateStop copyWith({
    String? id,
    String? address,
    String? estimatedTime,
    double? priceFromDeparture,
    double? lat,
    double? lng,
    bool? selected,
    String? source,
  }) {
    return _IntermediateStop(
      id: id ?? this.id,
      address: address ?? this.address,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      priceFromDeparture: priceFromDeparture ?? this.priceFromDeparture,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      selected: selected ?? this.selected,
      source: source ?? this.source,
    );
  }
}

class _PublishedTrip {
  const _PublishedTrip({
    required this.id,
    required this.trackNum,
    required this.title,
    required this.selectedStopsCount,
  });

  final String id;
  final String trackNum;
  final String title;
  final int selectedStopsCount;
}

class AddTripPage extends StatefulWidget {
  const AddTripPage({super.key});

  @override
  State<AddTripPage> createState() => _AddTripPageState();
}

class _AddTripPageState extends State<AddTripPage> {
  static const String _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const LatLng _defaultMapCenter = LatLng(5.3600, -4.0083);
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  static const List<_TripStep> _steps = [
    _TripStep.departure,
    _TripStep.arrival,
    _TripStep.seats,
    _TripStep.price,
    _TripStep.date,
    _TripStep.time,
    _TripStep.stops,
    _TripStep.driver,
    _TripStep.vehicle,
    _TripStep.comfort,
    _TripStep.review,
  ];

  final TextEditingController _departureController = TextEditingController();
  final TextEditingController _arrivalController = TextEditingController();
  final TextEditingController _seatsController = TextEditingController(text: '3');
  final TextEditingController _priceController = TextEditingController(text: '0');
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _manualStopAddressController = TextEditingController();
  final TextEditingController _manualStopPriceController = TextEditingController(text: '0');
  final FocusNode _departureFocusNode = FocusNode();
  final FocusNode _arrivalFocusNode = FocusNode();
  final FocusNode _seatsFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  final FocusNode _manualStopFocusNode = FocusNode();
  final FocusNode _driverFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _notesFocusNode = FocusNode();

  DateTime? _departureDate;
  TimeOfDay? _departureTime;
  TimeOfDay? _manualStopTime;
  _RoutePoint _departurePoint = const _RoutePoint(address: '');
  _RoutePoint _arrivalPoint = const _RoutePoint(address: '');
  _RoutePoint? _manualStopPoint;

  int _stepIndex = 0;
  bool _isForwardTransition = true;
  bool _isBus = false;
  bool _hasLuggageSpace = true;
  bool _allowsPets = false;
  String _currency = 'XOF';
  String _tripFrequency = 'none';
  bool _isPublishing = false;
  bool _isResolvingCurrentLocation = false;
  _PublishedTrip? _submittedTrip;

  final List<_IntermediateStop> _intermediateStops = <_IntermediateStop>[];

  bool get _isLastStep => _stepIndex == _steps.length - 1;
  int get _seatCount => int.tryParse(_seatsController.text.trim()) ?? 3;

  String get _tripTitle {
    final String from = _departureController.text.trim();
    final String to = _arrivalController.text.trim();
    if (from.isEmpty && to.isEmpty) return 'Nouveau trajet';
    if (from.isEmpty) return 'Vers $to';
    if (to.isEmpty) return 'Depuis $from';
    return '$from -> $to';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestStepFocus());
  }

  LatLng? get _departureLatLng {
    if (_departurePoint.lat == null || _departurePoint.lng == null) return null;
    return LatLng(_departurePoint.lat!, _departurePoint.lng!);
  }

  LatLng? get _arrivalLatLng {
    if (_arrivalPoint.lat == null || _arrivalPoint.lng == null) return null;
    return LatLng(_arrivalPoint.lat!, _arrivalPoint.lng!);
  }

  LatLng get _mapCenter {
    final LatLng? departure = _departureLatLng;
    final LatLng? arrival = _arrivalLatLng;
    if (departure != null && arrival != null) {
      return LatLng(
        (departure.latitude + arrival.latitude) / 2,
        (departure.longitude + arrival.longitude) / 2,
      );
    }
    return departure ?? arrival ?? _defaultMapCenter;
  }

  Set<Marker> get _mapMarkers {
    final Set<Marker> markers = <Marker>{};
    final LatLng? departure = _departureLatLng;
    final LatLng? arrival = _arrivalLatLng;

    if (departure != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('departure'),
          position: departure,
          infoWindow: InfoWindow(title: 'Depart', snippet: _departurePoint.address),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }
    if (arrival != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('arrival'),
          position: arrival,
          infoWindow: InfoWindow(title: 'Arrivee', snippet: _arrivalPoint.address),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> get _mapPolylines {
    final LatLng? departure = _departureLatLng;
    final LatLng? arrival = _arrivalLatLng;
    if (departure == null || arrival == null) return <Polyline>{};

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('trip_line'),
        points: <LatLng>[departure, arrival],
        color: const Color(0xFF0A7B4F),
        width: 5,
      ),
    };
  }

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    _seatsController.dispose();
    _priceController.dispose();
    _driverController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _notesController.dispose();
    _manualStopAddressController.dispose();
    _manualStopPriceController.dispose();
    _departureFocusNode.dispose();
    _arrivalFocusNode.dispose();
    _seatsFocusNode.dispose();
    _priceFocusNode.dispose();
    _manualStopFocusNode.dispose();
    _driverFocusNode.dispose();
    _phoneFocusNode.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  bool _validateCurrentStep() {
    switch (_steps[_stepIndex]) {
      case _TripStep.departure:
        return _departureController.text.trim().length >= 5;
      case _TripStep.arrival:
        return _arrivalController.text.trim().length >= 5;
      case _TripStep.seats:
        final int? seats = int.tryParse(_seatsController.text.trim());
        return seats != null && seats > 0;
      case _TripStep.price:
        final double? price = double.tryParse(_priceController.text.trim());
        return price != null && price >= 0;
      case _TripStep.date:
        return _departureDate != null;
      case _TripStep.time:
        return _departureTime != null;
      case _TripStep.stops:
      case _TripStep.review:
        return true;
      case _TripStep.driver:
        return _driverController.text.trim().length >= 2;
      case _TripStep.vehicle:
        return _phoneController.text.trim().length >= 6 && _vehicleController.text.trim().length >= 2;
      case _TripStep.comfort:
        return _notesController.text.trim().length <= 500;
    }
  }

  void _goNext() {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez completer les informations requises pour continuer.')),
      );
      return;
    }
    _setStepIndex((_stepIndex + 1).clamp(0, _steps.length - 1), isForward: true);
  }

  void _goBack() {
    _setStepIndex((_stepIndex - 1).clamp(0, _steps.length - 1), isForward: false);
  }

  void _setStepIndex(int nextIndex, {required bool isForward}) {
    if (nextIndex == _stepIndex) return;
    setState(() {
      _isForwardTransition = isForward;
      _stepIndex = nextIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestStepFocus();
      _handleStepAutoActions();
    });
  }

  void _handleStepAutoActions() {
    if (!mounted) return;
    final _TripStep step = _steps[_stepIndex];
    if (step == _TripStep.date && _departureDate == null) {
      Future<void>.delayed(const Duration(milliseconds: 120), _selectDate);
    }
  }

  FocusNode? _focusNodeForStep(_TripStep step) {
    switch (step) {
      case _TripStep.departure:
        return _departureFocusNode;
      case _TripStep.arrival:
        return _arrivalFocusNode;
      case _TripStep.seats:
        return _seatsFocusNode;
      case _TripStep.price:
        return _priceFocusNode;
      case _TripStep.date:
      case _TripStep.time:
      case _TripStep.review:
        return null;
      case _TripStep.stops:
        return _manualStopFocusNode;
      case _TripStep.driver:
        return _driverFocusNode;
      case _TripStep.vehicle:
        return _phoneFocusNode;
      case _TripStep.comfort:
        return _notesFocusNode;
    }
  }

  void _requestStepFocus() {
    final FocusNode? node = _focusNodeForStep(_steps[_stepIndex]);
    if (node == null || !mounted) return;
    FocusScope.of(context).requestFocus(node);
  }

  void _decrementSeats() {
    final int next = (_seatCount - 1).clamp(1, 99);
    setState(() {
      _seatsController.text = next.toString();
      _seatsController.selection = TextSelection.collapsed(offset: _seatsController.text.length);
    });
  }

  void _incrementSeats() {
    final int next = (_seatCount + 1).clamp(1, 99);
    setState(() {
      _seatsController.text = next.toString();
      _seatsController.selection = TextSelection.collapsed(offset: _seatsController.text.length);
    });
  }

  InputDecoration _clearableDecoration({
    required String labelText,
    String? hintText,
    required TextEditingController controller,
    required VoidCallback onCleared,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: controller.text.trim().isNotEmpty
          ? IconButton(
              tooltip: 'Effacer',
              onPressed: onCleared,
              icon: const Icon(Icons.close_rounded),
            )
          : null,
    );
  }

  void _autoAdvanceFromDeparture() {
    if (_stepIndex != 0) return;
    final String currentDeparture = _departureController.text.trim();
    if (currentDeparture.length < 5) return;
    _setStepIndex(1, isForward: true);
  }

  void _autoAdvanceFromArrival() {
    if (_stepIndex != 1) return;
    final String currentArrival = _arrivalController.text.trim();
    if (currentArrival.length < 5) return;
    _setStepIndex(2, isForward: true);
  }

  Future<void> _useCurrentLocationForDeparture() async {
    if (_isResolvingCurrentLocation) return;
    setState(() {
      _isResolvingCurrentLocation = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activez la localisation pour utiliser votre position actuelle.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission de localisation refusee.')),
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      String resolvedAddress =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final Placemark p = placemarks.first;
          final List<String> parts = <String>[
            if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
            if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
            if ((p.country ?? '').trim().isNotEmpty) p.country!.trim(),
          ];
          if (parts.isNotEmpty) {
            resolvedAddress = parts.join(', ');
          }
        }
      } catch (_) {
        // Keep coordinate fallback if reverse geocoding fails.
      }

      _departureController.text = resolvedAddress;
      _departureController.selection = TextSelection.collapsed(offset: resolvedAddress.length);

      if (!mounted) return;
      setState(() {
        _departurePoint = _RoutePoint(
          address: resolvedAddress,
          lat: position.latitude,
          lng: position.longitude,
        );
      });
      _autoAdvanceFromDeparture();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de recuperer votre position actuelle.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isResolvingCurrentLocation = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = _departureDate ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      locale: const Locale('fr', 'FR'),
    );
    if (picked == null) return;
    setState(() {
      _departureDate = picked;
    });
  }

  Future<void> _selectTime({required bool manualStop}) async {
    final TimeOfDay initialTime = manualStop
        ? (_manualStopTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_departureTime ?? const TimeOfDay(hour: 8, minute: 0));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Localizations.override(
          context: context,
          locale: const Locale('fr', 'FR'),
          child: child,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (manualStop) {
        _manualStopTime = picked;
      } else {
        _departureTime = picked;
      }
    });
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatTime(TimeOfDay? value) {
    if (value == null) return '--:--';
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _addManualStop() {
    final String address = _manualStopAddressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez saisir une adresse darret.')),
      );
      return;
    }
    final double price = double.tryParse(_manualStopPriceController.text.trim()) ?? 0;

    setState(() {
      _intermediateStops.add(
        _IntermediateStop(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          address: address,
          estimatedTime: _formatTime(_manualStopTime),
          priceFromDeparture: price < 0 ? 0 : price,
          lat: _manualStopPoint?.lat,
          lng: _manualStopPoint?.lng,
        ),
      );
      _manualStopAddressController.clear();
      _manualStopPriceController.text = '0';
      _manualStopTime = null;
      _manualStopPoint = null;
    });
  }

  void _removeStop(String id) {
    setState(() {
      _intermediateStops.removeWhere((stop) => stop.id == id);
    });
  }

  void _toggleStopSelection(String id) {
    setState(() {
      final int idx = _intermediateStops.indexWhere((s) => s.id == id);
      if (idx < 0) return;
      final _IntermediateStop current = _intermediateStops[idx];
      _intermediateStops[idx] = current.copyWith(selected: !current.selected);
    });
  }

  Future<void> _publishTrip() async {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Certains champs sont invalides.')),
      );
      return;
    }
    setState(() {
      _isPublishing = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final int selectedStopsCount = _intermediateStops.where((stop) => stop.selected).length;
    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final String trackNum = 'TR-${id.substring(id.length - 6)}';

    setState(() {
      _submittedTrip = _PublishedTrip(
        id: id,
        trackNum: trackNum,
        title: _tripTitle,
        selectedStopsCount: selectedStopsCount,
      );
      _isPublishing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trajet publie avec succes.')),
    );
  }

  Widget _buildStepContent() {
    switch (_steps[_stepIndex]) {
      case _TripStep.departure:
        return _TripFieldSection(
          title: "D'ou partez-vous ?",
          subtitle: 'Choisissez votre depart ou utilisez votre position actuelle.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AddressAutocompleteField(
                controller: _departureController,
                apiKey: _googleMapsApiKey,
                labelText: 'Adresse de depart',
                hintText: 'Ex: Cocody, Abidjan',
                focusNode: _departureFocusNode,
                onChanged: (value) {
                  setState(() {
                    _departurePoint = _RoutePoint(address: value);
                  });
                },
                onSuggestionSelected: (_) => _autoAdvanceFromDeparture(),
                onPlaceResolved: (PlaceDetailsResult place) {
                  setState(() {
                    _departurePoint = _RoutePoint(
                      address: place.address,
                      lat: place.lat,
                      lng: place.lng,
                    );
                  });
                  _autoAdvanceFromDeparture();
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isResolvingCurrentLocation ? null : _useCurrentLocationForDeparture,
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(
                    _isResolvingCurrentLocation
                        ? 'Localisation en cours...'
                        : 'Utiliser ma position actuelle',
                  ),
                ),
              ),
            ],
          ),
        );
      case _TripStep.arrival:
        return _TripFieldSection(
          title: 'Ou allez-vous ?',
          subtitle: 'Entrez votre destination principale.',
          child: AddressAutocompleteField(
            controller: _arrivalController,
            apiKey: _googleMapsApiKey,
            labelText: 'Adresse d arrivee',
            hintText: 'Ex: Plateau, Abidjan',
            focusNode: _arrivalFocusNode,
            onChanged: (value) {
              setState(() {
                _arrivalPoint = _RoutePoint(address: value);
              });
            },
            onSuggestionSelected: (_) => _autoAdvanceFromArrival(),
            onPlaceResolved: (PlaceDetailsResult place) {
              setState(() {
                _arrivalPoint = _RoutePoint(
                  address: place.address,
                  lat: place.lat,
                  lng: place.lng,
                );
              });
              _autoAdvanceFromArrival();
            },
          ),
        );
      case _TripStep.seats:
        return _TripFieldSection(
          title: 'Combien de places ?',
          subtitle: 'Ajustez rapidement le nombre de places disponibles.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SeatsInputCard(
                seatsController: _seatsController,
                seatsFocusNode: _seatsFocusNode,
                currentSeats: _seatCount,
                onIncrement: _incrementSeats,
                onDecrement: _decrementSeats,
                onManualChanged: (_) => setState(() {}),
              ),
            ],
          ),
        );
      case _TripStep.price:
        return _TripFieldSection(
          title: 'Prix par place',
          subtitle: 'Definissez le tarif par passager.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'XOF', label: Text('CFA')),
                  ButtonSegment<String>(value: 'EUR', label: Text('Euro')),
                ],
                selected: <String>{_currency},
                onSelectionChanged: (selection) {
                  setState(() {
                    _currency = selection.first;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceController,
                focusNode: _priceFocusNode,
                keyboardType: TextInputType.number,
                decoration: _clearableDecoration(
                  labelText: 'Prix par place ($_currency)',
                  controller: _priceController,
                  onCleared: () {
                    setState(() {
                      _priceController.clear();
                    });
                    _priceFocusNode.requestFocus();
                  },
                ),
              ),
            ],
          ),
        );
      case _TripStep.date:
        return _TripFieldSection(
          title: 'Choisissez la date',
          subtitle: 'Selectionnez le jour de depart du trajet.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _departureDate == null ? 'Choisir la date' : _formatDate(_departureDate),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case _TripStep.time:
        return _TripFieldSection(
          title: 'Choisissez l heure',
          subtitle: 'Selectionnez l heure de depart du trajet.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectTime(manualStop: false),
                      icon: const Icon(Icons.access_time_outlined),
                      label: Text(
                        _departureTime == null ? 'Choisir l heure' : _formatTime(_departureTime),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case _TripStep.stops:
        return _TripFieldSection(
          title: 'Arrets intermediaires',
          subtitle: 'Ajoutez des arrets optionnels et ajustez leur prix.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AddressAutocompleteField(
                controller: _manualStopAddressController,
                apiKey: _googleMapsApiKey,
                labelText: 'Adresse arret',
                hintText: 'Ex: Gare, rond-point, commune',
                focusNode: _manualStopFocusNode,
                onChanged: (value) {
                  setState(() {
                    _manualStopPoint = _RoutePoint(address: value);
                  });
                },
                onPlaceResolved: (PlaceDetailsResult place) {
                  setState(() {
                    _manualStopPoint = _RoutePoint(
                      address: place.address,
                      lat: place.lat,
                      lng: place.lng,
                    );
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectTime(manualStop: true),
                      icon: const Icon(Icons.access_time_outlined),
                      label: Text(
                        _manualStopTime == null ? 'Heure estimee' : _formatTime(_manualStopTime),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _manualStopPriceController,
                      keyboardType: TextInputType.number,
                      decoration: _clearableDecoration(
                        labelText: 'Prix ($_currency)',
                        controller: _manualStopPriceController,
                        onCleared: () {
                          setState(() {
                            _manualStopPriceController.clear();
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addManualStop,
                  child: const Text('Ajouter cet arret'),
                ),
              ),
              const SizedBox(height: 14),
              if (_intermediateStops.isEmpty)
                const _InlineInfo(text: 'Aucun arret ajoute pour le moment.')
              else
                ..._intermediateStops.map(
                  (stop) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(stop.address),
                      subtitle: Text(
                        '${stop.estimatedTime} - ${stop.priceFromDeparture.toStringAsFixed(0)} $_currency (${stop.source})',
                      ),
                      leading: Checkbox(
                        value: stop.selected,
                        onChanged: (_) => _toggleStopSelection(stop.id),
                      ),
                      trailing: IconButton(
                        onPressed: () => _removeStop(stop.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      case _TripStep.driver:
        return _TripFieldSection(
          title: 'Infos conducteur',
          subtitle: 'Nom affiche pour les voyageurs.',
          child: TextFormField(
            controller: _driverController,
            focusNode: _driverFocusNode,
            decoration: _clearableDecoration(
              labelText: 'Nom du conducteur',
              hintText: 'Ex: Koffi',
              controller: _driverController,
              onCleared: () {
                setState(() {
                  _driverController.clear();
                });
                _driverFocusNode.requestFocus();
              },
            ),
          ),
        );
      case _TripStep.vehicle:
        return _TripFieldSection(
          title: 'Contact et vehicule',
          subtitle: 'Precisez votre numero et le vehicule utilise.',
          child: Column(
            children: [
              TextFormField(
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                decoration: _clearableDecoration(
                  labelText: 'Telephone',
                  hintText: '+225 07 00 00 00 00',
                  controller: _phoneController,
                  onCleared: () {
                    setState(() {
                      _phoneController.clear();
                    });
                    _phoneFocusNode.requestFocus();
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vehicleController,
                decoration: _clearableDecoration(
                  labelText: 'Vehicule',
                  hintText: 'Toyota Corolla - Gris',
                  controller: _vehicleController,
                  onCleared: () {
                    setState(() {
                      _vehicleController.clear();
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _isBus,
                onChanged: (value) {
                  setState(() {
                    _isBus = value ?? false;
                  });
                },
                title: const Text('Transporteur pro'),
                subtitle: const Text('Activez pour un service professionnel.'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _tripFrequency,
                decoration: const InputDecoration(labelText: 'Frequence'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Ponctuel')),
                  DropdownMenuItem(value: 'daily', child: Text('Quotidien')),
                  DropdownMenuItem(value: 'weekly', child: Text('Hebdomadaire')),
                  DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _tripFrequency = value;
                  });
                },
              ),
            ],
          ),
        );
      case _TripStep.comfort:
        return _TripFieldSection(
          title: 'Confort du trajet',
          subtitle: 'Definissez les preferences de voyage.',
          child: Column(
            children: [
              CheckboxListTile(
                value: _hasLuggageSpace,
                onChanged: (value) {
                  setState(() {
                    _hasLuggageSpace = value ?? true;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Bagages autorises'),
              ),
              CheckboxListTile(
                value: _allowsPets,
                onChanged: (value) {
                  setState(() {
                    _allowsPets = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                title: const Text('Animaux acceptes'),
              ),
              TextFormField(
                controller: _notesController,
                focusNode: _notesFocusNode,
                maxLines: 4,
                maxLength: 500,
                decoration: _clearableDecoration(
                  labelText: 'Notes',
                  hintText: 'Point de rendez-vous, climatisation, etc.',
                  controller: _notesController,
                  onCleared: () {
                    setState(() {
                      _notesController.clear();
                    });
                    _notesFocusNode.requestFocus();
                  },
                ),
              ),
            ],
          ),
        );
      case _TripStep.review:
        final String frequencyLabel = switch (_tripFrequency) {
          'daily' => 'Quotidien',
          'weekly' => 'Hebdomadaire',
          'monthly' => 'Mensuel',
          _ => 'Ponctuel',
        };

        return _TripFieldSection(
          title: 'Verification finale',
          subtitle: 'Validez les informations avant publication.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow(label: 'Trajet', value: _tripTitle),
              _SummaryRow(
                label: 'Depart',
                value: '${_formatDate(_departureDate)} - ${_formatTime(_departureTime)}',
              ),
              _SummaryRow(
                label: 'Places / Prix',
                value: '${_seatsController.text.trim()} - ${_priceController.text.trim()} $_currency',
              ),
              _SummaryRow(
                label: 'Conducteur',
                value: '${_driverController.text.trim()} (${_phoneController.text.trim()})',
              ),
              _SummaryRow(
                label: 'Vehicule',
                value: '${_vehicleController.text.trim()} - ${_isBus ? 'Transporteur pro' : 'Vehicule leger'}',
              ),
              _SummaryRow(label: 'Frequence', value: frequencyLabel),
              _SummaryRow(
                label: 'Arrets selectionnes',
                value: _intermediateStops.where((stop) => stop.selected).length.toString(),
              ),
            ],
          ),
        );
    }
  }

  String _stepIllustrationAsset(_TripStep step) {
    switch (step) {
      case _TripStep.departure:
        return 'assets/illustrations/departure.svg';
      case _TripStep.arrival:
        return 'assets/illustrations/arrival.svg';
      case _TripStep.seats:
      case _TripStep.price:
        return 'assets/illustrations/seats_price.svg';
      case _TripStep.date:
      case _TripStep.time:
        return 'assets/illustrations/schedule.svg';
      case _TripStep.stops:
        return 'assets/illustrations/stops.svg';
      case _TripStep.driver:
        return 'assets/illustrations/driver.svg';
      case _TripStep.vehicle:
        return 'assets/illustrations/vehicle.svg';
      case _TripStep.comfort:
        return 'assets/illustrations/comfort.svg';
      case _TripStep.review:
        return 'assets/illustrations/review.svg';
    }
  }

  Widget _buildRouteMapCard() {
    final bool hasAnyPoint = _departureLatLng != null || _arrivalLatLng != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7EFE2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAnyPoint
          ? SizedBox(
              height: 196,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 11.4),
                markers: _mapMarkers,
                polylines: _mapPolylines,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
              ),
            )
          : Container(
              height: 150,
              color: const Color(0xFFEAF8F0),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD3F0DE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.map_outlined, color: Color(0xFF0A7B4F)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'La carte apparaitra ici des que vous choisissez le depart ou l arrivee.',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Color(0xFF14532D)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un trajet'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        final Animation<Offset> slide = Tween<Offset>(
                          begin: Offset(_isForwardTransition ? 0.18 : -0.18, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return SlideTransition(
                          position: slide,
                          child: FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<int>(_stepIndex),
                        child: _buildStepContent(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          '${_departurePoint.lat ?? 0}-${_departurePoint.lng ?? 0}-${_arrivalPoint.lat ?? 0}-${_arrivalPoint.lng ?? 0}',
                        ),
                        child: _buildRouteMapCard(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _StepIllustration(
                        key: ValueKey<_TripStep>(_steps[_stepIndex]),
                        assetPath: _stepIllustrationAsset(_steps[_stepIndex]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_submittedTrip != null) ...[
                      const SizedBox(height: 14),
                      Card(
                        color: const Color(0xFFEFFAF2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.green.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trajet publie',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('ID: ${_submittedTrip!.id}'),
                              Text('Track: ${_submittedTrip!.trackNum}'),
                              Text(_submittedTrip!.title),
                              Text('Arrets: ${_submittedTrip!.selectedStopsCount}'),
                            ],
                          ),
                        ),
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
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.98),
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              if (_stepIndex > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _goBack,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Retour'),
                  ),
                ),
              if (_stepIndex > 0) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isPublishing
                      ? null
                      : _isLastStep
                          ? _publishTrip
                          : _goNext,
                  icon: Icon(_isLastStep ? Icons.check_circle_outline : Icons.chevron_right),
                  label: Text(_isLastStep ? (_isPublishing ? 'Publication...' : 'Publier le trajet') : 'Continuer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripFieldSection extends StatelessWidget {
  const _TripFieldSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }
}

class _StepIllustration extends StatelessWidget {
  const _StepIllustration({
    required this.assetPath,
    super.key,
  });

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCF5E6)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SvgPicture.asset(
        assetPath,
        fit: BoxFit.cover,
        height: 160,
      ),
    );
  }
}

class _SeatsInputCard extends StatelessWidget {
  const _SeatsInputCard({
    required this.seatsController,
    required this.seatsFocusNode,
    required this.currentSeats,
    required this.onIncrement,
    required this.onDecrement,
    required this.onManualChanged,
  });

  final TextEditingController seatsController;
  final FocusNode seatsFocusNode;
  final int currentSeats;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<String> onManualChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7EFE2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nombre de places',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF14532D),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SeatActionButton(
                icon: Icons.remove,
                onTap: onDecrement,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCAEBD9)),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Text(
                        '$currentSeats',
                        key: ValueKey<int>(currentSeats),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0A7B4F),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SeatActionButton(
                icon: Icons.add,
                onTap: onIncrement,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: seatsController,
            focusNode: seatsFocusNode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Saisie manuelle',
              hintText: 'Ex: 3',
              suffixIcon: seatsController.text.trim().isNotEmpty
                  ? IconButton(
                      tooltip: 'Effacer',
                      onPressed: () {
                        seatsController.clear();
                        onManualChanged('');
                        seatsFocusNode.requestFocus();
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
            ),
            onChanged: onManualChanged,
          ),
        ],
      ),
    );
  }
}

class _SeatActionButton extends StatelessWidget {
  const _SeatActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A7B4F),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          width: 52,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
