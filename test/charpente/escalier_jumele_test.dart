// Escalier jumelé au plancher dans le projet de charpente : enregistrement, calcul, place sur
// le côté choisi, commande et onglet.

import 'dart:math' as math;

import 'package:construction_app/charpente/escalier_projet.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plateforme de 13 pi × 10 pi 6 po (le projet par défaut) en composite, escalier de 3 pi au
/// centre du côté 1 (le bas, y = 0), 9 pi de haut.
const _projet = ProjetCharpente(
  plancher: ParametresPlancher(composite: 'trex_select'),
  escalierActif: true,
  escalier: ParametresEscalier(hauteur: 108, largeur: 36),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  group('enregistrement', () {
    test('les choix de l\'escalier sont gardés et relus', () {
      const e = ParametresEscalier(
        hauteur: 60,
        largeur: 48,
        giron: 11,
        nombreImpose: true,
        nombre: 8,
        contremarchesFermees: true,
        cote: 2,
        centre: false,
        distanceCoin: 24,
      );
      final relu = ParametresEscalier.fromJson(e.toJson());
      expect(relu.toJson(), e.toJson());
      final p = ProjetCharpente.fromJson(
        const ProjetCharpente(escalierActif: true, escalier: e).toJson(),
      );
      expect(p.escalierActif, isTrue);
      expect(p.escalier.toJson(), e.toJson());
    });

    test(
      'un projet sans escalier n\'a pas les clés (rien ne change pour eux)',
      () {
        final j = const ProjetCharpente().toJson();
        expect(j.containsKey('escalierActif'), isFalse);
        expect(j.containsKey('escalier'), isFalse);
        final p = ProjetCharpente.fromJson(j);
        expect(p.escalierActif, isFalse);
      },
    );

    test('une valeur mal formée est refusée', () {
      final j = _projet.toJson();
      (j['escalier'] as Map)['largeur'] = 'large';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
    });
  });

  group('calcul du projet', () {
    final res = calculerProjet(_projet);

    test('l\'escalier prend la hauteur de la plateforme et le composite du plancher', () {
      expect(res.erreurEscalier, isNull);
      final r = res.escalier!;
      expect(r.spec.hauteurTotale, 108);
      expect(r.spec.composite!.id, 'trex_select');
      // La plus haute contremarche est la fascia du plancher.
      expect(r.spec.contremarcheHautFournie, isTrue);
    });

    test('3D : l\'escalier descend du côté 1, au centre, sous le dessus du plancher', () {
      final esc = [
        for (final s in res.scene.solides)
          if (s.groupe.startsWith('escalier.')) s,
      ];
      expect(esc, isNotEmpty);
      final xs = [for (final s in esc) ...s.coque.map((p) => p.x)];
      final ys = [for (final s in esc) ...s.coque.map((p) => p.y)];
      // Centré sur le côté de 13 pi : de 60 à 96 po.
      expect(xs.reduce(math.min), closeTo(60, 0.01));
      expect(xs.reduce(math.max), closeTo(96, 0.01));
      // À l'extérieur de la rive (y < 0), jusqu'à la face de la fascia du plancher.
      expect(ys.reduce(math.max), lessThanOrEqualTo(0));
      // Du sol (−108) au dessus de la marche du haut, sous le plancher.
      expect(esc.map((s) => s.z0).reduce(math.min), closeTo(-108, 0.01));
      expect(esc.map((s) => s.z1).reduce(math.max), lessThan(0));
      expect(
        res.scene.infos.keys.any((k) => k.startsWith('escalier.limon')),
        isTrue,
      );
    });

    test('commande : limons, planches et vis avec celles du plancher', () {
      final lignes = res.commande.lignes;
      expect(lignes.any((l) => l.usage == 'Escalier (limons)'), isTrue);
      final rive = [
        for (final l in lignes)
          if (l.article.startsWith('Planches Trex Select à rive carrée')) l,
      ];
      // Le cadre du plancher et les marches : la même planche ; une longueur commune est
      // additionnée (jamais deux lignes pour le même article).
      expect(rive.any((l) => l.usage.contains('Plancher')), isTrue);
      expect(rive.any((l) => l.usage.contains('Escalier')), isTrue);
      final articles = [
        for (final l in lignes) '${l.categorie.name}|${l.article}',
      ];
      expect(articles.toSet(), hasLength(articles.length));
      expect(lignes.any((l) => l.usage == 'Escalier (2x12 à plat)'), isTrue);
    });
  });

  group('place sur le plancher : messages clairs', () {
    String? erreur(ParametresEscalier e, {int? maison}) => calculerProjet(
      ProjetCharpente(
        plancher: ParametresPlancher(coteMaison: maison),
        escalierActif: true,
        escalier: e,
      ),
    ).erreurEscalier;

    test('du côté de la maison : refusé', () {
      expect(
        erreur(const ParametresEscalier(cote: 2), maison: 2),
        contains('côté de la maison'),
      );
    });

    test('trop large pour le côté, ou trop loin du coin : refusé', () {
      expect(
        erreur(const ParametresEscalier(cote: 1, largeur: 130)),
        contains('ne rentre pas'),
      );
      expect(
        erreur(
          const ParametresEscalier(cote: 0, centre: false, distanceCoin: 140),
        ),
        contains('du coin'),
      );
      expect(
        erreur(
          const ParametresEscalier(cote: 0, centre: false, distanceCoin: 120),
        ),
        isNull,
      );
    });

    test('un côté qui n\'existe pas : refusé', () {
      expect(
        erreur(const ParametresEscalier(cote: 9)),
        contains('n\'existe pas'),
      );
    });

    test('sans plancher : l\'escalier est calculé seul, en bois', () {
      final res = calculerProjet(
        const ProjetCharpente(plancherActif: false, escalierActif: true),
      );
      expect(res.erreurEscalier, isNull);
      expect(res.escalier!.spec.composite, isNull);
      expect(res.scene.estVide, isFalse);
    });
  });

  testWidgets(
    'onglet Escalier : inclure, placer, la hauteur de la plateforme',
    (t) async {
      t.view.physicalSize = const Size(900, 12000);
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
      await t.tap(find.widgetWithText(Tab, 'Escalier'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('escalier_hauteur')), findsNothing);
      await t.tap(find.byKey(const ValueKey('escalier_actif')));
      await t.pumpAndSettle();
      // Le calcul de l'escalier, avec la hauteur de la plateforme et sa place sur le plancher.
      expect(find.text('Hauteur de la plateforme'), findsOneWidget);
      expect(find.byKey(const ValueKey('escalier_mode_donnees')), findsNothing);
      expect(find.byKey(const ValueKey('escalier_cote_0')), findsOneWidget);
      expect(find.text('Centré'), findsOneWidget);
      // Plancher en feuilles : marches en bois, sans choix du composite.
      expect(find.byKey(const ValueKey('escalier_composite')), findsNothing);
      // Depuis le coin : la distance apparaît.
      await t.tap(find.text('Depuis le coin'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('escalier_distance_coin')),
        findsOneWidget,
      );
      // La commande a l'escalier.
      await t.tap(find.widgetWithText(Tab, 'Commande'));
      await t.pumpAndSettle();
      expect(find.textContaining('Escalier'), findsWidgets);
    },
  );
}
