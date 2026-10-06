import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/regles_paie.dart';
import '../../services/app_session.dart';
import '../../services/fonctions.dart';

/// Règles de paie de la compagnie : pauses et voyagement.
/// Réservé aux admins (dont le super-admin) ; appliqué par les règles
/// Firestore. Après chaque enregistrement, le serveur recalcule les feuilles de
/// la SEMAINE COURANTE ; les semaines précédentes ne sont jamais modifiées.
class ReglesPaieScreen extends StatefulWidget {
  const ReglesPaieScreen({super.key});

  @override
  State<ReglesPaieScreen> createState() => _ReglesPaieScreenState();
}

class _ReglesPaieScreenState extends State<ReglesPaieScreen> {
  late ReglesPaie _r = AppSession.reglesPaie.value;
  bool _enCours = false;
  bool _recalculEnCours = false;

  /// Demande au serveur d'appliquer les règles actuelles aux feuilles de la
  /// semaine courante. Retourne le message à montrer et le succès ; n'échoue jamais.
  static Future<(String, bool)> recalculerSemaineCourante() async {
    try {
      final r = await Fonctions.appeler('recalculerSemaineCourante');
      final n = (r['modifiees'] as num?)?.toInt() ?? 0;
      return (
        n == 0
            ? 'Semaine courante déjà à jour.'
            : 'Semaine courante mise à jour : $n feuille${n > 1 ? 's' : ''} '
                  'recalculée${n > 1 ? 's' : ''}.',
        true,
      );
    } catch (e) {
      return (
        Fonctions.message(
          e,
          'la semaine courante n\'a pas pu être mise à jour. Réessayez.',
        ),
        false,
      );
    }
  }

  Future<void> _recalculerMaintenant() async {
    if (!AppSession.estAdmin) return;
    setState(() => _recalculEnCours = true);
    final messager = ScaffoldMessenger.of(context);
    final (message, ok) = await recalculerSemaineCourante();
    if (!mounted) return;
    setState(() => _recalculEnCours = false);
    messager.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? null : Colors.red),
    );
  }

  void _modifier({
    int? pauseMatinMinutes,
    bool? pauseMatinPayee,
    int? dinerMinutes,
    bool? dinerPaye,
    bool? voyagementActif,
    int? voyagementSeuilMinutes,
    int? voyagementPourcentage,
  }) {
    setState(() {
      _r = ReglesPaie(
        pauseMatinMinutes: pauseMatinMinutes ?? _r.pauseMatinMinutes,
        pauseMatinPayee: pauseMatinPayee ?? _r.pauseMatinPayee,
        dinerMinutes: dinerMinutes ?? _r.dinerMinutes,
        dinerPaye: dinerPaye ?? _r.dinerPaye,
        voyagementActif: voyagementActif ?? _r.voyagementActif,
        voyagementSeuilMinutes:
            voyagementSeuilMinutes ?? _r.voyagementSeuilMinutes,
        voyagementPourcentage:
            voyagementPourcentage ?? _r.voyagementPourcentage,
      );
    });
  }

  Future<void> _enregistrer() async {
    final companyId = AppSession.current?.companyId;
    if (companyId == null || !AppSession.estAdmin) return;
    setState(() => _enCours = true);
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);
    final regles = _r;

    // Effet immédiat sur cet appareil (les feuilles de temps se recalculent
    // sans attendre le serveur). Firestore renvoie l'état réel si l'écriture
    // est refusée : l'écoute de la compagnie rétablit alors les anciennes règles.
    AppSession.reglesPaie.value = regles;
    final ecriture = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .update({'reglesPaie': regles.versMap()});
    navigateur.pop();
    messager.showSnackBar(
      const SnackBar(content: Text('Enregistrement des règles de paie…')),
    );
    try {
      await ecriture;
      // La semaine courante s'ajuste aux nouvelles règles (heures déjà saisies) ;
      // les semaines précédentes ne bougent pas.
      final (message, ok) = await recalculerSemaineCourante();
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Règles de paie enregistrées. $message'
                  : 'Règles de paie enregistrées, mais $message',
            ),
            backgroundColor: ok ? null : Colors.orange.shade800,
            duration: const Duration(seconds: 6),
          ),
        );
    } catch (_) {
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'enregistrer les règles. Réessayez.'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  /// « 2 h de voyagement → 1 h au-delà du seuil, payées à 50 % = 0 h 30. »
  String get _exempleVoyagement {
    const jour = 120; // 2 h de voyagement
    final audela = jour - _r.voyagementSeuilMinutes;
    if (audela <= 0) {
      return 'Exemple : 2 h de voyagement → rien (sous le seuil).';
    }
    return 'Exemple : 2 h de voyagement → ${_heures(audela)} au-delà du seuil, '
        'payées à ${_r.voyagementPourcentage} % = '
        '${_heures(_r.minutesVoyagementPayees(jour))}.';
  }

  static String _heures(num minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final exempleJour = _r.minutesTravaillees(
      debutMinutes: 7 * 60,
      finMinutes: 15 * 60,
      pauseMatinPrise: true,
      dinerPris: true,
    );
    final modifie = _r != AppSession.reglesPaie.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Heures et voyagement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'S\'applique aux feuilles de temps de toute la compagnie. La semaine '
            'courante est mise à jour avec les nouvelles règles ; les semaines '
            'précédentes ne changent jamais.',
            key: ValueKey('texte_semaines'),
          ),
          const SizedBox(height: 16),
          _Section(
            titre: 'Pause du matin',
            enfants: [
              _Compteur(
                cle: 'pause_minutes',
                libelle: 'Durée',
                valeur: _r.pauseMatinMinutes,
                pas: 5,
                max: ReglesPaie.maxMinutesPause,
                unite: 'min',
                onChanged: (v) => _modifier(pauseMatinMinutes: v),
              ),
              SwitchListTile(
                key: const ValueKey('pause_payee'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Pause payée'),
                subtitle: Text(
                  _r.pauseMatinPayee
                      ? 'Non prise : ${_r.pauseMatinMinutes} min ajoutées'
                      : 'Prise : ${_r.pauseMatinMinutes} min retirées',
                ),
                value: _r.pauseMatinPayee,
                onChanged: (v) => _modifier(pauseMatinPayee: v),
              ),
            ],
          ),
          _Section(
            titre: 'Dîner',
            enfants: [
              _Compteur(
                cle: 'diner_minutes',
                libelle: 'Durée',
                valeur: _r.dinerMinutes,
                pas: 5,
                max: ReglesPaie.maxMinutesPause,
                unite: 'min',
                onChanged: (v) => _modifier(dinerMinutes: v),
              ),
              SwitchListTile(
                key: const ValueKey('diner_paye'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Dîner payé'),
                subtitle: Text(
                  _r.dinerPaye
                      ? 'Non pris : ${_r.dinerMinutes} min ajoutées'
                      : 'Pris : ${_r.dinerMinutes} min retirées',
                ),
                value: _r.dinerPaye,
                onChanged: (v) => _modifier(dinerPaye: v),
              ),
            ],
          ),
          _Section(
            titre: 'Voyagement',
            enfants: [
              SwitchListTile(
                key: const ValueKey('voyagement_actif'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Voyagement payé par l\'employeur'),
                subtitle: Text(
                  _r.voyagementActif
                      ? 'Les employés saisissent leur voyagement chaque jour.'
                      : 'Le champ voyagement est retiré des feuilles de temps.',
                ),
                value: _r.voyagementActif,
                onChanged: (v) => _modifier(voyagementActif: v),
              ),
              if (_r.voyagementActif) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Seul le temps au-delà du seuil est payé, au pourcentage '
                    'choisi. Rien jusqu\'au seuil.',
                    key: ValueKey('explication_voyagement'),
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                _Compteur(
                  cle: 'voyagement_seuil',
                  libelle: 'Payé à partir de',
                  valeur: _r.voyagementSeuilMinutes,
                  pas: 15,
                  max: ReglesPaie.maxSeuilMinutes,
                  unite: 'min / jour',
                  onChanged: (v) => _modifier(voyagementSeuilMinutes: v),
                ),
                _Compteur(
                  cle: 'voyagement_pourcentage',
                  libelle: 'Pourcentage payé',
                  valeur: _r.voyagementPourcentage,
                  pas: 5,
                  max: ReglesPaie.maxPourcentage,
                  unite: '%',
                  onChanged: (v) => _modifier(voyagementPourcentage: v),
                ),
                const SizedBox(height: 4),
                Text(
                  _exempleVoyagement,
                  key: const ValueKey('exemple_voyagement'),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Exemple : 7 h à 15 h, pause et dîner pris = '
                '${exempleJour == null ? '—' : _heures(exempleJour)} payées.',
                key: const ValueKey('exemple_journee'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('enregistrer_regles'),
            onPressed: (!modifie || _enCours) ? null : _enregistrer,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer pour la compagnie'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('recalculer_semaine'),
            onPressed: (_enCours || _recalculEnCours || modifie)
                ? null
                : _recalculerMaintenant,
            icon: _recalculEnCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Recalculer la semaine courante'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Applique les règles enregistrées aux heures déjà saisies cette '
              'semaine. Les semaines précédentes ne sont jamais modifiées.',
              key: ValueKey('aide_recalcul'),
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String titre;
  final List<Widget> enfants;
  const _Section({required this.titre, required this.enfants});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          ...enfants,
        ],
      ),
    );
  }
}

/// Valeur entière réglée avec − et +, bornée entre 0 et [max].
class _Compteur extends StatelessWidget {
  final String cle;
  final String libelle;
  final int valeur;
  final int pas;
  final int max;
  final String unite;
  final ValueChanged<int> onChanged;

  const _Compteur({
    required this.cle,
    required this.libelle,
    required this.valeur,
    required this.pas,
    required this.max,
    required this.unite,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(libelle)),
        IconButton(
          key: ValueKey('${cle}_moins'),
          tooltip: 'Diminuer',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: valeur <= 0
              ? null
              : () => onChanged((valeur - pas).clamp(0, max)),
        ),
        SizedBox(
          width: 96,
          child: Text(
            '$valeur $unite',
            key: ValueKey('${cle}_valeur'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: ValueKey('${cle}_plus'),
          tooltip: 'Augmenter',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: valeur >= max
              ? null
              : () => onChanged((valeur + pas).clamp(0, max)),
        ),
      ],
    );
  }
}
