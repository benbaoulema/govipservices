import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/features/parcels/data/parcel_route_preview_service.dart';
import 'package:govipservices/features/parcels/data/parcel_service_matcher.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_service_match.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';

enum _ShipStep { request, matches, recipient }

class _AddressPoint {
  const _AddressPoint({
    this.address = '',
    this.lat,
    this.lng,
    this.placeId,
  });

  final String address;
  final double? lat;
  final double? lng;
  final String? placeId;

  bool get isComplete =>
      address.trim().isNotEmpty && lat != null && lng != null;

  _AddressPoint copyWith({
    String? address,
    double? lat,
    double? lng,
    String? placeId,
    bool clearCoords = false,
  }) {
    return _AddressPoint(
      address: address ?? this.address,
      lat: clearCoords ? null : lat ?? this.lat,
      lng: clearCoords ? null : lng ?? this.lng,
      placeId: clearCoords ? null : placeId ?? this.placeId,
    );
  }
}

class ShipPackagePage extends StatefulWidget {
  const ShipPackagePage({super.key});

  @override
  State<ShipPackagePage> createState() => _ShipPackagePageState();
}

class _ShipPackagePageState extends State<ShipPackagePage> {
  static const String _googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  final PageController _pageController = PageController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _deliveryController = TextEditingController();
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController =
      TextEditingController();

  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _deliveryFocusNode = FocusNode();
  final FocusNode _recipientNameFocusNode = FocusNode();
  final FocusNode _recipientPhoneFocusNode = FocusNode();
  final ParcelServiceMatcher _parcelServiceMatcher = ParcelServiceMatcher();
  late final ParcelRoutePreviewService _routePreviewService;

  GoogleMapController? _mapController;
  _ShipStep _currentStep = _ShipStep.request;
  _AddressPoint _pickup = const _AddressPoint();
  _AddressPoint _delivery = const _AddressPoint();
  List<LatLng> _routePreviewPoints = const <LatLng>[];
  List<ParcelServiceMatch> _matches = const <ParcelServiceMatch>[];
  ParcelServiceMatch? _selectedMatch;
  bool _hasSearchedMatches = false;
  bool _matchesOverlayHidden = false;
  bool _isFetchingPickupLocation = false;
  bool _isSearchingMatches = false;
  bool _isSubmitting = false;
  int _routeRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _routePreviewService = ParcelRoutePreviewService(apiKey: _googleMapsApiKey);
    _recipientNameController.addListener(_handleRecipientChanged);
    _recipientPhoneController.addListener(_handleRecipientChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocationForPickup();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pickupController.dispose();
    _deliveryController.dispose();
    _recipientNameController
      ..removeListener(_handleRecipientChanged)
      ..dispose();
    _recipientPhoneController
      ..removeListener(_handleRecipientChanged)
      ..dispose();
    _pickupFocusNode.dispose();
    _deliveryFocusNode.dispose();
    _recipientNameFocusNode.dispose();
    _recipientPhoneFocusNode.dispose();
    super.dispose();
  }

  bool get _canContinueFromCurrentStep {
    switch (_currentStep) {
      case _ShipStep.request:
        return _pickup.isComplete && _delivery.isComplete;
      case _ShipStep.matches:
        return _selectedMatch != null && !_isSearchingMatches;
      case _ShipStep.recipient:
        return _recipientNameController.text.trim().isNotEmpty &&
            _recipientPhoneController.text.trim().isNotEmpty &&
            !_isSubmitting;
    }
  }

  int get _currentStepIndex => _ShipStep.values.indexOf(_currentStep);

  void _handleRecipientChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _handleBack() async {
    if (_currentStep == _ShipStep.request) return true;
    _goToStep(_ShipStep.values[_currentStepIndex - 1]);
    return false;
  }

  void _handlePickupTextChanged(String value) {
    setState(() {
      _pickup = _pickup.copyWith(address: value, clearCoords: true);
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
  }

  void _handleDeliveryTextChanged(String value) {
    setState(() {
      _delivery = _delivery.copyWith(address: value, clearCoords: true);
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
  }

  void _applyPickupDetails(PlaceDetailsResult details) {
    setState(() {
      _pickup = _pickup.copyWith(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        placeId: details.placeId,
      );
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
    _refreshRoutePreview();
    _refreshRequestMapViewport();
    _triggerAutoSearchIfReady();
  }

  void _applyDeliveryDetails(PlaceDetailsResult details) {
    setState(() {
      _delivery = _delivery.copyWith(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        placeId: details.placeId,
      );
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
    _refreshRoutePreview();
    _refreshRequestMapViewport();
    _triggerAutoSearchIfReady();
  }

  Future<void> _openDeliverySearchSheet() async {
    _AddressSearchSheet.companionConfig = _AddressSheetCompanionConfig(
      label: 'Départ',
      value: _pickup.address.trim().isEmpty
          ? 'Touchez pour renseigner le départ'
          : _pickup.address,
      onTap: () {
        Navigator.of(context).maybePop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openPickupSearchSheet();
        });
      },
    );
    final _AddressPoint? result = await _showAddressSearchSheet(
      title: 'Où livrer votre envoi ?',
      initialAddress: _delivery.address,
      labelText: 'Lieu de livraison',
      hintText: 'Destination, repère, quartier...',
    );

    if (result == null || !mounted) {
      _AddressSearchSheet.companionConfig = null;
      return;
    }
    _AddressSearchSheet.companionConfig = null;
    _deliveryController.text = result.address;
    _deliveryController.selection = TextSelection.collapsed(
      offset: result.address.length,
    );
    setState(() {
      _delivery = result;
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
    _refreshRoutePreview();
    _refreshRequestMapViewport();
    _triggerAutoSearchIfReady();
  }

  Future<void> _openPickupSearchSheet() async {
    _AddressSearchSheet.companionConfig = _AddressSheetCompanionConfig(
      label: 'Livraison',
      value: _delivery.address.trim().isEmpty
          ? 'Touchez pour renseigner la destination'
          : _delivery.address,
      onTap: () {
        Navigator.of(context).maybePop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openDeliverySearchSheet();
        });
      },
    );
    final _AddressPoint? result = await _showAddressSearchSheet(
      title: 'Où récupérer votre envoi ?',
      initialAddress: _pickup.address,
      labelText: 'Lieu de récupération',
      hintText: 'Départ, repère, quartier...',
    );

    if (result == null || !mounted) {
      _AddressSearchSheet.companionConfig = null;
      return;
    }
    _AddressSearchSheet.companionConfig = null;
    _pickupController.text = result.address;
    _pickupController.selection = TextSelection.collapsed(
      offset: result.address.length,
    );
    setState(() {
      _pickup = result;
      _matches = const <ParcelServiceMatch>[];
      _selectedMatch = null;
      _hasSearchedMatches = false;
      _matchesOverlayHidden = false;
    });
    _refreshRoutePreview();
    _refreshRequestMapViewport();
    _triggerAutoSearchIfReady();
  }

  Future<_AddressPoint?> _showAddressSearchSheet({
    required String title,
    required String initialAddress,
    required String labelText,
    required String hintText,
  }) {
    return showGeneralDialog<_AddressPoint>(
      context: context,
      barrierLabel: 'Recherche adresse',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.12),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (BuildContext context, _, __) {
        return _AddressSearchSheetRoute(
          child: _AddressSearchSheet(
            title: title,
            apiKey: _googleMapsApiKey,
            initialAddress: initialAddress,
            labelText: labelText,
            hintText: hintText,
            onResolved: (PlaceDetailsResult details) {
              Navigator.of(context).pop(
                _AddressPoint(
                  address: details.address,
                  lat: details.lat,
                  lng: details.lng,
                  placeId: details.placeId,
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final CurvedAnimation curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _useCurrentLocationForPickup() async {
    if (_isFetchingPickupLocation) return;

    setState(() {
      _isFetchingPickupLocation = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(
          'Activez la localisation pour utiliser votre position actuelle.',
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage(
          'Autorisez la localisation pour préremplir le lieu de récupération.',
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final String resolvedAddress = await _reverseGeocodePosition(position);

      _pickupController.text = resolvedAddress;
      _pickupController.selection = TextSelection.collapsed(
        offset: resolvedAddress.length,
      );

      if (!mounted) return;
      setState(() {
        _pickup = _pickup.copyWith(
          address: resolvedAddress,
          lat: position.latitude,
          lng: position.longitude,
          placeId: null,
        );
        _matches = const <ParcelServiceMatch>[];
        _selectedMatch = null;
        _hasSearchedMatches = false;
        _matchesOverlayHidden = false;
      });
      _showMessage('Adresse de récupération renseignée depuis votre position.');
      _refreshRoutePreview();
      _refreshRequestMapViewport();
    } catch (_) {
      _showMessage('Impossible de récupérer votre position actuelle.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isFetchingPickupLocation = false;
      });
    }
  }

  Future<String> _reverseGeocodePosition(Position position) async {
    try {
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
      ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(', ');
      if (address.isNotEmpty) return address;
    } catch (_) {
      // Fallback to raw coordinates below.
    }

    return '${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)}';
  }

  LatLng get _requestMapCenter {
    if (_pickup.lat != null && _pickup.lng != null) {
      return LatLng(_pickup.lat!, _pickup.lng!);
    }
    return const LatLng(5.359952, -4.008256);
  }

  Set<Marker> get _requestMarkers {
    final Set<Marker> markers = <Marker>{};
    if (_pickup.lat != null && _pickup.lng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickup.lat!, _pickup.lng!),
          infoWindow: const InfoWindow(title: 'Départ'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }
    if (_delivery.lat != null && _delivery.lng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(_delivery.lat!, _delivery.lng!),
          infoWindow: const InfoWindow(title: 'Livraison'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> get _requestPolylines {
    final List<LatLng> points = _routePreviewPoints.isNotEmpty
        ? _routePreviewPoints
        : (_pickup.lat != null &&
                _pickup.lng != null &&
                _delivery.lat != null &&
                _delivery.lng != null)
            ? <LatLng>[
                LatLng(_pickup.lat!, _pickup.lng!),
                LatLng(_delivery.lat!, _delivery.lng!),
              ]
            : const <LatLng>[];

    if (points.length < 2) {
      return const <Polyline>{};
    }

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route-glow'),
        points: points,
        color: const Color(0x4DD946EF),
        width: 14,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId('route-main'),
        points: points,
        color: const Color(0xFFBE185D),
        width: 7,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  Future<void> _refreshRoutePreview() async {
    if (_pickup.lat == null ||
        _pickup.lng == null ||
        _delivery.lat == null ||
        _delivery.lng == null) {
      if (_routePreviewPoints.isEmpty) return;
      setState(() {
        _routePreviewPoints = const <LatLng>[];
      });
      return;
    }

    final int requestSerial = ++_routeRequestSerial;
    final List<LatLng> routePoints = await _routePreviewService.fetchRoutePoints(
      pickupLat: _pickup.lat!,
      pickupLng: _pickup.lng!,
      deliveryLat: _delivery.lat!,
      deliveryLng: _delivery.lng!,
    );

    if (!mounted || requestSerial != _routeRequestSerial) return;
    setState(() {
      _routePreviewPoints = routePoints;
    });
    _refreshRequestMapViewport();
  }

  Future<void> _refreshRequestMapViewport() async {
    final GoogleMapController? controller = _mapController;
    if (controller == null || !mounted) return;

    final List<LatLng> boundsPoints = _routePreviewPoints.isNotEmpty
        ? _routePreviewPoints
        : (_pickup.lat != null &&
                _pickup.lng != null &&
                _delivery.lat != null &&
                _delivery.lng != null)
            ? <LatLng>[
                LatLng(_pickup.lat!, _pickup.lng!),
                LatLng(_delivery.lat!, _delivery.lng!),
              ]
            : const <LatLng>[];

    if (boundsPoints.length >= 2) {
      double south = boundsPoints.first.latitude;
      double north = boundsPoints.first.latitude;
      double west = boundsPoints.first.longitude;
      double east = boundsPoints.first.longitude;

      for (final LatLng point in boundsPoints.skip(1)) {
        if (point.latitude < south) south = point.latitude;
        if (point.latitude > north) north = point.latitude;
        if (point.longitude < west) west = point.longitude;
        if (point.longitude > east) east = point.longitude;
      }

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          84,
        ),
      );
      return;
    }

    if (_pickup.lat != null && _pickup.lng != null) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_pickup.lat!, _pickup.lng!),
            zoom: 15.2,
          ),
        ),
      );
    }
  }

  Future<void> _continue() async {
    if (!_canContinueFromCurrentStep) return;

    switch (_currentStep) {
      case _ShipStep.request:
        if (_matches.isNotEmpty && _selectedMatch != null) {
          _goToStep(_ShipStep.recipient);
          return;
        }
        await _loadMatchesAndContinue();
        return;
      case _ShipStep.matches:
        _goToStep(_ShipStep.recipient);
        return;
      case _ShipStep.recipient:
        await _submitDraft();
        return;
    }
  }

  void _goToStep(_ShipStep step) {
    final int targetIndex = _ShipStep.values.indexOf(step);
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      targetIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (step) {
        case _ShipStep.request:
          _deliveryFocusNode.requestFocus();
          return;
        case _ShipStep.matches:
          return;
        case _ShipStep.recipient:
          _recipientNameFocusNode.requestFocus();
          return;
      }
    });
  }

  void _triggerAutoSearchIfReady() {
    if (!mounted ||
        _currentStep != _ShipStep.request ||
        !_pickup.isComplete ||
        !_delivery.isComplete ||
        _isSearchingMatches) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _currentStep != _ShipStep.request ||
          !_pickup.isComplete ||
          !_delivery.isComplete ||
          _isSearchingMatches) {
        return;
      }
      _loadMatchesAndContinue();
    });
  }

  Future<void> _loadMatchesAndContinue() async {
    if (_isSearchingMatches || !_pickup.isComplete || !_delivery.isComplete) {
      return;
    }

    setState(() {
      _isSearchingMatches = true;
    });

    try {
      final List<ParcelServiceMatch> matches =
          await _parcelServiceMatcher.findMatches(
        pickupAddress: _pickup.address,
        pickupLat: _pickup.lat!,
        pickupLng: _pickup.lng!,
        deliveryAddress: _delivery.address,
        deliveryLat: _delivery.lat!,
        deliveryLng: _delivery.lng!,
      );

      if (!mounted) return;
      setState(() {
        _matches = matches;
        _selectedMatch = matches.isNotEmpty ? matches.first : null;
        _hasSearchedMatches = true;
        _matchesOverlayHidden = false;
      });
    } catch (_) {
      _showMessage('Impossible de rechercher des livreurs pour le moment.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSearchingMatches = false;
      });
    }
  }

  Future<void> _submitDraft() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Récapitulatif',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                _SummaryRow(
                  icon: Icons.my_location_outlined,
                  title: 'Récupération',
                  value: _pickup.address,
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  icon: Icons.flag_outlined,
                  title: 'Livraison',
                  value: _delivery.address,
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Destinataire',
                  value:
                      '${_recipientNameController.text.trim()} - ${_recipientPhoneController.text.trim()}',
                ),
                if (_selectedMatch != null) ...[
                  const SizedBox(height: 12),
                  _SummaryRow(
                    icon: Icons.local_shipping_outlined,
                    title: 'Livreur choisi',
                    value:
                        '${_selectedMatch!.contactName} - ${_selectedMatch!.priceSource} ${_formatPrice(_selectedMatch!.price)} ${_selectedMatch!.currency}',
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'La suite du formulaire peut maintenant créer la demande dans Firestore.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continuer ensuite'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _currentStep == _ShipStep.request,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_currentStep != _ShipStep.request)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: _ProgressHeader(currentStep: _currentStep),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildRequestStep(colorScheme),
                    _buildMatchesStep(colorScheme),
                    _buildRecipientStep(colorScheme),
                  ],
                ),
              ),
              _BottomActionBar(
                canGoBack: _currentStep != _ShipStep.request,
                continueLabel: _currentStep == _ShipStep.recipient
                    ? 'Continuer'
                    : _currentStep == _ShipStep.request
                        ? _matches.isNotEmpty && _selectedMatch != null
                            ? 'Continuer'
                            : 'Voir les livreurs'
                        : 'Suivant',
                compactContinueAction: _currentStep == _ShipStep.request,
                onBack: _currentStep == _ShipStep.request
                    ? null
                    : () => _goToStep(_ShipStep.values[_currentStepIndex - 1]),
                onContinue: _canContinueFromCurrentStep ? _continue : null,
                isLoading: _isSubmitting,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestStep(ColorScheme colorScheme) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              _refreshRequestMapViewport();
            },
            initialCameraPosition: CameraPosition(
              target: _requestMapCenter,
              zoom: _delivery.lat == null ? 15.2 : 13.0,
            ),
            markers: _requestMarkers,
            polylines: _requestPolylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withOpacity(0.10),
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.48),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          right: 18,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Où livrer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.white.withOpacity(0.92),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Actualiser ma position',
                  onPressed: _isFetchingPickupLocation
                      ? null
                      : _useCurrentLocationForPickup,
                  icon: _isFetchingPickupLocation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.gps_fixed_rounded),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FBFA),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(34),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DBE4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _openPickupSearchSheet,
                      borderRadius: BorderRadius.circular(18),
                      child: _SlimAddressBar(
                        icon: Icons.my_location_rounded,
                        iconColor: const Color(0xFF0F766E),
                        label: 'Départ',
                        value: _pickup.address.trim().isEmpty
                            ? 'Position en cours de détection...'
                            : _pickup.address,
                        trailingIcon: Icons.chevron_right_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _openDeliverySearchSheet,
                      borderRadius: BorderRadius.circular(22),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Lieu de livraison',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF0F172A),
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _delivery.address.trim().isEmpty
                                          ? 'Touchez pour saisir une destination'
                                          : _delivery.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: _delivery.address.trim().isEmpty
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF475569),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_delivery.address.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _pickup.isComplete && _delivery.isComplete
                            ? 'Destination confirmée. Vous pouvez maintenant trouver les meilleurs livreurs.'
                            : 'Sélectionnez une suggestion pour confirmer la destination.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isSearchingMatches || _matches.isNotEmpty || _hasSearchedMatches)
          Positioned(
            left: 0,
            right: 0,
            bottom: 246,
            child: _matchesOverlayHidden
                ? _buildInlineMatchesCollapsedChip()
                : _buildInlineMatchesOverlay(colorScheme),
          ),
      ],
    );
  }

  Widget _buildPickupStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: colorScheme.primary,
      icon: Icons.inventory_2_outlined,
      title: 'Où récupère-t-on votre colis ?',
      subtitle:
          'Entrez une adresse précise ou utilisez votre position actuelle.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddressAutocompleteField(
            controller: _pickupController,
            focusNode: _pickupFocusNode,
            labelText: 'Lieu de récupération',
            hintText: 'Rue, quartier, ville...',
            apiKey: _googleMapsApiKey,
            onChanged: _handlePickupTextChanged,
            onPlaceResolved: _applyPickupDetails,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed:
                _isFetchingPickupLocation ? null : _useCurrentLocationForPickup,
            icon: _isFetchingPickupLocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(
              _isFetchingPickupLocation
                  ? 'Localisation en cours...'
                  : 'Utiliser ma position',
            ),
          ),
          const SizedBox(height: 18),
          _AddressStatusCard(
            title: 'Adresse retenue',
            icon: Icons.check_circle_outline_rounded,
            isReady: _pickup.isComplete,
            lines: [
              if (_pickup.address.trim().isNotEmpty) _pickup.address,
              if (_pickup.lat != null && _pickup.lng != null)
                'Coordonnees: ${_pickup.lat!.toStringAsFixed(5)}, ${_pickup.lng!.toStringAsFixed(5)}',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: const Color(0xFF0F766E),
      icon: Icons.local_shipping_outlined,
      title: 'Où doit-on livrer le colis ?',
      subtitle:
          'Choisissez le point d\'arrivée. L\'adresse doit être sélectionnée dans les suggestions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddressAutocompleteField(
            controller: _deliveryController,
            focusNode: _deliveryFocusNode,
            labelText: 'Lieu de livraison',
            hintText: 'Adresse du destinataire',
            apiKey: _googleMapsApiKey,
            onChanged: _handleDeliveryTextChanged,
            onPlaceResolved: _applyDeliveryDetails,
          ),
          const SizedBox(height: 18),
          _AddressStatusCard(
            title: 'Destination retenue',
            icon: Icons.flag_circle_outlined,
            isReady: _delivery.isComplete,
            lines: [
              if (_delivery.address.trim().isNotEmpty) _delivery.address,
              if (_delivery.lat != null && _delivery.lng != null)
                'Coordonnees: ${_delivery.lat!.toStringAsFixed(5)}, ${_delivery.lng!.toStringAsFixed(5)}',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatchesStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: const Color(0xFF0B766E),
      icon: Icons.local_shipping_rounded,
      title: 'Choisissez un livreur',
      subtitle:
          'Nous affichons au maximum 3 correspondances selon la proximite du depart et la couverture de zone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isSearchingMatches)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_matches.isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Aucune correspondance immediate n a ete trouvee pour ce trajet. La suite pourra ensuite proposer un mode de demande plus large.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            Column(
              children: _matches
                  .map(
                    (ParcelServiceMatch match) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ParcelMatchCard(
                        match: match,
                        isSelected: _selectedMatch?.serviceId == match.serviceId,
                        onTap: () {
                          setState(() {
                            _selectedMatch = match;
                          });
                        },
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineMatchesOverlay(ColorScheme colorScheme) {
    return SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(999),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _isSearchingMatches
                            ? const Color(0xFFF59E0B)
                            : _matches.isNotEmpty
                                ? const Color(0xFF10B981)
                                : const Color(0xFF94A3B8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _isSearchingMatches
                            ? 'Recherche en cours'
                            : _matches.isNotEmpty
                                ? 'Livreurs disponibles'
                                : 'Aucune correspondance',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.1,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _matchesOverlayHidden = true;
                        });
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF64748B),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _isSearchingMatches
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  )
                : _matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Aucun livreur pertinent n’a été trouvé pour cette course pour le moment.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF334155),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (BuildContext context, int index) {
                          final ParcelServiceMatch match = _matches[index];
                          return SizedBox(
                            width: 268,
                            child: _ParcelMatchCard(
                              match: match,
                              isSelected:
                                  _selectedMatch?.serviceId == match.serviceId,
                              compact: true,
                              onTap: () {
                                setState(() {
                                  _selectedMatch = match;
                                });
                              },
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemCount: _matches.length,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMatchesCollapsedChip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () {
            setState(() {
              _matchesOverlayHidden = false;
            });
          },
          borderRadius: BorderRadius.circular(999),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(999),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 16,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _matches.isNotEmpty
                        ? 'Afficher les livreurs'
                        : 'Afficher le résultat',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecipientStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: const Color(0xFF115E59),
      icon: Icons.person_pin_circle_outlined,
      title: 'Qui recoit le colis ?',
      subtitle:
          'Ajoutez le nom et le numero du destinataire avant la suite du formulaire.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _recipientNameController,
            focusNode: _recipientNameFocusNode,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              context,
              label: 'Nom du destinataire',
              hint: 'Ex: Aicha Kone',
              icon: Icons.person_outline_rounded,
            ),
            onSubmitted: (_) => _recipientPhoneFocusNode.requestFocus(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _recipientPhoneController,
            focusNode: _recipientPhoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: _inputDecoration(
              context,
              label: 'Telephone du destinataire',
              hint: 'Ex: +225 07 00 00 00 00',
              icon: Icons.call_outlined,
            ),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF4FBF7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recap rapide',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    icon: Icons.my_location_outlined,
                    title: 'Récupération',
                    value: _pickup.address.isEmpty
                        ? 'A definir'
                        : _pickup.address,
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    icon: Icons.flag_outlined,
                    title: 'Livraison',
                    value: _delivery.address.isEmpty
                        ? 'A definir'
                        : _delivery.address,
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Destinataire',
                    value: _recipientNameController.text.trim().isEmpty
                        ? 'Nom et telephone a renseigner'
                        : '${_recipientNameController.text.trim()} - ${_recipientPhoneController.text.trim()}',
                  ),
                  if (_selectedMatch != null) ...[
                    const SizedBox(height: 10),
                    _SummaryRow(
                      icon: Icons.local_shipping_outlined,
                      title: 'Livreur',
                      value:
                          '${_selectedMatch!.contactName} - ${_selectedMatch!.priceSource} ${_formatPrice(_selectedMatch!.price)} ${_selectedMatch!.currency}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF4FBF7),
      prefixIcon: Icon(icon),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.currentStep});

  final _ShipStep currentStep;

  @override
  Widget build(BuildContext context) {
    const List<String> labels = <String>[
      'Demande',
      'Choix',
      'Destinataire',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nouvel envoi',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Un parcours simple, étape par étape, pour lancer une demande d\'expédition.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: List<Widget>.generate(labels.length, (int index) {
            final bool isActive = index == currentStep.index;
            final bool isDone = index < currentStep.index;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.compactHeader = false,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final bool compactHeader;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.12),
                  accentColor.withOpacity(0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentColor.withOpacity(0.12)),
            ),
            child: Padding(
              padding: EdgeInsets.all(compactHeader ? 16 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(icon, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        SizedBox(height: compactHeader ? 4 : 6),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _PickupHeroCard extends StatelessWidget {
  const _PickupHeroCard({
    required this.isLoadingLocation,
    required this.pickupAddress,
    required this.onRefreshLocation,
  });

  final bool isLoadingLocation;
  final String pickupAddress;
  final VoidCallback onRefreshLocation;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0F766E),
            Color(0xFF115E59),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Départ détecté',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pickupAddress.trim().isEmpty
                            ? 'Détection en cours ou position à confirmer.'
                            : pickupAddress,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.88),
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: isLoadingLocation ? null : onRefreshLocation,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: isLoadingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.gps_fixed_rounded, size: 18),
              label: const Text('Actualiser ma position'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressSearchSheetRoute extends StatefulWidget {
  const _AddressSearchSheetRoute({required this.child});

  final Widget child;

  @override
  State<_AddressSearchSheetRoute> createState() => _AddressSearchSheetRouteState();
}

class _AddressSearchSheetRouteState extends State<_AddressSearchSheetRoute> {
  double _dragOffset = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    final double nextOffset = (_dragOffset + details.delta.dy).clamp(0, 220);
    if (nextOffset == _dragOffset) return;
    setState(() {
      _dragOffset = nextOffset;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 120 || velocity > 900) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double maxHeight =
            constraints.maxHeight - mediaQuery.padding.top - 6;

        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.36, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double value, Widget? child) {
                  final double height = maxHeight * value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(
                      0,
                      ((1 - value) * 24) + _dragOffset,
                      0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragUpdate: _handleDragUpdate,
                        onVerticalDragEnd: _handleDragEnd,
                        child: child,
                      ),
                    ),
                  );
                },
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddressSheetCompanionConfig {
  const _AddressSheetCompanionConfig({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
}

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet({
    required this.title,
    required this.apiKey,
    required this.initialAddress,
    required this.labelText,
    required this.hintText,
    required this.onResolved,
  });

  static _AddressSheetCompanionConfig? companionConfig;

  final String title;
  final String apiKey;
  final String initialAddress;
  final String labelText;
  final String hintText;
  final ValueChanged<PlaceDetailsResult> onResolved;

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _entered = true;
        });
      }
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _AddressSheetCompanionConfig? companionConfig =
        _AddressSearchSheet.companionConfig;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: _entered ? 1 : 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF9FBFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DBE4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideY(begin: -0.8, end: 0, duration: 320.ms),
              ),
              const SizedBox(height: 16),
                Row(
                  children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 40.ms, duration: 220.ms)
                      .slideX(begin: -0.2, end: 0, duration: 280.ms),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    )
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 240.ms)
                        .slideY(begin: 0.15, end: 0, duration: 320.ms),
                  ),
                ],
              ),
              if (companionConfig != null) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: companionConfig.onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: _SlimAddressBar(
                    icon: Icons.swap_horiz_rounded,
                    iconColor: const Color(0xFF0F766E),
                    label: companionConfig.label,
                    value: companionConfig.value,
                    trailingIcon: Icons.chevron_right_rounded,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 145.ms, duration: 250.ms)
                    .slideY(begin: 0.2, end: 0, duration: 340.ms),
              ],
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.06),
                      blurRadius: 22,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.labelText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Recherchez un lieu précis pour continuer.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF667085),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: InputDecorationTheme(
                            labelStyle: const TextStyle(
                              color: Color(0xFF475467),
                              fontWeight: FontWeight.w700,
                            ),
                            hintStyle: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFF0F766E),
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                        child: AddressAutocompleteField(
                          controller: _controller,
                          focusNode: _focusNode,
                          labelText: widget.labelText,
                          hintText: widget.hintText,
                          apiKey: widget.apiKey,
                          countries: const <String>['ci', 'fr'],
                          suggestionTypes: null,
                          onPlaceResolved: widget.onResolved,
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 160.ms, duration: 260.ms)
                  .slideY(begin: 0.22, end: 0, duration: 360.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlimAddressBar extends StatelessWidget {
  const _SlimAddressBar({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailingIcon,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Text(
              '$label :',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                  ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(
                trailingIcon,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddressStatusCard extends StatelessWidget {
  const _AddressStatusCard({
    required this.title,
    required this.icon,
    required this.isReady,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final bool isReady;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isReady ? const Color(0xFFEAF7F1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isReady ? const Color(0xFF99D3B7) : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isReady ? const Color(0xFF0F766E) : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (lines.isEmpty)
                    Text(
                      'Sélectionnez une adresse valide pour continuer.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    )
                  else
                    ...lines.map(
                      (String line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0F766E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParcelMatchCard extends StatelessWidget {
  const _ParcelMatchCard({
    required this.match,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  final ParcelServiceMatch match;
  final bool isSelected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color accent = isSelected
        ? const Color(0xFF0F766E)
        : const Color(0xFFCBD5E1);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent, width: isSelected ? 1.8 : 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.contactName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 13 : null,
                          ),
                    ),
                  ),
                  SizedBox(width: compact ? 4 : 12),
                  Text(
                    '${_formatPrice(match.price)} ${match.currency}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F766E),
                          fontSize: compact ? 13 : null,
                        ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              Wrap(
                spacing: compact ? 4 : 8,
                runSpacing: compact ? 4 : 8,
                children: [
                  _matchPill(match.priceSource),
                  _matchPill(match.vehicleLabel),
                  _matchPill(_distanceLabel(match.distanceToPickupMeters)),
                  if (!compact)
                    _matchPill(
                      match.isZoneCovered ? 'Tarif prestataire' : 'Tarif GoVIP',
                    ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                Text(
                  match.isZoneCovered
                      ? 'Tarif du prestataire applique pour cette course.'
                      : 'Tarif GoVIP applique car le service ne couvre pas directement cette zone.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchPill(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}

String _distanceLabel(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _formatPrice(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(0);
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.canGoBack,
    required this.continueLabel,
    required this.compactContinueAction,
    required this.onBack,
    required this.onContinue,
    required this.isLoading,
  });

  final bool canGoBack;
  final String continueLabel;
  final bool compactContinueAction;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            mainAxisAlignment: compactContinueAction
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (canGoBack) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : onBack,
                    child: const Text('Retour'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (compactContinueAction)
                TextButton.icon(
                  onPressed: isLoading ? null : onContinue,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.tune_rounded, size: 18),
                  label: Text(continueLabel),
                )
              else
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: isLoading ? null : onContinue,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(continueLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
