/// Produits de terrasse en composite (ou PVC) : ce que disent les guides d'installation des
/// fabricants pour des marches d'escalier. Tout est en POUCES. Sources : guides et fiches des
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
    required this.source,
  });

  String get nom => gamme.isEmpty ? marque : '$marque $gamme';
}

const _po12 = <double>[144];
const _carre12a20 = <double>[144, 192, 240];
const _carre16et20 = <double>[192, 240];

const _trexGuide =
    'Trex, guide d\'installation 2026 (images.salsify.com/…/hqvoka6uysitrwuk4oij.pdf) et fiche Enhance';
const _trexEcarts =
    'Bout à bout : 4 mm au-dessus de 15 °C, 6 mm de 3 à 15 °C, 8 mm de −9 à 3 °C (Canada) ; '
    '6 mm contre une structure.';
const _trexMarches =
    'Attaches Hideaway permises sur les marches avec des planches à bord carré rainurées à la '
    'toupie ; sinon vis en surface. Écart de 1/4 à 3/8 po entre les planches des marches ; '
    'fascia de contremarche : 2 vis par limon.';

const _ttGuide =
    'TimberTech, guide d\'installation composite et fiches 2024 (assets.timbertech.com)';
const _ttEcarts =
    'Bout à bout : 3/16 po à 32 °F et moins, 1/8 po de 33 à 74 °F, 1/32 po à 75 °F et plus ; '
    '3/16 po au moins contre une structure.';
const _ttMarches =
    'Attaches cachées interdites sur les marches : vis Cortex (bouchons) ou TOPLoc. Limon central '
    'obligatoire ; marche sans contremarche déconseillée.';

const _fibGuide =
    'Fiberon, instructions PE FIB-0354-LIT 10/25 et ESR-4947 (fiberondecking.com)';
const _fibEcarts =
    'Bout contre rive : 1/8 po à 70 °F et moins, 1/16 po au-dessus ; bout à bout : 1/4 po à 35 °F '
    'et moins, 3/16 po de 36 à 69 °F, 1/8 po de 70 à 89 °F ; 1/4 po au moins contre une structure.';
const _fibMarches =
    'Planches rainurées interdites sur les marches : bord carré vissé en surface (PRO PLUG ou '
    'Cortex). Au moins 2 portées ; contremarche : 2 vis par limon.';

const _msGuide =
    'MoistureShield, guide d\'installation mars 2021 et fiches 04-26 (moistureshield.com) ; '
    'gamme rachetée par Deckorators en 2026 : offre à reconfirmer';
const _msEcarts =
    'Bout à bout : 1/8 po au moins ; 1/4 po contre une structure.';
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
      11.25,
    ], // fascia de 12 po nominal : largeur réelle non vérifiée
    longueursFascia: _po12,
    entraxeMaxLimons: 10,
    debordNezMax: 0.5,
    noteMarches:
        'Bord carré vissé en surface (Cortex ou TOPLoc) ; contremarche : 2 vis par limon, '
        'blocage derrière si les limons sont à plus de 10 po. Longueurs du bord carré et largeur '
        'de la fascia à vérifier.',
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
    source: _msGuide,
  ),
];

/// Le produit d'un identifiant (le générique s'il est inconnu).
ProduitComposite produitComposite(String? id) => produitsComposite.firstWhere(
  (p) => p.id == id,
  orElse: () => produitCompositeGenerique,
);
