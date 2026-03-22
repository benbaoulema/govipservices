import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/data/parcel_route_preview_service.dart';
import 'package:govipservices/features/parcels/data/parcel_service_matcher.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_service_match.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/features/user/data/user_firestore_repository.dart';
import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/parcels/presentation/services/delivery_notification_service.dart';
import 'package:govipservices/features/parcels/presentation/widgets/delivery_completion_dialog.dart';
import 'package:govipservices/features/user/models/user_role.dart';


part 'ship_package_step_widgets.dart';
part 'ship_package_address_sheet.dart';
part 'ship_package_match_card.dart';
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

class _RequesterIdentity {
  const _RequesterIdentity({
    required this.uid,
    required this.name,
    required this.contact,
  });

  final String uid;
  final String name;
  final String contact;
}

enum _RequesterAction { login, lightAccount }

class ShipPackagePage extends StatefulWidget {
  const ShipPackagePage({
    super.key,
    this.resumeRequestId,
    this.openAddressSheet = false,
  });

  /// Si non-null, reprend le suivi de la demande active à l'ouverture de la page.
  final String? resumeRequestId;

  /// Si true, ouvre directement le sheet de saisie d'adresse à l'ouverture.
  final bool openAddressSheet;

  @override
  State<ShipPackagePage> createState() => _ShipPackagePageState();
}

class _ShipPackagePageState extends State<ShipPackagePage> {
  String get _googleMapsApiKey => RuntimeAppConfig.googleMapsApiKey;

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
  final ParcelRequestService _parcelRequestService = ParcelRequestService();
  final ParcelServiceMatcher _parcelServiceMatcher = ParcelServiceMatcher();
  final UserFirestoreRepository _userFirestoreRepository =
      UserFirestoreRepository();
  late final ParcelRoutePreviewService _routePreviewService;

  GoogleMapController? _mapController;
  _ShipStep _currentStep = _ShipStep.request;
  _AddressPoint _pickup = const _AddressPoint();
  _AddressPoint _delivery = const _AddressPoint();
  List<LatLng> _routePreviewPoints = const <LatLng>[];
  List<ParcelServiceMatch> _matches = const <ParcelServiceMatch>[];
  ParcelServiceMatch? _selectedMatch;
  bool _hasSearchedMatches = false;
  bool _isFetchingPickupLocation = false;
  bool _isSearchingMatches = false;
  bool _isCreatingParcelRequest = false;
  bool _isSubmitting = false;
  String? _orderingServiceId;
  int _routeRequestSerial = 0;
  String? _routeDurationText;

  // Contacts confirmed before ordering
  String _confirmedSenderContact = '';
  String _confirmedReceiverName = '';
  String _confirmedReceiverPhone = '';

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  bool _autoMode = false;
  bool _isSearchingAutoDriver = false;

  // Active request watch (after ordering)
  String? _activeRequestId;
  String? _activeTrackNum;
  ParcelServiceMatch? _activeMatch;
  _SenderRequestStatus _activeStatus = _SenderRequestStatus.pending;
  LatLng? _courierLivePosition;
  String? _courierEtaText;
  StreamSubscription<ParcelRequestDocument?>? _requestSub;
  BitmapDescriptor? _courierLiveIcon;

  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _deliveryIcon;

  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  DateTime? _maxDeliveryDate;

  @override
  void initState() {
    super.initState();
    _routePreviewService = ParcelRoutePreviewService(apiKey: _googleMapsApiKey);
    _recipientNameController.addListener(_handleRecipientChanged);
    _recipientPhoneController.addListener(_handleRecipientChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocationForPickup();
      _loadMarkerIcons();
      if (widget.resumeRequestId != null) {
        _resumeWatchingRequest(widget.resumeRequestId!);
      } else if (widget.openAddressSheet) {
        _openDeliverySearchSheet();
      }
    });
  }

  Future<BitmapDescriptor> _emojiToBitmap(String emoji, double fontSize) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final TextPainter tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(text: emoji, style: TextStyle(fontSize: fontSize))
      ..layout();
    tp.paint(canvas, Offset.zero);
    final ui.Image img = await recorder
        .endRecording()
        .toImage(tp.width.ceil(), tp.height.ceil());
    final ByteData? data =
        await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  Future<void> _loadMarkerIcons() async {
    final List<BitmapDescriptor> icons = await Future.wait(<Future<BitmapDescriptor>>[
      _emojiToBitmap('📦', 42),
      _emojiToBitmap('🏍️📦', 36),
      _emojiToBitmap('🏍️', 44),
    ]);
    if (!mounted) return;
    setState(() {
      _pickupIcon = icons[0];
      _deliveryIcon = icons[1];
      _courierLiveIcon = icons[2];
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
    _noteController.dispose();
    _weightController.dispose();
    _requestSub?.cancel();
    _sheetController.dispose();
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
      barrierColor: Colors.black.withValues(alpha: 0.12),
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
        });
      _showMessage('Adresse de récupération renseignée depuis votre position.');
      _refreshRoutePreview();
      _refreshRequestMapViewport();
    } catch (_) {
      _showMessage('Impossible de récupérer votre position actuelle.');
    } finally {
      if (mounted) setState(() => _isFetchingPickupLocation = false);
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
          icon: _pickupIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }
    if (_delivery.lat != null && _delivery.lng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(_delivery.lat!, _delivery.lng!),
          infoWindow: const InfoWindow(title: 'Livraison'),
          icon: _deliveryIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    if (_courierLivePosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier_live'),
          position: _courierLivePosition!,
          infoWindow: InfoWindow(
            title: _activeMatch?.contactName ?? 'Livreur',
            snippet: 'En route',
          ),
          icon: _courierLiveIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 2,
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
        color: const Color(0x400F766E),
        width: 14,
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId('route-main'),
        points: points,
        color: const Color(0xFF0F766E),
        width: 6,
        geodesic: true,
        jointType: JointType.round,
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
    final RouteResult routeResult = await _routePreviewService.fetchRoute(
      pickupLat: _pickup.lat!,
      pickupLng: _pickup.lng!,
      deliveryLat: _delivery.lat!,
      deliveryLng: _delivery.lng!,
    );

    if (!mounted || requestSerial != _routeRequestSerial) return;
    setState(() {
      _routePreviewPoints = routeResult.points;
      _routeDurationText = routeResult.durationText;
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
        pickupPlaceId: _pickup.placeId,
        deliveryAddress: _delivery.address,
        deliveryLat: _delivery.lat!,
        deliveryLng: _delivery.lng!,
        deliveryPlaceId: _delivery.placeId,
      );

      if (!mounted) return;
      setState(() {
        _matches = matches;
        _selectedMatch = matches.isNotEmpty ? matches.first : null;
        _hasSearchedMatches = true;
        });
    } catch (_) {
      _showMessage('Impossible de rechercher des livreurs pour le moment.');
    } finally {
      if (mounted) setState(() => _isSearchingMatches = false);
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickMaxDate(BuildContext ctx) async {
    final DateTime? picked = await showDatePicker(
      context: ctx,
      initialDate: _maxDeliveryDate ?? DateTime.now().add(
        const Duration(days: 1),
      ),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      helpText: 'Date limite de livraison',
      confirmText: 'Confirmer',
      cancelText: 'Annuler',
    );
    if (picked != null && mounted) {
      setState(() => _maxDeliveryDate = picked);
    }
  }

  String _formatDate(DateTime date) {
    const List<String> months = <String>[
      'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
      'jul', 'aoû', 'sep', 'oct', 'nov', 'déc',
    ];
    return '${date.day} ${months[date.month - 1]}. ${date.year}';
  }

  Future<void> _orderMatch(ParcelServiceMatch match) async {
    if (_isCreatingParcelRequest || !_pickup.isComplete || !_delivery.isComplete) {
      return;
    }

    // 1. Identify the sender
    final _RequesterIdentity? requester = await _ensureRequesterIdentity();
    if (requester == null || !mounted) return;

    // 2. Resolve pre-fill values
    final String prefillSender = _confirmedSenderContact.isNotEmpty
        ? _confirmedSenderContact
        : requester.contact;
    final String prefillReceiverName = _confirmedReceiverName.isNotEmpty
        ? _confirmedReceiverName
        : _recipientNameController.text.trim();
    final String prefillReceiverPhone = _confirmedReceiverPhone.isNotEmpty
        ? _confirmedReceiverPhone
        : _recipientPhoneController.text.trim();

    // 3. Always show contact confirmation sheet (pre-filled)
    final _ContactConfirmResult? confirmed = await _showContactConfirmSheet(
      prefillSenderContact: prefillSender,
      prefillReceiverName: prefillReceiverName,
      prefillReceiverPhone: prefillReceiverPhone,
    );
    if (confirmed == null || !mounted) return;
    final String senderContact = confirmed.senderContact;
    final String receiverName = confirmed.receiverName;
    final String receiverPhone = confirmed.receiverPhone;
    setState(() {
      _confirmedSenderContact = senderContact;
      _confirmedReceiverName = receiverName;
      _confirmedReceiverPhone = receiverPhone;
    });

    // 4. Place the order
    setState(() {
      _isCreatingParcelRequest = true;
      _orderingServiceId = match.serviceId;
      _selectedMatch = match;
    });

    try {
      final ParcelRequestDocument request =
          await _parcelRequestService.createRequest(
        CreateParcelRequestInput(
          serviceId: match.serviceId,
          providerUid: match.ownerUid,
          providerName: match.contactName,
          providerPhone: match.contactPhone,
          requesterUid: requester.uid,
          requesterName: requester.name,
          requesterContact: senderContact,
          pickupAddress: _pickup.address,
          pickupLat: _pickup.lat!,
          pickupLng: _pickup.lng!,
          deliveryAddress: _delivery.address,
          deliveryLat: _delivery.lat!,
          deliveryLng: _delivery.lng!,
          price: match.price,
          currency: match.currency,
          priceSource: match.priceSource,
          vehicleLabel: match.vehicleLabel,
          receiverName: receiverName,
          receiverContactPhone: receiverPhone,
        ),
      );

      if (!mounted) return;
      _startWatchingRequest(request: request, match: match);
    } catch (_) {
      if (mounted) {
        _showMessage('Impossible de notifier ce livreur pour le moment.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingParcelRequest = false;
          _orderingServiceId = null;
        });
      }
    }
  }

  Future<void> _orderAutoMode() async {
    if (_isSearchingAutoDriver || !_pickup.isComplete || !_delivery.isComplete) {
      return;
    }

    // 1. Identify sender
    final _RequesterIdentity? requester = await _ensureRequesterIdentity();
    if (requester == null || !mounted) return;

    // 2. Contact confirmation
    final String prefillSender = _confirmedSenderContact.isNotEmpty
        ? _confirmedSenderContact
        : requester.contact;
    final _ContactConfirmResult? confirmed = await _showContactConfirmSheet(
      prefillSenderContact: prefillSender,
      prefillReceiverName: _confirmedReceiverName,
      prefillReceiverPhone: _confirmedReceiverPhone,
    );
    if (confirmed == null || !mounted) return;
    setState(() {
      _confirmedSenderContact = confirmed.senderContact;
      _confirmedReceiverName = confirmed.receiverName;
      _confirmedReceiverPhone = confirmed.receiverPhone;
      _isSearchingAutoDriver = true;
    });

    try {
      await _dispatchToNearestDriver(
        requesterUid: requester.uid,
        requesterName: requester.name,
        senderContact: confirmed.senderContact,
        receiverName: confirmed.receiverName,
        receiverPhone: confirmed.receiverPhone,
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Impossible de trouver un livreur pour le moment.');
      }
    } finally {
      if (mounted) setState(() => _isSearchingAutoDriver = false);
    }
  }

  /// Cherche le driver le plus proche et crée la demande.
  /// Les contacts doivent être déjà confirmés.
  Future<void> _dispatchToNearestDriver({
    required String requesterUid,
    required String requesterName,
    required String senderContact,
    required String receiverName,
    required String receiverPhone,
  }) async {
    final ParcelServiceMatch? match =
        await _parcelServiceMatcher.findNearestAvailableDriver(
      pickupAddress: _pickup.address,
      pickupLat: _pickup.lat!,
      pickupLng: _pickup.lng!,
      deliveryAddress: _delivery.address,
      deliveryLat: _delivery.lat!,
      deliveryLng: _delivery.lng!,
    );

    if (!mounted) return;

    if (match == null) {
      _showMessage(
          'Aucun livreur disponible pour le moment. Réessayez dans quelques instants.');
      return;
    }

    final ParcelRequestDocument request =
        await _parcelRequestService.createRequest(
      CreateParcelRequestInput(
        serviceId: match.serviceId,
        providerUid: match.ownerUid,
        providerName: match.contactName,
        providerPhone: match.contactPhone,
        requesterUid: requesterUid,
        requesterName: requesterName,
        requesterContact: senderContact,
        pickupAddress: _pickup.address,
        pickupLat: _pickup.lat!,
        pickupLng: _pickup.lng!,
        deliveryAddress: _delivery.address,
        deliveryLat: _delivery.lat!,
        deliveryLng: _delivery.lng!,
        price: match.price,
        currency: match.currency,
        priceSource: match.priceSource,
        vehicleLabel: match.vehicleLabel,
        receiverName: receiverName,
        receiverContactPhone: receiverPhone,
      ),
    );

    if (!mounted) return;
    _startWatchingRequest(request: request, match: match);
  }

  /// Annule la demande en cours silencieusement et redispatche vers un autre
  /// driver — utilisé par le timer 30 s en mode auto.
  Future<void> _autoRetryAfterTimeout() async {
    if (!_autoMode || !_pickup.isComplete || !_delivery.isComplete) return;

    final String? requestId = _activeRequestId;
    final String? providerUid = _activeMatch?.ownerUid;
    final String trackNum = _activeTrackNum ?? '';

    // Arrêter le watch immédiatement
    _requestSub?.cancel();
    _requestSub = null;
    DeliveryNotificationService.instance.cancel();
    setState(() {
      _activeRequestId = null;
      _activeTrackNum = null;
      _activeMatch = null;
      _activeStatus = _SenderRequestStatus.pending;
      _courierLivePosition = null;
      _courierEtaText = null;
      _isSearchingAutoDriver = true;
    });

    // Annuler côté Firestore en arrière-plan (sans bloquer l'UI)
    if (requestId != null && providerUid != null) {
      final String requesterName =
          FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      _parcelRequestService
          .cancelRequestAndNotifyDriver(
            requestId: requestId,
            providerUid: providerUid,
            requesterName: requesterName,
            trackNum: trackNum,
          )
          .catchError((_) {});
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) {
      setState(() => _isSearchingAutoDriver = false);
      return;
    }

    try {
      final _RequesterIdentity requester =
          await _loadAuthenticatedRequesterIdentity(user);
      if (!mounted) return;
      await _dispatchToNearestDriver(
        requesterUid: requester.uid,
        requesterName: requester.name,
        senderContact: _confirmedSenderContact,
        receiverName: _confirmedReceiverName,
        receiverPhone: _confirmedReceiverPhone,
      );
    } catch (_) {
      if (mounted) _showMessage('Impossible de trouver un livreur pour le moment.');
    } finally {
      if (mounted) setState(() => _isSearchingAutoDriver = false);
    }
  }

  Future<_ContactConfirmResult?> _showContactConfirmSheet({
    required String prefillSenderContact,
    required String prefillReceiverName,
    required String prefillReceiverPhone,
  }) async {
    final TextEditingController senderCtrl =
        TextEditingController(text: prefillSenderContact);
    final TextEditingController receiverNameCtrl =
        TextEditingController(text: prefillReceiverName);
    final TextEditingController receiverPhoneCtrl =
        TextEditingController(text: prefillReceiverPhone);

    final _ContactConfirmResult? result =
        await showModalBottomSheet<_ContactConfirmResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext sheetCtx) {
          String? errorText;
          return StatefulBuilder(
            builder: (BuildContext ctx, StateSetter setSheetState) {
              void confirm() {
                final String sender = senderCtrl.text.trim();
                final String recName = receiverNameCtrl.text.trim();
                final String recPhone = receiverPhoneCtrl.text.trim();
                if (sender.isEmpty) {
                  setSheetState(() => errorText = 'Saisissez votre numéro de contact.');
                  return;
                }
                if (recPhone.isEmpty) {
                  setSheetState(() => errorText = 'Saisissez le numéro du destinataire.');
                  return;
                }
                Navigator.of(ctx).pop(
                  _ContactConfirmResult(
                    senderContact: sender,
                    receiverName: recName,
                    receiverPhone: recPhone,
                  ),
                );
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24, 0, 24,
                    MediaQuery.of(ctx).viewInsets.bottom + 28,
                  ),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    // Header
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.contacts_rounded,
                              color: Color(0xFF0F766E), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Confirmer les contacts',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Nécessaire pour que le livreur vous contacte.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Sender
                    const Text('Votre numéro',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    _inputField(
                      controller: senderCtrl,
                      hint: 'Ex: 0700000000',
                      icon: Icons.person_outline_rounded,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setSheetState(() => errorText = null),
                    ),
                    const SizedBox(height: 16),
                    // Divider section
                    Row(children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Destinataire',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 16),
                    _inputField(
                      controller: receiverNameCtrl,
                      hint: 'Nom du destinataire (optionnel)',
                      icon: Icons.badge_outlined,
                      onChanged: (_) => setSheetState(() => errorText = null),
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      controller: receiverPhoneCtrl,
                      hint: 'Numéro du destinataire',
                      icon: Icons.call_outlined,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setSheetState(() => errorText = null),
                      onSubmitted: (_) => confirm(),
                    ),
                    if (errorText != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(errorText!,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB42318))),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                        label: const Text('Confirmer et commander',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
                ), // SingleChildScrollView
              );
            },
          );
        },
      );

    // Dispose après 400ms pour couvrir l'animation de fermeture du sheet
    // (~300ms) avant de libérer les controllers (évite "used after disposed").
    Future.delayed(const Duration(milliseconds: 400), () {
      senderCtrl.dispose();
      receiverNameCtrl.dispose();
      receiverPhoneCtrl.dispose();
    });

    return result;
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction:
          onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF0F766E)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.6),
        ),
      ),
    );
  }

  /// Reprend le suivi d'une demande active depuis son ID (ex: depuis le banner).
  Future<void> _resumeWatchingRequest(String requestId) async {
    final ParcelRequestDocument? doc =
        await _parcelRequestService.fetchRequestById(requestId);
    if (doc == null || !mounted) return;

    // Reconstruit un match minimal depuis les données du document
    final ParcelServiceMatch match = ParcelServiceMatch(
      serviceId: doc.serviceId,
      ownerUid: doc.providerUid,
      title: doc.providerName,
      contactName: doc.providerName,
      contactPhone: '',
      price: doc.price,
      currency: doc.currency,
      priceSource: 'fixed',
      isZoneCovered: true,
      distanceToPickupMeters: 0,
      priorityRank: 1,
      vehicleLabel: doc.vehicleLabel,
    );
    _startWatchingRequest(request: doc, match: match);
  }

  void _startWatchingRequest({
    required ParcelRequestDocument request,
    required ParcelServiceMatch match,
  }) {
    setState(() {
      _activeRequestId = request.id;
      _activeTrackNum = request.trackNum;
      _activeMatch = match;
      _activeStatus = _SenderRequestStatus.fromFirestore(request.status);
      _courierLivePosition = null;
      _courierEtaText = null;
    });
    // Étendre le sheet pour afficher le suivi en plein écran
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.62,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      }
    });
    _requestSub?.cancel();
    _requestSub = _parcelRequestService
        .watchRequestById(request.id)
        .listen((ParcelRequestDocument? doc) async {
      if (doc == null || !mounted) return;

      // Le driver a refusé → retour à la liste, on le retire des propositions
      if (doc.status == 'rejected') {
        final String? rejectedUid = _activeMatch?.ownerUid;
        _requestSub?.cancel();
        _requestSub = null;
        DeliveryNotificationService.instance.cancel();
        if (!mounted) return;
        setState(() {
          _activeRequestId = null;
          _activeTrackNum = null;
          _activeMatch = null;
          _activeStatus = _SenderRequestStatus.pending;
          _courierLivePosition = null;
          _courierEtaText = null;
          if (rejectedUid != null) {
            _matches = _matches
                .where((m) => m.ownerUid != rejectedUid)
                .toList(growable: false);
          }
        });
        // Mode auto : on cherche un autre driver automatiquement
        if (_autoMode) {
          _autoRetryAfterTimeout();
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: Color(0xFF991B1B),
                content: Text(
                  'Ce livreur n\'est pas disponible. Choisissez-en un autre.',
                ),
              ),
            );
        }
        return;
      }

      final _SenderRequestStatus newStatus =
          _SenderRequestStatus.fromFirestore(doc.status);
      LatLng? newCourierPos;
      if (doc.courierLat != null && doc.courierLng != null) {
        newCourierPos = LatLng(doc.courierLat!, doc.courierLng!);
      }
      setState(() {
        _activeStatus = newStatus;
        if (newCourierPos != null) _courierLivePosition = newCourierPos;
        if (newStatus == _SenderRequestStatus.arrivedAtPickup ||
            newStatus == _SenderRequestStatus.arrivedAtDelivery ||
            newStatus.isFinal) {
          _courierEtaText = null;
        }
      });
      // Mettre à jour la notification persistante
      DeliveryNotificationService.instance.showForSender(
        requestId: doc.id,
        status: doc.status,
        trackNum: doc.trackNum,
        pickupAddress: doc.pickupAddress,
        deliveryAddress: doc.deliveryAddress,
        etaText: _courierEtaText,
      );
      // Popup de fin de course quand livraison effectuée
      if (newStatus.isFinal) {
        _requestSub?.cancel();
        DeliveryNotificationService.instance.cancel();
        await showDeliveryCompletionDialog(
          context,
          trackNum: doc.trackNum,
          price: doc.price,
          currency: doc.currency,
          role: DeliveryCompletionRole.sender,
        );
        return;
      }
      // Recalcule ETA + bouge la caméra si position mise à jour
      if (newCourierPos != null) {
        _refreshCourierEta(courierPos: newCourierPos, status: newStatus);
        _moveCameraToShowCourier(newCourierPos);
      }
    });
    // Notif initiale
    DeliveryNotificationService.instance.showForSender(
      requestId: request.id,
      status: request.status,
      trackNum: request.trackNum,
      pickupAddress: request.pickupAddress,
      deliveryAddress: request.deliveryAddress,
    );
  }

  Future<void> _cancelRequest() async {
    final String? requestId = _activeRequestId;
    final String? providerUid = _activeMatch?.ownerUid;
    final String trackNum = _activeTrackNum ?? '';
    if (requestId == null) return;

    try {
      final String requesterName =
          FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
      await _parcelRequestService.cancelRequestAndNotifyDriver(
        requestId: requestId,
        providerUid: providerUid ?? '',
        requesterName: requesterName,
        trackNum: trackNum,
      );
      if (!mounted) return;
      _stopWatchingRequest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF991B1B),
            content: Text(
              error is StateError
                  ? error.message ?? 'La demande ne peut plus être annulée.'
                  : 'Impossible d’annuler la demande pour le moment.',
            ),
          ),
        );
    }
  }

  void _stopWatchingRequest() {
    DeliveryNotificationService.instance.cancel();
    _requestSub?.cancel();
    _requestSub = null;
    setState(() {
      _activeRequestId = null;
      _activeTrackNum = null;
      _activeMatch = null;
      _activeStatus = _SenderRequestStatus.pending;
      _courierLivePosition = null;
      _courierEtaText = null;
    });
  }

  Future<void> _refreshCourierEta({
    required LatLng courierPos,
    required _SenderRequestStatus status,
  }) async {
    // Destination = pickup tant que le colis n'est pas recupere.
    final LatLng? dest = status == _SenderRequestStatus.pickedUp ||
            status == _SenderRequestStatus.arrivedAtDelivery
        ? (_delivery.lat != null && _delivery.lng != null
            ? LatLng(_delivery.lat!, _delivery.lng!)
            : null)
        : (_pickup.lat != null && _pickup.lng != null
            ? LatLng(_pickup.lat!, _pickup.lng!)
            : null);
    if (dest == null) return;
    try {
      final RouteResult result = await _routePreviewService.fetchRoute(
        pickupLat: courierPos.latitude,
        pickupLng: courierPos.longitude,
        deliveryLat: dest.latitude,
        deliveryLng: dest.longitude,
      );
      if (!mounted) return;
      setState(() => _courierEtaText = result.durationText);
      final String? requestId = _activeRequestId;
      final String? trackNum = _activeTrackNum;
      if (requestId != null && trackNum != null) {
        DeliveryNotificationService.instance.showForSender(
          requestId: requestId,
          status: status.firestoreValue,
          trackNum: trackNum,
          pickupAddress: _pickup.address,
          deliveryAddress: _delivery.address,
          etaText: result.durationText,
        );
      }
    } catch (_) {}
  }

  void _moveCameraToShowCourier(LatLng courierPos) {
    final GoogleMapController? ctrl = _mapController;
    if (ctrl == null) return;
    final List<LatLng> points = <LatLng>[courierPos];
    if (_pickup.lat != null && _pickup.lng != null) {
      points.add(LatLng(_pickup.lat!, _pickup.lng!));
    }
    if (_delivery.lat != null && _delivery.lng != null) {
      points.add(LatLng(_delivery.lat!, _delivery.lng!));
    }
    if (points.length == 1) {
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(courierPos, 15));
      return;
    }
    final double minLat =
        points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final double maxLat =
        points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final double minLng =
        points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final double maxLng =
        points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    // padding bottom élevé : compense le sheet qui couvre ~62% de l'écran
    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  Future<_RequesterIdentity?> _ensureRequesterIdentity() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      return _loadAuthenticatedRequesterIdentity(currentUser);
    }

    final _RequesterAction? action = await _showRequesterAuthPrompt();
    if (action == null || !mounted) return null;

    if (action == _RequesterAction.login) {
      final Object? result = await Navigator.of(context).pushNamed(
        AppRoutes.authLogin,
        arguments: <String, dynamic>{'returnToCaller': true},
      );
      if (result != true) return null;
      final User? loggedUser = FirebaseAuth.instance.currentUser;
      if (loggedUser == null) return null;
      return _loadAuthenticatedRequesterIdentity(loggedUser);
    }

    return _showLightAccountPrompt();
  }

  Future<_RequesterIdentity> _loadAuthenticatedRequesterIdentity(
    User currentUser,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final String displayName =
          (data['displayName'] as String? ?? currentUser.displayName ?? '')
              .trim();
      final Map<String, dynamic> phone = data['phone'] is Map
          ? Map<String, dynamic>.from(data['phone'] as Map)
          : <String, dynamic>{};
      final String contact = <String>[
        (phone['countryCode'] as String? ?? '').trim(),
        (phone['number'] as String? ?? '').trim(),
      ].where((String value) => value.isNotEmpty).join(' ').trim();

      return _RequesterIdentity(
        uid: currentUser.uid,
        name: displayName.isEmpty ? 'Client GoVIP' : displayName,
        contact: contact.isEmpty
            ? (currentUser.email ?? '').trim()
            : contact,
      );
    } catch (_) {
      return _RequesterIdentity(
        uid: currentUser.uid,
        name: (currentUser.displayName ?? '').trim().isEmpty
            ? 'Client GoVIP'
            : currentUser.displayName!.trim(),
        contact: (currentUser.email ?? '').trim(),
      );
    }
  }

  Future<_RequesterAction?> _showRequesterAuthPrompt() {
    return showModalBottomSheet<_RequesterAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Avant de commander',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connectez-vous pour utiliser votre compte, ou laissez simplement votre nom et votre contact pour creer un compte leger.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_RequesterAction.login),
                  child: const Text('Se connecter'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context)
                      .pop(_RequesterAction.lightAccount),
                  child: const Text('Continuer avec mes infos'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_RequesterIdentity?> _showLightAccountPrompt() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController contactController = TextEditingController();

    try {
      return await showModalBottomSheet<_RequesterIdentity>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (BuildContext context) {
          bool isSaving = false;
          String? errorText;

          Future<void> submit(StateSetter setSheetState) async {
            final String name = nameController.text.trim();
            final String rawContact = contactController.text.trim();
            final String normalizedPhone = _normalizeLightAccountPhone(rawContact);

            if (name.isEmpty) {
              setSheetState(() {
                errorText = 'Saisissez votre nom complet.';
              });
              return;
            }
            if (normalizedPhone.isEmpty) {
              setSheetState(() {
                errorText = 'Saisissez un numero de contact valide sur 10 chiffres.';
              });
              return;
            }

            setSheetState(() {
              isSaving = true;
              errorText = null;
            });

            try {
              final _RequesterIdentity identity =
                  await _createOrReuseLightRequester(
                fullName: name,
                phoneNumber: normalizedPhone,
              );
              if (!context.mounted) return;
              Navigator.of(context).pop(identity);
            } catch (_) {
              setSheetState(() {
                errorText = 'Impossible de preparer votre compte leger pour le moment.';
                isSaving = false;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vos informations',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Renseignez votre nom complet et votre contact. Nous creerons un compte leger pour envoyer la demande au livreur.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        context,
                        label: 'Nom complet',
                        hint: 'Ex: Awa Kone',
                        icon: Icons.person_outline_rounded,
                      ),
                      onChanged: (_) {
                        if (errorText == null) return;
                        setSheetState(() {
                          errorText = null;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: contactController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: _inputDecoration(
                        context,
                        label: 'Contact',
                        hint: 'Ex: 0700000000',
                        icon: Icons.call_outlined,
                      ),
                      onChanged: (_) {
                        if (errorText == null) return;
                        setSheetState(() {
                          errorText = null;
                        });
                      },
                      onSubmitted: (_) => submit(setSheetState),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFB42318),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isSaving ? null : () => submit(setSheetState),
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Envoyer la demande'),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    } finally {
      nameController.dispose();
      contactController.dispose();
    }
  }

  Future<_RequesterIdentity> _createOrReuseLightRequester({
    required String fullName,
    required String phoneNumber,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await FirebaseFirestore.instance
            .collection('users')
            .where('phone.number', isEqualTo: phoneNumber)
            .limit(1)
            .get();

    if (snapshot.docs.isNotEmpty) {
      final String existingUid = snapshot.docs.first.id;
      await _userFirestoreRepository.update(existingUid, <String, dynamic>{
        'displayName': fullName,
        'role': userRoleToJson(UserRole.simpleUser),
        'phone': <String, dynamic>{
          'countryCode': '+225',
          'number': phoneNumber,
        },
        'meta': <String, dynamic>{
          'authEmailSource': 'phone-generated',
          'lightAccountFlow': 'parcel_request',
        },
      });

      return _RequesterIdentity(
        uid: existingUid,
        name: fullName,
        contact: '+225 $phoneNumber',
      );
    }

    final String syntheticEmail = '225$phoneNumber@govipuser.local';
    final String generatedPassword = _buildLightAccountPassword(phoneNumber);
    final UserCredential credentials =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: syntheticEmail,
      password: generatedPassword,
    );
    final User? authUser = credentials.user;
    if (authUser == null) {
      throw FirebaseAuthException(
        code: 'null-user',
        message: 'Compte leger introuvable apres creation.',
      );
    }
    await authUser.updateDisplayName(fullName);

    final AppUser user = AppUser(
      uid: authUser.uid,
      email: syntheticEmail,
      displayName: fullName,
      role: UserRole.simpleUser,
      phone: UserPhone(countryCode: '+225', number: phoneNumber),
      photoURL: null,
      materialPhotoUrl: null,
      service: null,
      isServiceProvider: false,
      createdAt: null,
      updatedAt: null,
      archived: false,
      meta: <String, dynamic>{
        'authEmailSource': 'phone-generated',
        'lightAccountFlow': 'parcel_request',
      },
    );

    await _userFirestoreRepository.setUser(authUser.uid, user);
    return _RequesterIdentity(
      uid: authUser.uid,
      name: fullName,
      contact: '+225 $phoneNumber',
    );
  }

  String _normalizeLightAccountPhone(String rawContact) {
    final String digitsOnly = rawContact.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) return digitsOnly;
    if (digitsOnly.length == 13 && digitsOnly.startsWith('225')) {
      return digitsOnly.substring(3);
    }
    return '';
  }

  String _buildLightAccountPassword(String phoneNumber) {
    return 'GoVip#$phoneNumber';
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
        resizeToAvoidBottomInset: false,
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
              if (_currentStep != _ShipStep.request)
                _BottomActionBar(
                  canGoBack: true,
                  showContinueAction: true,
                  continueLabel: _currentStep == _ShipStep.recipient
                      ? 'Continuer'
                      : 'Suivant',
                  compactContinueAction: false,
                  onBack: () => _goToStep(
                    _ShipStep.values[_currentStepIndex - 1],
                  ),
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
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.48),
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
              Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                shadowColor: Colors.black26,
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Platform.isIOS
                          ? Icons.chevron_left
                          : Icons.arrow_back_rounded,
                      size: Platform.isIOS ? 28 : 22,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Material(
                color: Colors.white.withValues(alpha: 0.92),
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
        // ── Switch "Mode auto" flottant au-dessus du sheet ──────────────
        if (_activeRequestId == null)
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.40 + 12,
            left: 20,
            right: 20,
            child: Center(
              child: GestureDetector(
                onTap: () => setState(() => _autoMode = !_autoMode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _autoMode
                        ? const Color(0xFF0F766E)
                        : Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _autoMode
                            ? const Color(0xFF0F766E).withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.14),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _autoMode
                              ? Icons.bolt_rounded
                              : Icons.bolt_outlined,
                          key: ValueKey<bool>(_autoMode),
                          size: 18,
                          color: _autoMode
                              ? Colors.white
                              : const Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mode auto',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _autoMode
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        width: 36,
                        height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _autoMode
                              ? Colors.white.withValues(alpha: 0.3)
                              : const Color(0xFFE2E8F0),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            AnimatedAlign(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: _autoMode
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                width: 16,
                                height: 16,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _autoMode
                                      ? Colors.white
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.40,
          minChildSize: 0.28,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const <double>[0.28, 0.40, 0.62, 0.92],
          builder: (BuildContext ctx, ScrollController scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  // ── Handle (sticky) ──────────────────────────────────
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),

                  // ── Mode auto panel ───────────────────────────────────
                  if (_autoMode && _activeRequestId == null)
                    _AutoModePanel(
                      pickup: _pickup,
                      delivery: _delivery,
                      durationText: _routeDurationText,
                      isLoading: _isSearchingAutoDriver,
                      onOrder: _orderAutoMode,
                    ),

                  // ── Livreurs (sticky) — masqué pendant le suivi ────────
                  if (_activeRequestId == null && !_autoMode && (_isSearchingMatches || _matches.isNotEmpty || _hasSearchedMatches)) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                      child: Row(
                        children: <Widget>[
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
                          Expanded(
                            child: Text(
                              _isSearchingMatches
                                  ? 'Recherche en cours…'
                                  : _matches.isNotEmpty
                                      ? 'Livreurs disponibles'
                                      : 'Aucune correspondance',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          if (_routeDurationText != null) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: Color(0xFF0F766E),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _routeDurationText!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F766E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 138,
                      child: _isSearchingMatches
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              ),
                            )
                          : _matches.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: Text(
                                        'Aucun livreur pertinent trouvé pour cette course.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _matches.length,
                                  separatorBuilder:
                                      (_, __) => const SizedBox(width: 12),
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                        final ParcelServiceMatch match =
                                            _matches[index];
                                        return SizedBox(
                                          width: 268,
                                          child: _ParcelMatchCard(
                                            match: match,
                                            isSelected:
                                                _selectedMatch?.serviceId ==
                                                match.serviceId,
                                            compact: true,
                                            onTap: () => _orderMatch(match),
                                            onOrder: () => _orderMatch(match),
                                            isOrdering:
                                                _orderingServiceId ==
                                                match.serviceId,
                                          ),
                                        );
                                      },
                                ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ],

                  // ── Waiting / Formulaire ──────────────────────────────
                  if (_activeRequestId != null)
                    _WaitingInlineContent(
                      match: _activeMatch!,
                      trackNum: _activeTrackNum ?? '',
                      status: _activeStatus,
                      etaText: _courierEtaText ?? _routeDurationText,
                      onClose: _stopWatchingRequest,
                      onCancel: _cancelRequest,
                      onTimeout: _autoMode ? _autoRetryAfterTimeout : null,
                      scrollController: scrollController,
                    )
                  else
                  Expanded(child: ListView(controller: scrollController, padding: EdgeInsets.zero, children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[

                        // ── Titre + bouton GPS ─────────────────────────────
                        Row(
                          children: <Widget>[
                            const Text(
                              'Expédier un colis',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _isFetchingPickupLocation
                                  ? null
                                  : _useCurrentLocationForPickup,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6FAF8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _isFetchingPickupLocation
                                    ? const Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.gps_fixed_rounded,
                                        size: 20,
                                        color: Color(0xFF0F766E),
                                      ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Adresse départ ─────────────────────────────────
                        GestureDetector(
                          onTap: _openPickupSearchSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF0F766E).withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.my_location_rounded,
                                  color: Color(0xFF0F766E),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'DÉPART',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F766E),
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _pickup.address.trim().isEmpty
                                            ? 'Position en cours de détection...'
                                            : _pickup.address,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _pickup.address.trim().isEmpty
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ── Adresse livraison ──────────────────────────────
                        GestureDetector(
                          onTap: _openDeliverySearchSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x08000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.flag_rounded,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'LIVRAISON',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF10B981),
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _delivery.address.trim().isEmpty
                                            ? 'Touchez pour saisir une destination'
                                            : _delivery.address,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: _delivery.address
                                                  .trim()
                                                  .isEmpty
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF94A3B8),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Séparateur "Détails de l'envoi" ───────────────
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Divider(color: Color(0xFFE2E8F0)),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Détails de l\'envoi',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(color: Color(0xFFE2E8F0)),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Instructions ──────────────────────────────────
                        _ShipDetailField(
                          controller: _noteController,
                          icon: Icons.notes_rounded,
                          label: 'Instructions',
                          hint: 'Ex: Fragile, tenir à plat...',
                        ),

                        const SizedBox(height: 12),

                        // ── Poids ─────────────────────────────────────────
                        _ShipDetailField(
                          controller: _weightController,
                          icon: Icons.scale_rounded,
                          label: 'Poids estimé',
                          hint: 'Ex: 2 kg',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ── Date max ──────────────────────────────────────
                        GestureDetector(
                          onTap: () => _pickMaxDate(ctx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  color: Color(0xFF0F766E),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'Date limite de livraison',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _maxDeliveryDate == null
                                            ? 'Aucune date limite'
                                            : _formatDate(_maxDeliveryDate!),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _maxDeliveryDate == null
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_maxDeliveryDate != null)
                                  GestureDetector(
                                    onTap: () => setState(
                                      () => _maxDeliveryDate = null,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Bouton principal ──────────────────────────────
                        GestureDetector(
                          onTap: _canContinueFromCurrentStep
                              ? _continue
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: _canContinueFromCurrentStep
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: <Color>[
                                        Color(0xFF14B8A6),
                                        Color(0xFF0F766E),
                                      ],
                                    )
                                  : const LinearGradient(
                                      colors: <Color>[
                                        Color(0xFFCBD5E1),
                                        Color(0xFFCBD5E1),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: _canContinueFromCurrentStep
                                  ? <BoxShadow>[
                                      const BoxShadow(
                                        color: Color(0x4014B8A6),
                                        blurRadius: 16,
                                        offset: Offset(0, 6),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: _isSearchingMatches
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        const Icon(
                                          Icons.search_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _matches.isNotEmpty &&
                                                  _selectedMatch != null
                                              ? 'Continuer'
                                              : 'Voir les livreurs',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),

                        SizedBox(
                          height: 20 +
                              MediaQuery.of(ctx).padding.bottom,
                        ),
                      ],
                    ),
                  ),
                  ])),
                ],
              ),
            ), // Container
            ); // ClipRRect
          },
        ),
      ],
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
                        onOrder: () => _orderMatch(match),
                        isOrdering: _orderingServiceId == match.serviceId,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
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
