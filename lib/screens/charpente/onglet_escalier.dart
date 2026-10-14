import 'package:flutter/material.dart';

import '../../charpente/escalier_projet.dart';
import '../../charpente/projet.dart';
import '../../charpente/unites.dart';
import '../../services/preferences.dart';
import 'champs.dart';
import 'ecran_escalier.dart';

/// Onglet « Escalier » de la charpente : l'escalier jumelé au plancher. Il descend du côté
/// choisi (centré, ou à une distance du coin de gauche vu de l'extérieur), sa hauteur est celle
/// de la plateforme et ses marches suivent le dessus du plancher (composite ou bois). Il est dans
/// la 3D et la commande du projet.
class OngletEscalier extends StatelessWidget {
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  final ValueChanged<ProjetCharpente> onChange;

  const OngletEscalier({
    super.key,
    required this.projet,
    required this.resultats,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final interrupteur = SwitchListTile(
      key: const ValueKey('escalier_actif'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Inclure un escalier'),
      subtitle: const Text(
        'Jumelé au plancher : il descend d\'un côté de la plateforme.',
      ),
      value: projet.escalierActif,
      onChanged: (v) => onChange(projet.copieAvec(escalierActif: v)),
    );
    if (!projet.escalierActif) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [interrupteur],
      );
    }
    final plancherComposite = projet.plancherActif
        ? projet.plancher.composite
        : null;
    return EcranEscalier(
      key: const ValueKey('escalier_du_projet'),
      projet: true,
      initial: projet.escalier,
      onChange: (e) => onChange(projet.copieAvec(escalier: e)),
      compositeDuPlancher: plancherComposite,
      contremarcheHautFournie: resultats.terrasse != null,
      entete: [
        interrupteur,
        if (resultats.erreurEscalier != null)
          BlocMessages(
            [resultats.erreurEscalier!],
            erreur: true,
            key: const ValueKey('escalier_projet_erreur'),
          ),
        ..._placement(context),
      ],
    );
  }

  List<Widget> _placement(BuildContext context) {
    final contour = resultats.contour;
    final e = projet.escalier;
    if (!projet.plancherActif || contour == null) {
      return [
        Text(
          'Sans plancher, l\'escalier est calculé seul.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    final metrique = Preferences.estMetrique;
    String l(double po) => formatLongueur(po, metrique: metrique);
    final maison = projet.plancher.coteMaison;
    void changer(ParametresEscalier Function(ParametresEscalier) f) =>
        onChange(projet.copieAvec(escalier: f(e)));
    return [
      const TitreSection('Place sur le plancher'),
      DropdownButtonFormField<int>(
        key: ValueKey('escalier_cote_${e.cote}'),
        initialValue: e.cote < contour.nombre ? e.cote : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Côté du plancher',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (var i = 0; i < contour.nombre; i++)
            DropdownMenuItem(
              value: i,
              enabled: i != maison,
              child: Text(
                'Côté ${i + 1} — ${l(contour.longueurCote(i))}'
                '${i == maison ? ' (maison)' : ''}',
              ),
            ),
        ],
        onChanged: (i) =>
            i == null ? null : changer((e) => e.copieAvec(cote: i)),
      ),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        key: const ValueKey('escalier_position'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Centré')),
          ButtonSegment(value: false, label: Text('Depuis le coin')),
        ],
        selected: {e.centre},
        onSelectionChanged: (s) => changer((e) => e.copieAvec(centre: s.first)),
      ),
      if (!e.centre) ...[
        const SizedBox(height: 8),
        ChampLongueur(
          key: const ValueKey('escalier_distance_coin'),
          label: 'Distance du coin de gauche',
          aide: 'Vu de l\'extérieur, face à la plateforme.',
          valeur: e.distanceCoin,
          min: 0,
          max: 12000,
          onChange: (v) => changer((e) => e.copieAvec(distanceCoin: v)),
        ),
      ],
    ];
  }
}
