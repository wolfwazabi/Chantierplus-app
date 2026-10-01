import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../charpente/commande.dart';
import '../../charpente/projet.dart';
import '../../services/preferences.dart';
import '../../services/theme_compagnie.dart';
import 'assistant_charpente.dart';
import 'champs.dart';
import 'onglet_commande.dart';
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

  const CharpenteScreen({
    super.key,
    required this.companyId,
    required this.chantierId,
    required this.connecte,
    this.listeEnregistrees,
    this.appelAssistant = appelAssistantParDefaut,
  });

  @override
  State<CharpenteScreen> createState() => _CharpenteScreenState();
}

class _CharpenteScreenState extends State<CharpenteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _onglets = TabController(length: 4, vsync: this);
  ProjetCharpente _projet = const ProjetCharpente();
  late ResultatsProjet _res;
  List<LigneCommande> _manuelles = [];
  Timer? _sauvegarde;
  Timer? _recalcul;
  bool _enAttente = false;
  Duration _dernierCalcul = Duration.zero;
  final _nom = TextEditingController();

  String get _cle => 'charpente.brouillon.${widget.chantierId}';

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
      _projet = const ProjetCharpente();
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

  Future<void> _restaurer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texte = prefs.getString(_cle);
      if (texte == null) {
        return;
      }
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
      _changer(p);
      _onglets.animateTo(0);
    }
  }

  Future<void> _nouveau() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau calcul ?'),
        content: const Text(
          'Le calcul en cours (plancher, murs et lignes ajoutées) est effacé. '
          'Les commandes déjà enregistrées ne changent pas.',
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
        _projet = const ProjetCharpente();
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
          tabs: const [
            Tab(icon: Icon(Icons.grid_on), text: 'Plancher'),
            Tab(icon: Icon(Icons.view_week), text: 'Murs'),
            Tab(icon: Icon(Icons.view_in_ar), text: '3D'),
            Tab(icon: Icon(Icons.list_alt), text: 'Commande'),
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
                ouvrir3D: () => _onglets.animateTo(2),
              ),
              OngletMurs(
                projet: _projet,
                resultats: _res,
                onChange: _changer,
                ouvrir3D: () => _onglets.animateTo(2),
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
