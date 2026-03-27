import 'package:cloud_firestore/cloud_firestore.dart';

// ── RewardConfig ───────────────────────────────────────────────────────────────

class RewardConfig {
  const RewardConfig({
    required this.id,
    required this.type,
    required this.label,
    required this.weight,
    this.value,
  });

  final String id;
  final String type;
  final String label;
  final int weight;
  final double? value;

  bool get isNothing => type == 'nothing';

  factory RewardConfig.fromMap(Map<String, dynamic> m) {
    return RewardConfig(
      id: m['id'] as String? ?? '',
      type: m['type'] as String? ?? 'nothing',
      label: m['label'] as String? ?? '',
      weight: (m['weight'] as num? ?? 0).toInt(),
      value: (m['value'] as num?)?.toDouble(),
    );
  }
}

// ── ScratchCampaign ────────────────────────────────────────────────────────────

class ScratchCampaign {
  const ScratchCampaign({
    required this.id,
    this.showOnHomepage = false,
    this.maxGlobalRewards,
    this.departureLocation,
    this.arrivalLocation,
    this.targetAudience,
    this.rewardsPool = const <RewardConfig>[],
  });

  final String id;
  final bool showOnHomepage;
  final int? maxGlobalRewards;
  final String? departureLocation;
  final String? arrivalLocation;
  final String? targetAudience;
  final List<RewardConfig> rewardsPool;

  bool get hasRoute => departureLocation != null && arrivalLocation != null;
  bool get isForStudents => targetAudience == 'students';

  factory ScratchCampaign.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return ScratchCampaign(
      id: doc.id,
      showOnHomepage: d['showOnHomepage'] as bool? ?? false,
      maxGlobalRewards: (d['maxGlobalRewards'] as num?)?.toInt(),
      departureLocation: d['departureLocation'] as String?,
      arrivalLocation: d['arrivalLocation'] as String?,
      targetAudience: d['targetAudience'] as String?,
      rewardsPool: (d['rewardsPool'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => RewardConfig.fromMap(Map<String, dynamic>.from(e)))
          .where((r) => r.weight > 0)
          .toList(growable: false),
    );
  }
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
    this.remainingValue,
    this.serviceScope,
    this.expiresAt,
    this.usedAt,
  });

  final String id;
  final String campaignId;
  final String cardId;
  final String type;
  final String label;
  final double? value;
  /// Montant restant après utilisations partielles. Géré par le backend.
  final double? remainingValue;
  /// Ex: "transport", "parcels". Null = applicable partout.
  final String? serviceScope;
  final RewardStatus status;
  final DateTime earnedAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  /// Valeur effective utilisable : remainingValue en priorité, sinon value.
  double get effectiveValue => remainingValue ?? value ?? 0;

  bool get isExpiredReward =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isEligibleForTransport =>
      !isNothing &&
      !isExpiredReward &&
      status == RewardStatus.available &&
      type == 'discount_fixed' &&
      (serviceScope == null || serviceScope!.contains('transport'));

  factory UserReward.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return UserReward(
      id: doc.id,
      campaignId: d['campaignId'] as String? ?? '',
      cardId: d['cardId'] as String? ?? '',
      type: d['type'] as String? ?? 'nothing',
      label: d['label'] as String? ?? '',
      value: (d['value'] as num?)?.toDouble(),
      remainingValue: (d['remainingValue'] as num?)?.toDouble(),
      serviceScope: d['serviceScope'] as String?,
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
