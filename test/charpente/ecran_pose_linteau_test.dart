// Onglet Murs : une fenêtre qui monte jusqu'à la sablière. La fiche de l'ouverture dit ce qui
// manque et quelle pose du linteau la fait passer ; la pose choisie se voit sur la carte du mur et
// les plaques de liaison arrivent dans la commande.
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _cle(String k) => find.byKey(ValueKey(k));

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Finder _champ(String label) => find.widgetWithText(TextField, label);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  testWidgets(
    'fenêtre jusqu\'à la sablière : la pose « à la place des lisses » la fait passer',
    (t) async {
      t.view.physicalSize = const Size(900, 9000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CharpenteScreen(
              companyId: 'A',
              chantierId: 'chA',
              connecte: true,
              listeEnregistrees: Text('(aucune commande)'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await _tap(t, find.widgetWithText(Tab, 'Murs'));
      await _tap(t, _cle('murs_actifs'));
      await _tap(t, _cle('carte_mur_0'));
      await _tap(t, _cle('mur_0_ajouter_fenetre'));

      // Mur de 8 pi 1 1/8 po (lisse haute à 94 1/8 po) : cadre de 74 po, allège de 14 po.
      await t.enterText(
        find.descendant(of: _cle('haut_0'), matching: find.byType(TextField)),
        '74"',
      );
      await t.enterText(_champ('Allège'), '14"');
      await t.pumpAndSettle();
      expect(
        find.textContaining('Ne passe pas : il manque 1 7/8"'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Avec « À la place des lisses », elle passe.'),
        findsOneWidget,
      );

      // Sous une lisse simple : pas encore assez.
      await _tap(t, _cle('ouverture_pose_sousLesLisses'));
      await t.tap(find.text('Sous une lisse simple').last);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Ne passe pas : il manque 3/8"'),
        findsOneWidget,
      );
      expect(find.textContaining('Gagne 1 1/2 po'), findsOneWidget);

      // À la place des lisses : elle passe ; la condition du Code est dite.
      await _tap(t, _cle('ouverture_pose_sousLisseSimple'));
      await t.tap(find.text('À la place des lisses').last);
      await t.pumpAndSettle();
      expect(find.textContaining('Ne passe pas'), findsNothing);
      expect(
        find.textContaining('plaque d\'acier galvanisé de 3 × 6 po'),
        findsOneWidget,
      );
      await _tap(t, _cle('ouverture_ok'));

      // La carte du mur montre la pose ; le calcul n'a plus d'erreur.
      expect(find.textContaining('· à la place des lisses'), findsOneWidget);
      expect(find.textContaining('ne passe pas'), findsNothing);

      // La commande contient les deux plaques de liaison.
      await _tap(t, find.widgetWithText(Tab, 'Commande'));
      expect(
        find.textContaining('Plaque de liaison en acier galvanisé 3 × 6 po'),
        findsOneWidget,
      );
      expect(find.textContaining('2 × Plaque de liaison'), findsOneWidget);
    },
  );

  testWidgets(
    'sans linteau : l\'ingénieur est nommé, rien n\'est compté pour la poutre',
    (t) async {
      t.view.physicalSize = const Size(900, 9000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CharpenteScreen(
              companyId: 'A',
              chantierId: 'chA',
              connecte: true,
              listeEnregistrees: Text('(aucune commande)'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await _tap(t, find.widgetWithText(Tab, 'Murs'));
      await _tap(t, _cle('murs_actifs'));
      await _tap(t, _cle('carte_mur_0'));
      await _tap(t, _cle('mur_0_ajouter_fenetre'));
      await _tap(t, _cle('ouverture_pose_sousLesLisses'));
      await t.tap(find.text('Sans linteau (poutre, ingénieur)').last);
      await t.pumpAndSettle();
      expect(find.textContaining('conçus par un ingénieur'), findsOneWidget);
      expect(find.textContaining('Haut de la baie à'), findsOneWidget);
      await _tap(t, _cle('ouverture_ok'));
      expect(
        find.textContaining('· sans linteau (poutre, ingénieur)'),
        findsOneWidget,
      );
      expect(find.textContaining('Loi sur les ingénieurs'), findsWidgets);
    },
  );
}
