import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/regles_paie.dart';
import '../../services/app_session.dart';

/// Règles de paie de la compagnie : pauses et voyagement.
/// Réservé aux admins (dont le super-admin) ; appliqué par les règles
/// Firestore. S'applique aux feuilles de temps saisies à partir de maintenant.
class ReglesPaieScreen extends StatefulWidget {
  const ReglesPaieScreen({super.key});

  @override
  State<ReglesPaieScreen> createState() => _ReglesPaieScreenState();
}

class _ReglesPaieScreenState extends State<ReglesPaieScreen> {
  late ReglesPaie _r = AppSession.reglesPaie.value;
  bool _enCours = false;

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
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Règles de paie enregistrées.')),
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
            'S\'applique aux feuilles de temps de toute la compagnie. Les semaines '
            'déjà remises gardent les règles en vigueur au moment de la saisie.',
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
                  'Exemples : ${_r.voyagementSeuilMinutes > 0 ? '${_r.voyagementSeuilMinutes - 1} min → rien ; ' : ''}'
                  '90 min → ${_heures(_r.minutesVoyagementPayees(90))} payées.',
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
