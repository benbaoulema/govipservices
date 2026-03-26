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

  /// Retourne la première campagne active — accessible sans authentification.
  Future<ScratchCampaign?> fetchActiveCampaign() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection('scratchCampaigns')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScratchCampaign.fromFirestore(snap.docs.first);
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
}
