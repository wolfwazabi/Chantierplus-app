/// Correction des heures d'un employé par un admin (tableau admin des feuilles de temps).
///
/// L'admin ne saisit que ce que l'employé saisit lui-même (chantier, début, fin, pauses,
/// voyagement) : les heures payées sont toujours recalculées par le serveur
/// (`corrigerFeuilleTemps`) avec les règles de la compagnie.
library;

/// Durée maximale d'un voyagement par jour, comme sur le serveur.
const int voyagementMaxMinutes = 12 * 60;

/// Nombre de jours d'une feuille de temps (lundi à vendredi).
const int joursParFeuille = 5;

const List<String> nomsJoursFeuille = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
];

int? _entier(Object? v) => v is num ? v.toInt() : null;

/// La saisie d'une journée.
class SaisieJour {
  /// « Jour non travaillé » : aucune heure, rien d'autre à saisir.
  final bool estAucun;
  final String? chantierId;
  final int? debutMinutes;
  final int? finMinutes;
  final bool pauseMatin;
  final bool diner;
  final int? voyagementMinutes;

  const SaisieJour({
    this.estAucun = false,
    this.chantierId,
    this.debutMinutes,
    this.finMinutes,
    this.pauseMatin = true,
    this.diner = true,
    this.voyagementMinutes,
  });

  /// Une journée sans rien de saisi.
  static const SaisieJour vide = SaisieJour();

  /// La saisie d'une journée de la feuille enregistrée (absente ou vide : journée vide).
  factory SaisieJour.depuisJour(Map<String, dynamic>? jour) {
    if (jour == null) return vide;
    if (jour['estAucun'] == true) return const SaisieJour(estAucun: true);
    final chantier = jour['chantierId'];
    return SaisieJour(
      chantierId: chantier is String && chantier.isNotEmpty ? chantier : null,
      debutMinutes: _entier(jour['heureDebutMinutes']),
      finMinutes: _entier(jour['heureFinMinutes']),
      pauseMatin: jour['pauseMatin'] is bool
          ? jour['pauseMatin'] as bool
          : true,
      diner: jour['diner'] is bool ? jour['diner'] as bool : true,
      voyagementMinutes: _entier(jour['tempsVoyagementMinutes']),
    );
  }

  bool get estVide =>
      !estAucun &&
      chantierId == null &&
      debutMinutes == null &&
      finMinutes == null &&
      (voyagementMinutes == null || voyagementMinutes == 0);

  SaisieJour copieAvec({
    bool? estAucun,
    Object? chantierId = _inchange,
    Object? debutMinutes = _inchange,
    Object? finMinutes = _inchange,
    bool? pauseMatin,
    bool? diner,
    Object? voyagementMinutes = _inchange,
  }) => SaisieJour(
    estAucun: estAucun ?? this.estAucun,
    chantierId: identical(chantierId, _inchange)
        ? this.chantierId
        : chantierId as String?,
    debutMinutes: identical(debutMinutes, _inchange)
        ? this.debutMinutes
        : debutMinutes as int?,
    finMinutes: identical(finMinutes, _inchange)
        ? this.finMinutes
        : finMinutes as int?,
    pauseMatin: pauseMatin ?? this.pauseMatin,
    diner: diner ?? this.diner,
    voyagementMinutes: identical(voyagementMinutes, _inchange)
        ? this.voyagementMinutes
        : voyagementMinutes as int?,
  );

  /// Ce qu'on envoie au serveur : seulement la saisie (jamais d'heures calculées).
  Map<String, dynamic> versDonnees() {
    if (estAucun) return {'estAucun': true};
    return {
      'estAucun': false,
      'chantierId': chantierId,
      'heureDebutMinutes': debutMinutes,
      'heureFinMinutes': finMinutes,
      'pauseMatin': pauseMatin,
      'diner': diner,
      'tempsVoyagementMinutes':
          (voyagementMinutes == null || voyagementMinutes == 0)
          ? null
          : voyagementMinutes,
    };
  }

  /// Message à montrer si la saisie ne peut pas être enregistrée, sinon null. Le serveur
  /// revérifie tout : ceci évite seulement un aller-retour.
  String? get erreur {
    if (estAucun || estVide) return null;
    if (chantierId == null) return 'Choisissez un chantier.';
    if (debutMinutes == null || finMinutes == null) {
      return 'Indiquez l\'heure de début et l\'heure de fin.';
    }
    if (finMinutes! <= debutMinutes!) {
      return 'L\'heure de fin doit suivre l\'heure de début.';
    }
    final v = voyagementMinutes;
    if (v != null && (v < 0 || v > voyagementMaxMinutes)) {
      return 'Le voyagement ne peut pas dépasser 12 h.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SaisieJour &&
      other.estAucun == estAucun &&
      other.chantierId == chantierId &&
      other.debutMinutes == debutMinutes &&
      other.finMinutes == finMinutes &&
      other.pauseMatin == pauseMatin &&
      other.diner == diner &&
      (other.voyagementMinutes ?? 0) == (voyagementMinutes ?? 0);

  @override
  int get hashCode => Object.hash(
    estAucun,
    chantierId,
    debutMinutes,
    finMinutes,
    pauseMatin,
    diner,
    voyagementMinutes ?? 0,
  );
}

const Object _inchange = Object();

/// Les cinq jours à envoyer au serveur : les jours enregistrés tels quels (leur saisie, pas
/// leurs heures calculées), sauf [index] qui prend [saisie]. Un jour absent ou vide reste
/// vide : le serveur n'efface jamais une journée déjà soumise sur une saisie vide.
List<Map<String, dynamic>> joursPourCorrection({
  required List<Map<String, dynamic>> existants,
  required int index,
  required SaisieJour saisie,
}) {
  assert(index >= 0 && index < joursParFeuille);
  return [
    for (var i = 0; i < joursParFeuille; i++)
      (i == index
              ? saisie
              : SaisieJour.depuisJour(
                  i < existants.length ? existants[i] : null,
                ))
          .versDonnees(),
  ];
}

/// « 7:00 » ← 420 ; « --:-- » si absent.
String heureAffichee(int? minutes) {
  if (minutes == null) return '--:--';
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// « 1 h 30 » ← 90 ; « Aucun » si absent ou nul.
String dureeAffichee(int? minutes) {
  if (minutes == null || minutes == 0) return 'Aucun';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')}';
}
