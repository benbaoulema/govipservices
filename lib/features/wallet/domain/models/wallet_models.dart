import 'package:cloud_firestore/cloud_firestore.dart';

class WalletDocument {
  const WalletDocument({
    required this.uid,
    required this.balance,
    required this.currency,
    this.updatedAt,
  });

  final String uid;
  final int balance;
  final String currency;
  final Timestamp? updatedAt;

  factory WalletDocument.empty(String uid) =>
      WalletDocument(uid: uid, balance: 0, currency: 'XOF');

  factory WalletDocument.fromMap(String uid, Map<String, dynamic> map) {
    return WalletDocument(
      uid: uid,
      balance: (map['balance'] as num? ?? 0).toInt(),
      currency: (map['currency'] as String? ?? 'XOF').trim(),
      updatedAt: map['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'balance': balance,
        'currency': currency,
        'updatedAt': updatedAt,
      };
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    this.reference = '',
    this.method = '',
    this.status = 'completed',
    this.createdAt,
  });

  final String id;
  /// Positive = credit, negative = debit
  final int amount;
  final String type; // 'commission' | 'recharge' | 'retrait'
  final String description;
  final String reference;
  final String method; // 'wave' | 'orange_money' | ''
  final String status; // 'completed' | 'pending'
  final Timestamp? createdAt;

  bool get isCredit => amount > 0;

  factory WalletTransaction.fromMap(String id, Map<String, dynamic> map) {
    return WalletTransaction(
      id: id,
      amount: (map['amount'] as num? ?? 0).toInt(),
      type: (map['type'] as String? ?? '').trim(),
      description: (map['description'] as String? ?? '').trim(),
      reference: (map['reference'] as String? ?? '').trim(),
      method: (map['method'] as String? ?? '').trim(),
      status: (map['status'] as String? ?? 'completed').trim(),
      createdAt: map['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'amount': amount,
        'type': type,
        'description': description,
        'reference': reference,
        'method': method,
        'status': status,
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      };
}
