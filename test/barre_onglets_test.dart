import 'package:construction_app/widgets/barre_onglets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _onglets = [
  OngletBarre('Calculatrice', Icons.calculate_outlined, Icons.calculate),
  OngletBarre('Temps', Icons.access_time_outlined, Icons.access_time),
  OngletBarre('Chantier', Icons.construction_outlined, Icons.construction),
  OngletBarre('Admin', Icons.bar_chart_outlined, Icons.bar_chart),
  OngletBarre('Compagnies', Icons.business_outlined, Icons.business),
  OngletBarre('Compte', Icons.person_outline, Icons.person),
];

void main() {
  Future<void> ouvrir(
    WidgetTester tester,
    int choisi, {
    double largeur = 360,
  }) async {
    tester.view.physicalSize = Size(largeur, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BarreOnglets(
            onglets: _onglets,
            indexSelectionne: choisi,
            onSelection: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('six onglets sur un petit écran : aucun débordement', (
    tester,
  ) async {
    for (var i = 0; i < _onglets.length; i++) {
      await ouvrir(tester, i);
      expect(tester.takeException(), isNull, reason: 'onglet $i');
    }
  });

  testWidgets(
    'l\'icône et l\'étiquette ne bougent pas d\'un onglet à l\'autre',
    (tester) async {
      await ouvrir(tester, 0);
      final reference = <String, Offset>{};
      for (final o in _onglets) {
        reference[o.label] = tester.getCenter(
          find.byKey(ValueKey('icone_${o.label}')),
        );
      }
      final tailleEtiquette = tester.getSize(find.text('Calculatrice'));

      for (var i = 0; i < _onglets.length; i++) {
        await ouvrir(tester, i);
        for (final o in _onglets) {
          expect(
            tester.getCenter(find.byKey(ValueKey('icone_${o.label}'))),
            reference[o.label],
            reason: '${o.label} quand l\'onglet $i est choisi',
          );
        }
        // Même police sélectionnée ou non : la taille de l'étiquette est stable.
        expect(tester.getSize(find.text('Calculatrice')), tailleEtiquette);
      }
    },
  );

  testWidgets('hauteur de 56, plus basse que la NavigationBar (80)', (
    tester,
  ) async {
    await ouvrir(tester, 0);
    expect(
      tester.getSize(find.byType(BarreOnglets)).height,
      BarreOnglets.hauteur,
    );
    expect(BarreOnglets.hauteur, lessThan(80));
  });

  testWidgets('toucher un onglet le sélectionne', (tester) async {
    int? choisi;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BarreOnglets(
            onglets: _onglets,
            indexSelectionne: 0,
            onSelection: (i) => choisi = i,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('onglet_Compagnies')));
    expect(choisi, 4);
  });
}
