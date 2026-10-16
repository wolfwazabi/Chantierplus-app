/// Correction des heures d'un employé par un admin (tableau admin des feuilles de temps).
///
/// L'admin ne saisit que ce que l'employé saisit lui-même (chantier, début, fin, pauses,
/// voyagement) : les heures payées sont toujours recalculées par le serveur
/// (`corrigerFeuilleTemps`) avec les règles de la compagnie.
library;

/// Durée maximale d'un voyagement par jour, comme sur le serveur.
const int voyagementMaxMinutes = 12 * 60;

/// Journée fériée : 8 h payées d'office, hors chantier (calculées par le serveur).
const double heuresFerie = 8;

/// Heures en banque : au plus 24 h par journée (comme le serveur).
const double maxHeuresBanque = 24;

/// « 7,5 » ou « 7.5 » → 7.5 ; null si ce n'est pas un nombre d'heures valable (plus de 0, au
/// plus [maxHeuresBanque]).
double? lireHeuresBanque(String texte) {
  final v = double.tryParse(texte.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v <= 0 || v > maxHeuresBanque) return null;
  return (v * 100).round() / 100;
}

/// « 7,5 » ← 7.5 ; « 8 » ← 8.
String heuresBanqueAffichees(double h) =>
    (h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toString()).replaceAll(
      '.',
      ',',
    );

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

  /// « Férié » : 8 h payées, aucun chantier, rien d'autre à saisir.
  final bool estFerie;

  /// « Heures en banque » : les heures prises dans la banque de l'employé ([heuresBanque]),
  /// payées, aucun chantier.
  final bool estBanque;
  final double? heuresBanque;

  /// La journée entrée par erreur est supprimée (gardée dans l'historique des corrections).
  final bool effacer;
  final String? chantierId;
  final int? debutMinutes;
  final int? finMinutes;
  final bool pauseMatin;
  final bool diner;
  final int? voyagementMinutes;

  const SaisieJour({
    this.estAucun = false,
    this.estFerie = false,
    this.estBanque = false,
    this.heuresBanque,
    this.effacer = false,
    this.chantierId,
    this.debutMinutes,
    this.finMinutes,
    this.pauseMatin = true,
    this.diner = true,
    this.voyagementMinutes,
  });

  /// Une journée sans rien de saisi.
  static const SaisieJour vide = SaisieJour();

  /// Une journée à supprimer.
  static const SaisieJour effacee = SaisieJour(effacer: true);

  /// La saisie d'une journée de la feuille enregistrée (absente ou vide : journée vide).
  factory SaisieJour.depuisJour(Map<String, dynamic>? jour) {
    if (jour == null) return vide;
    if (jour['estAucun'] == true) return const SaisieJour(estAucun: true);
    if (jour['estFerie'] == true) return const SaisieJour(estFerie: true);
    if (jour['estBanque'] == true) {
      return SaisieJour(
        estBanque: true,
        heuresBanque: (jour['heuresBanque'] as num?)?.toDouble(),
      );
    }
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
      !estFerie &&
      !estBanque &&
      !effacer &&
      chantierId == null &&
      debutMinutes == null &&
      finMinutes == null &&
      (voyagementMinutes == null || voyagementMinutes == 0);

  SaisieJour copieAvec({
    bool? estAucun,
    bool? estFerie,
    bool? estBanque,
    Object? heuresBanque = _inchange,
    Object? chantierId = _inchange,
    Object? debutMinutes = _inchange,
    Object? finMinutes = _inchange,
    bool? pauseMatin,
    bool? diner,
    Object? voyagementMinutes = _inchange,
  }) => SaisieJour(
    estAucun: estAucun ?? this.estAucun,
    estFerie: estFerie ?? this.estFerie,
    estBanque: estBanque ?? this.estBanque,
    heuresBanque: identical(heuresBanque, _inchange)
        ? this.heuresBanque
        : heuresBanque as double?,
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
    if (effacer) return {'effacer': true};
    if (estAucun) return {'estAucun': true};
    if (estFerie) return {'estFerie': true};
    if (estBanque) return {'estBanque': true, 'heuresBanque': heuresBanque};
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
    if (estBanque) {
      final h = heuresBanque;
      return h == null || h <= 0 || h > maxHeuresBanque
          ? 'Indiquez les heures prises dans la banque (plus de 0, au plus 24).'
          : null;
    }
    if (estAucun || estFerie || effacer || estVide) return null;
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
      other.estFerie == estFerie &&
      other.estBanque == estBanque &&
      other.heuresBanque == heuresBanque &&
      other.effacer == effacer &&
      other.chantierId == chantierId &&
      other.debutMinutes == debutMinutes &&
      other.finMinutes == finMinutes &&
      other.pauseMatin == pauseMatin &&
      other.diner == diner &&
      (other.voyagementMinutes ?? 0) == (voyagementMinutes ?? 0);

  @override
  int get hashCode => Object.hash(
    estAucun,
    estFerie,
    estBanque,
    heuresBanque,
    effacer,
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

/// « 8 h » : les heures payées d'un férié.
String formatHeuresFerie() => '${heuresFerie.toStringAsFixed(0)} h';

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
