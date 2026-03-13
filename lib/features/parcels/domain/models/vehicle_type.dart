class VehicleType {
  const VehicleType({
    required this.id,
    required this.name,
    this.imageUrl,
    this.description,
    this.volume,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final String? description;
  final double? volume;
  final bool isActive;

  factory VehicleType.fromMap(String id, Map<String, dynamic> data) {
    double? toDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final double? parsed = double.tryParse(value.toString());
      return parsed;
    }

    return VehicleType(
      id: id,
      name: (data['name'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String?)?.trim(),
      description: (data['description'] as String?)?.trim(),
      volume: toDouble(data['volume']),
      isActive: data['active'] as bool? ?? data['isActive'] as bool? ?? true,
    );
  }
}
