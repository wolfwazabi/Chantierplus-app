import 'dart:math' as math;

import 'geometrie.dart';
import 'unites.dart';

/// Calcul des limons d'un escalier droit (une volée) à marches en bois.
///
/// Tout est en POUCES. Le profil du limon est calculé géométriquement (pas par
/// des formules approchées) : pointes des dents alignées sur le dessus de la
/// planche, gorge mesurée perpendiculairement, longueur de planche prise sur
/// l'étendue réelle du profil.
///
/// Repère : x vers le haut de l'escalier, y vers le haut, origine au pied de la
/// coupe d'aplomb du bas, sur le plancher fini du bas.
///
///  - la 1re marche a son dessus à R du plancher du bas : le siège du limon est
///    donc à R − t (t = épaisseur de la marche) ;
///  - la marche k (k = 1 … n − 1) a son siège à k·R − t, de x = (k − 1)·G à k·G ;
///  - la dernière contremarche arrive au plancher du haut (H = n·R) : il y a n
///    contremarches et n − 1 marches.
///
/// Valeurs du Code : CNB 2015, section 9.8, tel qu'adopté au Québec (Code de
/// construction du Québec, chapitre I). Elles sont à confirmer auprès de la RBQ,
/// de la Garantie de construction résidentielle ou de l'inspecteur municipal.

// -----------------------------------------------------------------------------
// Limites du Code (mm)
// -----------------------------------------------------------------------------

enum UsageEscalier { prive, commun }

/// Exigences dimensionnelles d'un escalier (millimètres).
class LimitesEscalier {
  final double contremarcheMin;
  final double contremarcheMax;
  final double gironMin;

  /// Null : pas de maximum.
  final double? gironMax;
  final double largeurMin;
  final double echappeeMin;
  final double hauteurVoleeMax;

  const LimitesEscalier({
    required this.contremarcheMin,
    required this.contremarcheMax,
    required this.gironMin,
    required this.gironMax,
    required this.largeurMin,
    required this.echappeeMin,
    required this.hauteurVoleeMax,
  });

  /// Escalier privé : à l'intérieur d'un logement (CNB 9.8.4.2, 9.8.2.1, 9.8.2.2, 9.8.3.3).
  static const prive = LimitesEscalier(
    contremarcheMin: 125,
    contremarcheMax: 200,
    gironMin: 255,
    gironMax: 355,
    largeurMin: 860,
    echappeeMin: 1950,
    hauteurVoleeMax: 3700,
  );

  /// Escalier commun ou public (autres escaliers).
  static const commun = LimitesEscalier(
    contremarcheMin: 125,
    contremarcheMax: 180,
    gironMin: 280,
    gironMax: null,
    largeurMin: 900,
    echappeeMin: 2050,
    hauteurVoleeMax: 3700,
  );

  static LimitesEscalier de(UsageEscalier u) =>
      u == UsageEscalier.prive ? prive : commun;
}

/// Saillie maximale du nez de marche : la profondeur d'une marche rectangulaire
/// ne dépasse pas son giron de plus de 25 mm (CNB 9.8.4.2).
const double saillieNezMaxMm = 25;

/// Écart permis entre deux contremarches (ou deux girons) voisins et sur toute
/// la volée (CNB 9.8.4.5).
const double uniformiteAdjacenteMm = 5;
const double uniformiteVoleeMm = 10;

/// Confort : giron + 2 × contremarche entre 600 et 650 mm (règle de Blondel,
/// indication de confort, pas une exigence du Code).
const double blondelMinMm = 600;
const double blondelMaxMm = 650;

/// Tolérance de conversion po → mm : 7 7/8 po (200,025 mm) est la limite de 200 mm.
const double _tolMm = 0.05;

// -----------------------------------------------------------------------------
// Entrées
// -----------------------------------------------------------------------------

/// Planche de limon (dimensions réelles).
enum SectionLimon {
  s2x10('2×10', 1.5, 9.25),
  s2x12('2×12', 1.5, 11.25);

  final String nom;
  final double epaisseur;
  final double profondeur;
  const SectionLimon(this.nom, this.epaisseur, this.profondeur);
}

/// Comment le giron est déterminé.
enum ModeCourse {
  /// L'utilisateur choisit le giron ; la course totale en découle.
  gironFixe,

  /// L'utilisateur donne la course horizontale disponible ; le giron en découle.
  courseDisponible,
}

class EscalierInvalide implements Exception {
  final String message;
  const EscalierInvalide(this.message);
  @override
  String toString() => message;
}

class SpecEscalier {
  /// Hauteur d'un plancher fini à l'autre.
  final double hauteurTotale;

  /// Largeur utile de l'escalier (hors tout des limons extérieurs).
  final double largeur;
  final UsageEscalier usage;
  final ModeCourse mode;

  /// Mode [ModeCourse.gironFixe] : giron voulu (nez à nez).
  final double giron;

  /// Mode [ModeCourse.courseDisponible] : distance horizontale entre la face de
  /// la 1re contremarche et celle du plancher du haut, soit (n − 1) × giron.
  final double courseDisponible;

  /// Hauteur de contremarche visée, pour choisir le nombre de contremarches.
  final double contremarcheSouhaitee;

  /// Impose le nombre de contremarches (sinon choisi automatiquement).
  final int? nombreContremarches;
  final double epaisseurMarche;

  /// Saillie du nez de marche au-delà de la contremarche.
  final double nez;
  final bool contremarchesFermees;
  final double epaisseurContremarche;
  final SectionLimon section;

  /// Entraxe maximal des limons.
  final double espacementMax;

  /// Gorge minimale (bois restant sous l'entaille la plus profonde).
  final double gorgeMin;

  /// Les mesures de traçage sont arrondies à ce pas (1/16 po ou 1 mm).
  final double precisionTrace;

  const SpecEscalier({
    required this.hauteurTotale,
    this.largeur = 36,
    this.usage = UsageEscalier.prive,
    this.mode = ModeCourse.gironFixe,
    this.giron = 10.25, // 260 mm : 10 po (254 mm) serait 1 mm sous le minimum du Code
    this.courseDisponible = 120,
    this.contremarcheSouhaitee = 7.25,
    this.nombreContremarches,
    this.epaisseurMarche = 1.5,
    this.nez = 0.75,
    this.contremarchesFermees = false,
    this.epaisseurContremarche = 0.75,
    this.section = SectionLimon.s2x12,
    this.espacementMax = 16,
    this.gorgeMin = 3.5,
    this.precisionTrace = 1 / 16,
  });

  LimitesEscalier get limites => LimitesEscalier.de(usage);

  SpecEscalier copieAvec({int? nombreContremarches}) => SpecEscalier(
    hauteurTotale: hauteurTotale,
    largeur: largeur,
    usage: usage,
    mode: mode,
    giron: giron,
    courseDisponible: courseDisponible,
    contremarcheSouhaitee: contremarcheSouhaitee,
    nombreContremarches: nombreContremarches ?? this.nombreContremarches,
    epaisseurMarche: epaisseurMarche,
    nez: nez,
    contremarchesFermees: contremarchesFermees,
    epaisseurContremarche: epaisseurContremarche,
    section: section,
    espacementMax: espacementMax,
    gorgeMin: gorgeMin,
    precisionTrace: precisionTrace,
  );

  void valider() {
    void borne(double v, double min, double max, String nom) {
      if (!v.isFinite || v < min || v > max) {
        throw EscalierInvalide(
          '$nom : valeur invalide (entre ${formatNombre(min)} et '
          '${formatNombre(max)} po).',
        );
      }
    }

    borne(hauteurTotale, 4, 400, 'Hauteur totale');
    borne(largeur, 12, 240, 'Largeur');
    borne(giron, 4, 24, 'Giron');
    borne(courseDisponible, 4, 1200, 'Course disponible');
    borne(contremarcheSouhaitee, 3, 12, 'Contremarche souhaitée');
    borne(epaisseurMarche, 0.25, 4, 'Épaisseur de la marche');
    borne(nez, 0, 4, 'Nez de marche');
    borne(epaisseurContremarche, 0.25, 2, 'Épaisseur de la contremarche');
    borne(espacementMax, 6, 48, 'Entraxe des limons');
    borne(gorgeMin, 0, 12, 'Gorge minimale');
    borne(precisionTrace, 1 / 64, 1, 'Précision du traçage');
    final n = nombreContremarches;
    if (n != null && (n < 2 || n > 100)) {
      throw const EscalierInvalide(
        'Le nombre de contremarches doit être entre 2 et 100.',
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Résultats
// -----------------------------------------------------------------------------

enum Niveau { ok, info, avertissement, erreur }

class Verification {
  final String id;
  final Niveau niveau;
  final String message;

  /// Article du Code ou source de la règle.
  final String? reference;
  const Verification(this.id, this.niveau, this.message, [this.reference]);
}

/// Ligne du tableau de traçage : marche k, dessus à k·R, siège du limon à
/// k·R − t, et position horizontale k·G (face de la contremarche suivante).
class LigneTrace {
  final int marche;
  final double hauteurDessus;
  final double hauteurSiege;
  final double course;
  const LigneTrace(this.marche, this.hauteurDessus, this.hauteurSiege, this.course);
}

/// Autre nombre de contremarches possible, avec ce qu'il donnerait.
class VarianteEscalier {
  final int nombreContremarches;
  final double contremarche;
  final double giron;
  final double course;
  final bool conforme;
  const VarianteEscalier(
    this.nombreContremarches,
    this.contremarche,
    this.giron,
    this.course,
    this.conforme,
  );
}

class ResultatEscalier {
  final SpecEscalier spec;
  final int nombreContremarches;
  int get nombreMarches => nombreContremarches - 1;

  /// Hauteur d'une contremarche (hauteur totale ÷ nombre de contremarches).
  final double contremarche;
  final double giron;

  /// Course horizontale totale : (n − 1) × giron.
  final double course;

  /// Profondeur de la planche de marche : giron + nez.
  final double profondeurMarche;

  /// Pente du limon, en degrés.
  final double angle;

  /// Distance entre deux pointes de dents voisines, le long de la pente.
  final double diagonale;

  /// Longueur du dessus du limon, de la 1re à la dernière pointe.
  final double longueurEntrePointes;

  /// Longueur de planche nécessaire (étendue réelle du profil, pieds et tête compris).
  final double longueurLimon;

  /// Longueur de planche à commander (pieds pairs, 8 pi minimum).
  final double longueurCommerciale;

  /// Bois qui reste sous l'entaille la plus profonde, mesuré à 90° du limon.
  final double gorge;

  /// Hauteur de la coupe d'aplomb du bas : R − t.
  final double hauteurDepart;

  /// Hauteur de la pointe du haut au-dessus du plancher du bas : H − t.
  final double hauteurPointeHaute;

  /// Largeur de la coupe de niveau du pied, posée sur le plancher du bas.
  final double coupePied;

  /// Hauteur de la coupe d'aplomb de la tête, contre la poutre du haut.
  final double coupeTete;

  /// Écart de la coupe d'aplomb avec la coupe d'équerre, en degrés.
  final double anglePlomb;

  /// Écart de la coupe de niveau avec la coupe d'équerre, en degrés.
  final double angleNiveau;
  final int nombreLimons;

  /// Entraxe réel des limons (centre à centre).
  final double espacementReel;

  /// Contour du limon (sans les dents intermédiaires cachées : les dents sont
  /// incluses), dans l'ordre : pied, pointe 0, siège 1, pointe 1 … pointe haute,
  /// bas de la coupe de tête, fin du dessous, retour au pied.
  final List<Pt> profil;
  final List<LigneTrace> table;

  /// Plus grands écarts de hauteur de contremarche ou de giron une fois le
  /// traçage arrondi au pas de [SpecEscalier.precisionTrace] : entre deux
  /// voisins, et sur la volée.
  final double ecartAdjacent;
  final double ecartVolee;
  final List<Verification> verifications;
  final List<VarianteEscalier> variantes;

  const ResultatEscalier({
    required this.spec,
    required this.nombreContremarches,
    required this.contremarche,
    required this.giron,
    required this.course,
    required this.profondeurMarche,
    required this.angle,
    required this.diagonale,
    required this.longueurEntrePointes,
    required this.longueurLimon,
    required this.longueurCommerciale,
    required this.gorge,
    required this.hauteurDepart,
    required this.hauteurPointeHaute,
    required this.coupePied,
    required this.coupeTete,
    required this.anglePlomb,
    required this.angleNiveau,
    required this.nombreLimons,
    required this.espacementReel,
    required this.profil,
    required this.table,
    required this.ecartAdjacent,
    required this.ecartVolee,
    required this.verifications,
    required this.variantes,
  });

  List<Verification> get erreurs =>
      verifications.where((v) => v.niveau == Niveau.erreur).toList();

  List<Verification> get avertissements =>
      verifications.where((v) => v.niveau == Niveau.avertissement).toList();

  /// Aucune erreur : toutes les exigences vérifiées sont respectées.
  bool get conforme => erreurs.isEmpty;

  /// Une mesure de traçage, arrondie au pas choisi.
  double arrondi(double v) => arrondirAuPas(v, spec.precisionTrace);

  ResultatEscalier avecVariantes(List<VarianteEscalier> v) => ResultatEscalier(
    spec: spec,
    nombreContremarches: nombreContremarches,
    contremarche: contremarche,
    giron: giron,
    course: course,
    profondeurMarche: profondeurMarche,
    angle: angle,
    diagonale: diagonale,
    longueurEntrePointes: longueurEntrePointes,
    longueurLimon: longueurLimon,
    longueurCommerciale: longueurCommerciale,
    gorge: gorge,
    hauteurDepart: hauteurDepart,
    hauteurPointeHaute: hauteurPointeHaute,
    coupePied: coupePied,
    coupeTete: coupeTete,
    anglePlomb: anglePlomb,
    angleNiveau: angleNiveau,
    nombreLimons: nombreLimons,
    espacementReel: espacementReel,
    profil: profil,
    table: table,
    ecartAdjacent: ecartAdjacent,
    ecartVolee: ecartVolee,
    verifications: verifications,
    variantes: v,
  );
}

/// Arrondit [v] au multiple de [pas] le plus proche.
double arrondirAuPas(double v, double pas) => (v / pas).round() * pas;

// -----------------------------------------------------------------------------
// Calcul
// -----------------------------------------------------------------------------

/// Calcule l'escalier. Lance [EscalierInvalide] si les entrées sont inutilisables ;
/// un escalier qui ne respecte pas le Code est quand même calculé, avec ses
/// erreurs dans [ResultatEscalier.verifications].
ResultatEscalier calculerEscalier(SpecEscalier spec, {bool metrique = false}) {
  spec.valider();
  final n = spec.nombreContremarches ?? _choisirNombre(spec);
  final base = _calculer(spec, n, metrique);

  final variantes = <VarianteEscalier>[];
  for (var v = n - 3; v <= n + 3; v++) {
    if (v == n || v < 2) continue;
    final r = _calculerOuNull(spec, v, metrique);
    if (r != null && r.conforme) {
      variantes.add(
        VarianteEscalier(v, r.contremarche, r.giron, r.course, true),
      );
    }
  }
  return base.avecVariantes(variantes);
}

ResultatEscalier? _calculerOuNull(SpecEscalier spec, int n, bool metrique) {
  try {
    return _calculer(spec, n, metrique);
  } on EscalierInvalide {
    return null;
  }
}

bool _gironPermis(LimitesEscalier lim, double gironPo) {
  final mm = poucesEnMm(gironPo);
  return mm >= lim.gironMin - _tolMm &&
      (lim.gironMax == null || mm <= lim.gironMax! + _tolMm);
}

/// Nombre de contremarches : celui dont la hauteur est la plus proche de la
/// hauteur souhaitée parmi ceux qui respectent le Code (et, avec une course
/// imposée, dont le giron respecte aussi le Code).
int _choisirNombre(SpecEscalier s) {
  final lim = s.limites;
  final h = s.hauteurTotale;
  final rMax = mmEnPouces(lim.contremarcheMax);
  final rMin = mmEnPouces(lim.contremarcheMin);
  final bas = math.max(2, (h / (rMax + _tolMm / mmParPouce)).ceil());
  final haut = (h / (rMin - _tolMm / mmParPouce)).floor();
  var candidats = [for (var n = bas; n <= haut; n++) n];
  if (candidats.isEmpty) {
    // Hauteur hors de ce que le Code permet : le plus proche, qui sera signalé.
    return math.max(2, (h / s.contremarcheSouhaitee).round());
  }
  if (s.mode == ModeCourse.courseDisponible) {
    final valides = candidats
        .where((n) => _gironPermis(lim, s.courseDisponible / (n - 1)))
        .toList();
    if (valides.isNotEmpty) candidats = valides;
  }
  double ecart(int n) => (h / n - s.contremarcheSouhaitee).abs();
  candidats.sort((a, b) {
    final c = ecart(a).compareTo(ecart(b));
    return c != 0 ? c : b.compareTo(a); // à égalité : la plus petite contremarche
  });
  return candidats.first;
}

String _l(double po, bool metrique) => formatLongueur(po, metrique: metrique);

ResultatEscalier _calculer(SpecEscalier s, int n, bool metrique) {
  final lim = s.limites;
  final h = s.hauteurTotale;
  final r = h / n;
  final t = s.epaisseurMarche;
  if (t >= r) {
    throw const EscalierInvalide(
      'L\'épaisseur de la marche doit être inférieure à la hauteur de contremarche.',
    );
  }
  final g = s.mode == ModeCourse.gironFixe
      ? s.giron
      : s.courseDisponible / (n - 1);
  final nbMarches = n - 1;
  final course = nbMarches * g;
  final d = math.sqrt(r * r + g * g);
  final cosT = g / d;
  final sinT = r / d;
  final theta = math.atan2(r, g);
  final prof = s.section.profondeur;

  // Profil. Les pointes des dents sont toutes sur la droite de pente R/G passant
  // par (0, R − t) : c'est le dessus de la planche. Le dessous lui est parallèle,
  // à la profondeur de la planche, mesurée à 90°.
  final pointes = [
    for (var k = 0; k < n; k++) Pt(k * g, (k + 1) * r - t),
  ];
  final cTop = (r - t) * cosT; // abscisse de la normale (−sin, cos) sur le dessus
  final xBas = (prof - cTop) / sinT; // où le dessous coupe le plancher (y = 0)
  final coupeTete = prof / cosT;
  final basTete = Pt(course, h - t - coupeTete);
  final pied = const Pt(0, 0);
  final finDessous = Pt(xBas, 0);

  final profil = <Pt>[pied, pointes[0]];
  for (var k = 1; k < n; k++) {
    profil
      ..add(Pt(k * g, k * r - t)) // fond de l'entaille : siège k (fin)
      ..add(pointes[k]);
  }
  profil..add(basTete)..add(finDessous);

  // Étendue de la planche le long de la pente (sommets du contour, sans les
  // fonds d'entaille qui sont à l'intérieur).
  final u = Pt(cosT, sinT);
  final sommets = [pied, pointes.first, pointes.last, basTete, finDessous];
  var mini = double.infinity;
  var maxi = -double.infinity;
  for (final p in sommets) {
    final v = p.dot(u);
    mini = math.min(mini, v);
    maxi = math.max(maxi, v);
  }
  final longueurLimon = maxi - mini;
  final commerciale = math.max(96.0, (longueurLimon / 24).ceilToDouble() * 24);

  final gorge = prof - r * cosT;

  // Limons : un à chaque bord, les autres répartis à l'entraxe maximal ou moins.
  final portee = s.largeur - s.section.epaisseur;
  final nbLimons = math.max(1, (portee / s.espacementMax - 1e-9).ceil()) + 1;
  final entraxe = portee / (nbLimons - 1);

  // Traçage arrondi : chaque hauteur et chaque position est arrondie seule (pas
  // d'addition de valeurs arrondies). On mesure l'écart des contremarches et des
  // girons qui en résultent, entre voisins et sur la volée.
  final table = [
    for (var k = 1; k < n; k++) LigneTrace(k, k * r, k * r - t, k * g),
  ];
  final p = s.precisionTrace;
  final hauteursMarquees = [
    0.0,
    for (var k = 1; k < n; k++) arrondirAuPas(k * r, p),
    h,
  ];
  final positionsMarquees = [
    0.0,
    for (var k = 1; k < n; k++) arrondirAuPas(k * g, p),
  ];
  List<double> intervalles(List<double> v) => [
    for (var i = 1; i < v.length; i++) v[i] - v[i - 1],
  ];
  var ecartAdjacent = 0.0;
  var ecartVolee = 0.0;
  for (final serie in [
    intervalles(hauteursMarquees),
    intervalles(positionsMarquees),
  ]) {
    for (var i = 1; i < serie.length; i++) {
      ecartAdjacent = math.max(ecartAdjacent, (serie[i] - serie[i - 1]).abs());
    }
    ecartVolee = math.max(
      ecartVolee,
      serie.reduce(math.max) - serie.reduce(math.min),
    );
  }

  final verifications = _verifier(
    s: s,
    lim: lim,
    r: r,
    g: g,
    h: h,
    prof: prof,
    gorge: gorge,
    xBas: xBas,
    longueurLimon: longueurLimon,
    ecartAdjacent: ecartAdjacent,
    ecartVolee: ecartVolee,
    metrique: metrique,
  );

  return ResultatEscalier(
    spec: s,
    nombreContremarches: n,
    contremarche: r,
    giron: g,
    course: course,
    profondeurMarche: g + s.nez,
    angle: radEnDeg(theta),
    diagonale: d,
    longueurEntrePointes: nbMarches * d,
    longueurLimon: longueurLimon,
    longueurCommerciale: commerciale,
    gorge: gorge,
    hauteurDepart: r - t,
    hauteurPointeHaute: h - t,
    coupePied: xBas,
    coupeTete: coupeTete,
    anglePlomb: radEnDeg(theta),
    angleNiveau: 90 - radEnDeg(theta),
    nombreLimons: nbLimons,
    espacementReel: entraxe,
    profil: profil,
    table: table,
    ecartAdjacent: ecartAdjacent,
    ecartVolee: ecartVolee,
    verifications: verifications,
    variantes: const [],
  );
}

List<Verification> _verifier({
  required SpecEscalier s,
  required LimitesEscalier lim,
  required double r,
  required double g,
  required double h,
  required double prof,
  required double gorge,
  required double xBas,
  required double longueurLimon,
  required double ecartAdjacent,
  required double ecartVolee,
  required bool metrique,
}) {
  final v = <Verification>[];
  final rMm = poucesEnMm(r);
  final gMm = poucesEnMm(g);
  final prive = s.usage == UsageEscalier.prive;
  final genre = prive ? 'escalier privé' : 'escalier commun';

  // Contremarche.
  if (rMm < lim.contremarcheMin - _tolMm || rMm > lim.contremarcheMax + _tolMm) {
    v.add(
      Verification(
        'contremarche',
        Niveau.erreur,
        'Contremarche de ${_l(r, metrique)} : le Code exige entre '
            '${_l(mmEnPouces(lim.contremarcheMin), metrique)} et '
            '${_l(mmEnPouces(lim.contremarcheMax), metrique)} ($genre).',
        'CNB 9.8.4.2',
      ),
    );
  } else {
    v.add(
      Verification(
        'contremarche',
        Niveau.ok,
        'Contremarche ${_l(r, metrique)} : dans les limites du Code.',
        'CNB 9.8.4.2',
      ),
    );
  }

  // Giron.
  final gMaxMm = lim.gironMax;
  if (!_gironPermis(lim, g)) {
    v.add(
      Verification(
        'giron',
        Niveau.erreur,
        'Giron de ${_l(g, metrique)} : le Code exige '
            '${gMaxMm == null ? 'au moins ${_l(mmEnPouces(lim.gironMin), metrique)}' : 'entre ${_l(mmEnPouces(lim.gironMin), metrique)} et ${_l(mmEnPouces(gMaxMm), metrique)}'} '
            '($genre).',
        'CNB 9.8.4.2',
      ),
    );
  } else {
    v.add(
      Verification(
        'giron',
        Niveau.ok,
        'Giron ${_l(g, metrique)} : dans les limites du Code.',
        'CNB 9.8.4.2',
      ),
    );
  }

  // Profondeur de la marche : de son giron à son giron + 25 mm.
  final nezMm = poucesEnMm(s.nez);
  if (nezMm > saillieNezMaxMm + _tolMm) {
    v.add(
      Verification(
        'profondeur',
        Niveau.erreur,
        'Nez de marche de ${_l(s.nez, metrique)} : la profondeur de la marche ne '
            'dépasse pas le giron de plus de ${formatNombre(saillieNezMaxMm, decimales: 0)} mm '
            '(${_l(mmEnPouces(saillieNezMaxMm), metrique)}).',
        'CNB 9.8.4.2',
      ),
    );
  } else {
    v.add(
      Verification(
        'profondeur',
        Niveau.ok,
        'Marche de ${_l(g + s.nez, metrique)} de profondeur (giron + nez de '
            '${_l(s.nez, metrique)}) : dans les limites du Code.',
        'CNB 9.8.4.2',
      ),
    );
  }

  // Uniformité du traçage arrondi.
  final adjMm = poucesEnMm(ecartAdjacent);
  final voleeMm = poucesEnMm(ecartVolee);
  if (adjMm > uniformiteAdjacenteMm + _tolMm || voleeMm > uniformiteVoleeMm + _tolMm) {
    v.add(
      Verification(
        'uniformite',
        Niveau.erreur,
        'Avec ce pas de traçage, les contremarches varient de '
            '${formatNombre(adjMm, decimales: 1)} mm (voisines) et '
            '${formatNombre(voleeMm, decimales: 1)} mm (volée) : le Code permet '
            '${formatNombre(uniformiteAdjacenteMm, decimales: 0)} mm et '
            '${formatNombre(uniformiteVoleeMm, decimales: 0)} mm. Utilisez un pas plus fin.',
        'CNB 9.8.4.5',
      ),
    );
  } else {
    v.add(
      Verification(
        'uniformite',
        Niveau.ok,
        'Traçage arrondi : contremarches uniformes à '
            '${formatNombre(voleeMm, decimales: 1)} mm près (permis : '
            '${formatNombre(uniformiteVoleeMm, decimales: 0)} mm).',
        'CNB 9.8.4.5',
      ),
    );
  }

  // Largeur.
  final largMm = poucesEnMm(s.largeur);
  if (largMm < lim.largeurMin - _tolMm) {
    v.add(
      Verification(
        'largeur',
        Niveau.erreur,
        'Largeur de ${_l(s.largeur, metrique)} : le Code exige au moins '
            '${_l(mmEnPouces(lim.largeurMin), metrique)} ($genre).',
        'CNB 9.8.2.1',
      ),
    );
  } else {
    v.add(
      Verification(
        'largeur',
        Niveau.ok,
        'Largeur ${_l(s.largeur, metrique)} : dans les limites du Code.',
        'CNB 9.8.2.1',
      ),
    );
  }

  // Hauteur de la volée.
  if (poucesEnMm(h) > lim.hauteurVoleeMax + _tolMm) {
    v.add(
      Verification(
        'volee',
        Niveau.erreur,
        'Volée de ${_l(h, metrique)} de hauteur : au-delà de '
            '${_l(mmEnPouces(lim.hauteurVoleeMax), metrique)}, un palier '
            'intermédiaire est exigé. Calculez chaque volée séparément.',
        'CNB 9.8.3.3',
      ),
    );
  } else {
    v.add(
      Verification(
        'volee',
        Niveau.ok,
        'Hauteur de volée ${_l(h, metrique)} : sans palier intermédiaire '
            '(maximum ${_l(mmEnPouces(lim.hauteurVoleeMax), metrique)}).',
        'CNB 9.8.3.3',
      ),
    );
  }

  // Gorge du limon (règle de métier, pas du Code).
  if (xBas < 0) {
    v.add(
      Verification(
        'gorge',
        Niveau.erreur,
        'La planche ${s.section.nom} est trop étroite pour porter la première '
            'marche : choisissez une planche plus large.',
      ),
    );
  } else if (gorge < s.gorgeMin - 1e-9) {
    v.add(
      Verification(
        'gorge',
        Niveau.erreur,
        'Gorge de ${_l(gorge, metrique)} sous les entailles : au moins '
            '${_l(s.gorgeMin, metrique)} de bois doit rester. Choisissez une '
            'planche plus large ou ajoutez un limon plein au centre.',
      ),
    );
  } else {
    v.add(
      Verification(
        'gorge',
        Niveau.ok,
        'Gorge de ${_l(gorge, metrique)} dans la ${s.section.nom} (minimum '
            '${_l(s.gorgeMin, metrique)}).',
      ),
    );
  }

  // Confort (Blondel).
  final blondel = gMm + 2 * rMm;
  if (blondel < blondelMinMm || blondel > blondelMaxMm) {
    v.add(
      Verification(
        'blondel',
        Niveau.avertissement,
        'Confort : giron + 2 × contremarche = ${formatNombre(blondel, decimales: 0)} mm. '
            'La marche est plus confortable entre ${formatNombre(blondelMinMm, decimales: 0)} et '
            '${formatNombre(blondelMaxMm, decimales: 0)} mm.',
      ),
    );
  }

  // Longueur de la planche.
  if (longueurLimon > 240) {
    v.add(
      Verification(
        'longueur',
        Niveau.avertissement,
        'Le limon demande une planche de ${formatPlanche((longueurLimon / 24).ceilToDouble() * 24, metrique: metrique)} : '
            'plus long que le 20 pi courant. Prévoyez un autre matériau ou un limon en lamellé.',
      ),
    );
  }

  // Rappels.
  v.add(
    Verification(
      'planchers',
      Niveau.info,
      'Les hauteurs sont mesurées du plancher FINI du bas au plancher FINI du '
          'haut. Si l\'un des planchers n\'est pas encore posé, tenez compte de '
          'son épaisseur : la coupe d\'aplomb du bas et la hauteur totale changent.',
    ),
  );
  v.add(
    Verification(
      'tete',
      Niveau.info,
      'La pointe du haut du limon est ${_l(s.epaisseurMarche, metrique)} sous le '
          'plancher fini du haut : elle affleure l\'ossature du plancher du haut '
          'si sous-plancher et finition ont l\'épaisseur d\'une marche. Sinon, '
          'recoupez la pointe au niveau de l\'ossature.',
    ),
  );
  v.add(
    Verification(
      'echappee',
      Niveau.info,
      'Échappée libre d\'au moins ${_l(mmEnPouces(lim.echappeeMin), metrique)} au-dessus '
          'de la ligne des nez : à vérifier avec l\'ouverture du plancher du haut.',
      'CNB 9.8.2.2',
    ),
  );
  if (!s.contremarchesFermees) {
    v.add(
      const Verification(
        'ouvertes',
        Niveau.info,
        'Contremarches ouvertes : confirmez avec votre inspecteur si l\'ouverture '
            'entre les marches est limitée.',
      ),
    );
  }
  return v;
}
