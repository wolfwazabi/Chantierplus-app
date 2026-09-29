import 'package:construction_app/main.dart';
import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => CalculatriceScreen.mode.value = ModeCalculatrice.charpente);

  testWidgets('boutons Charpente | Béton en haut de la calculatrice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode_charpente')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mode_beton')));
    await tester.pump();
    expect(CalculatriceScreen.mode.value, ModeCalculatrice.beton);
    expect(find.text('Longueur'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mode_charpente')));
    await tester.pump();
    expect(CalculatriceScreen.mode.value, ModeCalculatrice.charpente);
    expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);
  });

  testWidgets('retoucher l\'onglet Calculatrice ne change plus de mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Calculatrice'),
      ),
    );
    await tester.pump();
    expect(CalculatriceScreen.mode.value, ModeCalculatrice.charpente);
  });
}
