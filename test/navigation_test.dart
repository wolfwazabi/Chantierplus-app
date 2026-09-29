import 'package:construction_app/main.dart';
import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => CalculatriceScreen.mode.value = ModeCalculatrice.charpente);

  testWidgets('toucher l\'onglet Calculatrice déjà ouvert bascule charpente ↔ béton', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    final onglet = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Calculatrice'),
    );
    expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);

    await tester.tap(onglet);
    await tester.pump();
    expect(CalculatriceScreen.mode.value, ModeCalculatrice.beton);
    expect(find.text('Longueur'), findsOneWidget);

    await tester.tap(onglet);
    await tester.pump();
    expect(CalculatriceScreen.mode.value, ModeCalculatrice.charpente);
    expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);
  });
}
