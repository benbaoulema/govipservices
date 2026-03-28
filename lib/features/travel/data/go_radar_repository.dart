import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

const double _kGoRadarRadiusKm = 5;

enum GoRadarStatus {
  chargement,
  chargementEnCours,
  enRoute,
  termine;

  String get label => switch (this) {
        GoRadarStatus.chargement => 'Chargement non débuté',
        GoRadarStatus.chargementEnCours => 'Chargement en cours',
        GoRadarStatus.enRoute => 'En route',
        GoRadarStatus.termine => 'Termine',
      };

  String get value => switch (this) {
        GoRadarStatus.chargement => 'chargement',
        GoRadarStatus.chargementEnCours => 'chargement_en_cours',
        GoRadarStatus.enRoute => 'en_route',
        GoRadarStatus.termine => 'termine',
      };

  static GoRadarStatus fromValue(String v) => switch (v) {
        'chargement_en_cours' => GoRadarStatus.chargementEnCours,
        'en_route' => GoRadarStatus.enRoute,
        'termine' => GoRadarStatus.termine,
        _ => GoRadarStatus.chargement,
      };
}

class GoRadarException implements Exception {
  const GoRadarException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoRadarSessionArgs {
  const GoRadarSessionArgs({
    required this.tripId,
    required this.companyId,
    required this.companyName,
    required this.departure,
    required this.arrival,
    required this.scheduledTime,
    required this.slotNumber,
    required this.date,
    this.departureLat,
    this.departureLng,
    this.arrivalLat,
    this.arrivalLng,
  });

  final String tripId;
  final String companyId;
  final String companyName;
  final String departure;
  final String arrival;
  final String scheduledTime;
  final int slotNumber;
  final String date;
  final double? departureLat;
  final double? departureLng;
  final double? arrivalLat;
  final double? arrivalLng;

  factory GoRadarSessionArgs.fromSession(GoRadarSession session) {
    return GoRadarSessionArgs(
      tripId: session.tripId,
      companyId: session.companyId,
      companyName: session.companyName,
      departure: session.departure,
      arrival: session.arrival,
      scheduledTime: session.scheduledTime,
      slotNumber: session.slotNumber,
      date: session.date,
      departureLat: session.departureLat,
      departureLng: session.departureLng,
      arrivalLat: session.arrivalLat,
      arrivalLng: session.arrivalLng,
    );
  }
}

class GoRadarSession {
  const GoRadarSession({
    required this.id,
    required this.tripId,
    required this.companyId,
    required this.companyName,
    required this.departure,
    required this.arrival,
    required this.scheduledTime,
    required this.slotNumber,
    required this.date,
    required this.status,
    required this.availableSeats,
    required this.reporterUid,
    required this.lastUpdatedAt,
    this.departureLat,
    this.departureLng,
    this.arrivalLat,
    this.arrivalLng,
    this.lastLat,
    this.lastLng,
    this.departureRealTime,
    this.nextEstimatedCity,
    this.nextEstimatedDuration,
  });

  final String id;
  final String tripId;
  final String companyId;
  final String companyName;
  final String departure;
  final String arrival;
  final String scheduledTime;
  final int slotNumber;
  final String date;
  final GoRadarStatus status;
  final int availableSeats;
  final String reporterUid;
  final DateTime lastUpdatedAt;
  final double? departureLat;
  final double? departureLng;
  final double? arrivalLat;
  final double? arrivalLng;
  final double? lastLat;
  final double? lastLng;
  final String? departureRealTime;
  final String? nextEstimatedCity;
  final String? nextEstimatedDuration;

  factory GoRadarSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return GoRadarSession(
      id: doc.id,
      tripId: d['tripId'] as String? ?? '',
      companyId: d['companyId'] as String? ?? '',
      companyName: d['companyName'] as String? ?? '',
      departure: d['departure'] as String? ?? '',
      arrival: d['arrival'] as String? ?? '',
      scheduledTime: d['scheduledTime'] as String? ?? '',
      slotNumber: (d['slotNumber'] as num?)?.toInt() ?? 1,
      date: d['date'] as String? ?? '',
      status: GoRadarStatus.fromValue(d['status'] as String? ?? ''),
      availableSeats: (d['availableSeats'] as num?)?.toInt() ?? 0,
      reporterUid: d['reporterUid'] as String? ?? '',
      lastUpdatedAt:
          (d['lastUpdatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      departureLat: (d['departureLat'] as num?)?.toDouble(),
      departureLng: (d['departureLng'] as num?)?.toDouble(),
      arrivalLat: (d['arrivalLat'] as num?)?.toDouble(),
      arrivalLng: (d['arrivalLng'] as num?)?.toDouble(),
      lastLat: (d['lastLat'] as num?)?.toDouble(),
      lastLng: (d['lastLng'] as num?)?.toDouble(),
      departureRealTime: d['departureRealTime'] as String?,
      nextEstimatedCity: d['nextEstimatedCity'] as String?,
      nextEstimatedDuration: d['nextEstimatedDuration'] as String?,
    );
  }
}

class GoRadarStop {
  const GoRadarStop({
    required this.address,
    required this.lat,
    required this.lng,
    this.estimatedTime,
  });

  final String address;
  final double lat;
  final double lng;
  final String? estimatedTime;
}

class _GoRadarPoint {
  const _GoRadarPoint({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;
}

class GoRadarRepository {
  GoRadarRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection('goRadarSessions');

  String get todayKey {
    final DateTime now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<GoRadarSession?> fetchMyActiveSession({String? date}) async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return null;

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _sessions
        .where('reporterUid', isEqualTo: uid)
        .where('date', isEqualTo: date ?? todayKey)
        .limit(10)
        .get();

    final List<GoRadarSession> sessions = snapshot.docs
        .map(GoRadarSession.fromDoc)
        .where((session) => session.status != GoRadarStatus.termine)
        .toList()
      ..sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));

    return sessions.isEmpty ? null : sessions.first;
  }

  Future<Set<String>> fetchTakenSlotIds({
    required String companyId,
    required String departure,
    required String arrival,
    required String date,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _sessions
        .where('companyId', isEqualTo: companyId)
        .where('departure', isEqualTo: departure)
        .where('arrival', isEqualTo: arrival)
        .where('date', isEqualTo: date)
        .get();

    return snapshot.docs
        .map(GoRadarSession.fromDoc)
        .map((session) => '${session.tripId}_slot${session.slotNumber}')
        .toSet();
  }

  Future<GoRadarSession> openSession(
    GoRadarSessionArgs args, {
    required double reporterLat,
    required double reporterLng,
    double maxDistanceKm = _kGoRadarRadiusKm,
  }) async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw const GoRadarException(
        'Connexion requise pour ouvrir une session GO Radar.',
      );
    }

    final GoRadarSession? activeSession = await fetchMyActiveSession(date: args.date);
    if (activeSession != null) {
      final bool isSameSlot = activeSession.tripId == args.tripId &&
          activeSession.slotNumber == args.slotNumber &&
          activeSession.date == args.date;
      if (!isSameSlot) {
        throw const GoRadarException(
          'Vous avez deja une session GO Radar active aujourd\'hui.',
        );
      }
      return activeSession;
    }

    final QuerySnapshot<Map<String, dynamic>> existing = await _sessions
        .where('tripId', isEqualTo: args.tripId)
        .where('slotNumber', isEqualTo: args.slotNumber)
        .where('date', isEqualTo: args.date)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final GoRadarSession session = GoRadarSession.fromDoc(existing.docs.first);
      if (session.reporterUid == uid && session.status != GoRadarStatus.termine) {
        return session;
      }
      throw const GoRadarException(
        'Ce depart a deja un reporter pour aujourd\'hui.',
      );
    }

    final _GoRadarPoint departurePoint = await _resolveTripPoint(
      tripId: args.tripId,
      fallbackName: args.departure,
      latField: 'departureLat',
      lngField: 'departureLng',
      rawLat: args.departureLat,
      rawLng: args.departureLng,
    );
    final _GoRadarPoint arrivalPoint = await _resolveTripPoint(
      tripId: args.tripId,
      fallbackName: args.arrival,
      latField: 'arrivalLat',
      lngField: 'arrivalLng',
      rawLat: args.arrivalLat,
      rawLng: args.arrivalLng,
    );

    _ensureWithinRadius(
      target: departurePoint,
      reporterLat: reporterLat,
      reporterLng: reporterLng,
      maxDistanceKm: maxDistanceKm,
      failureMessage:
          'Vous devez etre sur les lieux pour ouvrir cette session.',
    );

    final DocumentReference<Map<String, dynamic>> ref = _sessions.doc();
    final DateTime now = DateTime.now();
    await ref.set(<String, dynamic>{
      'tripId': args.tripId,
      'companyId': args.companyId,
      'companyName': args.companyName,
      'departure': args.departure,
      'arrival': args.arrival,
      'scheduledTime': args.scheduledTime,
      'slotNumber': args.slotNumber,
      'date': args.date,
      'status': GoRadarStatus.chargement.value,
      'availableSeats': 0,
      'reporterUid': uid,
      'departureLat': departurePoint.lat,
      'departureLng': departurePoint.lng,
      'arrivalLat': arrivalPoint.lat,
      'arrivalLng': arrivalPoint.lng,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return GoRadarSession(
      id: ref.id,
      tripId: args.tripId,
      companyId: args.companyId,
      companyName: args.companyName,
      departure: args.departure,
      arrival: args.arrival,
      scheduledTime: args.scheduledTime,
      slotNumber: args.slotNumber,
      date: args.date,
      status: GoRadarStatus.chargement,
      availableSeats: 0,
      reporterUid: uid,
      lastUpdatedAt: now,
      departureLat: departurePoint.lat,
      departureLng: departurePoint.lng,
      arrivalLat: arrivalPoint.lat,
      arrivalLng: arrivalPoint.lng,
    );
  }

  Future<void> ensureCanCompleteSession(
    GoRadarSession session, {
    required double reporterLat,
    required double reporterLng,
    double maxDistanceKm = _kGoRadarRadiusKm,
  }) async {
    final _GoRadarPoint arrivalPoint = await _resolveTripPoint(
      tripId: session.tripId,
      fallbackName: session.arrival,
      latField: 'arrivalLat',
      lngField: 'arrivalLng',
      rawLat: session.arrivalLat,
      rawLng: session.arrivalLng,
    );

    _ensureWithinRadius(
      target: arrivalPoint,
      reporterLat: reporterLat,
      reporterLng: reporterLng,
      maxDistanceKm: maxDistanceKm,
      failureMessage:
          'Vous devez etre sur les lieux pour terminer la session.',
    );
  }

  Future<void> pushUpdate({
    required String sessionId,
    required GoRadarStatus status,
    required int availableSeats,
    double? lat,
    double? lng,
    String? departureRealTime,
    String? nextEstimatedCity,
    String? nextEstimatedDuration,
  }) async {
    final FieldValue now = FieldValue.serverTimestamp();

    final Map<String, dynamic> sessionPatch = <String, dynamic>{
      'status': status.value,
      'availableSeats': availableSeats,
      'lastUpdatedAt': now,
      if (lat != null) 'lastLat': lat,
      if (lng != null) 'lastLng': lng,
      if (departureRealTime != null) 'departureRealTime': departureRealTime,
      if (nextEstimatedCity != null) 'nextEstimatedCity': nextEstimatedCity,
      if (nextEstimatedDuration != null) 'nextEstimatedDuration': nextEstimatedDuration,
    };

    final Map<String, dynamic> historyEntry = <String, dynamic>{
      'status': status.value,
      'availableSeats': availableSeats,
      'updatedAt': now,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };

    final WriteBatch batch = _firestore.batch();
    batch.update(_sessions.doc(sessionId), sessionPatch);
    batch.set(_sessions.doc(sessionId).collection('history').doc(), historyEntry);
    await batch.commit();
  }

  // Enregistre un arrêt effectif (bus s'arrête en route pour prendre des passagers)
  Future<void> recordStop({
    required String sessionId,
    required int availableSeats,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final FieldValue now = FieldValue.serverTimestamp();

    final Map<String, dynamic> stopEntry = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'availableSeats': availableSeats,
      'recordedAt': now,
      if (address != null && address.isNotEmpty) 'address': address,
    };

    final WriteBatch batch = _firestore.batch();
    // Ajoute dans la sous-collection arrets
    batch.set(
      _sessions.doc(sessionId).collection('arrets').doc(),
      stopEntry,
    );
    // Met aussi à jour la position et les places sur la session principale
    batch.update(_sessions.doc(sessionId), <String, dynamic>{
      'lastLat': lat,
      'lastLng': lng,
      'availableSeats': availableSeats,
      'lastUpdatedAt': now,
    });
    await batch.commit();
  }

  Future<void> pushLocationUpdate({
    required String sessionId,
    required double lat,
    required double lng,
  }) async {
    await _sessions.doc(sessionId).update(<String, dynamic>{
      'lastLat': lat,
      'lastLng': lng,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Retourne les arrêts intermédiaires du trip, ordonnés tels que saisis.
  Future<List<GoRadarStop>> fetchIntermediateStops(String tripId) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _firestore.collection('voyageTrips').doc(tripId).get();
    final List<dynamic> raw =
        (snap.data()?['intermediateStops'] as List<dynamic>?) ?? [];
    return raw
        .whereType<Map<String, dynamic>>()
        .where((s) => s['selected'] != false)
        .where((s) => s['lat'] != null && s['lng'] != null)
        .map((s) => GoRadarStop(
              address: s['address'] as String? ?? '',
              lat: (s['lat'] as num).toDouble(),
              lng: (s['lng'] as num).toDouble(),
              estimatedTime: s['estimatedTime'] as String?,
            ))
        .toList();
  }

  Stream<GoRadarSession?> watchSession(String sessionId) {
    return _sessions
        .doc(sessionId)
        .snapshots()
        .map((snap) => snap.exists ? GoRadarSession.fromDoc(snap) : null);
  }

  Stream<List<GoRadarSession>> watchActiveSessions({String? date}) {
    return _sessions
        .where('date', isEqualTo: date ?? todayKey)
        .snapshots()
        .map((snap) => snap.docs
            .map(GoRadarSession.fromDoc)
            .where((s) => s.status != GoRadarStatus.termine)
            .toList());
  }

  Future<_GoRadarPoint> _resolveTripPoint({
    required String tripId,
    required String fallbackName,
    required String latField,
    required String lngField,
    double? rawLat,
    double? rawLng,
  }) async {
    if (rawLat != null && rawLng != null) {
      return _GoRadarPoint(lat: rawLat, lng: rawLng);
    }

    final DocumentSnapshot<Map<String, dynamic>> tripSnapshot =
        await _firestore.collection('voyageTrips').doc(tripId).get();
    final Map<String, dynamic>? raw = tripSnapshot.data();
    final double? tripLat = (raw?[latField] as num?)?.toDouble();
    final double? tripLng = (raw?[lngField] as num?)?.toDouble();
    if (tripLat != null && tripLng != null) {
      return _GoRadarPoint(lat: tripLat, lng: tripLng);
    }

    final List<Location> matches = await locationFromAddress(fallbackName);
    if (matches.isEmpty) {
      throw GoRadarException('Coordonnees introuvables pour $fallbackName.');
    }

    final Location best = matches.first;
    return _GoRadarPoint(lat: best.latitude, lng: best.longitude);
  }

  void _ensureWithinRadius({
    required _GoRadarPoint target,
    required double reporterLat,
    required double reporterLng,
    required double maxDistanceKm,
    required String failureMessage,
  }) {
    if (kDebugMode) return;
    final double distanceMeters = Geolocator.distanceBetween(
      reporterLat,
      reporterLng,
      target.lat,
      target.lng,
    );
    if (distanceMeters > maxDistanceKm * 1000) {
      throw GoRadarException(failureMessage);
    }
  }
}
