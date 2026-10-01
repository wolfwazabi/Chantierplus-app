import 'package:flutter/material.dart';

import '../../charpente/geometrie.dart';
import '../../charpente/mur.dart' show SectionBois;
import '../../charpente/panneaux.dart';
import '../../charpente/plancher.dart';
import '../../charpente/projet.dart';
import '../../charpente/unites.dart';
import '../../services/preferences.dart';
import 'champs.dart';
import 'vue_3d.dart';

/// Onglet « Plancher » : forme, solives, sous-plancher et résultats.
class OngletPlancher extends StatelessWidget {
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  final ValueChanged<ProjetCharpente> onChange;

  /// Un toucher sur l'aperçu ouvre la vue 3D.
  final VoidCallback? ouvrir3D;

  const OngletPlancher({
    super.key,
    required this.projet,
    required this.resultats,
    required this.onChange,
    this.ouvrir3D,
  });

  ParametresPlancher get _p => projet.plancher;

  void _set(ParametresPlancher p) => onChange(projet.copieAvec(plancher: p));

  bool get _metrique => Preferences.estMetrique;

  @override
  Widget build(BuildContext context) {
    final res = resultats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SwitchListTile(
          key: const ValueKey('plancher_actif'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Inclure un plancher'),
          subtitle: const Text(
            'Solives, solives de rive, étriers et sous-plancher',
          ),
          value: projet.plancherActif,
          onChanged: (v) => onChange(projet.copieAvec(plancherActif: v)),
        ),
        if (projet.plancherActif) ...[
          if (res.erreurPlancher != null)
            BlocMessages([res.erreurPlancher!], erreur: true),
          if (res.plancher != null)
            Vue3D(
              key: const ValueKey('plancher_apercu'),
              scene: res.scene,
              controles: false,
              interactif: false,
              onTap: ouvrir3D,
              hauteur: 240,
            ),
          const TitreSection(
            'Forme du plancher',
            aide:
                'Mesures hors tout de l\'ossature (face extérieure des rives).',
          ),
          _SelecteurForme(projet: projet, onChange: onChange),
          const TitreSection('Solives'),
          _entraxe(),
          const SizedBox(height: 12),
          DropdownButtonFormField<SectionBois>(
            key: ValueKey('section_${_p.section.nom}'),
            initialValue: _p.section,
            decoration: const InputDecoration(
              labelText: 'Section des solives et des rives',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final s in sectionsPlancher)
                DropdownMenuItem(
                  value: s,
                  child: Text('${s.nom} (${formatImperial(s.profondeur)})'),
                ),
            ],
            onChanged: (s) => s == null ? null : _set(_p.copieAvec(section: s)),
          ),
          const SizedBox(height: 12),
          _direction(),
          SwitchListTile(
            key: const ValueKey('rive_double'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Solives de rive doubles'),
            subtitle: const Text(
              'Deux épaisseurs côte à côte aux extrémités des solives',
            ),
            value: _p.riveDouble,
            onChanged: (v) => _set(_p.copieAvec(riveDouble: v)),
          ),
          SwitchListTile(
            key: const ValueKey('bordure_double'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Solives de bordure doublées'),
            subtitle: const Text(
              'Les solives le long des côtés parallèles aux solives',
            ),
            value: _p.solivesDoublesAuxCotes,
            onChanged: (v) => _set(_p.copieAvec(solivesDoublesAuxCotes: v)),
          ),
          const SizedBox(height: 4),
          const Text('Étriers de solive'),
          const SizedBox(height: 4),
          SegmentedButton<ModeEtriers>(
            key: const ValueKey('etriers'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ModeEtriers.aucun, label: Text('Aucun')),
              ButtonSegment(value: ModeEtriers.unBout, label: Text('Un bout')),
              ButtonSegment(
                value: ModeEtriers.deuxBouts,
                label: Text('Deux bouts'),
              ),
            ],
            selected: {_p.etriers},
            onSelectionChanged: (s) => _set(_p.copieAvec(etriers: s.first)),
          ),
          const SizedBox(height: 12),
          const Text('Rangées d\'entremises (blocage)'),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            key: const ValueKey('entremises'),
            segments: const [
              ButtonSegment(value: 0, label: Text('0')),
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {_p.rangeesEntremises},
            onSelectionChanged: (s) =>
                _set(_p.copieAvec(rangeesEntremises: s.first)),
          ),
          const TitreSection(
            'Sous-plancher',
            aide:
                'Feuilles posées en travers des solives, joints décalés, '
                'chaque joint sur le centre d\'une solive.',
          ),
          DropdownButtonFormField<FormatPanneau>(
            key: ValueKey('format_${_p.panneau.id}'),
            initialValue: _p.panneau,
            decoration: const InputDecoration(
              labelText: 'Format des feuilles',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final f in formatsPanneaux.where((f) => !f.estIsolant))
                DropdownMenuItem(
                  value: f,
                  child: Text(
                    _metrique
                        ? '${f.nom} (${f.surfaceM2.toStringAsFixed(2)} m²)'
                        : '${f.nom} (${f.surfacePi2.toStringAsFixed(0)} pi²)',
                  ),
                ),
            ],
            onChanged: (f) => f == null ? null : _set(_p.copieAvec(panneau: f)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ChampLongueur(
                  label: 'Décalage minimal des joints',
                  valeur: _p.decalageMin,
                  min: 0,
                  max: 96,
                  aide: 'Entre deux rangées voisines',
                  onChange: (v) => _set(_p.copieAvec(decalageMin: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChampNombre(
                  label: 'Marge d\'achat',
                  valeur: _p.margePanneauxPourcent,
                  min: 0,
                  max: 50,
                  decimales: 0,
                  suffixe: '%',
                  aide: 'Sur les feuilles',
                  onChange: (v) => _set(_p.copieAvec(margePanneauxPourcent: v)),
                ),
              ),
            ],
          ),
          const TitreSection('Longueurs de bois disponibles'),
          _longueurs(),
          const TitreSection('Résultats'),
          if (res.plancher != null) _Resultats(res.plancher!, projet),
        ],
      ],
    );
  }

  Widget _entraxe() {
    final choix = espacementsStandards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Entraxe des solives'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final e in choix)
              ChoiceChip(
                key: ValueKey('entraxe_$e'),
                label: Text(
                  '${formatNombre(e, decimales: 1)} po (${(e * 25.4).round()} mm)',
                ),
                selected: (_p.espacement - e).abs() < 1e-9,
                onSelected: (_) => _set(_p.copieAvec(espacement: e)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ChampNombre(
          key: const ValueKey('entraxe_champ'),
          label: 'Entraxe (centre à centre)',
          valeur: _p.espacement,
          min: 6,
          max: 48,
          decimales: 2,
          suffixe: 'po',
          onChange: (v) => _set(_p.copieAvec(espacement: v)),
        ),
      ],
    );
  }

  Widget _direction() {
    final auto = _p.angleSolivesDeg == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Direction des solives'),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          key: const ValueKey('direction'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Automatique')),
            ButtonSegment(value: false, label: Text('Choisir l\'angle')),
          ],
          selected: {auto},
          onSelectionChanged: (s) => _set(
            _p.copieAvec(
              angleSolivesDeg: () => s.first
                  ? null
                  : (resultats.plancher?.angleSolivesDeg ?? 0).roundToDouble(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (auto)
          Text(
            resultats.plancher == null
                ? 'La plus courte portée est choisie.'
                : 'Portée la plus courte : solives à ${formatAngle(resultats.plancher!.angleSolivesDeg)} '
                      'du premier côté (portée ${formatLongueur(resultats.plancher!.porteeMax, metrique: _metrique)}).',
            style: const TextStyle(fontSize: 12),
          )
        else ...[
          const SizedBox(height: 4),
          ChampNombre(
            key: const ValueKey('angle_solives'),
            label: 'Angle des solives',
            valeur: _p.angleSolivesDeg!,
            min: 0,
            max: 180,
            suffixe: '°',
            aide: '0° : le long du premier côté ; 90° : perpendiculaire',
            onChange: (v) => _set(_p.copieAvec(angleSolivesDeg: () => v)),
          ),
        ],
      ],
    );
  }

  Widget _longueurs() {
    const toutes = longueursPlanchesParDefaut;
    return Wrap(
      spacing: 8,
      children: [
        for (final l in toutes)
          FilterChip(
            key: ValueKey('longueur_$l'),
            label: Text(formatPlanche(l, metrique: _metrique)),
            selected: _p.longueursPlanches.contains(l),
            onSelected: (v) {
              final nouvelles = [
                for (final x in toutes)
                  if (x == l ? v : _p.longueursPlanches.contains(x)) x,
              ];
              if (nouvelles.isNotEmpty) {
                _set(_p.copieAvec(longueursPlanches: nouvelles));
              }
            },
          ),
      ],
    );
  }
}

// =============================================================================
// Forme
// =============================================================================

class _SelecteurForme extends StatelessWidget {
  final ProjetCharpente projet;
  final ValueChanged<ProjetCharpente> onChange;
  const _SelecteurForme({required this.projet, required this.onChange});

  FormePlancher get _forme => projet.plancher.forme;

  int get _mode => switch (_forme) {
    FormeRectangle() => 0,
    FormeCotesAngles() => 1,
    FormePoints() => 2,
  };

  void _definir(FormePlancher f) =>
      onChange(projet.copieAvec(plancher: projet.plancher.copieAvec(forme: f)));

  /// Change de mode en conservant la forme actuelle quand c'est possible.
  void _changerMode(int m) {
    if (m == _mode) {
      return;
    }
    Polygone? p;
    try {
      p = _forme.construire();
    } on FormeInvalide {
      p = null;
    }
    switch (m) {
      case 0:
        final b = p?.boite;
        _definir(FormeRectangle(b?.largeur ?? 156, b?.hauteur ?? 126));
      case 1:
        if (p != null && p.nombre >= 3 && p.nombre <= 10) {
          // Côtés et angles : tous les côtés sauf le dernier, tous les angles
          // sauf les deux derniers.
          final c = p.longueursCotes;
          final a = [
            for (var i = 1; i < p.nombre - 1; i++) p.angleInterieurDeg(i),
          ];
          _definir(
            FormeCotesAngles(
              c.sublist(0, p.nombre - 1),
              a.sublist(0, p.nombre - 2),
            ),
          );
        } else {
          _definir(const FormeCotesAngles([156, 126, 156], [90, 90]));
        }
      case 2:
        // Coin le plus bas et le plus à gauche à l'origine : coordonnées positives.
        final b = p?.boite;
        _definir(
          FormePoints([
            for (final q
                in p?.sommets ??
                    const [Pt(0, 0), Pt(156, 0), Pt(156, 126), Pt(0, 126)])
              Pt(q.x - (b?.xMin ?? 0), q.y - (b?.yMin ?? 0)),
          ]),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _forme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          key: const ValueKey('forme_mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Rectangle')),
            ButtonSegment(value: 1, label: Text('Côtés et angles')),
            ButtonSegment(value: 2, label: Text('Points')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => _changerMode(s.first),
        ),
        const SizedBox(height: 12),
        switch (f) {
          FormeRectangle() => Row(
            children: [
              Expanded(
                child: ChampLongueur(
                  key: const ValueKey('rect_longueur'),
                  label: 'Longueur',
                  valeur: f.longueur,
                  onChange: (v) => _definir(FormeRectangle(v, f.largeur)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChampLongueur(
                  key: const ValueKey('rect_largeur'),
                  label: 'Largeur',
                  valeur: f.largeur,
                  onChange: (v) => _definir(FormeRectangle(f.longueur, v)),
                ),
              ),
            ],
          ),
          FormeCotesAngles() => _CotesAngles(forme: f, onChange: _definir),
          FormePoints() => _Points(forme: f, onChange: _definir),
        },
      ],
    );
  }
}

class _CotesAngles extends StatelessWidget {
  final FormeCotesAngles forme;
  final ValueChanged<FormePlancher> onChange;
  const _CotesAngles({required this.forme, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final cotes = forme.cotes;
    final angles = forme.angles;
    Polygone? p;
    String? erreur;
    try {
      p = forme.construire();
    } on FormeInvalide catch (e) {
      erreur = e.message;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Partez du coin en bas à gauche, premier côté vers la droite. Entrez '
          'chaque côté puis l\'angle INTÉRIEUR au coin suivant. Le dernier côté '
          'et les deux derniers angles sont calculés pour fermer la forme.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < cotes.length; i++) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ChampLongueur(
                  key: ValueKey('cote_$i'),
                  label: 'Côté ${i + 1}',
                  valeur: cotes[i],
                  aide: ' ',
                  onChange: (v) {
                    final c = [...cotes]..[i] = v;
                    onChange(FormeCotesAngles(c, angles));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: i < angles.length
                    ? ChampNombre(
                        key: ValueKey('angle_$i'),
                        label: 'Angle ${i + 1}',
                        valeur: angles[i],
                        min: 1,
                        max: 359,
                        suffixe: '°',
                        aide: ' ',
                        onChange: (v) {
                          final a = [...angles]..[i] = v;
                          onChange(FormeCotesAngles(cotes, a));
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('ajouter_cote'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un côté'),
              onPressed: cotes.length >= 9
                  ? null
                  : () => onChange(
                      FormeCotesAngles([...cotes, 120], [...angles, 90]),
                    ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('retirer_cote'),
              icon: const Icon(Icons.remove),
              label: const Text('Retirer le dernier'),
              onPressed: cotes.length <= 2
                  ? null
                  : () => onChange(
                      FormeCotesAngles(
                        cotes.sublist(0, cotes.length - 1),
                        angles.sublist(0, angles.length - 1),
                      ),
                    ),
            ),
          ],
        ),
        if (erreur != null) BlocMessages([erreur], erreur: true),
        if (p != null) _Descriptif(p, cotesSaisis: cotes.length),
      ],
    );
  }
}

/// Côtés et angles de la forme obtenue, les valeurs déduites étant marquées.
class _Descriptif extends StatelessWidget {
  final Polygone forme;
  final int cotesSaisis;
  const _Descriptif(this.forme, {required this.cotesSaisis});

  @override
  Widget build(BuildContext context) {
    final metrique = Preferences.estMetrique;
    final d = forme.descriptif;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forme obtenue : ${forme.nombre} côtés, '
              '${formatNombre(forme.aire / 144, decimales: 1)} pi² '
              '(${formatNombre(forme.aire * 0.00064516, decimales: 1)} m²)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < d.length; i++)
              Text(
                'Côté ${i + 1} : ${formatLongueur(d[i].$1, metrique: metrique)}'
                '${i >= cotesSaisis ? ' (calculé)' : ''}'
                '  —  angle ${formatAngle(d[i].$2)}'
                '${i >= cotesSaisis - 1 ? ' (calculé)' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

class _Points extends StatelessWidget {
  final FormePoints forme;
  final ValueChanged<FormePlancher> onChange;
  const _Points({required this.forme, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final pts = forme.points;
    String? erreur;
    try {
      forme.construire();
    } on FormeInvalide catch (e) {
      erreur = e.message;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Coordonnées des coins, dans l\'ordre autour de la forme (x vers la '
          'droite, y vers le haut).',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < pts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('${i + 1}')),
                Expanded(
                  child: ChampLongueur(
                    key: ValueKey('pt_x_$i'),
                    label: 'x',
                    valeur: pts[i].x.abs(),
                    min: 0,
                    aide: ' ',
                    onChange: (v) => onChange(
                      FormePoints(
                        [...pts]..[i] = Pt(pts[i].x < 0 ? -v : v, pts[i].y),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChampLongueur(
                    key: ValueKey('pt_y_$i'),
                    label: 'y',
                    valeur: pts[i].y.abs(),
                    min: 0,
                    aide: ' ',
                    onChange: (v) => onChange(
                      FormePoints(
                        [...pts]..[i] = Pt(pts[i].x, pts[i].y < 0 ? -v : v),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer ce point',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: pts.length <= 3
                      ? null
                      : () => onChange(FormePoints([...pts]..removeAt(i))),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('ajouter_point'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un point'),
              onPressed: pts.length >= 24
                  ? null
                  : () => onChange(
                      FormePoints([...pts, Pt(pts.last.x + 24, pts.last.y)]),
                    ),
            ),
          ],
        ),
        if (erreur != null) BlocMessages([erreur], erreur: true),
      ],
    );
  }
}

// =============================================================================
// Résultats
// =============================================================================

class _Resultats extends StatelessWidget {
  final ResultatPlancher r;
  final ProjetCharpente projet;
  const _Resultats(this.r, this.projet);

  @override
  Widget build(BuildContext context) {
    final metrique = Preferences.estMetrique;
    final section = projet.plancher.section.nom;
    final bordures = r.solives.where((s) => s.bordure).length;
    final lignes = <(String, String)>[
      (
        'Solives',
        '${r.nombreSolives}${bordures > 0 ? ' (dont $bordures de bordure)' : ''}',
      ),
      ('Solives de rive', '${r.nombreRives}'),
      if (r.entremises.isNotEmpty) ('Entremises', '${r.entremises.length}'),
      if (r.etriers > 0) ('Étriers', '${r.etriers}'),
      (
        'Portée la plus longue',
        formatLongueur(r.porteeMax, metrique: metrique),
      ),
      (
        'Feuilles de sous-plancher',
        '${r.panneaux.feuillesACommander} à commander '
            '(${r.panneaux.feuillesUtilisees} utilisées, perte '
            '${formatNombre(r.panneaux.pertePourcent, decimales: 0)} %)',
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (a, b) in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: Text(a)),
                    Expanded(
                      flex: 6,
                      child: Text(
                        b,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              'Bois à commander ($section)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final e in r.bois.parLongueur.entries)
              Text('${e.value} × ${formatPlanche(e.key, metrique: metrique)}'),
            Text(
              'Perte de bois : ${formatNombre(r.bois.pertePourcent, decimales: 1)} %',
              style: const TextStyle(fontSize: 12),
            ),
            BlocMessages(r.avertissements),
          ],
        ),
      ),
    );
  }
}
