import 'dart:math' as math;

import 'geometrie.dart';
import 'mur.dart';
import 'projet.dart';
import 'unites.dart';

/// Lecture d'un plan (PDF, photos) par l'assistant : le projet de charpente lu, plus la liste des
/// valeurs à vérifier. Rien n'est appliqué avant que l'utilisateur ait confirmé à la main chaque
/// valeur incertaine.

/// À quel point une valeur est sûre.
enum NiveauValeur {
  /// Écrite clairement sur le plan.
  lu,

  /// Obtenue à partir d'autres cotes, de l'échelle ou d'un tableau : à vérifier.
  deduit,

  /// Illisible, ambiguë ou supposée : l'utilisateur doit la confirmer.
  incertain,
}

enum ConfianceLecture { elevee, moyenne, faible }

/// Ce qu'une valeur est : une longueur (pouces), un angle (degrés), un nombre (entraxe), un
/// nombre entier (poutres, plis, pieux) ou un choix.
enum GenreValeur { longueur, angle, nombre, entier, choix }

/// Une valeur relevée sur le plan, retrouvée dans le projet par son [chemin] (ex. :
/// `plancher.forme.longueur`, `murs.ouverturesContour.0.1.largeur`).
class ValeurLue {
  final String chemin;
  final NiveauValeur niveau;

  /// Pourquoi elle est déduite ou incertaine (texte du serveur ou de l'assistant).
  final String raison;

  /// La cote telle qu'imprimée sur le plan (« 12'-6" »), si elle y est écrite.
  final String lecture;

  /// La cote du plan convertie par le serveur (pouces), quand elle ne correspond pas à la
  /// valeur lue.
  final double? valeurPlan;

  /// Le serveur a converti la cote imprimée lui-même : elle correspond à la valeur lue.
  final bool verifiee;

  const ValeurLue({
    required this.chemin,
    required this.niveau,
    this.raison = '',
    this.lecture = '',
    this.valeurPlan,
    this.verifiee = false,
  });

  /// Lit une valeur de la réponse du serveur. Null si elle est inutilisable.
  static ValeurLue? depuis(Object? j) {
    if (j is! Map) return null;
    final chemin = j['chemin'];
    if (chemin is! String || genreDuChemin(chemin) == null) return null;
    final niveau = NiveauValeur.values.where((n) => n.name == j['niveau']);
    final plan = j['valeurPlan'];
    return ValeurLue(
      chemin: chemin,
      // Niveau inconnu : le plus prudent.
      niveau: niveau.isEmpty ? NiveauValeur.incertain : niveau.first,
      raison: j['raison'] is String ? j['raison'] as String : '',
      lecture: j['lecture'] is String ? j['lecture'] as String : '',
      valeurPlan: plan is num && plan.isFinite ? plan.toDouble() : null,
      verifiee: j['verifiee'] == true,
    );
  }
}

/// La lecture d'un plan : le projet (JSON du serveur, modifiable valeur par valeur) et ce qu'il
/// reste à confirmer. Immuable : chaque correction donne une nouvelle lecture.
class LecturePlan {
  final String explication;
  final List<String> hypotheses;
  final String niveauLu;
  final String echelle;
  final ConfianceLecture confiance;
  final List<ValeurLue> valeurs;

  /// Chemins que l'utilisateur a confirmés ou corrigés.
  final Set<String> confirmees;

  /// Le projet tel que le serveur l'a filtré, avec les corrections de l'utilisateur.
  final Map<String, dynamic> projetJson;

  /// Le projet lu (calculable) : les positions des ouvertures sont celles de l'application,
  /// depuis le début de chaque mur (voir [projetDepuisPlan]).
  final ProjetCharpente projet;

  const LecturePlan._({
    required this.explication,
    required this.hypotheses,
    required this.niveauLu,
    required this.echelle,
    required this.confiance,
    required this.valeurs,
    required this.confirmees,
    required this.projetJson,
    required this.projet,
  });

  /// Lit la réponse de la fonction `lirePlanCharpente`. Lance [FormatException] si le projet
  /// est inutilisable.
  factory LecturePlan.depuis(Map<String, dynamic> reponse) {
    final projetJson = _copieProfonde(reponse['projet']);
    if (projetJson is! Map<String, dynamic>) {
      throw const FormatException('projet absent');
    }
    final confiance = ConfianceLecture.values.where(
      (c) => c.name == reponse['confiance'],
    );
    final brutes = reponse['valeurs'];
    final valeurs = <ValeurLue>[];
    if (brutes is List) {
      for (final b in brutes) {
        final v = ValeurLue.depuis(b);
        // Une valeur dont le chemin ne mène à rien dans le projet n'est pas affichée.
        if (v != null && lireChemin(projetJson, v.chemin) != null) {
          valeurs.add(v);
        }
      }
    }
    return LecturePlan._(
      explication: _texte(reponse['explication']),
      hypotheses: [
        if (reponse['hypotheses'] is List)
          for (final h in reponse['hypotheses'] as List)
            if (h is String && h.trim().isNotEmpty) h.trim(),
      ],
      niveauLu: _texte(reponse['niveau']),
      echelle: _texte(reponse['echelle']),
      confiance: confiance.isEmpty ? ConfianceLecture.moyenne : confiance.first,
      valeurs: List.unmodifiable(valeurs),
      confirmees: const {},
      projetJson: projetJson,
      projet: projetDepuisPlan(projetJson),
    );
  }

  List<ValeurLue> get aConfirmer =>
      valeurs.where((v) => v.niveau == NiveauValeur.incertain).toList();

  List<ValeurLue> get aVerifier =>
      valeurs.where((v) => v.niveau == NiveauValeur.deduit).toList();

  List<ValeurLue> get lues =>
      valeurs.where((v) => v.niveau == NiveauValeur.lu).toList();

  bool estConfirmee(String chemin) => confirmees.contains(chemin);

  /// Valeurs incertaines pas encore confirmées.
  int get restantes =>
      aConfirmer.where((v) => !confirmees.contains(v.chemin)).length;

  /// On peut appliquer le projet quand plus rien d'incertain n'attend.
  bool get toutConfirme => restantes == 0;

  /// La valeur actuelle d'un chemin dans le projet.
  Object? valeurDe(String chemin) => lireChemin(projetJson, chemin);

  /// Ce que le calcul ignorerait en silence, à montrer à l'utilisateur : portes et fenêtres placées
  /// sur un mur qui n'existe pas dans la forme du plancher.
  List<String> get avertissements {
    final p = projet;
    if (!p.mursActifs || p.murs.mode != ModeMurs.contour) return const [];
    final int nombre;
    try {
      nombre = p.plancher.forme.construire().nombre;
    } on FormeInvalide {
      return const [];
    }
    return [
      for (final e in p.murs.ouverturesContour.entries)
        if (e.key >= nombre)
          for (final o in e.value)
            '${nomOuverture(o)} : le mur ${e.key + 1} n\'existe pas '
                '(le plancher a $nombre murs) ; elle ne serait pas comptée.',
    ];
  }

  /// L'utilisateur confirme la valeur telle quelle.
  LecturePlan confirmer(String chemin) {
    if (!valeurs.any((v) => v.chemin == chemin)) return this;
    return _avec(confirmees: {...confirmees, chemin});
  }

  /// L'utilisateur retire sa confirmation (il veut revoir la valeur).
  LecturePlan annulerConfirmation(String chemin) {
    if (!confirmees.contains(chemin)) return this;
    return _avec(confirmees: {...confirmees}..remove(chemin));
  }

  /// L'utilisateur corrige une valeur. La confirmation est retirée : il confirme la valeur finale
  /// à la main. Lance [FormatException] si la valeur n'est pas permise pour ce chemin (la lecture
  /// reste intacte).
  LecturePlan modifier(String chemin, Object valeur) {
    if (!valeurs.any((v) => v.chemin == chemin)) {
      throw const FormatException('valeur inconnue');
    }
    final genre = genreDuChemin(chemin)!;
    if (genre == GenreValeur.choix) {
      if (valeur is! String || !choixDuChemin(chemin).contains(valeur)) {
        throw const FormatException('choix non permis');
      }
    } else {
      final (min, max) = bornesDuChemin(chemin);
      if (valeur is! num ||
          !valeur.isFinite ||
          valeur < min - 1e-9 ||
          valeur > max + 1e-9) {
        throw const FormatException('valeur hors des bornes');
      }
    }
    if (genre == GenreValeur.entier) {
      final n = valeur as num;
      if ((n - n.round()).abs() > 1e-9) {
        throw const FormatException('nombre entier attendu');
      }
      valeur = n.round();
    }
    var json = _avecValeur(projetJson, chemin, valeur);
    if (valeur == 'fenetre' && chemin.endsWith('.type')) {
      // Une porte devenue fenêtre garde son allège de 0 : on prend la valeur courante (36 po).
      final allege = chemin.replaceFirst(RegExp(r'\.type$'), '.allege');
      final actuelle = lireChemin(json, allege);
      if (actuelle is num && actuelle == 0) {
        json = _avecValeur(json, allege, 36);
      }
    }
    return _avec(
      projetJson: json,
      projet: projetDepuisPlan(json),
      confirmees: {...confirmees}..remove(chemin),
    );
  }

  LecturePlan _avec({
    Map<String, dynamic>? projetJson,
    ProjetCharpente? projet,
    Set<String>? confirmees,
  }) => LecturePlan._(
    explication: explication,
    hypotheses: hypotheses,
    niveauLu: niveauLu,
    echelle: echelle,
    confiance: confiance,
    valeurs: valeurs,
    confirmees: confirmees ?? this.confirmees,
    projetJson: projetJson ?? this.projetJson,
    projet: projet ?? this.projet,
  );
}

String _texte(Object? v) => v is String ? v.trim() : '';

/// Le projet du JSON de la lecture. Sur un plan, la position d'une porte ou d'une fenêtre se
/// mesure depuis le COIN extérieur du côté ; l'application la mesure depuis le début du MUR, qui
/// est raccourci là où il s'appuie sur le mur voisin (3 1/2 po en 2×4). La conversion se fait ici,
/// avec la même géométrie que le calcul des murs, pour que le modèle n'ait rien à calculer.
/// Lance [FormatException] si le JSON est inutilisable.
ProjetCharpente projetDepuisPlan(Map<String, dynamic> json) {
  final p = ProjetCharpente.fromJson(json);
  if (!p.mursActifs || p.murs.mode != ModeMurs.contour) return p;
  final List<SpecMur> murs;
  try {
    murs = mursDuContour(
      p.plancher.forme.construire(),
      hauteur: p.murs.hauteur,
      section: p.murs.params.section,
    );
  } on FormeInvalide {
    // Forme impossible : le calcul la signalera ; les positions restent celles du plan.
    return p;
  }
  final converties = <int, List<Ouverture>>{
    for (final e in p.murs.ouverturesContour.entries)
      e.key: [
        for (final o in e.value)
          e.key < murs.length
              ? o.avecPosition(
                  math.max(0, o.position - murs[e.key].retraitDebut),
                )
              : o,
      ],
  };
  return p.copieAvec(murs: p.murs.copieAvec(ouverturesContour: converties));
}

// =============================================================================
// Chemins : les mêmes que ceux que le serveur accepte (voir functions/src/lecture_plans.js)
// =============================================================================

final _ouverture = RegExp(
  r'^(murs\.ouverturesContour\.\d{1,2}\.\d{1,2}|murs\.libres\.\d{1,2}\.ouvertures\.\d{1,2})\.(largeur|hauteur|allege|position|type)$',
);

/// Le genre d'un chemin permis ; null pour tout autre chemin.
GenreValeur? genreDuChemin(String chemin) {
  if (chemin == 'plancher.espacement' || chemin == 'murs.params.espacement') {
    return GenreValeur.nombre;
  }
  if (chemin == 'plancher.section' || chemin == 'murs.params.section') {
    return GenreValeur.choix;
  }
  // Structure d'un plancher sur pieux : poutres, pieux, étriers.
  if (chemin == 'plancher.etriers' || chemin == 'plancher.poutres.section') {
    return GenreValeur.choix;
  }
  if (RegExp(r'^plancher\.poutres\.(nombre|plis|pieux)$').hasMatch(chemin)) {
    return GenreValeur.entier;
  }
  if (chemin == 'plancher.poutres.retraitPieux') return GenreValeur.longueur;
  if (RegExp(r'^plancher\.forme\.angles\.\d{1,2}$').hasMatch(chemin)) {
    return GenreValeur.angle;
  }
  if (RegExp(r'^plancher\.forme\.(longueur|largeur)$').hasMatch(chemin) ||
      RegExp(r'^plancher\.forme\.cotes\.\d{1,2}$').hasMatch(chemin) ||
      RegExp(r'^plancher\.forme\.points\.\d{1,2}\.[01]$').hasMatch(chemin) ||
      chemin == 'murs.hauteur' ||
      RegExp(r'^murs\.libres\.\d{1,2}\.(longueur|hauteur)$').hasMatch(chemin)) {
    return GenreValeur.longueur;
  }
  final o = _ouverture.firstMatch(chemin);
  if (o != null) {
    return o[2] == 'type' ? GenreValeur.choix : GenreValeur.longueur;
  }
  return null;
}

/// Les choix permis d'un chemin de genre « choix ».
List<String> choixDuChemin(String chemin) {
  if (chemin == 'plancher.section' || chemin == 'plancher.poutres.section') {
    return const ['2×6', '2×8', '2×10', '2×12'];
  }
  if (chemin == 'plancher.etriers') {
    return const ['aucun', 'unBout', 'deuxBouts'];
  }
  if (chemin == 'murs.params.section') return const ['2×4', '2×6'];
  if (chemin.endsWith('.type')) return const ['porte', 'fenetre'];
  return const [];
}

/// Bornes permises d'un chemin numérique (celles du filtre du serveur) : pouces, degrés ou
/// entraxe en pouces.
(double, double) bornesDuChemin(String chemin) {
  switch (genreDuChemin(chemin)) {
    case GenreValeur.angle:
      return (0.01, 359.99);
    case GenreValeur.nombre:
      return (6, 48);
    case GenreValeur.entier:
      return switch (chemin) {
        'plancher.poutres.nombre' => (1, 6),
        'plancher.poutres.plis' => (1, 5),
        _ => (2, 10), // pieux par poutre
      };
    case GenreValeur.longueur:
      if (chemin == 'plancher.poutres.retraitPieux') return (0, 120);
      // Un coin du plancher peut avoir une coordonnée négative.
      if (chemin.startsWith('plancher.forme.points.')) {
        return (-pouceMaxSaisie, pouceMaxSaisie);
      }
      // L'allège et la position peuvent être nulles.
      if (chemin.endsWith('.allege') || chemin.endsWith('.position')) {
        return (0, pouceMaxSaisie);
      }
      // Murs : hauteur de 2 à 20 pi, longueur d'un mur libre de 6 po à 100 pi.
      if (chemin == 'murs.hauteur' ||
          RegExp(r'^murs\.libres\.\d+\.hauteur$').hasMatch(chemin)) {
        return (24, 240);
      }
      if (RegExp(r'^murs\.libres\.\d+\.longueur$').hasMatch(chemin)) {
        return (6, 1200);
      }
      // Cotes du plancher et dimensions d'une ouverture.
      return (1, pouceMaxSaisie);
    case GenreValeur.choix:
    case null:
      return (0, 0);
  }
}

/// La valeur au bout d'un chemin (null si le chemin ne mène à rien).
Object? lireChemin(Object? json, String chemin) {
  Object? v = json;
  for (final segment in chemin.split('.')) {
    if (v is Map) {
      v = v[segment];
    } else if (v is List) {
      final i = int.tryParse(segment);
      if (i == null || i < 0 || i >= v.length) return null;
      v = v[i];
    } else {
      return null;
    }
    if (v == null) return null;
  }
  return v;
}

/// Copie du JSON avec une valeur remplacée. Lance [FormatException] si le chemin ne mène à rien.
Map<String, dynamic> _avecValeur(
  Map<String, dynamic> json,
  String chemin,
  Object valeur,
) {
  final copie = _copieProfonde(json) as Map<String, dynamic>;
  final segments = chemin.split('.');
  Object? v = copie;
  for (var i = 0; i < segments.length - 1; i++) {
    final s = segments[i];
    if (v is Map) {
      v = v[s];
    } else if (v is List) {
      final k = int.tryParse(s);
      if (k == null || k < 0 || k >= v.length) {
        throw const FormatException('chemin inconnu');
      }
      v = v[k];
    } else {
      throw const FormatException('chemin inconnu');
    }
  }
  final dernier = segments.last;
  if (v is Map && v.containsKey(dernier)) {
    v[dernier] = valeur;
  } else if (v is List) {
    final k = int.tryParse(dernier);
    if (k == null || k < 0 || k >= v.length) {
      throw const FormatException('chemin inconnu');
    }
    v[k] = valeur;
  } else {
    throw const FormatException('chemin inconnu');
  }
  return copie;
}

/// Copie profonde d'un JSON reçu (cartes `Map<Object?, Object?>` comprises).
Object? _copieProfonde(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) '${e.key}': _copieProfonde(e.value),
    };
  }
  if (v is List) return [for (final e in v) _copieProfonde(e)];
  return v;
}

// =============================================================================
// Libellés lisibles
// =============================================================================

String _champ(String c) => switch (c) {
  'largeur' => 'largeur',
  'hauteur' => 'hauteur',
  'allege' => 'allège (du plancher au bas du cadre)',
  'position' => 'position (du coin extérieur au centre)',
  'type' => 'type (porte ou fenêtre)',
  _ => c,
};

/// « Mur 1 — Fenêtre F1 — largeur » : ce que désigne un chemin, pour l'utilisateur.
String libelleChemin(Map<String, dynamic> projetJson, String chemin) {
  final p = chemin.split('.');
  switch (chemin) {
    case 'plancher.forme.longueur':
      return 'Plancher — longueur';
    case 'plancher.forme.largeur':
      return 'Plancher — largeur';
    case 'plancher.espacement':
      return 'Plancher — entraxe des solives';
    case 'plancher.section':
      return 'Plancher — section des solives';
    case 'murs.hauteur':
      return 'Murs — hauteur';
    case 'murs.params.espacement':
      return 'Murs — entraxe des montants';
    case 'murs.params.section':
      return 'Murs — section des montants';
    case 'plancher.etriers':
      return 'Plancher — étriers de solive';
    case 'plancher.poutres.nombre':
      return 'Plancher — nombre de poutres';
    case 'plancher.poutres.plis':
      return 'Plancher — plis de chaque poutre';
    case 'plancher.poutres.section':
      return 'Plancher — section des poutres';
    case 'plancher.poutres.pieux':
      return 'Plancher — pieux par poutre';
    case 'plancher.poutres.retraitPieux':
      return 'Plancher — premier pieu (distance du bord)';
  }
  if (chemin.startsWith('plancher.forme.cotes.')) {
    return 'Plancher — côté ${int.parse(p[3]) + 1}';
  }
  if (chemin.startsWith('plancher.forme.angles.')) {
    final i = int.parse(p[3]);
    return 'Plancher — angle entre les côtés ${i + 1} et ${i + 2}';
  }
  if (chemin.startsWith('plancher.forme.points.')) {
    return 'Plancher — coin ${int.parse(p[3]) + 1} (${p[4] == '0' ? 'x' : 'y'})';
  }
  if (chemin.startsWith('murs.ouverturesContour.')) {
    final cote = int.parse(p[2]);
    final o = lireChemin(projetJson, p.sublist(0, 4).join('.'));
    return 'Mur ${cote + 1} — ${_nomOuverture(o, int.parse(p[3]))} — ${_champ(p[4])}';
  }
  if (chemin.startsWith('murs.libres.')) {
    final mur = lireChemin(projetJson, p.sublist(0, 3).join('.'));
    final nom = mur is Map && '${mur['nom'] ?? ''}'.isNotEmpty
        ? '${mur['nom']}'
        : 'Mur ${int.parse(p[2]) + 1}';
    if (p[3] == 'ouvertures') {
      final o = lireChemin(projetJson, p.sublist(0, 5).join('.'));
      return '$nom — ${_nomOuverture(o, int.parse(p[4]))} — ${_champ(p[5])}';
    }
    return '$nom — ${_champ(p[3])}';
  }
  return chemin;
}

/// « Fenêtre F1 », « Porte P2 », ou « Porte » sans repère.
String nomOuverture(Ouverture o) {
  final type = o.type == TypeOuverture.porte ? 'Porte' : 'Fenêtre';
  final nom = o.nom.trim();
  return nom.isEmpty ? type : '$type $nom';
}

/// « Fenêtre F1 », « Porte 2 »…
String _nomOuverture(Object? o, int rang) {
  final type = o is Map && o['type'] == 'porte' ? 'Porte' : 'Fenêtre';
  final nom = o is Map ? '${o['nom'] ?? ''}'.trim() : '';
  return nom.isEmpty ? '$type ${rang + 1}' : '$type $nom';
}
