// Plateforme : le dessus du plancher en composite dans le projet de charpente (enregistrement,
// calcul, commande, 3D, onglet Plancher).

import 'package:construction_app/charpente/commande.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/solides.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aide_reglages.dart';

const _plateforme = ProjetCharpente(
  plancher: ParametresPlancher(composite: 'fiberon_sanctuary'),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  group('enregistrement', () {
    test('le produit est gardé et relu', () {
      final j = _plateforme.toJson();
      expect((j['plancher'] as Map)['composite'], 'fiberon_sanctuary');
      final relu = ProjetCharpente.fromJson(j);
      expect(relu.plancher.composite, 'fiberon_sanctuary');
    });

    test('un projet en feuilles n\'a pas la clé (rien ne change pour eux)', () {
      final j = const ProjetCharpente().toJson();
      expect((j['plancher'] as Map).containsKey('composite'), isFalse);
      expect(ProjetCharpente.fromJson(j).plancher.composite, isNull);
    });

    test('un produit inconnu est refusé', () {
      final j = _plateforme.toJson();
      (j['plancher'] as Map)['composite'] = 'inconnu';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
    });
  });

  group('calcul du projet', () {
    final res = calculerProjet(_plateforme);

    test('le composite est calculé sur le plancher', () {
      expect(res.terrasse, isNotNull);
      expect(res.erreurTerrasse, isNull);
      expect(res.terrasse!.produit.id, 'fiberon_sanctuary');
    });

    test('commande : planches, fascias, attaches, vis, blocage ; pas de sous-plancher', () {
      final articles = [
        for (final l in res.commande.lignes) '${l.categorie.name}|${l.article}',
      ];
      bool a(String debut) => articles.any((x) => x.startsWith(debut));
      expect(
        a('composite|Planches Fiberon Sanctuary, Concordia à rive carrée ×'),
        isTrue,
      );
      expect(
        a('composite|Planches Fiberon Sanctuary, Concordia rainurées ×'),
        isTrue,
      );
      expect(a('composite|Fascias Fiberon 11 1/4" ×'), isTrue);
      expect(
        a('quincaillerie|Attaches cachées Phantom Universal (boîte de 90)'),
        isTrue,
      );
      expect(a('quincaillerie|Vis et bouchons'), isTrue);
      expect(a('quincaillerie|Vis de fascia de la couleur'), isTrue);
      expect(
        res.commande.lignes.any(
          (l) => l.usage == 'Plancher (blocage du cadre)',
        ),
        isTrue,
      );
      expect(articles.any((x) => x.contains('Sous-plancher')), isFalse);
      expect(libelleCategorie(CategorieCommande.composite), 'Composite');
    });

    test('3D : planches de composite et fascias, plus de feuilles', () {
      final matieres = {for (final s in res.scene.solides) s.matiere};
      expect(matieres, containsAll([Matiere.composite, Matiere.fascia]));
      expect(matieres, isNot(contains(Matiere.sousPlancher)));
      // Le dessus du composite est à 0 (comme le dessus du sous-plancher).
      expect(res.scene.max.z, closeTo(0, 1e-9));
    });

    test('plateforme trop petite : message, le plancher reste calculé', () {
      final petit = calculerProjet(
        const ProjetCharpente(
          plancher: ParametresPlancher(
            forme: FormeRectangle(14, 14),
            composite: 'generique',
          ),
        ),
      );
      expect(petit.plancher, isNotNull);
      expect(petit.terrasse, isNull);
      expect(petit.erreurTerrasse, contains('trop petite'));
      expect(petit.aDesErreurs, isTrue);
    });
  });

  testWidgets(
    'onglet Plancher : dessus en feuilles ou en composite, avec le produit',
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
      await deplierReglages(t, ['sous_plancher']);
      expect(find.text('Dessus du plancher'), findsOneWidget);
      expect(find.textContaining('Feuilles de sous-plancher'), findsOneWidget);
      await t.tap(find.text('Composite'));
      await t.pumpAndSettle();
      // Le produit, sa fiche ; les réglages des feuilles disparaissent.
      expect(
        find.byKey(const ValueKey('plancher_produit_generique')),
        findsOneWidget,
      );
      final fiche = t
          .widget<Text>(find.byKey(const ValueKey('plancher_produit_fiche')))
          .data!;
      expect(fiche, contains('Cadre de planches à rive carrée en onglet'));
      expect(
        fiche,
        contains('solives aux ${formatLongueur(16, metrique: false)} au plus'),
      );
      expect(find.text('Format des feuilles'), findsNothing);
      // Résultats : le composite à la place des feuilles.
      expect(find.textContaining('Feuilles de sous-plancher'), findsNothing);
      expect(find.text('Composite Composite courant'), findsOneWidget);
      expect(find.textContaining('planches de cadre'), findsOneWidget);
      // La largeur de la première et de la dernière planche (jamais une lisière).
      expect(find.text('Première et dernière planche'), findsOneWidget);
      expect(find.textContaining('refendues à'), findsOneWidget);
      // Retour aux feuilles.
      await t.tap(find.text('Feuilles'));
      await t.pumpAndSettle();
      expect(find.text('Format des feuilles'), findsOneWidget);
      expect(find.textContaining('Feuilles de sous-plancher'), findsOneWidget);
    },
  );
}
