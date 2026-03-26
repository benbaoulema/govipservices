import 'package:cloud_firestore/cloud_firestore.dart';

// ── ScratchCampaign ────────────────────────────────────────────────────────────

class ScratchCampaign {
  const ScratchCampaign({required this.id});
  final String id;

  factory ScratchCampaign.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      ScratchCampaign(id: doc.id);
}

// ── CardStatus ─────────────────────────────────────────────────────────────────

enum CardStatus {
  pending,
  revealed,
  expired;

  static CardStatus fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'revealed':
        return CardStatus.revealed;
      case 'expired':
        return CardStatus.expired;
      default:
        return CardStatus.pending;
    }
  }
}

// ── RewardStatus ───────────────────────────────────────────────────────────────

enum RewardStatus {
  available,
  used,
  expired;

  static RewardStatus fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'used':
        return RewardStatus.used;
      case 'expired':
        return RewardStatus.expired;
      default:
        return RewardStatus.available;
    }
  }
}

// ── UserScratchCard ────────────────────────────────────────────────────────────

class UserScratchCard {
  const UserScratchCard({
    required this.id,
    required this.campaignId,
    required this.status,
    required this.assignedAt,
    this.expiresAt,
    this.revealedAt,
    this.rewardId,
    this.rewardType,
    this.rewardLabel,
    this.rewardValue,
  });

  final String id;
  final String campaignId;
  final CardStatus status;
  final DateTime assignedAt;
  final DateTime? expiresAt;
  final DateTime? revealedAt;
  final String? rewardId;
  final String? rewardType;
  final String? rewardLabel;
  final double? rewardValue;

  factory UserScratchCard.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return UserScratchCard(
      id: doc.id,
      campaignId: d['campaignId'] as String? ?? '',
      status: CardStatus.fromString(d['status'] as String?),
      assignedAt: (d['assignedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      revealedAt: (d['revealedAt'] as Timestamp?)?.toDate(),
      rewardId: d['rewardId'] as String?,
      rewardType: d['rewardType'] as String?,
      rewardLabel: d['rewardLabel'] as String?,
      rewardValue: (d['rewardValue'] as num?)?.toDouble(),
    );
  }

  bool get isExpired {
    if (status == CardStatus.expired) return true;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) return true;
    return false;
  }
}

// ── UserReward ─────────────────────────────────────────────────────────────────

class UserReward {
  const UserReward({
    required this.id,
    required this.campaignId,
    required this.cardId,
    required this.type,
    required this.label,
    required this.status,
    required this.earnedAt,
    this.value,
    this.expiresAt,
    this.usedAt,
  });

  final String id;
  final String campaignId;
  final String cardId;
  final String type;
  final String label;
  final double? value;
  final RewardStatus status;
  final DateTime earnedAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  factory UserReward.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return UserReward(
      id: doc.id,
      campaignId: d['campaignId'] as String? ?? '',
      cardId: d['cardId'] as String? ?? '',
      type: d['type'] as String? ?? 'nothing',
      label: d['label'] as String? ?? '',
      value: (d['value'] as num?)?.toDouble(),
      status: RewardStatus.fromString(d['status'] as String?),
      earnedAt: (d['earnedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      usedAt: (d['usedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isNothing => type == 'nothing';
}

// ── RevealResult ───────────────────────────────────────────────────────────────

class RevealResult {
  const RevealResult({
    required this.rewardId,
    required this.rewardType,
    required this.rewardLabel,
    this.rewardValue,
  });

  final String rewardId;
  final String rewardType;
  final String rewardLabel;
  final double? rewardValue;

  bool get isNothing => rewardType == 'nothing';

  factory RevealResult.fromMap(Map<String, dynamic> m) {
    return RevealResult(
      rewardId: m['rewardId'] as String? ?? '',
      rewardType: m['rewardType'] as String? ?? 'nothing',
      rewardLabel: m['rewardLabel'] as String? ?? '',
      rewardValue: (m['rewardValue'] as num?)?.toDouble(),
    );
  }
}
