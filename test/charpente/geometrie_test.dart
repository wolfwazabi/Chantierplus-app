import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
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

void main() {
  group('rectangle', () {
    test('aire, périmètre, angles, boîte', () {
      final r = _rect;
      expect(r.aire, 19656);
      expect(r.perimetre, 564);
      expect(r.longueursCotes, [156, 126, 156, 126]);
      expect(r.anglesInterieursDeg.every((a) => (a - 90).abs() < 1e-9), isTrue);
      expect(r.estConvexe, isTrue);
      expect(r.estRectangle, isTrue);
      expect(r.boite.largeur, 156);
      expect(r.boite.hauteur, 126);
    });

    test('orientation horaire : inversée en anti-horaire', () {
      final horaire = Polygone(const [
        Pt(0, 0),
        Pt(0, 126),
        Pt(156, 126),
        Pt(156, 0),
      ]);
      expect(horaire.aire, 19656);
      expect(
        horaire.anglesInterieursDeg.every((a) => (a - 90).abs() < 1e-9),
        isTrue,
      );
    });

    test('sommet répété à la fin : ignoré', () {
      final p = Polygone(const [
        Pt(0, 0),
        Pt(10, 0),
        Pt(10, 10),
        Pt(0, 10),
        Pt(0, 0),
      ]);
      expect(p.nombre, 4);
    });

    test('normale intérieure : vers l\'intérieur sur chaque côté', () {
      final r = _rect;
      for (var i = 0; i < 4; i++) {
        final milieu = (r.sommet(i) + r.sommet(i + 1)) * 0.5;
        final dedans = milieu + r.normaleInterieure(i) * 1.0;
        expect(
          dedans.x > 0 && dedans.x < 156 && dedans.y > 0 && dedans.y < 126,
          isTrue,
          reason: 'côté $i',
        );
      }
    });
  });

  group('forme en L (concave)', () {
    test('aire, angle rentrant, non convexe', () {
      final l = _enL;
      expect(l.aire, 43200);
      expect(l.estConvexe, isFalse);
      expect(l.estRectangle, isFalse);
      expect(l.angleInterieurDeg(3), closeTo(270, 1e-9)); // coin rentrant
      expect(
        l.anglesInterieursDeg.fold<double>(0, (a, b) => a + b),
        closeTo(720, 1e-9),
      );
    });

    test('aire dans un rectangle (découpe de feuille)', () {
      expect(_enL.aireDansRectangle(100, 100, 200, 200), closeTo(3600, 1e-6));
      expect(_enL.aireDansRectangle(0, 0, 240, 240), closeTo(43200, 1e-6));
      expect(
        _enL.aireDansRectangle(130, 130, 200, 200),
        closeTo(0, 1e-6),
      ); // dans l'encoche
      expect(_enL.aireDansRectangle(-50, -50, 5, 5), closeTo(25, 1e-6));
    });
  });

  group('formes invalides', () {
    test('moins de 3 sommets, sans surface, doublons', () {
      expect(
        () => Polygone(const [Pt(0, 0), Pt(1, 1)]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone(const [Pt(0, 0), Pt(5, 0), Pt(10, 0)]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone(const [Pt(0, 0), Pt(0, 0), Pt(5, 5)]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone(
          List.generate(25, (i) => Pt(i.toDouble(), (i * i).toDouble())),
        ),
        throwsA(isA<FormeInvalide>()),
      );
    });

    test('nœud papillon (côtés qui se croisent)', () {
      expect(
        () => Polygone(const [Pt(0, 0), Pt(10, 10), Pt(10, 0), Pt(0, 10)]),
        throwsA(isA<FormeInvalide>()),
      );
    });

    test('côté qui se replie sur le précédent (angle 0°)', () {
      expect(
        () => Polygone(const [Pt(0, 0), Pt(10, 0), Pt(5, 0), Pt(5, 5)]),
        throwsA(isA<FormeInvalide>()),
      );
    });

    test('un sommet posé sur un côté éloigné', () {
      expect(
        () => Polygone(const [
          Pt(0, 0),
          Pt(10, 0),
          Pt(10, 10),
          Pt(5, 0),
          Pt(0, 10),
        ]),
        throwsA(isA<FormeInvalide>()),
      );
    });

    test('valeurs non finies', () {
      expect(
        () => Polygone(const [Pt(0, 0), Pt(double.nan, 0), Pt(5, 5)]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone(const [Pt(0, 0), Pt(double.infinity, 0), Pt(5, 5)]),
        throwsA(isA<FormeInvalide>()),
      );
    });

    test('sommets colinéaires permis (angle de 180°)', () {
      final p = Polygone(const [
        Pt(0, 0),
        Pt(5, 0),
        Pt(10, 0),
        Pt(10, 10),
        Pt(0, 10),
      ]);
      expect(p.aire, 100);
      expect(p.angleInterieurDeg(1), closeTo(180, 1e-9));
    });
  });

  group('côtés et angles', () {
    test(
      'rectangle : 3 côtés + 2 angles de 90° → le dernier côté se déduit',
      () {
        final p = Polygone.deCotesEtAngles([156, 126, 156], [90, 90]);
        expect(p.nombre, 4);
        expect(p.longueurCote(3), closeTo(126, 1e-9));
        expect(p.aire, closeTo(19656, 1e-6));
        expect(p.estRectangle, isTrue);
      },
    );

    test('triangle 3-4-5 (côtés 36 et 48, angle droit) : hypoténuse et angles déduits', () {
      final p = Polygone.deCotesEtAngles([36, 48], [90]);
      expect(p.nombre, 3);
      expect(p.longueurCote(2), closeTo(60, 1e-9));
      final angles = p.anglesInterieursDeg;
      expect(angles[0], closeTo(53.1301, 1e-3));
      expect(angles[1], closeTo(90, 1e-9));
      expect(angles[2], closeTo(36.8699, 1e-3));
      expect(angles.fold<double>(0, (a, b) => a + b), closeTo(180, 1e-9));
    });

    test('angle de 35° : côté de fermeture par la loi des cosinus', () {
      final p = Polygone.deCotesEtAngles([144, 96], [35]);
      final attendu = math.sqrt(
        144 * 144 + 96 * 96 - 2 * 144 * 96 * math.cos(35 * math.pi / 180),
      );
      expect(p.nombre, 3);
      expect(p.angleInterieurDeg(1), closeTo(35, 1e-9));
      expect(p.longueurCote(2), closeTo(attendu, 1e-9));
      expect(
        p.aire,
        closeTo(0.5 * 144 * 96 * math.sin(35 * math.pi / 180), 1e-6),
      );
    });

    test('pentagone régulier (5 côtés égaux, angles de 108°)', () {
      final p = Polygone.deCotesEtAngles([100, 100, 100, 100], [108, 108, 108]);
      expect(p.nombre, 5);
      for (final c in p.longueursCotes) {
        expect(c, closeTo(100, 1e-9));
      }
      for (final a in p.anglesInterieursDeg) {
        expect(a, closeTo(108, 1e-9));
      }
      // Aire d'un pentagone régulier de côté a : a² × √(25 + 10√5) / 4.
      expect(
        p.aire,
        closeTo(100 * 100 * math.sqrt(25 + 10 * math.sqrt(5)) / 4, 1e-6),
      );
    });

    test('forme à 5 côtés avec un coin à 90° et un autre à 35°', () {
      // 4 côtés + 3 angles saisis ; le 5e côté et les 2 derniers angles se déduisent.
      final p = Polygone.deCotesEtAngles([180, 120, 90, 140], [90, 110, 120]);
      expect(p.nombre, 5);
      expect(
        p.anglesInterieursDeg.fold<double>(0, (a, b) => a + b),
        closeTo(540, 1e-9),
      );
      expect(p.estSimple, isTrue);
      expect(p.aire, greaterThan(0));
      // Les angles saisis sont bien aux sommets 1, 2 et 3.
      expect(p.angleInterieurDeg(1), closeTo(90, 1e-9));
      expect(p.angleInterieurDeg(2), closeTo(110, 1e-9));
      expect(p.angleInterieurDeg(3), closeTo(120, 1e-9));
    });

    test('angle rentrant (> 180°) : forme en L par côtés et angles', () {
      final p = Polygone.deCotesEtAngles(
        [240, 120, 120, 120, 120],
        [90, 90, 270, 90],
      );
      expect(p.nombre, 6);
      expect(p.aire, closeTo(43200, 1e-6));
      expect(p.estConvexe, isFalse);
    });

    test('refus : angles inversés, forme croisée, valeurs invalides', () {
      expect(
        () => Polygone.deCotesEtAngles([100, 100], [270]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100], []),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, 100, 100], [90]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, 0], [90]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, -5], [90]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, 100], [0]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, 100], [360]),
        throwsA(isA<FormeInvalide>()),
      );
      expect(
        () => Polygone.deCotesEtAngles([100, double.nan], [90]),
        throwsA(isA<FormeInvalide>()),
      );
      // Les angles font se croiser les côtés.
      expect(
        () => Polygone.deCotesEtAngles([100, 100, 100, 100], [30, 30, 30]),
        throwsA(isA<FormeInvalide>()),
      );
    });
  });

  group('cordes (joists, feuilles)', () {
    test('rectangle : une corde de bout en bout, côtés gauche et droit', () {
      final c = _rect.cordes(horizontale: true, c: 60);
      expect(c, hasLength(1));
      expect(c.single.debut, closeTo(0, 1e-9));
      expect(c.single.fin, closeTo(156, 1e-9));
      expect(c.single.longueur, closeTo(156, 1e-9));
      expect(
        _rect.cordes(horizontale: false, c: 10).single.longueur,
        closeTo(126, 1e-9),
      );
    });

    test('hors du polygone : aucune corde', () {
      expect(_rect.cordes(horizontale: true, c: -1), isEmpty);
      expect(_rect.cordes(horizontale: true, c: 200), isEmpty);
    });

    test('forme en L : une ou deux cordes selon la position', () {
      final l = _enL;
      expect(
        l.cordes(horizontale: true, c: 60).single.longueur,
        closeTo(240, 1e-9),
      );
      expect(
        l.cordes(horizontale: true, c: 180).single.longueur,
        closeTo(120, 1e-9),
      );
      expect(
        l.cordes(horizontale: false, c: 180).single.longueur,
        closeTo(120, 1e-9),
      );
      // Sur la ligne même de l'encoche (y = 120) : on garde la corde la plus longue.
      expect(
        l.cordes(horizontale: true, c: 120).single.longueur,
        closeTo(240, 1e-6),
      );
    });

    test('forme en U : deux cordes séparées par l\'encoche', () {
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
      final deux = u.cordes(horizontale: true, c: 150);
      expect(deux, hasLength(2));
      expect(deux[0].longueur, closeTo(100, 1e-9));
      expect(deux[1].longueur, closeTo(100, 1e-9));
      expect(deux[0].fin, closeTo(100, 1e-9));
      expect(deux[1].debut, closeTo(200, 1e-9));
      expect(
        u.cordes(horizontale: true, c: 50).single.longueur,
        closeTo(300, 1e-9),
      );
    });

    test('côté en biais (trapèze) : corde et côtés d\'extrémité', () {
      final t = Polygone(const [
        Pt(0, 0),
        Pt(200, 0),
        Pt(150, 100),
        Pt(50, 100),
      ]);
      final c = t.cordes(horizontale: true, c: 50).single;
      expect(c.debut, closeTo(25, 1e-6));
      expect(c.fin, closeTo(175, 1e-6));
      expect(c.areteDebut, 3); // côté (50,100) → (0,0)
      expect(c.areteFin, 1); // côté (200,0) → (150,100)
    });

    test('somme des cordes ≈ aire (intégration)', () {
      for (final p in [_rect, _enL]) {
        var aire = 0.0;
        for (var y = 0.5; y < p.boite.yMax; y += 1) {
          for (final c in p.cordes(horizontale: true, c: y, union: false)) {
            aire += c.longueur;
          }
        }
        expect(aire, closeTo(p.aire, p.aire * 0.01));
      }
    });
  });

  group('rotation', () {
    test('une rotation conserve aire, côtés et angles', () {
      final p = Polygone.deCotesEtAngles([180, 120, 90, 140], [90, 110, 120]);
      final q = p.pivote(0.7);
      expect(q.aire, closeTo(p.aire, 1e-6));
      for (var i = 0; i < p.nombre; i++) {
        expect(q.longueurCote(i), closeTo(p.longueurCote(i), 1e-9));
        expect(q.angleInterieurDeg(i), closeTo(p.angleInterieurDeg(i), 1e-9));
      }
    });
  });
}
