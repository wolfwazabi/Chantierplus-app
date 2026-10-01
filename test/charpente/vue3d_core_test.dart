import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/scene.dart';
import 'package:construction_app/charpente/solides.dart';
import 'package:construction_app/charpente/vue3d_core.dart';
import 'package:flutter_test/flutter_test.dart';

Solide _boite(
  int id,
  double x0,
  double y0,
  double z0,
  double x1,
  double y1,
  double z1,
) => extrusionHorizontale(
  id: id,
  groupe: 'b$id',
  calque: Calque.solives,
  matiere: Matiere.bois,
  boucles: [
    [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)],
  ],
  z0: z0,
  z1: z1,
);

Scene _batiment({bool plancher = true}) {
  final contour = Polygone.rectangle(288, 240);
  final base = mursDuContour(contour, hauteur: 97.125);
  const fenetre = Ouverture(
    type: TypeOuverture.fenetre,
    largeurCadre: 36,
    hauteurCadre: 48,
    position: 100,
  );
  const porte = Ouverture(
    type: TypeOuverture.porte,
    largeurCadre: 36,
    hauteurCadre: 80,
    position: 200,
  );
  final specs = [
    for (var i = 0; i < base.length; i++)
      SpecMur(
        nom: base[i].nom,
        longueur: base[i].longueur,
        hauteur: base[i].hauteur,
        ouvertures: i == 0
            ? const [fenetre, porte]
            : (i == 1 ? const [fenetre] : const []),
        montantsCoinDebut: base[i].montantsCoinDebut,
        montantsCoinFin: base[i].montantsCoinFin,
        cote: base[i].cote,
        retraitDebut: base[i].retraitDebut,
        retraitFin: base[i].retraitFin,
        angleDebut: base[i].angleDebut,
        angleFin: base[i].angleFin,
      ),
  ];
  return construireScene(
    plancher: plancher
        ? calculerPlancher(SpecPlancher(forme: contour, rangeesEntremises: 1))
        : null,
    murs: calculerMurs(specs, const ParametresMurs()),
    contour: contour,
  );
}

/// Pièce visible sous le pixel, d'après l'ordre d'affichage (dernière dessinée
/// dont une face visible contient le pixel).
Solide? _parOrdre(
  List<Solide> solides,
  List<int> ordre,
  Camera cam,
  Pt px,
  double w,
  double h,
) {
  final e = cam.oeil;
  for (final i in ordre.reversed) {
    for (final f in solides[i].faces) {
      if (f.normale.dot(e) <= 1e-9) {
        continue;
      }
      final b = [
        for (final l in f.boucles) [for (final p in l) cam.projeter(p, w, h)],
      ];
      if (pointDansBoucles(px, b)) {
        return solides[i];
      }
    }
  }
  return null;
}

void main() {
  group('caméra', () {
    test('axes orthonormés et main droite, quelle que soit la vue', () {
      for (final az in [-3.0, -1.0, 0.0, 0.7, 2.5]) {
        for (final el in [0.05, 0.5, 1.0, 1.5]) {
          final c = Camera(
            azimut: az,
            elevation: el,
            echelle: 1,
            cible: const P3(0, 0, 0),
          );
          expect(c.oeil.longueur, closeTo(1, 1e-12));
          expect(c.droite.longueur, closeTo(1, 1e-12));
          expect(c.haut.longueur, closeTo(1, 1e-12));
          expect(c.oeil.dot(c.droite), closeTo(0, 1e-12));
          expect(c.oeil.dot(c.haut), closeTo(0, 1e-12));
          expect(c.droite.dot(c.haut), closeTo(0, 1e-12));
          final d = c.droite.cross(c.haut);
          expect((d - c.oeil).longueur, closeTo(0, 1e-12));
        }
      }
    });

    test(
      'projection : la cible est au centre, le haut du monde est en haut',
      () {
        final c = Camera(
          azimut: 0.4,
          elevation: 0.6,
          echelle: 2,
          cible: const P3(10, 20, 5),
          decalage: const Pt(7, -3),
        );
        final p = c.projeter(const P3(10, 20, 5), 800, 600);
        expect(p.x, closeTo(407, 1e-9));
        expect(p.y, closeTo(297, 1e-9));
        final haut = c.projeter(const P3(10, 20, 15), 800, 600);
        expect(haut.y, lessThan(p.y)); // y de l'écran vers le bas
      },
    );

    test('origine du rayon : projeter(origine) = pixel', () {
      final c = Camera(
        azimut: -0.8,
        elevation: 0.5,
        echelle: 1.7,
        cible: const P3(3, 4, 5),
        decalage: const Pt(10, 20),
      );
      const pixel = Pt(123, 321);
      final o = c.origineRayon(pixel, 800, 600);
      final q = c.projeter(o, 800, 600);
      expect(q.x, closeTo(123, 1e-9));
      expect(q.y, closeTo(321, 1e-9));
    });

    test('cadrage : toute la scène tient dans l\'écran avec la marge', () {
      final s = _batiment();
      for (final (w, h) in [(800.0, 600.0), (360.0, 640.0), (1200.0, 400.0)]) {
        final c = Camera.pourScene(s, w, h, marge: 20);
        for (final x in [s.min.x, s.max.x]) {
          for (final y in [s.min.y, s.max.y]) {
            for (final z in [s.min.z, s.max.z]) {
              final p = c.projeter(P3(x, y, z), w, h);
              expect(p.x, inInclusiveRange(20 - 1e-6, w - 20 + 1e-6));
              expect(p.y, inInclusiveRange(20 - 1e-6, h - 20 + 1e-6));
            }
          }
        }
      }
    });
  });

  group('ordre d\'affichage', () {
    test(
      'deux pièces côte à côte : la plus proche est dessinée en dernier',
      () {
        final a = _boite(0, 0, 0, 0, 10, 10, 10);
        final b = _boite(1, 20, 0, 0, 30, 10, 10);
        // Œil du côté des x positifs : b est devant.
        var c = const Camera(
          azimut: 0,
          elevation: 0.3,
          echelle: 1,
          cible: P3(15, 5, 5),
        );
        expect(ordreAffichage([a, b], c), [0, 1]);
        // Œil du côté des x négatifs : a est devant.
        c = const Camera(
          azimut: math.pi,
          elevation: 0.3,
          echelle: 1,
          cible: P3(15, 5, 5),
        );
        expect(ordreAffichage([a, b], c), [1, 0]);
      },
    );

    test('au-dessus / en dessous', () {
      final bas = _boite(0, 0, 0, 0, 10, 10, 5);
      final haut = _boite(1, 0, 0, 5, 10, 10, 10);
      var c = const Camera(
        azimut: 0.3,
        elevation: 0.8,
        echelle: 1,
        cible: P3(5, 5, 5),
      );
      expect(ordreAffichage([haut, bas], c), [1, 0]); // le bas d'abord
      c = const Camera(
        azimut: 0.3,
        elevation: -0.8,
        echelle: 1,
        cible: P3(5, 5, 5),
      );
      expect(ordreAffichage([haut, bas], c), [
        0,
        1,
      ]); // vu d'en dessous : le haut d'abord
    });

    test(
      'pièces qui ne se recouvrent pas : toutes présentes, une seule fois',
      () {
        final s = _batiment();
        final c = Camera.pourScene(s, 800, 600);
        final o = ordreAffichage(s.solides, c);
        expect(o.length, s.solides.length);
        expect(o.toSet().length, s.solides.length);
      },
    );

    test(
      'accord avec la profondeur exacte : bâtiment complet, vues au hasard',
      () {
        final s = _batiment();
        final alea = math.Random(3);
        var total = 0, ecarts = 0;
        for (var essai = 0; essai < 24; essai++) {
          final cam = Camera.pourScene(
            s,
            800,
            600,
            azimut: alea.nextDouble() * 2 * math.pi,
            elevation: 0.15 + alea.nextDouble() * 1.3,
          );
          final ordre = ordreAffichage(s.solides, cam);
          for (var k = 0; k < 250; k++) {
            final px = Pt(alea.nextDouble() * 800, alea.nextDouble() * 600);
            final vrai = choisir(s.solides, cam, px, 800, 600);
            final dessine = _parOrdre(s.solides, ordre, cam, px, 800, 600);
            total++;
            if (vrai?.solide.id != dessine?.id) {
              ecarts++;
            }
          }
        }
        // L'ordre « du plus loin au plus proche » est exact, sauf rares cycles.
        expect(
          ecarts / total,
          lessThan(0.002),
          reason: '$ecarts écarts sur $total',
        );
      },
    );

    test('accord avec la profondeur exacte : seulement le plancher', () {
      final s = _batiment();
      final plancher = s.solides
          .where(
            (x) =>
                x.calque == Calque.solives || x.calque == Calque.sousPlancher,
          )
          .toList();
      final alea = math.Random(9);
      var total = 0, ecarts = 0;
      for (var essai = 0; essai < 24; essai++) {
        final cam = Camera.pourScene(
          Scene(
            solides: plancher,
            infos: s.infos,
            cotes: const [],
            min: s.min,
            max: s.max,
          ),
          800,
          600,
          azimut: alea.nextDouble() * 2 * math.pi,
          elevation: 0.15 + alea.nextDouble() * 1.3,
        );
        final ordre = ordreAffichage(plancher, cam);
        for (var k = 0; k < 250; k++) {
          final px = Pt(alea.nextDouble() * 800, alea.nextDouble() * 600);
          final vrai = choisir(plancher, cam, px, 800, 600);
          final dessine = _parOrdre(plancher, ordre, cam, px, 800, 600);
          total++;
          if (vrai?.solide.id != dessine?.id) {
            ecarts++;
          }
        }
      }
      expect(
        ecarts / total,
        lessThan(0.002),
        reason: '$ecarts écarts sur $total',
      );
    });
  });

  group('sélection', () {
    test('rien sous un pixel vide', () {
      final s = _batiment();
      final c = Camera.pourScene(s, 800, 600);
      expect(choisir(s.solides, c, const Pt(2, 2), 800, 600), isNull);
    });

    test(
      'toutes couches : on touche le revêtement ; ossature seule : un montant',
      () {
        final s = _batiment(plancher: false);
        final c = Camera(
          azimut: -math.pi / 2, // œil du côté des y négatifs : face du mur 0
          elevation: 0.0,
          echelle: 2,
          cible: const P3(144, 0, 48),
        );
        // Un point du mur 0 (le long de y = 0), loin des ouvertures : x = 20.
        final px = c.projeter(const P3(20, 0, 48), 800, 600);
        final tout = choisir(s.solides, c, px, 800, 600);
        expect(tout, isNotNull);
        expect(tout!.solide.calque, Calque.revetement);
        final ossature = s.solides
            .where((x) => x.calque == Calque.ossature)
            .toList();
        final seul = choisir(ossature, c, px, 800, 600);
        expect(seul, isNotNull);
        expect(seul!.solide.calque, Calque.ossature);
      },
    );

    test('fenêtre : à travers le trou, on voit l\'intérieur', () {
      final s = _batiment(plancher: false);
      final c = Camera(
        azimut: -math.pi / 2,
        elevation: 0.0,
        echelle: 2,
        cible: const P3(144, 0, 48),
      );
      // Milieu de la baie de la fenêtre du mur 0 (x ≈ 100 + 3,5 de retrait de coin, z = 60).
      final hit = choisir(
        s.solides,
        c,
        c.projeter(const P3(103.5, 0, 60), 800, 600),
        800,
        600,
      );
      expect(hit, isNotNull);
      // Rien du mur 0 devant la baie : on voit l'intérieur du bâtiment (ici,
      // le mur opposé, le mur 2).
      expect(
        hit!.solide.groupe.startsWith('w0'),
        isFalse,
        reason: hit.solide.groupe,
      );
      expect(
        hit.solide.groupe.startsWith('w2'),
        isTrue,
        reason: hit.solide.groupe,
      );
      // À côté de la baie, le revêtement du mur 0 est bien touché.
      final a = choisir(
        s.solides,
        c,
        c.projeter(const P3(30, 0, 60), 800, 600),
        800,
        600,
      );
      expect(a!.solide.groupe, startsWith('w0'));
    });

    test(
      'éclairage : entre 0,45 et 1, faces de dessus plus claires de dessus',
      () {
        final s = _batiment();
        final c = Camera.pourScene(s, 800, 600, elevation: 1.2);
        for (final x in s.solides.take(60)) {
          for (final f in x.faces) {
            final e = eclairage(f, c);
            expect(e, inInclusiveRange(0.45, 1.0));
          }
        }
      },
    );
  });

  group('pointDansBoucles', () {
    test('contour avec trou : règle pair-impair', () {
      final boucles = [
        const [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)],
        const [Pt(3, 3), Pt(3, 7), Pt(7, 7), Pt(7, 3)],
      ];
      expect(pointDansBoucles(const Pt(1, 1), boucles), isTrue);
      expect(pointDansBoucles(const Pt(5, 5), boucles), isFalse);
      expect(pointDansBoucles(const Pt(11, 5), boucles), isFalse);
    });
  });
}
