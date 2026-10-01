import 'dart:convert';

import 'package:flutter/material.dart';

import '../../charpente/projet.dart';
import '../../charpente/unites.dart';
import '../../services/fonctions.dart';
import '../../services/preferences.dart';
import 'champs.dart';

/// Appel du serveur : description (et projet actuel en JSON) → réponse brute.
typedef AppelAssistant = Future<Map<String, dynamic>> Function(
  String texte,
  String? projetActuel,
);

Future<Map<String, dynamic>> appelAssistantParDefaut(
  String texte,
  String? projetActuel,
) => Fonctions.appeler('assistantCharpente', {
  'texte': texte,
  'projetActuel': ?projetActuel,
});

class _Interpretation {
  final String explication;
  final List<String> hypotheses;
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  const _Interpretation(
    this.explication,
    this.hypotheses,
    this.projet,
    this.resultats,
  );
}

/// Feuille « Assistant IA » : on décrit le projet en français, le serveur le
/// convertit en paramètres validés, et l'application les calcule comme si on
/// les avait saisis. Rien n'est appliqué avant la confirmation.
class AssistantCharpente extends StatefulWidget {
  final ProjetCharpente projetActuel;
  final AppelAssistant appeler;

  const AssistantCharpente({
    super.key,
    required this.projetActuel,
    this.appeler = appelAssistantParDefaut,
  });

  @override
  State<AssistantCharpente> createState() => _AssistantCharpenteState();
}

class _AssistantCharpenteState extends State<AssistantCharpente> {
  final _texte = TextEditingController();
  bool _enCours = false;
  String? _erreur;
  _Interpretation? _resultat;

  static const _exemples = [
    'Plancher de 10\'6" × 13\' aux 16 po, solives 2×10, étriers aux deux bouts',
    'Garage de 24 pi × 20 pi : murs de 8 pi, 2 fenêtres de 36 × 48 po sur le long mur et une porte de 36 po',
    'Plancher à 5 côtés : 20 pi, 12 pi, 15 pi, 10 pi avec des angles de 90°, 110° et 120°',
  ];

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  bool get _valide => _texte.text.trim().length >= 5;

  Future<void> _interpreter({required bool modifier}) async {
    setState(() {
      _enCours = true;
      _erreur = null;
      _resultat = null;
    });
    try {
      // Le serveur relit et filtre ce JSON ; il est borné à 20 000 caractères.
      final json = jsonEncode(widget.projetActuel.toJson());
      final actuel = modifier && json.length <= 20000 ? json : null;
      final r = await widget.appeler(_texte.text.trim(), actuel);
      final projet = ProjetCharpente.fromJson(r['projet']);
      final hypotheses = [
        for (final h
            in (r['hypotheses'] is List ? r['hypotheses'] as List : []))
          if (h is String && h.trim().isNotEmpty) h.trim(),
      ];
      final explication = r['explication'] is String
          ? (r['explication'] as String).trim()
          : '';
      if (!mounted) {
        return;
      }
      setState(() {
        _resultat = _Interpretation(
          explication,
          hypotheses,
          projet,
          calculerProjet(projet, metrique: Preferences.estMetrique),
        );
        _enCours = false;
      });
    } on FormatException {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = 'La réponse de l\'assistant est illisible. Reformulez et réessayez.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = Fonctions.message(
            e,
            'L\'assistant est indisponible. Réessayez.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultat;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assistant IA',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Décrivez le projet avec vos mots : l\'assistant remplit les champs, '
              'l\'application calcule le bois. Vérifiez toujours les valeurs avant de commander.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('assistant_texte'),
              controller: _texte,
              minLines: 3,
              maxLines: 6,
              maxLength: 1500,
              decoration: const InputDecoration(
                hintText: 'Ex. : plancher de 10\'6" × 13\' aux 16 po…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _exemples)
                  ActionChip(
                    label: Text(
                      e.length > 40 ? '${e.substring(0, 38)}…' : e,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => setState(() => _texte.text = e),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('assistant_interpreter'),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Interpréter'),
                  onPressed: _valide && !_enCours
                      ? () => _interpreter(modifier: false)
                      : null,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('assistant_modifier'),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Modifier le calcul actuel'),
                  onPressed: _valide && !_enCours
                      ? () => _interpreter(modifier: true)
                      : null,
                ),
              ],
            ),
            if (_enCours)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_erreur != null) BlocMessages([_erreur!], erreur: true),
            if (r != null) ..._apercu(context, r),
          ],
        ),
      ),
    );
  }

  List<Widget> _apercu(BuildContext context, _Interpretation r) {
    final metrique = Preferences.estMetrique;
    final res = r.resultats;
    final p = r.projet;
    final lignes = <String>[
      if (p.plancherActif && res.contour != null)
        'Plancher : ${_decrire(res)} à ${formatNombre(p.plancher.espacement, decimales: 1)} po c/c, '
            'solives ${p.plancher.section.nom}'
            '${p.plancher.riveDouble ? ', rive double' : ''}',
      if (p.mursActifs && res.murs != null)
        'Murs : ${res.murs!.murs.length} mur${res.murs!.murs.length > 1 ? 's' : ''}, '
            '${res.murs!.murs.fold(0, (a, m) => a + m.spec.ouvertures.length)} ouverture(s), '
            'hauteur ${formatLongueur(res.murs!.murs.first.spec.hauteur, metrique: metrique)}',
      if (!p.plancherActif && !p.mursActifs) 'Aucun plancher ni mur.',
    ];
    return [
      const Divider(height: 24),
      Text(
        'Ce que l\'assistant a compris',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (r.explication.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(r.explication),
        ),
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      if (r.hypotheses.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Hypothèses à vérifier :'),
        for (final h in r.hypotheses)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $h')),
      ],
      if (res.aDesErreurs)
        BlocMessages([
          if (res.erreurPlancher != null) 'Plancher : ${res.erreurPlancher}',
          if (res.erreurMurs != null) 'Murs : ${res.erreurMurs}',
        ], erreur: true),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          key: const ValueKey('assistant_appliquer'),
          onPressed: () => Navigator.pop(context, r.projet),
          child: Text(
            res.aDesErreurs ? 'Appliquer et corriger' : 'Appliquer ce projet',
          ),
        ),
      ),
    ];
  }

  String _decrire(ResultatsProjet res) {
    final b = res.contour!.boite;
    final metrique = Preferences.estMetrique;
    if (res.contour!.nombre == 4 && res.contour!.estRectangle) {
      return '${formatLongueur(b.largeur, metrique: metrique)} × '
          '${formatLongueur(b.hauteur, metrique: metrique)}';
    }
    return '${res.contour!.nombre} côtés, '
        '${formatNombre(res.contour!.aire / 144, decimales: 0)} pi²';
  }
}
