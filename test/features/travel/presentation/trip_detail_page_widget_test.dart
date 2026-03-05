import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govipservices/features/travel/presentation/pages/trip_detail_page.dart';

void main() {
  testWidgets('TripBookingPanel desactive le bouton reserver si canBook=false', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripBookingPanel(
            selectedSeats: 1,
            maxSeats: 1,
            currency: 'XOF',
            total: 0,
            canBook: false,
            onIncrement: () {},
            onDecrement: () {},
            onBook: () {},
          ),
        ),
      ),
    );

    final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
