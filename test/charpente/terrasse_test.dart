// Dessus de plancher en composite (plateforme) : cadre, planches du centre, attaches, vis,
// fascia et blocage.

import 'package:construction_app/charpente/composite.dart';
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/terrasse.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plateforme de [x] × [y] po, solives le long de x (repère pivoté = repère de la forme).
ResultatPlancher _plancher(
  double x,
  double y, {
  int? coteMaison,
  double espacement = 16,
}) => calculerPlancher(
  SpecPlancher(
    forme: Polygone.rectangle(x, y),
    angleSolivesDeg: 0,
    espacement: espacement,
    coteMaison: coteMaison,
  ),
);

ResultatTerrasse _terrasse(ResultatPlancher p, [String id = 'generique']) =>
    calculerTerrasse(p, produitComposite(id), section: section2x10);

/// Solives distinctes (une doublée compte une fois) strictement entre y0 et y1.
int _solivesEntre(ResultatPlancher p, double y0, double y1) {
  final vs = [
    for (final s in p.solives)
      if (s.v > y0 && s.v < y1) s.v,
  ]..sort();
  var n = 0;
  double? d;
  for (final v in vs) {
    if (d == null || v - d > 2) n++;
    d = v;
  }
  return n;
}

void main() {
  group('plateforme de 12 pi × 10 pi, sans maison (composite courant)', () {
    final p = _plancher(144, 120);
    final t = _terrasse(p);
    // Planche 5 1/2, fascia 3/4, débord 1/2 : le cadre va de −1 1/4 à 145 1/4.

    test(
      'un cadre sur les 4 côtés, en onglet, qui dépasse la fascia de 1/2 po',
      () {
        expect(t.cadre, hasLength(4));
        final c0 = t.cadre.firstWhere((c) => c.cote == 0);
        expect(c0.contour.first.x, closeTo(-1.25, 1e-9));
        expect(c0.contour.first.y, closeTo(-1.25, 1e-9));
        // Pointe longue : 144 + 2 × 1 1/4.
        expect(c0.longueur, closeTo(146.5, 1e-9));
        expect(c0.morceaux, 1);
        expect(c0.longeSolives, isTrue); // côté le long des solives
        expect(
          t.cadre.firstWhere((c) => c.cote == 1).longueur,
          closeTo(122.5, 1e-9),
        );
        expect(t.cadre.firstWhere((c) => c.cote == 1).longeSolives, isFalse);
      },
    );

    test(
      'le centre : planches perpendiculaires aux solives, la dernière refendue',
      () {
        // Centre : x de 4 7/16 à 139 9/16 (écart côte à côte 3/16 contre le cadre), y de 4 3/8 à
        // 115 5/8 (écart de bout 1/8 contre le cadre).
        expect(t.rangees, 24);
        expect(t.centre, hasLength(24));
        for (final pl in t.centre) {
          expect(pl.longueur, closeTo(111.25, 1e-9));
        }
        expect(t.centre.where((pl) => pl.refendue), hasLength(1));
        expect(t.centre.last.refendue, isTrue);
        expect(t.joints, 0);
        expect(t.planchesCentre.horsLimites, isEmpty);
      },
    );

    test('une attache par solive par planche ; vis en surface du cadre et des rangées de rive', () {
      final parRangee = _solivesEntre(p, 4.375, 115.625);
      expect(parRangee, greaterThan(5));
      expect(t.attaches, 24 * parRangee);
      expect(t.boitesAttaches, (24 * parRangee / 90).ceil());
      // Cadre : 2 vis par appui (blocs aux 16 po le long des solives, solives aux 16 po en
      // travers) ; première et dernière rangée : 2 vis par solive.
      final cadre = 2 * (2 * (10 + 1) + 2 * (8 + 1));
      expect(t.visSurface, cadre + 2 * 2 * parRangee);
      expect(t.bouchons, t.visSurface);
    });

    test('fascia sur les 4 rives (12 pi max) ; 3 vis aux 16 po', () {
      expect(t.fascias, hasLength(4));
      expect(
        t.fascias.firstWhere((f) => f.cote == 0).longueur,
        closeTo(145.5, 1e-9),
      );
      expect(t.fascias.firstWhere((f) => f.cote == 0).morceaux, 2);
      expect(
        t.fascias.firstWhere((f) => f.cote == 1).longueur,
        closeTo(121.5, 1e-9),
      );
      expect(t.hauteurFascia, 11.25); // rive en 2x10 : la fascia de 11 1/4
      expect(t.visFascia, 3 * (2 * (10 + 1) + 2 * (8 + 1)));
    });

    test(
      'blocage en échelle aux 16 po sous le cadre qui longe les solives',
      () {
        expect(t.blocs, 2 * (9 + 1));
        expect(t.longueurBloc, 14.5);
        expect(t.blocage.horsLimites, isEmpty);
      },
    );

    test('aucun avertissement à 16 po', () {
      expect(t.avertissements, isEmpty);
    });
  });

  test('contre la maison : ni cadre ni fascia de ce côté, 1/4 po d\'écart', () {
    final t = _terrasse(_plancher(144, 120, coteMaison: 3));
    expect(t.cadre.map((c) => c.cote), isNot(contains(3)));
    expect(t.fascias.map((f) => f.cote), isNot(contains(3)));
    // Les cadres voisins finissent à 1/4 po de la maison.
    final c0 = t.cadre.firstWhere((c) => c.cote == 0);
    expect(c0.contour.first.x, closeTo(0.25, 1e-9));
    // Le centre commence à 1/4 po de la maison.
    final xMin = t.centre
        .expand((pl) => pl.contour)
        .map((q) => q.x)
        .reduce((a, b) => a < b ? a : b);
    expect(xMin, closeTo(0.25, 1e-9));
  });

  test('Trex Enhance : solives aux 300 mm au Canada, l\'entraxe de 16 po est signalé', () {
    final t = _terrasse(_plancher(144, 120), 'trex_enhance');
    expect(t.avertissements.single, contains('Trex Enhance'));
    expect(t.avertissements.single, contains('au plus'));
    final ok = _terrasse(_plancher(144, 120, espacement: 12), 'trex_enhance');
    expect(ok.avertissements, isEmpty);
  });

  test('rangée plus longue que 20 pi : joints bout à bout, signalés', () {
    final t = _terrasse(_plancher(120, 300));
    // Centre de 300 − 2 × 4 3/8 = 291 1/4 : 2 morceaux par rangée.
    expect(t.joints, t.rangees);
    for (final pl in t.centre) {
      expect(pl.longueur, closeTo(291.25 / 2, 1e-9));
    }
    expect(t.avertissements.single, contains('joints bout à bout'));
  });

  test('Fiberon : 2 vis en surface au milieu de chaque planche, en plus des attaches', () {
    final p = _plancher(144, 120);
    final g = _terrasse(p);
    final f = _terrasse(p, 'fiberon_sanctuary');
    // Même largeur ou presque : on compare le surplus à ce que donne le nombre de planches.
    final sansCentre = f.visSurface - 2 * f.centre.length;
    expect(sansCentre, greaterThan(0));
    expect(g.visSurface, isNot(f.visSurface));
  });

  test('plateforme trop petite pour un cadre : message clair', () {
    expect(() => _terrasse(_plancher(12, 12)), throwsA(isA<SpecInvalide>()));
  });
}
