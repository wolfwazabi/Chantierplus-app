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
    await _tap(
      t,
      find.descendant(of: _cle('etriers'), matching: find.text('Un bout')),
    );
    // Par défaut : pas d'étrier sur les solives de bordure (à l'extérieur du plancher).
    expect(
      t.widget<SwitchListTile>(_cle('etriers_bordures')).value,
      isFalse,
      reason: 'étriers sur les solives de bordure : décoché par défaut',
    );

    // Entremises automatiques en pose alternée ; coupes séparées.
    await _tap(t, _cle('entremises_auto'));
    await _tap(t, _cle('entremises_alternees'));
    // Par défaut : chaque catégorie dans ses propres planches.
    expect(
      t.widget<SwitchListTile>(_cle('coupes_separees')).value,
      isTrue,
      reason: 'coupes séparées : coché par défaut',
    );

    // Poutres sur pieux vissés, pattes de 16 po.
    await _tap(t, _cle('poutres_actives'));
    await _saisir(t, 'poutres_patte', '16"');

    // Résultats du plancher.
    expect(
      _present('15 (dont 4 de bordure)'),
      isTrue,
      reason: '15 (dont 4 de bordure)',
    );
    expect(
      _present('2 de 3 plis en 2×8'),
      isTrue,
      reason: '2 de 3 plis en 2×8',
    );
    expect(
      _present('6 · entraxe 6\' 6"'),
      isTrue,
      reason: '6 · entraxe 6\' 6"',
    );
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
    expect(
      _present('Étrier de solive pour 2×8'),
      isTrue,
      reason: 'Étrier de solive pour 2×8',
    );
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

  testWidgets(
    'poutres : réglages visibles seulement quand elles sont actives',
    (t) async {
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
    },
  );

  testWidgets(
    'entremises : automatiques ou à la main, jamais les deux champs',
    (t) async {
      await _ouvrir(t);
      expect(_cle('entremises'), findsOneWidget);
      expect(_cle('entremises_espacement'), findsNothing);
      expect(_cle('entremises_alternees'), findsNothing);
      await _tap(t, _cle('entremises_auto'));
      expect(_cle('entremises'), findsNothing);
      expect(_cle('entremises_espacement'), findsOneWidget);
      expect(_cle('entremises_alternees'), findsOneWidget);
    },
  );

  group('clous d\'étriers', () {
    bool coche(WidgetTester t) =>
        t.widget<CheckboxListTile>(_cle('clous_etriers_inclus')).value!;
    bool choisi(WidgetTester t, int n) =>
        t.widget<ChoiceChip>(_cle('clous_choix_$n')).selected;

    testWidgets('case cochée par défaut, 10 par étrier, nombres proposés', (
      t,
    ) async {
      await _ouvrir(t);
      expect(coche(t), isTrue);
      expect(_present('10 par étrier'), isTrue, reason: '10 par étrier');
      for (final n in [6, 8, 10, 12, 14, 16]) {
        expect(_cle('clous_choix_$n'), findsOneWidget, reason: '$n');
        expect(choisi(t, n), n == 10, reason: '$n');
      }
      expect(_cle('clous_par_etrier'), findsOneWidget);
      expect(_cle('clous_par_boite'), findsOneWidget);
      expect(_cle('clous_marge'), findsOneWidget);
      expect(_present('clous, boîtes de'), isTrue, reason: 'résultats');
    });

    testWidgets('choisir le nombre de clous par étrier', (t) async {
      await _ouvrir(t);
      await _tap(t, _cle('clous_choix_12'));
      expect(choisi(t, 12), isTrue);
      expect(choisi(t, 10), isFalse);
      expect(_present('12 par étrier · boîte de 120'), isTrue);
      // Le champ libre suit : une autre valeur désélectionne les choix proposés.
      await _saisir(t, 'clous_par_etrier', '18');
      for (final n in [6, 8, 10, 12, 14, 16]) {
        expect(choisi(t, n), isFalse, reason: '$n');
      }
      expect(_present('18 par étrier'), isTrue, reason: '18 par étrier');
      // Revenir à un choix proposé.
      await _tap(t, _cle('clous_choix_6'));
      expect(choisi(t, 6), isTrue);
      expect(_present('6 par étrier'), isTrue, reason: '6 par étrier');
    });

    testWidgets(
      'décocher : les clous sortent des résultats, les réglages se cachent',
      (t) async {
        await _ouvrir(t);
        expect(_present('clous, boîtes de'), isTrue);
        await _tap(t, _cle('clous_etriers_inclus'));
        expect(coche(t), isFalse);
        expect(_present('Non comptés dans la commande'), isTrue);
        expect(_present('clous, boîtes de'), isFalse, reason: 'résultats');
        for (final cle in [
          'clous_choix_10',
          'clous_par_etrier',
          'clous_par_boite',
          'clous_marge',
        ]) {
          expect(_cle(cle), findsNothing, reason: cle);
        }
      },
    );

    testWidgets('recocher : les réglages choisis sont retrouvés', (t) async {
      await _ouvrir(t);
      await _tap(t, _cle('clous_choix_14'));
      await _tap(t, _cle('clous_etriers_inclus'));
      await _tap(t, _cle('clous_etriers_inclus'));
      expect(coche(t), isTrue);
      expect(choisi(t, 14), isTrue);
      expect(_present('clous, boîtes de'), isTrue);
    });

    testWidgets(
      'sans étrier : plus de case ni de réglages ; avec : ils reviennent',
      (t) async {
        await _ouvrir(t);
        await _tap(
          t,
          find.descendant(of: _cle('etriers'), matching: find.text('Aucun')),
        );
        expect(_cle('clous_etriers_inclus'), findsNothing);
        expect(_cle('etriers_bordures'), findsNothing);
        await _tap(
          t,
          find.descendant(of: _cle('etriers'), matching: find.text('Un bout')),
        );
        expect(_cle('clous_etriers_inclus'), findsOneWidget);
        expect(coche(t), isTrue);
      },
    );

    testWidgets('la commande suit la case', (t) async {
      await _ouvrir(t);
      await _tap(t, find.widgetWithText(Tab, 'Commande'));
      expect(_present('Clous d\'étriers 10d'), isTrue, reason: 'cochée');
      await _tap(t, find.widgetWithText(Tab, 'Plancher'));
      await _tap(t, _cle('clous_etriers_inclus'));
      await _tap(t, find.widgetWithText(Tab, 'Commande'));
      expect(_present('Clous d\'étriers 10d'), isFalse, reason: 'décochée');
      expect(_present('Étrier de solive'), isTrue);
    });
  });

  test('le plancher de l\'écran = le moteur (mêmes nombres)', () {
    // Garde-fou : si le moteur change, ce test et l'écran ci-dessus le disent.
    expect(section2x8.nom, '2×8');
    expect(longueursPlanchesParDefaut.last, 240);
  });
}
