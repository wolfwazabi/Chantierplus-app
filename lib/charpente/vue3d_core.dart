import 'dart:math' as math;

import 'geometrie.dart';
import 'solides.dart';

/// Caméra orthographique (les cotes se lisent juste), ordre d'affichage « du
/// plus loin au plus proche » et sélection des pièces. Sans dépendance à
/// Flutter : testé sur des scènes complètes.

class Camera {
  /// Rotation autour de l'axe vertical et hauteur de l'œil (radians).
  final double azimut;
  final double elevation;

  /// Pixels par pouce.
  final double echelle;

  /// Point visé (centre de l'écran avant décalage).
  final P3 cible;

  /// Déplacement de l'image à l'écran, en pixels.
  final Pt decalage;

  const Camera({
    required this.azimut,
    required this.elevation,
    required this.echelle,
    required this.cible,
    this.decalage = const Pt(0, 0),
  });

  /// Direction de la cible vers l'œil (unitaire).
  P3 get oeil => P3(
    math.cos(elevation) * math.cos(azimut),
    math.cos(elevation) * math.sin(azimut),
    math.sin(elevation),
  );

  /// Axes de l'écran : droite et haut.
  P3 get droite => P3(-math.sin(azimut), math.cos(azimut), 0);
  P3 get haut => P3(
    -math.sin(elevation) * math.cos(azimut),
    -math.sin(elevation) * math.sin(azimut),
    math.cos(elevation),
  );

  Camera avec({
    double? azimut,
    double? elevation,
    double? echelle,
    P3? cible,
    Pt? decalage,
  }) => Camera(
    azimut: azimut ?? this.azimut,
    elevation: elevation ?? this.elevation,
    echelle: echelle ?? this.echelle,
    cible: cible ?? this.cible,
    decalage: decalage ?? this.decalage,
  );

  /// Position à l'écran d'un point 3D, l'écran faisant [largeur] × [hauteur].
  Pt projeter(P3 p, double largeur, double hauteur) {
    final d = p - cible;
    return Pt(
      largeur / 2 + decalage.x + d.dot(droite) * echelle,
      hauteur / 2 + decalage.y - d.dot(haut) * echelle,
    );
  }

  /// Distance signée vers l'œil : plus grand = plus proche.
  double profondeur(P3 p) => (p - cible).dot(oeil);

  /// Point de la cible (plan perpendiculaire à la vue) sous un pixel : origine
  /// du rayon qui va vers l'œil.
  P3 origineRayon(Pt pixel, double largeur, double hauteur) {
    final u = (pixel.x - largeur / 2 - decalage.x) / echelle;
    final v = -(pixel.y - hauteur / 2 - decalage.y) / echelle;
    return cible + droite * u + haut * v;
  }

  /// Vue de départ : 3/4 face, légèrement en plongée, scène entière à l'écran.
  static Camera pourScene(
    Scene scene,
    double largeur,
    double hauteur, {
    double azimut = -0.6,
    double elevation = 0.55,
    double marge = 24,
  }) {
    final base = Camera(
      azimut: azimut,
      elevation: elevation,
      echelle: 1,
      cible: scene.centre,
    );
    return base.ajustee(scene, largeur, hauteur, marge: marge);
  }

  /// Même angle, échelle et décalage qui cadrent la scène.
  Camera ajustee(
    Scene scene,
    double largeur,
    double hauteur, {
    double marge = 24,
  }) {
    if (scene.estVide) {
      return this;
    }
    final c = avec(echelle: 1, decalage: const Pt(0, 0), cible: scene.centre);
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final x in [scene.min.x, scene.max.x]) {
      for (final y in [scene.min.y, scene.max.y]) {
        for (final z in [scene.min.z, scene.max.z]) {
          final p = c.projeter(P3(x, y, z), 0, 0);
          x0 = math.min(x0, p.x);
          x1 = math.max(x1, p.x);
          y0 = math.min(y0, p.y);
          y1 = math.max(y1, p.y);
        }
      }
    }
    final largeurScene = math.max(x1 - x0, 1e-6);
    final hauteurScene = math.max(y1 - y0, 1e-6);
    // Écran minuscule ou caché : échelle minimale, jamais nulle ni négative.
    final e = math.max(
      1e-3,
      math.min(
        (largeur - 2 * marge) / largeurScene,
        (hauteur - 2 * marge) / hauteurScene,
      ),
    );
    // Centre de l'enveloppe projetée ramené au centre de l'écran.
    return c.avec(
      echelle: e,
      decalage: Pt(-(x0 + x1) / 2 * e, -(y0 + y1) / 2 * e),
    );
  }
}

// =============================================================================
// Ordre d'affichage
// =============================================================================

/// Enveloppe d'un solide à l'écran : boîte englobante (rejet rapide) et
/// polygone convexe (test exact de recouvrement).
class _Ecran {
  final double x0, y0, x1, y1;
  final List<Pt> hull;
  const _Ecran(this.x0, this.y0, this.x1, this.y1, this.hull);

  bool boiteChevauche(_Ecran o) =>
      x0 < o.x1 - 1e-9 &&
      o.x0 < x1 - 1e-9 &&
      y0 < o.y1 - 1e-9 &&
      o.y0 < y1 - 1e-9;

  /// Deux polygones convexes se recouvrent s'il n'existe aucun axe qui les
  /// sépare (un simple contact ne compte pas).
  bool chevauche(_Ecran o) {
    for (final poly in [hull, o.hull]) {
      if (poly.length < 3) {
        continue;
      }
      for (var i = 0; i < poly.length; i++) {
        final d = poly[(i + 1) % poly.length] - poly[i];
        final l = d.longueur;
        if (l < 1e-12) {
          continue;
        }
        final n = Pt(d.y / l, -d.x / l);
        var minA = double.infinity, maxA = -double.infinity;
        for (final p in hull) {
          final v = n.dot(p);
          minA = math.min(minA, v);
          maxA = math.max(maxA, v);
        }
        var minB = double.infinity, maxB = -double.infinity;
        for (final p in o.hull) {
          final v = n.dot(p);
          minB = math.min(minB, v);
          maxB = math.max(maxB, v);
        }
        if (maxA <= minB + 1e-6 || maxB <= minA + 1e-6) {
          return false;
        }
      }
    }
    return true;
  }
}

/// 1 : [a] est devant [b] (à dessiner après) ; -1 : [b] devant [a] ; 0 : aucun
/// plan séparateur utile (les deux solides ne se masquent pas, ou le plan est
/// vu de chant).
int _devant(Solide a, Solide b, P3 e) {
  const eps = 1e-6;
  // Plan horizontal : l'un est entièrement au-dessus de l'autre.
  if (e.z.abs() > 1e-9) {
    if (a.z0 >= b.z1 - eps) {
      return e.z > 0 ? 1 : -1;
    }
    if (b.z0 >= a.z1 - eps) {
      return e.z > 0 ? -1 : 1;
    }
  }
  // Plans verticaux : arêtes des empreintes.
  for (final poly in [a.coque, b.coque]) {
    for (var i = 0; i < poly.length; i++) {
      final d = poly[(i + 1) % poly.length] - poly[i];
      final l = d.longueur;
      if (l < 1e-9) {
        continue;
      }
      final n = Pt(d.y / l, -d.x / l);
      final ne = n.x * e.x + n.y * e.y;
      if (ne.abs() < 1e-9) {
        continue;
      }
      var minA = double.infinity, maxA = -double.infinity;
      for (final p in a.coque) {
        final v = n.dot(p);
        minA = math.min(minA, v);
        maxA = math.max(maxA, v);
      }
      var minB = double.infinity, maxB = -double.infinity;
      for (final p in b.coque) {
        final v = n.dot(p);
        minB = math.min(minB, v);
        maxB = math.max(maxB, v);
      }
      if (maxA <= minB + eps) {
        // B du côté de n : devant si n regarde vers l'œil.
        return ne > 0 ? -1 : 1;
      }
      if (maxB <= minA + eps) {
        return ne > 0 ? 1 : -1;
      }
    }
  }
  return 0;
}

/// Indices de [solides] du plus loin au plus proche de l'œil. L'ordre respecte
/// les plans séparateurs de chaque paire de solides qui se recouvrent à
/// l'écran ; un cycle éventuel est coupé par la profondeur du centre.
List<int> ordreAffichage(List<Solide> solides, Camera cam) {
  final n = solides.length;
  final e = cam.oeil;
  final boites = <_Ecran>[];
  final profondeurs = <double>[];
  for (final s in solides) {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    final points = <Pt>[];
    for (final p in s.coque) {
      for (final z in [s.z0, s.z1]) {
        final q = cam.projeter(P3(p.x, p.y, z), 0, 0);
        points.add(q);
        x0 = math.min(x0, q.x);
        x1 = math.max(x1, q.x);
        y0 = math.min(y0, q.y);
        y1 = math.max(y1, q.y);
      }
    }
    boites.add(_Ecran(x0, y0, x1, y1, enveloppeConvexe(points)));
    profondeurs.add(cam.profondeur(s.centre));
  }

  // avant[j] : solides à dessiner avant j.
  final avant = List.generate(n, (_) => <int>{});
  final apres = List.generate(n, (_) => <int>[]);
  // Balayage selon x : seules les paires qui se recouvrent en x sont testées.
  final tri = List.generate(n, (i) => i)
    ..sort((a, b) => boites[a].x0.compareTo(boites[b].x0));
  for (var ii = 0; ii < n; ii++) {
    final i = tri[ii];
    for (var jj = ii + 1; jj < n; jj++) {
      final j = tri[jj];
      if (boites[j].x0 >= boites[i].x1 - 1e-9) {
        break;
      }
      if (!boites[i].boiteChevauche(boites[j]) ||
          !boites[i].chevauche(boites[j])) {
        continue;
      }
      final r = _devant(solides[i], solides[j], e);
      if (r > 0) {
        if (avant[i].add(j)) {
          apres[j].add(i);
        }
      } else if (r < 0) {
        if (avant[j].add(i)) {
          apres[i].add(j);
        }
      }
    }
  }

  final restants = {for (var i = 0; i < n; i++) i};
  final reste = List.generate(n, (i) => avant[i].length);
  final sortie = <int>[];
  final disponibles = <int>[
    for (var i = 0; i < n; i++)
      if (reste[i] == 0) i,
  ];
  while (restants.isNotEmpty) {
    int choix;
    if (disponibles.isNotEmpty) {
      // Le plus loin d'abord.
      var m = 0;
      for (var k = 1; k < disponibles.length; k++) {
        if (profondeurs[disponibles[k]] < profondeurs[disponibles[m]]) {
          m = k;
        }
      }
      choix = disponibles.removeAt(m);
    } else {
      // Cycle : on coupe au plus loin.
      choix = restants.reduce(
        (a, b) => profondeurs[a] <= profondeurs[b] ? a : b,
      );
    }
    restants.remove(choix);
    sortie.add(choix);
    for (final j in apres[choix]) {
      if (!restants.contains(j)) {
        continue;
      }
      reste[j]--;
      if (reste[j] == 0) {
        disponibles.add(j);
      }
    }
  }
  return sortie;
}

// =============================================================================
// Sélection
// =============================================================================

/// Vrai si [p] est dans les boucles (règle pair-impair).
bool pointDansBoucles(Pt p, List<List<Pt>> boucles) {
  var dedans = false;
  for (final b in boucles) {
    for (var i = 0, j = b.length - 1; i < b.length; j = i++) {
      final a = b[i], c = b[j];
      if ((a.y > p.y) != (c.y > p.y)) {
        final x = (c.x - a.x) * (p.y - a.y) / (c.y - a.y) + a.x;
        if (p.x < x) {
          dedans = !dedans;
        }
      }
    }
  }
  return dedans;
}

class Impact {
  final Solide solide;
  final Face face;

  /// Distance vers l'œil : plus grand = plus proche.
  final double profondeur;
  const Impact(this.solide, this.face, this.profondeur);
}

/// Pièce visible sous le pixel [pixel] (profondeur exacte : la face la plus
/// proche de l'œil). [visibles] : indices des solides affichés.
Impact? choisir(
  List<Solide> solides,
  Camera cam,
  Pt pixel,
  double largeur,
  double hauteur,
) {
  final e = cam.oeil;
  final origine = cam.origineRayon(pixel, largeur, hauteur);
  Impact? meilleur;
  for (final s in solides) {
    for (final f in s.faces) {
      final ne = f.normale.dot(e);
      if (ne <= 1e-9) {
        continue; // face vue de dos ou de chant
      }
      final boucles = [
        for (final b in f.boucles)
          [for (final p in b) cam.projeter(p, largeur, hauteur)],
      ];
      if (!pointDansBoucles(pixel, boucles)) {
        continue;
      }
      // Profondeur du point de la face sous le pixel.
      final t = f.normale.dot(f.point - origine) / ne;
      final profondeur = (origine - cam.cible).dot(e) + t;
      if (meilleur == null || profondeur > meilleur.profondeur) {
        meilleur = Impact(s, f, profondeur);
      }
    }
  }
  return meilleur;
}

/// Éclairage d'une face (0,45 à 1) : lumière attachée à la caméra, venant de
/// l'œil, d'en haut et un peu de la gauche.
double eclairage(Face f, Camera cam) {
  final l = (cam.oeil * 0.6 + cam.haut * 0.55 - cam.droite * 0.35).unitaire;
  final d = math.max(0.0, f.normale.dot(l));
  return 0.45 + 0.55 * d;
}
