import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/presentation/services/delivery_notification_service.dart';
import 'package:govipservices/features/parcels/data/parcel_route_preview_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';
import 'package:govipservices/features/parcels/presentation/widgets/delivery_completion_dialog.dart';
import 'package:govipservices/shared/services/safe_wakelock_service.dart';

/// Statuts métier de la course côté livreur.
///
/// Le livreur valide explicitement les arrivées et les remises pour que
/// l'expéditeur voie une progression fiable et exploitable dans le suivi.
enum _RunStatus {
  accepted,
  enRouteToPickup,
  arrivedAtPickup,
  pickedUp,
  arrivedAtDelivery,
  delivered;
  static _RunStatus fromString(String value) {
    switch (value) {
      case 'en_route_to_pickup':
      case 'en_route':
        return _RunStatus.enRouteToPickup;
      case 'arrived_at_pickup':
        return _RunStatus.arrivedAtPickup;
      case 'picked_up':
        return _RunStatus.pickedUp;
      case 'arrived_at_delivery':
        return _RunStatus.arrivedAtDelivery;
      case 'delivered':
        return _RunStatus.delivered;
      default:
        return _RunStatus.accepted;
    }
  }
  String get firestoreValue {
    switch (this) {
      case _RunStatus.accepted:
        return 'accepted';
      case _RunStatus.enRouteToPickup:
        return 'en_route_to_pickup';
      case _RunStatus.arrivedAtPickup:
        return 'arrived_at_pickup';
      case _RunStatus.pickedUp:
        return 'picked_up';
      case _RunStatus.arrivedAtDelivery:
        return 'arrived_at_delivery';
      case _RunStatus.delivered:
        return 'delivered';
    }
  }
}
// ─── Page ────────────────────────────────────────────────────────────────────

class ParcelDeliveryRunPage extends StatefulWidget {
  const ParcelDeliveryRunPage({required this.request, super.key});

  final ParcelRequestDocument request;

  @override
  State<ParcelDeliveryRunPage> createState() => _ParcelDeliveryRunPageState();
}

class _ParcelDeliveryRunPageState extends State<ParcelDeliveryRunPage>
    with WidgetsBindingObserver {
  static const Color _teal = Color(0xFF14B8A6);
  static const Color _tealDark = Color(0xFF0F766E);

  late final ParcelRequestService _requestService;
  late final ParcelRoutePreviewService _routeService;

  GoogleMapController? _mapController;
  _RunStatus _status = _RunStatus.accepted;
  List<LatLng> _routePoints = const <LatLng>[];
  String? _routeDurationText;
  Position? _courierPosition;
  bool _isUpdatingStatus = false;
  bool _isLoadingRoute = false;

  BitmapDescriptor? _courierIcon;
  BitmapDescriptor? _pickupIcon;

  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestService = ParcelRequestService();
    _routeService = ParcelRoutePreviewService(
      apiKey: RuntimeAppConfig.googleMapsApiKey,
    );
    _status = _RunStatus.fromString(widget.request.status);
    DeliveryNotificationService.instance.showForDriver(
      requestId: widget.request.id,
      status: widget.request.status,
      trackNum: widget.request.trackNum,
      pickupAddress: widget.request.pickupAddress,
      deliveryAddress: widget.request.deliveryAddress,
    );
    _syncWakeLock();
    _init();
  }

  @override
  void dispose() {
    SafeWakelockService.setEnabled(false);
    WidgetsBinding.instance.removeObserver(this);
    DeliveryNotificationService.instance.cancel();
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncWakeLock();
  }

  void _syncWakeLock() {
    final AppLifecycleState? lifecycleState =
        WidgetsBinding.instance.lifecycleState;
    final bool shouldKeepScreenOn =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    SafeWakelockService.setEnabled(shouldKeepScreenOn);
  }

  Future<void> _init() async {
    await Future.wait(<Future<void>>[
      _fetchCourierPosition(),
      _loadMarkerIcons(),
    ]);
    await _refreshRoute();
    _startPositionTracking();
  }

  // ── Icônes emoji pour les marqueurs ────────────────────────────────────────

  Future<BitmapDescriptor> _emojiToBitmap(String emoji, double fontSize) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final TextPainter tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: emoji,
        style: TextStyle(fontSize: fontSize),
      )
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
      _emojiToBitmap('🏍️', 44),  // marker position livreur
      _emojiToBitmap('📦', 40),   // marker pickup (colis)
    ]);
    if (!mounted) return;
    setState(() {
      _courierIcon = icons[0];
      _pickupIcon = icons[1];
    });
  }

  Future<void> _fetchCourierPosition() async {
    try {
      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }
      final Position pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _courierPosition = pos);
    } catch (_) {}
  }

  void _startPositionTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((Position pos) {
      if (!mounted) return;
      final bool needsRoute = _routePoints.isEmpty &&
          _status != _RunStatus.delivered &&
          _status != _RunStatus.arrivedAtDelivery;
      setState(() => _courierPosition = pos);
      if (needsRoute) _refreshRoute();
      if (_status != _RunStatus.delivered) {
        _requestService.updateCourierLocation(
          requestId: widget.request.id,
          lat: pos.latitude,
          lng: pos.longitude,
        );
      }
    });
  }

  Future<void> _refreshRoute() async {
    if (_status == _RunStatus.delivered) return;
    setState(() => _isLoadingRoute = true);

    try {
      final RouteResult result;

      if (_status == _RunStatus.pickedUp ||
          _status == _RunStatus.arrivedAtDelivery) {
        // Phase 2 : pickup → livraison
        if (widget.request.pickupLat == 0 && widget.request.deliveryLat == 0) {
          result = const RouteResult(points: <LatLng>[]);
        } else {
          result = await _routeService.fetchRoute(
            pickupLat: widget.request.pickupLat,
            pickupLng: widget.request.pickupLng,
            deliveryLat: widget.request.deliveryLat,
            deliveryLng: widget.request.deliveryLng,
          );
        }
      } else {
        // Phase 1 : position livreur → point de collecte
        final Position? pos = _courierPosition;
        if (pos == null || widget.request.pickupLat == 0) {
          result = const RouteResult(points: <LatLng>[]);
        } else {
          result = await _routeService.fetchRoute(
            pickupLat: pos.latitude,
            pickupLng: pos.longitude,
            deliveryLat: widget.request.pickupLat,
            deliveryLng: widget.request.pickupLng,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _routePoints = result.points;
        _routeDurationText = result.durationText;
      });
      DeliveryNotificationService.instance.showForDriver(
        requestId: widget.request.id,
        status: _status.firestoreValue,
        trackNum: widget.request.trackNum,
        pickupAddress: widget.request.pickupAddress,
        deliveryAddress: widget.request.deliveryAddress,
        etaText: result.durationText,
      );
      _fitMapToBounds();
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _fitMapToBounds() {
    final GoogleMapController? ctrl = _mapController;
    if (ctrl == null || _routePoints.isEmpty) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (final LatLng p in _routePoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    ctrl.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final Set<Marker> markers = <Marker>{};

    if (widget.request.pickupLat != 0) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(widget.request.pickupLat, widget.request.pickupLng),
          infoWindow: InfoWindow(title: 'Collecte', snippet: widget.request.pickupAddress),
          icon: _pickupIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }

    if (widget.request.deliveryLat != 0) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(widget.request.deliveryLat, widget.request.deliveryLng),
          infoWindow: InfoWindow(title: 'Livraison', snippet: widget.request.deliveryAddress),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    final Position? pos = _courierPosition;
    if (pos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: const InfoWindow(title: 'Ma position'),
          icon: _courierIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (_routePoints.isEmpty) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: const Color(0xFF6366F1), // indigo élégant
        width: 6,
        patterns: const <PatternItem>[],
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ),
    };
  }

  LatLng get _initialCameraTarget {
    if (widget.request.pickupLat != 0) {
      return LatLng(widget.request.pickupLat, widget.request.pickupLng);
    }
    return const LatLng(5.3599, -4.0083); // Abidjan par défaut
  }

  // ── Changement de statut ───────────────────────────────────────────────────

  _RunStatus? get _nextStatus {
    switch (_status) {
      case _RunStatus.accepted:
        return _RunStatus.arrivedAtPickup;
      case _RunStatus.enRouteToPickup:
        return _RunStatus.arrivedAtPickup;
      case _RunStatus.arrivedAtPickup:
        return _RunStatus.pickedUp;
      case _RunStatus.pickedUp:
        return _RunStatus.arrivedAtDelivery;
      case _RunStatus.arrivedAtDelivery:
        return _RunStatus.delivered;
      case _RunStatus.delivered:
        return null;
    }
  }
  String get _statusButtonLabel {
    switch (_status) {
      case _RunStatus.accepted:
        return 'Arrivé au point de collecte';
      case _RunStatus.enRouteToPickup:
        return 'Arrivé au point de collecte';
      case _RunStatus.arrivedAtPickup:
        return 'Colis récupéré';
      case _RunStatus.pickedUp:
        return 'Arrivé à destination';
      case _RunStatus.arrivedAtDelivery:
        return 'Livraison effectuée';
      case _RunStatus.delivered:
        return 'Terminé';
    }
  }
  IconData get _statusButtonIcon {
    switch (_status) {
      case _RunStatus.accepted:
        return Icons.place_rounded;
      case _RunStatus.enRouteToPickup:
        return Icons.place_rounded;
      case _RunStatus.arrivedAtPickup:
        return Icons.inventory_2_rounded;
      case _RunStatus.pickedUp:
        return Icons.location_on_rounded;
      case _RunStatus.arrivedAtDelivery:
        return Icons.flag_rounded;
      case _RunStatus.delivered:
        return Icons.check_circle_rounded;
    }
  }
  Future<void> _advanceStatus() async {
    final _RunStatus? next = _nextStatus;
    if (next == null || _isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);

    try {
      await _requestService.updateRequestStatusAndNotify(
        requestId: widget.request.id,
        status: next.firestoreValue,
        requesterUid: widget.request.requesterUid,
        providerName: widget.request.providerName,
        trackNum: widget.request.trackNum,
      );
      if (!mounted) return;
      setState(() => _status = next);

      // Mettre à jour la notification persistante
      DeliveryNotificationService.instance.showForDriver(
        requestId: widget.request.id,
        status: next.firestoreValue,
        trackNum: widget.request.trackNum,
        pickupAddress: widget.request.pickupAddress,
        deliveryAddress: widget.request.deliveryAddress,
      );

      if (next == _RunStatus.delivered) {
        if (!mounted) return;
        await showDeliveryCompletionDialog(
          context,
          trackNum: widget.request.trackNum,
          price: widget.request.price,
          currency: widget.request.currency,
          role: DeliveryCompletionRole.driver,
        );
        return;
      }

      // Retracer l'itinéraire si on vient de récupérer le colis
      if (next != _RunStatus.delivered) {
        await _refreshRoute();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF991B1B),
          content: Text('Mise à jour impossible pour le moment.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  String _phaseLabel() {
    switch (_status) {
      case _RunStatus.accepted:
      case _RunStatus.enRouteToPickup:
        return 'Aller au départ';
      case _RunStatus.arrivedAtPickup:
        return 'Au point de collecte';
      case _RunStatus.pickedUp:
        return 'En route vers la livraison';
      case _RunStatus.arrivedAtDelivery:
        return 'Arrivé à destination';
      case _RunStatus.delivered:
        return 'Livraison effectuée';
    }
  }
  Color _phaseColor() {
    switch (_status) {
      case _RunStatus.accepted:
        return const Color(0xFFF59E0B);
      case _RunStatus.enRouteToPickup:
        return _teal;
      case _RunStatus.arrivedAtPickup:
        return const Color(0xFFF97316);
      case _RunStatus.pickedUp:
        return const Color(0xFF3B82F6);
      case _RunStatus.arrivedAtDelivery:
        return const Color(0xFF2563EB);
      case _RunStatus.delivered:
        return const Color(0xFF10B981);
    }
  }
  Future<void> _openNavigation(double lat, double lng) async {
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callContact(String contact) async {
    final String digits = contact.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    await launchUrl(
      Uri.parse('tel:$digits'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // ── Carte ──────────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialCameraTarget,
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (GoogleMapController ctrl) {
              _mapController = ctrl;
              _fitMapToBounds();
            },
          ),

          // ── Bouton retour + badge ref ──────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  _MapButton(
                    icon: Platform.isIOS
                        ? Icons.chevron_left
                        : Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.request.trackNum,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: _tealDark,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_isLoadingRoute)
                    _MapButton(
                      icon: Icons.refresh_rounded,
                      onTap: _refreshRoute,
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom sheet ───────────────────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.22,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const <double>[0.22, 0.42, 0.88],
            builder: (BuildContext context, ScrollController scrollController) {
              return _DeliverySheet(
                scrollController: scrollController,
                request: widget.request,
                status: _status,
                phaseLabel: _phaseLabel(),
                phaseColor: _phaseColor(),
                durationText: _routeDurationText,
                statusButtonLabel: _statusButtonLabel,
                statusButtonIcon: _statusButtonIcon,
                isUpdating: _isUpdatingStatus,
                onAdvanceStatus: _advanceStatus,
                onCall: _callContact,
                onNavigate: _openNavigation,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

class _DeliverySheet extends StatelessWidget {
  const _DeliverySheet({
    required this.scrollController,
    required this.request,
    required this.status,
    required this.phaseLabel,
    required this.phaseColor,
    this.durationText,
    required this.statusButtonLabel,
    required this.statusButtonIcon,
    required this.isUpdating,
    required this.onAdvanceStatus,
    required this.onCall,
    required this.onNavigate,
  });

  final ScrollController scrollController;
  final ParcelRequestDocument request;
  final _RunStatus status;
  final String phaseLabel;
  final Color phaseColor;
  final String? durationText;
  final String statusButtonLabel;
  final IconData statusButtonIcon;
  final bool isUpdating;
  final VoidCallback onAdvanceStatus;
  final Future<void> Function(String contact) onCall;
  final Future<void> Function(double lat, double lng) onNavigate;

  static const Color _teal = Color(0xFF14B8A6);
  static const Color _tealDark = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: <Widget>[
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Phase chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                // ── Chips gauche (statut + ETA) ──
                Expanded(
                  child: Row(
                    children: <Widget>[
                      // Chip statut
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: phaseColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: phaseColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  phaseLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: phaseColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ETA badge
                      if (durationText != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                durationText!,
                                style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Bouton nav étape courante
                if (status != _RunStatus.delivered)
                  GestureDetector(
                    onTap: () {
                      final bool toPickup = status == _RunStatus.accepted ||
                          status == _RunStatus.enRouteToPickup ||
                          status == _RunStatus.arrivedAtPickup;
                      onNavigate(
                        toPickup ? request.pickupLat : request.deliveryLat,
                        toPickup ? request.pickupLng : request.deliveryLng,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: phaseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Nav',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // ── BOUTON DE STATUT (grand, ergonomique) ─────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _StatusButton(
              label: statusButtonLabel,
              icon: statusButtonIcon,
              isUpdating: isUpdating,
              isDone: status == _RunStatus.delivered,
              onTap: onAdvanceStatus,
            ),
          ),

          const SizedBox(height: 20),

          // ── Contacts ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Expéditeur
                _ContactCard(
                  icon: Icons.person_rounded,
                  color: _teal,
                  role: 'Expéditeur',
                  name: request.requesterName.isEmpty
                      ? 'Client'
                      : request.requesterName,
                  contact: request.requesterContact,
                  onCall: onCall,
                ),
                const SizedBox(height: 12),
                // Destinataire
                _ContactCard(
                  icon: Icons.person_pin_rounded,
                  color: const Color(0xFF3B82F6),
                  role: 'Destinataire',
                  name: request.receiverName.isEmpty
                      ? 'Non renseigné'
                      : request.receiverName,
                  contact: request.receiverContactPhone,
                  onCall: onCall,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Adresses ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: <Widget>[
                _NavAddressCard(
                  icon: Icons.my_location_rounded,
                  color: const Color(0xFFF59E0B),
                  label: 'Point de collecte',
                  address: request.pickupAddress.isEmpty
                      ? 'Adresse non disponible'
                      : request.pickupAddress,
                  lat: request.pickupLat,
                  lng: request.pickupLng,
                  onNavigate: onNavigate,
                ),
                const SizedBox(height: 10),
                _NavAddressCard(
                  icon: Icons.flag_rounded,
                  color: const Color(0xFF10B981),
                  label: 'Point de livraison',
                  address: request.deliveryAddress.isEmpty
                      ? 'Adresse non disponible'
                      : request.deliveryAddress,
                  lat: request.deliveryLat,
                  lng: request.deliveryLng,
                  onNavigate: onNavigate,
                ),
              ],
            ),
          ),

          // Prix
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Montant de la course',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_formatPrice(request.price)} ${request.currency}',
                  style: const TextStyle(
                    color: _tealDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─── Bouton statut ────────────────────────────────────────────────────────────

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.isUpdating,
    required this.isDone,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isUpdating;
  final bool isDone;
  final VoidCallback onTap;

  static const Color _teal = Color(0xFF14B8A6);
  static const Color _tealDark = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUpdating || isDone ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        decoration: BoxDecoration(
          gradient: isDone
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF10B981), Color(0xFF059669)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[_teal, _tealDark],
                ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _teal.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isUpdating
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, color: Colors.white, size: 26),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Contact card ─────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.color,
    required this.role,
    required this.name,
    required this.contact,
    required this.onCall,
  });

  final IconData icon;
  final Color color;
  final String role;
  final String name;
  final String contact;
  final Future<void> Function(String contact) onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  role,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (contact.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    contact,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (contact.isNotEmpty)
            GestureDetector(
              onTap: () => onCall(contact),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.phone_rounded, color: color, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'Appeler',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Carte adresse avec navigation ───────────────────────────────────────────

class _NavAddressCard extends StatelessWidget {
  const _NavAddressCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    required this.onNavigate,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String address;
  final double lat;
  final double lng;
  final Future<void> Function(double lat, double lng) onNavigate;

  @override
  Widget build(BuildContext context) {
    final bool hasCoords = lat != 0 || lng != 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            address,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasCoords) ...<Widget>[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => onNavigate(lat, lng),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Naviguer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bouton carte ─────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

// ─── Utils ────────────────────────────────────────────────────────────────────

String _formatPrice(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(0);
}

