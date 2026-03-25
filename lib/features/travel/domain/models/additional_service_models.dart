import 'package:cloud_firestore/cloud_firestore.dart';

// ── AdditionalServiceType ─────────────────────────────────────────────────────

enum AdditionalServiceType {
  domicileGare,
  gareMaison,
  kitAlimentaire;

  String get firestoreId {
    switch (this) {
      case AdditionalServiceType.domicileGare:
        return 'domicile_gare';
      case AdditionalServiceType.gareMaison:
        return 'gare_maison';
      case AdditionalServiceType.kitAlimentaire:
        return 'kit_alimentaire';
    }
  }

  String get label {
    switch (this) {
      case AdditionalServiceType.domicileGare:
        return 'Domicile → Gare';
      case AdditionalServiceType.gareMaison:
        return 'Gare de destination → Maison';
      case AdditionalServiceType.kitAlimentaire:
        return 'Kit alimentaire';
    }
  }

  static AdditionalServiceType? tryFromFirestoreId(String id) {
    try {
      return AdditionalServiceType.values.firstWhere(
        (e) => e.firestoreId == id,
      );
    } catch (_) {
      return null;
    }
  }
}

// ── CityEntry ─────────────────────────────────────────────────────────────────

class CityEntry {
  const CityEntry({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory CityEntry.fromMap(Map<String, dynamic> map) {
    return CityEntry(
      id: (map['id'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}

// ── AdditionalServiceDocument ─────────────────────────────────────────────────

class AdditionalServiceDocument {
  const AdditionalServiceDocument({
    required this.type,
    required this.name,
    required this.isActive,
    required this.cities,
    this.updatedAt,
  });

  final AdditionalServiceType type;
  final String name;
  final bool isActive;
  final List<CityEntry> cities;
  final Timestamp? updatedAt;

  factory AdditionalServiceDocument.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    final AdditionalServiceType? type =
        AdditionalServiceType.tryFromFirestoreId(doc.id);
    if (type == null) throw ArgumentError('Unknown service type: ${doc.id}');

    return AdditionalServiceDocument(
      type: type,
      name: (data['name'] as String? ?? type.label).trim(),
      isActive: data['isActive'] as bool? ?? true,
      cities: (data['cities'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => CityEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  /// Returns true if the given address is covered by this service.
  /// Matching is done at commune level: address.contains(cityEntry.name).
  bool coversAddress(String address) {
    if (!isActive) return false;
    final String lower = address.toLowerCase();
    return cities.any(
      (c) => c.isActive && lower.contains(c.name.toLowerCase()),
    );
  }
}
