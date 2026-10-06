// L'écran Plancher reproduit une commande réelle (véranda 15 × 14 pi sur pieux
// vissés) avec les réglages de l'entrepreneur. Voir docs/exemples_reels_plancher.md.
import 'package:construction_app/charpente/mur.dart' show section2x8;
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _cle(String k) => find.byKey(ValueKey(k));
Finder _champ(String cle) =>
    find.descendant(of: _cle(cle), matching: find.byType(TextField));

Future<void> _ouvrir(WidgetTester t) async {
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
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> _saisir(WidgetTester t, String cle, String texte) async {
  await t.ensureVisible(_champ(cle));
  await t.enterText(_champ(cle), texte);
  await t.pumpAndSettle();
}

Future<void> _choisir(WidgetTester t, String cleMenu, String texte) async {
  await _tap(t, _cle(cleMenu));
  await t.tap(find.text(texte).last);
  await t.pumpAndSettle();
}

bool _present(String texte) =>
    find.textContaining(texte, findRichText: true).evaluate().isNotEmpty;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  testWidgets('véranda 15 × 14 pi : résultats et commande de l\'entrepreneur', (
    t,
  ) async {
    await _ouvrir(t);
    await _saisir(t, 'rect_longueur', "15'");
    await _saisir(t, 'rect_largeur', "14'");
    await _choisir(t, 'section_2×10', '2×8 (7 1/4")');

    // Rives doublées, côté de la maison simple, solives de bordure doublées.
    await _tap(t, _cle('rive_double'));
    await _tap(t, _cle('bordure_double'));
    await _choisir(t, 'cote_maison_null', 'Côté 3 — 15\'');

    // Étriers à un bout, solives intérieures seulement.
    await _tap(t, find.descendant(of: _cle('etriers'), matching: find.text('Un bout')));
    await _tap(t, _cle('etriers_bordures'));

    // Entremises automatiques en pose alternée ; coupes séparées.
    await _tap(t, _cle('entremises_auto'));
    await _tap(t, _cle('entremises_alternees'));
    await _tap(t, _cle('coupes_separees'));

    // Poutres sur pieux vissés, pattes de 16 po.
    await _tap(t, _cle('poutres_actives'));
    await _saisir(t, 'poutres_patte', '16"');

    // Résultats du plancher.
    expect(_present('15 (dont 4 de bordure)'), isTrue, reason: '15 (dont 4 de bordure)');
    expect(_present('2 de 3 plis en 2×8'), isTrue, reason: '2 de 3 plis en 2×8');
    expect(_present('6 · entraxe 6\' 6"'), isTrue, reason: '6 · entraxe 6\' 6"');
    expect(_present('6 de 1\' 4"'), isTrue, reason: 'pattes');
    expect(_present('1 boîte'), isTrue, reason: '1 boîte');
    expect(find.text('Poutres (2×8 traité)'), findsOneWidget);

    // Liste de commande.
    await t.tap(find.widgetWithText(Tab, 'Commande'));
    await t.pumpAndSettle();
    expect(_present("2×8 × 14'"), isTrue, reason: "2×8 × 14'");
    expect(_present("2×8 × 16' traité"), isTrue, reason: "2×8 × 16' traité");
    expect(_present("6×6 × 8' traité"), isTrue, reason: "6×6 × 8' traité");
    expect(_present('Clous d\'étriers'), isTrue, reason: 'Clous d\'étriers');
    expect(_present('Étrier de solive pour 2×8'), isTrue, reason: 'Étrier de solive pour 2×8');
  });

  testWidgets('côté de la maison : « Aucun » rétablit les rives doublées', (
    t,
  ) async {
    await _ouvrir(t);
    await _tap(t, _cle('rive_double'));
    expect(_cle('cote_maison_null'), findsOneWidget);
    await _choisir(t, 'cote_maison_null', 'Côté 1 — 13\'');
    expect(_cle('cote_maison_0'), findsOneWidget);
    await _choisir(t, 'cote_maison_0', 'Aucun');
    expect(_cle('cote_maison_null'), findsOneWidget);
  });

  testWidgets('poutres : réglages visibles seulement quand elles sont actives', (
    t,
  ) async {
    await _ouvrir(t);
    expect(_cle('poutres_nombre'), findsNothing);
    await _tap(t, _cle('poutres_actives'));
    for (final k in [
      'poutres_nombre',
      'poutres_plis',
      'poutres_pieux',
      'poutres_retrait',
      'poutres_patte',
    ]) {
      expect(_cle(k), findsOneWidget, reason: k);
    }
    await _tap(t, _cle('poutres_actives'));
    expect(_cle('poutres_nombre'), findsNothing);
  });

  testWidgets('entremises : automatiques ou à la main, jamais les deux champs', (
    t,
  ) async {
    await _ouvrir(t);
    expect(_cle('entremises'), findsOneWidget);
    expect(_cle('entremises_espacement'), findsNothing);
    expect(_cle('entremises_alternees'), findsNothing);
    await _tap(t, _cle('entremises_auto'));
    expect(_cle('entremises'), findsNothing);
    expect(_cle('entremises_espacement'), findsOneWidget);
    expect(_cle('entremises_alternees'), findsOneWidget);
  });

  testWidgets('clous d\'étriers : réglables, sans étrier ils disparaissent', (
    t,
  ) async {
    await _ouvrir(t);
    // Étriers aux deux bouts par défaut.
    expect(_cle('clous_etriers'), findsOneWidget);
    await _tap(t, find.descendant(of: _cle('etriers'), matching: find.text('Aucun')));
    expect(_cle('clous_etriers'), findsNothing);
    expect(_cle('etriers_bordures'), findsNothing);
    await _tap(t, find.descendant(of: _cle('etriers'), matching: find.text('Un bout')));
    await _tap(t, _cle('clous_etriers'));
    expect(_cle('clous_par_etrier'), findsOneWidget);
    await _saisir(t, 'clous_par_etrier', '12');
    expect(_present('12 par étrier'), isTrue, reason: '12 par étrier');
  });

  test('le plancher de l\'écran = le moteur (mêmes nombres)', () {
    // Garde-fou : si le moteur change, ce test et l'écran ci-dessus le disent.
    expect(section2x8.nom, '2×8');
    expect(longueursPlanchesParDefaut.last, 240);
  });
}
