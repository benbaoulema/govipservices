import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';

abstract class TripDetailRepository {
  Future<TripDetailModel?> getTripDetailById(String tripId);
}
