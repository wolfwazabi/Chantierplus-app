import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/chantier.dart';
import '../../models/correction_feuille.dart';
import '../../services/app_session.dart';
import '../../services/fiches_employes.dart';
import '../../services/fonctions.dart';

/// Choix d'une heure (minutes depuis minuit) ou d'une durée (minutes) ; null = annulé.
typedef ChoisirMinutes = Future<int?> Function(
  BuildContext context,
  String titre,
  int? initial,
);

typedef ChargerChantiers = Future<List<Chantier>> Function();

/// Points d'injection des tests pour la correction des heures par un admin.
class OutilsEditionJour {
  final AppelFonction? appelerFonction;
  final ChargerChantiers? chargerChantiers;
  final ChoisirMinutes? choisirHeure;
  final ChoisirMinutes? choisirDuree;

  const OutilsEditionJour({
    this.appelerFonction,
    this.chargerChantiers,
    this.choisirHeure,
    this.choisirDuree,
  });
}

/// Les vrais chantiers de la compagnie (jamais « Général »), par nom.
Future<List<Chantier>> chantiersDeLaCompagnie() async {
  final companyId = AppSession.current?.companyId;
  if (companyId == null) return [];
  final snap = await FirebaseFirestore.instance
      .collection('chantiers')
      .where('companyId', isEqualTo: companyId)
      .get();
  return sansGeneral(
    snap.docs.map((d) => Chantier.fromFirestore(d.id, d.data())),
  )..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
}

/// Roue d'heures (comme sur la feuille de l'employé) ; retourne les minutes depuis minuit.
Future<int?> choisirHeureMinutes(
  BuildContext context,
  String titre,
  int? initial,
) async {
  final depart = initial ?? 7 * 60;
  var choisi = DateTime(2024, 1, 1, depart ~/ 60, depart % 60);
  final r = await showModalBottomSheet<DateTime>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              titre,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SizedBox(
            height: 200,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: false,
              initialDateTime: choisi,
              onDateTimeChanged: (d) => choisi = d,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, choisi),
                child: const Text('Confirmer'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return r == null ? null : r.hour * 60 + r.minute;
}

/// Roue de durée (heures et minutes), au plus 12 h ; retourne des minutes.
Future<int?> choisirDureeMinutes(
  BuildContext context,
  String titre,
  int? initial,
) async {
  var choisi = Duration(minutes: initial ?? 0);
  final r = await showModalBottomSheet<Duration>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              titre,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          SizedBox(
            height: 200,
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hm,
              initialTimerDuration: choisi,
              onTimerDurationChanged: (d) => choisi = d,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  choisi.inMinutes > voyagementMaxMinutes
                      ? const Duration(minutes: voyagementMaxMinutes)
                      : choisi,
                ),
                child: const Text('Confirmer'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return r?.inMinutes;
}

/// Ouvre le formulaire de correction d'une journée d'un employé. Retourne la réponse du
/// serveur (totaux recalculés) si les heures ont été enregistrées, sinon null.
Future<Map<String, dynamic>?> modifierJourEmploye(
  BuildContext context, {
  required String employeeId,
  required String employeeNom,
  required String lundiDate,
  required List<Map<String, dynamic>> jours,
  required int index,
  OutilsEditionJour? outils,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => FormulaireJour(
      employeeId: employeeId,
      employeeNom: employeeNom,
      lundiDate: lundiDate,
      jours: jours,
      index: index,
      outils: outils ?? const OutilsEditionJour(),
    ),
  );
}

class FormulaireJour extends StatefulWidget {
  final String employeeId;
  final String employeeNom;
  final String lundiDate;
  final List<Map<String, dynamic>> jours;
  final int index;
  final OutilsEditionJour outils;

  const FormulaireJour({
    super.key,
    required this.employeeId,
    required this.employeeNom,
    required this.lundiDate,
    required this.jours,
    required this.index,
    required this.outils,
  });

  @override
  State<FormulaireJour> createState() => _FormulaireJourState();
}

class _FormulaireJourState extends State<FormulaireJour> {
  late final SaisieJour _origine;
  late SaisieJour _saisie;
  List<Chantier> _chantiers = [];
  bool _chargement = true;
  bool _erreurChantiers = false;
  bool _enCours = false;
  String? _erreur;

  Map<String, dynamic>? get _jourExistant =>
      widget.index < widget.jours.length ? widget.jours[widget.index] : null;

  @override
  void initState() {
    super.initState();
    _origine = SaisieJour.depuisJour(_jourExistant);
    _saisie = _origine;
    _chargerChantiers();
  }

  Future<void> _chargerChantiers() async {
    try {
      final liste =
          await (widget.outils.chargerChantiers ?? chantiersDeLaCompagnie)();
      if (!mounted) return;
      setState(() {
        _chantiers = liste;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreurChantiers = true;
      });
    }
  }

  String get _dateDuJour {
    final lundi = DateTime.tryParse(widget.lundiDate);
    if (lundi == null) return '';
    final d = lundi.add(Duration(days: widget.index));
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// Chantiers proposés : les actifs, plus celui déjà choisi s'il a été archivé depuis.
  List<DropdownMenuItem<String>> get _optionsChantier {
    final items = <DropdownMenuItem<String>>[
      for (final c in _chantiers.where((c) => !c.archive))
        DropdownMenuItem(value: c.id, child: Text(c.nom)),
    ];
    final choisi = _saisie.chantierId;
    if (choisi != null && !items.any((i) => i.value == choisi)) {
      final connu = _chantiers.where((c) => c.id == choisi);
      final nom = connu.isNotEmpty
          ? '${connu.first.nom} (archivé)'
          : ((_jourExistant?['chantierNom'] as String?) ?? 'Chantier retiré');
      items.add(DropdownMenuItem(value: choisi, child: Text(nom)));
    }
    return items;
  }

  bool get _voyagementOffert =>
      AppSession.reglesPaie.value.voyagementActif ||
      (_origine.voyagementMinutes ?? 0) > 0;

  Future<void> _choisirHeure(bool debut) async {
    final choisir = widget.outils.choisirHeure ?? choisirHeureMinutes;
    final m = await choisir(
      context,
      debut ? 'Heure de début' : 'Heure de fin',
      debut ? _saisie.debutMinutes : _saisie.finMinutes,
    );
    if (m == null || !mounted) return;
    setState(() {
      _erreur = null;
      _saisie = debut
          ? _saisie.copieAvec(debutMinutes: m)
          : _saisie.copieAvec(finMinutes: m);
    });
  }

  Future<void> _choisirVoyagement() async {
    final choisir = widget.outils.choisirDuree ?? choisirDureeMinutes;
    final m = await choisir(
      context,
      'Temps de voyagement',
      _saisie.voyagementMinutes,
    );
    if (m == null || !mounted) return;
    setState(() {
      _erreur = null;
      _saisie = _saisie.copieAvec(voyagementMinutes: m == 0 ? null : m);
    });
  }

  Future<void> _enregistrer() async {
    final erreur = _saisie.erreur;
    if (erreur != null) {
      setState(() => _erreur = erreur);
      return;
    }
    if (_saisie == _origine) {
      setState(() => _erreur = 'Aucun changement à enregistrer.');
      return;
    }
    if (_saisie.estVide) {
      // Le serveur n'efface jamais une journée déjà soumise sur une saisie vide.
      setState(
        () => _erreur =
            _origine.estAucun || _origine.estFerie || _origine.estBanque
            ? 'Indiquez un chantier et les heures, ou supprimez la journée.'
            : 'Rien à enregistrer. Pour retirer cette journée, touchez '
                  '« Supprimer la journée ».',
      );
      return;
    }
    await _envoyer(_saisie);
  }

  /// Non travaillé, férié ou heures en banque : pas de chantier ni d'heures de début et de fin.
  static bool _horsChantier(SaisieJour s) =>
      s.estAucun || s.estFerie || s.estBanque;

  /// La journée entrée par erreur (ex. jeudi au lieu de mercredi) : supprimée, ses heures
  /// retirées de la semaine ; la suppression reste dans l'historique des corrections.
  Future<void> _supprimer() async {
    final nomJour = widget.index < nomsJoursFeuille.length
        ? nomsJoursFeuille[widget.index].toLowerCase()
        : 'ce jour';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer la journée de $nomJour ?'),
        content: const Text(
          'Ses heures sont retirées de la semaine. La suppression reste dans '
          'l\'historique des corrections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('jour_supprimer_confirmer'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _envoyer(SaisieJour.effacee);
  }

  Future<void> _envoyer(SaisieJour saisie) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final appeler = widget.outils.appelerFonction ?? Fonctions.appeler;
      final reponse = await appeler('corrigerFeuilleTemps', {
        'employeeId': widget.employeeId,
        'lundiDate': widget.lundiDate,
        'jours': joursPourCorrection(
          existants: widget.jours,
          index: widget.index,
          saisie: saisie,
        ),
      });
      if (!mounted) return;
      Navigator.of(context).pop(reponse);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = Fonctions.message(e, 'Enregistrement impossible. Réessayez.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomJour = widget.index < nomsJoursFeuille.length
        ? nomsJoursFeuille[widget.index]
        : '';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Modifier les heures',
                key: const ValueKey('jour_titre'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.employeeNom} • $nomJour $_dateDuJour',
                key: const ValueKey('jour_sous_titre'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('jour_non_travaille'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Jour non travaillé'),
                subtitle: const Text(
                  'Aucune heure ne sera comptée pour ce jour.',
                ),
                value: _saisie.estAucun,
                onChanged: _enCours
                    ? null
                    : (v) => setState(() {
                        _erreur = null;
                        _saisie = v
                            ? const SaisieJour(estAucun: true)
                            : _horsChantier(_origine)
                            ? SaisieJour.vide
                            : _origine;
                      }),
              ),
              SwitchListTile(
                key: const ValueKey('jour_ferie'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Férié'),
                subtitle: Text(
                  '${formatHeuresFerie()} payées, comptées dans la semaine (aucun chantier).',
                ),
                value: _saisie.estFerie,
                onChanged: _enCours
                    ? null
                    : (v) => setState(() {
                        _erreur = null;
                        _saisie = v
                            ? const SaisieJour(estFerie: true)
                            : _horsChantier(_origine)
                            ? SaisieJour.vide
                            : _origine;
                      }),
              ),
              SwitchListTile(
                key: const ValueKey('jour_banque'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Heures en banque'),
                subtitle: const Text(
                  'Prises dans la banque d\'heures de l\'employé (aucun chantier).',
                ),
                value: _saisie.estBanque,
                onChanged: _enCours
                    ? null
                    : (v) => setState(() {
                        _erreur = null;
                        _saisie = v
                            ? SaisieJour(
                                estBanque: true,
                                heuresBanque: _origine.estBanque
                                    ? _origine.heuresBanque
                                    : null,
                              )
                            : _horsChantier(_origine)
                            ? SaisieJour.vide
                            : _origine;
                      }),
              ),
              if (_saisie.estBanque)
                TextFormField(
                  key: const ValueKey('jour_heures_banque'),
                  initialValue: _saisie.heuresBanque == null
                      ? ''
                      : heuresBanqueAffichees(_saisie.heuresBanque!),
                  enabled: !_enCours,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Heures prises dans la banque',
                    hintText: 'Ex. : 8 ou 3,5',
                    suffixText: 'h',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() {
                    _erreur = null;
                    _saisie = _saisie.copieAvec(
                      heuresBanque: lireHeuresBanque(v),
                    );
                  }),
                ),
              if (!_saisie.estAucun &&
                  !_saisie.estFerie &&
                  !_saisie.estBanque) ...[
                if (_chargement)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_erreurChantiers)
                  const Text(
                    'Impossible de charger les chantiers.',
                    key: ValueKey('jour_erreur_chantiers'),
                    style: TextStyle(color: Colors.red),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: const ValueKey('jour_chantier'),
                    isExpanded: true,
                    initialValue: _saisie.chantierId,
                    decoration: const InputDecoration(
                      labelText: 'Chantier',
                      border: OutlineInputBorder(),
                    ),
                    items: _optionsChantier,
                    onChanged: _enCours
                        ? null
                        : (v) => setState(() {
                            _erreur = null;
                            _saisie = _saisie.copieAvec(chantierId: v);
                          }),
                  ),
                ListTile(
                  key: const ValueKey('jour_debut'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Début'),
                  trailing: Text(heureAffichee(_saisie.debutMinutes)),
                  onTap: _enCours ? null : () => _choisirHeure(true),
                ),
                ListTile(
                  key: const ValueKey('jour_fin'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fin'),
                  trailing: Text(heureAffichee(_saisie.finMinutes)),
                  onTap: _enCours ? null : () => _choisirHeure(false),
                ),
                SwitchListTile(
                  key: const ValueKey('jour_pause'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pause du matin prise'),
                  value: _saisie.pauseMatin,
                  onChanged: _enCours
                      ? null
                      : (v) => setState(
                          () => _saisie = _saisie.copieAvec(pauseMatin: v),
                        ),
                ),
                SwitchListTile(
                  key: const ValueKey('jour_diner'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dîner pris'),
                  value: _saisie.diner,
                  onChanged: _enCours
                      ? null
                      : (v) => setState(
                          () => _saisie = _saisie.copieAvec(diner: v),
                        ),
                ),
                if (_voyagementOffert)
                  ListTile(
                    key: const ValueKey('jour_voyagement'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Temps de voyagement'),
                    trailing: Text(dureeAffichee(_saisie.voyagementMinutes)),
                    onTap: _enCours ? null : _choisirVoyagement,
                  ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Les heures payées sont calculées par le serveur avec les règles de '
                'la compagnie ; pour une semaine passée, avec les règles de cette '
                'semaine-là. Une journée entrée par erreur : « Supprimer la journée ».',
                key: ValueKey('jour_explication'),
                style: TextStyle(fontSize: 12),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 8),
                Text(
                  _erreur!,
                  key: const ValueKey('jour_erreur'),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              // Journée déjà enregistrée : on peut la supprimer (entrée par erreur).
              if (!_origine.estVide)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('jour_supprimer'),
                    onPressed: _enCours ? null : _supprimer,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Supprimer la journée',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('jour_annuler'),
                      onPressed: _enCours
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('jour_enregistrer'),
                      onPressed: _enCours ? null : _enregistrer,
                      child: _enCours
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
