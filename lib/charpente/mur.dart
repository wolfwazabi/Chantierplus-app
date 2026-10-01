import 'dart:math' as math;

import 'empaquetage.dart';
import 'geometrie.dart';
import 'panneaux.dart';
import 'plancher.dart'
    show SpecInvalide, espacementsStandards, longueursPlanchesParDefaut;
import 'unites.dart';

/// Calcul des murs à ossature de bois : montants, lisses, ouvertures (portes et
/// fenêtres), linteaux, panneaux (OSB, OSB isolant R-4), fourrures, membrane et
/// revêtement. Unités : POUCES. Origine d'un mur : son début, au pied (z = 0 :
/// dessus du sous-plancher). Les montants vont de y = 0 (intérieur) à y =
/// profondeur ; les couches extérieures s'empilent au-delà.

// =============================================================================
// Jeux autour des fenêtres et des portes
// =============================================================================

/// Dégagements de la baie, fiche technique GCR FT-9.7.6.1 (révision 2024-04-10)
/// et norme CAN/CSA-A440.4 : valables pour les fenêtres et les portes.
///  - largeur de la baie = largeur du dormant + 13 à 38 mm (1/2 à 1 1/2 po),
///    soit un jour de 6 à 19 mm (1/4 à 3/4 po) de chaque côté ;
///  - hauteur de la baie = hauteur du dormant + 25 à 44 mm (1 à 1 3/4 po),
///    soit un jour de 13 à 22 mm (1/2 à 7/8 po) en haut et en bas.
class JeuxBaie {
  // Bornes de la fiche en pouces (1/2 à 1 1/2 ; 1 à 1 3/4) ; la borne basse en
  // hauteur est celle de 25 mm (un peu sous 1 po), pour accepter les deux unités.
  static const double largeurMin = 0.5;
  static const double largeurMax = 1.5;
  static const double hauteurMin = 25 / mmParPouce;
  static const double hauteurMax = 1.75;

  /// Valeurs proposées : 1 po en largeur (1/2 po de chaque côté) et 1 1/2 po en
  /// hauteur (3/4 po en haut et en bas), au milieu des plages permises.
  static const double largeurDefaut = 1;
  static const double hauteurDefaut = 1.5;
}

enum TypeOuverture { porte, fenetre }

class Ouverture {
  final TypeOuverture type;
  final String nom;

  /// Dimensions du DORMANT (cadre du produit), pas de la baie.
  final double largeurCadre;
  final double hauteurCadre;

  /// Fenêtre : hauteur du bas du cadre au-dessus du plancher. Porte : 0.
  final double allege;

  /// Distance du début du mur au CENTRE de l'ouverture.
  final double position;

  /// Jeu total en largeur et en hauteur (baie − cadre).
  final double jeuLargeur;
  final double jeuHauteur;

  const Ouverture({
    required this.type,
    this.nom = '',
    required this.largeurCadre,
    required this.hauteurCadre,
    double? allege,
    required this.position,
    this.jeuLargeur = JeuxBaie.largeurDefaut,
    this.jeuHauteur = JeuxBaie.hauteurDefaut,
  }) : allege = allege ?? (type == TypeOuverture.porte ? 0 : 36);

  double get largeurBaie => largeurCadre + jeuLargeur;
  double get hauteurBaie => hauteurCadre + jeuHauteur;
  double get baieG => position - largeurBaie / 2;
  double get baieD => position + largeurBaie / 2;

  /// Bas de la baie : fenêtre = bas du cadre − jeu du bas ; porte = plancher.
  double get baieBas =>
      type == TypeOuverture.porte ? 0 : allege - jeuHauteur / 2;
  double get baieHaut => baieBas + hauteurBaie;

  String get libelle => nom.isNotEmpty
      ? nom
      : (type == TypeOuverture.porte ? 'Porte' : 'Fenêtre');
}

// =============================================================================
// Sections de bois et paramètres
// =============================================================================

class SectionBois {
  final String nom;
  final double epaisseur;
  final double profondeur;
  const SectionBois(this.nom, this.epaisseur, this.profondeur);
}

const section2x4 = SectionBois('2×4', 1.5, 3.5);
const section2x6 = SectionBois('2×6', 1.5, 5.5);
const section2x8 = SectionBois('2×8', 1.5, 7.25);
const section2x10 = SectionBois('2×10', 1.5, 9.25);
const section2x12 = SectionBois('2×12', 1.5, 11.25);

const sectionsMurs = [section2x4, section2x6];
const sectionsLinteaux = [section2x6, section2x8, section2x10, section2x12];

/// Montants précoupés courants (po) : 92 5/8, 104 5/8 et 116 5/8.
const montantsPrecoupes = <double>[92.625, 104.625, 116.625];

class ParametresMurs {
  final double espacement;
  final SectionBois section;

  /// 1 ou 2 lisses hautes.
  final int lissesHautes;

  /// Montants de linteau (jacks) de chaque côté d'une ouverture.
  final int jacksParCote;
  final SectionBois linteau;
  final int plisLinteau;
  final int plisAppui;
  final List<double> longueursPlanches;
  final bool precoupes;
  final FormatPanneau panneau;

  /// Débord des feuilles sous le mur (po) : recouvrir la solive de rive.
  final double debordPlancher;

  /// Fourrures verticales : entraxe, épaisseur et largeur (1×3 = 3/4 × 2 1/2).
  final double fourrureEntraxe;
  final double fourrureEpaisseur;
  final double fourrureLargeur;
  final List<double> longueursFourrures;

  /// Épaisseur du revêtement (po) et marges d'achat (%).
  final double revetementEpaisseur;
  final double margeMembranePct;
  final double margeRevetementPct;

  /// Aire d'un rouleau de membrane (pi²) : 9 pi × 100 pi.
  final double aireRouleauPi2;
  final double margeFeuillesPct;

  const ParametresMurs({
    this.espacement = 16,
    this.section = section2x4,
    this.lissesHautes = 2,
    this.jacksParCote = 1,
    this.linteau = section2x8,
    this.plisLinteau = 2,
    this.plisAppui = 1,
    this.longueursPlanches = longueursPlanchesParDefaut,
    this.precoupes = true,
    this.panneau = panneau4x9,
    this.debordPlancher = 0,
    this.fourrureEntraxe = 16,
    this.fourrureEpaisseur = 0.75,
    this.fourrureLargeur = 2.5,
    this.longueursFourrures = const [96, 120, 144, 192],
    this.revetementEpaisseur = 0.75,
    this.margeMembranePct = 10,
    this.margeRevetementPct = 10,
    this.aireRouleauPi2 = 900,
    this.margeFeuillesPct = 0,
  });

  ParametresMurs copieAvec({
    double? espacement,
    SectionBois? section,
    int? lissesHautes,
    int? jacksParCote,
    SectionBois? linteau,
    int? plisLinteau,
    int? plisAppui,
    List<double>? longueursPlanches,
    bool? precoupes,
    FormatPanneau? panneau,
    double? debordPlancher,
    double? fourrureEntraxe,
    double? fourrureEpaisseur,
    double? fourrureLargeur,
    List<double>? longueursFourrures,
    double? revetementEpaisseur,
    double? margeMembranePct,
    double? margeRevetementPct,
    double? aireRouleauPi2,
    double? margeFeuillesPct,
  }) => ParametresMurs(
    espacement: espacement ?? this.espacement,
    section: section ?? this.section,
    lissesHautes: lissesHautes ?? this.lissesHautes,
    jacksParCote: jacksParCote ?? this.jacksParCote,
    linteau: linteau ?? this.linteau,
    plisLinteau: plisLinteau ?? this.plisLinteau,
    plisAppui: plisAppui ?? this.plisAppui,
    longueursPlanches: longueursPlanches ?? this.longueursPlanches,
    precoupes: precoupes ?? this.precoupes,
    panneau: panneau ?? this.panneau,
    debordPlancher: debordPlancher ?? this.debordPlancher,
    fourrureEntraxe: fourrureEntraxe ?? this.fourrureEntraxe,
    fourrureEpaisseur: fourrureEpaisseur ?? this.fourrureEpaisseur,
    fourrureLargeur: fourrureLargeur ?? this.fourrureLargeur,
    longueursFourrures: longueursFourrures ?? this.longueursFourrures,
    revetementEpaisseur: revetementEpaisseur ?? this.revetementEpaisseur,
    margeMembranePct: margeMembranePct ?? this.margeMembranePct,
    margeRevetementPct: margeRevetementPct ?? this.margeRevetementPct,
    aireRouleauPi2: aireRouleauPi2 ?? this.aireRouleauPi2,
    margeFeuillesPct: margeFeuillesPct ?? this.margeFeuillesPct,
  );

  void valider() {
    if (!(espacement >= 6 && espacement <= 48)) {
      throw const SpecInvalide('Entraxe des montants : entre 6 et 48 po.');
    }
    if (lissesHautes < 1 || lissesHautes > 2) {
      throw const SpecInvalide('Lisses hautes : 1 ou 2.');
    }
    if (jacksParCote < 1 || jacksParCote > 3) {
      throw const SpecInvalide('Montants de linteau par côté : de 1 à 3.');
    }
    if (plisLinteau < 1 || plisLinteau > 4) {
      throw const SpecInvalide('Épaisseurs du linteau : de 1 à 4.');
    }
    if (plisAppui < 1 || plisAppui > 2) {
      throw const SpecInvalide('Appui de fenêtre : 1 ou 2 pièces.');
    }
    if (longueursPlanches.isEmpty || longueursPlanches.any((l) => !(l > 0))) {
      throw const SpecInvalide('Choisissez au moins une longueur de planche.');
    }
    if (!(debordPlancher >= 0 && debordPlancher <= 24)) {
      throw const SpecInvalide('Débord des feuilles : entre 0 et 24 po.');
    }
    if (!(fourrureEntraxe >= 6 && fourrureEntraxe <= 48)) {
      throw const SpecInvalide('Entraxe des fourrures : entre 6 et 48 po.');
    }
    if (!(fourrureLargeur >= 1 && fourrureLargeur <= 6) ||
        !(fourrureEpaisseur >= 0.25 && fourrureEpaisseur <= 3)) {
      throw const SpecInvalide('Dimensions des fourrures invalides.');
    }
    if (!(revetementEpaisseur > 0 && revetementEpaisseur <= 6)) {
      throw const SpecInvalide('Épaisseur du revêtement invalide.');
    }
    if (!(margeMembranePct >= 0 && margeMembranePct <= 50) ||
        !(margeRevetementPct >= 0 && margeRevetementPct <= 50) ||
        !(margeFeuillesPct >= 0 && margeFeuillesPct <= 50)) {
      throw const SpecInvalide('Les marges d\'achat vont de 0 à 50 %.');
    }
    if (!(aireRouleauPi2 > 0)) {
      throw const SpecInvalide('Aire du rouleau de membrane invalide.');
    }
  }
}

class SpecMur {
  final String nom;

  /// Longueur de l'ossature (des lisses), en pouces.
  final double longueur;

  /// Du dessus du sous-plancher au dessus de la dernière lisse haute.
  final double hauteur;
  final List<Ouverture> ouvertures;

  /// Montants supplémentaires aux deux bouts (coin à 3 montants : 1 ; coin à
  /// angle : 1 ou 2 ; bout libre : 0), en plus du montant d'extrémité.
  final int montantsCoinDebut;
  final int montantsCoinFin;

  /// Intersections en T : position (po) de l'axe de chaque cloison qui s'appuie
  /// sur ce mur ; 2 montants d'appui par intersection.
  final List<double> intersections;

  /// Mur d'un contour : côté du contour (0, 1, …) et retraits de l'ossature aux
  /// deux bouts par rapport aux sommets. Retrait > 0 : le mur s'appuie sur
  /// l'autre (ses feuilles, sa membrane et son revêtement vont quand même
  /// jusqu'au sommet) ; retrait < 0 : le mur est prolongé (coin rentrant).
  final int? cote;
  final double retraitDebut;
  final double retraitFin;

  /// Angle intérieur du contour au début et à la fin du mur ; null : mur isolé,
  /// bout d'équerre. Autour de 90° (coin d'équerre) l'ossature est d'équerre ;
  /// ailleurs, les deux murs se rencontrent en onglet. Les couches extérieures
  /// sont d'équerre à 90° seulement.
  final double? angleDebut;
  final double? angleFin;

  const SpecMur({
    this.nom = 'Mur',
    required this.longueur,
    required this.hauteur,
    this.ouvertures = const [],
    this.montantsCoinDebut = 0,
    this.montantsCoinFin = 0,
    this.intersections = const [],
    this.cote,
    this.retraitDebut = 0,
    this.retraitFin = 0,
    this.angleDebut,
    this.angleFin,
  });
}

/// Un angle de coin est « d'équerre » à 0,5° près de 90° ou, pour l'ossature,
/// de 270° (coin rentrant : un mur prolonge l'autre).
bool _coinDEquerre(double? angle) =>
    angle == null || (angle - 90).abs() < 0.5 || (angle - 270).abs() < 0.5;

/// Recul des montants de bout contre un onglet : sur la face intérieure, la
/// coupe d'onglet est reculée de profondeur × cot(angle / 2) du sommet.
double _reculOnglet(double? angle, double profondeur) {
  if (_coinDEquerre(angle)) {
    return 0;
  }
  final cot = 1 / math.tan(angle! * math.pi / 360);
  return math.max(0.0, profondeur * cot);
}

// =============================================================================
// Résultats
// =============================================================================

enum TypeMembre {
  montant,
  montantCoin,
  roi,
  jack,
  linteau,
  appui,
  courtHaut,
  courtBas,
  lisseBasse,
  lisseHaute,
  entremise,
}

String libelleMembre(TypeMembre t) => switch (t) {
  TypeMembre.montant => 'Montant',
  TypeMembre.montantCoin => 'Montant de coin',
  TypeMembre.roi => 'Montant de rive d\'ouverture (roi)',
  TypeMembre.jack => 'Montant de linteau (jack)',
  TypeMembre.linteau => 'Linteau',
  TypeMembre.appui => 'Appui de fenêtre',
  TypeMembre.courtHaut => 'Court montant (haut)',
  TypeMembre.courtBas => 'Court montant (bas)',
  TypeMembre.lisseBasse => 'Lisse basse',
  TypeMembre.lisseHaute => 'Lisse haute',
  TypeMembre.entremise => 'Entremise',
};

/// Une pièce de bois du mur, en coordonnées du mur (x le long du mur, y dans
/// l'épaisseur, z en hauteur).
class Membre {
  final TypeMembre type;
  final double x0, x1;
  final double y0, y1;
  final double z0, z1;

  /// Longueur à couper (pointe longue).
  final double longueurCoupe;
  final String section;
  const Membre({
    required this.type,
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.z0,
    required this.z1,
    required this.longueurCoupe,
    required this.section,
  });
}

/// Une pièce de feuille (OSB / Isobrace) sur un mur : rectangle englobant, avec
/// les découpes d'ouvertures qui la traversent.
class PosePanneauMur {
  final int mur;
  final int colonne;
  final int rangee;
  final double x0, x1, z0, z1;
  final List<(double, double, double, double)> decoupes;
  final int feuille;
  const PosePanneauMur({
    required this.mur,
    required this.colonne,
    required this.rangee,
    required this.x0,
    required this.x1,
    required this.z0,
    required this.z1,
    required this.decoupes,
    required this.feuille,
  });
  double get largeur => x1 - x0;
  double get hauteur => z1 - z0;
}

/// Une fourrure (1×3) posée sur le mur : rectangle (x, z) dans le plan du mur.
class PieceFourrure {
  final double x0, x1, z0, z1;
  final bool verticale;
  const PieceFourrure(this.x0, this.x1, this.z0, this.z1, this.verticale);
  double get longueur => verticale ? z1 - z0 : x1 - x0;
}

class ResultatMur {
  final SpecMur spec;
  final List<Membre> membres;
  final List<PosePanneauMur> panneaux;
  final List<PieceFourrure> fourrures;
  final double aireBrutePo2;
  final double aireNettePo2;
  final List<String> avertissements;
  const ResultatMur({
    required this.spec,
    required this.membres,
    required this.panneaux,
    required this.fourrures,
    required this.aireBrutePo2,
    required this.aireNettePo2,
    required this.avertissements,
  });

  int compter(TypeMembre t) => membres.where((m) => m.type == t).length;
}

class ResultatMurs {
  final ParametresMurs parametres;
  final List<ResultatMur> murs;

  /// Bois des montants, lisses, appuis, entremises (même section) : coupes dans
  /// des planches, sans les montants précoupés.
  final ResultatDecoupe boisOssature;
  final ResultatDecoupe boisLinteaux;

  /// Montants précoupés : longueur (po) → nombre.
  final Map<double, int> precoupes;
  final ResultatFeuilles decoupePanneaux;
  final int feuillesUtilisees;
  final int feuillesACommander;
  final ResultatDecoupe fourrures;
  final int rouleauxMembrane;
  final double aireMembranePi2;
  final double aireRevetementPi2;
  final List<String> avertissements;

  const ResultatMurs({
    required this.parametres,
    required this.murs,
    required this.boisOssature,
    required this.boisLinteaux,
    required this.precoupes,
    required this.decoupePanneaux,
    required this.feuillesUtilisees,
    required this.feuillesACommander,
    required this.fourrures,
    required this.rouleauxMembrane,
    required this.aireMembranePi2,
    required this.aireRevetementPi2,
    required this.avertissements,
  });

  int compter(TypeMembre t) => murs.fold(0, (a, m) => a + m.compter(t));
}

// =============================================================================
// Calcul d'un mur
// =============================================================================

const double _epLisse = 1.5;

class _Zone {
  final double a, b;
  const _Zone(this.a, this.b);
  bool chevauche(double x0, double x1) => x0 < b - 1e-9 && x1 > a + 1e-9;
}

ResultatMur _calculerMur(SpecMur spec, ParametresMurs p, int indice) {
  final avert = <String>[];
  final sec = p.section;
  final t = sec.epaisseur;
  final d = sec.profondeur;
  final longueur = spec.longueur;
  final h = spec.hauteur;
  final lissesHaut = p.lissesHautes * _epLisse;
  final longMontant = h - _epLisse - lissesHaut;

  if (!(longueur >= 6 && longueur <= 1200)) {
    throw SpecInvalide('${spec.nom} : longueur entre 6 po et 100 pi.');
  }
  if (!(h >= 24 && h <= 240)) {
    throw SpecInvalide('${spec.nom} : hauteur entre 2 et 20 pi.');
  }
  if (longMontant <= 3) {
    throw SpecInvalide('${spec.nom} : hauteur trop courte pour ces lisses.');
  }
  if (spec.ouvertures.isNotEmpty && p.plisLinteau * t > d + 1e-6) {
    throw SpecInvalide(
      '${spec.nom} : ${p.plisLinteau} épaisseurs de linteau (${formatImperial(p.plisLinteau * t)}) '
      'ne tiennent pas dans un mur de ${formatImperial(d)}.',
    );
  }
  if (spec.montantsCoinDebut < 0 ||
      spec.montantsCoinDebut > 3 ||
      spec.montantsCoinFin < 0 ||
      spec.montantsCoinFin > 3) {
    throw SpecInvalide('${spec.nom} : montants de coin de 0 à 3.');
  }
  if (spec.intersections.length > 10 ||
      spec.intersections.any((x) => !(x >= 6 && x <= longueur - 6))) {
    throw SpecInvalide(
      '${spec.nom} : intersections en T : 10 au plus, à l\'intérieur du mur.',
    );
  }

  final membres = <Membre>[];
  void ajouter(
    TypeMembre type,
    double x0,
    double x1,
    double z0,
    double z1,
    double longueurCoupe, {
    double y0 = 0,
    double? y1,
  }) {
    membres.add(
      Membre(
        type: type,
        x0: x0,
        x1: x1,
        y0: y0,
        y1: y1 ?? d,
        z0: z0,
        z1: z1,
        longueurCoupe: longueurCoupe,
        section: sec.nom,
      ),
    );
  }

  // --- Extrémités : montant d'extrémité + montants de coin ------------------
  final reculDebut = _reculOnglet(spec.angleDebut, d);
  final reculFin = _reculOnglet(spec.angleFin, d);
  final largeurDebut = reculDebut + t * (1 + spec.montantsCoinDebut);
  final largeurFin = reculFin + t * (1 + spec.montantsCoinFin);
  for (var i = 0; i <= spec.montantsCoinDebut; i++) {
    ajouter(
      i == 0 ? TypeMembre.montant : TypeMembre.montantCoin,
      reculDebut + i * t,
      reculDebut + (i + 1) * t,
      _epLisse,
      _epLisse + longMontant,
      longMontant,
    );
  }
  for (var i = 0; i <= spec.montantsCoinFin; i++) {
    ajouter(
      i == 0 ? TypeMembre.montant : TypeMembre.montantCoin,
      longueur - reculFin - (i + 1) * t,
      longueur - reculFin - i * t,
      _epLisse,
      _epLisse + longMontant,
      longMontant,
    );
  }

  // --- Ouvertures : validation et zones -------------------------------------
  final ouvertures = [...spec.ouvertures]
    ..sort((a, b) => a.position.compareTo(b.position));
  final zones = <_Zone>[];
  final jacksW = p.jacksParCote * t;
  for (final o in ouvertures) {
    if (!(o.largeurCadre > 0 && o.hauteurCadre > 0)) {
      throw SpecInvalide('${spec.nom} : ${o.libelle} : dimensions invalides.');
    }
    if (!(o.jeuLargeur >= 0 && o.jeuLargeur <= 6) ||
        !(o.jeuHauteur >= 0 && o.jeuHauteur <= 6)) {
      throw SpecInvalide('${spec.nom} : ${o.libelle} : jeux invalides.');
    }
    if (!(o.allege >= 0 && o.allege < 240)) {
      throw SpecInvalide(
        '${spec.nom} : ${o.libelle} : hauteur d\'allège invalide.',
      );
    }
    final zoneG = o.baieG - jacksW - t;
    final zoneD = o.baieD + jacksW + t;
    if (zoneG < largeurDebut - 1e-6) {
      throw SpecInvalide(
        '${spec.nom} : ${o.libelle} trop près du début du mur (il faut au moins '
        '${formatImperial(largeurDebut + t + jacksW)} entre le bout du mur et la baie).',
      );
    }
    if (zoneD > longueur - largeurFin + 1e-6) {
      throw SpecInvalide(
        '${spec.nom} : ${o.libelle} trop près de la fin du mur (il faut au moins '
        '${formatImperial(largeurFin + t + jacksW)} entre la baie et le bout du mur).',
      );
    }
    final zoneNeuve = _Zone(zoneG, zoneD);
    for (final z in zones) {
      if (zoneNeuve.chevauche(z.a, z.b)) {
        throw SpecInvalide(
          '${spec.nom} : ${o.libelle} chevauche une autre ouverture (laissez au moins '
          '${formatImperial(2 * (jacksW + t))} entre deux baies).',
        );
      }
    }
    zones.add(zoneNeuve);
    if (o.baieBas < -1e-9) {
      throw SpecInvalide(
        '${spec.nom} : ${o.libelle} : l\'allège est plus basse que le jeu du bas.',
      );
    }
    final hautLinteau = o.baieHaut + p.linteau.profondeur;
    if (hautLinteau > h - lissesHaut + 1e-6) {
      throw SpecInvalide(
        '${spec.nom} : ${o.libelle} : le linteau ${p.linteau.nom} dépasse sous la lisse haute '
        '(dessus du linteau à ${formatImperial(hautLinteau)}, lisse à ${formatImperial(h - lissesHaut)}). '
        'Choisissez un linteau moins profond ou un mur plus haut.',
      );
    }
    // Jeux de la fiche GCR.
    final jl = o.jeuLargeur, jh = o.jeuHauteur;
    if (jl < JeuxBaie.largeurMin - 1e-6 || jl > JeuxBaie.largeurMax + 1e-6) {
      avert.add(
        '${o.libelle} : jeu en largeur de ${formatImperial(jl)} hors de la plage GCR '
        '(${formatImperial(JeuxBaie.largeurMin)} à ${formatImperial(JeuxBaie.largeurMax)}).',
      );
    }
    if (jh < JeuxBaie.hauteurMin - 1e-6 || jh > JeuxBaie.hauteurMax + 1e-6) {
      avert.add(
        '${o.libelle} : jeu en hauteur de ${formatImperial(jh)} hors de la plage GCR '
        '(${formatImperial(JeuxBaie.hauteurMin)} à ${formatImperial(JeuxBaie.hauteurMax)}).',
      );
    }
  }

  // --- Intersections en T : un montant d'appui de part et d'autre de la cloison
  // (les faces d'une cloison de 3 1/2 po sont à 1 3/4 po de son axe).
  final reserves = <_Zone>[];
  for (final c in spec.intersections) {
    for (final cote in [-1, 1]) {
      final centre = c + cote * (1.75 + t / 2);
      final zone = _Zone(centre - t / 2, centre + t / 2);
      if (zone.a < largeurDebut - 1e-6 ||
          zone.b > longueur - largeurFin + 1e-6) {
        throw SpecInvalide(
          '${spec.nom} : intersection en T trop près d\'un coin.',
        );
      }
      for (final z in zones) {
        if (zone.chevauche(z.a, z.b)) {
          throw SpecInvalide(
            '${spec.nom} : intersection en T trop près d\'une ouverture.',
          );
        }
      }
      for (final z in reserves) {
        if (zone.chevauche(z.a, z.b)) {
          throw SpecInvalide(
            '${spec.nom} : deux intersections en T trop rapprochées.',
          );
        }
      }
      reserves.add(zone);
    }
  }

  // --- Montants courants (entraxe depuis le début du mur) --------------------
  // Montants de coin et d'extrémité déjà posés ; ceux qui touchent une zone
  // d'ouverture sont remplacés par les rois et les jacks, ceux qui touchent un
  // montant d'appui de cloison sont retirés (le montant d'appui les remplace).
  final cripplesParOuverture = <int, List<double>>{};
  for (var k = 1; ; k++) {
    final c = k * p.espacement;
    if (c + t / 2 > longueur - largeurFin + 1e-9) {
      break;
    }
    final x0 = c - t / 2, x1 = c + t / 2;
    if (x0 < largeurDebut - 1e-9) {
      continue;
    }
    var retire = reserves.any((z) => z.chevauche(x0, x1));
    for (var i = 0; i < ouvertures.length && !retire; i++) {
      final o = ouvertures[i];
      final zg = o.baieG - jacksW - t, zd = o.baieD + jacksW + t;
      if (x1 > zg + 1e-9 && x0 < zd - 1e-9) {
        // Dans la baie : court montant ; sur un roi ou un jack : retiré.
        if (x0 >= o.baieG - 1e-9 && x1 <= o.baieD + 1e-9) {
          cripplesParOuverture.putIfAbsent(i, () => []).add(c);
        }
        retire = true;
        break;
      }
    }
    if (!retire) {
      ajouter(
        TypeMembre.montant,
        x0,
        x1,
        _epLisse,
        _epLisse + longMontant,
        longMontant,
      );
    }
  }

  // Montants d'appui des intersections en T.
  for (final z in reserves) {
    ajouter(
      TypeMembre.montantCoin,
      z.a,
      z.b,
      _epLisse,
      _epLisse + longMontant,
      longMontant,
    );
  }

  // --- Chaque ouverture : rois, jacks, linteau, appui, courts montants -------
  for (var i = 0; i < ouvertures.length; i++) {
    final o = ouvertures[i];
    final baieG = o.baieG, baieD = o.baieD;
    final bas = o.baieBas, haut = o.baieHaut;
    // Rois (pleine hauteur) et jacks (jusqu'au dessous du linteau).
    for (final cote in [-1, 1]) {
      final bord = cote < 0 ? baieG : baieD;
      for (var j = 0; j < p.jacksParCote; j++) {
        final x0 = cote < 0 ? bord - (j + 1) * t : bord + j * t;
        ajouter(TypeMembre.jack, x0, x0 + t, _epLisse, haut, haut - _epLisse);
      }
      final xRoi = cote < 0 ? bord - jacksW - t : bord + jacksW;
      ajouter(
        TypeMembre.roi,
        xRoi,
        xRoi + t,
        _epLisse,
        _epLisse + longMontant,
        longMontant,
      );
    }
    // Linteau : sur les jacks, de la baie + les jacks, en plis côte à côte.
    final longLinteau = o.largeurBaie + 2 * jacksW;
    // Plis répartis sur l'épaisseur du mur (cales isolantes entre les plis).
    for (var j = 0; j < p.plisLinteau; j++) {
      final y = p.plisLinteau == 1
          ? (d - t) / 2
          : j * (d - t) / (p.plisLinteau - 1);
      ajouter(
        TypeMembre.linteau,
        baieG - jacksW,
        baieD + jacksW,
        haut,
        haut + p.linteau.profondeur,
        longLinteau,
        y0: y,
        y1: y + t,
      );
    }
    // Courts montants au-dessus du linteau.
    final espaceHaut = h - lissesHaut - (haut + p.linteau.profondeur);
    final centres = cripplesParOuverture[i] ?? const [];
    if (espaceHaut >= 1.5 - 1e-9) {
      for (final c in centres) {
        ajouter(
          TypeMembre.courtHaut,
          c - t / 2,
          c + t / 2,
          haut + p.linteau.profondeur,
          h - lissesHaut,
          espaceHaut,
        );
      }
    } else if (espaceHaut > 1e-9) {
      avert.add(
        '${o.libelle} : ${formatImperial(espaceHaut)} entre le linteau et la lisse haute : '
        'pas de court montant ; le linteau se pose sous la lisse (cale de ${formatImperial(espaceHaut)}).',
      );
    }
    // Fenêtre : appui et courts montants sous l'appui.
    if (o.type == TypeOuverture.fenetre) {
      for (var j = 0; j < p.plisAppui; j++) {
        ajouter(
          TypeMembre.appui,
          baieG,
          baieD,
          bas - (j + 1) * _epLisse,
          bas - j * _epLisse,
          o.largeurBaie,
        );
      }
      final dessous = bas - p.plisAppui * _epLisse - _epLisse;
      if (dessous >= 1.5 - 1e-9) {
        for (final c in centres) {
          ajouter(
            TypeMembre.courtBas,
            c - t / 2,
            c + t / 2,
            _epLisse,
            _epLisse + dessous,
            dessous,
          );
        }
      } else if (dessous < -1e-9) {
        throw SpecInvalide(
          '${spec.nom} : ${o.libelle} : l\'allège est trop basse pour l\'appui.',
        );
      }
    }
  }

  // --- Lisses ---------------------------------------------------------------
  // Basse : coupée aux portes. Hautes : sur toute la longueur.
  final trouesPortes = <(double, double)>[
    for (final o in ouvertures)
      if (o.type == TypeOuverture.porte) (o.baieG, o.baieD),
  ];
  var debut = 0.0;
  final segments = <(double, double)>[];
  for (final (a, b) in trouesPortes) {
    if (a - debut > 1e-6) {
      segments.add((debut, a));
    }
    debut = b;
  }
  if (longueur - debut > 1e-6) {
    segments.add((debut, longueur));
  }
  for (final (a, b) in segments) {
    ajouter(TypeMembre.lisseBasse, a, b, 0, _epLisse, b - a);
  }
  for (var j = 0; j < p.lissesHautes; j++) {
    ajouter(
      TypeMembre.lisseHaute,
      0,
      longueur,
      h - (p.lissesHautes - j) * _epLisse,
      h - (p.lissesHautes - j - 1) * _epLisse,
      longueur,
    );
  }

  // --- Aires ----------------------------------------------------------------
  final couverture = h + p.debordPlancher;
  // Couches extérieures : de sommet à sommet quand le mur s'appuie sur un autre.
  final xDebut = -spec.retraitDebut;
  final xFin = longueur + spec.retraitFin;
  final aireBrute = (xFin - xDebut) * couverture;
  var aireOuvertures = 0.0;
  for (final o in ouvertures) {
    aireOuvertures += o.largeurBaie * o.hauteurBaie;
  }
  final aireNette = math.max(0.0, aireBrute - aireOuvertures);

  // --- Feuilles : colonnes sur les montants, rangées de la longueur du panneau
  final panneaux = <PosePanneauMur>[];
  // Les feuilles sont posées sur toute la hauteur, ouvertures comprises (les
  // baies sont découpées après la pose) ; chaque joint vertical tombe sur le
  // centre d'un montant, d'un roi, d'un jack ou d'un court montant. Dans une
  // baie, un joint est aussi appuyé par le linteau et par l'appui.
  final candidats = <double>{};
  for (final m in membres) {
    if (m.type == TypeMembre.montant ||
        m.type == TypeMembre.montantCoin ||
        m.type == TypeMembre.roi ||
        m.type == TypeMembre.jack ||
        m.type == TypeMembre.courtHaut ||
        m.type == TypeMembre.courtBas) {
      candidats.add(((m.x0 + m.x1) / 2 * 1e6).roundToDouble() / 1e6);
    }
  }
  for (var k = 1; k * p.espacement < longueur; k++) {
    final c = k * p.espacement;
    if (ouvertures.any((o) => c > o.baieG + 1e-9 && c < o.baieD - 1e-9)) {
      candidats.add(c);
    }
  }
  final xs = candidats.toList()..sort();
  final colonnes = <(double, double)>[];
  var cur = xDebut;
  final largeurPanneau = p.panneau.largeur;
  const dernierMin = 12.0;
  while (xFin - cur > largeurPanneau + 1e-6) {
    // Le plus loin possible, sans laisser moins de 12 po pour la dernière
    // colonne (une bande si étroite se coupe mal).
    final limite = math.min(cur + largeurPanneau, xFin - dernierMin);
    final options = xs.where((x) => x > cur + 6 && x <= limite + 1e-6).toList();
    final double suivant;
    if (options.isNotEmpty) {
      suivant = options.last;
    } else {
      suivant = math.min(cur + largeurPanneau, xFin - dernierMin);
      avert.add(
        '${spec.nom} : un joint de feuille à ${formatImperial(suivant)} ne tombe '
        'sur aucun montant ; ajoutez une entremise ou un montant.',
      );
    }
    colonnes.add((cur, suivant));
    cur = suivant;
  }
  colonnes.add((cur, xFin));

  final longueurPanneau = p.panneau.longueur;
  final zBas = -p.debordPlancher;
  final rangees = <(double, double)>[];
  if (couverture <= longueurPanneau + 1e-6) {
    rangees.add((zBas, h));
  } else {
    var haut1 = zBas + longueurPanneau;
    if (h - haut1 < 6) {
      haut1 = h - 6;
    }
    rangees.add((zBas, haut1));
    rangees.add((haut1, h));
    avert.add(
      '${spec.nom} : le mur est plus haut que le panneau (${formatImperial(longueurPanneau)}) : '
      'joint horizontal à ${formatImperial(haut1)} (prévoir des entremises).',
    );
  }
  for (var c = 0; c < colonnes.length; c++) {
    for (var r = 0; r < rangees.length; r++) {
      final (x0, x1) = colonnes[c];
      final (z0, z1) = rangees[r];
      // Ouvertures qui traversent cette pièce.
      final traversees = [
        for (final o in ouvertures)
          if (o.baieG < x1 - 1e-6 &&
              o.baieD > x0 + 1e-6 &&
              o.baieBas < z1 - 1e-6 &&
              o.baieHaut > z0 + 1e-6)
            o,
      ];
      final pleines = [
        for (final o in traversees)
          if (o.baieG <= x0 + 1e-6 && o.baieD >= x1 - 1e-6) o,
      ];
      if (pleines.isNotEmpty) {
        // L'ouverture couvre toute la largeur : une pièce en dessous, une au-dessus.
        final o = pleines.first;
        final dessous = math.min(z1, o.baieBas) - z0;
        final dessus = z1 - math.max(z0, o.baieHaut);
        if (dessous > 0.5) {
          panneaux.add(
            PosePanneauMur(
              mur: indice,
              colonne: c,
              rangee: r,
              x0: x0,
              x1: x1,
              z0: z0,
              z1: z0 + dessous,
              decoupes: const [],
              feuille: -1,
            ),
          );
        }
        if (dessus > 0.5) {
          panneaux.add(
            PosePanneauMur(
              mur: indice,
              colonne: c,
              rangee: r,
              x0: x0,
              x1: x1,
              z0: z1 - dessus,
              z1: z1,
              decoupes: const [],
              feuille: -1,
            ),
          );
        }
      } else {
        panneaux.add(
          PosePanneauMur(
            mur: indice,
            colonne: c,
            rangee: r,
            x0: x0,
            x1: x1,
            z0: z0,
            z1: z1,
            decoupes: [
              for (final o in traversees)
                (
                  math.max(x0, o.baieG),
                  math.min(x1, o.baieD),
                  math.max(z0, o.baieBas),
                  math.min(z1, o.baieHaut),
                ),
            ],
            feuille: -1,
          ),
        );
      }
    }
  }

  // Entremises aux joints horizontaux (entre les montants).
  if (rangees.length > 1) {
    final jointZ = rangees[0].$2;
    final montants =
        membres
            .where(
              (m) =>
                  (m.type == TypeMembre.montant ||
                      m.type == TypeMembre.montantCoin ||
                      m.type == TypeMembre.roi ||
                      m.type == TypeMembre.jack) &&
                  m.z0 < jointZ &&
                  m.z1 > jointZ,
            )
            .toList()
          ..sort((a, b) => a.x0.compareTo(b.x0));
    for (var i = 0; i + 1 < montants.length; i++) {
      final ecart = montants[i + 1].x0 - montants[i].x1;
      if (ecart > 0.5 && ecart <= p.espacement + 1) {
        ajouter(
          TypeMembre.entremise,
          montants[i].x1,
          montants[i + 1].x0,
          jointZ - t / 2,
          jointZ + t / 2,
          ecart,
        );
      }
    }
  }

  // --- Fourrures ------------------------------------------------------------
  // Verticales à l'entraxe choisi (sur les montants) et le long des bouts ;
  // autour de chaque baie : un cadre (côtés, dessus, dessous de la fenêtre), les
  // verticales courantes s'arrêtent contre ce cadre.
  final fourrures = <PieceFourrure>[];
  final fl = p.fourrureLargeur;
  final centres = <double>[xDebut + fl / 2, xFin - fl / 2];
  for (var k = (xDebut / p.fourrureEntraxe).floor(); ; k++) {
    final c = k * p.fourrureEntraxe;
    if (c >= xFin - fl / 2 - 1e-9) {
      break;
    }
    if (c - fl / 2 >= xDebut - 1e-9 &&
        centres.every((e) => (e - c).abs() >= fl - 1e-9)) {
      centres.add(c);
    }
  }
  centres.sort();
  for (final c in centres) {
    // Intervalles de hauteur libres, après avoir retiré les cadres des baies.
    var libres = <(double, double)>[(zBas, h)];
    for (final o in ouvertures) {
      if (c + fl / 2 > o.baieG - fl + 1e-9 &&
          c - fl / 2 < o.baieD + fl - 1e-9) {
        final bas = o.type == TypeOuverture.porte ? zBas : o.baieBas - fl;
        final haut = o.baieHaut + fl;
        libres = [
          for (final (a, b) in libres) ...[
            if (math.min(b, bas) - a > 0) (a, math.min(b, bas)),
            if (b - math.max(a, haut) > 0) (math.max(a, haut), b),
          ],
        ];
      }
    }
    for (final (a, b) in libres) {
      if (b - a > 1) {
        fourrures.add(PieceFourrure(c - fl / 2, c + fl / 2, a, b, true));
      }
    }
  }
  for (final o in ouvertures) {
    // Côtés (montants du cadre), dessus et, pour une fenêtre, dessous.
    fourrures.add(
      PieceFourrure(o.baieG - fl, o.baieG, o.baieBas, o.baieHaut, true),
    );
    fourrures.add(
      PieceFourrure(o.baieD, o.baieD + fl, o.baieBas, o.baieHaut, true),
    );
    fourrures.add(
      PieceFourrure(
        o.baieG - fl,
        o.baieD + fl,
        o.baieHaut,
        o.baieHaut + fl,
        false,
      ),
    );
    if (o.type == TypeOuverture.fenetre) {
      fourrures.add(
        PieceFourrure(
          o.baieG - fl,
          o.baieD + fl,
          o.baieBas - fl,
          o.baieBas,
          false,
        ),
      );
    }
  }

  return ResultatMur(
    spec: spec,
    membres: membres,
    panneaux: panneaux,
    fourrures: fourrures,
    aireBrutePo2: aireBrute,
    aireNettePo2: aireNette,
    avertissements: avert,
  );
}

// =============================================================================
// Calcul de tous les murs
// =============================================================================

bool _estPrecoupe(double l) =>
    montantsPrecoupes.any((m) => (m - l).abs() < 1 / 16 + 1e-9);

/// Calcule les murs et le bois, les feuilles, les fourrures et le revêtement à
/// commander. Lance [SpecInvalide] si une donnée est invalide.
ResultatMurs calculerMurs(List<SpecMur> specs, ParametresMurs params) {
  params.valider();
  if (specs.isEmpty) {
    throw const SpecInvalide('Ajoutez au moins un mur.');
  }
  if (specs.length > 40) {
    throw const SpecInvalide('40 murs au maximum.');
  }
  final avert = <String>[];
  final murs = [
    for (var i = 0; i < specs.length; i++) _calculerMur(specs[i], params, i),
  ];
  for (final m in murs) {
    avert.addAll(m.avertissements);
  }

  // --- Bois de l'ossature -----------------------------------------------------
  final piecesOssature = <PieceCoupe>[];
  final piecesLinteaux = <PieceCoupe>[];
  final precoupes = <double, int>{};
  // Montants et jacks : une planche chacun (on achète des 8 pi, pas des 16 pi à
  // couper en deux) ; les chutes servent aux courts montants.
  final unParPlanche = <String>{};
  var n = 0;
  for (final m in murs) {
    for (final b in m.membres) {
      switch (b.type) {
        case TypeMembre.linteau:
          piecesLinteaux.add(PieceCoupe('l${n++}', b.longueurCoupe, 'linteau'));
        case TypeMembre.montant || TypeMembre.montantCoin || TypeMembre.roi:
          if (params.precoupes && _estPrecoupe(b.longueurCoupe)) {
            final cle = montantsPrecoupes.firstWhere(
              (x) => (x - b.longueurCoupe).abs() < 1 / 16 + 1e-9,
            );
            precoupes[cle] = (precoupes[cle] ?? 0) + 1;
          } else {
            unParPlanche.add('m$n');
            piecesOssature.add(
              PieceCoupe('m${n++}', b.longueurCoupe, libelleMembre(b.type)),
            );
          }
        case TypeMembre.jack:
          unParPlanche.add('m$n');
          piecesOssature.add(
            PieceCoupe('m${n++}', b.longueurCoupe, libelleMembre(b.type)),
          );
        default:
          piecesOssature.add(
            PieceCoupe('m${n++}', b.longueurCoupe, libelleMembre(b.type)),
          );
      }
    }
  }
  // Plaques plus longues que la plus longue planche : épissées (jointes) sur un montant.
  final maxPlanche = params.longueursPlanches.reduce(math.max);
  final epissees = <PieceCoupe>[];
  final aCouper = <PieceCoupe>[];
  for (final p in piecesOssature) {
    if (p.longueur > maxPlanche + 1e-9 &&
        (p.etiquette == 'Lisse basse' || p.etiquette == 'Lisse haute')) {
      final morceaux = (p.longueur / maxPlanche - 1e-9).ceil();
      for (var k = 0; k < morceaux; k++) {
        epissees.add(
          PieceCoupe('${p.id}.$k', p.longueur / morceaux, p.etiquette),
        );
      }
    } else {
      aCouper.add(p);
    }
  }
  if (epissees.isNotEmpty) {
    avert.add(
      'Une lisse dépasse la plus longue planche (${formatImperial(maxPlanche)}) : '
      'elle est épissée sur un montant ; décalez les joints des deux lisses hautes d\'au moins 4 pi.',
    );
  }
  final boisOssature = decouperPlanches(
    [...aCouper, ...epissees],
    params.longueursPlanches,
    uneParPlanche: unParPlanche,
  );
  final boisLinteaux = decouperPlanches(
    piecesLinteaux,
    params.longueursPlanches,
  );
  if (boisOssature.horsLimites.isNotEmpty ||
      boisLinteaux.horsLimites.isNotEmpty) {
    avert.add(
      'Une pièce dépasse la plus longue planche permise (${formatImperial(maxPlanche)}).',
    );
  }

  // --- Feuilles : toutes les pièces des murs dans les mêmes feuilles ---------
  final pieces = <PieceRect>[];
  final cles = <PieceRect, PosePanneauMur>{};
  for (final m in murs) {
    for (final p in m.panneaux) {
      final r = PieceRect(
        '${p.mur}.${p.colonne}.${p.rangee}.${p.z0.toStringAsFixed(3)}',
        p.hauteur,
        p.largeur,
      );
      pieces.add(r);
      cles[r] = p;
    }
  }
  final decoupe = empaqueterFeuilles(
    pieces,
    longueurFeuille: params.panneau.longueur,
    largeurFeuille: params.panneau.largeur,
  );
  final numero = <PieceRect, int>{};
  for (var i = 0; i < decoupe.feuilles.length; i++) {
    for (final pl in decoupe.feuilles[i].placements) {
      numero[pl.piece] = i;
    }
  }
  final avecFeuille = <ResultatMur>[];
  for (var i = 0; i < murs.length; i++) {
    final m = murs[i];
    final poses = <PosePanneauMur>[];
    for (final p in m.panneaux) {
      final r = pieces.firstWhere((x) => identical(cles[x], p));
      poses.add(
        PosePanneauMur(
          mur: p.mur,
          colonne: p.colonne,
          rangee: p.rangee,
          x0: p.x0,
          x1: p.x1,
          z0: p.z0,
          z1: p.z1,
          decoupes: p.decoupes,
          feuille: numero[r] ?? -1,
        ),
      );
    }
    avecFeuille.add(
      ResultatMur(
        spec: m.spec,
        membres: m.membres,
        panneaux: poses,
        fourrures: m.fourrures,
        aireBrutePo2: m.aireBrutePo2,
        aireNettePo2: m.aireNettePo2,
        avertissements: m.avertissements,
      ),
    );
  }
  if (decoupe.horsLimites.isNotEmpty) {
    avert.add(
      'Une pièce de feuille dépasse le format choisi (${params.panneau.nom}).',
    );
  }
  final utilisees = decoupe.nombre;
  final commande = params.margeFeuillesPct <= 0
      ? utilisees
      : (utilisees * (1 + params.margeFeuillesPct / 100) - 1e-9).ceil();

  // --- Fourrures ---------------------------------------------------------------
  final fourrures = <PieceCoupe>[];
  var f = 0;
  for (final m in avecFeuille) {
    for (final fo in m.fourrures) {
      fourrures.add(PieceCoupe('f${f++}', fo.longueur, 'fourrure'));
    }
  }
  final boisFourrures = decouperPlanches(fourrures, params.longueursFourrures);

  // --- Membrane et revêtement --------------------------------------------------
  final aireNette = avecFeuille.fold(0.0, (a, m) => a + m.aireNettePo2) / 144;
  final aireMembrane = aireNette * (1 + params.margeMembranePct / 100);
  final rouleaux = aireMembrane <= 0
      ? 0
      : (aireMembrane / params.aireRouleauPi2 - 1e-9).ceil();
  final aireRevetement = aireNette * (1 + params.margeRevetementPct / 100);

  return ResultatMurs(
    parametres: params,
    murs: avecFeuille,
    boisOssature: boisOssature,
    boisLinteaux: boisLinteaux,
    precoupes: Map.fromEntries(
      precoupes.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    decoupePanneaux: decoupe,
    feuillesUtilisees: utilisees,
    feuillesACommander: commande,
    fourrures: boisFourrures,
    rouleauxMembrane: rouleaux,
    aireMembranePi2: aireMembrane,
    aireRevetementPi2: aireRevetement,
    avertissements: [
      ...avert,
      'Le dimensionnement des linteaux (${params.linteau.nom} × ${params.plisLinteau}) n\'est pas vérifié : '
          'à valider avec les tables du Code de construction du Québec ou un ingénieur.',
    ],
  );
}

// =============================================================================
// Murs d'un contour (bâtiment)
// =============================================================================

/// Un mur par côté du contour (longueur mesurée sur la face extérieure).
/// Aux coins à 90°, un des deux murs passe jusqu'au coin et l'autre s'y appuie
/// (alternance autour du bâtiment) : le mur qui s'appuie est raccourci de la
/// profondeur de l'autre et reçoit 1 montant de coin (coin à 3 montants). Aux
/// coins rentrants à 270°, le mur qui passe est prolongé de la profondeur de
/// l'autre, qui s'y appuie avec 1 montant de plus. Aux autres angles, les deux
/// murs vont jusqu'au sommet (coupes d'onglet, pointe longue) et reçoivent
/// chacun 1 montant de plus.
List<SpecMur> mursDuContour(
  Polygone contour, {
  required double hauteur,
  SectionBois section = section2x4,
}) {
  final n = contour.nombre;
  final retraitDebut = List<double>.filled(n, 0);
  final retraitFin = List<double>.filled(n, 0);
  final coinDebut = List<int>.filled(n, 0);
  final coinFin = List<int>.filled(n, 0);
  final angleDebut = List<double?>.filled(n, null);
  final angleFin = List<double?>.filled(n, null);
  for (var k = 0; k < n; k++) {
    // Sommet k : entre le côté k-1 (qui y finit) et le côté k (qui y commence).
    final avant = (k - 1 + n) % n;
    final angle = contour.angleInterieurDeg(k);
    if ((angle - 90).abs() < 0.5) {
      if (k.isEven) {
        retraitDebut[k] =
            section.profondeur; // le côté k s'appuie sur le côté k-1
        coinDebut[k] = 1;
      } else {
        retraitFin[avant] = section.profondeur;
        coinFin[avant] = 1;
      }
    } else if ((angle - 270).abs() < 0.5) {
      // Coin rentrant : les deux ossatures ne se touchent que par le sommet ;
      // le mur qui passe est prolongé de la profondeur de l'autre, qui s'y appuie.
      if (k.isEven) {
        retraitFin[avant] = -section.profondeur;
        coinDebut[k] = 1;
      } else {
        retraitDebut[k] = -section.profondeur;
        coinFin[avant] = 1;
      }
    } else {
      coinDebut[k] = 1;
      coinFin[avant] = 1;
    }
    angleDebut[k] = angle;
    angleFin[avant] = angle;
  }
  return [
    for (var i = 0; i < n; i++)
      SpecMur(
        nom: 'Mur ${i + 1}',
        longueur: contour.longueurCote(i) - retraitDebut[i] - retraitFin[i],
        hauteur: hauteur,
        montantsCoinDebut: coinDebut[i],
        montantsCoinFin: coinFin[i],
        cote: i,
        retraitDebut: retraitDebut[i],
        retraitFin: retraitFin[i],
        angleDebut: angleDebut[i],
        angleFin: angleFin[i],
      ),
  ];
}

const espacementsMontants = espacementsStandards;
