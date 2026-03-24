class TransportCompany {
  const TransportCompany({
    required this.id,
    required this.name,
    this.contact,
    this.imageUrl,
    this.imageStoragePath,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String? contact;
  final String? imageUrl;
  final String? imageStoragePath;
  final bool enabled;

  factory TransportCompany.fromMap(String id, Map<String, dynamic> data) {
    return TransportCompany(
      id: id,
      name: (data['name'] as String? ?? '').trim(),
      contact: data['contact'] as String?,
      imageUrl: data['imageUrl'] as String?,
      imageStoragePath: data['imageStoragePath'] as String?,
      enabled: data['enabled'] as bool? ?? true,
    );
  }
}
