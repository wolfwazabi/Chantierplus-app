import 'dart:math' as math;

import 'composite.dart';
import 'empaquetage.dart';
import 'escalier.dart';
import 'plancher.dart' show longueursPlanchesParDefaut;

/// Marches en composite, comme les fabricants le demandent et comme sur un escalier fini :
///  - chaque marche en cadre : un nez sur toute la largeur, deux côtés en onglet (de la
///    profondeur de la marche) et des planches au centre entre les côtés ;
///  - chaque contremarche en fascia composite (la plus basse hauteur vendue qui la couvre),
///    refendue à la hauteur de la contremarche ;
///  - un 2x traité (« backing ») derrière chaque contremarche, pour visser la fascia ;
///  - au choix, un 2x12 traité à plat de chaque côté de chaque marche, entre le limon de côté et
///    le suivant, sous la planche de côté du cadre ;
///  - limons à l'entraxe du fabricant.
/// Les dimensions (largeur et épaisseur des planches, écart des attaches cachées, longueurs,
/// fascias) viennent du produit choisi ([ProduitComposite]). Tout est en POUCES.

/// Un reste plus petit que ceci au fond de la marche ne demande pas une planche de plus
/// (le dernier rang déborde un peu sous la contremarche suivante).
const double _toleranceRang = 0.5;

class MaterielComposite {
  final ProduitComposite produit;

  /// Planches de composite des marches (en cadre).
  final ResultatDecoupe planches;

  /// Fascias des contremarches.
  final ResultatDecoupe fascias;
  final double hauteurFascia;

  /// 2x traité derrière chaque contremarche.
  final ResultatDecoupe backing;
  final String sectionBacking;

  /// 2x12 traités à plat aux côtés de chaque marche (null : sans).
  final ResultatDecoupe? blocs;

  /// Morceaux de 2x12 par marche (un de chaque côté ; un seul s'il n'y a que 2 limons).
  final int blocsParMarche;

  /// Longueur d'un morceau : l'espace libre entre le limon de côté et le suivant.
  final double longueurBloc;

  /// Par marche : rangs de planches au centre (entre les côtés), et leur longueur.
  final int rangsCentre;
  final double longueurCentre;

  /// Vis en surface des marches (nez et côtés ; toutes les planches si le fabricant interdit ses
  /// attaches sur les marches) : autant de bouchons si le produit en a.
  final int visApparentes;

  /// Attaches cachées des planches du centre.
  final int attaches;

  /// Vis des fascias (dans le backing, à chaque limon).
  final int visFascia;

  const MaterielComposite({
    required this.produit,
    required this.planches,
    required this.fascias,
    required this.hauteurFascia,
    required this.backing,
    required this.sectionBacking,
    this.blocs,
    this.blocsParMarche = 0,
    this.longueurBloc = 0,
    required this.rangsCentre,
    required this.longueurCentre,
    required this.visApparentes,
    required this.attaches,
    required this.visFascia,
  });

  int get boitesAttaches => (attaches / produit.attachesParBoite).ceil();
}

/// Vissage en surface : 2 vis par limon dans chaque planche en travers des limons, et 2 vis par
/// côté de marche (dans le limon extérieur).
const int visParLimonParPlanche = 2;
const int visParCote = 2;

/// Vis par limon dans chaque fascia (dans le backing).
const int visFasciaParLimon = 2;

/// Le composite d'un escalier calculé. Lance [EscalierInvalide] si l'escalier est trop étroit
/// pour une marche en cadre ou si la contremarche est plus haute que la plus haute fascia.
MaterielComposite calculerComposite(ResultatEscalier r) {
  final produit = r.spec.composite ?? produitCompositeGenerique;
  final largeur = r.spec.largeur;
  final profondeur = r.profondeurMarche;
  final b = produit.largeur;
  // Les planches du centre finissent contre les côtés (le cadre) : l'écart du fabricant à
  // chaque bout.
  final longueurCentre = largeur - 2 * b - 2 * produit.ecartBout;
  if (longueurCentre <= 0) {
    throw const EscalierInvalide(
      'Escalier trop étroit pour des marches en cadre (deux côtés de planche).',
    );
  }
  // Rangs au centre : derrière le nez, jusqu'au fond de la marche.
  final rangs = math.max(
    0,
    ((profondeur - b - _toleranceRang) / (b + produit.ecart)).ceil(),
  );

  final pieces = <PieceCoupe>[];
  for (var k = 0; k < r.nombreMarches; k++) {
    pieces
      ..add(PieceCoupe('nez$k', largeur, 'nez'))
      ..add(PieceCoupe('cote${k}g', profondeur, 'côté'))
      ..add(PieceCoupe('cote${k}d', profondeur, 'côté'));
    for (var j = 0; j < rangs; j++) {
      pieces.add(PieceCoupe('centre$k.$j', longueurCentre, 'centre'));
    }
  }

  final hauteur = r.contremarche;
  final fascia = ([
    ...produit.hauteursFascia,
  ]..sort()).where((h) => h >= hauteur - 1e-9);
  if (fascia.isEmpty) {
    throw EscalierInvalide(
      'Contremarche plus haute que la fascia la plus haute de ${produit.nom}.',
    );
  }
  final contremarches = [
    for (var k = 0; k < r.nombreContremarches; k++)
      PieceCoupe('cm$k', largeur, 'contremarche'),
  ];
  // Fascia de 12 pi : une contremarche plus large se fait en morceaux égaux (joint sur un limon).
  final fasciaMax = produit.longueursFascia.reduce(math.max);
  final morceaux = (largeur / fasciaMax - 1e-9).ceil();
  final fascias = [
    for (var k = 0; k < r.nombreContremarches; k++)
      for (var j = 0; j < morceaux; j++)
        PieceCoupe('f$k.$j', largeur / morceaux, 'contremarche'),
  ];
  // Le 2x de backing : la plus petite section qui couvre la contremarche (à refendre).
  final section = hauteur <= 7.25 + 1e-9
      ? '2x8'
      : hauteur <= 9.25 + 1e-9
      ? '2x10'
      : '2x12';

  // Fixation : le nez et les côtés (bords visibles) sont vissés en surface. Les planches du
  // centre posent sur les limons intérieurs : attaches cachées à chaque joint de planches
  // (devant, entre les rangs et au fond) si le fabricant les permet sur les marches, sinon
  // vissées en surface elles aussi.
  final limons = r.nombreLimons;
  final limonsInterieurs = math.max(0, limons - 2);
  final avecAttaches = produit.attachesSurMarches && rangs > 0;
  final visApparentes =
      r.nombreMarches *
      (visParLimonParPlanche * limons +
          2 * visParCote +
          (avecAttaches
              ? 0
              : rangs * visParLimonParPlanche * limonsInterieurs));
  final attaches = avecAttaches
      ? r.nombreMarches * (rangs + 1) * limonsInterieurs
      : 0;
  final visFascia = r.nombreContremarches * visFasciaParLimon * limons;

  // 2x12 à plat aux côtés : à chaque marche, un morceau entre le limon de côté et le suivant, de
  // chaque côté (le milieu reste ouvert), de l'espace libre entre eux.
  final longueurBloc = r.espacementReel - r.spec.section.epaisseur;
  final blocsParMarche = math.min(2, limons - 1);
  final blocs = !r.spec.blocs2x12
      ? null
      : decouperPlanches([
          for (var k = 0; k < r.nombreMarches; k++)
            for (var j = 0; j < blocsParMarche; j++)
              PieceCoupe('bloc$k.$j', longueurBloc, 'bloc'),
        ], longueursPlanchesParDefaut);

  return MaterielComposite(
    produit: produit,
    blocs: blocs,
    blocsParMarche: blocs == null ? 0 : blocsParMarche,
    longueurBloc: longueurBloc,
    planches: decouperPlanches(pieces, produit.longueurs),
    fascias: decouperPlanches(fascias, produit.longueursFascia),
    hauteurFascia: fascia.first,
    backing: decouperPlanches(contremarches, longueursPlanchesParDefaut),
    sectionBacking: section,
    rangsCentre: rangs,
    longueurCentre: longueurCentre,
    visApparentes: visApparentes,
    attaches: attaches,
    visFascia: visFascia,
  );
}
