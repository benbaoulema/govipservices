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

const LatLng _kDefaultCenter = LatLng(4.0511, 9.7679);

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

  // ── Filtres ─────────────────────────────────────────────────────────────────
  List<TransportCompany> _companies = [];
  TransportCompany? _selectedCompany;

  List<String> _departures = [];
  String? _selectedDeparture;

  List<String> _arrivals = [];
  String? _selectedArrival;

  String? _selectedHour;

  bool _loadingCompanies = true;
  bool _loadingDepartures = false;
  bool _loadingArrivals = false;

  // ── Sessions ─────────────────────────────────────────────────────────────────
  StreamSubscription<List<GoRadarSession>>? _sessionsSub;
  List<GoRadarSession> _sessions = [];

  // ── Map ──────────────────────────────────────────────────────────────────────
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

  // ── Icône bus ─────────────────────────────────────────────────────────────────

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

  // ── Données ──────────────────────────────────────────────────────────────────

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

  Future<void> _onCompanySelected(TransportCompany company) async {
    final bool same = company.id == _selectedCompany?.id;
    setState(() {
      _selectedCompany = same ? null : company;
      _selectedDeparture = null;
      _selectedArrival = null;
      _selectedHour = null;
      _departures = [];
      _arrivals = [];
      _loadingDepartures = !same;
    });
    _cancelStream();
    if (same) return;

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
      setState(() {
        _departures = places.toList()..sort();
        _loadingDepartures = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDepartures = false);
    }
  }

  Future<void> _onDepartureSelected(String dep) async {
    final bool same = dep == _selectedDeparture;
    setState(() {
      _selectedDeparture = same ? null : dep;
      _selectedArrival = null;
      _selectedHour = null;
      _arrivals = [];
      _loadingArrivals = !same;
    });
    _cancelStream();
    if (same) return;

    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore
          .instance
          .collection('voyageTrips')
          .where('companyId', isEqualTo: _selectedCompany!.id)
          .where('departurePlace', isEqualTo: dep)
          .get();
      final Set<String> places = snap.docs
          .map((d) => (d.data()['arrivalPlace'] as String? ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _arrivals = places.toList()..sort();
        _loadingArrivals = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingArrivals = false);
    }
  }

  void _onArrivalSelected(String arr) {
    final bool same = arr == _selectedArrival;
    setState(() {
      _selectedArrival = same ? null : arr;
      _selectedHour = null;
    });
    _cancelStream();
  }

  void _onHourSelected(String hour) {
    final bool same = hour == _selectedHour;
    setState(() => _selectedHour = same ? null : hour);
    if (!same) {
      _startStream();
    } else {
      _cancelStream();
    }
  }

  // ── Stream sessions ───────────────────────────────────────────────────────────

  void _cancelStream() {
    _sessionsSub?.cancel();
    _sessionsSub = null;
    setState(() {
      _sessions = [];
      _markers = {};
      _polylines = {};
    });
  }

  void _startStream() {
    _sessionsSub?.cancel();
    if (_selectedCompany == null ||
        _selectedDeparture == null ||
        _selectedArrival == null ||
        _selectedHour == null) return;

    final String hourPrefix = _selectedHour!.replaceAll('h', '');

    _sessionsSub = _radarRepo.watchActiveSessions().listen((all) async {
      if (!mounted) return;
      final List<GoRadarSession> filtered = all.where((s) {
        if (s.companyId != _selectedCompany!.id) return false;
        if (s.departure != _selectedDeparture) return false;
        if (s.arrival != _selectedArrival) return false;
        if (!s.scheduledTime.startsWith(hourPrefix)) return false;
        return true;
      }).toList();
      setState(() => _sessions = filtered);
      await _refreshMap(filtered);
    });
  }

  // ── Map overlays ──────────────────────────────────────────────────────────────

  Future<void> _refreshMap(List<GoRadarSession> sessions) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    for (final GoRadarSession s in sessions) {
      final double? busLat = s.lastLat ?? s.departureLat;
      final double? busLng = s.lastLng ?? s.departureLng;

      if (busLat != null && busLng != null) {
        markers.add(Marker(
          markerId: MarkerId(s.id),
          position: LatLng(busLat, busLng),
          icon: _busIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '${s.departure} → ${s.arrival}',
            snippet:
                '${s.status.label}  •  ${s.availableSeats} place(s)  •  Dép. ${s.slotNumber}',
          ),
        ));
      }

      if (s.departureLat != null &&
          s.departureLng != null &&
          s.arrivalLat != null &&
          s.arrivalLng != null) {
        final String key =
            '${s.departureLat},${s.departureLng}-${s.arrivalLat},${s.arrivalLng}';
        if (!_routeCache.containsKey(key)) {
          final RouteResult r = await _routeService.fetchRoute(
            pickupLat: s.departureLat!,
            pickupLng: s.departureLng!,
            deliveryLat: s.arrivalLat!,
            deliveryLng: s.arrivalLng!,
          );
          _routeCache[key] = r.points;
        }

        final List<LatLng> full = _routeCache[key] ?? [];
        if (full.isNotEmpty && busLat != null && busLng != null) {
          final int idx =
              _nearestIdx(full, LatLng(busLat, busLng));
          if (idx > 0) {
            polylines.add(Polyline(
              polylineId: PolylineId('${s.id}_done'),
              points: full.sublist(0, idx + 1),
              color: Colors.grey.shade400,
              width: 4,
              zIndex: 1,
            ));
          }
          if (idx < full.length - 1) {
            polylines.add(Polyline(
              polylineId: PolylineId('${s.id}_remaining'),
              points: full.sublist(idx),
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

    if (markers.isNotEmpty && _mapController != null) {
      _fitBounds(markers.map((m) => m.position).toList());
    }
  }

  void _fitBounds(List<LatLng> positions) {
    if (positions.length == 1) {
      _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(positions.first, 12));
      return;
    }
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
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.05, minLng - 0.05),
        northeast: LatLng(maxLat + 0.05, maxLng + 0.05),
      ),
      80,
    ));
  }

  int _nearestIdx(List<LatLng> pts, LatLng target) {
    int best = 0;
    double minD = double.infinity;
    for (int i = 0; i < pts.length; i++) {
      final double d = Geolocator.distanceBetween(
          target.latitude, target.longitude,
          pts[i].latitude, pts[i].longitude);
      if (d < minD) {
        minD = d;
        best = i;
      }
    }
    return best;
  }

  // ── GPS ────────────────────────────────────────────────────────────────────

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

  void _onSessionTap(GoRadarSession s) {
    final double? lat = s.lastLat ?? s.departureLat;
    final double? lng = s.lastLng ?? s.departureLng;
    if (lat != null && lng != null) {
      _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 14));
      _mapController?.showMarkerInfoWindow(MarkerId(s.id));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition:
                const CameraPosition(target: _kDefaultCenter, zoom: 10),
            onMapCreated: (c) => _mapController = c,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Bouton retour ───────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _MapBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).pop()),
          ),

          // ── Titre ───────────────────────────────────────────────────
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
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    const Text('GO Radar',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if (_sessions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${_sessions.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Bouton ma position ──────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _MapBtn(
                icon: Icons.my_location_rounded,
                onTap: _goToMyLocation),
          ),

          // ── Sheet résultats (par-dessus le sheet filtres) ───────────
          if (_sessions.isNotEmpty)
            DraggableScrollableSheet(
              initialChildSize: 0.40,
              minChildSize: 0.10,
              maxChildSize: 0.72,
              builder: (_, sc) => _ResultsSheet(
                scrollController: sc,
                sessions: _sessions,
                onSessionTap: _onSessionTap,
              ),
            ),

          // ── Sheet filtres ───────────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.52,
            minChildSize: 0.10,
            maxChildSize: 0.88,
            builder: (_, sc) => _FiltersSheet(
              scrollController: sc,
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

// ─── Sheet filtres ────────────────────────────────────────────────────────────

class _FiltersSheet extends StatelessWidget {
  const _FiltersSheet({
    required this.scrollController,
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

  final ScrollController scrollController;
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
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, -6))
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          // Poignée
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Titre sheet
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    color: _accentDark, size: 20),
                const SizedBox(width: 8),
                const Text('Rechercher un voyage',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A))),
              ],
            ),
          ),

          // ── Compagnies ─────────────────────────────────────────────
          _SectionLabel(label: 'Compagnie'),
          if (loadingCompanies)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2)),
            )
          else
            _CompanyRow(
              companies: companies,
              selectedId: selectedCompany?.id,
              onSelect: onCompanySelected,
            ),

          const SizedBox(height: 16),

          // ── Départs ────────────────────────────────────────────────
          _SectionLabel(label: 'Ville de départ'),
          _CityRow(
            cities: departures,
            loading: loadingDepartures,
            selected: selectedDeparture,
            emptyText: selectedCompany == null
                ? 'Sélectionnez une compagnie'
                : 'Aucun trajet disponible',
            onSelect: onDepartureSelected,
          ),

          const SizedBox(height: 16),

          // ── Arrivées ────────────────────────────────────────────────
          _SectionLabel(label: "Ville d'arrivée"),
          _CityRow(
            cities: arrivals,
            loading: loadingArrivals,
            selected: selectedArrival,
            emptyText: selectedDeparture == null
                ? 'Sélectionnez un départ'
                : 'Aucune arrivée disponible',
            onSelect: onArrivalSelected,
          ),

          const SizedBox(height: 16),

          // ── Horaires ────────────────────────────────────────────────
          _SectionLabel(label: 'Heure de départ'),
          _TimeRow(
            selected: selectedHour,
            enabled: selectedArrival != null,
            onSelect: onHourSelected,
          ),

          SizedBox(
              height:
                  MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

// ─── Composants filtres ───────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade400,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// Cartes compagnies (style book_trip_page)
class _CompanyRow extends StatelessWidget {
  const _CompanyRow({
    required this.companies,
    required this.selectedId,
    required this.onSelect,
  });

  final List<TransportCompany> companies;
  final String? selectedId;
  final void Function(TransportCompany) onSelect;

  @override
  Widget build(BuildContext context) {
    if (companies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text('Aucune compagnie',
            style:
                TextStyle(fontSize: 13, color: Colors.grey.shade400)),
      );
    }
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: companies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final TransportCompany c = companies[i];
          final bool sel = c.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel ? _accent : const Color(0xFFD8F3EE),
                  width: sel ? 2.5 : 1.5,
                ),
                color: sel
                    ? _accent.withValues(alpha: 0.07)
                    : Colors.white,
                boxShadow: sel
                    ? [
                        BoxShadow(
                            color: _accent.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (c.imageUrl != null)
                      Image.network(
                        c.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    // Gradient overlay si image
                    if (c.imageUrl != null)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black
                                  .withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    // Nom compagnie
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: Text(
                          c.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.imageUrl != null
                                ? Colors.white
                                : (sel
                                    ? _accentDark
                                    : const Color(0xFF0F172A)),
                            shadows: c.imageUrl != null
                                ? const [
                                    Shadow(
                                        blurRadius: 4,
                                        color: Colors.black54)
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    // Check sélection
                    if (sel)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle),
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

// Villes départ / arrivée
class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.cities,
    required this.loading,
    required this.selected,
    required this.emptyText,
    required this.onSelect,
  });

  final List<String> cities;
  final bool loading;
  final String? selected;
  final String emptyText;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: _accent, strokeWidth: 2)),
      );
    }
    if (cities.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Text(emptyText,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic)),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: cities.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final String city = cities[i];
          final bool sel = city == selected;
          return GestureDetector(
            onTap: () => onSelect(city),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _accentDark : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                city,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel
                      ? Colors.white
                      : const Color(0xFF334155),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Créneaux horaires
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final String? selected;
  final bool enabled;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Text("Sélectionnez une arrivée d'abord",
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic)),
      );
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _kTimeSlots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final String h = _kTimeSlots[i];
          final bool sel = h == selected;
          return GestureDetector(
            onTap: () => onSelect(h),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _accentDark : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                h,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel
                      ? Colors.white
                      : const Color(0xFF475569),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Sheet résultats ──────────────────────────────────────────────────────────

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
        color: Color(0xFFF0FDFB),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
              color: Color(0x20000000),
              blurRadius: 20,
              offset: Offset(0, -4))
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.directions_bus_rounded,
                    color: _accentDark, size: 20),
                const SizedBox(width: 8),
                const Text('Bus en direct',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A))),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${sessions.length} trouvé${sessions.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accentDark),
                  ),
                ),
              ],
            ),
          ),
          // Légende polyline
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Container(
                    width: 24, height: 4, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text('Trajet effectué',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(width: 16),
                Container(width: 24, height: 4, color: _accent),
                const SizedBox(width: 6),
                Text('Restant',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          ...sessions.map((s) =>
              _SessionCard(session: s, onTap: () => onSessionTap(s))),
          const SizedBox(height: 32),
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

  String _ago() {
    final Duration d =
        DateTime.now().difference(session.lastUpdatedAt);
    if (d.inMinutes < 1) return 'À l\'instant';
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    return 'il y a ${d.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final Color sc = _statusColor(session.status);
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
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(session.companyName,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: sc, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(session.status.label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: sc)),
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
                    child: Text(session.departure,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(session.arrival,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(session.scheduledTime,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(width: 10),
                Text('Départ ${session.slotNumber}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                const Spacer(),
                Icon(Icons.event_seat_outlined,
                    size: 13, color: _accentDark),
                const SizedBox(width: 3),
                Text('${session.availableSeats} pl.',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accentDark)),
                const SizedBox(width: 10),
                Text(_ago(),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bouton flottant map ──────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  const _MapBtn({required this.icon, required this.onTap});

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
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, size: 20, color: _accentDark),
      ),
    );
  }
}
