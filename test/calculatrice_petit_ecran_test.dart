import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ModeCalculatrice.values) {
    testWidgets(
      'petit téléphone (360 x 560, avec la barre du bas) : aucun débordement, ${mode.name}',
      (tester) async {
        CalculatriceScreen.mode.value = mode;
        tester.view.physicalSize = const Size(360, 560);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CalculatriceScreen())),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('mode_charpente')), findsOneWidget);
        expect(find.byKey(const ValueKey('mode_beton')), findsOneWidget);
      },
    );
  }
}
