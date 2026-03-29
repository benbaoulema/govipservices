import 'package:cloud_firestore/cloud_firestore.dart';

// ── Agent ─────────────────────────────────────────────────────────────────────

class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.code,
    this.userId,
    this.phone,
    this.isActive = true,
  });

  final String id;
  final String name;
  /// Code agent à 8 chiffres pour authentification.
  final String code;
  /// UID Firebase de l'utilisateur lié à cet agent.
  final String? userId;
  final String? phone;
  final bool isActive;

  bool get hasLinkedUser => userId != null && userId!.isNotEmpty;

  factory Agent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return Agent(
      id: doc.id,
      name: d['name'] as String? ?? '',
      code: d['code'] as String? ?? '',
      userId: d['userId'] as String?,
      phone: d['phone'] as String?,
      isActive: d['isActive'] as bool? ?? true,
    );
  }
}

// ── AgentOtp ──────────────────────────────────────────────────────────────────

class AgentOtp {
  const AgentOtp({
    required this.id,
    required this.agentId,
    required this.code,
    required this.expiresAt,
    required this.createdAt,
    this.used = false,
  });

  final String id;
  final String agentId;
  /// Code OTP à 6 chiffres.
  final String code;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool used;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !used && !isExpired;

  factory AgentOtp.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? {};
    return AgentOtp(
      id: doc.id,
      agentId: d['agentId'] as String? ?? '',
      code: d['code'] as String? ?? '',
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().subtract(const Duration(minutes: 1)),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      used: d['used'] as bool? ?? false,
    );
  }
}
