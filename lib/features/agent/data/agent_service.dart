import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/agent/domain/models/agent_models.dart';

class AgentService {
  AgentService._();
  static final AgentService instance = AgentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _agents =>
      _db.collection('agents');

  CollectionReference<Map<String, dynamic>> get _otps =>
      _db.collection('agentOtps');

  // ── Récupérer l'agent lié à un userId ────────────────────────────────────

  Future<Agent?> fetchAgentByUserId(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _agents
          .where('userId', isEqualTo: uid)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return Agent.fromFirestore(snap.docs.first);
    } catch (_) {
      return null;
    }
  }

  // ── Vérifier le code agent (8 chiffres) ──────────────────────────────────

  Future<bool> verifyAgentCode({
    required String agentId,
    required String code,
  }) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _agents.doc(agentId).get();
      if (!doc.exists) return false;
      final String? storedCode = doc.data()?['code'] as String?;
      return storedCode != null && storedCode == code;
    } catch (_) {
      return false;
    }
  }

  // ── Générer un OTP à 6 chiffres ──────────────────────────────────────────

  Future<AgentOtp> generateOtp(String agentId) async {
    final String code = _generateCode();
    final DateTime now = DateTime.now();
    final DateTime expiresAt = now.add(const Duration(minutes: 8));

    final DocumentReference<Map<String, dynamic>> ref = _otps.doc();
    await ref.set(<String, dynamic>{
      'agentId': agentId,
      'code': code,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'used': false,
    });

    return AgentOtp(
      id: ref.id,
      agentId: agentId,
      code: code,
      expiresAt: expiresAt,
      createdAt: now,
    );
  }

  // ── Vérifier et consommer un OTP ─────────────────────────────────────────

  /// Retourne l'agentId si l'OTP est valide, null sinon.
  Future<String?> verifyAndConsumeOtp(String code) async {
    if (code.length != 6) return null;
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _otps
          .where('code', isEqualTo: code)
          .where('used', isEqualTo: false)
          .where('expiresAt', isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;

      final DocumentSnapshot<Map<String, dynamic>> doc = snap.docs.first;
      final AgentOtp otp = AgentOtp.fromFirestore(doc);

      // Marquer comme utilisé de façon atomique
      await _db.runTransaction((tx) async {
        final DocumentSnapshot<Map<String, dynamic>> fresh =
            await tx.get(doc.reference);
        if (fresh.data()?['used'] == true) {
          throw Exception('OTP déjà utilisé.');
        }
        tx.update(doc.reference, <String, dynamic>{'used': true});
      });

      return otp.agentId;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _generateCode() {
    final Random rng = Random.secure();
    return List<int>.generate(6, (_) => rng.nextInt(10)).join();
  }
}
