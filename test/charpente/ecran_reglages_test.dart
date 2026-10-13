// Écran Charpente allégé : réglages repliés avec leur résumé, menu de l'entraxe, exemple de
// saisie pendant la saisie seulement, et réglages habituels (garder, remettre, nouveau calcul,
// lecture d'un plan).
import 'dart:convert';

import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/reglages_habituels.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/screens/charpente/ecran_escalier.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:construction_app/services/selecteur_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../doubles/faux_plans.dart';
import 'aide_reglages.dart';

const _cleHabitudes = 'charpente.reglagesHabituels';

Finder _cle(String k) => find.byKey(ValueKey(k));
Finder _champ(String cle) =>
    find.descendant(of: _cle(cle), matching: find.byType(TextField));

Widget _ecran({List<Map<String, dynamic>?>? reglagesRecus}) => MaterialApp(
  home: Scaffold(
    body: CharpenteScreen(
      companyId: 'A',
      chantierId: 'chA',
      connecte: true,
      listeEnregistrees: const Text('(aucune commande)'),
      appelLecturePlan: (fichiers, precisions, reglages) async {
        reglagesRecus?.add(reglages);
        return lectureGarage();
      },
      selecteurPlans: SelecteurPlansFaux(
        fichiers: [
          ChoixPlans([planFaux('plan.pdf')]),
        ],
      ),
    ),
  ),
);

Future<void> _ouvrir(
  WidgetTester t, {
  List<Map<String, dynamic>?>? recus,
}) async {
  t.view.physicalSize = const Size(900, 7000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(_ecran(reglagesRecus: recus));
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

Future<void> _onglet(WidgetTester t, String libelle) =>
    _tap(t, find.widgetWithText(Tab, libelle));

String _barre(WidgetTester t, String cle) => t
    .widgetList<Text>(
      find.descendant(of: _cle('habitudes_$cle'), matching: find.byType(Text)),
    )
    .first
    .data!;

bool _interrupteur(WidgetTester t, String cle) =>
    t.widget<SwitchListTile>(_cle(cle)).value;

Future<String?> _gardes() async =>
    (await SharedPreferences.getInstance()).getString(_cleHabitudes);

/// Réglages d'un entrepreneur : rives doubles, entremises automatiques alternées.
ReglagesHabituels _habitudesRivesDoubles() {
  const base = ProjetCharpente();
  final p = base.copieAvec(
    plancher: base.plancher.copieAvec(
      riveDouble: true,
      entremisesAuto: true,
      entremisesAlternees: true,
    ),
  );
  return ReglagesHabituels.vides.avecPlancherDe(p);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  group('réglages repliés', () {
    testWidgets(
      'chaque groupe montre le résumé de ses valeurs, ses champs à l\'ouverture',
      (t) async {
        await _ouvrir(t);
        expect(groupesDeReglages(), [
          'groupe_direction_rives',
          'groupe_etriers',
          'groupe_entremises',
          'groupe_poutres',
          'groupe_sous_plancher',
          'groupe_bois',
        ]);
        expect(
          find.text('Direction automatique · rives simples · bordures simples'),
          findsOneWidget,
        );
        expect(
          find.text('Deux bouts · solives intérieures · 10 clous par étrier'),
          findsOneWidget,
        );
        expect(find.text('Aucune'), findsNWidgets(2)); // entremises, poutres
        expect(
          find.text('4 × 8 pi · joints décalés de 2\' · marge 0 %'),
          findsOneWidget,
        );
        expect(
          find.text('Planches de 8\' à 20\' · coupes séparées'),
          findsOneWidget,
        );
        // Repliés : les champs ne sont pas affichés.
        expect(_cle('rive_double'), findsNothing);
        expect(_cle('etriers'), findsNothing);

        await deplierReglages(t, ['direction_rives']);
        expect(_cle('rive_double'), findsOneWidget);
        // Le résumé suit la valeur.
        await _tap(t, _cle('rive_double'));
        expect(
          find.text('Direction automatique · rives doubles · bordures simples'),
          findsOneWidget,
        );
      },
    );

    testWidgets('un groupe ouvert le reste après un changement d\'onglet', (
      t,
    ) async {
      await _ouvrir(t);
      await deplierReglages(t, ['etriers']);
      expect(_cle('etriers'), findsOneWidget);
      await _onglet(t, 'Commande');
      await _onglet(t, 'Plancher');
      expect(_cle('etriers'), findsOneWidget);
      expect(
        _cle('rive_double'),
        findsNothing,
        reason: 'les autres restent repliés',
      );
    });

    testWidgets(
      'résumés : étriers, entremises et poutres suivent les réglages',
      (t) async {
        await _ouvrir(t);
        await deplierReglages(t, ['etriers', 'entremises', 'poutres']);
        await _tap(
          t,
          find.descendant(of: _cle('etriers'), matching: find.text('Aucun')),
        );
        expect(find.text('Aucun étrier'), findsOneWidget);
        await _tap(t, _cle('entremises_auto'));
        expect(find.text('Automatiques : une rangée aux 10\''), findsOneWidget);
        await _tap(t, _cle('poutres_actives'));
        expect(
          find.text('2 poutres de 3 plis en 2×8 · 3 pieux par poutre'),
          findsOneWidget,
        );
      },
    );

    testWidgets('l\'exemple de saisie n\'apparaît que dans le champ en cours', (
      t,
    ) async {
      await _ouvrir(t);
      expect(find.textContaining('un nombre seul'), findsNothing);
      await t.tap(_champ('rect_longueur'));
      await t.pumpAndSettle();
      expect(find.textContaining('un nombre seul'), findsOneWidget);
    });

    testWidgets(
      'escalier : détails des marches et limons repliés, avec leur résumé',
      (t) async {
        t.view.physicalSize = const Size(900, 9000);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: EcranEscalier())),
        );
        await t.pumpAndSettle();
        expect(
          find.text('Marche 1 1/2" · nez 3/4" · contremarches ouvertes'),
          findsOneWidget,
        );
        expect(find.text('2×12 · entraxe maximal 1\' 4"'), findsOneWidget);
        expect(_cle('escalier_nez'), findsNothing);
        await deplierReglages(t, ['escalier_marches']);
        expect(_cle('escalier_nez'), findsOneWidget);
      },
    );
  });

  group('entraxe', () {
    testWidgets(
      'menu des valeurs courantes, et « Autre… » pour une autre valeur',
      (t) async {
        await _ouvrir(t);
        expect(_cle('entraxe_menu_16.0'), findsOneWidget);
        await _tap(t, _cle('entraxe_menu_16.0'));
        await t.tap(find.text('12 po').last);
        await t.pumpAndSettle();
        expect(_cle('entraxe_menu_12.0'), findsOneWidget);

        await _tap(t, _cle('entraxe_menu_12.0'));
        await t.tap(find.text('Autre…').last);
        await t.pumpAndSettle();
        final champ = find.descendant(
          of: _cle('entraxe_autre'),
          matching: find.byType(TextField),
        );
        // Hors des bornes : OK reste inactif.
        await t.enterText(champ, '70');
        await t.pumpAndSettle();
        expect(
          t.widget<FilledButton>(_cle('entraxe_autre_ok')).onPressed,
          isNull,
        );
        await t.enterText(champ, '13,5');
        await t.pumpAndSettle();
        await t.tap(_cle('entraxe_autre_ok'));
        await t.pumpAndSettle();
        expect(_cle('entraxe_menu_13.5'), findsOneWidget);
        expect(find.text('13,5 po'), findsOneWidget);
      },
    );
  });

  group('réglages habituels', () {
    testWidgets('garder, voir la différence, remettre, annuler', (t) async {
      await _ouvrir(t);
      expect(_barre(t, 'plancher'), 'Aucun réglage habituel');
      expect(_cle('habitudes_remettre_plancher'), findsNothing);

      await deplierReglages(t, ['direction_rives']);
      await _tap(t, _cle('rive_double'));
      await _tap(t, _cle('habitudes_garder_plancher'));
      expect(
        find.textContaining('Réglages du plancher gardés'),
        findsOneWidget,
      );
      expect(_barre(t, 'plancher'), 'Vos réglages habituels');
      expect(_cle('habitudes_garder_plancher'), findsNothing);
      final gardes = ReglagesHabituels.depuis(jsonDecode((await _gardes())!));
      expect(gardes.plancher!['riveDouble'], isTrue);
      expect(gardes.murs, isNull, reason: 'seulement l\'onglet Plancher');

      // Une mesure change : toujours les réglages habituels.
      await t.enterText(_champ('rect_longueur'), "20'");
      await t.pumpAndSettle();
      expect(_barre(t, 'plancher'), 'Vos réglages habituels');

      // Un réglage change : la barre le dit, on peut remettre.
      await _tap(t, _cle('bordure_double'));
      expect(_barre(t, 'plancher'), 'Différents de vos habitudes');
      await _tap(t, _cle('habitudes_remettre_plancher'));
      expect(_interrupteur(t, 'bordure_double'), isFalse);
      expect(_interrupteur(t, 'rive_double'), isTrue);
      expect(_barre(t, 'plancher'), 'Vos réglages habituels');
      // La mesure est restée.
      expect(
        t.widget<TextField>(_champ('rect_longueur')).controller!.text,
        "20'",
      );

      // « Annuler » rétablit le réglage d'avant.
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(_interrupteur(t, 'bordure_double'), isTrue);
      expect(_barre(t, 'plancher'), 'Différents de vos habitudes');
    });

    testWidgets('« Garder » de nouveau remplace les réglages habituels', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        _cleHabitudes: jsonEncode(_habitudesRivesDoubles().toJson()),
      });
      await _ouvrir(t);
      await deplierReglages(t, ['direction_rives']);
      await _tap(t, _cle('rive_double'));
      expect(_barre(t, 'plancher'), 'Différents de vos habitudes');
      await _tap(t, _cle('habitudes_garder_plancher'));
      expect(_barre(t, 'plancher'), 'Vos réglages habituels');
      final gardes = ReglagesHabituels.depuis(jsonDecode((await _gardes())!));
      expect(gardes.plancher!['riveDouble'], isFalse);
      expect(gardes.plancher!['entremisesAuto'], isTrue);
    });

    testWidgets(
      'un chantier sans calcul en cours part des réglages habituels',
      (t) async {
        SharedPreferences.setMockInitialValues({
          _cleHabitudes: jsonEncode(_habitudesRivesDoubles().toJson()),
        });
        await _ouvrir(t);
        expect(_barre(t, 'plancher'), 'Vos réglages habituels');
        expect(
          find.text('Direction automatique · rives doubles · bordures simples'),
          findsOneWidget,
        );
        expect(
          find.text('Automatiques : une rangée aux 10\' · pose alternée'),
          findsOneWidget,
        );
      },
    );

    testWidgets('un calcul en cours garde ses propres réglages', (t) async {
      const brouillon = ProjetCharpente(nom: 'Brouillon');
      SharedPreferences.setMockInitialValues({
        _cleHabitudes: jsonEncode(_habitudesRivesDoubles().toJson()),
        'charpente.brouillon.chA': jsonEncode({
          'projet': brouillon.toJson(),
          'manuelles': [],
        }),
      });
      await _ouvrir(t);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('charpente_nom')))
            .controller!
            .text,
        'Brouillon',
      );
      expect(_barre(t, 'plancher'), 'Différents de vos habitudes');
      expect(
        find.text('Direction automatique · rives simples · bordures simples'),
        findsOneWidget,
      );
    });

    testWidgets('nouveau calcul : il repart des réglages habituels', (t) async {
      SharedPreferences.setMockInitialValues({
        _cleHabitudes: jsonEncode(_habitudesRivesDoubles().toJson()),
      });
      await _ouvrir(t);
      await t.enterText(_champ('rect_longueur'), "20'");
      await t.pumpAndSettle();
      await deplierReglages(t, ['direction_rives']);
      await _tap(t, _cle('rive_double'));
      await _tap(t, _cle('charpente_nouveau'));
      expect(
        find.textContaining('part de vos réglages habituels'),
        findsOneWidget,
      );
      await t.tap(find.text('Effacer'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(_champ('rect_longueur')).controller!.text,
        "13'",
      );
      expect(_interrupteur(t, 'rive_double'), isTrue);
      expect(_barre(t, 'plancher'), 'Vos réglages habituels');
    });

    testWidgets('murs : leurs réglages se gardent à part', (t) async {
      await _ouvrir(t);
      await _onglet(t, 'Murs');
      await _tap(t, _cle('murs_actifs'));
      expect(_barre(t, 'murs'), 'Aucun réglage habituel');
      await deplierReglages(t, ['ossature_murs']);
      await _tap(t, _cle('murs_precoupes'));
      expect(
        find.text('2 lisses hautes · montants coupés sur place'),
        findsOneWidget,
      );
      await _tap(t, _cle('habitudes_garder_murs'));
      expect(find.textContaining('Réglages des murs gardés'), findsOneWidget);
      expect(_barre(t, 'murs'), 'Vos réglages habituels');
      final gardes = ReglagesHabituels.depuis(jsonDecode((await _gardes())!));
      expect(gardes.plancher, isNull);
      expect((gardes.murs!['params'] as Map)['precoupes'], isFalse);
      await _onglet(t, 'Plancher');
      expect(_barre(t, 'plancher'), 'Aucun réglage habituel');
    });

    testWidgets(
      'lecture d\'un plan : les réglages habituels partent avec le plan',
      (t) async {
        final habitudes = _habitudesRivesDoubles();
        SharedPreferences.setMockInitialValues({
          _cleHabitudes: jsonEncode(habitudes.toJson()),
        });
        final recus = <Map<String, dynamic>?>[];
        await _ouvrir(t, recus: recus);
        await _tap(t, _cle('charpente_lire_plan'));
        await _tap(t, _cle('plan_choisir_fichier'));
        await _tap(t, _cle('plan_analyser'));
        expect(recus, hasLength(1));
        expect(
          jsonEncode(recus.single),
          jsonEncode(habitudes.pourLecturePlan()),
        );
      },
    );

    testWidgets(
      'lecture d\'un plan sans réglages habituels : rien n\'est envoyé',
      (t) async {
        final recus = <Map<String, dynamic>?>[];
        await _ouvrir(t, recus: recus);
        await _tap(t, _cle('charpente_lire_plan'));
        await _tap(t, _cle('plan_choisir_fichier'));
        await _tap(t, _cle('plan_analyser'));
        expect(recus, [null]);
      },
    );
  });
}
