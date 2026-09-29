import 'package:construction_app/screens/materiaux/calcul_materiaux.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const f4x8 = FormatFeuille('4 × 8 pi', 4, 8);
  const f4x12 = FormatFeuille('4 × 12 pi', 4, 12);

  group('nombreDeFeuilles', () {
    test('impérial : 100 pi² en 4×8 avec 10 % → 110 / 32 = 3,44 → 4', () {
      expect(
        nombreDeFeuilles(
          surface: 100,
          format: f4x8,
          pertePourcent: 10,
          metrique: false,
        ),
        4,
      );
    });

    test('pile juste : 64 pi² en 4×8 sans perte → 2 (pas 3)', () {
      expect(
        nombreDeFeuilles(
          surface: 64,
          format: f4x8,
          pertePourcent: 0,
          metrique: false,
        ),
        2,
      );
    });

    test('4×12 : 480 pi² sans perte → 10', () {
      expect(
        nombreDeFeuilles(
          surface: 480,
          format: f4x12,
          pertePourcent: 0,
          metrique: false,
        ),
        10,
      );
    });

    test('métrique : 20 m² en 4×8 (2,973 m²) avec 10 % → 7,4 → 8', () {
      expect(
        nombreDeFeuilles(
          surface: 20,
          format: f4x8,
          pertePourcent: 10,
          metrique: true,
        ),
        8,
      );
    });

    test('surface nulle ou négative → 0', () {
      expect(
        nombreDeFeuilles(
          surface: 0,
          format: f4x8,
          pertePourcent: 10,
          metrique: false,
        ),
        0,
      );
      expect(
        nombreDeFeuilles(
          surface: -5,
          format: f4x8,
          pertePourcent: 10,
          metrique: false,
        ),
        0,
      );
    });
  });

  testWidgets('formulaire : la réponse suit la saisie et les unités', (
    tester,
  ) async {
    Preferences.unites.value = SystemeUnites.imperial;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CalculMateriaux())),
    );
    expect(find.text('Entrez la surface à couvrir.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('materiaux_surface')),
      '100',
    );
    await tester.pump();
    expect(find.text('4 feuilles de 4 × 8 pi'), findsOneWidget);
    expect(find.text('pi²'), findsOneWidget);

    Preferences.unites.value = SystemeUnites.metrique;
    await tester.pump();
    expect(find.text('m²'), findsOneWidget);
    // 100 m² → 110 / 2,97290 = 37,0009 → 38 (37 laisserait un manque)
    expect(find.text('38 feuilles de 4 × 8 pi'), findsOneWidget);
    Preferences.unites.value = SystemeUnites.imperial;
  });
}
