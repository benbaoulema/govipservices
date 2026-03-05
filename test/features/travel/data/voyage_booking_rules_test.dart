import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/data/voyage_booking_service.dart';
import 'package:govipservices/features/travel/domain/models/voyage_booking_models.dart';

void main() {
  CreateVoyageBookingInput makeInput() {
    return const CreateVoyageBookingInput(
      tripId: 'trip_1',
      requestedSeats: 2,
      requesterUid: 'u1',
      requesterTrackNum: 'USR01',
      requesterName: 'Alice',
      requesterContact: '01010101',
      requesterEmail: 'alice@test.com',
      segmentFrom: 'Abidjan, CI',
      segmentTo: 'Bouake, CI',
      segmentPrice: 5000,
      travelers: <VoyageBookingTraveler>[
        VoyageBookingTraveler(name: 'Alice A', contact: '01010101'),
        VoyageBookingTraveler(name: 'Bob B', contact: '01010101'),
      ],
    );
  }

  group('voyage booking rules', () {
    test('refus si seats insuffisantes', () {
      final String? error = validateVoyageTripForBooking(
        trip: <String, dynamic>{
          'status': 'published',
          'seats': 1,
        },
        requestedSeats: 2,
      );
      expect(error, 'Places insuffisantes.');
    });

    test('refus si trip non publie', () {
      final String? error = validateVoyageTripForBooking(
        trip: <String, dynamic>{
          'status': 'draft',
          'seats': 8,
        },
        requestedSeats: 2,
      );
      expect(error, 'Trajet non disponible a la reservation.');
    });

    test('totalPrice correct', () {
      final int total = computeVoyageBookingTotalPrice(
        segmentPrice: 5000,
        requestedSeats: 2,
      );
      expect(total, 10000);
    });

    test('lock duplicate bloque doublon via duplicateKey identique', () {
      final CreateVoyageBookingInput a = makeInput();
      final CreateVoyageBookingInput b = makeInput();

      final String keyA = buildVoyageBookingDuplicateKey(a);
      final String keyB = buildVoyageBookingDuplicateKey(b);
      expect(keyA, keyB);
    });
  });
}
