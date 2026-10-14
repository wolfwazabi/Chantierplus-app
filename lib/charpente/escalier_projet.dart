import 'composite.dart';
import 'escalier.dart';
import 'unites.dart';

/// Les choix d'un escalier (le formulaire de l'écran Escalier), enregistrables : dans un projet
/// de charpente, l'escalier est jumelé au plancher et descend d'un de ses côtés. Tout est en
/// POUCES.
class ParametresEscalier {
  /// Hauteur totale : dans un projet, celle de la plateforme (du sol fini au dessus fini).
  final double hauteur;
  final double largeur;
  final UsageEscalier usage;
  final ModeCourse mode;
  final double giron;
  final double course;
  final double contremarcheSouhaitee;

  /// Nombre de contremarches choisi à la main ([nombreImpose]) ; sinon le calcul le choisit.
  final bool nombreImpose;
  final int nombre;
  final double epaisseurMarche;
  final double nez;
  final bool contremarchesFermees;
  final double epaisseurContremarche;
  final SectionLimon section;
  final double entraxe;

  /// Marches en composite (escalier seul) : l'identifiant du produit. Dans un projet, le
  /// composite suit le plancher.
  final String? composite;

  /// Projet : le côté du plancher d'où l'escalier descend, et sa position sur ce côté (centré,
  /// ou à [distanceCoin] du coin de gauche, vu de l'extérieur face à la plateforme).
  final int cote;
  final bool centre;
  final double distanceCoin;

  const ParametresEscalier({
    this.hauteur = 108, // 9 pi
    this.largeur = 36,
    this.usage = UsageEscalier.prive,
    this.mode = ModeCourse.gironFixe,
    this.giron = 10.25,
    this.course = 144,
    this.contremarcheSouhaitee = 7.25,
    this.nombreImpose = false,
    this.nombre = 15,
    this.epaisseurMarche = 1.5,
    this.nez = 0.75,
    this.contremarchesFermees = false,
    this.epaisseurContremarche = 0.75,
    this.section = SectionLimon.s2x12,
    this.entraxe = 16,
    this.composite,
    this.cote = 0,
    this.centre = true,
    this.distanceCoin = 0,
  });

  ParametresEscalier copieAvec({
    double? hauteur,
    double? largeur,
    UsageEscalier? usage,
    ModeCourse? mode,
    double? giron,
    double? course,
    double? contremarcheSouhaitee,
    bool? nombreImpose,
    int? nombre,
    double? epaisseurMarche,
    double? nez,
    bool? contremarchesFermees,
    double? epaisseurContremarche,
    SectionLimon? section,
    double? entraxe,
    String? Function()? composite,
    int? cote,
    bool? centre,
    double? distanceCoin,
  }) => ParametresEscalier(
    hauteur: hauteur ?? this.hauteur,
    largeur: largeur ?? this.largeur,
    usage: usage ?? this.usage,
    mode: mode ?? this.mode,
    giron: giron ?? this.giron,
    course: course ?? this.course,
    contremarcheSouhaitee: contremarcheSouhaitee ?? this.contremarcheSouhaitee,
    nombreImpose: nombreImpose ?? this.nombreImpose,
    nombre: nombre ?? this.nombre,
    epaisseurMarche: epaisseurMarche ?? this.epaisseurMarche,
    nez: nez ?? this.nez,
    contremarchesFermees: contremarchesFermees ?? this.contremarchesFermees,
    epaisseurContremarche: epaisseurContremarche ?? this.epaisseurContremarche,
    section: section ?? this.section,
    entraxe: entraxe ?? this.entraxe,
    composite: composite != null ? composite() : this.composite,
    cote: cote ?? this.cote,
    centre: centre ?? this.centre,
    distanceCoin: distanceCoin ?? this.distanceCoin,
  );

  /// La spécification du calcul. [composite] : le produit des marches (dans un projet, celui du
  /// plancher) ; [contremarcheHautFournie] : la plus haute contremarche est la fascia du
  /// plancher (escalier jumelé à une plateforme en composite).
  SpecEscalier versSpec({
    required bool metrique,
    ProduitComposite? composite,
    bool contremarcheHautFournie = false,
  }) => SpecEscalier(
    hauteurTotale: hauteur,
    largeur: largeur,
    usage: usage,
    mode: mode,
    giron: giron,
    courseDisponible: course,
    contremarcheSouhaitee: contremarcheSouhaitee,
    nombreContremarches: nombreImpose ? nombre : null,
    epaisseurMarche: epaisseurMarche,
    nez: nez,
    contremarchesFermees: contremarchesFermees,
    epaisseurContremarche: epaisseurContremarche,
    section: section,
    espacementMax: entraxe,
    composite: composite,
    contremarcheHautFournie: contremarcheHautFournie,
    // Traçage au 1/16 po ou au millimètre, selon le système d'unités.
    precisionTrace: metrique ? 1 / mmParPouce : 1 / 16,
  );

  Map<String, dynamic> toJson() => {
    'hauteur': hauteur,
    'largeur': largeur,
    'usage': usage.name,
    'mode': mode.name,
    'giron': giron,
    'course': course,
    'souhaitee': contremarcheSouhaitee,
    'nombreImpose': nombreImpose,
    'nombre': nombre,
    'epaisseurMarche': epaisseurMarche,
    'nez': nez,
    'fermees': contremarchesFermees,
    'epaisseurContremarche': epaisseurContremarche,
    'section': section.name,
    'entraxe': entraxe,
    if (composite != null) 'composite': composite,
    'cote': cote,
    'centre': centre,
    'distanceCoin': distanceCoin,
  };

  /// Lit des choix enregistrés. Lance [FormatException] si une valeur est mal formée ; les
  /// valeurs hors du Code sont laissées au calcul, qui le dit.
  factory ParametresEscalier.fromJson(Object? j) {
    if (j is! Map) {
      throw const FormatException('escalier invalide');
    }
    double nombreDe(String cle, double min, double max) {
      final v = j[cle];
      if (v is! num || !v.isFinite || v < min || v > max) {
        throw FormatException('escalier : $cle invalide');
      }
      return v.toDouble();
    }

    int entierDe(String cle, int min, int max) {
      final v = j[cle];
      if (v is! int || v < min || v > max) {
        throw FormatException('escalier : $cle invalide');
      }
      return v;
    }

    bool boolDe(String cle) {
      final v = j[cle];
      if (v is! bool) {
        throw FormatException('escalier : $cle invalide');
      }
      return v;
    }

    T enumDe<T extends Enum>(String cle, List<T> valeurs) {
      final v = valeurs.where((e) => e.name == j[cle]);
      if (v.isEmpty) {
        throw FormatException('escalier : $cle invalide');
      }
      return v.first;
    }

    final composite = j['composite'];
    if (composite != null &&
        (composite is! String ||
            !produitsComposite.any((p) => p.id == composite))) {
      throw const FormatException('escalier : produit composite inconnu');
    }
    return ParametresEscalier(
      hauteur: nombreDe('hauteur', 4, 400),
      largeur: nombreDe('largeur', 12, 240),
      usage: enumDe('usage', UsageEscalier.values),
      mode: enumDe('mode', ModeCourse.values),
      giron: nombreDe('giron', 4, 24),
      course: nombreDe('course', 4, 1200),
      contremarcheSouhaitee: nombreDe('souhaitee', 3, 12),
      nombreImpose: boolDe('nombreImpose'),
      nombre: entierDe('nombre', 2, 100),
      epaisseurMarche: nombreDe('epaisseurMarche', 0.25, 4),
      nez: nombreDe('nez', 0, 4),
      contremarchesFermees: boolDe('fermees'),
      epaisseurContremarche: nombreDe('epaisseurContremarche', 0.25, 2),
      section: enumDe('section', SectionLimon.values),
      entraxe: nombreDe('entraxe', 6, 48),
      composite: composite as String?,
      cote: entierDe('cote', 0, 23),
      centre: boolDe('centre'),
      distanceCoin: nombreDe('distanceCoin', 0, 12000),
    );
  }
}
