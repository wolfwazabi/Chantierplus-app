import 'dart:math' as math;

/// Géométrie 2D du calcul de charpente. Unités : POUCES ; angles : degrés
/// (aux frontières de l'API) ou radians (en interne, suffixe « Rad »).

const double epsilon = 1e-9;

class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);
  double dot(Pt o) => x * o.x + y * o.y;
  double cross(Pt o) => x * o.y - y * o.x;
  double get longueur => math.sqrt(x * x + y * y);

  Pt get unitaire {
    final l = longueur;
    return l < epsilon ? const Pt(0, 0) : Pt(x / l, y / l);
  }

  /// Rotation de [a] radians (sens anti-horaire).
  Pt pivote(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    return Pt(x * c - y * s, x * s + y * c);
  }

  double distanceA(Pt o) => (this - o).longueur;

  @override
  bool operator ==(Object other) =>
      other is Pt && (x - other.x).abs() < 1e-7 && (y - other.y).abs() < 1e-7;

  @override
  int get hashCode => Object.hash((x * 1e5).round(), (y * 1e5).round());

  @override
  String toString() => 'Pt(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Boîte englobante.
class Boite {
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  const Boite(this.xMin, this.yMin, this.xMax, this.yMax);
  double get largeur => xMax - xMin;
  double get hauteur => yMax - yMin;
}

/// Une extrémité de corde : position et arête (indice du côté) traversée.
class Corde {
  final double debut;
  final double fin;
  final int areteDebut;
  final int areteFin;
  const Corde(this.debut, this.fin, this.areteDebut, this.areteFin);
  double get longueur => fin - debut;
}

/// Polygone simple (côtés qui ne se croisent pas), orienté anti-horaire.
class Polygone {
  final List<Pt> sommets;

  Polygone._(this.sommets);

  /// Au moins 3 sommets distincts, aire non nulle. Une orientation horaire
  /// est inversée. Lance [FormeInvalide] sinon (forme croisée comprise).
  factory Polygone(List<Pt> points) {
    if (points.length < 3) {
      throw const FormeInvalide('Il faut au moins 3 sommets.');
    }
    if (points.length > 24) {
      throw const FormeInvalide('24 sommets au maximum.');
    }
    for (final p in points) {
      if (!p.x.isFinite || !p.y.isFinite) {
        throw const FormeInvalide('Coordonnée invalide.');
      }
    }
    // Sommet répété à la fin : retiré.
    final pts = [...points];
    if (pts.length > 3 && pts.first == pts.last) {
      pts.removeLast();
    }
    for (var i = 0; i < pts.length; i++) {
      if (pts[i] == pts[(i + 1) % pts.length]) {
        throw const FormeInvalide('Deux sommets consécutifs sont identiques.');
      }
    }
    final aire = _aireSignee(pts);
    if (aire.abs() < 1e-6) {
      throw const FormeInvalide('La forme n\'a pas de surface.');
    }
    final p = Polygone._(aire > 0 ? pts : pts.reversed.toList());
    if (!p.estSimple) {
      throw const FormeInvalide(
        'Les côtés se croisent : vérifiez les mesures et les angles.',
      );
    }
    return p;
  }

  static Polygone rectangle(double longueur, double largeur) => Polygone([
    const Pt(0, 0),
    Pt(longueur, 0),
    Pt(longueur, largeur),
    Pt(0, largeur),
  ]);

  int get nombre => sommets.length;

  Pt sommet(int i) => sommets[i % nombre];

  /// Côté i : du sommet i au sommet i+1.
  double longueurCote(int i) => sommet(i).distanceA(sommet(i + 1));

  List<double> get longueursCotes => [
    for (var i = 0; i < nombre; i++) longueurCote(i),
  ];

  double get perimetre => longueursCotes.fold(0.0, (a, b) => a + b);

  double get aire => _aireSignee(sommets);

  /// Angle intérieur (degrés) au sommet i, entre 0 et 360 (rentrant > 180).
  double angleInterieurDeg(int i) {
    final prec = sommet(i - 1);
    final cur = sommet(i);
    final suiv = sommet(i + 1);
    final din = (cur - prec).unitaire;
    final dout = (suiv - cur).unitaire;
    final virage = math.atan2(din.cross(dout), din.dot(dout)); // > 0 : à gauche
    var interieur = 180 - virage * 180 / math.pi;
    if (interieur >= 360) interieur -= 360;
    if (interieur <= 0) interieur += 360;
    return interieur;
  }

  List<double> get anglesInterieursDeg => [
    for (var i = 0; i < nombre; i++) angleInterieurDeg(i),
  ];

  /// Normale unitaire vers l'INTÉRIEUR du côté i.
  Pt normaleInterieure(int i) {
    final d = (sommet(i + 1) - sommet(i)).unitaire;
    return Pt(-d.y, d.x); // polygone anti-horaire : l'intérieur est à gauche
  }

  Boite get boite {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final p in sommets) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    return Boite(x0, y0, x1, y1);
  }

  bool get estConvexe {
    for (var i = 0; i < nombre; i++) {
      if (angleInterieurDeg(i) > 180 + 1e-7) return false;
    }
    return true;
  }

  bool get estRectangle {
    if (nombre != 4) return false;
    for (var i = 0; i < 4; i++) {
      if ((angleInterieurDeg(i) - 90).abs() > 1e-6) return false;
    }
    return true;
  }

  /// Aucun couple de côtés non adjacents ne se croise ; les côtés adjacents
  /// ne se replient pas l'un sur l'autre.
  bool get estSimple {
    final n = nombre;
    // Côtés adjacents : refus s'ils se replient l'un sur l'autre (angle 0°/360°).
    for (var i = 0; i < n; i++) {
      final a = sommet(i - 1), b = sommet(i), c = sommet(i + 1);
      if ((a - b).cross(c - b).abs() < 1e-9 && (a - b).dot(c - b) > 0) {
        return false;
      }
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (j == i + 1 || (i == 0 && j == n - 1)) {
          continue;
        }
        if (segmentsSeCroisent(
          sommet(i),
          sommet(i + 1),
          sommet(j),
          sommet(j + 1),
        )) {
          return false;
        }
      }
    }
    return true;
  }

  /// Polygone tourné de [angleRad] (autour de l'origine).
  Polygone pivote(double angleRad) =>
      Polygone._([for (final p in sommets) p.pivote(angleRad)]);

  /// Cordes du polygone le long d'une droite HORIZONTALE (y = [c]) ou
  /// VERTICALE (x = [c]). Règle pair/impair ; un sommet exactement sur la
  /// droite est traité sans double compte. Chaque extrémité mémorise le côté
  /// traversé. Si [union], on fusionne ce qui se voit juste au-dessus et
  /// juste en dessous de la droite (une droite posée sur un côté intérieur).
  List<Corde> cordes({
    required bool horizontale,
    required double c,
    bool union = true,
  }) {
    List<Corde> balayer(double valeur) {
      final croisements = <(double, int)>[];
      final n = nombre;
      for (var i = 0; i < n; i++) {
        final p = sommet(i), q = sommet(i + 1);
        final pa = horizontale ? p.y : p.x;
        final qa = horizontale ? q.y : q.x;
        if ((pa <= valeur && valeur < qa) || (qa <= valeur && valeur < pa)) {
          final t = (valeur - pa) / (qa - pa);
          final autre = horizontale
              ? p.x + t * (q.x - p.x)
              : p.y + t * (q.y - p.y);
          croisements.add((autre, i));
        }
      }
      croisements.sort((a, b) => a.$1.compareTo(b.$1));
      final res = <Corde>[];
      for (var k = 0; k + 1 < croisements.length; k += 2) {
        res.add(
          Corde(
            croisements[k].$1,
            croisements[k + 1].$1,
            croisements[k].$2,
            croisements[k + 1].$2,
          ),
        );
      }
      return res;
    }

    const e = 1e-7;
    final dessus = balayer(c + e);
    if (!union) return dessus;
    final dessous = balayer(c - e);
    return _fusionnerCordes([...dessus, ...dessous]);
  }

  /// Aire de l'intersection avec un rectangle (Sutherland-Hodgman : le
  /// rectangle est convexe, le polygone peut être concave).
  double aireDansRectangle(double x0, double y0, double x1, double y1) {
    var pts = [...sommets];
    pts = _couper(pts, (p) => p.x - x0);
    pts = _couper(pts, (p) => x1 - p.x);
    pts = _couper(pts, (p) => p.y - y0);
    pts = _couper(pts, (p) => y1 - p.y);
    return pts.length < 3 ? 0 : _aireSignee(pts).abs();
  }

  static List<Pt> _couper(List<Pt> pts, double Function(Pt) dist) {
    if (pts.isEmpty) return pts;
    final sortie = <Pt>[];
    for (var i = 0; i < pts.length; i++) {
      final cur = pts[i], prev = pts[(i + pts.length - 1) % pts.length];
      final dc = dist(cur), dp = dist(prev);
      if (dc >= 0) {
        if (dp < 0) sortie.add(_croise(prev, cur, dp, dc));
        sortie.add(cur);
      } else if (dp >= 0) {
        sortie.add(_croise(prev, cur, dp, dc));
      }
    }
    return sortie;
  }

  static Pt _croise(Pt a, Pt b, double da, double db) {
    final t = da / (da - db);
    return Pt(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
  }

  /// Construit un polygone à partir de côtés et d'angles INTÉRIEURS, en
  /// partant de l'origine, premier côté vers la droite :
  /// côté 1, angle 1, côté 2, angle 2, … côté k. Le dernier côté et les deux
  /// derniers angles sont déduits pour fermer la forme (k côtés + 1).
  /// `cotes.length` = k ≥ 2, `angles.length` = k − 1.
  static Polygone deCotesEtAngles(List<double> cotes, List<double> anglesDeg) {
    if (cotes.length < 2) throw const FormeInvalide('Entrez au moins 2 côtés.');
    if (anglesDeg.length != cotes.length - 1) {
      throw const FormeInvalide(
        'Il faut un angle entre chaque paire de côtés.',
      );
    }
    for (final c in cotes) {
      if (!c.isFinite || c <= 0) {
        throw const FormeInvalide('Chaque côté doit être plus grand que 0.');
      }
    }
    for (final a in anglesDeg) {
      if (!a.isFinite || a <= 0 || a >= 360) {
        throw const FormeInvalide('Chaque angle doit être entre 0° et 360°.');
      }
    }
    final pts = <Pt>[const Pt(0, 0)];
    var direction = 0.0;
    for (var i = 0; i < cotes.length; i++) {
      final d = Pt(math.cos(direction), math.sin(direction));
      pts.add(pts.last + d * cotes[i]);
      if (i < anglesDeg.length) {
        direction += (180 - anglesDeg[i]) * math.pi / 180;
      }
    }
    final aire = _aireSignee(pts);
    if (aire <= 0) {
      throw const FormeInvalide(
        'Ces côtés et angles ne forment pas une surface fermée (forme inversée ou ouverte).',
      );
    }
    return Polygone(pts);
  }

  /// Polygone de côtés et angles « réels » (après fermeture), pour affichage.
  List<(double cote, double angleSuivantDeg)> get descriptif => [
    for (var i = 0; i < nombre; i++)
      (longueurCote(i), angleInterieurDeg(i + 1)),
  ];
}

/// Garde la partie de [poly] où a·x + b·y ≤ c (Sutherland–Hodgman, un seul
/// demi-plan). Un polygone concave donne un contour unique, qui peut longer le
/// bord du demi-plan quand le résultat est en plusieurs morceaux.
List<Pt> coupeDemiPlan(List<Pt> poly, double a, double b, double c) {
  if (poly.isEmpty) {
    return poly;
  }
  double f(Pt p) => a * p.x + b * p.y - c;
  final out = <Pt>[];
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i], q = poly[(i + 1) % poly.length];
    final fp = f(p), fq = f(q);
    final dedans = fp <= 1e-9, dedansQ = fq <= 1e-9;
    if (dedans) {
      out.add(p);
    }
    if (dedans != dedansQ) {
      final t = fp / (fp - fq);
      out.add(Pt(p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t));
    }
  }
  return out;
}

/// Polygone ∩ rectangle [x0, x1] × [y0, y1].
List<Pt> polygoneDansRectangle(
  List<Pt> poly,
  double x0,
  double x1,
  double y0,
  double y1,
) {
  var p = poly;
  p = coupeDemiPlan(p, -1, 0, -x0);
  p = coupeDemiPlan(p, 1, 0, x1);
  p = coupeDemiPlan(p, 0, -1, -y0);
  p = coupeDemiPlan(p, 0, 1, y1);
  // Points consécutifs confondus retirés.
  final nets = <Pt>[];
  for (final q in p) {
    if (nets.isEmpty || nets.last != q) {
      nets.add(q);
    }
  }
  while (nets.length > 1 && nets.first == nets.last) {
    nets.removeLast();
  }
  return nets;
}

class FormeInvalide implements Exception {
  final String message;
  const FormeInvalide(this.message);
  @override
  String toString() => message;
}

double _aireSignee(List<Pt> pts) {
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i], q = pts[(i + 1) % pts.length];
    s += p.x * q.y - q.x * p.y;
  }
  return s / 2;
}

/// Intersection franche de deux segments (hors extrémités communes).
bool segmentsSeCroisent(Pt a, Pt b, Pt c, Pt d) {
  double o(Pt p, Pt q, Pt r) => (q - p).cross(r - p);
  final o1 = o(a, b, c), o2 = o(a, b, d), o3 = o(c, d, a), o4 = o(c, d, b);
  const e = 1e-9;
  if (((o1 > e && o2 < -e) || (o1 < -e && o2 > e)) &&
      ((o3 > e && o4 < -e) || (o3 < -e && o4 > e))) {
    return true;
  }
  // Cas colinéaires ou sommet posé sur un autre côté (hors extrémités communes).
  bool surSegment(Pt p, Pt q, Pt r) =>
      o(p, q, r).abs() < e &&
      math.min(p.x, q.x) - e <= r.x &&
      r.x <= math.max(p.x, q.x) + e &&
      math.min(p.y, q.y) - e <= r.y &&
      r.y <= math.max(p.y, q.y) + e;
  bool partage(Pt p, Pt q) => p == q;
  if (surSegment(a, b, c) && !partage(c, a) && !partage(c, b)) return true;
  if (surSegment(a, b, d) && !partage(d, a) && !partage(d, b)) return true;
  if (surSegment(c, d, a) && !partage(a, c) && !partage(a, d)) return true;
  if (surSegment(c, d, b) && !partage(b, c) && !partage(b, d)) return true;
  return false;
}

List<Corde> _fusionnerCordes(List<Corde> cordes) {
  if (cordes.length < 2) return [...cordes];
  final tri = [...cordes]..sort((a, b) => a.debut.compareTo(b.debut));
  final res = <Corde>[];
  var cur = tri.first;
  for (var i = 1; i < tri.length; i++) {
    final n = tri[i];
    if (n.debut <= cur.fin + 1e-6) {
      cur = Corde(
        cur.debut,
        math.max(cur.fin, n.fin),
        cur.areteDebut,
        n.fin > cur.fin ? n.areteFin : cur.areteFin,
      );
    } else {
      res.add(cur);
      cur = n;
    }
  }
  res.add(cur);
  return res;
}
