import 'dart:math' as math;

import 'package:construction_app/charpente/empaquetage.dart';
import 'package:flutter_test/flutter_test.dart';

const _stocks = <double>[96, 120, 144, 168, 192, 216, 240]; // 8' à 20'

PieceCoupe _p(String id, double l) => PieceCoupe(id, l);

void main() {
  group('planches', () {
    test('aucune pièce : aucune planche', () {
      final r = decouperPlanches(const [], _stocks);
      expect(r.planches, isEmpty);
      expect(r.horsLimites, isEmpty);
      expect(r.longueurTotale, 0);
      expect(r.pertePourcent, 0);
    });

    test('une pièce : la plus courte planche qui la contient', () {
      expect(decouperPlanches([_p('a', 100)], _stocks).parLongueur, {120: 1});
      expect(decouperPlanches([_p('a', 96)], _stocks).parLongueur, {96: 1});
      expect(decouperPlanches([_p('a', 96.01)], _stocks).parLongueur, {120: 1});
      expect(decouperPlanches([_p('a', 240)], _stocks).parLongueur, {240: 1});
    });

    test('plus longue que la planche maximale : signalée, jamais perdue', () {
      final r = decouperPlanches([_p('a', 241), _p('b', 50)], _stocks);
      expect(r.horsLimites.map((p) => p.id), ['a']);
      expect(r.planches, hasLength(1));
    });

    test('deux pièces dans une planche : trait de scie compté', () {
      // 83 + 83 + 1/8 = 166,125 → planche de 14'.
      expect(
        decouperPlanches([_p('a', 83), _p('b', 83)], _stocks).parLongueur,
        {168: 1},
      );
      // 84 + 84 + 1/8 = 168,125 > 14' → 16'.
      expect(
        decouperPlanches([_p('a', 84), _p('b', 84)], _stocks).parLongueur,
        {192: 1},
      );
      // Sans trait de scie : 14' suffit.
      expect(
        decouperPlanches(
          [_p('a', 84), _p('b', 84)],
          _stocks,
          trait: 0,
        ).parLongueur,
        {168: 1},
      );
    });

    test('11\' + 5\' : une planche de 18\' (moins de bois que 12\' + 8\')', () {
      final r = decouperPlanches([_p('a', 132), _p('b', 60)], _stocks);
      expect(r.parLongueur, {216: 1});
      expect(r.longueurTotale, 216);
    });

    test('11\' + 5\' avec des planches de 16\' au plus : 12\' et 8\'', () {
      final r = decouperPlanches(
        [_p('a', 132), _p('b', 60)],
        const <double>[96, 120, 144, 168, 192],
      );
      expect(r.parLongueur, {96: 1, 144: 1});
      expect(r.longueurTotale, 240);
    });

    test('quatre montants de 7 pi - 1 po : deux planches de 14 pi', () {
      final r = decouperPlanches([
        for (var i = 0; i < 4; i++) _p('m$i', 83),
      ], _stocks);
      expect(r.parLongueur, {168: 2});
    });

    test('longueurs permises restreintes (8, 10, 12 pi)', () {
      final r = decouperPlanches(
        [_p('a', 83), _p('b', 83)],
        const <double>[96, 120, 144],
      );
      expect(r.parLongueur, {96: 2});
      expect(
        decouperPlanches(
          [_p('a', 150)],
          const <double>[96, 120, 144],
        ).horsLimites,
        hasLength(1),
      );
    });

    test('liste de longueurs vide : tout est hors limites', () {
      final r = decouperPlanches([_p('a', 50)], const <double>[]);
      expect(r.horsLimites, hasLength(1));
    });

    test(
      'une pièce par planche : deux montants = deux 8 pi, pas une 16 pi',
      () {
        final pieces = [_p('a', 92.625), _p('b', 92.625)];
        expect(decouperPlanches(pieces, _stocks).parLongueur, {192: 1});
        expect(
          decouperPlanches(
            pieces,
            _stocks,
            uneParPlanche: {'a', 'b'},
          ).parLongueur,
          {96: 2},
        );
      },
    );

    test('une pièce par planche : les chutes reçoivent les petites pièces', () {
      // Montant de 92 5/8 po dans une 8 pi : 3 3/8 po de chute, un court
      // montant de 2 1/8 po y entre ; un de 4 po n'y entre pas.
      final r = decouperPlanches(
        [_p('m', 92.625), _p('c', 2.125)],
        _stocks,
        uneParPlanche: {'m'},
      );
      expect(r.parLongueur, {96: 1});
      expect(r.planches.single.pieces, hasLength(2));
      final r2 = decouperPlanches(
        [_p('m', 92.625), _p('c', 4)],
        _stocks,
        uneParPlanche: {'m'},
      );
      expect(r2.planches, hasLength(2));
    });

    test('une pièce par planche : longueur commerciale la plus courte', () {
      final r = decouperPlanches(
        [_p('a', 100), _p('b', 150), _p('c', 240)],
        _stocks,
        uneParPlanche: {'a', 'b', 'c'},
      );
      expect(r.parLongueur, {120: 1, 168: 1, 240: 1});
    });

    test(
      'propriétés sur 300 cas aléatoires : tout est coupé, rien ne dépasse',
      () {
        final alea = math.Random(42);
        for (var essai = 0; essai < 300; essai++) {
          final n = 1 + alea.nextInt(40);
          final pieces = [
            for (var i = 0; i < n; i++) _p('p$i', 6 + alea.nextDouble() * 220),
          ];
          final r = decouperPlanches(pieces, _stocks);
          final ids = r.planches
              .expand((b) => b.pieces)
              .map((p) => p.id)
              .toList();
          expect(ids.length, n, reason: 'essai $essai');
          expect(ids.toSet().length, n, reason: 'doublon, essai $essai');
          for (final b in r.planches) {
            final besoin = b.utilise + traitDeScie * (b.pieces.length - 1);
            expect(
              besoin,
              lessThanOrEqualTo(b.stock + 1e-6),
              reason: 'planche trop courte, essai $essai',
            );
            expect(_stocks.contains(b.stock), isTrue);
            expect(b.chute, greaterThanOrEqualTo(-1e-6));
          }
          // Jamais plus de bois que « une planche par pièce ».
          final unParPiece = pieces.fold<double>(
            0,
            (s, p) => s + _stocks.firstWhere((x) => x >= p.longueur),
          );
          expect(
            r.longueurTotale,
            lessThanOrEqualTo(unParPiece + 1e-6),
            reason: 'essai $essai',
          );
        }
      },
    );

    test('la perte est cohérente', () {
      final r = decouperPlanches([_p('a', 90), _p('b', 90)], _stocks);
      expect(r.pertePourcent, greaterThan(0));
      expect(r.pertePourcent, lessThan(20));
    });
  });

  group('feuilles', () {
    ResultatFeuilles go(List<PieceRect> p, {double trait = 0}) =>
        empaqueterFeuilles(
          p,
          longueurFeuille: 96,
          largeurFeuille: 48,
          trait: trait,
        );

    test('une feuille entière : 1 feuille, aucune perte', () {
      final r = go([const PieceRect('a', 96, 48)]);
      expect(r.nombre, 1);
      expect(r.pertePourcent, closeTo(0, 1e-9));
    });

    test('40 + 56 sur la largeur complète : une seule feuille', () {
      final r = go([
        const PieceRect('a', 40, 48),
        const PieceRect('b', 56, 48),
      ]);
      expect(r.nombre, 1);
      expect(r.feuilles.single.placements, hasLength(2));
    });

    test('deux pièces de 60 : deux feuilles', () {
      expect(
        go([const PieceRect('a', 60, 48), const PieceRect('b', 60, 48)]).nombre,
        2,
      );
    });

    test(
      'bandes refendues : 30 + 18 de large dans la même feuille (trait 0)',
      () {
        final r = go([
          const PieceRect('a', 96, 30),
          const PieceRect('b', 96, 18),
        ]);
        expect(r.nombre, 1);
      },
    );

    test('avec un trait de scie, 30 + 18 ne tiennent plus dans 48', () {
      expect(
        go([
          const PieceRect('a', 96, 30),
          const PieceRect('b', 96, 18),
        ], trait: 0.125).nombre,
        2,
      );
    });

    test('plusieurs petites pièces partagent une feuille', () {
      final r = go([for (var i = 0; i < 4; i++) PieceRect('p$i', 40, 20)]);
      // 2 pièces de 40 par rangée, 2 rangées de 20 (+ rangée restante de 8) : 4 pièces = 1 feuille.
      expect(r.nombre, 1);
    });

    test('pas de rotation : 100 × 20 ne tient pas dans 96 × 48', () {
      final r = go([const PieceRect('a', 100, 20)]);
      expect(r.horsLimites, hasLength(1));
      expect(r.nombre, 0);
    });

    test('rotation permise : 20 × 90 est tournée pour entrer', () {
      final r = go([const PieceRect('a', 20, 90, rotationPermise: true)]);
      expect(r.nombre, 1);
      expect(r.feuilles.single.placements.single.tournee, isTrue);
      expect(r.feuilles.single.placements.single.a, 90);
    });

    test('trop grande dans les deux sens : hors limites', () {
      final r = go([const PieceRect('a', 120, 60, rotationPermise: true)]);
      expect(r.horsLimites, hasLength(1));
    });

    test('aucune pièce', () {
      final r = go(const []);
      expect(r.nombre, 0);
      expect(r.pertePourcent, 0);
    });

    test(
      'propriétés sur 200 cas aléatoires : aucun chevauchement, rien en dehors',
      () {
        final alea = math.Random(7);
        for (var essai = 0; essai < 200; essai++) {
          final n = 1 + alea.nextInt(25);
          final pieces = [
            for (var i = 0; i < n; i++)
              PieceRect(
                'p$i',
                4 + alea.nextDouble() * 92,
                4 + alea.nextDouble() * 44,
              ),
          ];
          final r = go(pieces);
          expect(r.horsLimites, isEmpty);
          final vus = <String>{};
          for (final f in r.feuilles) {
            for (final a in f.placements) {
              vus.add(a.piece.id);
              expect(a.x, greaterThanOrEqualTo(-1e-9));
              expect(a.y, greaterThanOrEqualTo(-1e-9));
              expect(
                a.x + a.a,
                lessThanOrEqualTo(96 + 1e-6),
                reason: 'essai $essai',
              );
              expect(
                a.y + a.b,
                lessThanOrEqualTo(48 + 1e-6),
                reason: 'essai $essai',
              );
              for (final b in f.placements) {
                if (identical(a, b)) {
                  continue;
                }
                final chevauche =
                    a.x < b.x + b.a - 1e-6 &&
                    b.x < a.x + a.a - 1e-6 &&
                    a.y < b.y + b.b - 1e-6 &&
                    b.y < a.y + a.b - 1e-6;
                expect(
                  chevauche,
                  isFalse,
                  reason: 'chevauchement, essai $essai',
                );
              }
            }
          }
          expect(vus.length, n, reason: 'pièces manquantes, essai $essai');
          // Jamais plus de feuilles que « une feuille par pièce ».
          expect(r.nombre, lessThanOrEqualTo(n));
          expect(
            r.aireUtile,
            closeTo(pieces.fold<double>(0, (s, p) => s + p.aire), 1e-6),
          );
        }
      },
    );
  });
}
