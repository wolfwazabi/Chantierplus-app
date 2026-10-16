import 'dart:math' as math;

import 'composite.dart';
import 'empaquetage.dart';
import 'geometrie.dart';
import 'mur.dart' show SectionBois;
import 'plancher.dart';
import 'unites.dart';

/// Dessus d'un plancher en composite (une plateforme, une terrasse), comme Philip le pose et
/// comme les guides des fabricants le demandent :
///  - un cadre (« picture frame ») de planches à rive carrée sur tout le pourtour, en onglet aux
///    coins, aussi contre la maison (à [ecartMaisonComposite] du mur) ; ailleurs il dépasse un
///    peu la fascia ;
///  - au centre, des planches rainurées perpendiculaires aux solives, retenues par les attaches
///    cachées du fabricant (une par solive par planche) ; la première et la dernière rangée
///    vissées en surface ;
///  - une fascia du même produit sur les rives, sauf contre la maison ;
///  - du blocage en échelle sous le cadre là où il longe les solives (il porte le cadre et le bout
///    des planches du centre).
/// Tout est en POUCES, dans le repère PIVOTÉ du plancher (solives le long de x, planches du
/// centre le long de y).

/// Écart entre les planches et la maison.
const double ecartMaisonComposite = 0.25;

/// Débord du cadre au-delà de la fascia (moins si le fabricant le limite).
const double debordCadreComposite = 0.5;

/// Blocage sous le cadre qui longe les solives : un bloc aux 16 po au plus.
const double espacementBlocageCadre = 16;

/// Vissage en surface : 2 vis par appui (solive ou bloc).
const int visParAppui = 2;

/// Reste plus petit que ceci : pris par les écarts aux bords du cadre (aucune planche refendue).
const double resteAbsorbe = 1 / 8;

/// Planche à refendre de moins que ceci : seule la dernière l'est (elle reste presque entière).
const double refenteLegere = 0.5;

/// Largeurs des rangées du centre sur [largeur] (d'un bord du cadre à l'autre, écarts compris),
/// planches de [b] et écart [e] (celui de l'attache cachée) : des planches entières, et le reste
/// réparti pour ne jamais finir avec une lisière difficile à visser et laide : la première et la
/// dernière rangée refendues à la même largeur, (b + reste) / 2, donc au moins une demi-planche.
/// Un reste minuscule est pris par les écarts aux bords ; une planche presque entière est seule
/// refendue (la dernière).
List<double> largeursRangees(double largeur, double b, double e) {
  final pas = b + e;
  final entieres = math.max(1, ((largeur + e) / pas + 1e-9).floor());
  // La place d'une planche de plus, son écart compris.
  final reste = largeur - entieres * pas;
  if (reste <= resteAbsorbe) return List.filled(entieres, b);
  if (reste >= b - refenteLegere) return [...List.filled(entieres, b), reste];
  final refendue = (b + reste) / 2;
  return [refendue, ...List.filled(entieres - 1, b), refendue];
}

/// Une planche du cadre, le long d'un côté du contour.
class PlancheCadre {
  final int cote;

  /// Contour de la planche, en onglet aux coins (repère pivoté).
  final List<Pt> contour;

  /// Longueur à couper (pointe longue), et en combien de morceaux si elle dépasse la plus
  /// longue planche vendue.
  final double longueur;
  final int morceaux;

  /// Le côté longe les solives : le cadre pose sur du blocage.
  final bool longeSolives;

  /// Appuis (solives ou blocs) sous la planche : 2 vis chacun.
  final int appuis;

  const PlancheCadre({
    required this.cote,
    required this.contour,
    required this.longueur,
    required this.morceaux,
    required this.longeSolives,
    required this.appuis,
  });
}

/// Une planche du centre (ou un morceau d'une rangée trop longue pour une seule planche).
class PlancheCentre {
  final int rangee;

  /// Contour (repère pivoté) et longueur à couper.
  final List<Pt> contour;
  final double longueur;

  /// Largeur de la planche ; refendue si elle est plus étroite qu'une planche entière (la
  /// première et la dernière rangée, voir [largeursRangees]).
  final double largeur;
  final bool refendue;

  /// Solives croisées : une attache cachée à chacune.
  final int appuis;

  const PlancheCentre({
    required this.rangee,
    required this.contour,
    required this.longueur,
    required this.largeur,
    required this.refendue,
    required this.appuis,
  });
}

/// La fascia d'un côté (repère pivoté) : de la face de la rive à sa face extérieure.
class FasciaCote {
  final int cote;
  final List<Pt> contour;
  final double longueur;
  final int morceaux;
  const FasciaCote({
    required this.cote,
    required this.contour,
    required this.longueur,
    required this.morceaux,
  });
}

class ResultatTerrasse {
  final ProduitComposite produit;
  final List<PlancheCadre> cadre;
  final List<PlancheCentre> centre;
  final List<FasciaCote> fascias;

  /// Rangées de planches au centre, et leur largeur (de la première à la dernière).
  final int rangees;
  final List<double> largeurs;

  /// Planches à commander : rive carrée (cadre), rainurées (centre), fascias.
  final ResultatDecoupe planchesCadre;
  final ResultatDecoupe planchesCentre;
  final ResultatDecoupe planchesFascia;
  final double hauteurFascia;

  /// Blocage en échelle sous le cadre qui longe les solives.
  final ResultatDecoupe blocage;
  final int blocs;
  final double longueurBloc;

  final int attaches;
  final int visSurface;
  final int visFascia;

  /// Joints bout à bout au centre (rangées plus longues que la plus longue planche).
  final int joints;
  final double aire;
  final List<String> avertissements;

  const ResultatTerrasse({
    required this.produit,
    required this.cadre,
    required this.centre,
    required this.fascias,
    required this.rangees,
    required this.largeurs,
    required this.planchesCadre,
    required this.planchesCentre,
    required this.planchesFascia,
    required this.hauteurFascia,
    required this.blocage,
    required this.blocs,
    required this.longueurBloc,
    required this.attaches,
    required this.visSurface,
    required this.visFascia,
    required this.joints,
    required this.aire,
    required this.avertissements,
  });

  /// Les rangées refendues : largeur de la première et de la dernière (null : entière).
  double? get premiereRefendue =>
      largeurs.first < produit.largeur - 1e-6 ? largeurs.first : null;
  double? get derniereRefendue =>
      largeurs.last < produit.largeur - 1e-6 ? largeurs.last : null;

  int get boitesAttaches => (attaches / produit.attachesParBoite - 1e-9).ceil();

  /// Bouchons : un par vis en surface si le produit en a.
  int get bouchons => produit.avecBouchons ? visSurface : 0;
}

/// Le composite sur le plancher calculé [plancher], solives en [section]. Lance [SpecInvalide]
/// si la plateforme est trop petite pour un cadre.
ResultatTerrasse calculerTerrasse(
  ResultatPlancher plancher,
  ProduitComposite produit, {
  required SectionBois section,
  bool metrique = false,
}) {
  final f = plancher.formePivotee;
  final n = f.nombre;
  final spec = plancher.spec;
  final maison = spec.coteMaison;
  final b = produit.largeur;
  final ef = produit.epaisseurFascia;
  final debord = math.min(debordCadreComposite, produit.debordPlancherMax);
  String l(double po) => formatLongueur(po, metrique: metrique);

  // Côté qui longe les solives (solives le long de x dans le repère pivoté).
  bool longe(int i) {
    final d = (f.sommet(i + 1) - f.sommet(i)).unitaire;
    return d.y.abs() < math.sin(math.pi / 4);
  }

  bool estMaison(int i) => maison != null && i % n == maison;

  // Droites décalées vers l'extérieur de chaque côté, et leurs croisements aux sommets.
  (Pt, Pt) droite(int i, double decalage) {
    final a = f.sommet(i);
    return (
      a - f.normaleInterieure(i) * decalage,
      (f.sommet(i + 1) - a).unitaire,
    );
  }

  Pt croisement((Pt, Pt) d1, (Pt, Pt) d2) {
    final (p, u) = d1;
    final (q, v) = d2;
    final den = u.cross(v);
    if (den.abs() < 1e-9) {
      return q; // côtés alignés
    }
    return p + u * ((q - p).cross(v) / den);
  }

  List<Pt> decale(double Function(int) decalage) => [
    for (var i = 0; i < n; i++)
      croisement(droite(i - 1, decalage(i - 1)), droite(i, decalage(i))),
  ];

  double exterieur(int i) => estMaison(i) ? -ecartMaisonComposite : ef + debord;
  double interieurCadre(int i) => exterieur(i) - b;
  double bordCentre(int i) =>
      interieurCadre(i) -
      (longe(i) ? produit.ecartBout : produit.ecartPlancher);

  final ext = decale(exterieur);
  final intCadre = decale(interieurCadre);
  final bord = decale(bordCentre);

  // --- Cadre ----------------------------------------------------------------------------------
  final maxCarre = produit.longueurs.reduce(math.max);
  final cadre = <PlancheCadre>[];
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final contour = [ext[i], ext[j], intCadre[j], intCadre[i]];
    final longueur = math.max(
      ext[i].distanceA(ext[j]),
      intCadre[i].distanceA(intCadre[j]),
    );
    final morceaux = (longueur / maxCarre - 1e-9).ceil();
    final pas = longe(i) ? espacementBlocageCadre : spec.espacement;
    cadre.add(
      PlancheCadre(
        cote: i,
        contour: contour,
        longueur: longueur,
        morceaux: morceaux,
        longeSolives: longe(i),
        appuis: (longueur / pas - 1e-9).ceil() + 1,
      ),
    );
  }

  // --- Centre : rangées perpendiculaires aux solives ------------------------------------------
  final Polygone centreForme;
  try {
    centreForme = Polygone(bord);
  } on FormeInvalide {
    throw const SpecInvalide(
      'Plateforme trop petite pour un cadre en composite.',
    );
  }
  // Solives (axes en v) qui portent une rangée à l'abscisse x, entre y0 et y1 ; une solive
  // doublée compte une fois.
  int appuis(double x, double y0, double y1) {
    final vs = [
      for (final s in plancher.solives)
        if (s.v > y0 && s.v < y1 && s.u0 - 0.1 <= x && x <= s.u1 + 0.1) s.v,
    ]..sort();
    var compte = 0;
    double? dernier;
    for (final v in vs) {
      if (dernier == null || v - dernier > 2) {
        compte++;
      }
      dernier = v;
    }
    return compte;
  }

  final maxRainure = produit.longueursRainurees.reduce(math.max);
  final boite = centreForme.boite;
  // Au moins une planche entière dans chaque sens, et une forme qui ne s'est pas retournée.
  if (centreForme.aire <= 0 || boite.largeur < b || boite.hauteur < b) {
    throw const SpecInvalide(
      'Plateforme trop petite pour un cadre en composite.',
    );
  }
  final largeurs = largeursRangees(boite.largeur, b, produit.ecartPlancher);
  final occupe =
      largeurs.fold(0.0, (a, w) => a + w) +
      (largeurs.length - 1) * produit.ecartPlancher;
  final centre = <PlancheCentre>[];
  var joints = 0;
  // Un reste pris par les écarts : partagé entre les deux bords.
  var x0 = boite.xMin + (boite.largeur - occupe) / 2;
  for (final (rangee, w) in largeurs.indexed) {
    final x1 = x0 + w;
    final xc = (x0 + x1) / 2;
    final bords = [
      ...centreForme.cordes(horizontale: false, c: x0 + 1e-4),
      ...centreForme.cordes(horizontale: false, c: x1 - 1e-4),
    ];
    for (final corde in centreForme.cordes(horizontale: false, c: xc)) {
      var y0 = corde.debut, y1 = corde.fin;
      for (final e in bords) {
        if (e.fin > corde.debut && e.debut < corde.fin) {
          y0 = math.min(y0, e.debut);
          y1 = math.max(y1, e.fin);
        }
      }
      // Rangée plus longue que la plus longue planche : des morceaux égaux, joints bout à bout.
      final morceaux = ((y1 - y0) / maxRainure - 1e-9).ceil();
      joints += morceaux - 1;
      final pas = (y1 - y0) / morceaux;
      for (var k = 0; k < morceaux; k++) {
        final ya = y0 + k * pas, yb = ya + pas;
        final contour = polygoneDansRectangle(
          centreForme.sommets,
          x0,
          x1,
          ya,
          yb,
        );
        if (contour.length < 3) continue;
        centre.add(
          PlancheCentre(
            rangee: rangee,
            contour: contour,
            longueur: pas,
            largeur: w,
            refendue: w < b - 1e-6,
            appuis: appuis(xc, ya - 0.01, yb + 0.01),
          ),
        );
      }
    }
    x0 = x1 + produit.ecartPlancher;
  }
  final rangee = largeurs.length;
  if (centre.isEmpty) {
    throw const SpecInvalide(
      'Plateforme trop petite pour un cadre en composite.',
    );
  }

  // --- Fascia : sur les rives, sauf contre la maison ------------------------------------------
  final faceFascia = decale((i) => estMaison(i) ? 0 : ef);
  final maxFascia = produit.longueursFascia.reduce(math.max);
  final fascias = <FasciaCote>[];
  for (var i = 0; i < n; i++) {
    if (estMaison(i)) continue;
    final j = (i + 1) % n;
    final longueur = faceFascia[i].distanceA(faceFascia[j]);
    fascias.add(
      FasciaCote(
        cote: i,
        contour: [f.sommet(i), f.sommet(j), faceFascia[j], faceFascia[i]],
        longueur: longueur,
        morceaux: (longueur / maxFascia - 1e-9).ceil(),
      ),
    );
  }
  final hauteurs = [...produit.hauteursFascia]..sort();
  final hauteurFascia = hauteurs.firstWhere(
    (h) => h >= section.profondeur - 1e-9,
    orElse: () => hauteurs.last,
  );

  // --- Blocage en échelle sous le cadre qui longe les solives ---------------------------------
  final longueurBloc = spec.espacement - section.epaisseur;
  var blocs = 0;
  for (var i = 0; i < n; i++) {
    if (!longe(i)) continue;
    blocs += (f.longueurCote(i) / espacementBlocageCadre - 1e-9).ceil() + 1;
  }

  // --- Quincaillerie --------------------------------------------------------------------------
  final attaches = centre.fold(0, (a, p) => a + p.appuis);
  // Première et dernière rangée : vissées en surface le long du cadre.
  final derniere = rangee - 1;
  final visRives = centre
      .where((p) => p.rangee == 0 || p.rangee == derniere)
      .fold(0, (a, p) => a + visParAppui * p.appuis);
  final visCadre = cadre.fold(0, (a, p) => a + visParAppui * p.appuis);
  final visCentre = produit.visCentreParPlanche * centre.length;
  final visFascia = fascias.fold(
    0,
    (a, p) =>
        a +
        produit.visFasciaParRangee *
            ((p.longueur / produit.espacementVisFascia - 1e-9).ceil() + 1),
  );

  final avertissements = <String>[
    if (spec.espacement > produit.entraxeMaxSolives + 0.05)
      '${produit.nom} : solives aux ${l(produit.entraxeMaxSolives)} au plus (guide du '
          'fabricant) ; l\'entraxe est de ${l(spec.espacement)}.',
    if (joints > 0)
      'Planches du centre de plus de ${formatPlanche(maxRainure, metrique: metrique)} : '
          '$joints joint${joints > 1 ? 's' : ''} bout à bout, sur une solive doublée ou un bloc '
          '(guide du fabricant).',
  ];

  return ResultatTerrasse(
    produit: produit,
    cadre: cadre,
    centre: centre,
    fascias: fascias,
    rangees: rangee,
    largeurs: largeurs,
    planchesCadre: decouperPlanches([
      for (final p in cadre)
        for (var k = 0; k < p.morceaux; k++)
          PieceCoupe('cadre${p.cote}.$k', p.longueur / p.morceaux, 'cadre'),
    ], produit.longueurs),
    planchesCentre: decouperPlanches([
      for (final (k, p) in centre.indexed)
        PieceCoupe('centre$k', p.longueur, 'centre'),
    ], produit.longueursRainurees),
    planchesFascia: decouperPlanches([
      for (final p in fascias)
        for (var k = 0; k < p.morceaux; k++)
          PieceCoupe('fascia${p.cote}.$k', p.longueur / p.morceaux, 'fascia'),
    ], produit.longueursFascia),
    hauteurFascia: hauteurFascia,
    blocage: decouperPlanches([
      for (var k = 0; k < blocs; k++)
        PieceCoupe('bloc$k', longueurBloc, 'bloc'),
    ], spec.longueursPlanches),
    blocs: blocs,
    longueurBloc: longueurBloc,
    attaches: attaches,
    visSurface: visCadre + visRives + visCentre,
    visFascia: visFascia,
    joints: joints,
    aire: Polygone(ext).aire.abs(),
    avertissements: avertissements,
  );
}
