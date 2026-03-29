import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';

class ScratchService {
  ScratchService._();
  static final ScratchService instance = ScratchService._();

  static const String _region = 'europe-west1';

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: _region);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Lectures ponctuelles (get) ────────────────────────────────────────────────

  /// Retourne la première campagne active affichable sur la home.
  /// Accessible sans authentification.
  Future<ScratchCampaign?> fetchActiveCampaign() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('scratchCampaigns')
        .where('isActive', isEqualTo: true)
        .where('showOnHomepage', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScratchCampaign.fromFirestore(snap.docs.first);
  }

  /// Retourne la campagne active associée à un trigger contextuel (ex: 'booking_checkout').
  Future<ScratchCampaign?> fetchCampaignByTrigger(String trigger) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('scratchCampaigns')
        .where('trigger', isEqualTo: trigger)
        .get();
    for (final doc in snap.docs) {
      if (doc.data()['isActive'] == true) {
        return ScratchCampaign.fromFirestore(doc);
      }
    }
    return null;
  }

  /// Retourne la campagne active ciblant les reporters GO Radar.
  Future<ScratchCampaign?> fetchReporterCampaign() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('scratchCampaigns')
        .where('isActive', isEqualTo: true)
        .where('targetAudience', isEqualTo: 'go_radar_reporters')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScratchCampaign.fromFirestore(snap.docs.first);
  }

  /// Retourne la campagne active ciblant les étudiants/élèves.
  Future<ScratchCampaign?> fetchStudentCampaign() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('scratchCampaigns')
        .where('isActive', isEqualTo: true)
        .where('targetAudience', isEqualTo: 'students')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScratchCampaign.fromFirestore(snap.docs.first);
  }

  /// Retourne une campagne par son id. Accessible sans authentification.
  Future<ScratchCampaign?> fetchCampaignById(String campaignId) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _db.collection('scratchCampaigns').doc(campaignId).get();
    if (!doc.exists) return null;
    return ScratchCampaign.fromFirestore(doc);
  }

  Future<List<UserScratchCard>> fetchPendingCards() async {
    final String? uid = _uid;
    if (uid == null) return [];
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('user_scratch_cards/$uid/cards')
        .where('status', isEqualTo: 'pending')
        .orderBy('assignedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => UserScratchCard.fromFirestore(d))
        .where((c) => !c.isExpired)
        .toList();
  }

  Future<List<UserScratchCard>> fetchRevealedCards() async {
    final String? uid = _uid;
    if (uid == null) return [];
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('user_scratch_cards/$uid/cards')
        .where('status', isEqualTo: 'revealed')
        .orderBy('revealedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => UserScratchCard.fromFirestore(d))
        .where((c) => c.rewardId != null && c.rewardType != 'nothing')
        .toList();
  }

  Future<List<UserReward>> fetchAvailableRewards() async {
    final String? uid = _uid;
    if (uid == null) return [];
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('user_rewards/$uid/rewards')
        .where('status', isEqualTo: 'available')
        .orderBy('earnedAt', descending: true)
        .get();
    return snap.docs.map((d) => UserReward.fromFirestore(d)).toList();
  }

  /// Retourne les récompenses éligibles pour un trajet bus (transport),
  /// triées de la plus ancienne à la plus récente (FIFO).
  Future<List<UserReward>> fetchEligibleRewardsForTransport() async {
    final String? uid = _uid;
    if (uid == null) return [];
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('user_rewards/$uid/rewards')
        .where('status', isEqualTo: 'available')
        .where('type', isEqualTo: 'discount_fixed')
        .orderBy('earnedAt')
        .get();
    return snap.docs
        .map((d) => UserReward.fromFirestore(d))
        .where((r) => r.isEligibleForTransport)
        .toList();
  }

  // ── Callables ────────────────────────────────────────────────────────────────

  /// Registers an app launch for the current user.
  /// Returns the list of newly assigned card IDs (may be empty).
  Future<List<String>> registerAppLaunch() async {
    if (_uid == null) return [];
    final HttpsCallable fn = _functions.httpsCallable('registerAppLaunch');
    final HttpsCallableResult<dynamic> result = await fn.call<dynamic>();
    final List<dynamic>? cardIds = (result.data as Map?)?['cardIds'] as List?;
    return cardIds?.cast<String>() ?? [];
  }

  /// Reveals a pending scratch card. Returns the drawn reward.
  Future<RevealResult> revealCard(String cardId) async {
    final HttpsCallable fn = _functions.httpsCallable('revealScratchCard');
    final HttpsCallableResult<dynamic> result =
        await fn.call<dynamic>({'cardId': cardId});
    return RevealResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// Redeems an available reward.
  /// Returns the redemptionId.
  Future<String> redeemReward(
    String rewardId, {
    Map<String, String>? context,
  }) async {
    final HttpsCallable fn = _functions.httpsCallable('redeemReward');
    final HttpsCallableResult<dynamic> result = await fn.call<dynamic>({
      'rewardId': rewardId,
      if (context != null) 'context': context,
    });
    return (result.data as Map?)?['redemptionId'] as String? ?? '';
  }

  bool isCardAlreadyProcessedError(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    if (error.code != 'failed-precondition') return false;

    final String message = (error.message ?? '').toLowerCase();
    return message.contains('already revealed') || message.contains('has expired');
  }
}
