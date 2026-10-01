import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/solides.dart';
import 'package:flutter_test/flutter_test.dart';

double _aireTotale(List<List<Pt>> boucles) =>
    boucles.fold(0.0, (a, b) => a + aireSignee(b));

void main() {
  group('enveloppe convexe', () {
    test('carré avec points intérieurs et alignés', () {
      final e = enveloppeConvexe(const [
        Pt(0, 0),
        Pt(10, 0),
        Pt(10, 10),
        Pt(0, 10),
        Pt(5, 5),
        Pt(5, 0),
        Pt(10, 5),
      ]);
      expect(e, hasLength(4));
      expect(aireSignee(e), closeTo(100, 1e-9));
    });

    test('anti-horaire, quel que soit l\'ordre d\'entrée', () {
      final e = enveloppeConvexe(const [
        Pt(4, 3),
        Pt(0, 0),
        Pt(4, 0),
        Pt(0, 3),
      ]);
      expect(aireSignee(e), closeTo(12, 1e-9));
    });
  });

  group('polygone dans un rectangle', () {
    final l = const [
      Pt(0, 0),
      Pt(100, 0),
      Pt(100, 50),
      Pt(50, 50),
      Pt(50, 100),
      Pt(0, 100),
    ];

    test('rectangle entièrement dedans : inchangé', () {
      final p = polygoneDansRectangle(l, -10, 110, -10, 110);
      expect(aireSignee(p), closeTo(7500, 1e-6));
    });

    test('rectangle qui déborde de l\'encoche : aire de l\'intersection', () {
      // Fenêtre 40..100 × 40..100 : de la forme en L, il reste
      // 40..100 × 40..50 (600) + 40..50 × 50..100 (500) = 1100.
      final p = polygoneDansRectangle(l, 40, 100, 40, 100);
      expect(aireSignee(p), closeTo(1100, 1e-6));
    });

    test('rectangle hors de la forme : vide ou sans aire', () {
      final p = polygoneDansRectangle(l, 200, 300, 0, 50);
      expect(p.length < 3 || aireSignee(p).abs() < 1e-9, isTrue);
    });
  });

  group('contour d\'un rectangle moins des trous', () {
    test('sans trou : une boucle de 4 sommets', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const []);
      expect(c, hasLength(1));
      expect(c.single, hasLength(4));
      expect(aireSignee(c.single), closeTo(48 * 97, 1e-9));
    });

    test('trou à l\'intérieur : contour + trou horaire', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (10.0, 30.0, 20.0, 60.0),
      ]);
      expect(c, hasLength(2));
      expect(aireSignee(c[0]), closeTo(48 * 97, 1e-9));
      expect(aireSignee(c[1]), closeTo(-20 * 40, 1e-9));
      expect(_aireTotale(c), closeTo(48 * 97 - 800, 1e-9));
    });

    test('trou qui touche le bord : encoche en un seul contour', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (30.0, 60.0, 20.0, 60.0), // dépasse à droite
      ]);
      expect(c, hasLength(1));
      expect(aireSignee(c.single), closeTo(48 * 97 - 18 * 40, 1e-9));
      expect(c.single, hasLength(8)); // L inversé en U : 8 sommets
    });

    test('trou dans un coin : forme en L de 6 sommets', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (30.0, 60.0, -5.0, 40.0),
      ]);
      expect(c, hasLength(1));
      expect(c.single, hasLength(6));
      expect(aireSignee(c.single), closeTo(48 * 97 - 18 * 40, 1e-9));
    });

    test('trou sur toute la largeur : deux morceaux', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (-5.0, 60.0, 30.0, 40.0),
      ]);
      expect(c, hasLength(2));
      expect(_aireTotale(c), closeTo(48 * 87, 1e-9));
      expect(c.every((b) => aireSignee(b) > 0), isTrue);
    });

    test('trou plus grand que le rectangle : rien', () {
      final c = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (-5.0, 60.0, -5.0, 100.0),
      ]);
      expect(c, isEmpty);
    });

    test('deux trous : aire exacte', () {
      final c = contourRectangleMoinsTrous(0, 96, 0, 97, const [
        (10.0, 30.0, 20.0, 60.0),
        (50.0, 80.0, 30.0, 90.0),
      ]);
      expect(_aireTotale(c), closeTo(96 * 97 - 800 - 1800, 1e-9));
    });

    test(
      'propriété : l\'aire est toujours celle du rectangle moins les trous',
      () {
        final rnd = math.Random(5);
        for (var essai = 0; essai < 200; essai++) {
          final w = 20 + rnd.nextDouble() * 100,
              h = 20 + rnd.nextDouble() * 100;
          final trous = <Rect4>[];
          // Trous disjoints : une colonne chacun.
          final n = rnd.nextInt(4);
          for (var i = 0; i < n; i++) {
            final x0 = (i / n) * w + rnd.nextDouble() * (w / n) * 0.4 - 3;
            final x1 = x0 + rnd.nextDouble() * (w / n) * 0.5 + 1;
            final z0 = rnd.nextDouble() * h - 5;
            final z1 = z0 + rnd.nextDouble() * h * 0.7 + 1;
            trous.add((x0, x1, z0, z1));
          }
          var attendu = w * h;
          for (final t in trous) {
            final x0 = math.max(0.0, t.$1), x1 = math.min(w, t.$2);
            final z0 = math.max(0.0, t.$3), z1 = math.min(h, t.$4);
            if (x1 > x0 && z1 > z0) {
              attendu -= (x1 - x0) * (z1 - z0);
            }
          }
          final c = contourRectangleMoinsTrous(0, w, 0, h, trous);
          expect(
            _aireTotale(c),
            closeTo(attendu, 1e-6),
            reason: 'essai $essai',
          );
        }
      },
    );
  });

  group('prisme horizontal', () {
    Solide poutre() => extrusionHorizontale(
      id: 1,
      groupe: 'a',
      calque: Calque.solives,
      matiere: Matiere.bois,
      boucles: [
        const [Pt(0, 0), Pt(100, 0), Pt(100, 1.5), Pt(0, 1.5)],
      ],
      z0: -9.25,
      z1: 0,
    );

    test('6 faces, normales sortantes', () {
      final s = poutre();
      expect(s.faces, hasLength(6));
      final c = s.centre;
      for (final f in s.faces) {
        final milieu = P3(
          f.boucles.first.fold(0.0, (a, p) => a + p.x) / f.boucles.first.length,
          f.boucles.first.fold(0.0, (a, p) => a + p.y) / f.boucles.first.length,
          f.boucles.first.fold(0.0, (a, p) => a + p.z) / f.boucles.first.length,
        );
        expect((milieu - c).dot(f.normale), greaterThan(0));
        expect(f.normale.longueur, closeTo(1, 1e-9));
      }
      expect(s.faces.first.normale.z, 1);
      expect(s.z0, -9.25);
      expect(s.coque, hasLength(4));
    });

    test('sommets confondus : pas de face d\'épaisseur nulle', () {
      final s = extrusionHorizontale(
        id: 2,
        groupe: 'b',
        calque: Calque.solives,
        matiere: Matiere.bois,
        boucles: [
          const [Pt(0, 0), Pt(10, 0), Pt(10, 0), Pt(10, 5), Pt(0, 5)],
        ],
        z0: 0,
        z1: 1,
      );
      expect(s.faces.where((f) => f.laterale), hasLength(4));
    });

    test('contour avec un pont (arête parcourue deux fois) : chant ignoré', () {
      final s = extrusionHorizontale(
        id: 3,
        groupe: 'c',
        calque: Calque.sousPlancher,
        matiere: Matiere.sousPlancher,
        boucles: [
          const [Pt(0, 0), Pt(10, 0), Pt(10, 5), Pt(5, 5), Pt(10, 5), Pt(0, 5)],
        ],
        z0: 0,
        z1: 1,
      );
      // (10,5)→(5,5) et (5,5)→(10,5) se annulent.
      expect(s.faces.where((f) => f.laterale), hasLength(4));
    });
  });

  group('plaque de mur', () {
    // Mur le long de l'axe x du bâtiment, de 0 à 192 ; le contour étant
    // anti-horaire, l'extérieur est à droite : y < 0.
    const repere = RepereMur(origine: Pt(0, 0), u: Pt(1, 0), d: 3.5);

    test('repère : l\'extérieur est du côté de la normale sortante', () {
      expect(repere.n, const Pt(0, -1));
      expect(
        repere.plan(10, 3.5),
        const Pt(10, 0),
      ); // face extérieure sur le contour
      expect(
        repere.plan(10, 0),
        const Pt(10, 3.5),
      ); // face intérieure, vers l'intérieur
      expect(repere.plan(10, 5), const Pt(10, -1.5)); // couches extérieures
    });

    Solide? plaque({RepereMur r = repere}) => plaqueMurOuNull(
      id: 1,
      groupe: 'p',
      calque: Calque.panneaux,
      matiere: Matiere.osb,
      repere: r,
      boucles: [
        const [Pt(0, 0), Pt(48, 0), Pt(48, 97), Pt(0, 97)],
      ],
      y0: 3.5,
      y1: 3.9375,
    );

    test('grandes faces : normale sortante côté extérieur', () {
      final s = plaque()!;
      final avant = s.faces[0], arriere = s.faces[1];
      expect(avant.normale.y, closeTo(-1, 1e-9));
      expect(arriere.normale.y, closeTo(1, 1e-9));
      expect(
        avant.boucles.first.every((p) => (p.y + 0.4375).abs() < 1e-9),
        isTrue,
      );
      expect(s.z0, 0);
      expect(s.z1, 97);
    });

    test('chants : normales vers l\'extérieur de la plaque', () {
      final s = plaque()!;
      final c = P3(24, -0.21875, 48.5);
      final chants = s.faces.where((f) => f.laterale).toList();
      expect(chants, hasLength(4));
      for (final f in chants) {
        final m = f.boucles.first;
        final milieu = P3(
          m.fold(0.0, (a, p) => a + p.x) / 4,
          m.fold(0.0, (a, p) => a + p.y) / 4,
          m.fold(0.0, (a, p) => a + p.z) / 4,
        );
        expect((milieu - c).dot(f.normale), greaterThan(0));
      }
    });

    test('trou : chants du trou tournés vers l\'ouverture', () {
      final boucles = contourRectangleMoinsTrous(0, 48, 0, 97, const [
        (10.0, 30.0, 20.0, 60.0),
      ]);
      final s = plaqueMurOuNull(
        id: 2,
        groupe: 'p2',
        calque: Calque.panneaux,
        matiere: Matiere.osb,
        repere: repere,
        boucles: boucles,
        y0: 3.5,
        y1: 3.9375,
      )!;
      final chants = s.faces.where((f) => f.laterale).toList();
      expect(chants, hasLength(8)); // 4 de contour + 4 du trou
      // Chant du bas du trou (z = 20, face supérieure du morceau du bas) : normale +z.
      final basDuTrou = chants.firstWhere(
        (f) =>
            f.boucles.first.every((p) => (p.z - 20).abs() < 1e-9) &&
            f.boucles.first.every((p) => p.x >= 10 - 1e-9 && p.x <= 30 + 1e-9),
      );
      expect(basDuTrou.normale.z, closeTo(1, 1e-9));
      final hautDuTrou = chants.firstWhere(
        (f) => f.boucles.first.every((p) => (p.z - 60).abs() < 1e-9),
      );
      expect(hautDuTrou.normale.z, closeTo(-1, 1e-9));
    });

    test('onglet : le bout de la plaque est coupé selon la bissectrice', () {
      // Coin de 90° vu comme un onglet : cot(45°) = 1 ; sommet à x = 0.
      const onglet = RepereMur(
        origine: Pt(0, 0),
        u: Pt(1, 0),
        d: 3.5,
        xSommetDebut: 0,
        cotDebut: 1,
      );
      final s = plaque(r: onglet)!;
      // Face intérieure (profondeur 3,5 → y = 3,5 ; décalage d - y = 0) : x ≥ 0 ;
      // face extérieure y1 = 3,9375 : profondeur -0,4375 → x ≥ -0,4375 (le bord
      // x = 0 est conservé car plus grand).
      expect(
        s.faces[0].boucles.first.map((p) => p.x).reduce(math.min),
        closeTo(0, 1e-9),
      );
      // Plaque de l'ossature (profondeur 0 à 3,5) : à y = 0, x ≥ 3,5.
      final lisse = plaqueMurOuNull(
        id: 3,
        groupe: 'l',
        calque: Calque.ossature,
        matiere: Matiere.bois,
        repere: onglet,
        boucles: [
          const [Pt(0, 0), Pt(100, 0), Pt(100, 1.5), Pt(0, 1.5)],
        ],
        y0: 0,
        y1: 3.5,
      )!;
      final xInterieur = lisse.faces[1].boucles.first
          .map((p) => p.x)
          .reduce(math.min);
      final xExterieur = lisse.faces[0].boucles.first
          .map((p) => p.x)
          .reduce(math.min);
      expect(xInterieur, closeTo(3.5, 1e-9));
      expect(xExterieur, closeTo(0, 1e-9));
    });

    test('plaque entièrement coupée par l\'onglet : rien', () {
      const onglet = RepereMur(
        origine: Pt(0, 0),
        u: Pt(1, 0),
        d: 3.5,
        xSommetFin: 10,
        cotFin: 1,
      );
      final s = plaqueMurOuNull(
        id: 4,
        groupe: 'e',
        calque: Calque.ossature,
        matiere: Matiere.bois,
        repere: onglet,
        boucles: [
          const [Pt(20, 0), Pt(30, 0), Pt(30, 10), Pt(20, 10)],
        ],
        y0: 0,
        y1: 3.5,
      );
      expect(s, isNull);
    });
  });
}
