import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/parcels/data/parcel_route_preview_service.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _surface = Color(0xFFFFFFFF);

// Centre par défaut : Douala, Cameroun
const LatLng _kDefaultCenter = LatLng(4.0511, 9.7679);

// ─── Page ─────────────────────────────────────────────────────────────────────

class GoRadarMapPage extends StatefulWidget {
  const GoRadarMapPage({super.key});

  @override
  State<GoRadarMapPage> createState() => _GoRadarMapPageState();
}

class _GoRadarMapPageState extends State<GoRadarMapPage> {
  final GoRadarRepository _repo = GoRadarRepository();
  late final ParcelRoutePreviewService _routeService;

  GoogleMapController? _mapController;
  StreamSubscription<List<GoRadarSession>>? _sessionsSub;

  List<GoRadarSession> _allSessions = [];
  final Map<String, List<LatLng>> _routeCache = {};
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _busIcon;

  // Filtres actifs
  String? _selectedCompany;
  String? _selectedDeparture;
  String? _selectedArrival;
  String? _selectedTime;

  @override
  void initState() {
    super.initState();
    _routeService = ParcelRoutePreviewService(
      apiKey: RuntimeAppConfig.googleMapsApiKey,
    );
    _loadBusIcon();
    _listenSessions();
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

  Future<BitmapDescriptor> _emojiToBitmap(String emoji, double fontSize) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final TextPainter tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(text: emoji, style: TextStyle(fontSize: fontSize))
      ..layout();
    tp.paint(canvas, Offset.zero);
    final ui.Image img =
        await recorder.endRecording().toImage(tp.width.ceil(), tp.height.ceil());
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  // ── Stream sessions ──────────────────────────────────────────────────────────

  void _listenSessions() {
    _sessionsSub = _repo.watchActiveSessions().listen((sessions) async {
      if (!mounted) return;
      setState(() => _allSessions = sessions);
      await _refreshMapOverlays();
    });
  }

  // ── Filtres ──────────────────────────────────────────────────────────────────

  List<GoRadarSession> get _filteredSessions {
    return _allSessions.where((s) {
      if (_selectedCompany != null && s.companyName != _selectedCompany) {
        return false;
      }
      if (_selectedDeparture != null && s.departure != _selectedDeparture) {
        return false;
      }
      if (_selectedArrival != null && s.arrival != _selectedArrival) {
        return false;
      }
      if (_selectedTime != null && s.scheduledTime != _selectedTime) {
        return false;
      }
      return true;
    }).toList();
  }

  Set<String> get _companies =>
      _allSessions.map((s) => s.companyName).toSet();
  Set<String> get _departures =>
      _allSessions.map((s) => s.departure).toSet();
  Set<String> get _arrivals =>
      _allSessions.map((s) => s.arrival).toSet();
  Set<String> get _times =>
      _allSessions.map((s) => s.scheduledTime).toSet();

  // ── Overlays map ─────────────────────────────────────────────────────────────

  Future<void> _refreshMapOverlays() async {
    final List<GoRadarSession> sessions = _filteredSessions;
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    for (final GoRadarSession session in sessions) {
      final double? busLat = session.lastLat ?? session.departureLat;
      final double? busLng = session.lastLng ?? session.departureLng;

      // Marqueur bus
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

      // Polyline bicolore
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
          final int splitIdx = _nearestPointIndex(
            fullRoute,
            LatLng(busLat, busLng),
          );

          // Segment fait → gris
          if (splitIdx > 0) {
            polylines.add(Polyline(
              polylineId: PolylineId('${session.id}_done'),
              points: fullRoute.sublist(0, splitIdx + 1),
              color: Colors.grey.shade400,
              width: 4,
              zIndex: 1,
            ));
          }

          // Segment restant → teal
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

  // ── Actions ──────────────────────────────────────────────────────────────────

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
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 13),
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

  void _onFilterChanged() {
    setState(() {});
    _refreshMapOverlays();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran ──────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _kDefaultCenter,
              zoom: 12,
            ),
            onMapCreated: (ctrl) => _mapController = ctrl,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Bouton retour ──────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _MapIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Titre flottant ─────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                    if (_filteredSessions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_filteredSessions.length}',
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

          // ── Bouton ma position ─────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _MapIconButton(
              icon: Icons.my_location_rounded,
              onTap: _goToMyLocation,
            ),
          ),

          // ── Sheet draggable ────────────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.12,
            maxChildSize: 0.75,
            builder: (_, scrollController) {
              return _GoRadarSheet(
                scrollController: scrollController,
                sessions: _filteredSessions,
                companies: _companies,
                departures: _departures,
                arrivals: _arrivals,
                times: _times,
                selectedCompany: _selectedCompany,
                selectedDeparture: _selectedDeparture,
                selectedArrival: _selectedArrival,
                selectedTime: _selectedTime,
                onCompanySelected: (v) {
                  setState(() => _selectedCompany =
                      _selectedCompany == v ? null : v);
                  _onFilterChanged();
                },
                onDepartureSelected: (v) {
                  setState(() => _selectedDeparture =
                      _selectedDeparture == v ? null : v);
                  _onFilterChanged();
                },
                onArrivalSelected: (v) {
                  setState(
                      () => _selectedArrival =
                          _selectedArrival == v ? null : v);
                  _onFilterChanged();
                },
                onTimeSelected: (v) {
                  setState(
                      () => _selectedTime =
                          _selectedTime == v ? null : v);
                  _onFilterChanged();
                },
                onSessionTap: _onSessionTap,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

class _GoRadarSheet extends StatelessWidget {
  const _GoRadarSheet({
    required this.scrollController,
    required this.sessions,
    required this.companies,
    required this.departures,
    required this.arrivals,
    required this.times,
    required this.selectedCompany,
    required this.selectedDeparture,
    required this.selectedArrival,
    required this.selectedTime,
    required this.onCompanySelected,
    required this.onDepartureSelected,
    required this.onArrivalSelected,
    required this.onTimeSelected,
    required this.onSessionTap,
  });

  final ScrollController scrollController;
  final List<GoRadarSession> sessions;
  final Set<String> companies;
  final Set<String> departures;
  final Set<String> arrivals;
  final Set<String> times;
  final String? selectedCompany;
  final String? selectedDeparture;
  final String? selectedArrival;
  final String? selectedTime;
  final void Function(String) onCompanySelected;
  final void Function(String) onDepartureSelected;
  final void Function(String) onArrivalSelected;
  final void Function(String) onTimeSelected;
  final void Function(GoRadarSession) onSessionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
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
          // ── Poignée ────────────────────────────────────────────────────
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

          // ── En-tête ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.directions_bus_rounded,
                    color: _accentDark, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Voyages en direct',
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
                    color: sessions.isEmpty
                        ? Colors.grey.shade100
                        : _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    sessions.isEmpty
                        ? 'Aucun'
                        : '${sessions.length} bus',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sessions.isEmpty
                          ? Colors.grey.shade500
                          : _accentDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filtres ────────────────────────────────────────────────────
          if (companies.isNotEmpty)
            _FilterChipRow(
              label: 'Compagnie',
              values: companies.toList()..sort(),
              selected: selectedCompany,
              onSelect: onCompanySelected,
            ),
          if (departures.isNotEmpty)
            _FilterChipRow(
              label: 'Départ',
              values: departures.toList()..sort(),
              selected: selectedDeparture,
              onSelect: onDepartureSelected,
            ),
          if (arrivals.isNotEmpty)
            _FilterChipRow(
              label: 'Arrivée',
              values: arrivals.toList()..sort(),
              selected: selectedArrival,
              onSelect: onArrivalSelected,
            ),
          if (times.isNotEmpty)
            _FilterChipRow(
              label: 'Horaire',
              values: times.toList()..sort(),
              selected: selectedTime,
              onSelect: onTimeSelected,
            ),

          const SizedBox(height: 8),

          // ── Liste sessions ─────────────────────────────────────────────
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.radar_rounded,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Aucun voyage en direct',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Les reporters actifs apparaissent ici',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            )
          else
            ...sessions.map(
              (s) => _SessionCard(session: s, onTap: () => onSessionTap(s)),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Ligne de filtres ─────────────────────────────────────────────────────────

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final List<String> values;
  final String? selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: values.map((v) {
                  final bool sel = v == selected;
                  return GestureDetector(
                    onTap: () => onSelect(v),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? _accentDark
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        v,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              sel ? Colors.white : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
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
    final Duration diff = DateTime.now().difference(session.lastUpdatedAt);
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
            // ── Ligne 1 : Compagnie + statut ──────────────────────────
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

            // ── Ligne 2 : Trajet ───────────────────────────────────────
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // ── Ligne 3 : Infos secondaires ────────────────────────────
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  session.scheduledTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.confirmation_number_outlined,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Départ ${session.slotNumber}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
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

// ─── Bouton flottant sur la map ───────────────────────────────────────────────

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
