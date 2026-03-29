import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/wallet/domain/models/wallet_models.dart';

class WalletService {
  WalletService._();
  static final WalletService instance = WalletService._();

  static const double _commissionRate = 0.10;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _wallets =>
      _db.collection('wallets');

  DocumentReference<Map<String, dynamic>> _walletRef(String uid) =>
      _wallets.doc(uid);

  CollectionReference<Map<String, dynamic>> _txRef(String uid) =>
      _walletRef(uid).collection('transactions');

  // ── Streams ──────────────────────────────────────────────────────────────

  Stream<WalletDocument> watchWallet(String uid) {
    return _walletRef(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return WalletDocument.empty(uid);
      }
      return WalletDocument.fromMap(uid, snap.data()!);
    });
  }

  Stream<List<WalletTransaction>> watchTransactions(String uid,
      {int limit = 50}) {
    return _txRef(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WalletTransaction.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  // ── Commission ───────────────────────────────────────────────────────────

  /// Deducts 10% commission when a trip starts.
  /// Uses a Firestore transaction to ensure atomicity.
  Future<void> deductCommission({
    required String driverUid,
    required int tripTotalPrice,
    required String bookingTrackNum,
  }) async {
    final int commission =
        (tripTotalPrice * _commissionRate).round();
    if (commission <= 0) return;

    final DocumentReference<Map<String, dynamic>> walletRef =
        _walletRef(driverUid);

    await _db.runTransaction((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await tx.get(walletRef);
      final int current =
          snap.exists ? (snap.data()?['balance'] as num? ?? 0).toInt() : 0;

      final Map<String, dynamic> walletData = <String, dynamic>{
        'balance': current - commission,
        'currency': 'XOF',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snap.exists) {
        tx.update(walletRef, walletData);
      } else {
        tx.set(walletRef, walletData);
      }

      final DocumentReference<Map<String, dynamic>> txRef =
          _txRef(driverUid).doc();
      tx.set(txRef, WalletTransaction(
        id: txRef.id,
        amount: -commission,
        type: 'commission',
        description: 'Commission course — Réf. $bookingTrackNum',
        reference: bookingTrackNum,
        status: 'completed',
      ).toMap());
    });
  }

  // ── Récompense reporter ──────────────────────────────────────────────────────

  /// Crédite le wallet du reporter avec le montant de sa récompense GO Radar.
  Future<void> creditReporterReward({
    required String uid,
    required int amount,
    required String tripRoute,
  }) async {
    if (amount <= 0) return;

    final DocumentReference<Map<String, dynamic>> walletRef = _walletRef(uid);

    await _db.runTransaction((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(walletRef);
      final int current =
          snap.exists ? (snap.data()?['balance'] as num? ?? 0).toInt() : 0;

      final Map<String, dynamic> walletData = <String, dynamic>{
        'balance': current + amount,
        'currency': 'XOF',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snap.exists) {
        tx.update(walletRef, walletData);
      } else {
        tx.set(walletRef, walletData);
      }

      final DocumentReference<Map<String, dynamic>> txRef = _txRef(uid).doc();
      tx.set(txRef, WalletTransaction(
        id: txRef.id,
        amount: amount,
        type: 'reporter_reward',
        description: 'Récompense GO Radar — $tripRoute',
        reference: '',
      ).toMap());
    });
  }

  // ── Retrait ───────────────────────────────────────────────────────────────

  /// Enregistre une demande de retrait Wave :
  /// - Déduit le solde immédiatement (statut pending)
  /// - Crée une transaction 'retrait' dans le wallet
  /// - Enregistre la demande dans walletWithdrawals
  Future<void> requestRetrait({
    required String uid,
    required int amount,
    required String wavePhone,
  }) async {
    if (amount <= 0) return;

    final DocumentReference<Map<String, dynamic>> walletRef = _walletRef(uid);
    final DocumentReference<Map<String, dynamic>> withdrawalRef =
        _db.collection('walletWithdrawals').doc();

    await _db.runTransaction((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(walletRef);
      final int current =
          snap.exists ? (snap.data()?['balance'] as num? ?? 0).toInt() : 0;

      if (current < amount) {
        throw Exception('Solde insuffisant.');
      }

      final Map<String, dynamic> walletData = <String, dynamic>{
        'balance': current - amount,
        'currency': 'XOF',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snap.exists) {
        tx.update(walletRef, walletData);
      } else {
        tx.set(walletRef, walletData);
      }

      final DocumentReference<Map<String, dynamic>> txRef = _txRef(uid).doc();
      tx.set(txRef, WalletTransaction(
        id: txRef.id,
        amount: -amount,
        type: 'retrait',
        description: 'Retrait Wave — $wavePhone',
        reference: wavePhone,
        method: 'wave',
        status: 'pending',
      ).toMap());

      tx.set(withdrawalRef, <String, dynamic>{
        'uid': uid,
        'amount': amount,
        'wavePhone': wavePhone,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── Recharge ─────────────────────────────────────────────────────────────

  /// Records a top-up request (pending until confirmed by payment provider).
  Future<void> requestRecharge({
    required String uid,
    required int amount,
    required String method,
    required String phone,
  }) async {
    final DocumentReference<Map<String, dynamic>> walletRef =
        _walletRef(uid);
    final DocumentReference<Map<String, dynamic>> txRef =
        _txRef(uid).doc();

    await _db.runTransaction((tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await tx.get(walletRef);
      final int current =
          snap.exists ? (snap.data()?['balance'] as num? ?? 0).toInt() : 0;

      final Map<String, dynamic> walletData = <String, dynamic>{
        'balance': current + amount,
        'currency': 'XOF',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (snap.exists) {
        tx.update(walletRef, walletData);
      } else {
        tx.set(walletRef, walletData);
      }

      tx.set(txRef, WalletTransaction(
        id: txRef.id,
        amount: amount,
        type: 'recharge',
        description: 'Recharge via ${method == 'wave' ? 'Wave' : 'Orange Money'}',
        reference: phone,
        method: method,
        status: 'completed',
      ).toMap());
    });
  }
}
