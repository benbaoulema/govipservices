// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:govipservices/app/app.dart';

void main() {
  testWidgets('Home switches between Voyager and Colis menus', (WidgetTester tester) async {
    await tester.pumpWidget(const GoVipApp());

    expect(find.text('Voyager'), findsOneWidget);
    expect(find.text('Ajouter trajet'), findsWidgets);
    expect(find.text('Reserver'), findsWidgets);
    expect(find.text('Mes trajet'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);

    await tester.tap(find.text('Colis'));
    await tester.pumpAndSettle();

    expect(find.text('Expedier'), findsWidgets);
    expect(find.text('Vip shopping'), findsWidgets);
    expect(find.text('Proposer'), findsWidgets);
  });
}
