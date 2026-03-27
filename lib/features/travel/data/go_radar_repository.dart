import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─── Modèles ──────────────────────────────────────────────────────────────────

enum GoRadarStatus {
  chargement,
  enRoute,
  arrive,
  termine;

  String get label => switch (this) {
        GoRadarStatus.chargement => 'Chargement en cours',
        GoRadarStatus.enRoute => 'En route',
        GoRadarStatus.arrive => 'Arrivé à un arrêt',
        GoRadarStatus.termine => 'Terminé',
      };

  String get value => switch (this) {
        GoRadarStatus.chargement => 'chargement',
        GoRadarStatus.enRoute => 'en_route',
        GoRadarStatus.arrive => 'arrive',
        GoRadarStatus.termine => 'termine',
      };

  static GoRadarStatus fromValue(String v) => switch (v) {
        'en_route' => GoRadarStatus.enRoute,
        'arrive' => GoRadarStatus.arrive,
        'termine' => GoRadarStatus.termine,
        _ => GoRadarStatus.chargement,
      };
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
  });

  final String tripId;
  final String companyId;
  final String companyName;
  final String departure;
  final String arrival;
  final String scheduledTime;
  final int slotNumber;
  final String date;
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
    this.lastLat,
    this.lastLng,
    this.departureRealTime,
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
  final double? lastLat;
  final double? lastLng;
  final String? departureRealTime;

  factory GoRadarSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
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
      lastUpdatedAt: (d['lastUpdatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLat: (d['lastLat'] as num?)?.toDouble(),
      lastLng: (d['lastLng'] as num?)?.toDouble(),
      departureRealTime: d['departureRealTime'] as String?,
    );
  }
}

// ─── Repository ───────────────────────────────────────────────────────────────

class GoRadarRepository {
  GoRadarRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection('goRadarSessions');

  // Crée ou reprend une session pour ce slot du jour
  Future<GoRadarSession> openSession(GoRadarSessionArgs args) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Cherche une session existante pour ce slot aujourd'hui
    final existing = await _sessions
        .where('tripId', isEqualTo: args.tripId)
        .where('slotNumber', isEqualTo: args.slotNumber)
        .where('date', isEqualTo: args.date)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return GoRadarSession.fromDoc(existing.docs.first);
    }

    // Crée une nouvelle session
    final ref = _sessions.doc();
    final now = DateTime.now();
    final data = <String, dynamic>{
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
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data);

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
    );
  }

  // Envoie une mise à jour
  Future<void> pushUpdate({
    required String sessionId,
    required GoRadarStatus status,
    required int availableSeats,
    double? lat,
    double? lng,
    String? departureRealTime,
  }) async {
    final now = FieldValue.serverTimestamp();

    final Map<String, dynamic> sessionPatch = {
      'status': status.value,
      'availableSeats': availableSeats,
      'lastUpdatedAt': now,
      if (lat != null) 'lastLat': lat,
      if (lng != null) 'lastLng': lng,
      if (departureRealTime != null) 'departureRealTime': departureRealTime,
    };

    final Map<String, dynamic> historyEntry = {
      'status': status.value,
      'availableSeats': availableSeats,
      'updatedAt': now,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    };

    final batch = _firestore.batch();
    batch.update(_sessions.doc(sessionId), sessionPatch);
    batch.set(_sessions.doc(sessionId).collection('history').doc(), historyEntry);
    await batch.commit();
  }

  // Écoute en temps réel une session (pour l'écran passager plus tard)
  Stream<GoRadarSession?> watchSession(String sessionId) {
    return _sessions
        .doc(sessionId)
        .snapshots()
        .map((snap) => snap.exists ? GoRadarSession.fromDoc(snap) : null);
  }
}
