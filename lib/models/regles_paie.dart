/// Règles de paie d'une compagnie (pauses et voyagement), modifiables par
/// les admins. Stockées dans companies/{id}.reglesPaie.
class ReglesPaie {
  final int pauseMatinMinutes;
  final bool pauseMatinPayee;
  final int dinerMinutes;
  final bool dinerPaye;
  final bool voyagementActif;
  final int voyagementSeuilMinutes;
  final int voyagementPourcentage;

  const ReglesPaie({
    this.pauseMatinMinutes = 15,
    this.pauseMatinPayee = false,
    this.dinerMinutes = 30,
    this.dinerPaye = true,
    this.voyagementActif = false,
    this.voyagementSeuilMinutes = 60,
    this.voyagementPourcentage = 50,
  });

  /// Règles par défaut (compagnie sans réglage, particuliers).
  static const defaut = ReglesPaie();

  // Bornes, identiques aux règles Firestore.
  static const maxMinutesPause = 120;
  static const maxSeuilMinutes = 600;
  static const maxPourcentage = 100;

  factory ReglesPaie.depuisMap(Map<String, dynamic>? m) {
    if (m == null) return defaut;
    int entier(String cle, int defaut, int max) {
      final v = m[cle];
      return v is int && v >= 0 && v <= max ? v : defaut;
    }

    bool booleen(String cle, bool defaut) =>
        m[cle] is bool ? m[cle] as bool : defaut;

    return ReglesPaie(
      pauseMatinMinutes: entier('pauseMatinMinutes', 15, maxMinutesPause),
      pauseMatinPayee: booleen('pauseMatinPayee', false),
      dinerMinutes: entier('dinerMinutes', 30, maxMinutesPause),
      dinerPaye: booleen('dinerPaye', true),
      voyagementActif: booleen('voyagementActif', false),
      voyagementSeuilMinutes: entier(
        'voyagementSeuilMinutes',
        60,
        maxSeuilMinutes,
      ),
      voyagementPourcentage: entier(
        'voyagementPourcentage',
        50,
        maxPourcentage,
      ),
    );
  }

  Map<String, dynamic> versMap() => {
    'pauseMatinMinutes': pauseMatinMinutes,
    'pauseMatinPayee': pauseMatinPayee,
    'dinerMinutes': dinerMinutes,
    'dinerPaye': dinerPaye,
    'voyagementActif': voyagementActif,
    'voyagementSeuilMinutes': voyagementSeuilMinutes,
    'voyagementPourcentage': voyagementPourcentage,
  };

  /// Minutes payées d'une journée : de l'heure de début à l'heure de fin,
  /// ajustées selon les pauses. Une pause non payée mais prise est retirée ;
  /// une pause payée mais non prise (travaillée) est ajoutée.
  /// Null si les heures sont absentes ou incohérentes.
  int? minutesTravaillees({
    required int? debutMinutes,
    required int? finMinutes,
    required bool pauseMatinPrise,
    required bool dinerPris,
  }) {
    if (debutMinutes == null || finMinutes == null) return null;
    var total = finMinutes - debutMinutes;
    if (total <= 0) return null;
    total += _ajustement(pauseMatinPrise, pauseMatinPayee, pauseMatinMinutes);
    total += _ajustement(dinerPris, dinerPaye, dinerMinutes);
    return total < 0 ? 0 : total;
  }

  static int _ajustement(bool prise, bool payee, int minutes) {
    if (prise && !payee) return -minutes;
    if (!prise && payee) return minutes;
    return 0;
  }

  /// Minutes de voyagement payées pour une journée : seul le temps AU-DELÀ du
  /// seuil est payé, au pourcentage choisi. Seuil de 60 min : 2 h de voyagement =
  /// 1 h payée à x % ; seuil de 30 min : 2 h = 1 h 30 payée à x %. Rien jusqu'au
  /// seuil ni si le voyagement n'est pas payé.
  double minutesVoyagementPayees(int? minutesVoyagement) {
    final v = minutesVoyagement ?? 0;
    final audela = v - voyagementSeuilMinutes;
    if (!voyagementActif || v <= 0 || audela <= 0) return 0;
    return audela * voyagementPourcentage / 100;
  }

  @override
  bool operator ==(Object other) =>
      other is ReglesPaie &&
      other.pauseMatinMinutes == pauseMatinMinutes &&
      other.pauseMatinPayee == pauseMatinPayee &&
      other.dinerMinutes == dinerMinutes &&
      other.dinerPaye == dinerPaye &&
      other.voyagementActif == voyagementActif &&
      other.voyagementSeuilMinutes == voyagementSeuilMinutes &&
      other.voyagementPourcentage == voyagementPourcentage;

  @override
  int get hashCode => Object.hash(
    pauseMatinMinutes,
    pauseMatinPayee,
    dinerMinutes,
    dinerPaye,
    voyagementActif,
    voyagementSeuilMinutes,
    voyagementPourcentage,
  );
}
