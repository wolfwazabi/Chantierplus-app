import 'dart:convert';

import 'projet.dart';

/// Les réglages habituels de l'entrepreneur : ses choix de construction (rives, étriers,
/// entremises, poutres, sous-plancher, bois, ossature des murs…), sans les mesures d'un projet
/// (forme, côté de la maison, portes et fenêtres, nom). Un nouveau calcul et la lecture d'un plan
/// partent de ces réglages ; le plan a toujours le dernier mot sur ce qu'il indique.
///
/// Gardés au format JSON du projet (mêmes clés), pour être validés par [ProjetCharpente.fromJson].
class ReglagesHabituels {
  /// Choix de construction du plancher (clés du JSON du projet).
  static const clesPlancher = [
    'espacement',
    'section',
    'bordureDouble',
    'riveDouble',
    'etriers',
    'entremises',
    'panneau',
    'decalageMin',
    'marge',
    'longueursPlanches',
    'etriersBordures',
    'entremisesAuto',
    'entremisesEspacement',
    'entremisesAlternees',
    'coupesSeparees',
    'poutres',
    'clousEtriers',
    'clousParEtrier',
    'clousParBoite',
    'margeClous',
  ];

  /// Plancher : clés du JSON. Null : pas de réglages habituels du plancher.
  final Map<String, dynamic>? plancher;

  /// Murs : `params` (ossature, linteaux, feuilles, fourrures, marges). La hauteur des murs est
  /// une mesure du projet : elle n'en fait pas partie.
  final Map<String, dynamic>? murs;

  const ReglagesHabituels._({this.plancher, this.murs});

  /// Aucun réglage gardé.
  static const vides = ReglagesHabituels._();

  bool get estVide => plancher == null && murs == null;

  static Map<String, dynamic> _plancherDe(ProjetCharpente p) {
    final j = p.toJson()['plancher'] as Map<String, dynamic>;
    return {for (final k in clesPlancher) k: j[k]};
  }

  static Map<String, dynamic> _mursDe(ProjetCharpente p) {
    final j = p.toJson()['murs'] as Map<String, dynamic>;
    return {'params': j['params']};
  }

  /// Garde les réglages du plancher de [p] (ceux des murs ne changent pas).
  ReglagesHabituels avecPlancherDe(ProjetCharpente p) =>
      ReglagesHabituels._(plancher: _plancherDe(p), murs: murs);

  /// Garde les réglages des murs de [p] (ceux du plancher ne changent pas).
  ReglagesHabituels avecMursDe(ProjetCharpente p) =>
      ReglagesHabituels._(plancher: plancher, murs: _mursDe(p));

  /// [p] avec ces réglages ; ses mesures (forme, côté de la maison, ouvertures, nom) restent.
  /// Des réglages illisibles (version future, valeur corrompue) laissent [p] tel quel.
  ProjetCharpente appliquer(
    ProjetCharpente p, {
    bool auPlancher = true,
    bool auxMurs = true,
  }) {
    if (estVide) return p;
    try {
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      if (auPlancher && plancher != null) {
        (j['plancher'] as Map<String, dynamic>).addAll(plancher!);
      }
      if (auxMurs && murs != null) {
        (j['murs'] as Map<String, dynamic>).addAll(murs!);
      }
      return ProjetCharpente.fromJson(j);
    } on FormatException {
      return p;
    } on TypeError {
      return p;
    }
  }

  /// Le plancher de [p] suit ces réglages (rien à garder ni à remettre).
  bool plancherSuivi(ProjetCharpente p) =>
      plancher != null && jsonEncode(_plancherDe(p)) == jsonEncode(plancher);

  /// Les murs de [p] suivent ces réglages.
  bool mursSuivis(ProjetCharpente p) =>
      murs != null && jsonEncode(_mursDe(p)) == jsonEncode(murs);

  Map<String, dynamic> toJson() => {
    'v': 1,
    if (plancher != null) 'plancher': plancher,
    if (murs != null) 'murs': murs,
  };

  /// Lit des réglages gardés. Ce qui ne s'applique pas à un projet est écarté : un réglage
  /// abîmé ne bloque jamais un calcul.
  static ReglagesHabituels depuis(Object? j) {
    if (j is! Map || j['v'] != 1) return vides;
    Map<String, dynamic>? partie(Object? x, List<String> cles) {
      if (x is! Map) return null;
      return {
        for (final k in cles)
          if (x.containsKey(k)) k: x[k],
      };
    }

    final plancher = partie(j['plancher'], clesPlancher);
    final murs = partie(j['murs'], const ['params']);
    var r = ReglagesHabituels._(
      plancher: plancher != null && plancher.length == clesPlancher.length
          ? plancher
          : null,
      murs: murs != null && murs.length == 1 ? murs : null,
    );
    // Chaque partie doit donner un projet valide, sinon elle est écartée.
    const base = ProjetCharpente();
    bool valide(ReglagesHabituels x, {required bool auPlancher}) {
      try {
        final j = jsonDecode(jsonEncode(base.toJson())) as Map<String, dynamic>;
        if (auPlancher) {
          (j['plancher'] as Map<String, dynamic>).addAll(x.plancher!);
        } else {
          (j['murs'] as Map<String, dynamic>).addAll(x.murs!);
        }
        ProjetCharpente.fromJson(j);
        return true;
      } on FormatException {
        return false;
      } on TypeError {
        return false;
      }
    }

    if (r.plancher != null && !valide(r, auPlancher: true)) {
      r = ReglagesHabituels._(murs: r.murs);
    }
    if (r.murs != null && !valide(r, auPlancher: false)) {
      r = ReglagesHabituels._(plancher: r.plancher);
    }
    return r;
  }

  /// Pour la lecture d'un plan : ce que le serveur applique là où le plan ne dit rien.
  Map<String, dynamic>? pourLecturePlan() => estVide ? null : toJson();
}
