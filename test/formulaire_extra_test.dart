import 'package:construction_app/models/extra_chantier.dart';
import 'package:construction_app/screens/extras/formulaire_extra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _extra = ExtraChantier(
  id: 'x1',
  companyId: 'A',
  chantierId: 'chA',
  description: 'Cloison',
  nombreHommes: 2,
  heures: 3.5,
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
    String? hommes,
    String? heures,
  }) async {
    if (desc != null) {
      await tester.enterText(
        find.byKey(const ValueKey('extra_description')),
        desc,
      );
    }
    if (hommes != null) {
      await tester.enterText(
        find.byKey(const ValueKey('extra_hommes')),
        hommes,
      );
    }
    if (heures != null) {
      await tester.enterText(
        find.byKey(const ValueKey('extra_heures')),
        heures,
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

  testWidgets(
    'description, hommes et temps sont obligatoires ; la photo est facultative',
    (tester) async {
      final recues = await ouvrir(tester);
      await valider(tester);
      expect(erreur(tester), contains('Décrivez'));

      await remplir(tester, desc: 'Cloison');
      await valider(tester);
      expect(erreur(tester), contains('hommes'));

      await remplir(tester, hommes: '0');
      await valider(tester);
      expect(erreur(tester), contains('hommes'));

      await remplir(tester, hommes: '2');
      await valider(tester);
      expect(erreur(tester), contains('Temps'));

      await remplir(tester, heures: '0');
      await valider(tester);
      expect(erreur(tester), contains('Temps'));
      expect(recues, isEmpty);

      await remplir(tester, heures: '3,5');
      await valider(tester);
      expect(recues, hasLength(1));
      expect(recues.single.description, 'Cloison');
      expect(recues.single.nombreHommes, 2);
      expect(recues.single.heures, 3.5);
      expect(recues.single.nouvellePhoto, isNull);
      expect(recues.single.retirerPhoto, isFalse);
      expect(dateIso(recues.single.date), dateIso(DateTime.now()));
    },
  );

  testWidgets('le total d\'heures-homme s\'affiche en direct', (tester) async {
    await ouvrir(tester);
    expect(find.byKey(const ValueKey('extra_resume')), findsNothing);
    await remplir(tester, hommes: '3', heures: '2.5');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('extra_resume'))).data,
      '3 hommes × 2.5 h = 7.5 h-homme',
    );
    await remplir(tester, hommes: 'x');
    expect(find.byKey(const ValueKey('extra_resume')), findsNothing);
  });

  testWidgets(
    'ajout réussi : formulaire vidé ; échec : la saisie est conservée',
    (tester) async {
      await ouvrir(tester);
      await remplir(tester, desc: 'Porte', hommes: '1', heures: '2');
      await valider(tester);
      expect(texteDe(tester, 'extra_description'), isEmpty);
      expect(texteDe(tester, 'extra_hommes'), isEmpty);

      await ouvrir(tester, reussite: false);
      await remplir(tester, desc: 'Porte', hommes: '1', heures: '2');
      await valider(tester);
      expect(texteDe(tester, 'extra_description'), 'Porte');
    },
  );

  testWidgets('non connecté : tout est désactivé', (tester) async {
    await ouvrir(tester, connecte: false);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('extra_description')))
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
      expect(texteDe(tester, 'extra_hommes'), '2');
      expect(texteDe(tester, 'extra_heures'), '3.5');
      expect(find.text('01/10/2026'), findsOneWidget);

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
    await remplir(tester, desc: 'Cloison corrigée');
    await valider(tester);
    expect(recues.single.retirerPhoto, isFalse);
    expect(recues.single.description, 'Cloison corrigée');
  });
}
