import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/parcels/data/parcel_route_preview_service.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';
import 'package:govipservices/features/travel/data/transport_company_repository.dart';
import 'package:govipservices/features/travel/domain/models/transport_company.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _surface = Color(0xFFFFFFFF);
const Color _bg = Color(0xFFF2FFFC);

const LatLng _kDefaultCenter = LatLng(4.0511, 9.7679); // Douala, Cameroun

// Créneaux fixes 00h → 23h
final List<String> _kTimeSlots = List.generate(
  24,
  (i) => '${i.toString().padLeft(2, '0')}h',
);

// ─── Page ─────────────────────────────────────────────────────────────────────

class GoRadarMapPage extends StatefulWidget {
  const GoRadarMapPage({super.key});

  @override
  State<GoRadarMapPage> createState() => _GoRadarMapPageState();
}

class _GoRadarMapPageState extends State<GoRadarMapPage> {
  final GoRadarRepository _radarRepo = GoRadarRepository();
  final TransportCompanyRepository _companyRepo = TransportCompanyRepository();
  late final ParcelRoutePreviewService _routeService;

  GoogleMapController? _mapController;

  // ── Données filtres ─────────────────────────────────────────────────────────
  List<TransportCompany> _companies = [];
  TransportCompany? _selectedCompany;

  List<String> _departures = [];
  String? _selectedDeparture;

  List<String> _arrivals = [];
  String? _selectedArrival;

  String? _selectedHour; // ex: '07h'

  bool _loadingCompanies = true;
  bool _loadingDepartures = false;
  bool _loadingArrivals = false;

  // ── Sessions GO Radar ───────────────────────────────────────────────────────
  StreamSubscription<List<GoRadarSession>>? _sessionsSub;
  List<GoRadarSession> _sessions = [];

  // ── Map ─────────────────────────────────────────────────────────────────────
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _busIcon;
  final Map<String, List<LatLng>> _routeCache = {};

  @override
  void initState() {
    super.initState();
    _routeService = ParcelRoutePreviewService(
      apiKey: RuntimeAppConfig.googleMapsApiKey,
    );
    _loadBusIcon();
    _loadCompanies();
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Icône bus ────────────────────────────────────────────────────────────────

  Future<void> _loadBusIcon() async {
    final BitmapDescriptor icon = await _emojiToBitmap('🚌', 48);
    if (!mounted) return;
    setState(() => _busIcon = icon);
  }

  Future<BitmapDescriptor> _emojiToBitmap(
      String emoji, double fontSize) async {
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

  // ── Chargement données ────────────────────────────────────────────────────

  Future<void> _loadCompanies() async {
    setState(() => _loadingCompanies = true);
    try {
      final List<TransportCompany> list =
          await _companyRepo.fetchEnabled();
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

  Future<void> _onCompanySelected(TransportCompany company) async {
    setState(() {
      _selectedCompany = company;
      _selectedDeparture = null;
      _selectedArrival = null;
      _selectedHour = null;
      _departures = [];
      _arrivals = [];
      _loadingDepartures = true;
    });
    _cancelSessionStream();

    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('voyageTrips')
          .where('companyId', isEqualTo: company.id)
          .get();
      final Set<String> places = snap.docs
          .map((d) => (d.data()['departurePlace'] as String? ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (!mounted) return;
      final List<String> sorted = places.toList()..sort();
      setState(() {
        _departures = sorted;
        _loadingDepartures = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDepartures = false);
    }
  }

  Future<void> _onDepartureSelected(String departure) async {
    setState(() {
      _selectedDeparture = departure;
      _selectedArrival = null;
      _selectedHour = null;
      _arrivals = [];
      _loadingArrivals = true;
    });
    _cancelSessionStream();

    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('voyageTrips')
          .where('companyId', isEqualTo: _selectedCompany!.id)
          .where('departurePlace', isEqualTo: departure)
          .get();
      final Set<String> places = snap.docs
          .map((d) => (d.data()['arrivalPlace'] as String? ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (!mounted) return;
      final List<String> sorted = places.toList()..sort();
      setState(() {
        _arrivals = sorted;
        _loadingArrivals = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingArrivals = false);
    }
  }

  void _onArrivalSelected(String arrival) {
    setState(() {
      _selectedArrival = arrival;
      _selectedHour = null;
    });
    _cancelSessionStream();
  }

  void _onHourSelected(String hour) {
    setState(() => _selectedHour = hour);
    _startSessionStream();
  }

  // ── Stream sessions ──────────────────────────────────────────────────────────

  void _cancelSessionStream() {
    _sessionsSub?.cancel();
    _sessionsSub = null;
    setState(() {
      _sessions = [];
      _markers = {};
      _polylines = {};
    });
  }

  void _startSessionStream() {
    _sessionsSub?.cancel();
    if (_selectedCompany == null ||
        _selectedDeparture == null ||
        _selectedArrival == null ||
        _selectedHour == null) {
      return;
    }

    final String hourPrefix =
        _selectedHour!.replaceAll('h', ''); // '07h' → '07'

    _sessionsSub = _radarRepo.watchActiveSessions().listen((sessions) async {
      if (!mounted) return;
      final List<GoRadarSession> filtered = sessions.where((s) {
        if (s.companyId != _selectedCompany!.id) return false;
        if (s.departure != _selectedDeparture) return false;
        if (s.arrival != _selectedArrival) return false;
        if (!s.scheduledTime.startsWith(hourPrefix)) return false;
        return true;
      }).toList();

      setState(() => _sessions = filtered);
      await _refreshMapOverlays(filtered);
    });
  }

  // ── Overlays map ─────────────────────────────────────────────────────────────

  Future<void> _refreshMapOverlays(List<GoRadarSession> sessions) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    for (final GoRadarSession session in sessions) {
      final double? busLat = session.lastLat ?? session.departureLat;
      final double? busLng = session.lastLng ?? session.departureLng;

      if (busLat != null && busLng != null) {
        markers.add(Marker(
          markerId: MarkerId(session.id),
          position: LatLng(busLat, busLng),
          icon: _busIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '${session.departure} → ${session.arrival}',
            snippet:
                '${session.status.label}  •  ${session.availableSeats} place(s)  •  Départ ${session.slotNumber}',
          ),
        ));
      }

      if (session.departureLat != null &&
          session.departureLng != null &&
          session.arrivalLat != null &&
          session.arrivalLng != null) {
        final String cacheKey =
            '${session.departureLat},${session.departureLng}'
            '-${session.arrivalLat},${session.arrivalLng}';

        if (!_routeCache.containsKey(cacheKey)) {
          final RouteResult result = await _routeService.fetchRoute(
            pickupLat: session.departureLat!,
            pickupLng: session.departureLng!,
            deliveryLat: session.arrivalLat!,
            deliveryLng: session.arrivalLng!,
          );
          _routeCache[cacheKey] = result.points;
        }

        final List<LatLng> fullRoute = _routeCache[cacheKey] ?? [];
        if (fullRoute.isNotEmpty && busLat != null && busLng != null) {
          final int splitIdx =
              _nearestPointIndex(fullRoute, LatLng(busLat, busLng));

          if (splitIdx > 0) {
            polylines.add(Polyline(
              polylineId: PolylineId('${session.id}_done'),
              points: fullRoute.sublist(0, splitIdx + 1),
              color: Colors.grey.shade400,
              width: 4,
              zIndex: 1,
            ));
          }
          if (splitIdx < fullRoute.length - 1) {
            polylines.add(Polyline(
              polylineId: PolylineId('${session.id}_remaining'),
              points: fullRoute.sublist(splitIdx),
              color: _accent,
              width: 5,
              zIndex: 2,
            ));
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    // Centre la caméra sur les résultats
    if (markers.isNotEmpty && _mapController != null) {
      final List<LatLng> positions =
          markers.map((m) => m.position).toList();
      if (positions.length == 1) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(positions.first, 11),
        );
      } else {
        double minLat = positions.first.latitude;
        double maxLat = positions.first.latitude;
        double minLng = positions.first.longitude;
        double maxLng = positions.first.longitude;
        for (final p in positions) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat - 0.05, minLng - 0.05),
              northeast: LatLng(maxLat + 0.05, maxLng + 0.05),
            ),
            80,
          ),
        );
      }
    }
  }

  int _nearestPointIndex(List<LatLng> points, LatLng target) {
    int nearestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < points.length; i++) {
      final double d = Geolocator.distanceBetween(
        target.latitude,
        target.longitude,
        points[i].latitude,
        points[i].longitude,
      );
      if (d < minDist) {
        minDist = d;
        nearestIdx = i;
      }
    }
    return nearestIdx;
  }

  // ── GPS ───────────────────────────────────────────────────────────────────────

  Future<void> _goToMyLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
            LatLng(pos.latitude, pos.longitude), 13),
      );
    } catch (_) {}
  }

  void _onSessionTap(GoRadarSession session) {
    final double? lat = session.lastLat ?? session.departureLat;
    final double? lng = session.lastLng ?? session.departureLng;
    if (lat != null && lng != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 14),
      );
      _mapController?.showMarkerInfoWindow(MarkerId(session.id));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool hasResults = _sessions.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran ────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _kDefaultCenter,
              zoom: 10,
            ),
            onMapCreated: (ctrl) => _mapController = ctrl,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Bouton retour ────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _MapIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Titre ────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentDark,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'GO Radar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasResults) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_sessions.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Bouton ma position ───────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _MapIconButton(
              icon: Icons.my_location_rounded,
              onTap: _goToMyLocation,
            ),
          ),

          // ── Sheet 2 : résultats (draggable, apparaît si résultats) ──
          if (hasResults)
            DraggableScrollableSheet(
              initialChildSize: 0.38,
              minChildSize: 0.12,
              maxChildSize: 0.70,
              builder: (_, scrollController) {
                return _ResultsSheet(
                  scrollController: scrollController,
                  sessions: _sessions,
                  onSessionTap: _onSessionTap,
                );
              },
            ),

          // ── Sheet 1 : filtres (fixe en bas) ─────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _FiltersPanel(
              companies: _companies,
              loadingCompanies: _loadingCompanies,
              selectedCompany: _selectedCompany,
              onCompanySelected: _onCompanySelected,
              departures: _departures,
              loadingDepartures: _loadingDepartures,
              selectedDeparture: _selectedDeparture,
              onDepartureSelected: _onDepartureSelected,
              arrivals: _arrivals,
              loadingArrivals: _loadingArrivals,
              selectedArrival: _selectedArrival,
              onArrivalSelected: _onArrivalSelected,
              selectedHour: _selectedHour,
              onHourSelected: _onHourSelected,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sheet 1 : Filtres ────────────────────────────────────────────────────────

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.companies,
    required this.loadingCompanies,
    required this.selectedCompany,
    required this.onCompanySelected,
    required this.departures,
    required this.loadingDepartures,
    required this.selectedDeparture,
    required this.onDepartureSelected,
    required this.arrivals,
    required this.loadingArrivals,
    required this.selectedArrival,
    required this.onArrivalSelected,
    required this.selectedHour,
    required this.onHourSelected,
  });

  final List<TransportCompany> companies;
  final bool loadingCompanies;
  final TransportCompany? selectedCompany;
  final void Function(TransportCompany) onCompanySelected;

  final List<String> departures;
  final bool loadingDepartures;
  final String? selectedDeparture;
  final void Function(String) onDepartureSelected;

  final List<String> arrivals;
  final bool loadingArrivals;
  final String? selectedArrival;
  final void Function(String) onArrivalSelected;

  final String? selectedHour;
  final void Function(String) onHourSelected;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(0, 10, 0, bottomPad + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée décorative
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Compagnies ─────────────────────────────────────────────
          _FilterRow(
            label: 'Compagnie',
            loading: loadingCompanies,
            isEmpty: companies.isEmpty && !loadingCompanies,
            emptyText: 'Aucune compagnie',
            child: Row(
              children: companies.map((c) {
                final bool sel = c.id == selectedCompany?.id;
                return _Chip(
                  label: c.name,
                  selected: sel,
                  onTap: () => onCompanySelected(c),
                );
              }).toList(),
            ),
          ),

          // ── Départs (si compagnie sélectionnée) ────────────────────
          if (selectedCompany != null)
            _FilterRow(
              label: 'Départ',
              loading: loadingDepartures,
              isEmpty: departures.isEmpty && !loadingDepartures,
              emptyText: 'Aucun trajet',
              child: Row(
                children: departures.map((d) {
                  final bool sel = d == selectedDeparture;
                  return _Chip(
                    label: d,
                    selected: sel,
                    onTap: () => onDepartureSelected(d),
                  );
                }).toList(),
              ),
            ),

          // ── Arrivées (si départ sélectionné) ───────────────────────
          if (selectedDeparture != null)
            _FilterRow(
              label: 'Arrivée',
              loading: loadingArrivals,
              isEmpty: arrivals.isEmpty && !loadingArrivals,
              emptyText: 'Aucune arrivée',
              child: Row(
                children: arrivals.map((a) {
                  final bool sel = a == selectedArrival;
                  return _Chip(
                    label: a,
                    selected: sel,
                    onTap: () => onArrivalSelected(a),
                  );
                }).toList(),
              ),
            ),

          // ── Créneaux horaires (si arrivée sélectionnée) ────────────
          if (selectedArrival != null)
            _FilterRow(
              label: 'Heure',
              loading: false,
              isEmpty: false,
              emptyText: '',
              child: Row(
                children: _kTimeSlots.map((h) {
                  final bool sel = h == selectedHour;
                  return _Chip(
                    label: h,
                    selected: sel,
                    onTap: () => onHourSelected(h),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.loading,
    required this.isEmpty,
    required this.emptyText,
    required this.child,
  });

  final String label;
  final bool loading;
  final bool isEmpty;
  final String emptyText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    color: _accent, strokeWidth: 2),
              ),
            )
          else if (isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                emptyText,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade400),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(right: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _accentDark : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ─── Sheet 2 : Résultats ──────────────────────────────────────────────────────

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({
    required this.scrollController,
    required this.sessions,
    required this.onSessionTap,
  });

  final ScrollController scrollController;
  final List<GoRadarSession> sessions;
  final void Function(GoRadarSession) onSessionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          // Poignée
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.directions_bus_rounded,
                    color: _accentDark, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Bus en direct',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${sessions.length} trouvé${sessions.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _accentDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Légende polyline
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Container(
                    width: 24,
                    height: 4,
                    color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text('Trajet effectué',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(width: 16),
                Container(width: 24, height: 4, color: _accent),
                const SizedBox(width: 6),
                Text('Trajet restant',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),

          // Cartes sessions
          ...sessions.map(
            (s) => _SessionCard(
                session: s, onTap: () => onSessionTap(s)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Carte session ────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final GoRadarSession session;
  final VoidCallback onTap;

  static Color _statusColor(GoRadarStatus s) => switch (s) {
        GoRadarStatus.chargement => Colors.orange,
        GoRadarStatus.enRoute => _accentDark,
        GoRadarStatus.arrive => Colors.blue.shade600,
        GoRadarStatus.termine => Colors.grey,
      };

  String _updatedAgo() {
    final Duration diff =
        DateTime.now().difference(session.lastUpdatedAt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return 'il y a ${diff.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _statusColor(session.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.companyName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        session.status.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.trip_origin_rounded,
                    size: 14, color: _accent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    session.departure,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    session.arrival,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  session.scheduledTime,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(width: 10),
                Icon(Icons.confirmation_number_outlined,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Départ ${session.slotNumber}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
                const Spacer(),
                Icon(Icons.event_seat_outlined,
                    size: 13, color: _accentDark),
                const SizedBox(width: 3),
                Text(
                  '${session.availableSeats} pl.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _accentDark,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _updatedAgo(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bouton flottant map ──────────────────────────────────────────────────────

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({required this.icon, required this.onTap});

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: _accentDark),
      ),
    );
  }
}
