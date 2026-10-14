import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../charpente/commande.dart';
import '../../charpente/projet.dart';
import '../../charpente/reglages_habituels.dart';
import '../../services/preferences.dart';
import '../../services/selecteur_plans.dart';
import '../../services/theme_compagnie.dart';
import 'assistant_charpente.dart';
import 'barre_reglages.dart';
import 'champs.dart';
import 'lire_plan_screen.dart';
import 'onglet_commande.dart';
import 'onglet_escalier.dart';
import 'onglet_murs.dart';
import 'onglet_plancher.dart';
import 'vue_3d.dart';

/// Calcul de charpente d'un chantier : plancher, murs, vue 3D et commande.
///
/// Le calcul en cours est gardé sur l'appareil (par chantier) : on le retrouve
/// en revenant sur l'onglet, même après la fermeture de l'application.
class CharpenteScreen extends StatefulWidget {
  final String companyId;
  final String chantierId;
  final bool connecte;

  /// Remplace la liste des commandes enregistrées (tests, sans Firestore).
  @visibleForTesting
  final Widget? listeEnregistrees;

  /// Remplace l'appel au serveur de l'assistant (tests).
  @visibleForTesting
  final AppelAssistant appelAssistant;

  /// Remplace l'appel au serveur de la lecture de plans (tests).
  @visibleForTesting
  final AppelLecturePlan appelLecturePlan;

  /// Remplace le choix des fichiers du plan (tests).
  @visibleForTesting
  final SelecteurPlans selecteurPlans;

  const CharpenteScreen({
    super.key,
    required this.companyId,
    required this.chantierId,
    required this.connecte,
    this.listeEnregistrees,
    this.appelAssistant = appelAssistantParDefaut,
    this.appelLecturePlan = appelLecturePlanParDefaut,
    this.selecteurPlans = const SelecteurPlansReel(),
  });

  @override
  State<CharpenteScreen> createState() => _CharpenteScreenState();
}

class _CharpenteScreenState extends State<CharpenteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _onglets = TabController(length: 5, vsync: this);
  ProjetCharpente _projet = const ProjetCharpente();
  late ResultatsProjet _res;
  List<LigneCommande> _manuelles = [];
  Timer? _sauvegarde;
  Timer? _recalcul;
  bool _enAttente = false;
  Duration _dernierCalcul = Duration.zero;
  final _nom = TextEditingController();

  /// Réglages habituels, gardés sur l'appareil (tous chantiers).
  ReglagesHabituels _habitudes = ReglagesHabituels.vides;
  static const _cleHabitudes = 'charpente.reglagesHabituels';

  String get _cle => 'charpente.brouillon.${widget.chantierId}';

  /// Un nouveau calcul part des réglages habituels.
  ProjetCharpente get _projetNeuf =>
      _habitudes.appliquer(const ProjetCharpente());

  static bool _memes(ProjetCharpente a, ProjetCharpente b) =>
      jsonEncode(a.toJson()) == jsonEncode(b.toJson());

  @override
  void initState() {
    super.initState();
    _res = calculerProjet(_projet, metrique: Preferences.estMetrique);
    Preferences.unites.addListener(_unitesChangees);
    _restaurer();
  }

  @override
  void didUpdateWidget(CharpenteScreen old) {
    super.didUpdateWidget(old);
    if (old.chantierId != widget.chantierId) {
      _projet = _projetNeuf;
      _manuelles = [];
      _nom.clear();
      _recalculer();
      _restaurer();
    }
  }

  @override
  void dispose() {
    Preferences.unites.removeListener(_unitesChangees);
    _sauvegarde?.cancel();
    _recalcul?.cancel();
    _onglets.dispose();
    _nom.dispose();
    super.dispose();
  }

  void _unitesChangees() {
    if (mounted) {
      setState(_recalculer);
    }
  }

  void _recalculer() {
    final chrono = Stopwatch()..start();
    _res = calculerProjet(_projet, metrique: Preferences.estMetrique);
    _dernierCalcul = chrono.elapsed;
    _enAttente = false;
  }

  static ReglagesHabituels _lireHabitudes(SharedPreferences prefs) {
    try {
      final texte = prefs.getString(_cleHabitudes);
      return texte == null
          ? ReglagesHabituels.vides
          : ReglagesHabituels.depuis(jsonDecode(texte));
    } catch (_) {
      return ReglagesHabituels.vides;
    }
  }

  Future<void> _restaurer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final habitudes = _lireHabitudes(prefs);
      if (!mounted) {
        return;
      }
      final texte = prefs.getString(_cle);
      if (texte == null) {
        // Pas de calcul en cours sur ce chantier : on part des réglages habituels.
        setState(() {
          final intact = _memes(_projet, _projetNeuf);
          _habitudes = habitudes;
          if (intact) {
            _projet = _projetNeuf;
            _recalculer();
          }
        });
        return;
      }
      setState(() => _habitudes = habitudes);
      final j = jsonDecode(texte);
      final projet = ProjetCharpente.fromJson(j['projet']);
      final lignes = <LigneCommande>[
        for (final l in (j['manuelles'] as List? ?? const []))
          LigneCommande.fromJson(l),
      ];
      if (!mounted) {
        return;
      }
      setState(() {
        _projet = projet;
        _manuelles = lignes;
        _nom.text = projet.nom;
        _recalculer();
      });
    } catch (_) {
      // Brouillon illisible ou stockage indisponible : on repart d'un projet neuf.
    }
  }

  void _planifierSauvegarde() {
    _sauvegarde?.cancel();
    _sauvegarde = Timer(const Duration(milliseconds: 800), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _cle,
          jsonEncode({
            'projet': _projet.toJson(),
            'manuelles': [for (final l in _manuelles) l.toJson()],
          }),
        );
      } catch (_) {}
    });
  }

  /// Applique un changement : les champs suivent tout de suite ; le calcul est
  /// immédiat, sauf pour une très grande forme (calcul lent) : il attend alors
  /// une courte pause de la saisie.
  void _changer(ProjetCharpente p) {
    _recalcul?.cancel();
    if (_dernierCalcul.inMilliseconds < 120) {
      setState(() {
        _projet = p;
        _recalculer();
      });
    } else {
      setState(() {
        _projet = p;
        _enAttente = true;
      });
      _recalcul = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(_recalculer);
        }
      });
    }
    _planifierSauvegarde();
  }

  void _changerManuelles(List<LigneCommande> l) {
    setState(() => _manuelles = l);
    _planifierSauvegarde();
  }

  Future<void> _assistant() async {
    final p = await showModalBottomSheet<ProjetCharpente>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => AssistantCharpente(
        projetActuel: _projet,
        appeler: widget.appelAssistant,
      ),
    );
    if (p != null && mounted) {
      _nom.text = p.nom;
      // L'assistant ne connaît pas le composite ni l'escalier : on les garde tels quels.
      _changer(
        p.copieAvec(
          plancher: p.plancher.copieAvec(
            composite: () => _projet.plancher.composite,
          ),
          escalierActif: _projet.escalierActif,
          escalier: _projet.escalier,
        ),
      );
      _onglets.animateTo(0);
    }
  }

  /// Le calcul en cours n'est plus un calcul neuf : le remplacer fait perdre du travail.
  bool get _aDuTravail => !_memes(_projet, _projetNeuf);

  /// Garde les réglages de l'onglet (plancher ou murs) pour les prochains calculs.
  Future<void> _garderHabitudes({required bool plancher}) async {
    final r = plancher
        ? _habitudes.avecPlancherDe(_projet)
        : _habitudes.avecMursDe(_projet);
    final messager = ScaffoldMessenger.of(context);
    var garde = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      garde = await prefs.setString(_cleHabitudes, jsonEncode(r.toJson()));
    } catch (_) {
      garde = false;
    }
    if (!mounted) {
      return;
    }
    if (garde) {
      setState(() => _habitudes = r);
    }
    messager
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            !garde
                ? 'Impossible de garder les réglages sur cet appareil.'
                : plancher
                ? 'Réglages du plancher gardés : vos prochains calculs partiront de ceux-ci.'
                : 'Réglages des murs gardés : vos prochains calculs partiront de ceux-ci.',
          ),
        ),
      );
  }

  /// Remet les réglages habituels de l'onglet ; les mesures du calcul restent.
  void _remettreHabitudes({required bool plancher}) {
    final avant = _projet;
    _changer(
      _habitudes.appliquer(_projet, auPlancher: plancher, auxMurs: !plancher),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Réglages habituels remis.'),
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () {
              if (mounted) _changer(avant);
            },
          ),
        ),
      );
  }

  /// Calcul à partir d'un plan : l'écran de lecture rend le projet confirmé, qui remplace le
  /// calcul en cours ; on va directement à la commande.
  Future<void> _lirePlan() async {
    final p = await Navigator.of(context).push<ProjetCharpente>(
      MaterialPageRoute(
        builder: (_) => LirePlanScreen(
          appeler: widget.appelLecturePlan,
          selecteur: widget.selecteurPlans,
          calculExistant: _aDuTravail,
          reglages: _habitudes.pourLecturePlan(),
        ),
      ),
    );
    if (p != null && mounted) {
      // Le nom du plan, sinon celui qu'on avait déjà.
      final nom = p.nom.isEmpty ? _nom.text : p.nom;
      _nom.text = nom;
      _changer(p.copieAvec(nom: nom));
      _onglets.animateTo(4);
    }
  }

  Future<void> _nouveau() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau calcul ?'),
        content: Text(
          'Le calcul en cours (plancher, murs et lignes ajoutées) est effacé. '
          'Les commandes déjà enregistrées ne changent pas.'
          '${_habitudes.estVide ? '' : ' Le nouveau calcul part de vos réglages habituels.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _nom.clear();
      setState(() {
        _manuelles = [];
        _projet = _projetNeuf;
        _recalculer();
      });
      _planifierSauvegarde();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ThemeCompagnie.accentDe(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('charpente_nom'),
                  controller: _nom,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Nom du calcul',
                    hintText: 'Ex. : Garage 24 × 20',
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                  onChanged: (v) => _changer(_projet.copieAvec(nom: v)),
                ),
              ),
              IconButton(
                key: const ValueKey('charpente_assistant'),
                tooltip: 'Assistant IA',
                icon: const Icon(Icons.auto_awesome),
                onPressed: widget.connecte ? _assistant : null,
              ),
              IconButton(
                key: const ValueKey('charpente_lire_plan'),
                tooltip: 'Calculer à partir d\'un plan',
                icon: const Icon(Icons.upload_file),
                onPressed: widget.connecte ? _lirePlan : null,
              ),
              IconButton(
                key: const ValueKey('charpente_nouveau'),
                tooltip: 'Nouveau calcul',
                icon: const Icon(Icons.restart_alt),
                onPressed: _nouveau,
              ),
            ],
          ),
        ),
        TabBar(
          controller: _onglets,
          labelColor: accent,
          indicatorColor: accent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          // Icône à côté du mot : une barre basse, plus de place pour le calcul.
          tabs: const [
            Tab(height: 40, child: _Etiquette(Icons.grid_on, 'Plancher')),
            Tab(height: 40, child: _Etiquette(Icons.view_week, 'Murs')),
            Tab(height: 40, child: _Etiquette(Icons.stairs, 'Escalier')),
            Tab(height: 40, child: _Etiquette(Icons.view_in_ar, '3D')),
            Tab(height: 40, child: _Etiquette(Icons.list_alt, 'Commande')),
          ],
        ),
        SizedBox(
          height: 2,
          child: _enAttente ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: TabBarView(
            controller: _onglets,
            // Pas de glissement : la vue 3D utilise les gestes.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              OngletPlancher(
                projet: _projet,
                resultats: _res,
                onChange: _changer,
                ouvrir3D: () => _onglets.animateTo(3),
                reglagesHabituels: BarreReglagesHabituels(
                  cle: 'plancher',
                  existe: _habitudes.plancher != null,
                  suivis: _habitudes.plancherSuivi(_projet),
                  onGarder: () => _garderHabitudes(plancher: true),
                  onRemettre: () => _remettreHabitudes(plancher: true),
                ),
              ),
              OngletMurs(
                projet: _projet,
                resultats: _res,
                onChange: _changer,
                ouvrir3D: () => _onglets.animateTo(3),
                reglagesHabituels: BarreReglagesHabituels(
                  cle: 'murs',
                  existe: _habitudes.murs != null,
                  suivis: _habitudes.mursSuivis(_projet),
                  onGarder: () => _garderHabitudes(plancher: false),
                  onRemettre: () => _remettreHabitudes(plancher: false),
                ),
              ),
              OngletEscalier(
                projet: _projet,
                resultats: _res,
                onChange: _changer,
              ),
              _Onglet3D(resultats: _res),
              OngletCommande(
                projet: _projet,
                resultats: _res,
                manuelles: _manuelles,
                onManuelles: _changerManuelles,
                companyId: widget.companyId,
                chantierId: widget.chantierId,
                connecte: widget.connecte,
                listeEnregistrees: widget.listeEnregistrees,
                onOuvrirProjet: (p) {
                  _nom.text = p.nom;
                  _changer(p);
                  _onglets.animateTo(0);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Etiquette extends StatelessWidget {
  final IconData icone;
  final String texte;
  const _Etiquette(this.icone, this.texte);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 18),
        const SizedBox(width: 4),
        Flexible(
          child: Text(texte, softWrap: false, overflow: TextOverflow.fade),
        ),
      ],
    );
  }
}

class _Onglet3D extends StatelessWidget {
  final ResultatsProjet resultats;
  const _Onglet3D({required this.resultats});

  @override
  Widget build(BuildContext context) {
    // Pas de défilement ici : la vue 3D prend toute la place et réagit aux gestes.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resultats.erreurPlancher != null)
            BlocMessages([
              'Plancher : ${resultats.erreurPlancher}',
            ], erreur: true),
          if (resultats.erreurTerrasse != null)
            BlocMessages([
              'Plancher : ${resultats.erreurTerrasse}',
            ], erreur: true),
          if (resultats.erreurEscalier != null)
            BlocMessages([
              'Escalier : ${resultats.erreurEscalier}',
            ], erreur: true),
          if (resultats.erreurMurs != null)
            BlocMessages(['Murs : ${resultats.erreurMurs}'], erreur: true),
          Expanded(
            child: Vue3D(
              key: const ValueKey('vue3d_principale'),
              scene: resultats.scene,
            ),
          ),
        ],
      ),
    );
  }
}
