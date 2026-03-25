import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:govipservices/features/travel/domain/models/additional_service_models.dart';

class AdditionalServiceRepository {
  const AdditionalServiceRepository();

  static const String _collection = 'additionalServices';

  Future<List<AdditionalServiceDocument>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await FirebaseFirestore.instance.collection(_collection).get();

    final List<AdditionalServiceDocument> result = <AdditionalServiceDocument>[];
    for (final doc in snap.docs) {
      try {
        result.add(AdditionalServiceDocument.fromFirestore(doc));
      } catch (_) {
        // Skip unknown service types silently
      }
    }
    return result;
  }
}
