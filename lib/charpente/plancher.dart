import 'dart:math' as math;

import 'empaquetage.dart';
import 'geometrie.dart';
import 'panneaux.dart';
import 'unites.dart';

/// Calcul d'un plancher : solives, solives de rive, étriers, entremises, bois à
/// commander, et feuilles de sous-plancher posées à joints décalés.
/// Unités : POUCES.

enum ModeEtriers { aucun, unBout, deuxBouts }

const espacementsStandards = <double>[12, 16, 19.2, 24];

/// 8, 10, 12, 14, 16, 18 et 20 pi.
const longueursPlanchesParDefaut = <double>[96, 120, 144, 168, 192, 216, 240];

class SpecInvalide implements Exception {
  final String message;
  const SpecInvalide(this.message);
  @override
  String toString() => message;
}

class SpecPlancher {
  /// Contour extérieur de l'ossature (hors tout), en pouces.
  final Polygone forme;

  /// Entraxe des solives (centre à centre) : 12, 16, 19,2 ou 24 po.
  final double espacement;

  /// Direction des solives en degrés (0 = le long de l'axe X de la forme).
  /// Null : choisie pour la portée la plus courte.
  final double? angleSolivesDeg;

  final double epaisseurSolive;
  final double epaisseurRive;

  /// Solives de bordure doublées (côtés parallèles aux solives).
  final bool solivesDoublesAuxCotes;

  /// Solive de rive doublée : deux pièces côte à côte (les solives sont
  /// alors plus courtes d'une épaisseur de rive de plus à chaque bout).
  final bool riveDouble;
  final ModeEtriers etriers;

  /// Rangées d'entremises (0 à 3).
  final int rangeesEntremises;
  final List<double> longueursPlanches;
  final FormatPanneau panneau;

  /// Décalage minimal entre les joints de rangées voisines (po).
  final double decalageMin;

  /// Marge d'achat sur les feuilles, en %.
  final double margePanneauxPourcent;

  const SpecPlancher({
    required this.forme,
    this.espacement = 16,
    this.angleSolivesDeg,
    this.epaisseurSolive = 1.5,
    this.epaisseurRive = 1.5,
    this.solivesDoublesAuxCotes = false,
    this.riveDouble = false,
    this.etriers = ModeEtriers.aucun,
    this.rangeesEntremises = 0,
    this.longueursPlanches = longueursPlanchesParDefaut,
    this.panneau = panneau4x8,
    this.decalageMin = 24,
    this.margePanneauxPourcent = 0,
  });

  void valider() {
    if (!(espacement >= 6 && espacement <= 48)) {
      throw const SpecInvalide('Entraxe des solives : entre 6 et 48 po.');
    }
    if (!(epaisseurSolive > 0 && epaisseurSolive <= 6)) {
      throw const SpecInvalide('Épaisseur des solives invalide.');
    }
    if (!(epaisseurRive > 0 && epaisseurRive <= 6)) {
      throw const SpecInvalide('Épaisseur de la solive de rive invalide.');
    }
    if (rangeesEntremises < 0 || rangeesEntremises > 3) {
      throw const SpecInvalide('Entremises : de 0 à 3 rangées.');
    }
    if (longueursPlanches.isEmpty || longueursPlanches.any((l) => !(l > 0))) {
      throw const SpecInvalide('Choisissez au moins une longueur de planche.');
    }
    if (!(decalageMin >= 0 && decalageMin <= 96)) {
      throw const SpecInvalide('Décalage des joints : entre 0 et 96 po.');
    }
    if (!(margePanneauxPourcent >= 0 && margePanneauxPourcent <= 50)) {
      throw const SpecInvalide('Marge sur les feuilles : entre 0 et 50 %.');
    }
    if (angleSolivesDeg != null && !angleSolivesDeg!.isFinite) {
      throw const SpecInvalide('Direction des solives invalide.');
    }
    final b = forme.boite;
    if (b.largeur > pouceMaxSaisie || b.hauteur > pouceMaxSaisie) {
      throw const SpecInvalide('Forme trop grande.');
    }
  }
}

/// Une solive (ou solive de bordure), dans le repère PIVOTÉ : les solives sont
/// parallèles à l'axe u ; v est la position transversale de leur axe.
class Solive {
  final double v;

  /// Extrémités de l'axe de la solive, rives déduites.
  final double u0;
  final double u1;

  /// Longueur à couper, mesurée à la pointe longue des coupes d'angle.
  final double longueurCoupe;
  final double biseauDebutDeg;
  final double biseauFinDeg;

  /// Pente de la coupe à chaque bout : décalage en u par unité de v (0 : coupe
  /// d'équerre). Sert au dessin : à v ± épaisseur/2, le bout est à u0 ± ... × pente.
  final double penteDebut;
  final double penteFin;

  /// Forme réelle de la solive (repère pivoté) : la bande de la solive coupée
  /// par les faces intérieures des rives. Elle diffère du rectangle à bouts
  /// biseautés près d'un sommet aigu, où la solive se termine en pointe.
  final List<Pt>? contour;

  /// Solive de bordure : posée le long d'un côté parallèle aux solives.
  final bool bordure;

  /// Deuxième solive d'un doublage.
  final bool doublon;
  const Solive({
    required this.v,
    required this.u0,
    required this.u1,
    required this.longueurCoupe,
    required this.biseauDebutDeg,
    required this.biseauFinDeg,
    this.penteDebut = 0,
    this.penteFin = 0,
    this.contour,
    required this.bordure,
    required this.doublon,
  });
}

/// Une entremise (blocage) entre deux solives voisines : à la position [u] le
/// long des solives, de [v0] à [v1] en travers.
class PoseEntremise {
  final double u;
  final double v0;
  final double v1;
  const PoseEntremise(this.u, this.v0, this.v1);
  double get longueur => v1 - v0;
}

/// Solive de rive (rim) : le long d'un côté non parallèle aux solives.
class PieceRive {
  /// Côté du contour (dans la forme d'origine).
  final int cote;
  final double longueur;

  /// Angles intérieurs aux deux extrémités du côté (info : coupes de coin).
  final double angleDebutDeg;
  final double angleFinDeg;

  /// Morceau (0, 1, …) si le côté dépasse la plus longue planche.
  final int morceau;
  final int morceaux;

  /// Deuxième pièce d'une rive doublée.
  final bool doublon;
  const PieceRive({
    required this.cote,
    required this.longueur,
    required this.angleDebutDeg,
    required this.angleFinDeg,
    required this.morceau,
    required this.morceaux,
    this.doublon = false,
  });
}

/// Une pièce de feuille posée : bande de largeur [u1 - u0], de [v0] à [v1].
class PosePanneau {
  final int rangee;
  final double u0;
  final double u1;
  final double v0;
  final double v1;

  /// Numéro de la feuille d'où elle est coupée.
  final int feuille;
  const PosePanneau({
    required this.rangee,
    required this.u0,
    required this.u1,
    required this.v0,
    required this.v1,
    required this.feuille,
  });
  double get longueur => v1 - v0;
  double get largeur => u1 - u0;
}

class PlanPanneaux {
  final FormatPanneau format;
  final List<PosePanneau> poses;
  final ResultatFeuilles decoupe;
  final int rangees;
  final int feuillesUtilisees;
  final int feuillesACommander;
  final double margePourcent;

  /// Vrai si un joint n'a pas pu tomber sur une solive (cas exceptionnel).
  final bool jointsHorsSolives;
  const PlanPanneaux({
    required this.format,
    required this.poses,
    required this.decoupe,
    required this.rangees,
    required this.feuillesUtilisees,
    required this.feuillesACommander,
    required this.margePourcent,
    this.jointsHorsSolives = false,
  });

  double get pertePourcent => decoupe.pertePourcent;
}

class ResultatPlancher {
  final SpecPlancher spec;

  /// Direction retenue des solives (degrés) et forme pivotée (solives // axe X).
  final double angleSolivesDeg;
  final Polygone formePivotee;
  final List<Solive> solives;
  final List<PieceRive> rives;
  final List<PieceCoupe> entremises;
  final List<PoseEntremise> entremisesPoses;
  final ResultatDecoupe bois;
  final int etriers;
  final PlanPanneaux panneaux;
  final double porteeMax;
  final List<String> avertissements;

  const ResultatPlancher({
    required this.spec,
    required this.angleSolivesDeg,
    required this.formePivotee,
    required this.solives,
    required this.rives,
    required this.entremises,
    required this.entremisesPoses,
    required this.bois,
    required this.etriers,
    required this.panneaux,
    required this.porteeMax,
    required this.avertissements,
  });

  int get nombreSolives => solives.length;
  int get nombreRives => rives.length;

  /// Point du repère pivoté → repère de la forme d'origine.
  Pt versForme(Pt p) => p.pivote(degEnRad(angleSolivesDeg));

  double get aire => spec.forme.aire;
}

// =============================================================================
// Calcul
// =============================================================================

const double _tolHorizontal = 0.05; // degrés

bool _estHorizontale(Pt p, Pt q) {
  final d = q - p;
  final l = d.longueur;
  return l > 0 && d.y.abs() / l < math.sin(degEnRad(_tolHorizontal));
}

double _normaliser180(double deg) {
  var a = deg % 180;
  if (a < 0) {
    a += 180;
  }
  return a;
}

/// Longueur de la plus longue solive pour une direction donnée.
double _porteeMax(Polygone p, double angleDeg) {
  final r = p.pivote(-degEnRad(angleDeg));
  var m = 0.0;
  for (final s in r.sommets) {
    for (final dy in const [-1e-6, 1e-6]) {
      for (final c in r.cordes(horizontale: true, c: s.y + dy, union: false)) {
        m = math.max(m, c.longueur);
      }
    }
  }
  return m;
}

/// Direction qui donne la plus courte portée (solives le long du petit côté
/// d'un rectangle). À égalité, on préfère 0° / 90°.
double angleSolivesAuto(Polygone p) {
  final candidats = <double>{0, 90};
  for (var i = 0; i < p.nombre; i++) {
    final d = p.sommet(i + 1) - p.sommet(i);
    final a = _normaliser180(radEnDeg(math.atan2(d.y, d.x)));
    candidats.add((a * 1e4).roundToDouble() / 1e4);
    candidats.add((_normaliser180(a + 90) * 1e4).roundToDouble() / 1e4);
  }
  double? meilleur;
  var portee = double.infinity;
  for (final a in candidats) {
    final m = _porteeMax(p, a);
    final egal = (m - portee).abs() < 1e-6;
    final mieux = m < portee - 1e-6;
    final prefere = a == 0 || a == 90;
    if (mieux || (egal && prefere && !(meilleur == 0 || meilleur == 90))) {
      portee = m;
      meilleur = a;
    }
  }
  return meilleur ?? 0;
}

/// Contour décalé vers l'intérieur de [e] le long des côtés qui reçoivent une
/// rive (non parallèles aux solives) ; les côtés parallèles aux solives ne sont
/// pas décalés. Les sommets sont les intersections des droites décalées
/// voisines. Null si la forme décalée n'est pas valable (détail plus petit que
/// la rive) : on retombe alors sur le calcul par retrait.
Polygone? _polygoneInterieur(Polygone r, double e) {
  final n = r.nombre;
  final points = <Pt>[];
  final dirs = <Pt>[];
  for (var i = 0; i < n; i++) {
    final p = r.sommet(i), q = r.sommet(i + 1);
    final off = _estHorizontale(p, q) ? 0.0 : e;
    points.add(p + r.normaleInterieure(i) * off);
    dirs.add((q - p).unitaire);
  }
  final sommets = <Pt>[];
  for (var k = 0; k < n; k++) {
    final i = (k - 1 + n) % n;
    final denom = dirs[i].cross(dirs[k]);
    if (denom.abs() < 1e-9) {
      sommets.add(points[k]);
      continue;
    }
    final t = (points[k] - points[i]).cross(dirs[k]) / denom;
    sommets.add(points[i] + dirs[i] * t);
  }
  var aire = 0.0;
  for (var i = 0; i < n; i++) {
    aire += sommets[i].cross(sommets[(i + 1) % n]);
  }
  if (!(aire > 1e-6) || aire / 2 > r.aire) {
    return null;
  }
  try {
    return Polygone(sommets);
  } on FormeInvalide {
    return null;
  }
}

class _Brute {
  final double v;
  final Corde corde;
  final bool bordure;
  final bool doublon;
  const _Brute(this.v, this.corde, this.bordure, this.doublon);
}

/// Calcule le plancher. Lance [SpecInvalide] si les données sont invalides.
ResultatPlancher calculerPlancher(SpecPlancher spec) {
  spec.valider();
  final avertissements = <String>[];
  final angle = spec.angleSolivesDeg == null
      ? angleSolivesAuto(spec.forme)
      : _normaliser180(spec.angleSolivesDeg!);
  final r = spec.forme.pivote(-degEnRad(angle));
  final boite = r.boite;
  final t = spec.epaisseurSolive;
  // Rive doublée : deux épaisseurs à chaque bout des solives.
  final trEff = spec.epaisseurRive * (spec.riveDouble ? 2 : 1);
  final s = spec.espacement;

  // --- Solives de bordure (côtés parallèles aux solives) ---------------------
  final brutes = <_Brute>[];
  final cles = <String>{};
  void ajouter(_Brute b) {
    final cle =
        '${(b.v * 100).round()}|${(b.corde.debut * 100).round()}|${(b.corde.fin * 100).round()}';
    if (cles.add(cle)) {
      brutes.add(b);
    }
  }

  for (var i = 0; i < r.nombre; i++) {
    final p = r.sommet(i), q = r.sommet(i + 1);
    if (!_estHorizontale(p, q)) {
      continue;
    }
    final n = r.normaleInterieure(i);
    final v = p.y + n.y * t / 2;
    final x0 = math.min(p.x, q.x), x1 = math.max(p.x, q.x);
    for (final c in r.cordes(horizontale: true, c: v)) {
      final chevauche = math.min(x1, c.fin) - math.max(x0, c.debut);
      if (chevauche >= 0.5 * (x1 - x0)) {
        ajouter(_Brute(v, c, true, false));
        if (spec.solivesDoublesAuxCotes) {
          final v2 = v + n.y * t;
          for (final c2 in r.cordes(horizontale: true, c: v2)) {
            if (math.min(c.fin, c2.fin) - math.max(c.debut, c2.debut) >
                0.5 * c.longueur) {
              ajouter(_Brute(v2, c2, true, true));
            }
          }
        }
      }
    }
  }
  final bordures = [...brutes];

  // --- Solives courantes : grille d'entraxe depuis le bord (v minimal) -------
  for (var k = 1; ; k++) {
    final v = boite.yMin + k * s;
    if (v >= boite.yMax - 1e-9) {
      break;
    }
    for (final c in r.cordes(horizontale: true, c: v)) {
      var gene = false;
      for (final b in bordures) {
        final chevauche =
            math.min(c.fin, b.corde.fin) - math.max(c.debut, b.corde.debut);
        if ((b.v - v).abs() < t - 1e-6 && chevauche > 1e-6) {
          gene = true; // la solive de bordure prend la place
          break;
        }
      }
      if (!gene) {
        ajouter(_Brute(v, c, false, false));
      }
    }
  }

  // --- Longueurs de coupe (retrait des solives de rive, coupes d'angle) -------
  final solives = <Solive>[];
  // Les bouts des solives sont sur les faces intérieures des rives : les cordes
  // du contour décalé (côtés parallèles aux solives : pas de rive, pas de décalage).
  final interieur = _polygoneInterieur(r, trEff);
  if (interieur == null) {
    avertissements.add(
      'La forme est trop étroite par endroits pour la solive de rive '
      '(${formatImperial(trEff)}) : les longueurs de solives sont approximatives, '
      'vérifiez la forme.',
    );
  }
  for (final b in brutes) {
    double retrait(int arete) {
      final n = r.normaleInterieure(arete);
      return trEff / math.max(n.x.abs(), 0.02);
    }

    double biseau(int arete) {
      final n = r.normaleInterieure(arete);
      return radEnDeg(math.acos(n.x.abs().clamp(0.0, 1.0)));
    }

    double u0, u1;
    int areteDebut, areteFin;
    if (interieur != null) {
      Corde? meilleure;
      var recouvrement = 0.0;
      for (final c in interieur.cordes(horizontale: true, c: b.v)) {
        final ch =
            math.min(c.fin, b.corde.fin) - math.max(c.debut, b.corde.debut);
        if (ch > recouvrement) {
          recouvrement = ch;
          meilleure = c;
        }
      }
      if (meilleure == null) {
        continue;
      }
      u0 = meilleure.debut;
      u1 = meilleure.fin;
      areteDebut = meilleure.areteDebut;
      areteFin = meilleure.areteFin;
    } else {
      final longueur = b.corde.longueur;
      final plafond = longueur * 0.45;
      u0 = b.corde.debut + math.min(retrait(b.corde.areteDebut), plafond);
      u1 = b.corde.fin - math.min(retrait(b.corde.areteFin), plafond);
      areteDebut = b.corde.areteDebut;
      areteFin = b.corde.areteFin;
    }
    final centre = u1 - u0;
    if (centre < 1) {
      continue; // éclat au sommet d'une forme : pas une vraie solive
    }
    final bd = biseau(areteDebut), bf = biseau(areteFin);
    double pente(int arete) {
      final e = r.sommet(arete + 1) - r.sommet(arete);
      return e.y.abs() < 1e-9 ? 0.0 : (e.x / e.y).clamp(-6.0, 6.0);
    }

    double pointe(double deg) =>
        (t / 2) * math.tan(degEnRad(math.min(deg, 80)));
    var longueurCoupe = centre + pointe(bd) + pointe(bf);
    List<Pt>? forme;
    if (interieur != null) {
      // Forme réelle : la bande de la solive dans le contour intérieur.
      final marge =
          t * math.max(pente(areteDebut).abs(), pente(areteFin).abs()) / 2 +
          1e-3;
      final c = polygoneDansRectangle(
        interieur.sommets,
        u0 - marge,
        u1 + marge,
        b.v - t / 2,
        b.v + t / 2,
      );
      if (c.length >= 3) {
        var aire = 0.0;
        var mn = double.infinity, mx = -double.infinity;
        for (var i = 0; i < c.length; i++) {
          aire += c[i].cross(c[(i + 1) % c.length]);
          mn = math.min(mn, c[i].x);
          mx = math.max(mx, c[i].x);
        }
        if (aire.abs() / 2 > 0.01) {
          forme = c;
          longueurCoupe = mx - mn;
        }
      }
    }
    solives.add(
      Solive(
        v: b.v,
        u0: u0,
        u1: u1,
        longueurCoupe: longueurCoupe,
        contour: forme,
        biseauDebutDeg: bd,
        biseauFinDeg: bf,
        penteDebut: pente(areteDebut),
        penteFin: pente(areteFin),
        bordure: b.bordure,
        doublon: b.doublon,
      ),
    );
  }
  solives.sort((a, b) {
    final c = a.v.compareTo(b.v);
    return c != 0 ? c : a.u0.compareTo(b.u0);
  });

  if (solives.isEmpty) {
    avertissements.add('La forme est trop étroite pour y poser des solives.');
  }

  // --- Solives de rive : côtés non parallèles aux solives --------------------
  final maxPlanche = spec.longueursPlanches.reduce(math.max);
  final rives = <PieceRive>[];
  for (var i = 0; i < r.nombre; i++) {
    if (_estHorizontale(r.sommet(i), r.sommet(i + 1))) {
      continue;
    }
    final longueur = r.longueurCote(i);
    final morceaux = math.max(1, (longueur / maxPlanche - 1e-9).ceil());
    for (var m = 0; m < morceaux; m++) {
      for (var d = 0; d < (spec.riveDouble ? 2 : 1); d++) {
        rives.add(
          PieceRive(
            cote: i,
            longueur: longueur / morceaux,
            angleDebutDeg: r.angleInterieurDeg(i),
            angleFinDeg: r.angleInterieurDeg(i + 1),
            morceau: m,
            morceaux: morceaux,
            doublon: d == 1,
          ),
        );
      }
    }
  }
  final epissures = rives
      .where((p) => p.morceaux > 1 && !p.doublon)
      .map((p) => p.cote)
      .toSet();
  if (epissures.isNotEmpty) {
    avertissements.add(
      'Un côté dépasse la plus longue planche (${formatImperial(maxPlanche)}) : '
      'la solive de rive est faite de plusieurs morceaux, à épisser sur une solive.',
    );
  }

  // --- Entremises (blocage) --------------------------------------------------
  final entremises = <PieceCoupe>[];
  final entremisesPoses = <PoseEntremise>[];
  if (spec.rangeesEntremises > 0) {
    final distinctes = solives.where((x) => !x.doublon).toList();
    // Une solive de bordure doublée occupe 2 épaisseurs : l'entremise s'arrête
    // contre la seconde.
    final bornes = <(double, double)>[
      for (final x in distinctes)
        () {
          var lo = x.v - t / 2, hi = x.v + t / 2;
          for (final d in solives) {
            if (d.doublon &&
                (d.v - x.v).abs() < t + 0.5 &&
                math.min(x.u1, d.u1) - math.max(x.u0, d.u0) >
                    0.5 * (x.u1 - x.u0)) {
              lo = math.min(lo, d.v - t / 2);
              hi = math.max(hi, d.v + t / 2);
            }
          }
          return (lo, hi);
        }(),
    ];
    for (var i = 0; i < distinctes.length; i++) {
      for (var j = i + 1; j < distinctes.length; j++) {
        final a = distinctes[i], b = distinctes[j];
        final ecart = bornes[j].$1 - bornes[i].$2;
        if (b.v - a.v > s + t + 1e-6) {
          break;
        }
        if (ecart < 0.5) {
          continue;
        }
        final chevauche = math.min(a.u1, b.u1) - math.max(a.u0, b.u0);
        if (chevauche >= 24) {
          final lo = math.max(a.u0, b.u0);
          for (var k = 0; k < spec.rangeesEntremises; k++) {
            entremises.add(
              PieceCoupe('e${entremises.length}', ecart, 'entremise'),
            );
            // Rangées réparties également sur la portée (1 : à mi-portée).
            final u = lo + chevauche * (k + 1) / (spec.rangeesEntremises + 1);
            entremisesPoses.add(PoseEntremise(u, bornes[i].$2, bornes[j].$1));
          }
        }
        break; // seulement la solive voisine
      }
    }
  }

  // --- Bois à commander ------------------------------------------------------
  final pieces = <PieceCoupe>[
    for (var i = 0; i < solives.length; i++)
      PieceCoupe(
        's$i',
        solives[i].longueurCoupe,
        solives[i].bordure ? 'solive de bordure' : 'solive',
      ),
    for (var i = 0; i < rives.length; i++)
      PieceCoupe('r$i', rives[i].longueur, 'solive de rive'),
    ...entremises,
  ];
  final bois = decouperPlanches(pieces, spec.longueursPlanches);
  if (bois.horsLimites.isNotEmpty) {
    final plusLongue = bois.horsLimites.map((p) => p.longueur).reduce(math.max);
    avertissements.add(
      'Une solive de ${formatImperial(plusLongue)} dépasse la plus longue planche '
      '(${formatImperial(maxPlanche)}) : prévoir une poutre intermédiaire ou des solives épissées.',
    );
  }

  // --- Étriers ----------------------------------------------------------------
  final parSolive = switch (spec.etriers) {
    ModeEtriers.aucun => 0,
    ModeEtriers.unBout => 1,
    ModeEtriers.deuxBouts => 2,
  };
  final etriers = solives.length * parSolive;

  final portee = solives.isEmpty
      ? 0.0
      : solives.map((x) => x.longueurCoupe).reduce(math.max);

  // --- Feuilles ---------------------------------------------------------------
  final plan = _planifierPanneaux(r, solives, spec, avertissements);

  if (!spec.forme.estRectangle) {
    avertissements.add(
      'Forme irrégulière : les feuilles sont comptées avec leur rectangle englobant '
      '(estimation prudente) ; les chutes en biais ne sont pas réutilisées.',
    );
  }
  avertissements.add(
    'La dimension des solives (portée admissible) n\'est pas vérifiée : '
    'à valider avec le Code de construction du Québec / un ingénieur.',
  );

  return ResultatPlancher(
    spec: spec,
    angleSolivesDeg: angle,
    formePivotee: r,
    solives: solives,
    rives: rives,
    entremises: entremises,
    entremisesPoses: entremisesPoses,
    bois: bois,
    etriers: etriers,
    panneaux: plan,
    porteeMax: portee,
    avertissements: avertissements,
  );
}

// =============================================================================
// Feuilles de sous-plancher : joints décalés, sur les solives
// =============================================================================

class _Rangee {
  final double u0;
  final double u1;
  final List<(double, double)> intervalles; // (v0, v1)
  _Rangee(this.u0, this.u1, this.intervalles);
}

/// Une façon de découper un intervalle en pièces : points de coupe croissants
/// de v0 à v1 (extrémités comprises).
typedef _Coupes = List<double>;

class _OptionRangee {
  final List<_Coupes> parIntervalle;
  const _OptionRangee(this.parIntervalle);
  Iterable<double> get joints sync* {
    for (final c in parIntervalle) {
      for (var i = 1; i < c.length - 1; i++) {
        yield c[i];
      }
    }
  }
}

/// Étendue (en v) de la forme dans la bande verticale [a, c], exacte : entre
/// deux sommets consécutifs, les bords de la forme sont des droites, donc
/// l'étendue de chaque morceau de corde est donnée par ses deux extrémités.
List<(double, double)> _intervallesBande(Polygone r, double a, double c) {
  final bornes = <double>{a, c};
  for (final s in r.sommets) {
    if (s.x > a + 1e-9 && s.x < c - 1e-9) {
      bornes.add(s.x);
    }
  }
  final xs = bornes.toList()..sort();
  final morceaux = <(double, double)>[];
  const e = 1e-7;
  for (var i = 0; i + 1 < xs.length; i++) {
    final x0 = xs[i], x1 = xs[i + 1];
    if (x1 - x0 < 4 * e) {
      continue;
    }
    final g = r.cordes(horizontale: false, c: x0 + e, union: false);
    final d = r.cordes(horizontale: false, c: x1 - 2 * e, union: false);
    if (g.length == d.length) {
      for (var k = 0; k < g.length; k++) {
        morceaux.add((
          math.min(g[k].debut, d[k].debut),
          math.max(g[k].fin, d[k].fin),
        ));
      }
    } else {
      for (final z in [...g, ...d]) {
        morceaux.add((z.debut, z.fin));
      }
    }
  }
  morceaux.sort((p, q) => p.$1.compareTo(q.$1));
  final fusion = <(double, double)>[];
  for (final m in morceaux) {
    if (fusion.isNotEmpty && m.$1 <= fusion.last.$2 + 1e-6) {
      fusion[fusion.length - 1] = (
        fusion.last.$1,
        math.max(fusion.last.$2, m.$2),
      );
    } else {
      fusion.add(m);
    }
  }
  return [
    for (final f in fusion)
      if (f.$2 - f.$1 > 0.5) f,
  ];
}

/// Largeurs des bandes : des feuilles entières, la dernière refendue. Une
/// dernière bande de moins de 12 po est évitée en rognant la précédente.
List<double> _largeursBandes(double total, double largeur) {
  final n = math.max(1, (total / largeur - 1e-9).ceil());
  final largeurs = <double>[
    for (var i = 0; i < n - 1; i++) largeur,
    total - largeur * (n - 1),
  ];
  const minBande = 12.0;
  if (n > 1 && largeurs.last < minBande - 1e-9) {
    final manque = minBande - largeurs.last;
    largeurs[n - 2] -= manque;
    largeurs[n - 1] = minBande;
  }
  return largeurs;
}

List<_Rangee> _rangees(Polygone r, double largeur, bool depuisMin) {
  final b = r.boite;
  final largeurs = _largeursBandes(b.largeur, largeur);
  final rangees = <_Rangee>[];
  var position = depuisMin ? b.xMin : b.xMax;
  for (var i = 0; i < largeurs.length; i++) {
    final double a, c;
    if (depuisMin) {
      a = position;
      c = math.min(b.xMax, a + largeurs[i]);
      position = c;
    } else {
      c = position;
      a = math.max(b.xMin, c - largeurs[i]);
      position = a;
    }
    rangees.add(_Rangee(a, c, _intervallesBande(r, a, c)));
  }
  if (!depuisMin) {
    return rangees.reversed.toList(); // dans l'ordre croissant de u
  }
  return rangees;
}

/// Façons de couper un intervalle [v0, v1] en pièces de longueur ≤ [lf], dont
/// les joints tombent sur des solives ([candidats]).
List<_Coupes> _sequences(
  double v0,
  double v1,
  List<double> candidats,
  double lf,
  double minPiece,
) {
  const tol = 1e-6;
  final longueur = v1 - v0;
  if (longueur <= lf + tol) {
    return [
      [v0, v1],
    ];
  }
  final utiles =
      candidats
          .where((c) => c >= v0 + minPiece - tol && c <= v1 - minPiece + tol)
          .toList()
        ..sort();
  final resultats = <String, _Coupes>{};

  void essayer(List<double> cands, bool miroir) {
    final premiers = cands.where((c) => c <= v0 + lf + tol).toList();
    for (final b1 in premiers) {
      for (var variante = 0; variante < 3; variante++) {
        final seq = <double>[v0, b1];
        var cur = b1;
        var ok = true;
        var etape = 0;
        while (v1 - cur > lf + tol) {
          final options = cands
              .where((c) => c > cur + minPiece - tol && c <= cur + lf + tol)
              .toList();
          if (options.isEmpty) {
            ok = false;
            break;
          }
          final idx = math.max(
            0,
            options.length - 1 - (etape == 0 ? variante : 0),
          );
          cur = options[idx];
          seq.add(cur);
          etape++;
        }
        if (!ok) {
          continue;
        }
        // Dernière pièce trop courte : on recule le dernier point de coupe.
        if (v1 - seq.last < minPiece - tol && seq.length > 2) {
          final avant = seq[seq.length - 2];
          final autres = cands
              .where(
                (c) =>
                    c > avant + minPiece - tol &&
                    c < seq.last - tol &&
                    v1 - c <= lf + tol,
              )
              .toList();
          if (autres.isEmpty) {
            continue;
          }
          seq[seq.length - 1] = autres.last;
        }
        if (v1 - seq.last < minPiece - tol) {
          continue;
        }
        seq.add(v1);
        final pts = miroir
            ? (seq.map((x) => v0 + v1 - x).toList()..sort())
            : seq;
        resultats[pts.map((x) => (x * 1000).round()).join(',')] = pts;
      }
    }
  }

  essayer(utiles, false);
  essayer(utiles.reversed.map((c) => v0 + v1 - c).toList()..sort(), true);
  return resultats.values.toList();
}

bool _decalageOk(_OptionRangee prec, _OptionRangee cur, double decalageMin) {
  if (decalageMin <= 0) {
    return true;
  }
  for (final a in prec.joints) {
    for (final b in cur.joints) {
      if ((a - b).abs() < decalageMin - 1e-6) {
        return false;
      }
    }
  }
  return true;
}

class _Etat {
  final List<_OptionRangee> choix;
  final (int, double, int) score; // feuilles, aire perdue, nombre de pièces
  const _Etat(this.choix, this.score);
}

(int, double, int) _evaluer(
  List<_Rangee> rangees,
  List<_OptionRangee> choix,
  FormatPanneau f,
) {
  final pieces = <PieceRect>[];
  for (var i = 0; i < choix.length; i++) {
    final rg = rangees[i];
    final largeur = rg.u1 - rg.u0;
    for (var k = 0; k < choix[i].parIntervalle.length; k++) {
      final c = choix[i].parIntervalle[k];
      for (var j = 0; j + 1 < c.length; j++) {
        pieces.add(PieceRect('$i.$k.$j', c[j + 1] - c[j], largeur));
      }
    }
  }
  final res = empaqueterFeuilles(
    pieces,
    longueurFeuille: f.longueur,
    largeurFeuille: f.largeur,
  );
  return (res.nombre, res.aireTotale - res.aireUtile, pieces.length);
}

int _comparer((int, double, int) a, (int, double, int) b) {
  if (a.$1 != b.$1) {
    return a.$1.compareTo(b.$1);
  }
  if ((a.$2 - b.$2).abs() > 1e-6) {
    return a.$2.compareTo(b.$2);
  }
  return a.$3.compareTo(b.$3);
}

PlanPanneaux? _tenterPanneaux(
  Polygone r,
  List<Solive> solives,
  SpecPlancher spec,
  bool depuisMin,
  double decalageMin,
) {
  final f = spec.panneau;
  final rangees = _rangees(r, f.largeur, depuisMin);
  final minPiece = 12.0;

  // Options par rangée.
  var horsSolives = false;
  final optionsParRangee = <List<_OptionRangee>>[];
  for (final rg in rangees) {
    // Solives qui passent dans la bande : elles portent les joints.
    final candidats = <double>{};
    for (final s in solives) {
      if (s.doublon) {
        continue;
      }
      final chevauche = math.min(s.u1, rg.u1) - math.max(s.u0, rg.u0);
      if (chevauche <= 0) {
        continue;
      }
      // Part de la bande qui se trouve dans la forme à la hauteur de cette solive :
      // la solive doit en porter au moins la moitié (ou 12 po).
      var besoin = 0.0;
      for (final c in r.cordes(horizontale: true, c: s.v)) {
        besoin += math.max(
          0,
          math.min(c.fin, rg.u1) - math.max(c.debut, rg.u0),
        );
      }
      if (besoin > 0 && chevauche >= math.min(12, 0.5 * besoin) - 1e-6) {
        candidats.add((s.v * 1e6).roundToDouble() / 1e6);
      }
    }
    final cands = candidats.toList()..sort();
    final parIntervalle = <List<_Coupes>>[];
    for (final iv in rg.intervalles) {
      var seqs = _sequences(iv.$1, iv.$2, cands, f.longueur, minPiece);
      if (seqs.isEmpty) {
        // Aucun joint possible sur une solive : pièces égales (cas exceptionnel).
        final n = math.max(2, ((iv.$2 - iv.$1) / f.longueur - 1e-9).ceil());
        seqs = [
          [for (var k = 0; k <= n; k++) iv.$1 + (iv.$2 - iv.$1) * k / n],
        ];
        horsSolives = true;
      }
      parIntervalle.add(seqs);
    }
    // Produit cartésien limité.
    var options = <_OptionRangee>[const _OptionRangee([])];
    for (final liste in parIntervalle) {
      final suivant = <_OptionRangee>[];
      for (final o in options) {
        for (final c in liste) {
          suivant.add(_OptionRangee([...o.parIntervalle, c]));
          if (suivant.length >= 80) {
            break;
          }
        }
        if (suivant.length >= 80) {
          break;
        }
      }
      options = suivant;
    }
    optionsParRangee.add(options);
  }

  // Recherche en faisceau : une option par rangée, joints décalés.
  const largeurFaisceau = 24;
  var faisceau = <_Etat>[const _Etat([], (0, 0, 0))];
  for (var i = 0; i < rangees.length; i++) {
    final suivants = <_Etat>[];
    for (final e in faisceau) {
      for (final o in optionsParRangee[i]) {
        if (e.choix.isNotEmpty && !_decalageOk(e.choix.last, o, decalageMin)) {
          continue;
        }
        final choix = [...e.choix, o];
        suivants.add(_Etat(choix, _evaluer(rangees, choix, f)));
      }
    }
    if (suivants.isEmpty) {
      return null; // décalage impossible
    }
    suivants.sort((a, b) => _comparer(a.score, b.score));
    faisceau = suivants.take(largeurFaisceau).toList();
  }
  final meilleur = faisceau.first;

  // Plan final : pièces posées + découpe dans les feuilles.
  final pieces = <PieceRect>[];
  final infos = <String, (int, double, double, double, double)>{};
  for (var i = 0; i < meilleur.choix.length; i++) {
    final rg = rangees[i];
    for (var k = 0; k < meilleur.choix[i].parIntervalle.length; k++) {
      final c = meilleur.choix[i].parIntervalle[k];
      for (var j = 0; j + 1 < c.length; j++) {
        final id = '$i.$k.$j';
        pieces.add(PieceRect(id, c[j + 1] - c[j], rg.u1 - rg.u0));
        infos[id] = (i, rg.u0, rg.u1, c[j], c[j + 1]);
      }
    }
  }
  final decoupe = empaqueterFeuilles(
    pieces,
    longueurFeuille: f.longueur,
    largeurFeuille: f.largeur,
  );
  final numero = <String, int>{};
  for (var n = 0; n < decoupe.feuilles.length; n++) {
    for (final p in decoupe.feuilles[n].placements) {
      numero[p.piece.id] = n;
    }
  }
  final poses =
      [
        for (final e in infos.entries)
          PosePanneau(
            rangee: e.value.$1,
            u0: e.value.$2,
            u1: e.value.$3,
            v0: e.value.$4,
            v1: e.value.$5,
            feuille: numero[e.key] ?? -1,
          ),
      ]..sort((a, b) {
        final c = a.rangee.compareTo(b.rangee);
        return c != 0 ? c : a.v0.compareTo(b.v0);
      });
  final utilisees = decoupe.nombre;
  final commande = spec.margePanneauxPourcent <= 0
      ? utilisees
      : (utilisees * (1 + spec.margePanneauxPourcent / 100) - 1e-9).ceil();
  return PlanPanneaux(
    format: f,
    poses: poses,
    decoupe: decoupe,
    rangees: rangees.length,
    feuillesUtilisees: utilisees,
    feuillesACommander: commande,
    margePourcent: spec.margePanneauxPourcent,
    jointsHorsSolives: horsSolives,
  );
}

PlanPanneaux _planifierPanneaux(
  Polygone r,
  List<Solive> solives,
  SpecPlancher spec,
  List<String> avertissements,
) {
  var decalage = spec.decalageMin;
  PlanPanneaux? meilleur;
  for (final depuisMin in const [true, false]) {
    final p = _tenterPanneaux(r, solives, spec, depuisMin, decalage);
    if (p != null &&
        (meilleur == null ||
            p.feuillesUtilisees < meilleur.feuillesUtilisees)) {
      meilleur = p;
    }
  }
  if (meilleur == null && decalage > 0) {
    // Décalage impossible avec ces solives : on le relâche et on le dit.
    decalage = 0;
    avertissements.add(
      'Le décalage minimal des joints (${formatImperial(spec.decalageMin)}) est impossible avec '
      'ces solives : joints décalés au mieux.',
    );
    for (final depuisMin in const [true, false]) {
      final p = _tenterPanneaux(r, solives, spec, depuisMin, decalage);
      if (p != null &&
          (meilleur == null ||
              p.feuillesUtilisees < meilleur.feuillesUtilisees)) {
        meilleur = p;
      }
    }
  }
  if (meilleur == null) {
    avertissements.add(
      'Les feuilles n\'ont pas pu être planifiées avec ces solives.',
    );
    meilleur = PlanPanneaux(
      format: spec.panneau,
      poses: const [],
      decoupe: const ResultatFeuilles([], []),
      rangees: 0,
      feuillesUtilisees: 0,
      feuillesACommander: 0,
      margePourcent: spec.margePanneauxPourcent,
    );
  }
  if (meilleur.jointsHorsSolives) {
    avertissements.add(
      'Certains joints de feuilles ne tombent sur aucune solive : ajoutez des entremises '
      'sous ces joints.',
    );
  }
  final f = spec.panneau;
  final surJoists = f.longueur % spec.espacement;
  if (surJoists > 1e-6 && (spec.espacement - surJoists) > 1e-6) {
    avertissements.add(
      'Une feuille de ${formatImperial(f.longueur)} ne se termine pas sur une solive à '
      '${formatNombre(spec.espacement, decimales: 1)} po c/c : les joints sont coupés pour '
      'tomber sur une solive (plus de chutes). Un format 4 × 8 pi est plus économique ici.',
    );
  }
  return meilleur;
}
