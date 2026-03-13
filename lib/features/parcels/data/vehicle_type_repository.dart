import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/parcels/domain/models/vehicle_type.dart';

class VehicleTypeRepository {
  VehicleTypeRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('typeVehicules');

  Future<List<VehicleType>> fetchActiveVehicleTypes() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _collection.orderBy('name').get();

    final List<VehicleType> items = snapshot.docs
        .map((doc) => VehicleType.fromMap(doc.id, doc.data()))
        .where((item) => item.name.isNotEmpty && item.isActive)
        .toList(growable: true);

    items.sort(_compareVehicleTypes);
    return items;
  }

  Stream<List<VehicleType>> watchActiveVehicleTypes() {
    return _collection.orderBy('name').snapshots().map((snapshot) {
      final List<VehicleType> items = snapshot.docs
          .map((doc) => VehicleType.fromMap(doc.id, doc.data()))
          .where((item) => item.name.isNotEmpty && item.isActive)
          .toList(growable: true);

      items.sort(_compareVehicleTypes);
      return items;
    });
  }

  int _compareVehicleTypes(VehicleType a, VehicleType b) {
    const List<String> priorityOrder = <String>[
      'moto',
      'tricycle',
      'car',
      'cargo',
    ];

    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    int priorityIndex(VehicleType item) {
      final String normalized = normalize(item.name);
      final int index =
          priorityOrder.indexWhere((keyword) => normalized.contains(keyword));
      return index == -1 ? priorityOrder.length : index;
    }

    final int aPriority = priorityIndex(a);
    final int bPriority = priorityIndex(b);
    if (aPriority != bPriority) return aPriority.compareTo(bPriority);

    final double aVolume = a.volume ?? double.infinity;
    final double bVolume = b.volume ?? double.infinity;
    final int volumeCompare = aVolume.compareTo(bVolume);
    if (volumeCompare != 0) return volumeCompare;

    return normalize(a.name).compareTo(normalize(b.name));
  }
}
