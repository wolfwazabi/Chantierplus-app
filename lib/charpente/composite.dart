/// Produits de terrasse en composite (ou PVC) : ce que disent les guides d'installation des
/// fabricants pour des marches d'escalier et pour le dessus d'une plateforme. Tout est en POUCES. Sources : guides et fiches des
/// fabricants consultés le 13 octobre 2026 (voir [ProduitComposite.source]) ; à revérifier avec
/// le guide du produit posé, les gammes changent.
class ProduitComposite {
  /// Identifiant gardé dans les calculs enregistrés.
  final String id;
  final String marque;
  final String gamme;

  /// Planche à bord carré (marches) : largeur et épaisseur réelles.
  final double largeur;
  final double epaisseur;

  /// Écart entre deux planches côte à côte sur une marche.
  final double ecart;

  /// Écart au bout d'une planche qui finit contre une planche de cadrage (ou de transition), par
  /// temps doux ; [noteEcarts] donne le tableau du fabricant selon la température.
  final double ecartBout;
  final String noteEcarts;

  /// Le fabricant permet ses attaches cachées sur les marches (sinon : vissées en surface).
  final bool attachesSurMarches;

  /// L'attache cachée du fabricant et le nombre par boîte.
  final String attache;
  final int attachesParBoite;

  /// Vissage en surface des marches (nez et côtés, et toutes les planches sans attaches) ; avec
  /// des bouchons de la couleur, ou des vis de la couleur sans bouchon.
  final String fixationSurface;
  final bool avecBouchons;

  /// Longueurs vendues des planches à bord carré.
  final List<double> longueurs;

  /// Fascia (contremarches) : hauteurs et longueurs vendues.
  final List<double> hauteursFascia;
  final List<double> longueursFascia;

  /// Entraxe maximal des limons sous des marches de ce produit.
  final double entraxeMaxLimons;

  /// Débord maximal du nez de la marche au-delà de la contremarche.
  final double debordNezMax;

  /// Ce que le guide demande de particulier pour les marches.
  final String noteMarches;

  /// Plancher (dessus d'une plateforme) : écart entre planches côte à côte avec l'attache cachée.
  final double ecartPlancher;

  /// Longueurs vendues des planches rainurées (le centre du plancher).
  final List<double> longueursRainurees;

  /// Entraxe maximal des solives sous un plancher de ce produit, planches perpendiculaires
  /// (valeur canadienne quand elle diffère).
  final double entraxeMaxSolives;

  /// Épaisseur de la fascia (pour le dessin et le débord du cadre).
  final double epaisseurFascia;

  /// Vis de fascia : par rangée verticale, et espacement des rangées.
  final int visFasciaParRangee;
  final double espacementVisFascia;

  /// Vis en surface au milieu de chaque planche du centre, en plus des attaches (Fiberon).
  final int visCentreParPlanche;

  /// Débord maximal des planches du plancher au-delà de la rive ou de la fascia.
  final double debordPlancherMax;

  /// Ce que le guide demande de particulier pour un plancher.
  final String notePlancher;

  /// D'où viennent ces valeurs.
  final String source;

  const ProduitComposite({
    required this.id,
    required this.marque,
    required this.gamme,
    required this.largeur,
    required this.epaisseur,
    required this.ecart,
    required this.ecartBout,
    required this.noteEcarts,
    required this.attachesSurMarches,
    required this.attache,
    required this.attachesParBoite,
    required this.fixationSurface,
    required this.avecBouchons,
    required this.longueurs,
    required this.hauteursFascia,
    required this.longueursFascia,
    required this.entraxeMaxLimons,
    required this.debordNezMax,
    required this.noteMarches,
    required this.ecartPlancher,
    required this.longueursRainurees,
    required this.entraxeMaxSolives,
    required this.epaisseurFascia,
    required this.visFasciaParRangee,
    required this.espacementVisFascia,
    required this.visCentreParPlanche,
    required this.debordPlancherMax,
    required this.notePlancher,
    required this.source,
  });

  String get nom => gamme.isEmpty ? marque : '$marque $gamme';
}

const _po12 = <double>[144];
const _carre12a20 = <double>[144, 192, 240];
const _carre16et20 = <double>[192, 240];
const _rainure12a20 = <double>[144, 192, 240];

const _trexGuide =
    'Trex, guide d\'installation 2026 (images.salsify.com/…/hqvoka6uysitrwuk4oij.pdf) et fiche Enhance';
const _trexEcarts =
    'Bout à bout : 4 mm au-dessus de 15 °C, 6 mm de 3 à 15 °C, 8 mm de −9 à 3 °C (Canada) ; '
    '6 mm contre une structure.';
const _trexMarches =
    'Attaches Hideaway permises sur les marches avec des planches à bord carré rainurées à la '
    'toupie ; sinon vis en surface. Écart de 1/4 à 3/8 po entre les planches des marches ; '
    'fascia de contremarche : 2 vis par limon.';

const _trexPlancher =
    'Au Canada (CCMC 13125-R) : Enhance aux 300 mm, Select et Transcend aux 400 mm. Hideaway : '
    '1 attache par solive par planche (boîte de 90 = 50 pi²). Joints bout à bout sur une solive '
    '(Butt Joint Clip, ou 2x4 contre la solive). Cadre : 2 solives de plus sous la bordure, 2 vis '
    'aux 16 po. Fascia : 3 vis aux 18 po (2 sur une rive 2x8), à 1 po des bords.';

const _ttGuide =
    'TimberTech, guide d\'installation composite et fiches 2024 (assets.timbertech.com)';
const _ttEcarts =
    'Bout à bout : 3/16 po à 32 °F et moins, 1/8 po de 33 à 74 °F, 1/32 po à 75 °F et plus ; '
    '3/16 po au moins contre une structure.';
const _ttMarches =
    'Attaches cachées interdites sur les marches : vis Cortex (bouchons) ou TOPLoc. Limon central '
    'obligatoire ; marche sans contremarche déconseillée.';

const _ttPlancher =
    'Solives aux 16 po au plus (12 conseillé). CONCEALoc : 1 attache et 1 vis par solive (boîte '
    'de 175 = 100 pi²). Joints bout à bout : toujours sur une solive doublée. Cadre : blocage aux '
    '16 po au plus, 2 vis de chaque côté de l\'onglet. Fascia : vis en alternance haut et bas aux '
    '12 po.';

const _fibGuide =
    'Fiberon, instructions PE FIB-0354-LIT 10/25 et ESR-4947 (fiberondecking.com)';
const _fibEcarts =
    'Bout contre rive : 1/8 po à 70 °F et moins, 1/16 po au-dessus ; bout à bout : 1/4 po à 35 °F '
    'et moins, 3/16 po de 36 à 69 °F, 1/8 po de 70 à 89 °F ; 1/4 po au moins contre une structure.';
const _fibMarches =
    'Planches rainurées interdites sur les marches : bord carré vissé en surface (PRO PLUG ou '
    'Cortex). Au moins 2 portées ; contremarche : 2 vis par limon.';

const _fibPlancher =
    'Solives aux 16 po au plus. Phantom : 1 attache par solive dans la rainure, plus 2 vis en '
    'surface à la solive près du milieu de chaque planche ; départ et fin : STARTER aux 16 po ou '
    'vis en surface. Joints : solives doublées (écartées de 1/2 po) ou cales. Cadre : rive carrée, '
    '2 vis par solive. Fascia : 3 vis aux 12 po, à 1 po des bords.';

const _msGuide =
    'MoistureShield, guide d\'installation mars 2021 (révisé 2024), fiches 04-26 et CCMC 13191-R '
    '(moistureshield.com) ; '
    'gamme rachetée par Deckorators en 2026 : offre à reconfirmer';
const _msEcarts =
    'Bout à bout : 1/8 po au moins ; 1/4 po contre une structure.';
const _msPlancher =
    'Solives aux 16 po (Canada : 400 mm, CCMC 13191-R pour Vision ; Elevate non évalué). '
    'Attache Aegis ou Deck Clip : 1 de chaque côté de la planche à chaque solive (90 = 50 pi²). '
    'Joints : chaque bout sur sa solive ; joints alignés sur une solive doublée. Fascia '
    '0,67 × 11,25 po : 3 vis par rangée aux 12 à 16 po, sous le débord. Elevate : débord de '
    '1/4 po au plus, pas de bouchons.';

const _msMarches =
    'Marches vissées en surface, 2 vis par limon ; au moins 5 limons ; marche d\'au moins 11 po. '
    'Système de bouchons à confirmer chez le fabricant.';

/// Quand la marque n'est pas choisie : des valeurs prudentes (limons aux 9 po, marches vissées
/// en surface avec bouchons, comme la plupart des fabricants le demandent).
const produitCompositeGenerique = ProduitComposite(
  id: 'generique',
  marque: 'Composite courant',
  gamme: '',
  largeur: 5.5,
  epaisseur: 1.0,
  ecart: 3 / 16,
  ecartBout: 1 / 8,
  noteEcarts: 'Valeurs courantes : vérifier le guide du produit posé.',
  attachesSurMarches: false,
  attache: 'attache cachée',
  attachesParBoite: 90,
  fixationSurface: 'vis et bouchons de la couleur',
  avecBouchons: true,
  longueurs: _carre12a20,
  hauteursFascia: [7.25, 11.25],
  longueursFascia: _po12,
  entraxeMaxLimons: 9,
  debordNezMax: 0.75,
  noteMarches: 'Valeurs prudentes : la plupart des fabricants demandent des marches vissées en surface.',
  ecartPlancher: 3 / 16,
  longueursRainurees: _rainure12a20,
  entraxeMaxSolives: 16,
  epaisseurFascia: 0.75,
  visFasciaParRangee: 3,
  espacementVisFascia: 16,
  visCentreParPlanche: 0,
  debordPlancherMax: 0.5,
  notePlancher: 'Valeurs courantes : vérifier le guide du produit posé.',
  source: 'Valeurs courantes ; vérifier le guide du produit posé.',
);

/// Les produits proposés (le générique en premier).
const produitsComposite = <ProduitComposite>[
  produitCompositeGenerique,
  ProduitComposite(
    id: 'trex_enhance',
    marque: 'Trex',
    gamme: 'Enhance',
    largeur: 5.5,
    epaisseur: 0.94,
    ecart: 1 / 4,
    ecartBout: 1 / 8,
    noteEcarts: 'Bout à bout : 1/8 po au-dessus de 40 °F, 3/16 po en dessous ; 1/4 po contre une structure.',
    attachesSurMarches: true,
    attache: 'Hideaway Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis de surface et bouchons de la couleur',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.375],
    longueursFascia: _po12,
    entraxeMaxLimons: 9,
    debordNezMax: 0.75,
    noteMarches: _trexMarches,
    ecartPlancher: 3 / 16, // 5 mm ; l'attache Hideaway fait l'écart
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 12, // « 300 mm » au Canada (CCMC 13125-R) : 12 po
    epaisseurFascia: 0.56,
    visFasciaParRangee: 3,
    espacementVisFascia: 18,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _trexPlancher,
    source: _trexGuide,
  ),
  ProduitComposite(
    id: 'trex_select',
    marque: 'Trex',
    gamme: 'Select',
    largeur: 5.5,
    epaisseur: 0.82,
    ecart: 1 / 4,
    ecartBout: 5 / 32, // 4 mm
    noteEcarts: _trexEcarts,
    attachesSurMarches: true,
    attache: 'Hideaway Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis de surface et bouchons de la couleur',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.375],
    longueursFascia: _po12,
    entraxeMaxLimons: 200 / 25.4, // 200 mm au Canada
    debordNezMax: 0.75,
    noteMarches: _trexMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16, // « 400 mm » au Canada : 16 po
    epaisseurFascia: 0.56,
    visFasciaParRangee: 3,
    espacementVisFascia: 18,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _trexPlancher,
    source: _trexGuide,
  ),
  ProduitComposite(
    id: 'trex_transcend',
    marque: 'Trex',
    gamme: 'Transcend',
    largeur: 5.5,
    epaisseur: 0.94,
    ecart: 1 / 4,
    ecartBout: 5 / 32, // 4 mm
    noteEcarts: _trexEcarts,
    attachesSurMarches: true,
    attache: 'Hideaway Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis de surface et bouchons de la couleur',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.375],
    longueursFascia: _po12,
    entraxeMaxLimons: 230 / 25.4, // 230 mm au Canada
    debordNezMax: 0.75,
    noteMarches: _trexMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16, // « 400 mm » au Canada : 16 po
    epaisseurFascia: 0.56,
    visFasciaParRangee: 3,
    espacementVisFascia: 18,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _trexPlancher,
    source: _trexGuide,
  ),
  ProduitComposite(
    id: 'timbertech_pro',
    marque: 'TimberTech',
    gamme: 'PRO (Legacy, Reserve)',
    largeur: 5.36,
    epaisseur: 0.94,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _ttEcarts,
    attachesSurMarches: false,
    attache: 'CONCEALoc',
    attachesParBoite: 175,
    fixationSurface: 'vis Cortex et bouchons',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.95],
    longueursFascia: _po12,
    entraxeMaxLimons: 10,
    debordNezMax: 1,
    noteMarches: _ttMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.58,
    visFasciaParRangee: 2,
    espacementVisFascia: 12,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _ttPlancher,
    source: _ttGuide,
  ),
  ProduitComposite(
    id: 'timbertech_terrain',
    marque: 'TimberTech',
    gamme: 'PRO Terrain',
    largeur: 5.36,
    epaisseur: 0.94,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _ttEcarts,
    attachesSurMarches: false,
    attache: 'CONCEALoc',
    attachesParBoite: 175,
    fixationSurface: 'vis TOPLoc de la couleur (Cortex exclu sur cette gamme)',
    avecBouchons: false,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.95],
    longueursFascia: _po12,
    entraxeMaxLimons: 8,
    debordNezMax: 1,
    noteMarches: _ttMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.58,
    visFasciaParRangee: 2,
    espacementVisFascia: 12,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _ttPlancher,
    source: _ttGuide,
  ),
  ProduitComposite(
    id: 'timbertech_edge_prime',
    marque: 'TimberTech',
    gamme: 'EDGE Prime',
    largeur: 5.36,
    epaisseur: 0.94,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _ttEcarts,
    attachesSurMarches: false,
    attache: 'CONCEALoc',
    attachesParBoite: 175,
    fixationSurface: 'vis TOPLoc de la couleur (Cortex exclu sur cette gamme)',
    avecBouchons: false,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.95],
    longueursFascia: _po12,
    entraxeMaxLimons: 10,
    debordNezMax: 1,
    noteMarches: _ttMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.58,
    visFasciaParRangee: 2,
    espacementVisFascia: 12,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _ttPlancher,
    source: _ttGuide,
  ),
  ProduitComposite(
    id: 'timbertech_edge_premier',
    marque: 'TimberTech',
    gamme: 'EDGE Premier',
    largeur: 5.36,
    epaisseur: 0.89,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _ttEcarts,
    attachesSurMarches: false,
    attache: 'CONCEALoc',
    attachesParBoite: 175,
    fixationSurface: 'vis Cortex et bouchons',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [7.25, 11.95],
    longueursFascia: _po12,
    entraxeMaxLimons: 9,
    debordNezMax: 1,
    noteMarches: _ttMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.58,
    visFasciaParRangee: 2,
    espacementVisFascia: 12,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher: _ttPlancher,
    source: _ttGuide,
  ),
  ProduitComposite(
    id: 'timbertech_azek',
    marque: 'TimberTech AZEK',
    gamme: '(PVC)',
    largeur: 5.5,
    epaisseur: 1,
    ecart: 3 / 16,
    ecartBout: 0,
    noteEcarts:
        'PVC : bouts serrés, sans écart ; 1/8 à 1/4 po entre les planches.',
    attachesSurMarches: false,
    attache: 'CONCEALoc',
    attachesParBoite: 175,
    fixationSurface: 'vis Cortex et bouchons',
    avecBouchons: true,
    longueurs: _carre12a20,
    hauteursFascia: [
      11.75,
    ], // fascia PVC 0,5 × 11,75 po (guide Advanced PVC 07/26)
    longueursFascia: _po12,
    entraxeMaxLimons: 10,
    debordNezMax: 0.5,
    noteMarches:
        'Bord carré vissé en surface (Cortex ou TOPLoc) ; contremarche : 2 vis par limon, '
        'blocage derrière si les limons sont à plus de 10 po. Longueurs du bord carré et largeur '
        'de la fascia à vérifier.',
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.5,
    visFasciaParRangee: 3,
    espacementVisFascia: 12,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.75,
    notePlancher:
        'PVC : solives aux 16 po au plus (12 conseillé) ; bouts serrés ; solive ou blocage double '
        'aux joints ; fascia sur fond plein (rive 2x12), 3 vis par rangée aux 12 po.',
    source: 'TimberTech, guide d\'installation PVC et fiche AZEK 2024 (assets.timbertech.com)',
  ),
  ProduitComposite(
    id: 'fiberon_good_life',
    marque: 'Fiberon',
    gamme: 'Good Life',
    largeur: 5.4,
    epaisseur: 0.94,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _fibEcarts,
    attachesSurMarches: false,
    attache: 'Phantom Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis et bouchons PRO PLUG ou Cortex',
    avecBouchons: true,
    longueurs: _carre12a20,
    hauteursFascia: [7.25, 11.25],
    longueursFascia: _po12,
    entraxeMaxLimons: 12,
    debordNezMax: 0.5,
    noteMarches: _fibMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.75,
    visFasciaParRangee: 3,
    espacementVisFascia: 12,
    visCentreParPlanche: 2,
    debordPlancherMax: 0.5,
    notePlancher: _fibPlancher,
    source: _fibGuide,
  ),
  ProduitComposite(
    id: 'fiberon_sanctuary',
    marque: 'Fiberon',
    gamme: 'Sanctuary, Concordia',
    largeur: 5.4,
    epaisseur: 0.94,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _fibEcarts,
    attachesSurMarches: false,
    attache: 'Phantom Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis et bouchons PRO PLUG ou Cortex',
    avecBouchons: true,
    longueurs: _carre12a20,
    hauteursFascia: [7.25, 11.25],
    longueursFascia: _po12,
    entraxeMaxLimons: 12,
    debordNezMax: 1,
    noteMarches: _fibMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.75,
    visFasciaParRangee: 3,
    espacementVisFascia: 12,
    visCentreParPlanche: 2,
    debordPlancherMax: 1,
    notePlancher: _fibPlancher,
    source: _fibGuide,
  ),
  ProduitComposite(
    id: 'fiberon_armorguard',
    marque: 'Fiberon',
    gamme: 'ArmorGuard',
    largeur: 5.2,
    epaisseur: 0.92,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _fibEcarts,
    attachesSurMarches: false,
    attache: 'Phantom Universal',
    attachesParBoite: 90,
    fixationSurface: 'vis et bouchons PRO PLUG ou Cortex',
    avecBouchons: true,
    longueurs: [96, 240],
    hauteursFascia: [11.25], // fascia seulement, pas de contremarche
    longueursFascia: _po12,
    entraxeMaxLimons: 12,
    debordNezMax: 0.5,
    noteMarches: _fibMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.75,
    visFasciaParRangee: 3,
    espacementVisFascia: 12,
    visCentreParPlanche: 2,
    debordPlancherMax: 0.5,
    notePlancher: _fibPlancher,
    source: _fibGuide,
  ),
  ProduitComposite(
    id: 'moistureshield_vision',
    marque: 'MoistureShield',
    gamme: 'Vision',
    largeur: 5.4,
    epaisseur: 1,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _msEcarts,
    attachesSurMarches: false,
    attache: 'Aegis',
    attachesParBoite: 90,
    fixationSurface: 'vis de surface et bouchons de la couleur',
    avecBouchons: true,
    longueurs: _carre16et20,
    hauteursFascia: [11.25], // fascia recoupée pour les contremarches
    longueursFascia: _po12,
    entraxeMaxLimons: 9,
    debordNezMax: 0.75,
    noteMarches: _msMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.67,
    visFasciaParRangee: 3,
    espacementVisFascia: 16,
    visCentreParPlanche: 0,
    debordPlancherMax: 1.5,
    notePlancher: _msPlancher,
    source: _msGuide,
  ),
  ProduitComposite(
    id: 'moistureshield_elevate',
    marque: 'MoistureShield',
    gamme: 'Elevate',
    largeur: 5.4,
    epaisseur: 1,
    ecart: 3 / 16,
    ecartBout: 1 / 8,
    noteEcarts: _msEcarts,
    attachesSurMarches: false,
    attache: 'Aegis',
    attachesParBoite: 90,
    fixationSurface: 'vis de surface et bouchons de la couleur',
    avecBouchons: true,
    longueurs: [240],
    hauteursFascia: [11.25],
    longueursFascia: _po12,
    entraxeMaxLimons: 8,
    debordNezMax: 0.75,
    noteMarches: _msMarches,
    ecartPlancher: 3 / 16,
    longueursRainurees: _rainure12a20,
    entraxeMaxSolives: 16,
    epaisseurFascia: 0.67,
    visFasciaParRangee: 3,
    espacementVisFascia: 16,
    visCentreParPlanche: 0,
    debordPlancherMax: 0.25,
    notePlancher: _msPlancher,
    source: _msGuide,
  ),
];

/// Le produit d'un identifiant (le générique s'il est inconnu).
ProduitComposite produitComposite(String? id) => produitsComposite.firstWhere(
  (p) => p.id == id,
  orElse: () => produitCompositeGenerique,
);
