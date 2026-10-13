// Escalier à partir de 2 données (ou plus) : le calcul trouve le reste avec les
// girons et contremarches idéals du Code. Les cas sont calculés à la main
// (commentaires) ; un test au hasard vérifie les relations exactes.
import 'dart:math' as math;

import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_solveur.dart';
import 'package:flutter_test/flutter_test.dart';

SolutionEscalier _res(
  DonneesEscalier d, {
  UsageEscalier usage = UsageEscalier.prive,
  bool metrique = false,
}) => resoudreEscalier(d, usage: usage, metrique: metrique);

void main() {
  group(
    'hauteur + course : le nombre de contremarches qui respecte le Code',
    () {
      test('108 po sur 135 po : un seul nombre possible, 14 contremarches', () {
        // n = 14 : R = 108/14 = 7,714 po (196 mm ≤ 200) ; G = 135/13 = 10,385 po (263,8 mm ≥ 255).
        // n = 15 : G = 135/14 = 9,643 po = 244,9 mm < 255 : refusé. n = 13 : R = 8,31 po > 200 mm.
        final s = _res(const DonneesEscalier(hauteur: 108, course: 135));
        expect(s.nombreContremarches, 14);
        expect(s.contremarche, closeTo(108 / 14, 1e-12));
        expect(s.giron, closeTo(135 / 13, 1e-12));
        expect(s.hauteur, 108);
        expect(s.course, 135);
        expect(s.donnees, {DonneeEscalier.hauteur, DonneeEscalier.course});
        expect(s.trouvees, {
          DonneeEscalier.giron,
          DonneeEscalier.contremarche,
          DonneeEscalier.nombre,
        });
        expect(s.autresChoix, isEmpty);
      });

      test('course plus longue : le plus confortable parmi plusieurs nombres conformes', () {
        // H = 108, L = 150 : n = 14 → R 7,714 / G 11,538 (2R+G = 26,97 po) ; n = 15 → 7,2 / 10,714
        // (25,11 po) ; n = 16 → 6,75 / 10 (23,5 po, giron 254 mm refusé). Le plus près de 25 po : n = 15.
        final s = _res(const DonneesEscalier(hauteur: 108, course: 150));
        expect(s.nombreContremarches, 15);
        expect(s.giron, closeTo(150 / 14, 1e-12));
        expect(s.autresChoix.map((c) => c.nombreContremarches), [14]);
      });

      test('course impossible : le moins éloigné du Code, signalé', () {
        // H = 108, L = 60 : aucun giron permis. n = 14 est le moins éloigné (giron 4,6 po).
        final s = _res(const DonneesEscalier(hauteur: 108, course: 60));
        expect(s.nombreContremarches, 14);
        expect(
          s.notes.join(' '),
          contains('Aucun nombre de contremarches ne respecte le Code'),
        );
        expect(calculerEscalier(_spec(s)).conforme, isFalse);
      });
    },
  );

  group('hauteur + giron : la course en découle', () {
    test(
      '108 po avec un giron de 10 1/4 po : 15 contremarches, course 143 1/2 po',
      () {
        // Coûts |2R + G − 25| : n = 15 → 0,35 po ; n = 14 → 0,68 po ; n = 16 → 1,25 po.
        final s = _res(const DonneesEscalier(hauteur: 108, giron: 10.25));
        expect(s.nombreContremarches, 15);
        expect(s.contremarche, closeTo(7.2, 1e-12));
        expect(s.giron, 10.25);
        expect(s.course, closeTo(143.5, 1e-12));
        expect(s.trouvees, {
          DonneeEscalier.course,
          DonneeEscalier.contremarche,
          DonneeEscalier.nombre,
        });
      },
    );

    test('autres choix : conformes, du meilleur au moins bon, sans le choix retenu', () {
      final s = _res(const DonneesEscalier(hauteur: 108, giron: 10.25));
      // Coûts : n = 14 → 17,2 mm ; 16 → 31,8 mm ; 17 → 51,9 mm ; 18 → 69,9 mm.
      expect(s.autresChoix.map((c) => c.nombreContremarches), [14, 16, 17, 18]);
      final couts = s.autresChoix.map((c) => c.cout).toList();
      expect([...couts]..sort(), couts);
      expect(s.autresChoix.any((c) => c.nombreContremarches == 15), isFalse);
      // Chaque choix garde la hauteur et le giron demandés.
      for (final c in s.autresChoix) {
        expect(c.hauteur, 108);
        expect(c.giron, 10.25);
        expect(c.contremarche, closeTo(108 / c.nombreContremarches, 1e-12));
        expect(c.course, closeTo((c.nombreContremarches - 1) * 10.25, 1e-12));
      }
    });

    test(
      'un giron en dessous du Code : calculé quand même, le Code le signalera',
      () {
        final s = _res(const DonneesEscalier(hauteur: 108, giron: 8));
        expect(s.giron, 8);
        final r = calculerEscalier(_spec(s));
        expect(r.conforme, isFalse);
      },
    );
  });

  group('hauteur seule : l\'escalier idéal', () {
    test('108 po : 15 contremarches de 7 1/5 po, giron idéal 10 5/8 po', () {
      // Contremarche visée 7 1/4 : n = 15 (7,2 po) est le plus proche (n = 14 : 7,714).
      // Giron = 25 − 2 × 7,2 = 10,6 po → 1/16 po le plus proche : 10 5/8 po.
      final s = _res(const DonneesEscalier(hauteur: 108));
      expect(s.nombreContremarches, 15);
      expect(s.contremarche, closeTo(7.2, 1e-12));
      expect(s.giron, 10.625);
      expect(s.course, closeTo(14 * 10.625, 1e-12));
      expect(s.notes.join(' '), contains('Giron idéal'));
    });

    test('escalier commun : contremarche max 180 mm et giron min 280 mm', () {
      // 108 po : n = 16 (6,75 po = 171 mm) ; giron = 25 − 13,5 = 11,5 po (292 mm ≥ 280).
      final s = _res(
        const DonneesEscalier(hauteur: 108),
        usage: UsageEscalier.commun,
      );
      expect(s.nombreContremarches, 16);
      expect(s.giron, 11.5);
    });

    test('un giron idéal au-dessus du maximum du Code est ramené, jamais au-dessus', () {
      // 20 contremarches de 5 po : giron idéal 25 − 10 = 15 po > 355 mm (13,98 po) :
      // ramené au 1/16 po en dessous du maximum, 13 15/16 po (354,0 mm).
      final s = _res(const DonneesEscalier(nombre: 20, contremarche: 5));
      expect(s.giron, 13.9375);
      expect(s.giron * 25.4, lessThanOrEqualTo(355));
    });

    test(
      'un giron idéal sous le minimum du Code est remonté, jamais en dessous',
      () {
        // H = 108, R = 7,5 → n = 14 (R 7,714) ; 25 − 15,43 = 9,57 po < 10,04 po (255 mm) :
        // remonté à 10 1/16 po (255,6 mm), au 1/16 po au-dessus du minimum.
        final s = _res(const DonneesEscalier(hauteur: 108, contremarche: 7.5));
        expect(s.nombreContremarches, 14);
        expect(s.giron, 10.0625);
        expect(s.giron * 25.4, greaterThanOrEqualTo(255));
        expect(s.course, closeTo(13 * 10.0625, 1e-12));
      },
    );
  });

  group('hauteur + contremarche, ou hauteur + nombre', () {
    test('contremarche voulue 7 1/2 po sur 108 po : 14 contremarches, ajustée à 7 11/16', () {
      final s = _res(const DonneesEscalier(hauteur: 108, contremarche: 7.5));
      expect(s.contremarche, closeTo(108 / 14, 1e-12));
      expect(s.notes.join(' '), contains('Contremarche ajustée'));
    });

    test('contremarche exacte : aucune note d\'ajustement', () {
      // 108 / 15 = 7,2 po.
      final s = _res(const DonneesEscalier(hauteur: 108, contremarche: 7.2));
      expect(s.nombreContremarches, 15);
      expect(s.notes.join(' '), isNot(contains('ajustée')));
    });

    test('hauteur + nombre : contremarche = hauteur ÷ n, giron idéal', () {
      // 108 / 16 = 6,75 po ; giron = 25 − 13,5 = 11,5 po ; course = 15 × 11,5 = 172,5 po.
      final s = _res(const DonneesEscalier(hauteur: 108, nombre: 16));
      expect(s.contremarche, 6.75);
      expect(s.giron, 11.5);
      expect(s.course, 172.5);
    });

    test('le nombre imposé gagne sur la contremarche demandée', () {
      final s = _res(
        const DonneesEscalier(hauteur: 108, nombre: 16, contremarche: 7.5),
      );
      expect(s.nombreContremarches, 16);
      expect(s.contremarche, 6.75);
      expect(s.notes.join(' '), contains('Contremarche ajustée'));
    });
  });

  group('sans la hauteur : elle est trouvée', () {
    test('course + giron : n marches = course ÷ giron, hauteur = n × contremarche idéale', () {
      // 144 / 10,5 = 13,71 → 14 marches, 15 contremarches ; giron ajusté 144/14 = 10,2857 po ;
      // contremarche idéale (25 − 10,2857) / 2 = 7,357 po → 7 3/8 po ; hauteur 15 × 7,375 = 110 5/8 po.
      final s = _res(const DonneesEscalier(course: 144, giron: 10.5));
      expect(s.nombreContremarches, 15);
      expect(s.giron, closeTo(144 / 14, 1e-12));
      expect(s.contremarche, 7.375);
      expect(s.hauteur, closeTo(110.625, 1e-12));
      expect(s.course, 144);
      final texte = s.notes.join(' ');
      expect(texte, contains('Giron ajusté'));
      expect(texte, contains('Hauteur trouvée'));
    });

    test('course + giron : le nombre de marches est l\'entier le plus proche (13,3 → 13 marches)', () {
      // 136,325 ÷ 10,25 = 13,3 → 13 marches, 14 contremarches ; giron ajusté 136,325 ÷ 13 = 10,4865 po.
      final s = _res(const DonneesEscalier(course: 136.325, giron: 10.25));
      expect(s.nombreContremarches, 14);
      expect(s.giron, closeTo(136.325 / 13, 1e-12));
    });

    test('course + nombre', () {
      final s = _res(const DonneesEscalier(course: 144, nombre: 15));
      expect(s.giron, closeTo(144 / 14, 1e-12));
      expect(s.contremarche, 7.375);
      expect(s.hauteur, closeTo(110.625, 1e-12));
    });

    test('course + contremarche : giron idéal 10 1/2, 14 marches, hauteur = n × contremarche', () {
      // Giron idéal pour 7,25 po : 25 − 14,5 = 10,5 po ; 144 / 10,5 = 13,71 → 14 marches (G = 10,2857).
      final s = _res(const DonneesEscalier(course: 144, contremarche: 7.25));
      expect(s.nombreContremarches, 15);
      expect(s.giron, closeTo(144 / 14, 1e-12));
      expect(s.contremarche, 7.25);
      expect(s.hauteur, closeTo(108.75, 1e-12));
    });

    test('nombre + giron : course = (n − 1) × giron, contremarche idéale', () {
      // 12 contremarches, giron 11 po : course 121 po ; contremarche idéale (25 − 11) / 2 = 7 po ; hauteur 84 po.
      final s = _res(const DonneesEscalier(nombre: 12, giron: 11));
      expect(s.course, 121);
      expect(s.contremarche, 7);
      expect(s.hauteur, 84);
    });

    test('nombre + contremarche : hauteur = n × contremarche, giron idéal', () {
      // 15 × 7 = 105 po ; giron 25 − 14 = 11 po ; course 154 po.
      final s = _res(const DonneesEscalier(nombre: 15, contremarche: 7));
      expect(s.hauteur, 105);
      expect(s.giron, 11);
      expect(s.course, 154);
    });

    test('le nombre seul : contremarche visée 7 1/4, giron idéal', () {
      // 12 × 7,25 = 87 po ; giron 25 − 14,5 = 10,5 po ; course 11 × 10,5 = 115,5 po.
      final s = _res(const DonneesEscalier(nombre: 12));
      expect(s.hauteur, 87);
      expect(s.giron, 10.5);
      expect(s.course, 115.5);
    });
  });

  group('données insuffisantes ou invalides : message clair', () {
    test('contremarche + giron seulement : la hauteur ou la course manque', () {
      expect(
        () => _res(const DonneesEscalier(contremarche: 7, giron: 10.5)),
        throwsA(
          isA<EscalierInvalide>().having(
            (e) => e.message,
            'message',
            contains('insuffisantes'),
          ),
        ),
      );
    });

    test('une seule donnée sans hauteur, course ni nombre', () {
      for (final d in const [
        DonneesEscalier(giron: 10.5),
        DonneesEscalier(contremarche: 7),
        DonneesEscalier(),
      ]) {
        expect(() => _res(d), throwsA(isA<EscalierInvalide>()));
      }
    });

    test('valeurs invalides', () {
      expect(
        () => _res(const DonneesEscalier(hauteur: 0)),
        throwsA(isA<EscalierInvalide>()),
      );
      expect(
        () => _res(const DonneesEscalier(hauteur: -5, giron: 10)),
        throwsA(isA<EscalierInvalide>()),
      );
      expect(
        () => _res(const DonneesEscalier(hauteur: double.nan)),
        throwsA(isA<EscalierInvalide>()),
      );
      expect(
        () => _res(const DonneesEscalier(hauteur: double.infinity, giron: 10)),
        throwsA(isA<EscalierInvalide>()),
      );
      expect(
        () => _res(const DonneesEscalier(hauteur: 108, nombre: 1)),
        throwsA(isA<EscalierInvalide>()),
      );
      expect(
        () => _res(const DonneesEscalier(hauteur: 108, nombre: 101)),
        throwsA(isA<EscalierInvalide>()),
      );
    });
  });

  group('notes en métrique', () {
    test('mm au lieu des pouces', () {
      final s = _res(
        const DonneesEscalier(course: 144, giron: 10.5),
        metrique: true,
      );
      final texte = s.notes.join(' ');
      expect(texte, contains('mm'));
      expect(texte, isNot(contains('"')));
    });
  });

  group('relations exactes, sur des cas au hasard', () {
    final hasard = math.Random(2026);

    test('hauteur + course : n × R = hauteur, (n − 1) × G = course, Code respecté si possible', () {
      var avecChoix = 0;
      for (var i = 0; i < 400; i++) {
        final h = 40 + hasard.nextDouble() * 140;
        final l = 60 + hasard.nextDouble() * 260;
        final s = _res(DonneesEscalier(hauteur: h, course: l));
        expect(s.nombreContremarches * s.contremarche, closeTo(h, 1e-9));
        expect((s.nombreContremarches - 1) * s.giron, closeTo(l, 1e-9));
        expect(s.hauteur, h);
        expect(s.course, l);
        final ResultatEscalier r;
        try {
          r = calculerEscalier(_spec(s));
        } on EscalierInvalide {
          continue; // giron hors de ce que le calcul accepte (plus de 24 po) : cas irréaliste
        }
        final mauvais = r.erreurs.where(
          (v) => v.id == 'contremarche' || v.id == 'giron',
        );
        if (!s.notes.any((n) => n.contains('Aucun nombre'))) {
          avecChoix++;
          expect(
            mauvais,
            isEmpty,
            reason: 'h=$h l=$l n=${s.nombreContremarches}',
          );
        }
      }
      expect(
        avecChoix,
        greaterThan(50),
      ); // le test examine bien des cas conformes
    });

    test('hauteur + giron : contremarche dans le Code ; la course est (n − 1) × giron', () {
      for (var i = 0; i < 300; i++) {
        final h = 40 + hasard.nextDouble() * 140;
        final g = 10.05 + hasard.nextDouble() * 3.9;
        final s = _res(DonneesEscalier(hauteur: h, giron: g));
        expect(s.nombreContremarches * s.contremarche, closeTo(h, 1e-9));
        expect(s.course, closeTo((s.nombreContremarches - 1) * g, 1e-9));
        expect(
          s.contremarche * 25.4,
          lessThanOrEqualTo(200.06),
          reason: 'h=$h g=$g',
        );
        expect(
          s.contremarche * 25.4,
          greaterThanOrEqualTo(124.9),
          reason: 'h=$h g=$g',
        );
      }
    });

    test('hauteur seule : contremarche et giron dans le Code', () {
      for (var i = 0; i < 300; i++) {
        final h = 30 + hasard.nextDouble() * 160;
        final s = _res(DonneesEscalier(hauteur: h));
        expect(s.nombreContremarches * s.contremarche, closeTo(h, 1e-9));
        expect(
          s.contremarche * 25.4,
          inInclusiveRange(124.9, 200.06),
          reason: 'h=$h',
        );
        expect(s.giron * 25.4, inInclusiveRange(254.9, 355.1), reason: 'h=$h');
        // Un seizième de pouce près : le giron idéal est arrondi au 1/16 po.
        expect(
          (s.giron / (1 / 16)) - (s.giron / (1 / 16)).roundToDouble(),
          closeTo(0, 1e-9),
        );
      }
    });

    test(
      'course + giron (hauteur trouvée) : relations exactes et Code respecté',
      () {
        for (var i = 0; i < 300; i++) {
          final l = 60 + hasard.nextDouble() * 260;
          final g = 10.05 + hasard.nextDouble() * 3.9;
          final s = _res(DonneesEscalier(course: l, giron: g));
          expect(s.course, l);
          expect((s.nombreContremarches - 1) * s.giron, closeTo(l, 1e-9));
          expect(
            s.nombreContremarches * s.contremarche,
            closeTo(s.hauteur, 1e-9),
          );
          expect(
            s.contremarche * 25.4,
            inInclusiveRange(124.9, 200.06),
            reason: 'l=$l g=$g',
          );
        }
      },
    );
  });

  group('avec le calcul des limons', () {
    test('la solution se calcule : 108 po / 135 po donne 14 contremarches et un giron de 10 3/8 po', () {
      final s = _res(const DonneesEscalier(hauteur: 108, course: 135));
      final r = calculerEscalier(_spec(s));
      expect(r.nombreContremarches, 14);
      expect(r.giron, closeTo(10.3846, 1e-3));
      expect(r.course, closeTo(135, 1e-9));
      expect(r.conforme, isTrue);
    });
  });
}

/// Le calcul des limons pour une solution (le nombre et le giron sont fixés).
SpecEscalier _spec(SolutionEscalier s) => SpecEscalier(
  hauteurTotale: s.hauteur,
  mode: ModeCourse.gironFixe,
  giron: s.giron,
  nombreContremarches: s.nombreContremarches,
);
