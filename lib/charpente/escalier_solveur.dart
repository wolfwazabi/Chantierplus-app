import 'dart:math' as math;

import 'escalier.dart';
import 'unites.dart';

/// Trouve les dimensions d'un escalier à partir de ce qu'on connaît (2 données ou
/// plus), avec les girons et contremarches idéals du Code.
///
/// Relations (en pouces) : hauteur = n × contremarche, course = (n − 1) × giron,
/// où n est le nombre de contremarches. Le Code (CNB 2015, section 9.8, tel
/// qu'adopté au Québec) borne la contremarche et le giron ([LimitesEscalier]) ;
/// ce qui reste libre est choisi pour le confort :
///  - giron + 2 × contremarche proche de 635 mm (25 po), au milieu de la plage de
///    confort de 600 à 650 mm ;
///  - contremarche visée de 7 1/4 po (184 mm) quand rien d'autre ne la fixe.
///
/// Les mesures trouvées sont arrondies au 1/16 po, jamais hors des bornes du Code.
/// La hauteur, la course et le nombre de contremarches sont EXACTS quand on les
/// donne ; la contremarche et le giron donnés sont des cibles qui s'ajustent.

/// Les cinq données d'un escalier.
enum DonneeEscalier { hauteur, course, giron, contremarche, nombre }

/// Confort : giron + 2 × contremarche visé, en millimètres (25 po).
const double confortCibleMm = 635;

/// Contremarche idéale quand elle n'est pas imposée : 7 1/4 po (184 mm).
const double contremarcheIdealePo = 7.25;

const double _pas = 1 / 16;
const double _tolPo = 0.05 / mmParPouce; // même tolérance que le calcul (0,05 mm)

/// Ce qu'on connaît d'un escalier (en pouces). Null : inconnu.
class DonneesEscalier {
  /// Hauteur d'un plancher fini à l'autre.
  final double? hauteur;

  /// Course horizontale : (n − 1) × giron.
  final double? course;
  final double? giron;
  final double? contremarche;
  final int? nombre;

  const DonneesEscalier({
    this.hauteur,
    this.course,
    this.giron,
    this.contremarche,
    this.nombre,
  });

  Set<DonneeEscalier> get connues => {
    if (hauteur != null) DonneeEscalier.hauteur,
    if (course != null) DonneeEscalier.course,
    if (giron != null) DonneeEscalier.giron,
    if (contremarche != null) DonneeEscalier.contremarche,
    if (nombre != null) DonneeEscalier.nombre,
  };
}

/// Une combinaison possible de contremarche et de giron.
class ChoixEscalier {
  final int nombreContremarches;
  final double hauteur;
  final double contremarche;
  final double giron;
  final double course;

  /// Plus petit = meilleur (voir [resoudreEscalier]).
  final double cout;
  const ChoixEscalier({
    required this.nombreContremarches,
    required this.hauteur,
    required this.contremarche,
    required this.giron,
    required this.course,
    required this.cout,
  });
}

class SolutionEscalier {
  final int nombreContremarches;
  final double hauteur;
  final double contremarche;
  final double giron;
  final double course;

  /// Ce que l'utilisateur a donné.
  final Set<DonneeEscalier> donnees;

  /// Explications : ajustements, arrondis, valeurs trouvées.
  final List<String> notes;

  /// Autres nombres de contremarches conformes au Code, le meilleur d'abord
  /// (vide quand le nombre est imposé par les données).
  final List<ChoixEscalier> autresChoix;

  const SolutionEscalier({
    required this.nombreContremarches,
    required this.hauteur,
    required this.contremarche,
    required this.giron,
    required this.course,
    required this.donnees,
    required this.notes,
    required this.autresChoix,
  });

  /// Les données trouvées par le calcul.
  Set<DonneeEscalier> get trouvees =>
      DonneeEscalier.values.toSet().difference(donnees);
}

/// Arrondit au 1/16 po le plus proche, puis ramène dans [min, max] SANS jamais
/// sortir des bornes du Code (vers le haut pour un minimum, vers le bas pour un
/// maximum).
double _arrondirDans(double v, double min, double? max) {
  var r = (v / _pas).round() * _pas;
  if (r < min - _tolPo) r = (min / _pas).ceil() * _pas;
  if (max != null && r > max + _tolPo) r = (max / _pas).floor() * _pas;
  return r;
}

/// Résout l'escalier. Lance [EscalierInvalide] avec un message clair si les
/// données ne suffisent pas ou sont inutilisables.
SolutionEscalier resoudreEscalier(
  DonneesEscalier d, {
  UsageEscalier usage = UsageEscalier.prive,
  bool metrique = false,
}) {
  void positif(double? v, String nom) {
    if (v != null && (!v.isFinite || v <= 0)) {
      throw EscalierInvalide('$nom : valeur invalide.');
    }
  }

  positif(d.hauteur, 'Hauteur');
  positif(d.course, 'Course');
  positif(d.giron, 'Giron');
  positif(d.contremarche, 'Contremarche');
  final nImpose = d.nombre;
  if (nImpose != null && (nImpose < 2 || nImpose > 100)) {
    throw const EscalierInvalide(
      'Le nombre de contremarches doit être entre 2 et 100.',
    );
  }

  final lim = LimitesEscalier.de(usage);
  final rMin = mmEnPouces(lim.contremarcheMin);
  final rMax = mmEnPouces(lim.contremarcheMax);
  final gMin = mmEnPouces(lim.gironMin);
  final gMax = lim.gironMax == null ? null : mmEnPouces(lim.gironMax!);
  final cible = mmEnPouces(confortCibleMm);

  // Giron et contremarche idéaux l'un pour l'autre (confort), dans le Code.
  double gironIdeal(double r) => _arrondirDans(cible - 2 * r, gMin, gMax);
  double contremarcheIdeale(double g) =>
      _arrondirDans((cible - g) / 2, rMin, rMax);

  // Hors du Code (en pouces) : 0 si dans les bornes.
  double ecartCode(double r, double g) {
    double hors(double v, double min, double? max) =>
        v < min - _tolPo
        ? min - v
        : (max != null && v > max + _tolPo ? v - max : 0);
    return hors(r, rMin, rMax) + hors(g, gMin, gMax);
  }

  double ecartConfort(double r, double g) =>
      poucesEnMm((2 * r + g - cible).abs());

  final notes = <String>[];
  var autres = <ChoixEscalier>[];
  int n;

  if (nImpose != null) {
    n = nImpose;
  } else if (d.hauteur != null && d.contremarche != null) {
    // Hauteur et contremarche : le nombre de contremarches le plus proche.
    n = (d.hauteur! / d.contremarche!).round().clamp(2, 100);
  } else if (d.hauteur != null) {
    // Hauteur connue : on cherche le meilleur nombre de contremarches.
    final h = d.hauteur!;
    ChoixEscalier? evaluer(int v) {
      final r = h / v;
      final double g;
      if (d.course != null) {
        if (v < 2) return null;
        g = d.course! / (v - 1);
      } else if (d.giron != null) {
        g = d.giron!;
      } else {
        g = gironIdeal(r);
      }
      final cout = d.course == null && d.giron == null
          ? poucesEnMm((r - contremarcheIdealePo).abs())
          : ecartConfort(r, g) +
                (d.giron != null && d.course != null
                    ? 3 * poucesEnMm((g - d.giron!).abs())
                    : 0);
      return ChoixEscalier(
        nombreContremarches: v,
        hauteur: h,
        contremarche: r,
        giron: g,
        course: (v - 1) * g,
        cout: cout,
      );
    }

    final bas = math.max(2, (h / (rMax + _tolPo)).ceil());
    final haut = math.min(100, (h / (rMin - _tolPo)).floor());
    final tous = <ChoixEscalier>[
      for (var v = bas; v <= haut; v++) ?evaluer(v),
    ];
    final conformes = tous.where((c) => ecartCode(c.contremarche, c.giron) == 0).toList()
      ..sort((a, b) {
        final c = a.cout.compareTo(b.cout);
        return c != 0 ? c : b.nombreContremarches.compareTo(a.nombreContremarches);
      });
    ChoixEscalier meilleur;
    if (conformes.isNotEmpty) {
      meilleur = conformes.first;
      autres = conformes.skip(1).take(4).toList();
    } else {
      // Rien ne respecte le Code avec ces données : le moins mauvais, qui sera
      // signalé par la vérification du Code.
      final voisins = <ChoixEscalier>[
        for (var v = math.max(2, bas - 3); v <= math.min(100, math.max(bas, haut) + 3); v++) ?evaluer(v),
      ]..sort((a, b) {
          final c = ecartCode(a.contremarche, a.giron).compareTo(ecartCode(b.contremarche, b.giron));
          return c != 0 ? c : a.cout.compareTo(b.cout);
        });
      if (voisins.isEmpty) {
        throw const EscalierInvalide('Ces données ne permettent aucun escalier.');
      }
      meilleur = voisins.first;
      notes.add(
        'Aucun nombre de contremarches ne respecte le Code avec ces données : '
        'voici le moins éloigné.',
      );
    }
    n = meilleur.nombreContremarches;
  } else if (d.course != null && d.giron != null) {
    // Course et giron : nombre de marches = course ÷ giron.
    n = (d.course! / d.giron!).round().clamp(1, 99) + 1;
  } else if (d.course != null) {
    // Course seule (ou avec la contremarche) : giron idéal, puis le nombre de marches.
    final r0 = d.contremarche ?? contremarcheIdealePo;
    final g0 = gironIdeal(r0);
    n = (d.course! / g0).round().clamp(1, 99) + 1;
  } else {
    throw const EscalierInvalide(
      'Données insuffisantes : donnez la hauteur, la course ou le nombre de '
      'contremarches.',
    );
  }

  // Giron.
  double? g;
  if (d.course != null) {
    g = d.course! / (n - 1);
  } else if (d.giron != null) {
    g = d.giron;
  }
  // Contremarche.
  double r;
  if (d.hauteur != null) {
    r = d.hauteur! / n;
  } else if (d.contremarche != null) {
    r = d.contremarche!;
  } else if (g != null) {
    r = contremarcheIdeale(g);
  } else {
    r = contremarcheIdealePo;
  }
  g ??= gironIdeal(r);

  final h = d.hauteur ?? n * r;
  final l = d.course ?? (n - 1) * g;

  // Explications.
  String po(double v) => formatLongueur(v, metrique: metrique);
  if (d.hauteur != null && d.contremarche != null && (r - d.contremarche!).abs() > _pas / 2) {
    notes.add(
      'Contremarche ajustée à ${po(r)} : $n contremarches pour la hauteur de '
      '${po(h)}.',
    );
  }
  if (d.course != null && d.giron != null && (g - d.giron!).abs() > _pas / 2) {
    notes.add(
      'Giron ajusté à ${po(g)} : ${n - 1} marches pour la course de ${po(l)}.',
    );
  }
  if (d.hauteur == null) {
    notes.add('Hauteur trouvée : ${po(h)} ($n contremarches de ${po(r)}).');
  }
  if (d.course == null && d.giron == null) {
    notes.add('Giron idéal : ${po(g)} (confort : giron + 2 × contremarche ≈ 25 po).');
  }
  if (d.course == null && d.giron != null) {
    notes.add('Course trouvée : ${po(l)} (${n - 1} marches de ${po(g)}).');
  }
  if (d.hauteur == null && d.contremarche == null && d.giron != null && d.course != null) {
    notes.add('Contremarche idéale : ${po(r)}.');
  }

  return SolutionEscalier(
    nombreContremarches: n,
    hauteur: h,
    contremarche: r,
    giron: g,
    course: l,
    donnees: d.connues,
    notes: notes,
    autresChoix: autres,
  );
}
