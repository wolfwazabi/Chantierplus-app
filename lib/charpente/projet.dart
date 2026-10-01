import 'commande.dart';
import 'geometrie.dart';
import 'mur.dart';
import 'panneaux.dart';
import 'plancher.dart';
import 'scene.dart';
import 'unites.dart';

/// Projet de charpente : plancher, murs, paramètres. Tout ce que l'utilisateur
/// règle, sérialisable en JSON (assistant, commandes enregistrées), et le calcul
/// complet qui en découle (plancher, murs, scène 3D, liste d'achat).

// =============================================================================
// Forme du plancher
// =============================================================================

sealed class FormePlancher {
  const FormePlancher();

  /// Contour du plancher. Lance [FormeInvalide] si la forme est impossible.
  Polygone construire();

  Map<String, dynamic> toJson();

  static FormePlancher fromJson(Object? j) {
    if (j is! Map) {
      throw const FormatException('forme invalide');
    }
    switch (j['type']) {
      case 'rectangle':
        return FormeRectangle(
          _num(j, 'longueur', 1, pouceMaxSaisie),
          _num(j, 'largeur', 1, pouceMaxSaisie),
        );
      case 'cotes':
        final cotes = _liste(
          j,
          'cotes',
          2,
          23,
          (e) => _nombre(e, 0.01, pouceMaxSaisie),
        );
        final angles = _liste(
          j,
          'angles',
          1,
          22,
          (e) => _nombre(e, 0.01, 359.99),
        );
        return FormeCotesAngles(cotes, angles);
      case 'points':
        final pts = _liste(j, 'points', 3, 24, (e) {
          if (e is! List || e.length != 2) {
            throw const FormatException('point invalide');
          }
          return Pt(
            _nombre(e[0], -pouceMaxSaisie, pouceMaxSaisie),
            _nombre(e[1], -pouceMaxSaisie, pouceMaxSaisie),
          );
        });
        return FormePoints(pts);
    }
    throw const FormatException('type de forme inconnu');
  }
}

class FormeRectangle extends FormePlancher {
  final double longueur;
  final double largeur;
  const FormeRectangle(this.longueur, this.largeur);

  @override
  Polygone construire() {
    if (!(longueur > 0 && largeur > 0)) {
      throw const FormeInvalide('Longueur et largeur doivent dépasser 0.');
    }
    return Polygone.rectangle(longueur, largeur);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rectangle',
    'longueur': longueur,
    'largeur': largeur,
  };
}

/// Côté 1, angle 1, côté 2, angle 2, … côté k : le dernier côté et les deux
/// derniers angles sont déduits pour fermer la forme (k + 1 côtés en tout).
class FormeCotesAngles extends FormePlancher {
  final List<double> cotes;
  final List<double> angles;
  const FormeCotesAngles(this.cotes, this.angles);

  @override
  Polygone construire() => Polygone.deCotesEtAngles(cotes, angles);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cotes',
    'cotes': cotes,
    'angles': angles,
  };
}

class FormePoints extends FormePlancher {
  final List<Pt> points;
  const FormePoints(this.points);

  @override
  Polygone construire() => Polygone(points);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'points',
    'points': [
      for (final p in points) [p.x, p.y],
    ],
  };
}

// =============================================================================
// Projet
// =============================================================================

class ParametresPlancher {
  final FormePlancher forme;
  final double espacement;

  /// Direction des solives en degrés ; null : automatique (portée la plus courte).
  final double? angleSolivesDeg;
  final SectionBois section;
  final bool solivesDoublesAuxCotes;
  final bool riveDouble;
  final ModeEtriers etriers;
  final int rangeesEntremises;
  final FormatPanneau panneau;
  final double decalageMin;
  final double margePanneauxPourcent;
  final List<double> longueursPlanches;

  const ParametresPlancher({
    this.forme = const FormeRectangle(156, 126),
    this.espacement = 16,
    this.angleSolivesDeg,
    this.section = section2x10,
    this.solivesDoublesAuxCotes = false,
    this.riveDouble = false,
    this.etriers = ModeEtriers.deuxBouts,
    this.rangeesEntremises = 0,
    this.panneau = panneau4x8,
    this.decalageMin = 24,
    this.margePanneauxPourcent = 0,
    this.longueursPlanches = longueursPlanchesParDefaut,
  });

  ParametresPlancher copieAvec({
    FormePlancher? forme,
    double? espacement,
    double? Function()? angleSolivesDeg,
    SectionBois? section,
    bool? solivesDoublesAuxCotes,
    bool? riveDouble,
    ModeEtriers? etriers,
    int? rangeesEntremises,
    FormatPanneau? panneau,
    double? decalageMin,
    double? margePanneauxPourcent,
    List<double>? longueursPlanches,
  }) => ParametresPlancher(
    forme: forme ?? this.forme,
    espacement: espacement ?? this.espacement,
    angleSolivesDeg: angleSolivesDeg != null
        ? angleSolivesDeg()
        : this.angleSolivesDeg,
    section: section ?? this.section,
    solivesDoublesAuxCotes:
        solivesDoublesAuxCotes ?? this.solivesDoublesAuxCotes,
    riveDouble: riveDouble ?? this.riveDouble,
    etriers: etriers ?? this.etriers,
    rangeesEntremises: rangeesEntremises ?? this.rangeesEntremises,
    panneau: panneau ?? this.panneau,
    decalageMin: decalageMin ?? this.decalageMin,
    margePanneauxPourcent: margePanneauxPourcent ?? this.margePanneauxPourcent,
    longueursPlanches: longueursPlanches ?? this.longueursPlanches,
  );

  SpecPlancher versSpec(Polygone contour) => SpecPlancher(
    forme: contour,
    espacement: espacement,
    angleSolivesDeg: angleSolivesDeg,
    epaisseurSolive: section.epaisseur,
    epaisseurRive: section.epaisseur,
    solivesDoublesAuxCotes: solivesDoublesAuxCotes,
    riveDouble: riveDouble,
    etriers: etriers,
    rangeesEntremises: rangeesEntremises,
    longueursPlanches: longueursPlanches,
    panneau: panneau,
    decalageMin: decalageMin,
    margePanneauxPourcent: margePanneauxPourcent,
  );
}

enum ModeMurs { contour, libres }

class ParametresMursProjet {
  final ModeMurs mode;

  /// Hauteur des murs du contour.
  final double hauteur;

  /// Murs du contour : ouvertures de chaque côté (indice du côté du contour).
  final Map<int, List<Ouverture>> ouverturesContour;

  /// Murs libres (isolés ou cloisons).
  final List<SpecMur> libres;
  final ParametresMurs params;

  const ParametresMursProjet({
    this.mode = ModeMurs.contour,
    this.hauteur = 97.125,
    this.ouverturesContour = const {},
    this.libres = const [],
    this.params = const ParametresMurs(),
  });

  ParametresMursProjet copieAvec({
    ModeMurs? mode,
    double? hauteur,
    Map<int, List<Ouverture>>? ouverturesContour,
    List<SpecMur>? libres,
    ParametresMurs? params,
  }) => ParametresMursProjet(
    mode: mode ?? this.mode,
    hauteur: hauteur ?? this.hauteur,
    ouverturesContour: ouverturesContour ?? this.ouverturesContour,
    libres: libres ?? this.libres,
    params: params ?? this.params,
  );
}

class ProjetCharpente {
  final String nom;
  final bool plancherActif;
  final ParametresPlancher plancher;
  final bool mursActifs;
  final ParametresMursProjet murs;

  const ProjetCharpente({
    this.nom = '',
    this.plancherActif = true,
    this.plancher = const ParametresPlancher(),
    this.mursActifs = false,
    this.murs = const ParametresMursProjet(),
  });

  ProjetCharpente copieAvec({
    String? nom,
    bool? plancherActif,
    ParametresPlancher? plancher,
    bool? mursActifs,
    ParametresMursProjet? murs,
  }) => ProjetCharpente(
    nom: nom ?? this.nom,
    plancherActif: plancherActif ?? this.plancherActif,
    plancher: plancher ?? this.plancher,
    mursActifs: mursActifs ?? this.mursActifs,
    murs: murs ?? this.murs,
  );

  // ---------------------------------------------------------------------------
  // JSON
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'v': 1,
    'nom': nom,
    'plancherActif': plancherActif,
    'plancher': {
      'forme': plancher.forme.toJson(),
      'espacement': plancher.espacement,
      'angle': plancher.angleSolivesDeg,
      'section': plancher.section.nom,
      'bordureDouble': plancher.solivesDoublesAuxCotes,
      'riveDouble': plancher.riveDouble,
      'etriers': plancher.etriers.name,
      'entremises': plancher.rangeesEntremises,
      'panneau': plancher.panneau.id,
      'decalageMin': plancher.decalageMin,
      'marge': plancher.margePanneauxPourcent,
      'longueursPlanches': plancher.longueursPlanches,
    },
    'mursActifs': mursActifs,
    'murs': {
      'mode': murs.mode.name,
      'hauteur': murs.hauteur,
      'ouverturesContour': {
        for (final e in murs.ouverturesContour.entries)
          '${e.key}': [for (final o in e.value) _ouvertureJson(o)],
      },
      'libres': [for (final m in murs.libres) _murJson(m)],
      'params': _paramsMursJson(murs.params),
    },
  };

  /// Lit un projet. Lance [FormatException] si le contenu est mal formé ; les
  /// valeurs hors limites sont refusées plus tard par le calcul, avec un message.
  factory ProjetCharpente.fromJson(Object? j) {
    if (j is! Map) {
      throw const FormatException('projet invalide');
    }
    if (j['v'] != 1) {
      throw const FormatException('version de projet inconnue');
    }
    final nom = j['nom'] ?? '';
    if (nom is! String || nom.length > 200) {
      throw const FormatException('nom invalide');
    }
    final p = j['plancher'];
    final m = j['murs'];
    if (p is! Map || m is! Map) {
      throw const FormatException('projet incomplet');
    }
    final section = _section(p['section'], sectionsPlancher);
    final panneau = panneauParId('${p['panneau']}');
    if (panneau == null) {
      throw const FormatException('format de feuille inconnu');
    }
    final etriers = ModeEtriers.values.where((e) => e.name == p['etriers']);
    if (etriers.isEmpty) {
      throw const FormatException('étriers invalides');
    }
    final angle = p['angle'];
    final plancher = ParametresPlancher(
      forme: FormePlancher.fromJson(p['forme']),
      espacement: _num(p, 'espacement', 1, 100),
      angleSolivesDeg: angle == null ? null : _nombre(angle, -720, 720),
      section: section,
      solivesDoublesAuxCotes: _bool(p['bordureDouble']),
      riveDouble: _bool(p['riveDouble']),
      etriers: etriers.first,
      rangeesEntremises: _entier(p['entremises'], 0, 10),
      panneau: panneau,
      decalageMin: _num(p, 'decalageMin', 0, 1000),
      margePanneauxPourcent: _num(p, 'marge', 0, 100),
      longueursPlanches: _liste(
        p,
        'longueursPlanches',
        1,
        20,
        (e) => _nombre(e, 1, 1000),
      ),
    );
    final mode = ModeMurs.values.where((e) => e.name == m['mode']);
    if (mode.isEmpty) {
      throw const FormatException('mode des murs invalide');
    }
    final oc = m['ouverturesContour'];
    if (oc is! Map || oc.length > 24) {
      throw const FormatException('ouvertures invalides');
    }
    final ouverturesContour = <int, List<Ouverture>>{};
    for (final e in oc.entries) {
      final k = int.tryParse('${e.key}');
      if (k == null || k < 0 || k > 23) {
        throw const FormatException('côté invalide');
      }
      final l = e.value;
      if (l is! List || l.length > 30) {
        throw const FormatException('ouvertures invalides');
      }
      ouverturesContour[k] = [for (final o in l) _ouvertureDe(o)];
    }
    final libres = m['libres'];
    if (libres is! List || libres.length > 40) {
      throw const FormatException('murs invalides');
    }
    return ProjetCharpente(
      nom: nom,
      plancherActif: _bool(j['plancherActif']),
      plancher: plancher,
      mursActifs: _bool(j['mursActifs']),
      murs: ParametresMursProjet(
        mode: mode.first,
        hauteur: _num(m, 'hauteur', 1, 1000),
        ouverturesContour: ouverturesContour,
        libres: [for (final e in libres) _murDe(e)],
        params: _paramsMursDe(m['params']),
      ),
    );
  }
}

/// Sections permises pour les solives.
const sectionsPlancher = [section2x6, section2x8, section2x10, section2x12];

// =============================================================================
// Calcul complet
// =============================================================================

class ResultatsProjet {
  final Polygone? contour;
  final ResultatPlancher? plancher;
  final String? erreurPlancher;
  final ResultatMurs? murs;
  final String? erreurMurs;
  final Scene scene;
  final Commande commande;

  const ResultatsProjet({
    this.contour,
    this.plancher,
    this.erreurPlancher,
    this.murs,
    this.erreurMurs,
    required this.scene,
    required this.commande,
  });

  bool get aDesErreurs => erreurPlancher != null || erreurMurs != null;
}

/// Calcule le projet. Une erreur de saisie (forme impossible, ouverture trop
/// près d'un coin…) est rapportée dans le résultat, jamais lancée.
ResultatsProjet calculerProjet(ProjetCharpente p, {bool metrique = false}) {
  Polygone? contour;
  String? erreurPlancher;
  ResultatPlancher? plancher;
  // Le contour sert au plancher et aux murs du contour.
  if (p.plancherActif || (p.mursActifs && p.murs.mode == ModeMurs.contour)) {
    try {
      contour = p.plancher.forme.construire();
    } on FormeInvalide catch (e) {
      erreurPlancher = e.message;
    }
  }
  if (p.plancherActif && contour != null) {
    try {
      plancher = calculerPlancher(p.plancher.versSpec(contour));
    } on SpecInvalide catch (e) {
      erreurPlancher = e.message;
    }
  }

  ResultatMurs? murs;
  String? erreurMurs;
  if (p.mursActifs) {
    try {
      final specs = specsMurs(p, contour);
      murs = calculerMurs(specs, p.murs.params);
    } on SpecInvalide catch (e) {
      erreurMurs = e.message;
    } on FormeInvalide catch (e) {
      erreurMurs = e.message;
    }
  }

  final scene = (plancher == null && murs == null)
      ? Scene.vide
      : construireScene(
          plancher: plancher,
          sectionPlancher: p.plancher.section,
          murs: murs,
          contour: p.murs.mode == ModeMurs.contour ? contour : null,
          metrique: metrique,
        );
  final commande = construireCommande(
    plancher: plancher,
    sectionPlancher: p.plancher.section,
    murs: murs,
    metrique: metrique,
  );
  return ResultatsProjet(
    contour: contour,
    plancher: plancher,
    erreurPlancher: erreurPlancher,
    murs: murs,
    erreurMurs: erreurMurs,
    scene: scene,
    commande: commande,
  );
}

/// Murs du projet : un par côté du contour (avec leurs ouvertures), ou les
/// murs libres. Lance [SpecInvalide] si le contour manque.
List<SpecMur> specsMurs(ProjetCharpente p, Polygone? contour) {
  final m = p.murs;
  if (m.mode == ModeMurs.libres) {
    return m.libres;
  }
  if (contour == null) {
    throw const SpecInvalide(
      'Les murs du contour demandent une forme de plancher valide.',
    );
  }
  final base = mursDuContour(
    contour,
    hauteur: m.hauteur,
    section: m.params.section,
  );
  return [
    for (final b in base)
      SpecMur(
        nom: b.nom,
        longueur: b.longueur,
        hauteur: b.hauteur,
        ouvertures: m.ouverturesContour[b.cote] ?? const [],
        montantsCoinDebut: b.montantsCoinDebut,
        montantsCoinFin: b.montantsCoinFin,
        cote: b.cote,
        retraitDebut: b.retraitDebut,
        retraitFin: b.retraitFin,
        angleDebut: b.angleDebut,
        angleFin: b.angleFin,
      ),
  ];
}

// =============================================================================
// Lecture JSON : fonctions strictes
// =============================================================================

double _nombre(Object? v, double min, double max) {
  if (v is! num || !v.isFinite || v < min || v > max) {
    throw const FormatException('nombre invalide ou hors limites');
  }
  return v.toDouble();
}

double _num(Map j, String cle, double min, double max) =>
    _nombre(j[cle], min, max);

int _entier(Object? v, int min, int max) {
  if (v is! int || v < min || v > max) {
    throw const FormatException('entier invalide');
  }
  return v;
}

bool _bool(Object? v) {
  if (v is! bool) {
    throw const FormatException('booléen invalide');
  }
  return v;
}

List<T> _liste<T>(
  Map j,
  String cle,
  int min,
  int max,
  T Function(Object?) lire,
) {
  final v = j[cle];
  if (v is! List || v.length < min || v.length > max) {
    throw FormatException('liste invalide : $cle');
  }
  return [for (final e in v) lire(e)];
}

SectionBois _section(Object? nom, List<SectionBois> permises) {
  final s = permises.where((e) => e.nom == nom);
  if (s.isEmpty) {
    throw const FormatException('section inconnue');
  }
  return s.first;
}

Map<String, dynamic> _ouvertureJson(Ouverture o) => {
  'type': o.type.name,
  'nom': o.nom,
  'largeur': o.largeurCadre,
  'hauteur': o.hauteurCadre,
  'allege': o.allege,
  'position': o.position,
  'jeuLargeur': o.jeuLargeur,
  'jeuHauteur': o.jeuHauteur,
};

Ouverture _ouvertureDe(Object? j) {
  if (j is! Map) {
    throw const FormatException('ouverture invalide');
  }
  final type = TypeOuverture.values.where((e) => e.name == j['type']);
  if (type.isEmpty) {
    throw const FormatException('type d\'ouverture inconnu');
  }
  final nom = j['nom'] ?? '';
  if (nom is! String || nom.length > 60) {
    throw const FormatException('nom d\'ouverture invalide');
  }
  return Ouverture(
    type: type.first,
    nom: nom,
    largeurCadre: _num(j, 'largeur', 0.01, pouceMaxSaisie),
    hauteurCadre: _num(j, 'hauteur', 0.01, pouceMaxSaisie),
    allege: _num(j, 'allege', 0, pouceMaxSaisie),
    position: _num(j, 'position', 0, pouceMaxSaisie),
    jeuLargeur: _num(j, 'jeuLargeur', 0, 12),
    jeuHauteur: _num(j, 'jeuHauteur', 0, 12),
  );
}

Map<String, dynamic> _murJson(SpecMur m) => {
  'nom': m.nom,
  'longueur': m.longueur,
  'hauteur': m.hauteur,
  'ouvertures': [for (final o in m.ouvertures) _ouvertureJson(o)],
  'coinDebut': m.montantsCoinDebut,
  'coinFin': m.montantsCoinFin,
  'intersections': m.intersections,
};

SpecMur _murDe(Object? j) {
  if (j is! Map) {
    throw const FormatException('mur invalide');
  }
  final nom = j['nom'] ?? 'Mur';
  if (nom is! String || nom.length > 60) {
    throw const FormatException('nom de mur invalide');
  }
  final ouvertures = j['ouvertures'];
  if (ouvertures is! List || ouvertures.length > 30) {
    throw const FormatException('ouvertures invalides');
  }
  return SpecMur(
    nom: nom,
    longueur: _num(j, 'longueur', 0.01, pouceMaxSaisie),
    hauteur: _num(j, 'hauteur', 0.01, pouceMaxSaisie),
    ouvertures: [for (final o in ouvertures) _ouvertureDe(o)],
    montantsCoinDebut: _entier(j['coinDebut'], 0, 3),
    montantsCoinFin: _entier(j['coinFin'], 0, 3),
    intersections: _liste(
      j,
      'intersections',
      0,
      10,
      (e) => _nombre(e, 0, pouceMaxSaisie),
    ),
  );
}

Map<String, dynamic> _paramsMursJson(ParametresMurs p) => {
  'espacement': p.espacement,
  'section': p.section.nom,
  'lissesHautes': p.lissesHautes,
  'jacksParCote': p.jacksParCote,
  'linteau': p.linteau.nom,
  'plisLinteau': p.plisLinteau,
  'plisAppui': p.plisAppui,
  'longueursPlanches': p.longueursPlanches,
  'precoupes': p.precoupes,
  'panneau': p.panneau.id,
  'debordPlancher': p.debordPlancher,
  'fourrureEntraxe': p.fourrureEntraxe,
  'fourrureEpaisseur': p.fourrureEpaisseur,
  'fourrureLargeur': p.fourrureLargeur,
  'longueursFourrures': p.longueursFourrures,
  'revetementEpaisseur': p.revetementEpaisseur,
  'margeMembrane': p.margeMembranePct,
  'margeRevetement': p.margeRevetementPct,
  'aireRouleau': p.aireRouleauPi2,
  'margeFeuilles': p.margeFeuillesPct,
};

ParametresMurs _paramsMursDe(Object? j) {
  if (j is! Map) {
    throw const FormatException('paramètres des murs invalides');
  }
  final panneau = panneauParId('${j['panneau']}');
  if (panneau == null) {
    throw const FormatException('format de feuille inconnu');
  }
  return ParametresMurs(
    espacement: _num(j, 'espacement', 1, 100),
    section: _section(j['section'], sectionsMurs),
    lissesHautes: _entier(j['lissesHautes'], 0, 10),
    jacksParCote: _entier(j['jacksParCote'], 0, 10),
    linteau: _section(j['linteau'], sectionsLinteaux),
    plisLinteau: _entier(j['plisLinteau'], 0, 10),
    plisAppui: _entier(j['plisAppui'], 0, 10),
    longueursPlanches: _liste(
      j,
      'longueursPlanches',
      1,
      20,
      (e) => _nombre(e, 1, 1000),
    ),
    precoupes: _bool(j['precoupes']),
    panneau: panneau,
    debordPlancher: _num(j, 'debordPlancher', 0, 100),
    fourrureEntraxe: _num(j, 'fourrureEntraxe', 1, 100),
    fourrureEpaisseur: _num(j, 'fourrureEpaisseur', 0.01, 12),
    fourrureLargeur: _num(j, 'fourrureLargeur', 0.01, 12),
    longueursFourrures: _liste(
      j,
      'longueursFourrures',
      1,
      20,
      (e) => _nombre(e, 1, 1000),
    ),
    revetementEpaisseur: _num(j, 'revetementEpaisseur', 0.01, 12),
    margeMembranePct: _num(j, 'margeMembrane', 0, 100),
    margeRevetementPct: _num(j, 'margeRevetement', 0, 100),
    aireRouleauPi2: _num(j, 'aireRouleau', 1, 100000),
    margeFeuillesPct: _num(j, 'margeFeuilles', 0, 100),
  );
}
