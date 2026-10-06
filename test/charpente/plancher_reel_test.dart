// Deux commandes de plancher réelles (véranda 15 × 14 pi et solarium 14 × 12 pi,
// sur pieux vissés), calculées avec les règles de l'entrepreneur :
//  - solives de bordure doublées ; rive avant doublée, rive côté maison simple ;
//  - étriers à un bout seulement, solives intérieures seulement ;
//  - une rangée d'entremises tous les 10 pi de portée au plus, pose alternée ;
//  - solives, rives et entremises coupées chacune dans leurs planches ;
//  - 2 poutres de 3 plis 2×8 traité sur pieux (le premier à 1 pi du bord) et
//    des pattes en 6×6 traité.
// Voir docs/exemples_reels_plancher.md.
import 'package:construction_app/charpente/commande.dart';
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart' show section2x8;
import 'package:construction_app/charpente/plancher.dart';
import 'package:flutter_test/flutter_test.dart';

SpecPlancher _spec(
  double longueur,
  double largeur, {
  double hauteurPatte = 0,
  int coteMaison = 2,
}) => SpecPlancher(
  forme: Polygone.rectangle(longueur, largeur),
  solivesDoublesAuxCotes: true,
  riveDouble: true,
  coteMaison: coteMaison,
  etriers: ModeEtriers.unBout,
  etriersBordures: false,
  entremisesAuto: true,
  entremisesAlternees: true,
  coupesSeparees: true,
  poutres: SpecPoutres(hauteurPatte: hauteurPatte),
);

Map<String, double> _lignes(Commande c) => {
  for (final l in c.lignes) l.article: l.quantite,
};

void main() {
  group('véranda 15 × 14 pi (solives de 14 pi)', () {
    final r = calculerPlancher(_spec(180, 168, hauteurPatte: 16));
    final c = construireCommande(plancher: r, sectionPlancher: section2x8);
    final l = _lignes(c);

    test('direction : solives sur le petit côté, rives sur les côtés de 15 pi', () {
      expect(r.porteeMax, closeTo(168 - 1.5 - 3, 1e-9));
      expect(r.cotesDeRive, [0, 2]);
    });

    test('solives : 13 positions + 2 de bordure doublées = 15 (11 intérieures)', () {
      expect(r.nombreSolives, 15);
      expect(r.solives.where((s) => s.bordure).length, 4);
      expect(r.solives.where((s) => !s.bordure).length, 11);
    });

    test('rives : avant doublée (2), maison simple (1)', () {
      expect(r.rives, hasLength(3));
      expect(r.rives.where((p) => p.cote == 2), hasLength(1));
      expect(r.rives.where((p) => p.cote == 0), hasLength(2));
      expect(r.rives.every((p) => (p.longueur - 180).abs() < 1e-9), isTrue);
    });

    test('solives plus courtes de 4 1/2 po : une rive simple + une rive doublée', () {
      expect(r.solives.every((s) => (s.longueurCoupe - 163.5).abs() < 1e-9), isTrue);
    });

    test('une rangée d\'entremises, 11 blocs dans un seul 2×8 de 16 pi', () {
      expect(r.entremises, hasLength(11));
      expect(r.entremisesPoses, hasLength(11));
    });

    test('bois : 15 solives + 1 planche d\'entremises en 14 pi, 3 rives en 16 pi', () {
      // La liste de l'entrepreneur : 16 × 14 pi (les 15 solives et la planche
      // des entremises) et 4 × 16 pi (3 rives + 1 de plus).
      expect(r.bois.parLongueur, {168.0: 16, 192.0: 3});
      expect(l["2×8 × 14'"], 16);
      expect(l["2×8 × 16'"], 3);
    });

    test('étriers : 11 (solives intérieures) et 1 boîte de clous', () {
      expect(r.etriers, 11);
      expect(l['Étrier de solive pour 2×8'], 11);
      expect(r.boitesClousEtriers, 1);
      expect(l.entries.firstWhere((e) => e.key.startsWith('Clous d')).value, 1);
    });

    test('contreplaqué : 7 feuilles', () {
      expect(r.panneaux.feuillesACommander, 7);
    });

    test('poutres : 2 × 3 plis de 15 pi = 6 × 2×8 × 16 pi traité', () {
      final p = r.poutres!;
      expect(p.longueur, 180);
      expect(p.bois.parLongueur, {192.0: 6});
      expect(l["2×8 × 16' traité"], 6);
    });

    test('pieux : 6, premier à 1 pi du bord, entraxe 6 pi 6 po', () {
      final p = r.poutres!;
      expect(p.nombrePieux, 6);
      expect(p.entraxePieux, closeTo(78, 1e-9));
    });

    test('pattes : 6 × 16 po = un 6×6 de 8 pi traité', () {
      expect(r.poutres!.pattes!.parLongueur, {96.0: 1});
      expect(l["6×6 × 8' traité"], 1);
    });

    test('aucun avertissement de poutre ou d\'épissure', () {
      expect(r.poutres!.avertissements, isEmpty);
      expect(r.avertissements.where((a) => a.contains('plusieurs morceaux')), isEmpty);
    });
  });

  group('solarium 14 × 12 pi (solives de 12 pi)', () {
    final r = calculerPlancher(_spec(144, 168, hauteurPatte: 20, coteMaison: 1));
    final c = construireCommande(plancher: r, sectionPlancher: section2x8);
    final l = _lignes(c);

    test('rives sur les côtés de 14 pi : 3 (avant doublée, maison simple)', () {
      expect(r.cotesDeRive, [1, 3]);
      expect(r.rives, hasLength(3));
    });

    test('solives : 12 positions + 2 de bordure doublées = 14, étriers : 10', () {
      expect(r.nombreSolives, 14);
      expect(r.etriers, 10);
      expect(r.solives.every((s) => (s.longueurCoupe - 139.5).abs() < 1e-9), isTrue);
    });

    test('bois : 14 × 12 pi (solives) et 4 × 14 pi (3 rives + 1 planche d\'entremises)', () {
      // La liste de l'entrepreneur : rives 4 + entremises 1 = 5 × 14 pi.
      expect(r.bois.parLongueur, {144.0: 14, 168.0: 4});
    });

    test('contreplaqué : 6 feuilles, une boîte de clous', () {
      expect(r.panneaux.feuillesACommander, 6);
      expect(r.boitesClousEtriers, 1);
    });

    test('poutres 6 × 16... de 14 pi : 6 × 2×8 × 14 pi traité, pieux à 6 pi', () {
      final p = r.poutres!;
      expect(p.longueur, 168);
      expect(p.bois.parLongueur, {168.0: 6});
      expect(p.entraxePieux, closeTo(72, 1e-9));
      expect(l["2×8 × 14' traité"], 6);
    });

    test('pattes : 6 × 20 po = un 6×6 de 10 pi traité', () {
      expect(l["6×6 × 10' traité"], 1);
    });

    test('mesure réelle de 14 pi 1 po : les poutres passent à 16 pi', () {
      final reel = calculerPlancher(_spec(144, 169, hauteurPatte: 20, coteMaison: 1));
      expect(reel.poutres!.bois.parLongueur, {192.0: 6});
    });
  });

  group('chaque règle, séparément', () {
    SpecPlancher base({
      int? coteMaison,
      bool riveDouble = true,
      bool bordures = true,
      bool etriersBordures = true,
      bool auto = false,
      int rangees = 0,
      bool alternees = false,
      bool separees = false,
      double largeur = 168,
      double longueur = 180,
    }) => SpecPlancher(
      forme: Polygone.rectangle(longueur, largeur),
      riveDouble: riveDouble,
      solivesDoublesAuxCotes: bordures,
      coteMaison: coteMaison,
      etriers: ModeEtriers.unBout,
      etriersBordures: etriersBordures,
      entremisesAuto: auto,
      rangeesEntremises: rangees,
      entremisesAlternees: alternees,
      coupesSeparees: separees,
    );

    test('sans côté de maison : les deux rives sont doublées comme avant', () {
      expect(calculerPlancher(base()).rives, hasLength(4));
      expect(calculerPlancher(base(riveDouble: false)).rives, hasLength(2));
    });

    test('côté de maison : rive simple, même sans rives doublées ailleurs', () {
      expect(calculerPlancher(base(coteMaison: 2)).rives, hasLength(3));
      expect(
        calculerPlancher(base(coteMaison: 2, riveDouble: false)).rives,
        hasLength(2),
      );
    });

    test('côté de maison parallèle aux solives : avertissement', () {
      final r = calculerPlancher(base(coteMaison: 1));
      expect(r.avertissements.any((a) => a.contains('parallèle aux solives')), isTrue);
    });

    test('côté de maison inexistant : refusé', () {
      expect(() => calculerPlancher(base(coteMaison: 9)), throwsA(isA<SpecInvalide>()));
    });

    test('étriers : les solives de bordure sont exclues sur demande', () {
      expect(calculerPlancher(base(etriersBordures: true)).etriers, 15);
      expect(calculerPlancher(base(etriersBordures: false)).etriers, 11);
      expect(
        calculerPlancher(base(etriersBordures: false, bordures: false)).etriers,
        11,
      );
    });

    test('entremises automatiques : une rangée par tranche de portée', () {
      // Portée des solives = la largeur donnée moins 4 1/2 po de rives ; la
      // forme est assez longue pour que les solives courent sur la largeur.
      int rangees(double portee, {double max = 120}) {
        final r = calculerPlancher(
          SpecPlancher(
            forme: Polygone.rectangle(portee + 4.5, 200),
            angleSolivesDeg: 0,
            riveDouble: true,
            coteMaison: 1,
            entremisesAuto: true,
            espacementMaxEntremises: max,
          ),
        );
        return {for (final p in r.entremisesPoses) (p.u * 100).round()}.length;
      }

      expect(rangees(96), 0); // 8 pi : pas d'entremises
      expect(rangees(120), 0); // 10 pi : au plus 10 pi, aucune
      expect(rangees(121), 1);
      expect(rangees(168), 1); // 14 pi : 1 rangée, à 7 pi
      expect(rangees(240), 1); // 20 pi : 1 rangée, à 10 pi
      expect(rangees(241), 2);
      expect(rangees(252), 2); // 21 pi
      // Portée sans entremises de 8 pi : 14 pi donne encore 1 rangée, 17 pi en donne 2.
      expect(rangees(168, max: 96), 1);
      expect(rangees(204, max: 96), 2);
    });

    test('les rangées automatiques sont réparties également sur la portée', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(252 + 4.5, 200),
          angleSolivesDeg: 0,
          riveDouble: true,
          coteMaison: 1,
          entremisesAuto: true,
        ),
      );
      final us = ({for (final p in r.entremisesPoses) (p.u * 100).round() / 100}).toList()..sort();
      expect(us, hasLength(2));
      expect(us[1] - us[0], closeTo(252 / 3, 1e-6));
    });

    test('le nombre de rangées choisi à la main est ignoré en mode automatique', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(168 + 4.5, 200),
          angleSolivesDeg: 0,
          entremisesAuto: true,
          rangeesEntremises: 3,
        ),
      );
      expect({for (final p in r.entremisesPoses) (p.u * 100).round()}, hasLength(1));
    });

    test('pose alternée : les blocs voisins sont décalés d\'une épaisseur de solive', () {
      final droite = calculerPlancher(base(rangees: 1));
      final alternee = calculerPlancher(base(rangees: 1, alternees: true));
      expect(alternee.entremises.length, droite.entremises.length);
      final us = [for (final p in alternee.entremisesPoses) p.u]..sort();
      final u0 = droite.entremisesPoses.first.u;
      expect(droite.entremisesPoses.every((p) => (p.u - u0).abs() < 1e-9), isTrue);
      expect(
        alternee.entremisesPoses
            .map((p) => ((p.u - u0) * 1000).round() / 1000)
            .toSet(),
        {-0.75, 0.75},
      );
      expect(us.first, lessThan(us.last));
      // Deux blocs voisins sont décalés l'un de l'autre.
      final pa = alternee.entremisesPoses;
      for (var i = 1; i < pa.length; i++) {
        expect((pa[i].u - pa[i - 1].u).abs(), closeTo(1.5, 1e-9));
      }
    });

    test('coupes séparées : aucune planche ne mêle solives et entremises', () {
      final ensemble = calculerPlancher(base(rangees: 2));
      final separees = calculerPlancher(base(rangees: 2, separees: true));
      for (final p in separees.bois.planches) {
        final kinds = p.pieces.map((x) => x.etiquette).toSet();
        final solives = kinds.where((k) => k.startsWith('solive')).isNotEmpty;
        final blocs = kinds.contains('entremise');
        expect(solives && blocs, isFalse, reason: 'planche ${p.stock}: $kinds');
      }
      // Même nombre de pièces coupées : on compte les pièces, pas les planches.
      int pieces(ResultatPlancher r) =>
          r.bois.planches.fold(0, (a, p) => a + p.pieces.length);
      expect(pieces(separees), pieces(ensemble));
      // L'optimisation d'ensemble n'achète jamais plus de bois.
      expect(separees.bois.longueurTotale, greaterThanOrEqualTo(ensemble.bois.longueurTotale));
    });

    test('clous d\'étriers : boîtes selon les clous nécessaires et la marge', () {
      // Une forme de n solives (2 de bordure + n − 2 à 16 po c/c) : étriers = n.
      ResultatPlancher avec(int n, {double marge = 5, int parEtrier = 10}) {
        final largeur = 16.0 * (n - 2) + 8;
        return calculerPlancher(
          SpecPlancher(
            forme: Polygone.rectangle(largeur, largeur / 2),
            etriers: ModeEtriers.unBout,
            margeClousPourcent: marge,
            clousParEtrier: parEtrier,
          ),
        );
      }

      final douze = avec(12);
      expect(douze.etriers, 12);
      expect(douze.boitesClousEtriers, 2); // 126 clous avec la marge de 5 %
      expect(avec(12, marge: 0).boitesClousEtriers, 1); // 120 clous : une boîte exacte
      final dix = avec(10);
      expect(dix.boitesClousEtriers, 1); // 105 clous
      expect(avec(10, parEtrier: 12).boitesClousEtriers, 2); // 126 clous
      expect(
        calculerPlancher(SpecPlancher(forme: Polygone.rectangle(100, 100))).boitesClousEtriers,
        0,
      );
    });
  });

  group('rives et poutres faites de plusieurs morceaux', () {
    test('morceauxEnPlis : plis pairs égaux, plis impairs décalés d\'un demi-morceau', () {
      expect(morceauxEnPlis(100, 240, 0), [100]);
      expect(morceauxEnPlis(100, 240, 1), [100]);
      expect(morceauxEnPlis(360, 240, 0), [180, 180]);
      expect(morceauxEnPlis(360, 240, 1), [90, 180, 90]);
      expect(morceauxEnPlis(480, 240, 0), [240, 240]);
      expect(morceauxEnPlis(480, 240, 1), [120, 240, 120]);
      expect(morceauxEnPlis(700, 240, 1), hasLength(4));
      for (final longueur in [250.0, 361.0, 481.0, 700.0]) {
        for (final pli in [0, 1]) {
          final m = morceauxEnPlis(longueur, 240, pli);
          expect(m.fold(0.0, (a, b) => a + b), closeTo(longueur, 1e-9));
          expect(m.every((x) => x <= 240 + 1e-9 && x > 1), isTrue);
        }
        // Les joints d'un pli ne tombent jamais sur ceux de l'autre.
        List<double> joints(List<double> m) {
          var s = 0.0;
          return [for (final x in m.take(m.length - 1)) s += x];
        }

        final a = joints(morceauxEnPlis(longueur, 240, 0));
        final b = joints(morceauxEnPlis(longueur, 240, 1));
        for (final x in a) {
          expect(b.any((y) => (x - y).abs() < 1), isFalse, reason: '$longueur');
        }
      }
    });

    test('rive de la maison de 30 pi : doublée, joints alternés', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(360, 144),
          riveDouble: false,
          coteMaison: 2,
        ),
      );
      final maison = r.rives.where((p) => p.cote == 2).toList();
      final avant = r.rives.where((p) => p.cote == 0).toList();
      expect(avant, hasLength(2)); // rive simple en 2 morceaux (comme avant)
      expect(maison, hasLength(5)); // 2 plis : 2 + 3 morceaux
      expect(maison.where((p) => !p.doublon).map((p) => p.longueur), [180, 180]);
      expect(maison.where((p) => p.doublon).map((p) => p.longueur), [90, 180, 90]);
      expect(r.avertissements.any((a) => a.contains('plusieurs morceaux')), isTrue);
    });

    test('poutres de 24 pi : plis alternés et avertissement', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(144, 288),
          poutres: const SpecPoutres(),
        ),
      );
      final p = r.poutres!;
      expect(p.longueur, 288);
      expect(p.avertissements.any((a) => a.contains('plusieurs morceaux')), isTrue);
      // 2 poutres × (2 + 3 + 2) morceaux.
      expect(p.bois.planches.fold(0, (a, b) => a + b.pieces.length), 2 * 7);
    });
  });

  group('poutres : validations', () {
    test('valeurs refusées', () {
      void refuse(SpecPoutres p) => expect(
        () => calculerPlancher(SpecPlancher(forme: Polygone.rectangle(100, 100), poutres: p)),
        throwsA(isA<SpecInvalide>()),
      );
      refuse(const SpecPoutres(nombre: 0));
      refuse(const SpecPoutres(plis: 0));
      refuse(const SpecPoutres(plis: 6));
      refuse(const SpecPoutres(pieuxParPoutre: 1));
      refuse(const SpecPoutres(retraitPieux: -1));
      refuse(const SpecPoutres(hauteurPatte: -1));
    });

    test('retrait trop grand : avertissement, pas de plantage', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(100, 100),
          poutres: const SpecPoutres(retraitPieux: 60),
        ),
      );
      expect(r.poutres!.avertissements.any((a) => a.contains('trop grand')), isTrue);
    });

    test('forme irrégulière : avertissement', () {
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone(const [Pt(0, 0), Pt(200, 0), Pt(200, 100), Pt(100, 100), Pt(100, 200), Pt(0, 200)]),
          poutres: const SpecPoutres(),
        ),
      );
      expect(r.poutres!.avertissements.any((a) => a.contains('irrégulière')), isTrue);
    });

    test('sans patte : aucun 6×6', () {
      final r = calculerPlancher(
        SpecPlancher(forme: Polygone.rectangle(180, 168), poutres: const SpecPoutres()),
      );
      expect(r.poutres!.pattes, isNull);
      final c = construireCommande(plancher: r, sectionPlancher: section2x8);
      expect(c.lignes.any((x) => x.article.contains('6×6')), isFalse);
    });
  });
}
