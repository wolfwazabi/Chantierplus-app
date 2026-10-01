import 'package:construction_app/models/extra_chantier.dart';
import 'package:construction_app/screens/extras/formulaire_extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _extra = ExtraChantier(
  id: 'x1',
  companyId: 'A',
  chantierId: 'chA',
  description: 'Cloison',
  mainOeuvre: '3 gars, 1 compagnon, 1 apprenti — 4 h',
  dateTravaux: '2026-10-01',
  photoUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/p.jpg',
  cheminPhoto: 'chantiers/A/chA/chantier_extras/p.jpg',
);

void main() {
  Future<List<ExtraSaisie>> ouvrir(
    WidgetTester tester, {
    bool connecte = true,
    ExtraChantier? initial,
    bool reussite = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final recues = <ExtraSaisie>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FormulaireExtra(
              initial: initial,
              connecte: connecte,
              libelleBouton: initial == null ? 'Ajouter' : 'Enregistrer',
              onValider: (s) async {
                recues.add(s);
                return reussite;
              },
            ),
          ),
        ),
      ),
    );
    return recues;
  }

  Future<void> remplir(
    WidgetTester tester, {
    String? desc,
    String? mainOeuvre,
  }) async {
    if (desc != null) {
      await tester.enterText(
        find.byKey(const ValueKey('extra_description')),
        desc,
      );
    }
    if (mainOeuvre != null) {
      await tester.enterText(
        find.byKey(const ValueKey('extra_main_oeuvre')),
        mainOeuvre,
      );
    }
    await tester.pump();
  }

  Future<void> valider(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('extra_valider')));
    await tester.pumpAndSettle();
  }

  String erreur(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('extra_erreur'))).data!;

  String texteDe(WidgetTester tester, String cle) =>
      tester.widget<TextField>(find.byKey(ValueKey(cle))).controller!.text;

  testWidgets('plus de champs « hommes » ni « temps » : un seul champ libre', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(find.byKey(const ValueKey('extra_hommes')), findsNothing);
    expect(find.byKey(const ValueKey('extra_heures')), findsNothing);
    expect(find.byKey(const ValueKey('extra_resume')), findsNothing);
    expect(find.byKey(const ValueKey('extra_main_oeuvre')), findsOneWidget);
    expect(find.text('Main-d\'œuvre et temps'), findsOneWidget);
  });

  testWidgets(
    'description et main-d\'œuvre sont obligatoires ; la photo est facultative',
    (tester) async {
      final recues = await ouvrir(tester);
      await valider(tester);
      expect(erreur(tester), contains('Décrivez'));

      await remplir(tester, desc: 'Cloison');
      await valider(tester);
      expect(erreur(tester), contains('main-d\'œuvre'));

      await remplir(tester, mainOeuvre: '   ');
      await valider(tester);
      expect(erreur(tester), contains('main-d\'œuvre'));
      expect(recues, isEmpty);

      await remplir(tester, mainOeuvre: '3 gars, 1 compagnon, 1 apprenti');
      await valider(tester);
      expect(recues, hasLength(1));
      expect(recues.single.description, 'Cloison');
      expect(recues.single.mainOeuvre, '3 gars, 1 compagnon, 1 apprenti');
      expect(recues.single.nouvellePhoto, isNull);
      expect(recues.single.retirerPhoto, isFalse);
      expect(dateIso(recues.single.date), dateIso(DateTime.now()));
    },
  );

  testWidgets('texte libre : n\'importe quelle formulation est acceptée', (
    tester,
  ) async {
    final recues = await ouvrir(tester);
    for (final texte in [
      '2 gars',
      '1 compagnon + 1 apprenti, 3 heures chacun',
      'Marc et Luc — demi-journée',
      '4',
    ]) {
      await remplir(tester, desc: 'Porte', mainOeuvre: texte);
      await valider(tester);
    }
    expect(recues.map((r) => r.mainOeuvre), [
      '2 gars',
      '1 compagnon + 1 apprenti, 3 heures chacun',
      'Marc et Luc — demi-journée',
      '4',
    ]);
  });

  testWidgets(
    'ajout réussi : formulaire vidé ; échec : la saisie est conservée',
    (tester) async {
      await ouvrir(tester);
      await remplir(tester, desc: 'Porte', mainOeuvre: '2 gars, 3 h');
      await valider(tester);
      expect(texteDe(tester, 'extra_description'), isEmpty);
      expect(texteDe(tester, 'extra_main_oeuvre'), isEmpty);

      await ouvrir(tester, reussite: false);
      await remplir(tester, desc: 'Porte', mainOeuvre: '2 gars, 3 h');
      await valider(tester);
      expect(texteDe(tester, 'extra_description'), 'Porte');
      expect(texteDe(tester, 'extra_main_oeuvre'), '2 gars, 3 h');
    },
  );

  testWidgets('non connecté : tout est désactivé', (tester) async {
    await ouvrir(tester, connecte: false);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('extra_main_oeuvre')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('extra_valider')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('extra_prendre_photo')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'modification : champs préremplis, retirer la photo est signalé',
    (tester) async {
      final recues = await ouvrir(tester, initial: _extra);
      expect(texteDe(tester, 'extra_description'), 'Cloison');
      expect(
        texteDe(tester, 'extra_main_oeuvre'),
        '3 gars, 1 compagnon, 1 apprenti — 4 h',
      );
      expect(find.text('Date : 01/10/2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('extra_retirer_photo')));
      await tester.pump();
      await valider(tester);
      expect(recues.single.retirerPhoto, isTrue);
      expect(recues.single.nouvellePhoto, isNull);
    },
  );

  testWidgets('modification sans toucher à la photo : elle est conservée', (
    tester,
  ) async {
    final recues = await ouvrir(tester, initial: _extra);
    await remplir(tester, mainOeuvre: '4 gars, 5 h');
    await valider(tester);
    expect(recues.single.retirerPhoto, isFalse);
    expect(recues.single.mainOeuvre, '4 gars, 5 h');
  });
}
