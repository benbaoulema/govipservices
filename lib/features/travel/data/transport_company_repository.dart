import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/models/transport_company.dart';

class TransportCompanyRepository {
  TransportCompanyRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('transportCompanies');

  Future<List<TransportCompany>> fetchEnabled() async {
    final snapshot = await _col.get();
    final list = snapshot.docs
        .map((doc) => TransportCompany.fromMap(doc.id, doc.data()))
        .where((c) => c.name.isNotEmpty && c.enabled)
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}
