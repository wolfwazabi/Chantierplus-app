import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/panneaux.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:flutter_test/flutter_test.dart';

Polygone get _rect => Polygone.rectangle(156, 126); // 13' x 10'6"

Polygone get _enL => Polygone(const [
  Pt(0, 0),
  Pt(240, 0),
  Pt(240, 120),
  Pt(120, 120),
  Pt(120, 240),
  Pt(0, 240),
]);

ResultatPlancher _calc(
  Polygone p, {
  double s = 16,
  double? angle,
  FormatPanneau panneau = panneau4x8,
  ModeEtriers etriers = ModeEtriers.aucun,
  int entremises = 0,
  bool doubles = false,
  double marge = 0,
  List<double> planches = longueursPlanchesParDefaut,
  double decalage = 24,
  double epRive = 1.5,
  bool riveDouble = false,
}) => calculerPlancher(
  SpecPlancher(
    forme: p,
    espacement: s,
    angleSolivesDeg: angle,
    panneau: panneau,
    etriers: etriers,
    rangeesEntremises: entremises,
    solivesDoublesAuxCotes: doubles,
    margePanneauxPourcent: marge,
    longueursPlanches: planches,
    decalageMin: decalage,
    epaisseurRive: epRive,
    riveDouble: riveDouble,
  ),
);

/// Le point (u, v) du repère pivoté est-il dans la forme ?
bool _dedans(Polygone r, double u, double v) {
  for (final c in r.cordes(horizontale: true, c: v)) {
    if (u >= c.debut - 1e-9 && u <= c.fin + 1e-9) {
      return true;
    }
  }
  return false;
}

/// Vérifications communes à tous les plans de feuilles.
void _verifierFeuilles(
  ResultatPlancher r, {
  double decalage = 24,
  bool verifierDecalage = true,
}) {
  final plan = r.panneaux;
  final f = plan.format;
  expect(plan.poses, isNotEmpty);

  // 1. Chaque pièce tient dans une feuille.
  for (final p in plan.poses) {
    expect(
      p.longueur,
      lessThanOrEqualTo(f.longueur + 1e-6),
      reason: 'pièce plus longue que la feuille',
    );
    expect(p.largeur, lessThanOrEqualTo(f.largeur + 1e-6));
    expect(p.feuille, greaterThanOrEqualTo(0));
  }

  // 2. Couverture : tout point de la forme est sous une pièce.
  final b = r.formePivotee.boite;
  var verifies = 0;
  for (var u = b.xMin + 1.5; u < b.xMax; u += 6) {
    for (var v = b.yMin + 1.5; v < b.yMax; v += 6) {
      if (!_dedans(r.formePivotee, u, v)) {
        continue;
      }
      verifies++;
      final couvert = plan.poses.any(
        (p) =>
            u >= p.u0 - 1e-6 &&
            u <= p.u1 + 1e-6 &&
            v >= p.v0 - 1e-6 &&
            v <= p.v1 + 1e-6,
      );
      expect(couvert, isTrue, reason: 'point ($u, $v) non couvert');
    }
  }
  expect(verifies, greaterThan(5));

  // 3. Chaque joint intérieur tombe sur l'axe d'une solive.
  final par = <int, List<PosePanneau>>{};
  for (final p in plan.poses) {
    par.putIfAbsent(p.rangee, () => []).add(p);
  }
  final joints = <int, List<double>>{};
  for (final e in par.entries) {
    final l = e.value..sort((a, c) => a.v0.compareTo(c.v0));
    for (var i = 0; i + 1 < l.length; i++) {
      if ((l[i].v1 - l[i + 1].v0).abs() > 1e-6) {
        continue; // intervalles distincts (forme concave)
      }
      final v = l[i].v1;
      joints.putIfAbsent(e.key, () => []).add(v);
      if (plan.jointsHorsSolives) {
        continue; // partie très étroite : le plan l'a signalé (avertissement)
      }
      final porte = r.solives.any(
        (s) =>
            !s.doublon &&
            (s.v - v).abs() < 1e-5 &&
            s.u1 > l[i].u0 + 1 &&
            s.u0 < l[i].u1 - 1,
      );
      expect(
        porte,
        isTrue,
        reason: 'joint à v=$v (rangée ${e.key}) hors solive',
      );
    }
  }

  // 4. Joints décalés d'une rangée à l'autre.
  if (verifierDecalage) {
    final rangs = joints.keys.toList()..sort();
    for (var i = 0; i + 1 < rangs.length; i++) {
      if (rangs[i + 1] != rangs[i] + 1) {
        continue;
      }
      for (final a in joints[rangs[i]]!) {
        for (final c in joints[rangs[i + 1]]!) {
          expect(
            (a - c).abs(),
            greaterThanOrEqualTo(decalage - 1e-6),
            reason:
                'joints trop proches : $a et $c (rangées ${rangs[i]}/${rangs[i + 1]})',
          );
        }
      }
    }
  }

  // 5. Nombre de feuilles : au moins la surface, au plus une feuille par pièce.
  final aireFeuille = f.longueur * f.largeur;
  expect(
    plan.feuillesUtilisees,
    greaterThanOrEqualTo((r.aire / aireFeuille - 1e-9).ceil()),
  );
  expect(plan.feuillesUtilisees, lessThanOrEqualTo(plan.poses.length));
}

void main() {
  group('plancher rectangulaire : 10\'6" × 13\' à 16 po c/c', () {
    final r = _calc(_rect);

    test('les solives courent dans le sens le plus court (portée 10\'6")', () {
      expect(r.angleSolivesDeg, 90);
      expect(r.porteeMax, closeTo(123, 1e-6)); // 126 − 2 × 1,5 de rive
    });

    test('11 solives de 123 po (10\' 3")', () {
      expect(r.nombreSolives, 11); // 156/16 → 10 espaces + 1
      for (final s in r.solives) {
        expect(s.longueurCoupe, closeTo(123, 1e-6));
        expect(s.biseauDebutDeg, closeTo(0, 1e-6));
        expect(s.biseauFinDeg, closeTo(0, 1e-6));
      }
      expect(r.solives.where((s) => s.bordure), hasLength(2));
      // Entraxes de 16 po entre les solives courantes.
      final courantes = r.solives.where((s) => !s.bordure).toList();
      expect(courantes, hasLength(9));
      for (var i = 0; i + 1 < courantes.length; i++) {
        expect(courantes[i + 1].v - courantes[i].v, closeTo(16, 1e-6));
      }
    });

    test('2 solives de rive de 13 pi (côtés perpendiculaires aux solives)', () {
      expect(r.rives, hasLength(2));
      expect(r.rives.map((p) => p.longueur), [156, 156]);
      expect(r.rives.every((p) => (p.angleDebutDeg - 90).abs() < 1e-9), isTrue);
    });

    test('bois à commander : 11 planches de 12 pi et 2 de 14 pi', () {
      expect(r.bois.parLongueur, {144: 11, 168: 2});
      expect(r.bois.horsLimites, isEmpty);
    });

    test('feuilles 4 × 8 : 5 feuilles (le minimum possible : 4,27), joints sur solives et décalés', () {
      expect(r.panneaux.feuillesUtilisees, 5);
      expect(r.panneaux.rangees, 3); // 126 po = 48 + 48 + 30
      expect(r.panneaux.feuillesACommander, 5);
      expect(
        r.panneaux.pertePourcent,
        closeTo((5 * 4608 - 19656) / (5 * 4608) * 100, 1e-6),
      );
      _verifierFeuilles(r);
    });

    test('aucun étrier, aucune entremise par défaut', () {
      expect(r.etriers, 0);
      expect(r.entremises, isEmpty);
    });

    test('avertissements : portée des solives à valider', () {
      expect(
        r.avertissements.any((a) => a.contains('portée admissible')),
        isTrue,
      );
    });

    test(
      'même résultat si la forme est donnée dans l\'autre sens (13\' × 10\'6")',
      () {
        final autre = _calc(Polygone.rectangle(126, 156));
        expect(autre.nombreSolives, 11);
        expect(autre.bois.parLongueur, {144: 11, 168: 2});
        expect(autre.panneaux.feuillesUtilisees, 5);
        expect(autre.angleSolivesDeg, 0);
      },
    );
  });

  group('entraxes', () {
    final cas = <double, int>{12: 14, 16: 11, 19.2: 10, 24: 8};
    cas.forEach((s, attendu) {
      test('${s.toStringAsFixed(1)} po c/c sur 13\' : $attendu solives', () {
        final r = _calc(_rect, s: s);
        expect(r.nombreSolives, attendu);
        expect(
          r.solives.every((x) => (x.longueurCoupe - 123).abs() < 1e-6),
          isTrue,
        );
        _verifierFeuilles(r);
      });
    });

    test('carré de 10\' à 16 po c/c : 9 solives de 117 po', () {
      final r = _calc(Polygone.rectangle(120, 120));
      expect(r.nombreSolives, 9);
      expect(
        r.solives.every((x) => (x.longueurCoupe - 117).abs() < 1e-6),
        isTrue,
      );
    });

    test('un entraxe plus serré demande plus de solives', () {
      final n = [
        12.0,
        16.0,
        19.2,
        24.0,
      ].map((s) => _calc(_rect, s: s).nombreSolives).toList();
      expect(n[0], greaterThan(n[1]));
      expect(n[1], greaterThan(n[2]));
      expect(n[2], greaterThan(n[3]));
    });

    test('chaque espace entre solives respecte l\'entraxe maximal', () {
      for (final s in [12.0, 16.0, 19.2, 24.0]) {
        final r = _calc(_rect, s: s);
        final vs = r.solives.map((x) => x.v).toList()..sort();
        for (var i = 0; i + 1 < vs.length; i++) {
          expect(
            vs[i + 1] - vs[i],
            lessThanOrEqualTo(s + 1e-6),
            reason: 'entraxe $s',
          );
        }
      }
    });
  });

  group('étriers, entremises, doublage, rives', () {
    test('étriers : un bout ou deux bouts', () {
      expect(_calc(_rect, etriers: ModeEtriers.unBout).etriers, 11);
      expect(_calc(_rect, etriers: ModeEtriers.deuxBouts).etriers, 22);
    });

    test('entremises : une rangée entre chaque paire de solives voisines', () {
      final r = _calc(_rect, entremises: 1);
      expect(r.entremises, hasLength(10));
      final l = r.entremises.map((e) => e.longueur).toList()..sort();
      expect(l.first, closeTo(9.75, 1e-9)); // dernier espace : 11,25 − 1,5
      expect(l.last, closeTo(14.5, 1e-9));
      expect(l.where((x) => (x - 14.5).abs() < 1e-9), hasLength(8));
      expect(_calc(_rect, entremises: 2).entremises, hasLength(20));
    });

    test(
      'entremises : positions (à mi-portée, ou au tiers avec 2 rangées)',
      () {
        final r1 = _calc(_rect, entremises: 1);
        expect(r1.entremisesPoses, hasLength(r1.entremises.length));
        final longueurs = r1.entremisesPoses.map((p) => p.longueur).toList()
          ..sort();
        final pieces = r1.entremises.map((e) => e.longueur).toList()..sort();
        for (var i = 0; i < pieces.length; i++) {
          expect(longueurs[i], closeTo(pieces[i], 1e-9));
        }
        final s0 = r1.solives.first;
        final milieu = (s0.u0 + s0.u1) / 2;
        for (final p in r1.entremisesPoses) {
          expect(p.u, closeTo(milieu, 1e-6));
        }
        final r2 = _calc(_rect, entremises: 2);
        final us =
            r2.entremisesPoses
                .map((p) => (p.u * 1e6).round() / 1e6)
                .toSet()
                .toList()
              ..sort();
        expect(us, hasLength(2));
        final portee = s0.u1 - s0.u0;
        expect(us[1] - us[0], closeTo(portee / 3, 1e-6));
        expect(us[0], closeTo(s0.u0 + portee / 3, 1e-6));
      },
    );

    test('solives de bordure doublées : 2 solives de plus', () {
      final r = _calc(_rect, doubles: true);
      expect(r.nombreSolives, 13);
      expect(r.solives.where((s) => s.doublon), hasLength(2));
    });

    test('solive de rive doublée : 4 pièces de 13 pi, solives plus courtes de 1 1/2 po à chaque bout', () {
      final r = _calc(_rect, riveDouble: true);
      expect(r.rives, hasLength(4));
      expect(r.rives.where((p) => p.doublon), hasLength(2));
      expect(r.rives.every((p) => (p.longueur - 156).abs() < 1e-9), isTrue);
      expect(
        r.solives.every((s) => (s.longueurCoupe - 120).abs() < 1e-6),
        isTrue,
      ); // 126 − 2 × 3
      expect(r.bois.parLongueur, {120: 11, 168: 4});
      expect(r.etriers, 0);
    });

    test(
      'rive doublée sur un côté trop long : un seul avertissement d\'épissure',
      () {
        final r = _calc(Polygone.rectangle(360, 144), riveDouble: true);
        expect(r.rives, hasLength(8));
        expect(
          r.avertissements.where((a) => a.contains('plusieurs morceaux')),
          hasLength(1),
        );
      },
    );

    test('solive de rive de 3 po : solives plus courtes', () {
      final r = _calc(_rect, epRive: 3);
      expect(
        r.solives.every((s) => (s.longueurCoupe - 120).abs() < 1e-6),
        isTrue,
      );
    });

    test(
      'plancher plus long que la plus longue planche : rive en deux morceaux',
      () {
        final r = _calc(Polygone.rectangle(360, 144));
        expect(r.rives.length, 4);
        expect(r.rives.every((p) => (p.longueur - 180).abs() < 1e-9), isTrue);
        expect(
          r.avertissements.any((a) => a.contains('plusieurs morceaux')),
          isTrue,
        );
      },
    );

    test('solive plus longue que la plus longue planche : signalée', () {
      final r = _calc(Polygone.rectangle(360, 360));
      expect(r.bois.horsLimites, isNotEmpty);
      expect(
        r.avertissements.any(
          (a) => a.contains('dépasse la plus longue planche'),
        ),
        isTrue,
      );
    });

    test('longueurs de planches restreintes : 8, 10 et 12 pi', () {
      final r = _calc(_rect, planches: const [96, 120, 144]);
      expect(r.bois.parLongueur.keys.every((k) => k <= 144), isTrue);
      // Le côté de 13' dépasse 12' : chaque rive est faite de 2 morceaux.
      expect(r.rives.length, 4);
      expect(r.rives.every((p) => (p.longueur - 78).abs() < 1e-9), isTrue);
      expect(
        r.avertissements.any((a) => a.contains('plusieurs morceaux')),
        isTrue,
      );
    });
  });

  group('feuilles de sous-plancher', () {
    test('4 × 9 pi à 12 po c/c sur 18\' × 8\' : 4 feuilles, aucune perte (joints à 108 po sur une solive)', () {
      final r = _calc(Polygone.rectangle(216, 96), s: 12, panneau: panneau4x9);
      expect(r.panneaux.feuillesUtilisees, 4);
      expect(r.panneaux.pertePourcent, closeTo(0, 1e-6));
      _verifierFeuilles(r);
    });

    test('4 × 9 pi à 16 po c/c : avertissement (108 po ne tombe pas sur une solive)', () {
      final r = _calc(_rect, panneau: panneau4x9);
      expect(
        r.avertissements.any(
          (a) => a.contains('ne se termine pas sur une solive'),
        ),
        isTrue,
      );
      _verifierFeuilles(r);
    });

    test('4 × 8 pi à 16 po c/c : aucun avertissement de ce type', () {
      expect(
        _calc(_rect).avertissements.any((a) => a.contains('ne se termine pas')),
        isFalse,
      );
    });

    test('marge d\'achat de 10 % : arrondie à la feuille supérieure', () {
      final r = _calc(_rect, marge: 10);
      expect(r.panneaux.feuillesUtilisees, 5);
      expect(r.panneaux.feuillesACommander, 6);
    });

    test(
      'décalage minimal plus grand : joints plus éloignés (ou signalés)',
      () {
        final r = _calc(Polygone.rectangle(192, 192), decalage: 48);
        _verifierFeuilles(r, decalage: 48);
      },
    );

    test('sans décalage exigé : jamais plus de feuilles qu\'avec', () {
      final avec = _calc(Polygone.rectangle(228, 156));
      final sans = _calc(Polygone.rectangle(228, 156), decalage: 0);
      expect(
        sans.panneaux.feuillesUtilisees,
        lessThanOrEqualTo(avec.panneaux.feuillesUtilisees),
      );
    });

    test('feuilles de 4 × 10 et 4 × 12 pi', () {
      for (final f in [panneau4x10, panneau4x12]) {
        final r = _calc(Polygone.rectangle(240, 144), panneau: f);
        _verifierFeuilles(r);
      }
    });

    test('chaque pièce est coupée dans une feuille : somme des aires ≥ aire de la forme', () {
      final r = _calc(_rect);
      final aire = r.panneaux.poses.fold<double>(
        0,
        (s, p) => s + p.longueur * p.largeur,
      );
      expect(aire, greaterThanOrEqualTo(r.aire - 1e-6));
      expect(aire, closeTo(r.aire, 1e-6)); // rectangle : aucune surépaisseur
    });
  });

  group('forme en L (concave)', () {
    final r = _calc(_enL, angle: 0);

    test('17 solives : 9 de 237 po et 8 de 117 po', () {
      expect(r.nombreSolives, 17);
      expect(
        r.solives.where((s) => (s.longueurCoupe - 237).abs() < 1e-6),
        hasLength(9),
      );
      expect(
        r.solives.where((s) => (s.longueurCoupe - 117).abs() < 1e-6),
        hasLength(8),
      );
      expect(
        r.solives.where((s) => s.bordure),
        hasLength(3),
      ); // dont celle de l'encoche
    });

    test(
      'solives de rive : les 3 côtés perpendiculaires (120, 120 et 240)',
      () {
        expect(r.rives.map((p) => p.longueur).toList()..sort(), [
          120,
          120,
          240,
        ]);
      },
    );

    test('angle rentrant à 270° visible dans la forme', () {
      expect(r.spec.forme.angleInterieurDeg(3), closeTo(270, 1e-9));
    });

    test('feuilles : couverture, joints sur solives, joints décalés', () {
      _verifierFeuilles(r);
    });

    test('portée choisie automatiquement : 240 po', () {
      final auto = _calc(_enL);
      expect(auto.nombreSolives, greaterThan(0));
      _verifierFeuilles(auto);
    });
  });

  group('forme en U : deux ailes séparées par une encoche', () {
    final u = Polygone(const [
      Pt(0, 0),
      Pt(300, 0),
      Pt(300, 200),
      Pt(200, 200),
      Pt(200, 100),
      Pt(100, 100),
      Pt(100, 200),
      Pt(0, 200),
    ]);
    test('les solives de chaque aile sont séparées, les feuilles couvrent toute la forme', () {
      final r = _calc(u, angle: 0);
      // Au-dessus de l'encoche (y > 100), deux solives par entraxe (une par aile).
      final haut = r.solives.where((s) => s.v > 105 && s.v < 195).toList();
      final parV = <double>{for (final s in haut) (s.v * 1000).roundToDouble()};
      expect(haut.length, parV.length * 2);
      _verifierFeuilles(r);
    });
  });

  group('forme à angle quelconque', () {
    test('triangle rectangle 12\' × 8\' : solive coupée en biseau (valeurs calculées à la main)', () {
      final tri = Polygone(const [Pt(0, 0), Pt(144, 0), Pt(0, 96)]);
      final r = _calc(tri, angle: 0);
      final s = r.solives.firstWhere((x) => (x.v - 16).abs() < 1e-6);
      // Corde de 120 po à y = 16 ; rive de 1,5 po (bout droit) et de 1,5/0,5547 = 2,704 po (biseau).
      // Longueur à la pointe longue : 120 − 1,5 − 2,704 + 0,75 × tan(56,31°) = 116,92 po.
      expect(s.longueurCoupe, closeTo(116.9208, 1e-3));
      final biseaux = [s.biseauDebutDeg, s.biseauFinDeg]..sort();
      expect(biseaux[0], closeTo(0, 1e-6));
      expect(biseaux[1], closeTo(56.3099, 1e-3));
      // Rive en biais : hypoténuse de 173,07 po, coins de 33,69° (atan 96/144) et 56,31°.
      final hypo = r.rives.firstWhere(
        (p) => (p.longueur - 173.0665).abs() < 1e-3,
      );
      expect(hypo.angleDebutDeg, closeTo(33.6901, 1e-3));
      expect(hypo.angleFinDeg, closeTo(56.3099, 1e-3));
      _verifierFeuilles(r);
    });

    test(
      'pente des coupes : les coins du bout touchent la face de la rive',
      () {
        final tri = Polygone(const [Pt(0, 0), Pt(144, 0), Pt(0, 96)]);
        final r = _calc(tri, angle: 0);
        final s = r.solives.firstWhere((x) => (x.v - 16).abs() < 1e-6);
        final pentes = [s.penteDebut, s.penteFin]..sort();
        expect(pentes[0], closeTo(-1.5, 1e-9)); // hypoténuse : dx/dy = -144/96
        expect(pentes[1], closeTo(0, 1e-9));
        // Les deux coins du bout sur l'hypoténuse sont à 1 1/2 po (rive) de sa droite.
        final u = s.penteDebut != 0 ? s.u0 : s.u1;
        final p = s.penteDebut != 0 ? s.penteDebut : s.penteFin;
        for (final dy in [-0.75, 0.75]) {
          final x = u + dy * p, y = s.v + dy;
          final distance =
              (96 * x + 144 * y - 13824) / math.sqrt(96 * 96 + 144 * 144);
          expect(distance, closeTo(-1.5, 1e-6));
        }
      },
    );

    test(
      'le sens des solives s\'adapte : plus courte portée pour le triangle',
      () {
        final tri = Polygone(const [Pt(0, 0), Pt(144, 0), Pt(0, 96)]);
        final r = _calc(tri);
        // Perpendiculaires à l'hypoténuse : la plus longue corde est la hauteur
        // 144 × 96 / 173,07 = 79,87 po, plus courte que le côté de 96 po.
        expect(r.angleSolivesDeg, closeTo(56.3099, 1e-3));
        expect(r.porteeMax, lessThan(80));
        // Imposé à 90° (le long du côté de 96 po) : portée plus longue.
        expect(_calc(tri, angle: 90).porteeMax, greaterThan(90));
      },
    );

    test(
      'invariance par rotation : une forme tournée de 37° donne le même bois',
      () {
        final base = _calc(_enL, angle: 0);
        final a = 37 * math.pi / 180;
        final tournee = Polygone([for (final p in _enL.sommets) p.pivote(a)]);
        final r = _calc(tournee, angle: 37);
        expect(r.nombreSolives, base.nombreSolives);
        final l1 = base.solives.map((s) => s.longueurCoupe).toList()..sort();
        final l2 = r.solives.map((s) => s.longueurCoupe).toList()..sort();
        for (var i = 0; i < l1.length; i++) {
          expect(l2[i], closeTo(l1[i], 1e-6));
        }
        expect(r.bois.parLongueur, base.bois.parLongueur);
        expect(r.panneaux.feuillesUtilisees, base.panneaux.feuillesUtilisees);
        _verifierFeuilles(r);
      },
    );

    test('rectangle tourné de 23° : direction retrouvée automatiquement', () {
      final a = 23 * math.pi / 180;
      final p = Polygone([for (final s in _rect.sommets) s.pivote(a)]);
      final r = _calc(p);
      expect(r.nombreSolives, 11);
      expect(r.porteeMax, closeTo(123, 1e-6));
      expect(r.bois.parLongueur, {144: 11, 168: 2});
      expect(r.panneaux.feuillesUtilisees, 5);
    });

    for (final (nom, cotes, angles) in [
      ('triangle avec un angle de 35°', [144.0, 96.0], [35.0]),
      (
        'quadrilatère avec angles de 90° et 100°',
        [150.0, 100.0, 140.0],
        [90.0, 100.0],
      ),
      (
        'pentagone régulier',
        [100.0, 100.0, 100.0, 100.0],
        [108.0, 108.0, 108.0],
      ),
      (
        'forme à 5 côtés (90°, 110°, 120°)',
        [180.0, 120.0, 90.0, 140.0],
        [90.0, 110.0, 120.0],
      ),
      (
        'hexagone irrégulier',
        [120.0, 80.0, 100.0, 90.0, 70.0],
        [100.0, 130.0, 95.0, 140.0],
      ),
    ]) {
      test('$nom : couverture, joints sur solives, solives dans la forme', () {
        final p = Polygone.deCotesEtAngles(cotes, angles);
        final r = _calc(p);
        expect(r.nombreSolives, greaterThan(2));
        // Chaque solive reste dans la forme (extrémités et milieu).
        for (final s in r.solives) {
          expect(_dedans(r.formePivotee, (s.u0 + s.u1) / 2, s.v), isTrue);
          expect(_dedans(r.formePivotee, s.u0 + 0.01, s.v), isTrue);
          expect(_dedans(r.formePivotee, s.u1 - 0.01, s.v), isTrue);
          expect(s.longueurCoupe, greaterThan(0.5));
          expect(s.biseauDebutDeg, inInclusiveRange(0, 90));
        }
        // La somme des cordes × entraxe approche l'aire (contrôle de cohérence).
        final courantes = r.solives.where((s) => !s.bordure && !s.doublon);
        final somme =
            courantes.fold<double>(0, (a, s) => a + (s.u1 - s.u0 + 3)) * 16;
        expect(somme, closeTo(p.aire, p.aire * 0.15));
        _verifierFeuilles(r);
      });
    }

    test('angle des solives imposé : toutes les solives suivent cette direction', () {
      final p = Polygone.deCotesEtAngles([180, 120, 90, 140], [90, 110, 120]);
      final r = _calc(p, angle: 30);
      expect(r.angleSolivesDeg, 30);
      expect(r.nombreSolives, greaterThan(2));
      // Retour dans le repère de la forme : les solives sont à 30° de l'axe X.
      for (final s in r.solives) {
        final a = r.versForme(Pt(s.u0, s.v));
        final b = r.versForme(Pt(s.u1, s.v));
        final ang = math.atan2(b.y - a.y, b.x - a.x) * 180 / math.pi;
        expect(ang, closeTo(30, 1e-6));
      }
    });
  });

  group('validation', () {
    SpecPlancher spec({
      double s = 16,
      double t = 1.5,
      double tr = 1.5,
      int entremises = 0,
      List<double> l = longueursPlanchesParDefaut,
      double decalage = 24,
      double marge = 0,
      double? angle,
    }) => SpecPlancher(
      forme: _rect,
      espacement: s,
      epaisseurSolive: t,
      epaisseurRive: tr,
      rangeesEntremises: entremises,
      longueursPlanches: l,
      decalageMin: decalage,
      margePanneauxPourcent: marge,
      angleSolivesDeg: angle,
    );

    test('valeurs refusées', () {
      for (final s in [
        spec(s: 0),
        spec(s: 5),
        spec(s: 49),
        spec(s: double.nan),
        spec(t: 0),
        spec(t: -1),
        spec(tr: 0),
        spec(entremises: -1),
        spec(entremises: 4),
        spec(l: const []),
        spec(l: const [96, 0]),
        spec(decalage: -1),
        spec(decalage: 200),
        spec(marge: -1),
        spec(marge: 60),
        spec(angle: double.nan),
      ]) {
        expect(() => calculerPlancher(s), throwsA(isA<SpecInvalide>()));
      }
    });

    test('valeurs limites acceptées', () {
      for (final s in [
        spec(s: 6),
        spec(s: 48),
        spec(entremises: 3),
        spec(decalage: 0),
        spec(marge: 50),
      ]) {
        expect(() => calculerPlancher(s), returnsNormally);
      }
    });
  });

  group('cohérence générale (100 formes aléatoires)', () {
    test('toujours un plan valide, quelle que soit la forme', () {
      final alea = math.Random(11);
      var essais = 0;
      while (essais < 100) {
        final n = 3 + alea.nextInt(4); // 3 à 6 côtés
        final cotes = [
          for (var i = 0; i < n - 1; i++) 60 + alea.nextDouble() * 200,
        ];
        final angles = [
          for (var i = 0; i < n - 2; i++) 45 + alea.nextDouble() * 200,
        ];
        Polygone p;
        try {
          p = Polygone.deCotesEtAngles(cotes, angles);
        } on FormeInvalide {
          continue; // forme fermée impossible : on en tire une autre
        }
        essais++;
        final r = _calc(p, s: [12.0, 16.0, 19.2, 24.0][alea.nextInt(4)]);
        if (r.nombreSolives == 0) {
          // Forme réduite à une lame : le calcul le dit au lieu de planter.
          expect(
            r.avertissements.any((a) => a.contains('trop étroite')),
            isTrue,
          );
          continue;
        }
        expect(
          r.bois.planches.expand((b) => b.pieces).length,
          r.nombreSolives +
              r.rives.length +
              r.entremises.length -
              r.bois.horsLimites.length,
        );
        for (final s in r.solives) {
          expect(s.longueurCoupe.isFinite && s.longueurCoupe > 0, isTrue);
        }
        _verifierFeuilles(r, verifierDecalage: false);
      }
    });
  });
}
