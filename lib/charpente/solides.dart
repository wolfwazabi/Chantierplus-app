import 'dart:math' as math;

import 'geometrie.dart';

/// Solides de la vue 3D : des plaques et des prismes décrits par leurs faces
/// (boucles de points 3D et normale sortante), plus l'empreinte convexe en plan
/// qui sert à ordonner l'affichage. Unités : POUCES ; x et y dans le plan du
/// bâtiment, z vers le haut.

class P3 {
  final double x, y, z;
  const P3(this.x, this.y, this.z);

  P3 operator +(P3 o) => P3(x + o.x, y + o.y, z + o.z);
  P3 operator -(P3 o) => P3(x - o.x, y - o.y, z - o.z);
  P3 operator *(double k) => P3(x * k, y * k, z * k);
  double dot(P3 o) => x * o.x + y * o.y + z * o.z;
  P3 cross(P3 o) => P3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get longueur => math.sqrt(x * x + y * y + z * z);
  P3 get unitaire {
    final l = longueur;
    return l < 1e-12 ? const P3(0, 0, 0) : P3(x / l, y / l, z / l);
  }

  @override
  String toString() =>
      'P3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// Couches de la vue : le plancher (solives, puis sous-plancher) et les murs
/// (ossature, feuilles, membrane, fourrures, revêtement).
enum Calque {
  solives,
  sousPlancher,
  ossature,
  panneaux,
  membrane,
  fourrures,
  revetement,
}

/// Matière, pour la couleur.
enum Matiere {
  bois,
  rive,
  linteau,
  sousPlancher,
  osb,
  isolant,
  membrane,
  fourrure,
  revetement,
}

class Face {
  /// Contour extérieur et trous éventuels ; remplissage pair-impair.
  final List<List<P3>> boucles;

  /// Normale unitaire sortante.
  final P3 normale;

  /// Face de chant (épaisseur) plutôt que grande face.
  final bool laterale;
  const Face(this.boucles, this.normale, {this.laterale = false});

  P3 get point => boucles.first.first;
}

class Solide {
  final int id;

  /// Pièce cliquable : plusieurs solides peuvent partager le même groupe.
  final String groupe;
  final Calque calque;
  final Matiere matiere;

  /// Empreinte convexe en plan (anti-horaire) et hauteurs : ordre d'affichage.
  final List<Pt> coque;
  final double z0, z1;
  final List<Face> faces;

  const Solide({
    required this.id,
    required this.groupe,
    required this.calque,
    required this.matiere,
    required this.coque,
    required this.z0,
    required this.z1,
    required this.faces,
  });

  P3 get centre {
    var sx = 0.0, sy = 0.0;
    for (final p in coque) {
      sx += p.x;
      sy += p.y;
    }
    return P3(sx / coque.length, sy / coque.length, (z0 + z1) / 2);
  }
}

// =============================================================================
// Géométrie 2D utilitaire
// =============================================================================

double aireSignee(List<Pt> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    a += p[i].cross(p[(i + 1) % p.length]);
  }
  return a / 2;
}

/// Enveloppe convexe (anti-horaire), chaîne monotone.
List<Pt> enveloppeConvexe(List<Pt> points) {
  final p = [...points]
    ..sort((a, b) {
      final c = a.x.compareTo(b.x);
      return c != 0 ? c : a.y.compareTo(b.y);
    });
  final uniques = <Pt>[];
  for (final q in p) {
    if (uniques.isEmpty ||
        (uniques.last.x - q.x).abs() > 1e-9 ||
        (uniques.last.y - q.y).abs() > 1e-9) {
      uniques.add(q);
    }
  }
  if (uniques.length < 3) {
    return uniques;
  }
  double croix(Pt o, Pt a, Pt b) => (a - o).cross(b - o);
  final bas = <Pt>[];
  for (final q in uniques) {
    while (bas.length >= 2 &&
        croix(bas[bas.length - 2], bas.last, q) <= 1e-12) {
      bas.removeLast();
    }
    bas.add(q);
  }
  final haut = <Pt>[];
  for (final q in uniques.reversed) {
    while (haut.length >= 2 &&
        croix(haut[haut.length - 2], haut.last, q) <= 1e-12) {
      haut.removeLast();
    }
    haut.add(q);
  }
  bas.removeLast();
  haut.removeLast();
  return [...bas, ...haut];
}

typedef Rect4 = (double, double, double, double); // x0, x1, z0, z1

/// Contour d'un rectangle auquel on retire des trous rectangulaires : une
/// boucle extérieure (anti-horaire) puis les trous (horaires), en coordonnées
/// (x, z). Un trou qui touche le bord crée une encoche ; un trou qui traverse
/// le rectangle le sépare en plusieurs boucles.
List<List<Pt>> contourRectangleMoinsTrous(
  double x0,
  double x1,
  double z0,
  double z1,
  List<Rect4> trous,
) {
  const tol = 1e-7;
  List<double> uniques(Iterable<double> v) {
    final s = [...v]..sort();
    final out = <double>[];
    for (final e in s) {
      if (out.isEmpty || e - out.last > tol) {
        out.add(e);
      }
    }
    return out;
  }

  final coupes = <Rect4>[
    for (final h in trous)
      (
        math.max(x0, h.$1),
        math.min(x1, h.$2),
        math.max(z0, h.$3),
        math.min(z1, h.$4),
      ),
  ].where((h) => h.$2 - h.$1 > tol && h.$4 - h.$3 > tol).toList();

  double accroche(double v, List<double> grille) {
    for (final g in grille) {
      if ((g - v).abs() <= tol) {
        return g;
      }
    }
    return v;
  }

  final xs = uniques([
    x0,
    x1,
    for (final h in coupes) ...[h.$1, h.$2],
  ]);
  final zs = uniques([
    z0,
    z1,
    for (final h in coupes) ...[h.$3, h.$4],
  ]);
  final nx = xs.length - 1, nz = zs.length - 1;
  if (nx < 1 || nz < 1) {
    return const [];
  }
  final plein = List.generate(nx, (_) => List.filled(nz, false));
  for (var i = 0; i < nx; i++) {
    for (var j = 0; j < nz; j++) {
      final cx = (xs[i] + xs[i + 1]) / 2, cz = (zs[j] + zs[j + 1]) / 2;
      plein[i][j] = !coupes.any(
        (h) => cx > h.$1 && cx < h.$2 && cz > h.$3 && cz < h.$4,
      );
    }
  }
  bool occupe(int i, int j) =>
      i >= 0 && i < nx && j >= 0 && j < nz && plein[i][j];

  // Arêtes dirigées, matière à gauche.
  final sortantes = <(int, int), List<(int, int)>>{};
  void arete((int, int) a, (int, int) b) =>
      sortantes.putIfAbsent(a, () => []).add(b);
  for (var i = 0; i < nx; i++) {
    for (var j = 0; j < nz; j++) {
      if (!plein[i][j]) {
        continue;
      }
      if (!occupe(i, j - 1)) {
        arete((i, j), (i + 1, j));
      }
      if (!occupe(i + 1, j)) {
        arete((i + 1, j), (i + 1, j + 1));
      }
      if (!occupe(i, j + 1)) {
        arete((i + 1, j + 1), (i, j + 1));
      }
      if (!occupe(i - 1, j)) {
        arete((i, j + 1), (i, j));
      }
    }
  }

  final boucles = <List<Pt>>[];
  while (sortantes.isNotEmpty) {
    final depart = sortantes.keys.first;
    final suite = <(int, int)>[depart];
    var courant = depart;
    var precedent = depart;
    var garde = 0;
    while (garde++ < 100000) {
      final options = sortantes[courant];
      if (options == null || options.isEmpty) {
        break;
      }
      // Au carrefour, on tourne à gauche en priorité.
      (int, int) choix = options.first;
      if (options.length > 1) {
        final dirIn = (courant.$1 - precedent.$1, courant.$2 - precedent.$2);
        var meilleur = -4.0;
        for (final o in options) {
          final dirOut = (o.$1 - courant.$1, o.$2 - courant.$2);
          final croix = dirIn.$1 * dirOut.$2 - dirIn.$2 * dirOut.$1;
          final point = dirIn.$1 * dirOut.$1 + dirIn.$2 * dirOut.$2;
          final score = croix > 0 ? 2.0 : (point > 0 ? 1.0 : 0.0);
          if (score > meilleur) {
            meilleur = score;
            choix = o;
          }
        }
      }
      options.remove(choix);
      if (options.isEmpty) {
        sortantes.remove(courant);
      }
      precedent = courant;
      courant = choix;
      if (courant == depart) {
        break;
      }
      suite.add(courant);
    }
    if (suite.length >= 3) {
      // Sommets alignés fusionnés.
      final pts = [for (final (a, b) in suite) Pt(xs[a], zs[b])];
      final nets = <Pt>[];
      for (var i = 0; i < pts.length; i++) {
        final p = pts[(i - 1 + pts.length) % pts.length];
        final q = pts[i];
        final r = pts[(i + 1) % pts.length];
        if ((q - p).cross(r - q).abs() > 1e-9) {
          nets.add(q);
        }
      }
      if (nets.length >= 3) {
        boucles.add(nets);
      }
    }
  }
  // Boucles extérieures (aire > 0) d'abord.
  boucles.sort((a, b) => aireSignee(b).compareTo(aireSignee(a)));
  // Fermeture à la grille d'origine : accroche exacte aux bords du rectangle.
  return [
    for (final b in boucles)
      [
        for (final p in b) Pt(accroche(p.x, [x0, x1]), accroche(p.y, [z0, z1])),
      ],
  ];
}

// =============================================================================
// Fabrication des solides
// =============================================================================

Face _faceHorizontale(List<List<Pt>> boucles, double z, double nz) => Face([
  for (final b in boucles) [for (final p in b) P3(p.x, p.y, z)],
], P3(0, 0, nz));

/// Prisme vertical : [boucles] en plan (anti-horaire, trous horaires) entre
/// [z0] et [z1]. [coque] : empreinte convexe pour l'ordre d'affichage (par
/// défaut, l'enveloppe des boucles).
Solide extrusionHorizontale({
  required int id,
  required String groupe,
  required Calque calque,
  required Matiere matiere,
  required List<List<Pt>> boucles,
  required double z0,
  required double z1,
  List<Pt>? coque,
}) {
  final faces = <Face>[
    _faceHorizontale(boucles, z1, 1),
    _faceHorizontale(boucles, z0, -1),
  ];
  for (final b in boucles) {
    for (var i = 0; i < b.length; i++) {
      final p = b[i], q = b[(i + 1) % b.length];
      final d = q - p;
      final l = d.longueur;
      if (l < 1e-9) {
        continue;
      }
      // Arête parcourue dans les deux sens (pont d'un découpage) : pas de chant.
      final jumelle = List.generate(
        b.length,
        (k) => k,
      ).any((k) => b[k] == q && b[(k + 1) % b.length] == p);
      if (jumelle) {
        continue;
      }
      faces.add(
        Face(
          [
            [
              P3(p.x, p.y, z0),
              P3(q.x, q.y, z0),
              P3(q.x, q.y, z1),
              P3(p.x, p.y, z1),
            ],
          ],
          P3(d.y / l, -d.x / l, 0),
          laterale: true,
        ),
      );
    }
  }
  return Solide(
    id: id,
    groupe: groupe,
    calque: calque,
    matiere: matiere,
    coque: coque ?? enveloppeConvexe([for (final b in boucles) ...b]),
    z0: z0,
    z1: z1,
    faces: faces,
  );
}

/// Repère d'un mur : x le long du mur, y de l'intérieur (0) vers l'extérieur
/// (profondeur [d] = face extérieure de l'ossature), z vers le haut.
class RepereMur {
  final Pt origine;
  final Pt u;
  final double d;

  /// Coins en onglet (coupes d'angle) : abscisse du sommet et cot(angle/2), ou
  /// null pour un bout d'équerre.
  final double xSommetDebut;
  final double? cotDebut;
  final double xSommetFin;
  final double? cotFin;

  const RepereMur({
    required this.origine,
    required this.u,
    required this.d,
    this.xSommetDebut = 0,
    this.cotDebut,
    this.xSommetFin = 0,
    this.cotFin,
  });

  /// Normale sortante (à droite du sens de marche, le contour étant
  /// anti-horaire).
  Pt get n => Pt(u.y, -u.x);

  Pt plan(double x, double y) => origine + u * x + n * (y - d);

  P3 point(double x, double y, double z) {
    final p = plan(x, y);
    return P3(p.x, p.y, z);
  }

  /// Abscisse x ramenée dans les limites de l'onglet, à la profondeur y.
  double serre(double x, double y) {
    var r = x;
    if (cotDebut != null) {
      r = math.max(r, xSommetDebut + cotDebut! * (d - y));
    }
    if (cotFin != null) {
      r = math.min(r, xSommetFin - cotFin! * (d - y));
    }
    return r;
  }
}

/// Plaque dans le plan d'un mur : [boucles] en (x, z) vues de l'extérieur
/// (anti-horaire), épaisseur de [y0] à [y1].
Solide plaqueMur({
  required int id,
  required String groupe,
  required Calque calque,
  required Matiere matiere,
  required RepereMur repere,
  required List<List<Pt>> boucles,
  required double y0,
  required double y1,
}) {
  List<List<P3>> sur(double y) => [
    for (final b in boucles)
      [for (final p in b) repere.point(repere.serre(p.x, y), y, p.y)],
  ];
  final avant = sur(y1);
  final arriere = sur(y0);
  // Plaque écrasée par un onglet : rien à dessiner.
  double largeur(List<List<P3>> l) {
    final plan = [
      for (final b in l)
        for (final p in b) Pt(p.x, p.y),
    ];
    var m = 0.0;
    for (final p in plan) {
      for (final q in plan) {
        m = math.max(m, p.distanceA(q));
      }
    }
    return m;
  }

  if (largeur(avant) < 1e-6 && largeur(arriere) < 1e-6) {
    throw const _SolideVide();
  }
  final n = repere.n;
  final nAvant = P3(n.x, n.y, 0);
  final faces = <Face>[Face(avant, nAvant), Face(arriere, P3(-n.x, -n.y, 0))];
  for (var k = 0; k < avant.length; k++) {
    final a = avant[k], b = arriere[k];
    for (var i = 0; i < a.length; i++) {
      final a0 = a[i], a1 = a[(i + 1) % a.length];
      final b0 = b[i], b1 = b[(i + 1) % b.length];
      if ((a1 - a0).longueur < 1e-9 && (b1 - b0).longueur < 1e-9) {
        continue;
      }
      // Normale approchée : (a1 - a0) x nAvant ; exacte : normale du quadrilatère.
      final approchee = (a1 - a0).cross(nAvant);
      var vraie = (a1 - a0).cross(b0 - a0);
      if (vraie.longueur < 1e-9) {
        vraie = (b1 - b0).cross(b0 - a0);
      }
      if (vraie.longueur < 1e-9) {
        continue;
      }
      if (vraie.dot(approchee) < 0) {
        vraie = vraie * -1;
      }
      faces.add(
        Face(
          [
            [b0, b1, a1, a0],
          ],
          vraie.unitaire,
          laterale: true,
        ),
      );
    }
  }
  final plan = [
    for (final l in [avant, arriere])
      for (final b in l)
        for (final p in b) Pt(p.x, p.y),
  ];
  var zMin = double.infinity, zMax = -double.infinity;
  for (final b in boucles) {
    for (final p in b) {
      zMin = math.min(zMin, p.y);
      zMax = math.max(zMax, p.y);
    }
  }
  return Solide(
    id: id,
    groupe: groupe,
    calque: calque,
    matiere: matiere,
    coque: enveloppeConvexe(plan),
    z0: zMin,
    z1: zMax,
    faces: faces,
  );
}

class _SolideVide implements Exception {
  const _SolideVide();
}

/// Comme [plaqueMur], mais renvoie null quand la plaque est écrasée.
Solide? plaqueMurOuNull({
  required int id,
  required String groupe,
  required Calque calque,
  required Matiere matiere,
  required RepereMur repere,
  required List<List<Pt>> boucles,
  required double y0,
  required double y1,
}) {
  if (boucles.isEmpty) {
    return null;
  }
  try {
    return plaqueMur(
      id: id,
      groupe: groupe,
      calque: calque,
      matiere: matiere,
      repere: repere,
      boucles: boucles,
      y0: y0,
      y1: y1,
    );
  } on _SolideVide {
    return null;
  }
}

// =============================================================================
// Scène
// =============================================================================

class InfoPiece {
  final String titre;
  final List<String> lignes;
  const InfoPiece(this.titre, this.lignes);
}

/// Une cote affichée : segment 3D et texte.
class Cote {
  final P3 a, b;
  final String texte;
  final Calque calque;
  const Cote(this.a, this.b, this.texte, this.calque);
}

class Scene {
  final List<Solide> solides;
  final Map<String, InfoPiece> infos;
  final List<Cote> cotes;
  final P3 min;
  final P3 max;

  const Scene({
    required this.solides,
    required this.infos,
    required this.cotes,
    required this.min,
    required this.max,
  });

  static const vide = Scene(
    solides: [],
    infos: {},
    cotes: [],
    min: P3(0, 0, 0),
    max: P3(0, 0, 0),
  );

  bool get estVide => solides.isEmpty;
  P3 get centre => (min + max) * 0.5;
  double get rayon => (max - min).longueur / 2;

  /// Nombre de solides par couche.
  Map<Calque, int> get parCalque {
    final m = <Calque, int>{};
    for (final s in solides) {
      m[s.calque] = (m[s.calque] ?? 0) + 1;
    }
    return m;
  }
}
