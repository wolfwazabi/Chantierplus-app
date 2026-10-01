// Optimisation des coupes : planches (1 dimension) et feuilles (2 dimensions).
// Unités : POUCES.

/// Épaisseur du trait de scie (1/8 po) retirée à chaque coupe.
const double traitDeScie = 0.125;

// =============================================================================
// Planches : coupe de pièces dans des longueurs commerciales
// =============================================================================

class PieceCoupe {
  final String id;
  final double longueur;

  /// Texte libre pour la liste de coupe (« solive », « montant », …).
  final String etiquette;
  const PieceCoupe(this.id, this.longueur, [this.etiquette = '']);
}

/// Une planche à commander et les pièces qu'on y coupe.
class PlancheCommandee {
  final double stock;
  final List<PieceCoupe> pieces;
  const PlancheCommandee(this.stock, this.pieces);

  double get utilise => pieces.fold(0.0, (a, p) => a + p.longueur);
  double get chute => stock - utilise - traitDeScie * (pieces.length - 1);
}

class ResultatDecoupe {
  final List<PlancheCommandee> planches;

  /// Pièces plus longues que la plus longue planche permise.
  final List<PieceCoupe> horsLimites;
  const ResultatDecoupe(this.planches, this.horsLimites);

  /// « 12 pi » → nombre de planches de cette longueur.
  Map<double, int> get parLongueur {
    final m = <double, int>{};
    for (final p in planches) {
      m[p.stock] = (m[p.stock] ?? 0) + 1;
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  double get longueurTotale => planches.fold(0.0, (a, p) => a + p.stock);
  double get longueurUtile => planches.fold(0.0, (a, p) => a + p.utilise);

  /// Part du bois acheté qui n'est pas dans une pièce (chutes + traits de scie).
  double get pertePourcent => longueurTotale <= 0
      ? 0
      : (longueurTotale - longueurUtile) / longueurTotale * 100;
}

/// Coupe [pieces] dans des planches de longueurs [stocks] (en pouces) en
/// minimisant la longueur totale achetée : placement « du plus long au plus
/// court » dans la meilleure planche déjà entamée, puis chaque planche est
/// ramenée à la plus courte longueur commerciale qui contient ses coupes.
///
/// [uneParPlanche] : pièces (déjà dans [pieces]) qui prennent chacune leur
/// propre planche, la plus courte qui les contient (les montants : on achète
/// des 8 pi, pas des 16 pi à couper en deux). Les chutes de ces planches
/// reçoivent les petites pièces.
ResultatDecoupe decouperPlanches(
  List<PieceCoupe> pieces,
  List<double> stocks, {
  double trait = traitDeScie,
  Set<String> uneParPlanche = const {},
}) {
  final longueurs = [...stocks.where((s) => s > 0)]..sort();
  if (longueurs.isEmpty) return ResultatDecoupe(const [], [...pieces]);
  final max = longueurs.last;
  const tol = 1e-6;

  final horsLimites = <PieceCoupe>[];
  final aPlacer = <PieceCoupe>[];
  for (final p in pieces) {
    if (p.longueur > max + tol) {
      horsLimites.add(p);
    } else if (p.longueur > tol) {
      aPlacer.add(p);
    }
  }
  aPlacer.sort((a, b) => b.longueur.compareTo(a.longueur));

  // Boîtes : une planche (capacité = longueur commerciale maximale permise) et
  // ses pièces ; besoin = somme des pièces + traits de scie.
  final boites = <(double, List<PieceCoupe>)>[];
  double besoin(List<PieceCoupe> b) =>
      b.fold(0.0, (a, p) => a + p.longueur) + trait * (b.length - 1);

  for (final p in aPlacer) {
    if (uneParPlanche.contains(p.id)) {
      final stock = longueurs.firstWhere(
        (s) => s + tol >= p.longueur,
        orElse: () => max,
      );
      boites.add((stock, [p]));
    }
  }
  for (final p in aPlacer) {
    if (uneParPlanche.contains(p.id)) {
      continue;
    }
    List<PieceCoupe>? meilleure;
    var restantMin = double.infinity;
    for (final (capacite, b) in boites) {
      final apres = besoin(b) + trait + p.longueur;
      if (apres <= capacite + tol) {
        final restant = capacite - apres;
        if (restant < restantMin) {
          restantMin = restant;
          meilleure = b;
        }
      }
    }
    if (meilleure != null) {
      meilleure.add(p);
    } else {
      boites.add((max, [p]));
    }
  }

  final planches = <PlancheCommandee>[];
  for (final (_, b) in boites) {
    final n = besoin(b);
    final stock = longueurs.firstWhere((s) => s + tol >= n, orElse: () => max);
    planches.add(PlancheCommandee(stock, b));
  }
  planches.sort((a, b) {
    final c = b.stock.compareTo(a.stock);
    return c != 0 ? c : b.utilise.compareTo(a.utilise);
  });
  return ResultatDecoupe(planches, horsLimites);
}

// =============================================================================
// Feuilles : pièces rectangulaires dans des panneaux
// =============================================================================

/// Pièce rectangulaire : [a] le long de la feuille (sa longueur), [b] en
/// travers (sa largeur). [rotationPermise] false : le sens du panneau compte
/// (contreplaqué de plancher, OSB…).
class PieceRect {
  final String id;
  final double a;
  final double b;
  final bool rotationPermise;
  const PieceRect(this.id, this.a, this.b, {this.rotationPermise = false});
  double get aire => a * b;
}

class Placement {
  final PieceRect piece;
  final double x;
  final double y;
  final double a;
  final double b;
  final bool tournee;
  const Placement(this.piece, this.x, this.y, this.a, this.b, this.tournee);
}

class FeuilleUtilisee {
  final double longueur;
  final double largeur;
  final List<Placement> placements;
  const FeuilleUtilisee(this.longueur, this.largeur, this.placements);
  double get aireUtilisee => placements.fold(0.0, (s, p) => s + p.a * p.b);
}

class ResultatFeuilles {
  final List<FeuilleUtilisee> feuilles;
  final List<PieceRect> horsLimites;
  const ResultatFeuilles(this.feuilles, this.horsLimites);

  int get nombre => feuilles.length;
  double get aireUtile => feuilles.fold(0.0, (s, f) => s + f.aireUtilisee);
  double get aireTotale =>
      feuilles.fold(0.0, (s, f) => s + f.longueur * f.largeur);
  double get pertePourcent =>
      aireTotale <= 0 ? 0 : (aireTotale - aireUtile) / aireTotale * 100;
}

class _Rayon {
  final double y;
  final double hauteur;
  double xUtilise = 0;
  _Rayon(this.y, this.hauteur);
}

class _Feuille {
  final List<_Rayon> rayons = [];
  final List<Placement> placements = [];
  double yUtilise = 0;
}

/// Place [pieces] dans des feuilles de [longueurFeuille] × [largeurFeuille]
/// (rangées « du plus large au moins large », meilleur ajustement).
///
/// [trait] : jeu entre deux pièces d'une même feuille. Par défaut 0 : les
/// pièces sont données joint à joint (centre à centre des supports) et se
/// posent avec un jeu de dilatation de 1/8 po qui compense le trait de scie.
ResultatFeuilles empaqueterFeuilles(
  List<PieceRect> pieces, {
  required double longueurFeuille,
  required double largeurFeuille,
  double trait = 0,
}) {
  const tol = 1e-6;
  final feuilles = <_Feuille>[];
  final horsLimites = <PieceRect>[];

  // Orientation de départ : la pièce garde son sens, sauf si la rotation est
  // permise (alors son grand côté va dans le sens de la feuille).
  final liste = <(PieceRect, double, double, bool)>[];
  for (final p in pieces) {
    var a = p.a, b = p.b, tournee = false;
    if (p.rotationPermise && b > a) {
      final t = a;
      a = b;
      b = t;
      tournee = true;
    }
    final entre = a <= longueurFeuille + tol && b <= largeurFeuille + tol;
    final entreTournee =
        p.rotationPermise &&
        b <= longueurFeuille + tol &&
        a <= largeurFeuille + tol;
    if (!entre && !entreTournee) {
      horsLimites.add(p);
      continue;
    }
    if (!entre) {
      final t = a;
      a = b;
      b = t;
      tournee = !tournee;
    }
    liste.add((p, a, b, tournee));
  }
  liste.sort((x, y) {
    final c = y.$3.compareTo(x.$3);
    return c != 0 ? c : y.$2.compareTo(x.$2);
  });

  for (final (p, a, b, tournee) in liste) {
    _Feuille? cibleFeuille;
    _Rayon? cibleRayon;
    var meilleur = double.infinity;
    for (final f in feuilles) {
      for (final r in f.rayons) {
        final x = r.xUtilise + (r.xUtilise > 0 ? trait : 0);
        if (b <= r.hauteur + tol && x + a <= longueurFeuille + tol) {
          final reste = (r.hauteur - b) * 1000 + (longueurFeuille - x - a);
          if (reste < meilleur) {
            meilleur = reste;
            cibleFeuille = f;
            cibleRayon = r;
          }
        }
      }
    }
    if (cibleRayon == null) {
      for (final f in feuilles) {
        final y = f.yUtilise + (f.yUtilise > 0 ? trait : 0);
        if (y + b <= largeurFeuille + tol) {
          cibleFeuille = f;
          cibleRayon = _Rayon(y, b);
          f.rayons.add(cibleRayon);
          f.yUtilise = y + b;
          break;
        }
      }
    }
    if (cibleRayon == null) {
      final f = _Feuille();
      feuilles.add(f);
      cibleFeuille = f;
      cibleRayon = _Rayon(0, b);
      f.rayons.add(cibleRayon);
      f.yUtilise = b;
    }
    final x = cibleRayon.xUtilise + (cibleRayon.xUtilise > 0 ? trait : 0);
    cibleFeuille!.placements.add(Placement(p, x, cibleRayon.y, a, b, tournee));
    cibleRayon.xUtilise = x + a;
  }

  return ResultatFeuilles([
    for (final f in feuilles)
      FeuilleUtilisee(longueurFeuille, largeurFeuille, f.placements),
  ], horsLimites);
}
