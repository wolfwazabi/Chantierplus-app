import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/panneaux.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/scene.dart';
import 'package:construction_app/charpente/solides.dart' show aireSignee;
import 'package:flutter_test/flutter_test.dart';

const _h = 97.125;

ResultatPlancher _plancher(
  Polygone forme, {
  int entremises = 0,
  bool riveDouble = false,
  bool bordureDouble = false,
  FormatPanneau panneau = panneau4x8,
  double? angle,
}) => calculerPlancher(
  SpecPlancher(
    forme: forme,
    rangeesEntremises: entremises,
    riveDouble: riveDouble,
    solivesDoublesAuxCotes: bordureDouble,
    panneau: panneau,
    angleSolivesDeg: angle,
  ),
);

/// Séparation par un axe (arêtes des deux polygones convexes) : les polygones
/// se chevauchent si aucun axe ne les sépare d'au moins [eps].
bool _planChevauche(List<Pt> a, List<Pt> b, double eps) {
  for (final poly in [a, b]) {
    for (var i = 0; i < poly.length; i++) {
      final e = poly[(i + 1) % poly.length] - poly[i];
      final n = Pt(e.y, -e.x).unitaire;
      if (n.longueur < 0.5) {
        continue;
      }
      double mn(List<Pt> p) => p.map(n.dot).reduce(math.min);
      double mx(List<Pt> p) => p.map(n.dot).reduce(math.max);
      if (mx(a) <= mn(b) + eps || mx(b) <= mn(a) + eps) {
        return false;
      }
    }
  }
  return true;
}

/// Triangles d'un polygone simple (découpage en oreilles).
List<List<Pt>> _triangles(List<Pt> poly) {
  final p = aireSignee(poly) >= 0 ? [...poly] : poly.reversed.toList();
  final out = <List<Pt>>[];
  var garde = 0;
  while (p.length > 3 && garde++ < 1000) {
    var coupe = false;
    for (var i = 0; i < p.length; i++) {
      final a = p[(i - 1 + p.length) % p.length],
          b = p[i],
          c = p[(i + 1) % p.length];
      if ((b - a).cross(c - b) <= 1e-9) {
        continue; // sommet rentrant ou aligné
      }
      final dedans = p.any((q) {
        if (q == a || q == b || q == c) {
          return false;
        }
        return (b - a).cross(q - a) > 1e-9 &&
            (c - b).cross(q - b) > 1e-9 &&
            (a - c).cross(q - c) > 1e-9;
      });
      if (!dedans) {
        out.add([a, b, c]);
        p.removeAt(i);
        coupe = true;
        break;
      }
    }
    if (!coupe) {
      break; // forme dégénérée : le reste est ignoré
    }
  }
  if (p.length == 3) {
    out.add(p);
  }
  return out;
}

/// Pièces convexes de l'empreinte d'un solide : son contour réel pour un
/// prisme horizontal (qui peut être concave), son enveloppe pour une plaque
/// de mur.
List<List<Pt>> _empreinte(Solide s) {
  final haut = s.faces.first;
  if (haut.normale.z > 0.5) {
    return [
      for (final b in haut.boucles.take(1))
        ..._triangles([for (final p in b) Pt(p.x, p.y)]),
    ];
  }
  return [s.coque];
}

List<String> _chevauchements(Scene s, {double eps = 0.02}) {
  final bad = <String>[];
  final empreintes = [for (final x in s.solides) _empreinte(x)];
  for (var i = 0; i < s.solides.length; i++) {
    for (var j = i + 1; j < s.solides.length; j++) {
      final a = s.solides[i], b = s.solides[j];
      if (math.min(a.z1, b.z1) - math.max(a.z0, b.z0) <= eps) {
        continue;
      }
      // Rejet rapide : enveloppes éloignées.
      if (!_planChevauche(a.coque, b.coque, eps)) {
        continue;
      }
      final touche = empreintes[i].any(
        (ta) => empreintes[j].any((tb) => _planChevauche(ta, tb, eps)),
      );
      if (touche) {
        bad.add(
          '${a.groupe} (${a.calque.name}) × ${b.groupe} (${b.calque.name})',
        );
      }
    }
  }
  return bad;
}

Scene _batiment(
  Polygone contour, {
  List<Ouverture> Function(int mur)? ouvertures,
  ParametresMurs params = const ParametresMurs(),
  bool plancher = true,
}) {
  final base = mursDuContour(contour, hauteur: _h);
  final specs = [
    for (var i = 0; i < base.length; i++)
      SpecMur(
        nom: base[i].nom,
        longueur: base[i].longueur,
        hauteur: base[i].hauteur,
        ouvertures: ouvertures?.call(i) ?? const [],
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
    plancher: plancher ? _plancher(contour, entremises: 1) : null,
    murs: calculerMurs(specs, params),
    contour: contour,
  );
}

const _fenetre = Ouverture(
  type: TypeOuverture.fenetre,
  largeurCadre: 36,
  hauteurCadre: 48,
  position: 80,
);
const _porte = Ouverture(
  type: TypeOuverture.porte,
  largeurCadre: 36,
  hauteurCadre: 80,
  position: 150,
);

/// Forme utilisable : ni tige ni pointe (angles de 15° à 345°, épaisseur
/// moyenne d'au moins 12 po) ni coin presque plat (172° à 188°) : à cet angle,
/// l'onglet des rives est quasi parallèle aux solives et la solive qui y
/// aboutit contourne le sommet, un détail sans intérêt pour l'affichage.
bool _formeRaisonnable(Polygone p) {
  for (var i = 0; i < p.nombre; i++) {
    final a = p.angleInterieurDeg(i);
    if (a < 15 || a > 345 || (a > 172 && a < 188)) {
      return false;
    }
  }
  return p.aire / p.perimetre >= 12;
}

void main() {
  group('plancher', () {
    test('rectangle 13 × 10 pi 6 po : solives, rives, feuilles, fiches', () {
      final r = _plancher(Polygone.rectangle(156, 126), entremises: 1);
      final s = construireScene(plancher: r);
      final cal = s.parCalque;
      expect(
        cal[Calque.solives],
        r.solives.length + r.rives.length + r.entremisesPoses.length,
      );
      expect(cal[Calque.sousPlancher], r.panneaux.poses.length);
      expect(cal.containsKey(Calque.ossature), isFalse);
      // Chaque solide a sa fiche.
      for (final x in s.solides) {
        expect(s.infos.containsKey(x.groupe), isTrue, reason: x.groupe);
      }
      // Dessus du sous-plancher à z = 0 ; dessous des solives à −(3/4 + 9 1/4).
      expect(s.max.z, closeTo(0, 1e-9));
      expect(s.min.z, closeTo(-10, 1e-9));
      expect(s.min.x, closeTo(0, 1e-6));
      expect(s.max.x, closeTo(156, 1e-6));
      expect(s.max.y, closeTo(126, 1e-6));
      expect(_chevauchements(s), isEmpty);
    });

    test('fiche d\'une feuille de sous-plancher : dimensions et position', () {
      final r = _plancher(Polygone.rectangle(156, 126));
      final s = construireScene(plancher: r);
      final fiches = [
        for (final e in s.infos.entries)
          if (e.key.startsWith('fs')) e.value,
      ];
      expect(fiches, hasLength(r.panneaux.poses.length));
      final f = fiches.first;
      expect(f.titre, startsWith('Feuille de sous-plancher n° '));
      expect(f.lignes.any((l) => l.startsWith('Pièce :')), isTrue);
      expect(f.lignes.any((l) => l.startsWith('Position :')), isTrue);
      // En système impérial, les dimensions sont en pieds et pouces.
      expect(
        f.lignes.firstWhere((l) => l.startsWith('Pièce :')),
        contains("'"),
      );
    });

    test('métrique : les fiches sont en mètres et millimètres', () {
      final r = _plancher(Polygone.rectangle(156, 126));
      final s = construireScene(plancher: r, metrique: true);
      final fiche = s.infos.entries
          .firstWhere((e) => e.key.startsWith('j'))
          .value;
      expect(
        fiche.lignes.firstWhere((l) => l.startsWith('Longueur')),
        contains('m'),
      );
      expect(fiche.lignes.join(), isNot(contains('"')));
    });

    test('rive doublée, solives de bordure doublées, entremises : sans chevauchement', () {
      final r = _plancher(
        Polygone.rectangle(240, 144),
        entremises: 2,
        riveDouble: true,
        bordureDouble: true,
      );
      final s = construireScene(plancher: r, sectionPlancher: section2x8);
      expect(_chevauchements(s), isEmpty);
      expect(
        s.infos.values.any((i) => i.titre == 'Solive de rive (doublée)'),
        isTrue,
      );
      expect(
        s.infos.values.any((i) => i.titre == 'Solive de bordure (doublée)'),
        isTrue,
      );
    });

    test('feuilles 4 × 9 et 4 × 10 : sans chevauchement', () {
      for (final f in [panneau4x9, panneau4x10, panneauIsobraceR4]) {
        final s = construireScene(
          plancher: _plancher(Polygone.rectangle(300, 200), panneau: f),
        );
        expect(_chevauchements(s), isEmpty, reason: f.nom);
      }
    });

    test('formes irrégulières : aucun chevauchement de pièces', () {
      final formes = <String, Polygone>{
        'L': Polygone(const [
          Pt(0, 0),
          Pt(240, 0),
          Pt(240, 120),
          Pt(120, 120),
          Pt(120, 240),
          Pt(0, 240),
        ]),
        'U': Polygone(const [
          Pt(0, 0),
          Pt(240, 0),
          Pt(240, 200),
          Pt(160, 200),
          Pt(160, 80),
          Pt(80, 80),
          Pt(80, 200),
          Pt(0, 200),
        ]),
        'triangle': Polygone(const [Pt(0, 0), Pt(144, 0), Pt(48, 96)]),
        'pentagone': Polygone.deCotesEtAngles(
          [180, 120, 90, 140],
          [90, 110, 120],
        ),
        'trapèze': Polygone(const [
          Pt(0, 0),
          Pt(200, 0),
          Pt(160, 120),
          Pt(40, 120),
        ]),
      };
      for (final e in formes.entries) {
        final r = _plancher(e.value, entremises: 1);
        final s = construireScene(plancher: r);
        expect(_chevauchements(s), isEmpty, reason: e.key);
        expect(s.parCalque[Calque.solives], greaterThan(0), reason: e.key);
        expect(s.parCalque[Calque.sousPlancher], greaterThan(0), reason: e.key);
      }
    });

    test('forme tournée à un angle quelconque : même nombre de pièces', () {
      final base = Polygone.rectangle(200, 140);
      final tournee = Polygone([
        for (final p in base.sommets) p.pivote(37 * math.pi / 180),
      ]);
      final a = construireScene(plancher: _plancher(base, entremises: 1));
      final b = construireScene(plancher: _plancher(tournee, entremises: 1));
      expect(b.solides.length, a.solides.length);
      expect(_chevauchements(b), isEmpty);
    });

    test('cotes : un côté par segment du contour', () {
      final s = construireScene(
        plancher: _plancher(Polygone.rectangle(156, 126)),
      );
      expect(s.cotes, hasLength(4));
      expect(s.cotes.map((c) => c.texte).toSet(), {"13'", "10' 6\""});
    });
  });

  group('murs isolés', () {
    test(
      'mur de 16 pi : ossature, feuilles, membrane, fourrures, revêtement',
      () {
        final r = calculerMurs(const [
          SpecMur(longueur: 192, hauteur: _h),
        ], const ParametresMurs());
        final s = construireScene(murs: r);
        final cal = s.parCalque;
        expect(cal[Calque.ossature], r.murs.single.membres.length);
        expect(cal[Calque.panneaux], 4);
        expect(cal[Calque.membrane], 1);
        expect(cal[Calque.fourrures], r.murs.single.fourrures.length);
        expect(cal[Calque.revetement], 1);
        expect(_chevauchements(s), isEmpty);
        // Du début à la fin du mur, de 0 à la hauteur.
        expect(s.min.z, closeTo(0, 1e-9));
        expect(s.max.z, closeTo(_h, 1e-9));
        for (final x in s.solides) {
          expect(s.infos.containsKey(x.groupe), isTrue);
        }
      },
    );

    test('fenêtre et porte : trous dans les feuilles, la membrane et le revêtement', () {
      final r = calculerMurs(const [
        SpecMur(longueur: 240, hauteur: _h, ouvertures: [_fenetre, _porte]),
      ], const ParametresMurs());
      final s = construireScene(murs: r);
      expect(_chevauchements(s), isEmpty);
      final membrane = s.solides.firstWhere((x) => x.calque == Calque.membrane);
      // Contour extérieur + 2 trous = 3 boucles sur la grande face (la porte
      // touche le bas : encoche, donc 2 boucles seulement).
      final boucles = membrane.faces.first.boucles;
      expect(boucles.length, anyOf(2, 3));
      var aire = 0.0;
      for (final b in boucles) {
        var a = 0.0;
        for (var i = 0; i < b.length; i++) {
          final p = b[i], q = b[(i + 1) % b.length];
          // Projection sur le plan du mur (x, z) : le mur est le long de l'axe x.
          a += p.x * q.z - q.x * p.z;
        }
        aire += a / 2;
      }
      final attendu = 240 * _h - 37 * 49.5 - 37 * 81.5;
      expect(aire.abs(), closeTo(attendu, 1e-6));
    });

    test('plusieurs murs isolés : alignés côte à côte, sans chevauchement', () {
      final r = calculerMurs(const [
        SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
        SpecMur(longueur: 144, hauteur: _h),
        SpecMur(longueur: 100, hauteur: _h),
      ], const ParametresMurs());
      final s = construireScene(murs: r);
      expect(_chevauchements(s), isEmpty);
      expect(s.max.x - s.min.x, greaterThan(192 + 144 + 100));
    });

    test('fiches : montant, feuille avec découpe, fourrure', () {
      final r = calculerMurs(const [
        SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      ], const ParametresMurs());
      final s = construireScene(murs: r);
      final montant = s.infos.values.firstWhere((i) => i.titre == 'Montant');
      expect(montant.lignes.join('|'), contains("7' 8 5/8\""));
      expect(montant.lignes.join('|'), contains('précoupé'));
      final feuilles = s.infos.values.where(
        (i) => i.titre.startsWith('Feuille murale'),
      );
      expect(
        feuilles.any(
          (i) => i.lignes.any((l) => l.startsWith('Découpe d\'ouverture')),
        ),
        isTrue,
      );
      expect(
        s.infos.values.any((i) => i.titre == 'Fourrure verticale'),
        isTrue,
      );
      expect(s.infos.values.any((i) => i.titre == 'Linteau'), isTrue);
    });

    test('cotes : longueur, hauteur et baies', () {
      final r = calculerMurs(const [
        SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      ], const ParametresMurs());
      final s = construireScene(murs: r);
      final textes = s.cotes.map((c) => c.texte).toList();
      expect(textes, contains("16'"));
      expect(textes, contains("8' 1 1/8\""));
      expect(textes.any((t) => t.startsWith('Fenêtre : baie')), isTrue);
    });

    test('Isobrace : matière isolante et épaisseur de 1 5/16 po', () {
      final r = calculerMurs(const [
        SpecMur(longueur: 192, hauteur: _h),
      ], const ParametresMurs(panneau: panneauIsobraceR4));
      final s = construireScene(murs: r);
      final pan = s.solides.where((x) => x.calque == Calque.panneaux);
      expect(pan.every((x) => x.matiere == Matiere.isolant), isTrue);
      final largeur =
          pan.first.coque.map((p) => p.y).reduce(math.max) -
          pan.first.coque.map((p) => p.y).reduce(math.min);
      expect(largeur, closeTo(1.3125, 1e-9));
    });
  });

  group('bâtiment complet', () {
    test(
      'rectangle 24 × 20 pi, fenêtres et porte : aucune pièce ne se chevauche',
      () {
        final s = _batiment(
          Polygone.rectangle(288, 240),
          ouvertures: (i) => i == 0
              ? const [_fenetre, _porte]
              : (i == 1 ? const [_fenetre] : const []),
        );
        expect(_chevauchements(s), isEmpty);
        // Les murs sont posés sur le contour du plancher.
        expect(s.min.x, closeTo(-2, 1));
        expect(s.max.x, closeTo(288, 3));
        expect(s.max.z, closeTo(_h, 1e-9));
      },
    );

    test('forme en L (coin rentrant) : aucune pièce ne se chevauche', () {
      final s = _batiment(
        Polygone(const [
          Pt(0, 0),
          Pt(288, 0),
          Pt(288, 144),
          Pt(144, 144),
          Pt(144, 288),
          Pt(0, 288),
        ]),
        ouvertures: (i) => i == 0 ? const [_fenetre] : const [],
      );
      expect(_chevauchements(s), isEmpty);
    });

    test('triangle (coins en onglet) : aucune pièce ne se chevauche', () {
      final s = _batiment(
        Polygone(const [Pt(0, 0), Pt(240, 0), Pt(80, 160)]),
        ouvertures: (i) => i == 0 ? const [_fenetre] : const [],
      );
      expect(_chevauchements(s), isEmpty);
    });

    test('pentagone irrégulier : aucune pièce ne se chevauche', () {
      final s = _batiment(
        Polygone.deCotesEtAngles([240, 160, 110, 200], [90, 110, 120]),
      );
      expect(_chevauchements(s), isEmpty);
    });

    test('hexagone en onglets, Isobrace et murs 2×6 : aucune pièce ne se chevauche', () {
      final hex = Polygone([
        for (var k = 0; k < 6; k++)
          Pt(160 * math.cos(k * math.pi / 3), 160 * math.sin(k * math.pi / 3)),
      ]);
      final s = _batiment(
        hex,
        params: const ParametresMurs(
          section: section2x6,
          panneau: panneauIsobraceR4,
        ),
      );
      expect(_chevauchements(s), isEmpty);
    });

    test(
      'le revêtement enveloppe le plancher : les murs sont sur le contour',
      () {
        final contour = Polygone.rectangle(288, 240);
        final s = _batiment(contour);
        final rev = s.solides.where((x) => x.calque == Calque.revetement);
        expect(rev, hasLength(4));
        // Chaque revêtement est à l'extérieur du contour (côté sortant).
        for (final x in rev) {
          for (final p in x.coque) {
            final dedans =
                p.x > 1e-6 &&
                p.x < 288 - 1e-6 &&
                p.y > 1e-6 &&
                p.y < 240 - 1e-6;
            expect(dedans, isFalse);
          }
        }
      },
    );
  });

  group('formes aléatoires', () {
    test('plancher seul : aucune pièce ne se chevauche (150 formes)', () {
      final alea = math.Random(23);
      var essais = 0;
      while (essais < 150) {
        final n = 3 + alea.nextInt(4);
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
          continue;
        }
        if (!_formeRaisonnable(p)) {
          continue;
        }
        final r = _plancher(
          p,
          entremises: alea.nextInt(3),
          riveDouble: alea.nextBool(),
          bordureDouble: alea.nextBool(),
        );
        if (r.avertissements.any(
          (a) => a.contains('trop étroite par endroits'),
        )) {
          continue; // goulot plus étroit que les rives : calcul approximatif signalé
        }
        essais++;
        final bad = _chevauchements(construireScene(plancher: r));
        expect(bad, isEmpty, reason: 'forme $essais : $cotes $angles');
      }
    });

    test('bâtiment (plancher + murs en onglet) : aucune pièce ne se chevauche (100 formes)', () {
      final alea = math.Random(31);
      var essais = 0;
      while (essais < 100) {
        final n = 3 + alea.nextInt(3);
        final cotes = [
          for (var i = 0; i < n - 1; i++) 120 + alea.nextDouble() * 200,
        ];
        final angles = [
          for (var i = 0; i < n - 2; i++) 60 + alea.nextDouble() * 150,
        ];
        Polygone p;
        try {
          p = Polygone.deCotesEtAngles(cotes, angles);
        } on FormeInvalide {
          continue;
        }
        // Les côtés trop courts ne portent pas un mur avec ses retraits.
        if (!_formeRaisonnable(p) || p.longueursCotes.any((l) => l < 60)) {
          continue;
        }
        Scene s;
        try {
          s = _batiment(
            p,
            ouvertures: (i) => i % 2 == 0 ? const [_fenetre] : const [],
          );
        } on SpecInvalide {
          continue; // ouverture qui ne tient pas sur un mur court
        }
        essais++;
        final bad = _chevauchements(s);
        expect(bad, isEmpty, reason: 'forme $essais : $cotes $angles');
      }
    });
  });
}
