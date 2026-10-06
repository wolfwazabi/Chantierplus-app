import 'dart:math' as math;

import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:flutter_test/flutter_test.dart';

// -----------------------------------------------------------------------------
// Outils de vérification INDÉPENDANTS du moteur (géométrie refaite ici).
// -----------------------------------------------------------------------------

/// Distance du point [p] à la droite (a, b).
double _distanceDroite(Pt p, Pt a, Pt b) =>
    ((b - a).cross(p - a)).abs() / (b - a).longueur;

/// Aire d'un polygone (formule du lacet).
double _aire(List<Pt> pts) {
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    s += a.cross(b);
  }
  return s.abs() / 2;
}

double _mm(double po) => po * 25.4;
double _po(double mm) => mm / 25.4;

/// Escalier dont la contremarche vaut exactement [rMm] (n imposé).
SpecEscalier _specR(
  double rMm,
  int n, {
  double giron = 10,
  double largeur = 36,
  UsageEscalier usage = UsageEscalier.prive,
  double nez = 0.75,
}) => SpecEscalier(
  hauteurTotale: _po(rMm) * n,
  nombreContremarches: n,
  giron: giron,
  largeur: largeur,
  usage: usage,
  nez: nez,
);

Verification _v(ResultatEscalier r, String id) =>
    r.verifications.firstWhere((v) => v.id == id);

void main() {
  group('cas calculé à la main : contremarche 7 1/2 po, giron 10 po (triangle 3-4-5)', () {
    // 7,5² + 10² = 12,5² : cos = 0,8 ; sin = 0,6 ; tout est exact à la main.
    final r = calculerEscalier(
      const SpecEscalier(hauteurTotale: 105, nombreContremarches: 14, giron: 10),
    );

    test('contremarches, marches, course', () {
      expect(r.nombreContremarches, 14);
      expect(r.nombreMarches, 13);
      expect(r.contremarche, closeTo(7.5, 1e-12));
      expect(r.giron, 10);
      expect(r.course, closeTo(130, 1e-12));
      expect(r.profondeurMarche, closeTo(10.75, 1e-12));
    });

    test('pente : 36,87° (tan = 0,75), diagonale 12,5 po', () {
      expect(r.diagonale, closeTo(12.5, 1e-12));
      expect(math.tan(degEnRad(r.angle)), closeTo(0.75, 1e-12));
      expect(r.angle, closeTo(36.8698976, 1e-6));
      expect(r.anglePlomb + r.angleNiveau, closeTo(90, 1e-12));
    });

    test('longueur entre pointes : 13 × 12,5 = 162,5 po', () {
      expect(r.longueurEntrePointes, closeTo(162.5, 1e-9));
    });

    test('gorge : 11,25 − 7,5 × 0,8 = 5,25 po', () {
      expect(r.gorge, closeTo(5.25, 1e-12));
    });

    test('coupes : départ 6 po, pointe du haut 103,5 po', () {
      expect(r.hauteurDepart, closeTo(6, 1e-12)); // 7,5 − 1,5
      expect(r.hauteurPointeHaute, closeTo(103.5, 1e-12)); // 105 − 1,5
      // Pied : (11,25 − 6 × 0,8) ÷ 0,6 = 10,75 po. Tête : 11,25 ÷ 0,8 = 14 1/16 po.
      expect(r.coupePied, closeTo(10.75, 1e-12));
      expect(r.coupeTete, closeTo(14.0625, 1e-12));
    });

    test('longueur de planche : 130 × 0,8 + 103,5 × 0,6 = 166,1 po → 14 pi', () {
      expect(r.longueurLimon, closeTo(166.1, 1e-9));
      expect(r.longueurCommerciale, 168);
    });

    test('4 limons à 11 1/2 po (largeur 36 po, entraxe max 16 po)', () {
      // (36 − 1,5) ÷ 16 = 2,16 → 3 espaces → 4 limons ; 34,5 ÷ 3 = 11,5.
      expect(r.nombreLimons, 4);
      expect(r.espacementReel, closeTo(11.5, 1e-12));
    });

    test('profil : sommets connus', () {
      final p = r.profil;
      expect(p.first, const Pt(0, 0));
      expect(p[1], const Pt(0, 6)); // pointe 0
      expect(p[2], const Pt(10, 6)); // siège 1 (fin)
      expect(p[3], const Pt(10, 13.5)); // pointe 1
      expect(p[4], const Pt(20, 13.5));
      expect(p[5], const Pt(20, 21));
      // 2 + 2 × 13 sommets d'escalier, puis tête et dessous.
      expect(p.length, 2 + 2 * 13 + 2);
      expect(p[p.length - 3], const Pt(130, 103.5)); // dernière pointe
      expect(p[p.length - 2], const Pt(130, 89.4375)); // bas de la coupe de tête
      expect(p.last, const Pt(10.75, 0)); // fin de la coupe de niveau
    });

    test('table de traçage', () {
      expect(r.table.length, 13);
      expect(r.table.first.marche, 1);
      expect(r.table.first.hauteurDessus, closeTo(7.5, 1e-12));
      expect(r.table.first.hauteurSiege, closeTo(6, 1e-12));
      expect(r.table.first.course, closeTo(10, 1e-12));
      expect(r.table.last.hauteurDessus, closeTo(97.5, 1e-12));
      expect(r.table.last.hauteurSiege, closeTo(96, 1e-12));
      expect(r.table.last.course, closeTo(130, 1e-12));
    });

    test('code : contremarche 190,5 mm, giron 254 mm → giron 1 mm sous le minimum', () {
      // 10 po = 254 mm < 255 mm : refusé, par 1 mm.
      expect(_v(r, 'contremarche').niveau, Niveau.ok);
      expect(_v(r, 'giron').niveau, Niveau.erreur);
      expect(r.conforme, isFalse);
    });
  });

  group('cas calculé à la main : plancher de 9 pi, giron 10 1/4 po', () {
    final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));

    test('15 contremarches de 7,2 po (108 ÷ 15), 14 marches', () {
      expect(r.nombreContremarches, 15);
      expect(r.contremarche, closeTo(7.2, 1e-12));
      expect(r.nombreMarches, 14);
      expect(r.course, closeTo(143.5, 1e-12));
    });

    test('longueur entre pointes et gorge, refaites à la main', () {
      // d = √(7,2² + 10,25²) = √(51,84 + 105,0625) = √156,9025 = 12,52607…
      final d = math.sqrt(7.2 * 7.2 + 10.25 * 10.25);
      expect(d, closeTo(12.52607, 1e-4));
      expect(r.diagonale, closeTo(d, 1e-12));
      expect(r.longueurEntrePointes, closeTo(14 * d, 1e-9));
      // gorge = 11,25 − 7,2 × 10,25 ÷ d
      expect(r.gorge, closeTo(11.25 - 7.2 * 10.25 / d, 1e-9));
      expect(r.gorge, closeTo(5.358, 1e-3));
    });

    test('conforme au Code (privé) ; pas d\'avertissement de confort', () {
      // 2 × 182,88 + 260,35 = 626 mm : confortable.
      expect(r.conforme, isTrue);
      expect(r.avertissements, isEmpty);
    });
  });

  group('choix du nombre de contremarches', () {
    test('la contremarche la plus proche de 7 1/4 po parmi celles que le Code permet', () {
      expect(calculerEscalier(const SpecEscalier(hauteurTotale: 108)).nombreContremarches, 15);
      expect(calculerEscalier(const SpecEscalier(hauteurTotale: 96)).nombreContremarches, 13);
      expect(calculerEscalier(const SpecEscalier(hauteurTotale: 120)).nombreContremarches, 17);
    });

    test('à égalité, la plus petite contremarche (7 1/2 ou 7 po : 15 contremarches)', () {
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 105));
      expect(r.nombreContremarches, 15);
      expect(r.contremarche, closeTo(7, 1e-12));
    });

    test('jamais une contremarche au-dessus de 200 mm quand une autre est possible', () {
      for (var h = 30.0; h <= 140; h += 0.25) {
        final r = calculerEscalier(SpecEscalier(hauteurTotale: h));
        if (h >= 4 * 125 / 25.4 && h <= 100 * 200 / 25.4) {
          // Si une solution conforme existe pour R, c'est elle qui est choisie.
          final existe = [for (var n = 2; n <= 40; n++) h / n]
              .any((v) => _mm(v) >= 125 - 0.05 && _mm(v) <= 200 + 0.05);
          if (existe) {
            expect(_v(r, 'contremarche').niveau, Niveau.ok, reason: 'H = $h po');
          }
        }
      }
    });

    test('course imposée : un nombre dont le giron respecte aussi le Code', () {
      // 108 po avec 135 po de course : 15 contremarches donneraient un giron de
      // 9,64 po (245 mm, trop court) ; 14 donnent 10,38 po (264 mm).
      final r = calculerEscalier(
        const SpecEscalier(
          hauteurTotale: 108,
          mode: ModeCourse.courseDisponible,
          courseDisponible: 135,
        ),
      );
      expect(r.nombreContremarches, 14);
      expect(r.giron, closeTo(135 / 13, 1e-12));
      expect(r.course, closeTo(135, 1e-9));
      expect(_v(r, 'giron').niveau, Niveau.ok);
    });

    test('course trop courte pour toute solution : calculé quand même, giron signalé', () {
      final r = calculerEscalier(
        SpecEscalier(
          hauteurTotale: _po(2600),
          mode: ModeCourse.courseDisponible,
          courseDisponible: _po(2800),
        ),
      );
      expect(r.nombreContremarches, 14);
      expect(r.giron, closeTo(_po(2800) / 13, 1e-12));
      expect(_v(r, 'giron').niveau, Niveau.erreur);
      expect(r.conforme, isFalse);
      expect(r.variantes, isEmpty);
    });

    test('autres choix : seuls les nombres conformes, autour du choix', () {
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.5));
      expect(r.nombreContremarches, 15);
      // 12 et 13 : contremarche trop haute ; 14, 16, 17, 18 : conformes.
      expect(r.variantes.map((v) => v.nombreContremarches), [14, 16, 17, 18]);
      for (final v in r.variantes) {
        expect(v.contremarche, closeTo(108 / v.nombreContremarches, 1e-12));
        expect(v.giron, 10.5);
        expect(v.course, closeTo((v.nombreContremarches - 1) * 10.5, 1e-9));
      }
    });

    test('un giron hors Code : aucun autre choix n\'est « conforme »', () {
      // 10 po = 254 mm, 1 mm sous le minimum : aucune variante ne l\'est non plus.
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10));
      expect(r.conforme, isFalse);
      expect(r.variantes, isEmpty);
    });

    test('le giron par défaut respecte le Code', () {
      expect(poucesEnMm(const SpecEscalier(hauteurTotale: 108).giron), greaterThanOrEqualTo(255));
    });

    test('un nombre imposé est respecté', () {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, nombreContremarches: 16),
      );
      expect(r.nombreContremarches, 16);
      expect(r.contremarche, closeTo(6.75, 1e-12));
    });
  });

  group('limites du Code, au millimètre', () {
    test('contremarche privée : 125 à 200 mm', () {
      expect(_v(calculerEscalier(_specR(200, 14)), 'contremarche').niveau, Niveau.ok);
      expect(_v(calculerEscalier(_specR(125, 14)), 'contremarche').niveau, Niveau.ok);
      expect(_v(calculerEscalier(_specR(200.5, 14)), 'contremarche').niveau, Niveau.erreur);
      expect(_v(calculerEscalier(_specR(124.5, 14)), 'contremarche').niveau, Niveau.erreur);
      // 7 7/8 po = 200,025 mm : c'est la limite de 200 mm en pouces.
      expect(
        _v(
          calculerEscalier(const SpecEscalier(hauteurTotale: 7.875 * 14, nombreContremarches: 14)),
          'contremarche',
        ).niveau,
        Niveau.ok,
      );
    });

    test('contremarche commune : 125 à 180 mm', () {
      SpecEscalier s(double mm) => _specR(mm, 14, usage: UsageEscalier.commun, giron: 11.5, largeur: 40);
      expect(_v(calculerEscalier(s(180)), 'contremarche').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(181)), 'contremarche').niveau, Niveau.erreur);
    });

    test('giron privé : 255 à 355 mm', () {
      SpecEscalier s(double mm) => SpecEscalier(
        hauteurTotale: 100,
        nombreContremarches: 14,
        giron: _po(mm),
      );
      expect(_v(calculerEscalier(s(255)), 'giron').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(354)), 'giron').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(355)), 'giron').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(254)), 'giron').niveau, Niveau.erreur);
      expect(_v(calculerEscalier(s(356)), 'giron').niveau, Niveau.erreur);
    });

    test('giron commun : au moins 280 mm, sans maximum', () {
      SpecEscalier s(double mm) => SpecEscalier(
        hauteurTotale: 100,
        nombreContremarches: 16,
        giron: _po(mm),
        usage: UsageEscalier.commun,
        largeur: 40,
      );
      expect(_v(calculerEscalier(s(280)), 'giron').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(400)), 'giron').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(279)), 'giron').niveau, Niveau.erreur);
    });

    test('nez de marche : 25 mm au plus', () {
      SpecEscalier s(double mm) => SpecEscalier(
        hauteurTotale: 100,
        nombreContremarches: 14,
        giron: 10.5,
        nez: _po(mm),
      );
      expect(_v(calculerEscalier(s(25)), 'profondeur').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(26)), 'profondeur').niveau, Niveau.erreur);
      // 1 po = 25,4 mm : 0,4 mm de trop, signalé.
      expect(
        _v(
          calculerEscalier(
            const SpecEscalier(hauteurTotale: 100, nombreContremarches: 14, giron: 10.5, nez: 1),
          ),
          'profondeur',
        ).niveau,
        Niveau.erreur,
      );
    });

    test('largeur : 860 mm (privé), 900 mm (commun)', () {
      SpecEscalier s(double mm, UsageEscalier u) => SpecEscalier(
        hauteurTotale: 100,
        nombreContremarches: 16,
        giron: 11.5,
        largeur: _po(mm),
        usage: u,
      );
      expect(_v(calculerEscalier(s(860, UsageEscalier.prive)), 'largeur').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(859, UsageEscalier.prive)), 'largeur').niveau, Niveau.erreur);
      expect(_v(calculerEscalier(s(900, UsageEscalier.commun)), 'largeur').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(899, UsageEscalier.commun)), 'largeur').niveau, Niveau.erreur);
    });

    test('volée : 3,7 m au plus, sinon un palier est exigé', () {
      SpecEscalier s(double mm) => SpecEscalier(
        hauteurTotale: _po(mm),
        nombreContremarches: (mm / 190).round(),
        giron: 10.5,
      );
      expect(_v(calculerEscalier(s(3700)), 'volee').niveau, Niveau.ok);
      expect(_v(calculerEscalier(s(3710)), 'volee').niveau, Niveau.erreur);
    });

    test('confort (Blondel) : avertissement seulement, jamais une erreur', () {
      // 2 × 200 + 255 = 655 mm : au-dessus de 650.
      final r = calculerEscalier(
        SpecEscalier(hauteurTotale: _po(200) * 14, nombreContremarches: 14, giron: _po(255)),
      );
      expect(_v(r, 'blondel').niveau, Niveau.avertissement);
      expect(r.conforme, isTrue);
    });

    test('rappels : échappée toujours ; contremarches ouvertes seulement si ouvertes', () {
      final ouvertes = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));
      expect(_v(ouvertes, 'echappee').niveau, Niveau.info);
      expect(_v(ouvertes, 'planchers').niveau, Niveau.info);
      expect(_v(ouvertes, 'tete').message, contains('1 1/2"'));
      expect(ouvertes.verifications.any((v) => v.id == 'ouvertes'), isTrue);
      final fermees = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, giron: 10.25, contremarchesFermees: true),
      );
      expect(fermees.verifications.any((v) => v.id == 'ouvertes'), isFalse);
    });
  });

  group('gorge et planche', () {
    test('2×10 : gorge plus mince, refusée sous 3 1/2 po', () {
      // R = 8 po : 9,25 − 8 × 10 ÷ 12,806 = 3,0 po : trop mince.
      final r = calculerEscalier(
        const SpecEscalier(
          hauteurTotale: 112,
          nombreContremarches: 14,
          giron: 10,
          section: SectionLimon.s2x10,
        ),
      );
      expect(r.gorge, closeTo(9.25 - 8 * 10 / math.sqrt(164), 1e-9));
      expect(_v(r, 'gorge').niveau, Niveau.erreur);
    });

    test('2×12 : même escalier, gorge suffisante', () {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 112, nombreContremarches: 14, giron: 10),
      );
      expect(_v(r, 'gorge').niveau, Niveau.ok);
    });

    test('limon trop long pour le 20 pi : avertissement', () {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 140, nombreContremarches: 19, giron: 11),
      );
      expect(r.longueurLimon, greaterThan(240));
      expect(r.verifications.any((v) => v.id == 'longueur'), isTrue);
    });

    test('longueurs courantes : pieds pairs, 8 pi minimum', () {
      final petit = calculerEscalier(const SpecEscalier(hauteurTotale: 28, nombreContremarches: 4));
      expect(petit.longueurCommerciale, 96);
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));
      expect(r.longueurCommerciale % 24, 0);
      expect(r.longueurCommerciale, greaterThanOrEqualTo(r.longueurLimon));
      expect(r.longueurCommerciale - r.longueurLimon, lessThan(24));
    });

    test('nombre de limons selon la largeur et l\'entraxe', () {
      int nb(double largeur, double ent) => calculerEscalier(
        SpecEscalier(hauteurTotale: 108, giron: 10.25, largeur: largeur, espacementMax: ent),
      ).nombreLimons;
      expect(nb(36, 16), 4);
      expect(nb(36, 18), 3); // 34,5 ÷ 18 = 1,92 → 2 espaces
      expect(nb(36, 34.5), 2); // un seul espace de 34,5
      expect(nb(48, 16), 4); // 46,5 ÷ 16 = 2,9 → 3 espaces
      expect(nb(60, 16), 5); // 58,5 ÷ 16 = 3,66 → 4 espaces
      expect(nb(32, 16), 3); // 30,5 ÷ 16 = 1,9 → 2 espaces
    });
  });

  group('traçage arrondi', () {
    test('au 1/16 po : écart de volée sous 10 mm, voisines sous 5 mm', () {
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));
      expect(r.ecartVolee, lessThanOrEqualTo(2 / 16 + 1e-9));
      expect(r.ecartAdjacent, lessThanOrEqualTo(2 / 16 + 1e-9));
      expect(_v(r, 'uniformite').niveau, Niveau.ok);
    });

    test('l\'uniformité compte aussi les girons, pas seulement les contremarches', () {
      // 15 contremarches de 7 po (parfaitement régulières au pas de 1/2 po), mais un
      // giron de 10,1 po dont les positions arrondies donnent des girons de 10 et 10 1/2 po.
      final r = calculerEscalier(
        const SpecEscalier(
          hauteurTotale: 105,
          nombreContremarches: 15,
          giron: 10.1,
          precisionTrace: 0.5,
        ),
      );
      expect(r.ecartVolee, closeTo(0.5, 1e-12));
      expect(r.ecartAdjacent, closeTo(0.5, 1e-12));
      expect(_v(r, 'uniformite').niveau, Niveau.erreur);
    });

    test('un pas trop grossier est signalé', () {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, giron: 10.25, precisionTrace: 0.5),
      );
      expect(_v(r, 'uniformite').niveau, Niveau.erreur);
    });

    test('arrondi au pas, sans accumuler : chaque hauteur est arrondie seule', () {
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));
      // 7,2 po × 15 = 108 : la marche 14 est à 100,8 po, pas à 14 × 7 3/16.
      expect(r.arrondi(r.table.last.hauteurDessus), closeTo(100.8125, 1e-12));
      expect(arrondirAuPas(7.2, 1 / 16), closeTo(7.1875, 1e-12));
      expect(arrondirAuPas(7.2, 1 / 25.4), closeTo(183 / 25.4, 1e-12));
    });
  });

  group('contrôles géométriques indépendants (300 escaliers au hasard)', () {
    final hasard = math.Random(20261002);
    final cas = <SpecEscalier>[];
    while (cas.length < 300) {
      cas.add(
        SpecEscalier(
          hauteurTotale: 40 + hasard.nextDouble() * 100,
          giron: 9 + hasard.nextDouble() * 4,
          epaisseurMarche: [0.75, 1.0, 1.5][hasard.nextInt(3)],
          section: hasard.nextBool() ? SectionLimon.s2x12 : SectionLimon.s2x10,
          largeur: 30 + hasard.nextDouble() * 40,
          espacementMax: [12.0, 16.0][hasard.nextInt(2)],
        ),
      );
    }

    test('n × R = H ; la pente vaut R ÷ G ; dents régulières', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final n = r.nombreContremarches;
        expect(n * r.contremarche, closeTo(s.hauteurTotale, 1e-9));
        expect(math.tan(degEnRad(r.angle)), closeTo(r.contremarche / r.giron, 1e-9));
        final p = r.profil;
        // p[2k] = pointe k − 1 pour k ≥ 1, p[2k + 1]… : pointes en indices 1, 3, 5…
        for (var k = 1; k < n; k++) {
          final fond = p[2 * k];
          final pointe = p[2 * k + 1];
          final avant = p[2 * k - 1];
          expect(fond.x - avant.x, closeTo(r.giron, 1e-9), reason: 'siège $k : giron');
          expect(fond.y, closeTo(avant.y, 1e-9), reason: 'siège $k : de niveau');
          expect(pointe.y - fond.y, closeTo(r.contremarche, 1e-9), reason: 'contremarche $k');
          expect(pointe.x, closeTo(fond.x, 1e-9), reason: 'contremarche $k : d\'aplomb');
          // Le dessus de la marche (siège + épaisseur) est à k × R du plancher.
          expect(fond.y + s.epaisseurMarche, closeTo(k * r.contremarche, 1e-9));
        }
        // La dernière pointe + épaisseur = hauteur totale (le plancher du haut).
        expect(p[p.length - 3].y + s.epaisseurMarche, closeTo(s.hauteurTotale, 1e-9));
      }
    });

    test('pointes alignées ; dessous parallèle à la profondeur de la planche', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final n = r.nombreContremarches;
        final p = r.profil;
        final pointes = [for (var k = 0; k < n; k++) p[1 + 2 * k]];
        final finDessous = p.last;
        final basTete = p[p.length - 2];
        for (final q in pointes) {
          // Toutes sur la droite passant par les deux premières pointes.
          expect(_distanceDroite(q, pointes[0], pointes[1]), closeTo(0, 1e-8));
          // Et à la même distance (= profondeur de la planche) du dessous.
          expect(_distanceDroite(q, finDessous, basTete), closeTo(s.section.profondeur, 1e-8));
        }
        // Dessous parallèle au dessus.
        expect(
          (basTete - finDessous).unitaire.cross((pointes.last - pointes[0]).unitaire),
          closeTo(0, 1e-9),
        );
      }
    });

    test('gorge = distance réelle du fond d\'une entaille au dessous de la planche', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final p = r.profil;
        final finDessous = p.last;
        final basTete = p[p.length - 2];
        for (var k = 1; k < r.nombreContremarches; k++) {
          expect(
            _distanceDroite(p[2 * k], finDessous, basTete),
            closeTo(r.gorge, 1e-8),
            reason: 'fond de l\'entaille $k',
          );
        }
      }
    });

    test('aire du limon = aire de la bande − (n − 1) entailles de R × G ÷ 2', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final p = r.profil;
        final n = r.nombreContremarches;
        // Bande : pied, 1re pointe, dernière pointe, bas de la tête, fin du dessous.
        final bande = [p.first, p[1], p[p.length - 3], p[p.length - 2], p.last];
        final attendue = _aire(bande) - (n - 1) * r.contremarche * r.giron / 2;
        expect(_aire(p), closeTo(attendue, 1e-6));
      }
    });

    test('longueur de planche = étendue du profil tourné à plat', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        // On tourne le contour de −pente : la planche devient horizontale.
        final a = degEnRad(-r.angle);
        final xs = [for (final q in r.profil) q.pivote(a).x];
        final etendue = xs.reduce(math.max) - xs.reduce(math.min);
        expect(r.longueurLimon, closeTo(etendue, 1e-8));
        // Encadrement : entre les pointes extrêmes et la diagonale étage à étage.
        expect(r.longueurLimon, greaterThanOrEqualTo(r.longueurEntrePointes - 1e-9));
        final diagonaleTotale = math.sqrt(
          s.hauteurTotale * s.hauteurTotale + r.course * r.course,
        );
        expect(r.longueurLimon, lessThanOrEqualTo(diagonaleTotale + 1e-9));
        // Hauteur de la planche (perpendiculaire) = profondeur de la section.
        final ys = [for (final q in r.profil) q.pivote(a).y];
        final hauteur = ys.reduce(math.max) - ys.reduce(math.min);
        expect(hauteur, closeTo(s.section.profondeur, 1e-8));
      }
    });

    test('la planche couvre tout le contour : aucun sommet hors du rectangle', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final a = degEnRad(-r.angle);
        final pts = [for (final q in r.profil) q.pivote(a)];
        final xMin = pts.map((q) => q.x).reduce(math.min);
        final xMax = pts.map((q) => q.x).reduce(math.max);
        expect(xMax - xMin, lessThanOrEqualTo(r.longueurCommerciale + 1e-9));
      }
    });

    test('pied au niveau du plancher : aucun point sous le plancher', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        for (final q in r.profil) {
          expect(q.y, greaterThanOrEqualTo(-1e-9));
        }
        expect(r.profil.first, const Pt(0, 0));
        expect(r.profil.last.y, closeTo(0, 1e-12));
      }
    });

    test('tableau de traçage : dessus de la marche k à k × R, siège t plus bas', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        expect(r.table.length, r.nombreMarches);
        for (final l in r.table) {
          expect(l.hauteurDessus, closeTo(l.marche * r.contremarche, 1e-9));
          expect(l.hauteurDessus - l.hauteurSiege, closeTo(s.epaisseurMarche, 1e-12));
          expect(l.course, closeTo(l.marche * r.giron, 1e-9));
        }
      }
    });

    test('verdicts cohérents avec les mesures (recalculés ici en millimètres)', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        final rMm = _mm(r.contremarche);
        final gMm = _mm(r.giron);
        final rOk = rMm >= 125 - 0.05 && rMm <= 200 + 0.05;
        final gOk = gMm >= 255 - 0.05 && gMm <= 355 + 0.05;
        expect(_v(r, 'contremarche').niveau == Niveau.ok, rOk);
        expect(_v(r, 'giron').niveau == Niveau.ok, gOk);
        expect(_v(r, 'largeur').niveau == Niveau.ok, _mm(s.largeur) >= 860 - 0.05);
        expect(_v(r, 'volee').niveau == Niveau.ok, _mm(s.hauteurTotale) <= 3700 + 0.05);
      }
    });

    test('le nombre de limons ne dépasse jamais l\'entraxe maximal', () {
      for (final s in cas) {
        final r = calculerEscalier(s);
        expect(r.espacementReel, lessThanOrEqualTo(s.espacementMax + 1e-9));
        expect(
          (r.nombreLimons - 1) * r.espacementReel,
          closeTo(s.largeur - s.section.epaisseur, 1e-9),
        );
        // Un limon de moins serait trop espacé.
        if (r.nombreLimons > 2) {
          expect(
            (s.largeur - s.section.epaisseur) / (r.nombreLimons - 2),
            greaterThan(s.espacementMax),
          );
        }
      }
    });
  });

  group('entrées invalides', () {
    test('valeurs absurdes refusées avec un message', () {
      void refuse(SpecEscalier s) =>
          expect(() => calculerEscalier(s), throwsA(isA<EscalierInvalide>()));
      refuse(const SpecEscalier(hauteurTotale: 0));
      refuse(const SpecEscalier(hauteurTotale: -10));
      refuse(const SpecEscalier(hauteurTotale: double.nan));
      refuse(const SpecEscalier(hauteurTotale: double.infinity));
      refuse(const SpecEscalier(hauteurTotale: 108, giron: 0));
      refuse(const SpecEscalier(hauteurTotale: 108, largeur: 0));
      refuse(const SpecEscalier(hauteurTotale: 108, nombreContremarches: 1));
      refuse(const SpecEscalier(hauteurTotale: 108, nombreContremarches: 0));
      refuse(const SpecEscalier(hauteurTotale: 108, epaisseurMarche: 0));
      refuse(const SpecEscalier(hauteurTotale: 108, nez: -1));
      refuse(const SpecEscalier(hauteurTotale: 108, precisionTrace: 0));
      refuse(const SpecEscalier(hauteurTotale: 108, espacementMax: 0));
    });

    test('marche plus épaisse que la contremarche : refusée', () {
      expect(
        () => calculerEscalier(
          const SpecEscalier(hauteurTotale: 20, nombreContremarches: 2, epaisseurMarche: 10),
        ),
        throwsA(isA<EscalierInvalide>()),
      );
    });

    test('hauteur hors du Code : calculée quand même, erreur signalée', () {
      // 8 po de haut : 2 contremarches de 4 po (< 125 mm).
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 8));
      expect(r.nombreContremarches, 2);
      expect(_v(r, 'contremarche').niveau, Niveau.erreur);
    });

    test('même résultat deux fois de suite (calcul déterministe)', () {
      const s = SpecEscalier(hauteurTotale: 108, giron: 10.25);
      final a = calculerEscalier(s);
      final b = calculerEscalier(s);
      expect(a.longueurLimon, b.longueurLimon);
      expect(a.profil, b.profil);
      expect(a.verifications.map((v) => v.message), b.verifications.map((v) => v.message));
    });

    test('messages en métrique quand on le demande', () {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, giron: 10.25),
        metrique: true,
      );
      expect(_v(r, 'contremarche').message, contains('mm'));
      final imperial = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 10.25));
      expect(_v(imperial, 'contremarche').message, contains('7 3/16"'));
    });
  });
}
