import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chantier.dart';
import '../models/employee.dart';
import '../models/regles_paie.dart';
import '../services/app_session.dart';
import '../services/fonctions.dart';
import '../widgets/recherche_chantier.dart';
import '../services/theme_compagnie.dart';

const Chantier chantierAucun = Chantier(
  id: '_aucun',
  companyId: '',
  nom: 'Aucun (jour non travaillé)',
  adresse: '',
);

/// Valeurs calculées à l'enregistrement d'une journée d'une semaine antérieure,
/// avec la saisie qui les a produites.
class _ValeursFigees {
  final int? debut;
  final int? fin;
  final bool pauseMatin;
  final bool diner;
  final int? voyagementMinutes;
  final double? heures;
  final double voyagementPaye;
  const _ValeursFigees({
    required this.debut,
    required this.fin,
    required this.pauseMatin,
    required this.diner,
    required this.voyagementMinutes,
    required this.heures,
    required this.voyagementPaye,
  });
}

class JourTravail {
  final String nomJour;
  Chantier? chantier;
  String projetTexte = '';
  TimeOfDay? heureDebut;
  TimeOfDay? heureFin;
  bool pauseMatin;
  bool diner;
  Duration? tempsVoyagement;
  bool verrouilleLocalement = false;
  bool modifieApresVerrouillage = false;

  /// Journée d'une semaine antérieure : les heures et le voyagement payés restent
  /// ceux calculés à l'époque, tant que la saisie n'a pas changé. Un changement
  /// des règles de paie ne réécrit jamais le passé.
  _ValeursFigees? _figees;

  JourTravail(this.nomJour, {this.pauseMatin = true, this.diner = true});

  bool get estAucun => chantier?.id == '_aucun';

  int? get _debutMinutes =>
      heureDebut == null ? null : heureDebut!.hour * 60 + heureDebut!.minute;
  int? get _finMinutes =>
      heureFin == null ? null : heureFin!.hour * 60 + heureFin!.minute;

  /// Garde les valeurs enregistrées (heures payées et voyagement payé) pour la
  /// saisie actuelle de la journée.
  void figer({required double? heures, required double voyagementPaye}) {
    _figees = _ValeursFigees(
      debut: _debutMinutes,
      fin: _finMinutes,
      pauseMatin: pauseMatin,
      diner: diner,
      voyagementMinutes: tempsVoyagement?.inMinutes,
      heures: heures,
      voyagementPaye: voyagementPaye,
    );
  }

  /// Les valeurs gardées valent encore : la saisie n'a pas été modifiée.
  _ValeursFigees? get _figeesValides {
    final f = _figees;
    if (f == null) return null;
    return f.debut == _debutMinutes &&
            f.fin == _finMinutes &&
            f.pauseMatin == pauseMatin &&
            f.diner == diner &&
            f.voyagementMinutes == tempsVoyagement?.inMinutes
        ? f
        : null;
  }

  /// Heures payées de la journée selon les règles de la compagnie (pauses).
  double? get heuresTravaillees {
    if (estAucun) return null;
    final figees = _figeesValides;
    if (figees != null) return figees.heures;
    final minutes = AppSession.reglesPaie.value.minutesTravaillees(
      debutMinutes: heureDebut == null
          ? null
          : heureDebut!.hour * 60 + heureDebut!.minute,
      finMinutes: heureFin == null
          ? null
          : heureFin!.hour * 60 + heureFin!.minute,
      pauseMatinPrise: pauseMatin,
      dinerPris: diner,
    );
    return minutes == null ? null : minutes / 60;
  }

  /// Voyagement payé de la journée (heures) : le temps au-delà du seuil de la
  /// compagnie, au pourcentage choisi.
  double get heuresVoyagementPayees {
    if (estAucun) return 0;
    final figees = _figeesValides;
    if (figees != null) return figees.voyagementPaye;
    return AppSession.reglesPaie.value.minutesVoyagementPayees(
          tempsVoyagement?.inMinutes,
        ) /
        60;
  }

  /// Quelque chose a été saisi (même si la journée est incomplète).
  bool get aDesDonnees =>
      chantier != null ||
      projetTexte.trim().isNotEmpty ||
      heureDebut != null ||
      heureFin != null ||
      tempsVoyagement != null;

  bool get estRempli {
    if (estAucun) return true;
    final aChantier = chantier != null || projetTexte.trim().isNotEmpty;
    return aChantier && heuresTravaillees != null;
  }
}

class FeuilleTempsScreen extends StatefulWidget {
  const FeuilleTempsScreen({super.key});

  @override
  State<FeuilleTempsScreen> createState() => _FeuilleTempsScreenState();
}

class _FeuilleTempsScreenState extends State<FeuilleTempsScreen> {
  DateTime _lundiDeLaSemaine = _trouverLundi(DateTime.now());
  late List<JourTravail> _jours;
  bool _chargement = false;
  bool _envoiSemaineEnCours = false;

  /// Journées à compléter, affichées en rouge après une soumission.
  Set<String> _joursEnErreur = {};

  /// Chantiers actifs : les seuls proposés à la saisie.
  List<Chantier> _chantiers = [];

  /// Tous les chantiers, archivés compris : les journées déjà enregistrées
  /// y retrouvent leur chantier.
  List<Chantier> _tousChantiers = [];

  static DateTime _trouverLundi(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: diff));
  }

  static String _isoDate(DateTime d) {
    final aa = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final jj = d.day.toString().padLeft(2, '0');
    return '$aa-$mm-$jj';
  }

  String _docId(String employeeId) =>
      '${employeeId}_${_isoDate(_lundiDeLaSemaine)}';

  @override
  void initState() {
    super.initState();
    _initialiserSemaineVide();
    AppSession.notifier.addListener(_onSessionChange);
    AppSession.reglesPaie.addListener(_onReglesPaie);
    _chargerTout();
  }

  @override
  void dispose() {
    AppSession.notifier.removeListener(_onSessionChange);
    AppSession.reglesPaie.removeListener(_onReglesPaie);
    super.dispose();
  }

  /// L'admin a changé les règles de paie : recalcul immédiat des totaux.
  void _onReglesPaie() {
    if (mounted) setState(() {});
  }

  void _onSessionChange() {
    _chargerTout();
  }

  /// Chantiers d'abord : les journées enregistrées y retrouvent leur chantier.
  Future<void> _chargerTout() async {
    await _chargerChantiers();
    if (mounted) await _chargerDonnees();
  }

  /// Un chargement a échoué : on ne laisse pas soumettre (une semaine affichée
  /// vide à tort ne doit jamais être renvoyée au serveur).
  bool _erreurChantiers = false;
  bool _erreurFeuille = false;
  bool get _erreurChargement => _erreurChantiers || _erreurFeuille;

  void _initialiserSemaineVide() {
    const noms = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi'];
    _jours = noms.map((n) => JourTravail(n)).toList();
    _joursEnErreur = {};
  }

  bool get _estIndividuel => AppSession.current?.estIndividuel == true;

  Future<void> _chargerChantiers() async {
    if (_estIndividuel) {
      setState(() {
        _chantiers = [];
        _tousChantiers = [];
      });
      return;
    }
    final companyId = AppSession.current?.companyId;
    if (companyId == null) {
      setState(() {
        _chantiers = [];
        _tousChantiers = [];
      });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chantiers')
          .where('companyId', isEqualTo: companyId)
          .get();
      final liste =
          snap.docs.map((d) => Chantier.fromFirestore(d.id, d.data())).toList()
            ..sort((a, b) => a.nom.compareTo(b.nom));
      if (mounted) {
        setState(() {
          _tousChantiers = liste;
          _chantiers = liste.where((c) => !c.archive).toList();
          _erreurChantiers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _erreurChantiers = true);
    }
  }

  Chantier? _trouverChantierParId(String? id) {
    if (id == null) return null;
    for (final c in _tousChantiers) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Chantiers proposés pour une journée : les actifs, plus le chantier déjà
  /// choisi s'il a été archivé depuis (le menu exige qu'il y figure).
  List<Chantier> _chantiersPour(JourTravail jour) {
    final choisi = jour.chantier;
    if (choisi == null ||
        choisi.id == chantierAucun.id ||
        _chantiers.any((c) => c.id == choisi.id)) {
      return _chantiers;
    }
    return [..._chantiers, choisi];
  }

  Future<void> _chargerDonnees() async {
    final employee = AppSession.current;
    if (employee == null) {
      if (mounted) setState(() {});
      return;
    }

    setState(() => _chargement = true);
    _initialiserSemaineVide();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('feuilles_temps')
          .doc(_docId(employee.id))
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final joursData = List<Map<String, dynamic>>.from(data['jours'] ?? []);
        for (int i = 0; i < _jours.length && i < joursData.length; i++) {
          final jd = joursData[i];
          _jours[i].chantier = jd['estAucun'] == true
              ? chantierAucun
              : _trouverChantierParId(jd['chantierId']);
          _jours[i].projetTexte = jd['chantierNom'] ?? '';
          if (jd['heureDebutMinutes'] != null) {
            final m = jd['heureDebutMinutes'] as int;
            _jours[i].heureDebut = TimeOfDay(hour: m ~/ 60, minute: m % 60);
          }
          if (jd['heureFinMinutes'] != null) {
            final m = jd['heureFinMinutes'] as int;
            _jours[i].heureFin = TimeOfDay(hour: m ~/ 60, minute: m % 60);
          }
          if (jd['tempsVoyagementMinutes'] != null) {
            _jours[i].tempsVoyagement = Duration(
              minutes: jd['tempsVoyagementMinutes'] as int,
            );
          }
          _jours[i].pauseMatin = jd['pauseMatin'] ?? true;
          _jours[i].diner = jd['diner'] ?? true;
          if (jd['verrouille'] == true) {
            _jours[i].verrouilleLocalement = true;
          }
          // Semaine antérieure : on garde les valeurs d'origine ; les règles de
          // paie actuelles ne s'y appliquent pas.
          if (_semaineAnterieure) {
            _jours[i].figer(
              heures: (jd['heuresTravaillees'] as num?)?.toDouble(),
              voyagementPaye:
                  (jd['voyagementPayeHeures'] as num?)?.toDouble() ?? 0,
            );
          }
        }
      }
      _erreurFeuille = false;
    } catch (_) {
      _erreurFeuille = true;
    }

    if (mounted) setState(() => _chargement = false);
  }

  void _changerSemaine(int delta) {
    setState(() {
      _lundiDeLaSemaine = _lundiDeLaSemaine.add(Duration(days: 7 * delta));
    });
    _chargerDonnees();
  }

  String _formatDateCourte(DateTime d) => '${d.day}/${d.month}';

  /// Semaine antérieure à la semaine courante : ses valeurs enregistrées ne
  /// suivent pas les changements de règles de paie.
  bool get _semaineAnterieure =>
      _lundiDeLaSemaine.isBefore(_trouverLundi(DateTime.now()));

  bool get _semaineVerrouillee {
    final mardiSuivant = _lundiDeLaSemaine.add(const Duration(days: 8));
    final dateVerrouillage = DateTime(
      mardiSuivant.year,
      mardiSuivant.month,
      mardiSuivant.day,
      18,
    );
    return !DateTime.now().isBefore(dateVerrouillage);
  }

  Future<void> _choisirHeure(
    JourTravail jour,
    bool debut,
    bool verrouillee,
  ) async {
    if (verrouillee) return;
    final initial =
        (debut ? jour.heureDebut : jour.heureFin) ??
        (debut
            ? const TimeOfDay(hour: 7, minute: 0)
            : const TimeOfDay(hour: 15, minute: 15));
    var dateTemp = DateTime(2024, 1, 1, initial.hour, initial.minute);

    final resultat = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  debut ? 'Heure de début' : 'Heure de fin',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  initialDateTime: dateTemp,
                  onDateTimeChanged: (d) => dateTemp = d,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, dateTemp),
                    child: const Text('Confirmer'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (resultat != null) {
      setState(() {
        final heure = TimeOfDay(hour: resultat.hour, minute: resultat.minute);
        if (debut) {
          jour.heureDebut = heure;
        } else {
          jour.heureFin = heure;
        }
      });
    }
  }

  Future<void> _choisirVoyagement(JourTravail jour, bool verrouillee) async {
    if (verrouillee) return;
    Duration temp = jour.tempsVoyagement ?? Duration.zero;

    final resultat = await showModalBottomSheet<Duration>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Temps de voyagement',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              SizedBox(
                height: 200,
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  initialTimerDuration: temp,
                  onTimerDurationChanged: (d) => temp = d,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      ctx,
                      temp > const Duration(hours: 12)
                          ? const Duration(hours: 12)
                          : temp,
                    ),
                    child: const Text('Confirmer'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (resultat != null) {
      setState(() => jour.tempsVoyagement = resultat);
    }
  }

  ReglesPaie get _regles => AppSession.reglesPaie.value;

  /// Voyagement payé par l'employeur (jamais pour un particulier). Une semaine
  /// antérieure garde son voyagement payé même si l'employeur ne le paie plus.
  bool get _voyagementPaye =>
      !_estIndividuel &&
      (_regles.voyagementActif ||
          _jours.any((j) => j.heuresVoyagementPayees > 0));

  /// Le particulier note son voyagement pour lui-même ; en compagnie, le
  /// champ disparaît si l'employeur ne paie pas le voyagement.
  bool get _afficherVoyagement => _estIndividuel || _regles.voyagementActif;

  double get _totalHeuresTravaillees =>
      _jours.fold(0.0, (total, j) => total + (j.heuresTravaillees ?? 0));

  double get _totalVoyagementPaye => _voyagementPaye
      ? _jours.fold(0.0, (total, j) => total + j.heuresVoyagementPayees)
      : 0;

  /// Total payé de la semaine : heures travaillées + voyagement payé.
  double get _totalSemaine => _totalHeuresTravaillees + _totalVoyagementPaye;

  Duration get _totalVoyagementSemaine => _jours.fold(
    Duration.zero,
    (total, j) => total + (j.tempsVoyagement ?? Duration.zero),
  );

  Widget _ligneTotal(String libelle, String valeur) {
    return Row(
      children: [
        Expanded(
          child: Text(
            libelle,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
        Text(
          valeur,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _formatDureeAffichage(Duration? d) {
    if (d == null || d.inMinutes == 0) return '--';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  int get _nombreJoursActifs => _jours
      .where(
        (j) =>
            (j.estRempli && !j.verrouilleLocalement) ||
            j.modifieApresVerrouillage,
      )
      .length;

  /// Total de la semaine calculé par le serveur lors du dernier envoi.
  double? _totalServeur;

  /// Compagnie : le serveur recalcule les heures (règles de paie de la
  /// compagnie, chantiers, verrouillage) ; l'app n'envoie que la saisie.
  Future<bool> _envoyerAuServeur() async {
    final jours = _jours.map((j) {
      // Une journée incomplète n'est pas soumise : elle est envoyée vide.
      if (!j.estRempli) return <String, dynamic>{'estAucun': false};
      return <String, dynamic>{
        'estAucun': j.estAucun,
        'chantierId': j.estAucun ? null : j.chantier?.id,
        'heureDebutMinutes': j.heureDebut == null
            ? null
            : j.heureDebut!.hour * 60 + j.heureDebut!.minute,
        'heureFinMinutes': j.heureFin == null
            ? null
            : j.heureFin!.hour * 60 + j.heureFin!.minute,
        'pauseMatin': j.pauseMatin,
        'diner': j.diner,
        'tempsVoyagementMinutes': _afficherVoyagement
            ? j.tempsVoyagement?.inMinutes
            : null,
      };
    }).toList();

    try {
      final reponse = await Fonctions.appeler('enregistrerFeuilleTemps', {
        'lundiDate': _isoDate(_lundiDeLaSemaine),
        'jours': jours,
      });
      _totalServeur = (reponse['totalHeures'] as num?)?.toDouble();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Fonctions.message(
                e,
                'Erreur lors de la sauvegarde. Vérifiez votre réseau et réessayez.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _sauvegarderDocument() async {
    final employee = AppSession.current;
    if (employee == null) return false;
    if (!_estIndividuel) return _envoyerAuServeur();

    final joursData = _jours.map((j) {
      return {
        'nomJour': j.nomJour,
        'chantierId': (j.chantier != null && !j.estAucun)
            ? j.chantier!.id
            : null,
        'chantierNom': _estIndividuel
            ? j.projetTexte
            : (j.estAucun ? 'Jour non travaillé' : j.chantier?.nom),
        'estAucun': j.estAucun,
        'heureDebutMinutes': j.heureDebut != null
            ? j.heureDebut!.hour * 60 + j.heureDebut!.minute
            : null,
        'heureFinMinutes': j.heureFin != null
            ? j.heureFin!.hour * 60 + j.heureFin!.minute
            : null,
        'pauseMatin': j.pauseMatin,
        'diner': j.diner,
        'heuresTravaillees': j.heuresTravaillees,
        'tempsVoyagementMinutes': _afficherVoyagement
            ? j.tempsVoyagement?.inMinutes
            : null,
        'voyagementPayeHeures': _voyagementPaye ? j.heuresVoyagementPayees : 0,
        'verrouille': j.verrouilleLocalement || j.estRempli,
        if (j.modifieApresVerrouillage)
          'modifieApresVerrouillageLe': DateTime.now().toIso8601String(),
      };
    }).toList();

    try {
      await FirebaseFirestore.instance
          .collection('feuilles_temps')
          .doc(_docId(employee.id))
          .set({
            'estIndividuel': true,
            'employeeId': employee.id,
            'employeeNom': employee.nom,
            'lundiDate': _isoDate(_lundiDeLaSemaine),
            'jours': joursData,
            'totalHeures': _totalSemaine,
            'totalHeuresTravaillees': _totalHeuresTravaillees,
            'totalVoyagementPaye': _totalVoyagementPaye,
            'dateModification': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FirebaseException && e.code == 'permission-denied'
                  ? 'Enregistrement refusé : session expirée. Reconnectez-vous.'
                  : 'Erreur lors de la sauvegarde. Vérifiez votre réseau et réessayez.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _soumettreSemaine() async {
    if (_erreurChargement) return;
    final joursSaisis = _jours.where((j) => j.estRempli);
    if (joursSaisis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir au moins une journée.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final aCompleter = _verifierJours();
    setState(() => _envoiSemaineEnCours = true);
    final succes = await _sauvegarderDocument();
    if (succes) {
      setState(() {
        for (final j in _jours) {
          if (j.estRempli) {
            j.verrouilleLocalement = true;
            j.modifieApresVerrouillage = false;
          }
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_nombreJoursActifs >= 2 ? 'Journées soumises' : 'Journée soumise'} : ${(_totalServeur ?? _totalSemaine).toStringAsFixed(2)}h au total'
              '${aCompleter.isEmpty ? '' : '\nÀ compléter : ${aCompleter.join(', ')}'}',
            ),
            duration: Duration(seconds: aCompleter.isEmpty ? 4 : 8),
            backgroundColor: aCompleter.isEmpty ? Colors.green : Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _envoiSemaineEnCours = false);
  }

  /// Journées à mettre en rouge à la soumission :
  ///  - incomplète (chantier ou heures manquants) : toujours ;
  ///  - jamais saisie : seulement quand on soumet le vendredi, qui clôt la
  ///    semaine de travail (lundi → vendredi).
  /// Retourne le texte de chaque journée à compléter.
  List<String> _verifierJours() {
    final vendrediSoumis =
        _jours.length > 4 &&
        _jours[4].estRempli &&
        (!_jours[4].verrouilleLocalement || _jours[4].modifieApresVerrouillage);
    final erreurs = <String, String>{};
    for (var i = 0; i < _jours.length; i++) {
      final j = _jours[i];
      if (j.estRempli) continue;
      if (j.aDesDonnees) {
        final sansChantier = j.chantier == null && j.projetTexte.trim().isEmpty;
        erreurs[j.nomJour] = sansChantier
            ? '${j.nomJour} (chantier)'
            : '${j.nomJour} (heures)';
      } else if (vendrediSoumis && i < 4) {
        erreurs[j.nomJour] = '${j.nomJour} (non saisie)';
      }
    }
    setState(() => _joursEnErreur = erreurs.keys.toSet());
    return erreurs.values.toList();
  }

  void _debloquerJour(JourTravail jour) {
    setState(() {
      jour.verrouilleLocalement = false;
      jour.modifieApresVerrouillage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Employee?>(
      valueListenable: AppSession.notifier,
      builder: (context, employee, _) {
        final pasConnecte = employee == null;
        final individuel = employee?.estIndividuel == true;
        final verrouillee = (!individuel && _semaineVerrouillee) || pasConnecte;
        final dimanche = _lundiDeLaSemaine.add(const Duration(days: 4));

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Feuille de temps',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => _changerSemaine(-1),
                          ),
                          Text(
                            'Semaine du ${_formatDateCourte(_lundiDeLaSemaine)} au ${_formatDateCourte(dimanche)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _changerSemaine(1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_erreurChargement && !pasConnecte) ...[
                    const SizedBox(height: 12),
                    Card(
                      key: const ValueKey('erreur_chargement'),
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off, color: Colors.red.shade800),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Impossible de charger vos données. Vérifiez '
                                'votre réseau : la soumission est bloquée pour '
                                'ne rien écraser.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            TextButton(
                              onPressed: _chargerTout,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (pasConnecte) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: ThemeCompagnie.teintePale(
                        Theme.of(context).colorScheme.primary,
                        0.12,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.login,
                              color: ThemeCompagnie.accentDe(context),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Connectez-vous (onglet "Se connecter") pour saisir vos heures.',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (!individuel && _chantiers.isEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.grey.shade200,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Aucun chantier n\'a été créé pour votre compagnie. Un administrateur peut en ajouter dans Admin → Chantiers.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ] else if (!individuel && _semaineVerrouillee) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.grey.shade200,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: Colors.grey),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Cette semaine est verrouillée (limite : mardi 18h00). Contactez votre superviseur pour toute correction.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ..._jours.map(
                    (jour) => _carteJour(jour, verrouillee, individuel),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: ThemeCompagnie.teintePale(
                      Theme.of(context).colorScheme.primary,
                      0.12,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total de la semaine',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_totalSemaine.toStringAsFixed(2)} h',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (_voyagementPaye) ...[
                            const Divider(height: 20),
                            _ligneTotal(
                              'Heures travaillées',
                              '${_totalHeuresTravaillees.toStringAsFixed(2)} h',
                            ),
                            const SizedBox(height: 4),
                            _ligneTotal(
                              'Voyagement payé',
                              '${_totalVoyagementPaye.toStringAsFixed(2)} h',
                            ),
                          ],
                          // Le voyagement saisi n'est montré qu'au particulier
                          // (en compagnie, seul le voyagement payé compte).
                          if (_afficherVoyagement && !_voyagementPaye) ...[
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Voyagement saisi',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  _formatDureeAffichage(
                                    _totalVoyagementSemaine,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          (verrouillee ||
                              _envoiSemaineEnCours ||
                              _erreurChargement)
                          ? null
                          : _soumettreSemaine,
                      icon: _envoiSemaineEnCours
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        pasConnecte
                            ? 'Connectez-vous pour soumettre'
                            : (!individuel && _semaineVerrouillee
                                  ? 'Semaine verrouillée'
                                  : '${individuel ? 'Enregistrer' : 'Soumettre'} ${_nombreJoursActifs >= 2 ? 'les journées' : 'la journée'}'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_chargement)
              Container(
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }

  Widget _carteJour(JourTravail jour, bool verrouillee, bool individuel) {
    if (jour.verrouilleLocalement) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(
            jour.nomJour,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            jour.estAucun
                ? 'Jour non travaillé'
                : '${individuel ? jour.projetTexte : (jour.chantier?.nom ?? '')} • ${jour.heuresTravaillees?.toStringAsFixed(2) ?? '0'} h',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: verrouillee ? null : () => _debloquerJour(jour),
          ),
        ),
      );
    }

    // Rouge tant que la journée signalée n'est pas complétée.
    final enErreur = _joursEnErreur.contains(jour.nomJour) && !jour.estRempli;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: enErreur
          ? Colors.red.shade50
          : (verrouillee ? Colors.grey.shade100 : null),
      shape: enErreur
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.red, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  jour.nomJour,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: enErreur ? Colors.red.shade800 : null,
                  ),
                ),
                if (jour.estAucun)
                  const Text(
                    '--',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  )
                else if (jour.heuresTravaillees != null)
                  Text(
                    '${jour.heuresTravaillees!.toStringAsFixed(2)} h',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ThemeCompagnie.accentDe(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (individuel)
              TextFormField(
                initialValue: jour.projetTexte,
                enabled: !verrouillee,
                decoration: const InputDecoration(
                  labelText: 'Projet / Client',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work_outline),
                  isDense: true,
                ),
                onChanged: (val) => jour.projetTexte = val,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Chantier>(
                      // La clé suit la valeur : la liste affiche aussi un
                      // chantier choisi par la recherche « … ».
                      key: ValueKey(
                        'chantier_${jour.nomJour}_${jour.chantier?.id}',
                      ),
                      initialValue: jour.chantier,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Chantier',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.construction),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<Chantier>(
                          value: chantierAucun,
                          child: Text('Aucun (jour non travaillé)'),
                        ),
                        ..._chantiersPour(jour).map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c.nom}\n${c.adresse}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }),
                      ],
                      onChanged: verrouillee
                          ? null
                          : (valeur) => setState(() => jour.chantier = valeur),
                    ),
                  ),
                  const SizedBox(width: 6),
                  BoutonRechercheChantier(
                    chantiers: _chantiersPour(jour),
                    onChoisi: verrouillee
                        ? null
                        : (c) => setState(() => jour.chantier = c),
                  ),
                ],
              ),
            if (!jour.estAucun) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _boutonHeurePetit(
                      label: 'Début',
                      valeur: jour.heureDebut?.format(context) ?? '--:--',
                      onTap: () => _choisirHeure(jour, true, verrouillee),
                      desactive: verrouillee,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _boutonHeurePetit(
                      label: 'Fin',
                      valeur: jour.heureFin?.format(context) ?? '--:--',
                      onTap: () => _choisirHeure(jour, false, verrouillee),
                      desactive: verrouillee,
                    ),
                  ),
                ],
              ),
              if (_afficherVoyagement) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: verrouillee
                      ? null
                      : () => _choisirVoyagement(jour, verrouillee),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Temps de voyagement',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: const Icon(Icons.directions_car, size: 20),
                      filled: verrouillee,
                      fillColor: verrouillee ? Colors.grey.shade200 : null,
                    ),
                    child: Text(
                      _formatDureeAffichage(jour.tempsVoyagement),
                      style: TextStyle(color: verrouillee ? Colors.grey : null),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: jour.pauseMatin,
                      onChanged: verrouillee
                          ? null
                          : (val) =>
                                setState(() => jour.pauseMatin = val ?? false),
                      title: const Text(
                        'Pause matin',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${_regles.pauseMatinMinutes} min'
                        '${_regles.pauseMatinPayee ? ', payée' : ', non payée'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      value: jour.diner,
                      onChanged: verrouillee
                          ? null
                          : (val) => setState(() => jour.diner = val ?? false),
                      title: const Text(
                        'Dîner',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${_regles.dinerMinutes} min'
                        '${_regles.dinerPaye ? ', payé' : ', non payé'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boutonHeurePetit({
    required String label,
    required String valeur,
    required VoidCallback onTap,
    bool desactive = false,
  }) {
    return InkWell(
      onTap: desactive ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          filled: desactive,
          fillColor: desactive ? Colors.grey.shade200 : null,
        ),
        child: Text(
          valeur,
          style: TextStyle(color: desactive ? Colors.grey : null),
        ),
      ),
    );
  }
}
