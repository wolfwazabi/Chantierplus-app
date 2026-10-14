import 'package:flutter/material.dart';

import '../../charpente/composite.dart';
import '../../charpente/geometrie.dart';
import '../../charpente/mur.dart' show SectionBois;
import '../../charpente/panneaux.dart';
import '../../charpente/plancher.dart';
import '../../charpente/projet.dart';
import '../../charpente/terrasse.dart';
import '../../charpente/unites.dart';
import '../../services/preferences.dart';
import 'champs.dart';
import 'vue_3d.dart';

/// Nombres de clous par étrier proposés en un toucher (le champ accepte les autres).
const _clousParEtrierCourants = [6, 8, 10, 12, 14, 16];

/// Onglet « Plancher » : forme, solives, sous-plancher et résultats.
class OngletPlancher extends StatelessWidget {
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  final ValueChanged<ProjetCharpente> onChange;

  /// Un toucher sur l'aperçu ouvre la vue 3D.
  final VoidCallback? ouvrir3D;

  /// Barre « Mes réglages habituels », au-dessus des réglages.
  final Widget? reglagesHabituels;

  const OngletPlancher({
    super.key,
    required this.projet,
    required this.resultats,
    required this.onChange,
    this.ouvrir3D,
    this.reglagesHabituels,
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
          subtitle: const Text('Solives, rives, étriers et sous-plancher'),
          value: projet.plancherActif,
          onChanged: (v) => onChange(projet.copieAvec(plancherActif: v)),
        ),
        if (projet.plancherActif) ...[
          if (res.erreurPlancher != null)
            BlocMessages([res.erreurPlancher!], erreur: true),
          if (res.erreurTerrasse != null)
            BlocMessages([res.erreurTerrasse!], erreur: true),
          if (res.plancher != null)
            Vue3D(
              key: const ValueKey('plancher_apercu'),
              scene: res.scene,
              controles: false,
              interactif: false,
              onTap: ouvrir3D,
              hauteur: 170,
            ),
          const TitreSection(
            'Forme du plancher',
            aide: 'Mesures hors tout (face extérieure des rives).',
          ),
          _SelecteurForme(projet: projet, onChange: onChange),
          const TitreSection('Solives'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<SectionBois>(
                  key: ValueKey('section_${_p.section.nom}'),
                  initialValue: _p.section,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final s in sectionsPlancher)
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          '${s.nom} (${formatImperial(s.profondeur)})',
                        ),
                      ),
                  ],
                  onChanged: (s) =>
                      s == null ? null : _set(_p.copieAvec(section: s)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoixEntraxe(
                  key: const ValueKey('entraxe'),
                  valeur: _p.espacement,
                  onChange: (v) => _set(_p.copieAvec(espacement: v)),
                ),
              ),
            ],
          ),
          const TitreSection('Réglages'),
          ?reglagesHabituels,
          SectionRepliable(
            cle: 'direction_rives',
            titre: 'Direction et rives',
            resume: _resumeRives(),
            enfants: [
              _direction(),
              SwitchListTile(
                key: const ValueKey('rive_double'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Solives de rive doubles'),
                subtitle: const Text('Deux épaisseurs aux bouts des solives'),
                value: _p.riveDouble,
                onChanged: (v) => _set(_p.copieAvec(riveDouble: v)),
              ),
              _coteMaison(),
              SwitchListTile(
                key: const ValueKey('bordure_double'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Solives de bordure doublées'),
                subtitle: const Text(
                  'Le long des côtés parallèles aux solives',
                ),
                value: _p.solivesDoublesAuxCotes,
                onChanged: (v) => _set(_p.copieAvec(solivesDoublesAuxCotes: v)),
              ),
            ],
          ),
          SectionRepliable(
            cle: 'etriers',
            titre: 'Étriers et clous',
            resume: _resumeEtriers(),
            enfants: [
              SegmentedButton<ModeEtriers>(
                key: const ValueKey('etriers'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ModeEtriers.aucun, label: Text('Aucun')),
                  ButtonSegment(
                    value: ModeEtriers.unBout,
                    label: Text('Un bout'),
                  ),
                  ButtonSegment(
                    value: ModeEtriers.deuxBouts,
                    label: Text('Deux bouts'),
                  ),
                ],
                selected: {_p.etriers},
                onSelectionChanged: (s) => _set(_p.copieAvec(etriers: s.first)),
              ),
              if (_p.etriers != ModeEtriers.aucun) ..._etriersEtClous(),
            ],
          ),
          SectionRepliable(
            cle: 'entremises',
            titre: 'Entremises',
            resume: _resumeEntremises(),
            enfants: _entremises(),
          ),
          SectionRepliable(
            cle: 'poutres',
            titre: 'Poutres et pieux vissés',
            resume: _resumePoutres(),
            enfants: _poutres(),
          ),
          SectionRepliable(
            cle: 'sous_plancher',
            titre: 'Dessus du plancher',
            resume: _resumeSousPlancher(),
            enfants: [
              SegmentedButton<bool>(
                key: const ValueKey('dessus_plancher'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Feuilles'),
                    tooltip: 'Sous-plancher en feuilles (un agrandissement)',
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Composite'),
                    tooltip:
                        'Plateforme : planches de composite, cadre et fascia',
                  ),
                ],
                selected: {_p.composite != null},
                onSelectionChanged: (s) => _set(
                  _p.copieAvec(
                    composite: () =>
                        s.first ? produitCompositeGenerique.id : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_p.composite != null)
                ..._composite(context)
              else ...[
                Text(
                  'Feuilles en travers des solives, joints décalés, '
                  'chaque joint sur une solive.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
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
                  onChanged: (f) =>
                      f == null ? null : _set(_p.copieAvec(panneau: f)),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ChampLongueur(
                        label: 'Décalage des joints',
                        valeur: _p.decalageMin,
                        min: 0,
                        max: 96,
                        aide: 'Minimum entre 2 rangées',
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
                        onChange: (v) =>
                            _set(_p.copieAvec(margePanneauxPourcent: v)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          SectionRepliable(
            cle: 'bois',
            titre: 'Bois',
            resume: _resumeBois(),
            enfants: [
              SwitchListTile(
                key: const ValueKey('coupes_separees'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Coupes séparées par catégorie'),
                subtitle: const Text(
                  'Solives, rives et entremises dans leurs propres planches',
                ),
                value: _p.coupesSeparees,
                onChanged: (v) => _set(_p.copieAvec(coupesSeparees: v)),
              ),
              const Text('Longueurs de bois disponibles'),
              const SizedBox(height: 4),
              _longueurs(),
            ],
          ),
          const TitreSection('Résultats'),
          if (res.plancher != null)
            _Resultats(res.plancher!, projet, res.terrasse),
        ],
      ],
    );
  }

  // --- Résumés des réglages repliés --------------------------------------------

  String _l(double po) => formatLongueur(po, metrique: _metrique);

  String _resumeRives() {
    final direction = _p.angleSolivesDeg == null
        ? 'Direction automatique'
        : 'Solives à ${formatAngle(_p.angleSolivesDeg!)}';
    final maison = _p.coteMaison == null
        ? ''
        : ' (côté ${_p.coteMaison! + 1} : maison)';
    return '$direction · rives ${_p.riveDouble ? 'doubles' : 'simples'}$maison · '
        'bordures ${_p.solivesDoublesAuxCotes ? 'doublées' : 'simples'}';
  }

  String _resumeEtriers() {
    if (_p.etriers == ModeEtriers.aucun) return 'Aucun étrier';
    final bouts = _p.etriers == ModeEtriers.unBout ? 'Un bout' : 'Deux bouts';
    final solives = _p.etriersBordures
        ? 'toutes les solives'
        : 'solives intérieures';
    final clous = _p.clousEtriers
        ? '${_p.clousParEtrier} clous par étrier'
        : 'clous non comptés';
    return '$bouts · $solives · $clous';
  }

  String _resumeEntremises() {
    final alternees = _p.entremisesAlternees ? ' · pose alternée' : '';
    if (_p.entremisesAuto) {
      return 'Automatiques : une rangée aux ${_l(_p.entremisesEspacement)}$alternees';
    }
    final n = _p.rangeesEntremises;
    if (n == 0) return 'Aucune';
    return '$n rangée${n > 1 ? 's' : ''}$alternees';
  }

  String _resumePoutres() {
    final po = _p.poutres;
    if (po == null) return 'Aucune';
    final patte = po.hauteurPatte > 0
        ? ' · pattes de ${_l(po.hauteurPatte)}'
        : '';
    return '${po.nombre} poutre${po.nombre > 1 ? 's' : ''} de ${po.plis} plis en '
        '${po.section.nom} · ${po.pieuxParPoutre} pieux par poutre$patte';
  }

  String _resumeSousPlancher() => _p.composite != null
      ? '${produitComposite(_p.composite).nom} · cadre en onglet · fascia'
      : '${_p.panneau.nom} · joints décalés de ${_l(_p.decalageMin)} · '
            'marge ${formatNombre(_p.margePanneauxPourcent, decimales: 0)} %';

  /// Dessus en composite : le produit et ce que son guide demande.
  List<Widget> _composite(BuildContext context) {
    final p = produitComposite(_p.composite);
    return [
      DropdownButtonFormField<String>(
        key: ValueKey('plancher_produit_${p.id}'),
        initialValue: p.id,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Produit',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final q in produitsComposite)
            DropdownMenuItem(value: q.id, child: Text(q.nom)),
        ],
        onChanged: (id) =>
            id == null ? null : _set(_p.copieAvec(composite: () => id)),
      ),
      const SizedBox(height: 6),
      Text(
        key: const ValueKey('plancher_produit_fiche'),
        'Cadre de planches à rive carrée en onglet sur le pourtour (sauf contre la maison), '
        'planches rainurées au centre en travers des solives avec les attaches ${p.attache}, '
        'fascia sur les rives, blocage sous le cadre qui longe les solives.\n'
        'Planches de ${_l(p.largeur)} × ${_l(p.epaisseur)} ; écart de ${_l(p.ecartPlancher)} '
        'entre planches, ${_l(p.ecartBout)} au bout contre le cadre, '
        '${_l(ecartMaisonComposite)} contre la maison ; solives aux '
        '${_l(p.entraxeMaxSolives)} au plus.\n'
        '${p.notePlancher}\n'
        'Source : ${p.source}.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  String _resumeBois() {
    final l = [..._p.longueursPlanches]..sort();
    final planches = l.length == longueursPlanchesParDefaut.length
        ? 'Planches de ${formatPlanche(l.first, metrique: _metrique)} à '
              '${formatPlanche(l.last, metrique: _metrique)}'
        : 'Planches : ${l.map((x) => formatPlanche(x, metrique: _metrique)).join(', ')}';
    return '$planches · coupes ${_p.coupesSeparees ? 'séparées' : 'mélangées'}';
  }

  /// Côté du contour contre la maison : sa rive reste simple.
  Widget _coteMaison() {
    final contour = resultats.contour;
    final cotes = <int>{
      ...?resultats.plancher?.cotesDeRive,
      if (_p.coteMaison != null) _p.coteMaison!,
    }.toList()..sort();
    String etiquette(int i) {
      final l = contour != null && i < contour.nombre
          ? ' — ${formatLongueur(contour.longueurCote(i), metrique: _metrique)}'
          : '';
      return 'Côté ${i + 1}$l';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: DropdownButtonFormField<int?>(
        key: ValueKey('cote_maison_${_p.coteMaison}'),
        initialValue: _p.coteMaison,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Côté de la maison',
          helperText:
              'Sa rive reste simple (doublée seulement si elle est en '
              'plusieurs morceaux).',
          helperMaxLines: 3,
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Aucun')),
          for (final i in cotes)
            DropdownMenuItem<int?>(value: i, child: Text(etiquette(i))),
        ],
        onChanged: (v) => _set(_p.copieAvec(coteMaison: () => v)),
      ),
    );
  }

  List<Widget> _etriersEtClous() => [
    SwitchListTile(
      key: const ValueKey('etriers_bordures'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Étriers sur les solives de bordure'),
      subtitle: const Text('Sinon : solives intérieures seulement'),
      value: _p.etriersBordures,
      onChanged: (v) => _set(_p.copieAvec(etriersBordures: v)),
    ),
    CheckboxListTile(
      key: const ValueKey('clous_etriers_inclus'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Clous d\'étriers'),
      subtitle: Text(
        _p.clousEtriers
            ? '${_p.clousParEtrier} par étrier · boîte de ${_p.clousParBoite} · '
                  'marge ${formatNombre(_p.margeClous, decimales: 0)} %'
            : 'Non comptés dans la commande',
        style: const TextStyle(fontSize: 12),
      ),
      value: _p.clousEtriers,
      onChanged: (v) => _set(_p.copieAvec(clousEtriers: v ?? true)),
    ),
    if (_p.clousEtriers) ...[
      const Text('Clous par étrier'),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final n in _clousParEtrierCourants)
            ChoiceChip(
              key: ValueKey('clous_choix_$n'),
              label: Text('$n'),
              selected: _p.clousParEtrier == n,
              onSelected: (_) => _set(_p.copieAvec(clousParEtrier: n)),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ChampNombre(
                key: const ValueKey('clous_par_etrier'),
                label: 'Par étrier',
                valeur: _p.clousParEtrier.toDouble(),
                min: 1,
                max: 40,
                decimales: 0,
                aide: 'LUS28 : 6 + 4',
                onChange: (v) => _set(_p.copieAvec(clousParEtrier: v.round())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChampNombre(
                key: const ValueKey('clous_par_boite'),
                label: 'Par boîte',
                valeur: _p.clousParBoite.toDouble(),
                min: 10,
                max: 5000,
                decimales: 0,
                aide: '1 lb de 10d × 1 1/2 po : environ 120',
                onChange: (v) => _set(_p.copieAvec(clousParBoite: v.round())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChampNombre(
                key: const ValueKey('clous_marge'),
                label: 'Marge',
                valeur: _p.margeClous,
                min: 0,
                max: 100,
                decimales: 0,
                suffixe: '%',
                onChange: (v) => _set(_p.copieAvec(margeClous: v)),
              ),
            ),
          ],
        ),
      ),
    ],
  ];

  List<Widget> _entremises() => [
    SwitchListTile(
      key: const ValueKey('entremises_auto'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Entremises automatiques'),
      subtitle: const Text(
        'Une rangée chaque fois que la portée dépasse la distance choisie',
      ),
      value: _p.entremisesAuto,
      onChanged: (v) => _set(_p.copieAvec(entremisesAuto: v)),
    ),
    if (_p.entremisesAuto) ...[
      const SizedBox(height: 4),
      ChampLongueur(
        key: const ValueKey('entremises_espacement'),
        label: 'Portée sans entremises',
        aide: 'Entre 7 et 10 pi',
        valeur: _p.entremisesEspacement,
        min: 24,
        max: 240,
        onChange: (v) => _set(_p.copieAvec(entremisesEspacement: v)),
      ),
    ] else ...[
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
    ],
    if (_p.entremisesAuto || _p.rangeesEntremises > 0)
      SwitchListTile(
        key: const ValueKey('entremises_alternees'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Pose alternée'),
        subtitle: const Text(
          'Blocs décalés d\'un côté puis de l\'autre, pour les clouer',
        ),
        value: _p.entremisesAlternees,
        onChanged: (v) => _set(_p.copieAvec(entremisesAlternees: v)),
      ),
  ];

  List<Widget> _poutres() {
    final po = _p.poutres;
    void maj(ParametresPoutres Function(ParametresPoutres) f) =>
        _set(_p.copieAvec(poutres: () => f(po!)));
    return [
      SwitchListTile(
        key: const ValueKey('poutres_actives'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Poutres sur pieux vissés'),
        subtitle: const Text(
          'Bois traité sur toute la largeur ; pieux et pattes en 6×6',
        ),
        value: po != null,
        onChanged: (v) => _set(
          _p.copieAvec(poutres: () => v ? const ParametresPoutres() : null),
        ),
      ),
      if (po != null) ...[
        const SizedBox(height: 4),
        const Text('Nombre de poutres'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          key: const ValueKey('poutres_nombre'),
          showSelectedIcon: false,
          segments: [
            for (final n in const [1, 2, 3, 4])
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {po.nombre.clamp(1, 4)},
          onSelectionChanged: (s) => maj((p) => p.copieAvec(nombre: s.first)),
        ),
        const SizedBox(height: 12),
        const Text('Épaisseurs par poutre (plis)'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          key: const ValueKey('poutres_plis'),
          showSelectedIcon: false,
          segments: [
            for (final n in const [2, 3, 4])
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {po.plis.clamp(2, 4)},
          onSelectionChanged: (s) => maj((p) => p.copieAvec(plis: s.first)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SectionBois>(
          key: ValueKey('poutres_section_${po.section.nom}'),
          initialValue: po.section,
          decoration: const InputDecoration(
            labelText: 'Section des planches de poutre (traité)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final s in sectionsPlancher)
              DropdownMenuItem(value: s, child: Text(s.nom)),
          ],
          onChanged: (s) =>
              s == null ? null : maj((p) => p.copieAvec(section: s)),
        ),
        const SizedBox(height: 12),
        const Text('Pieux vissés par poutre'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          key: const ValueKey('poutres_pieux'),
          showSelectedIcon: false,
          segments: [
            for (final n in const [2, 3, 4, 5, 6])
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {po.pieuxParPoutre.clamp(2, 6)},
          onSelectionChanged: (s) =>
              maj((p) => p.copieAvec(pieuxParPoutre: s.first)),
        ),
        const SizedBox(height: 12),
        ChampLongueur(
          key: const ValueKey('poutres_retrait'),
          label: 'Premier pieu à',
          aide: 'Du bord du plancher, d\'après le plan',
          valeur: po.retraitPieux,
          min: 0,
          max: 120,
          onChange: (v) => maj((p) => p.copieAvec(retraitPieux: v)),
        ),
        const SizedBox(height: 12),
        ChampLongueur(
          key: const ValueKey('poutres_patte'),
          label: 'Hauteur de la patte (6×6)',
          aide: '0 : pas de patte. Rehausse chaque pieu s\'il est trop bas.',
          valeur: po.hauteurPatte,
          min: 0,
          max: 120,
          onChange: (v) => maj((p) => p.copieAvec(hauteurPatte: v)),
        ),
      ],
    ];
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
  final ResultatTerrasse? terrasse;
  const _Resultats(this.r, this.projet, this.terrasse);

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
      if (r.boitesClousEtriers > 0)
        (
          'Clous d\'étriers',
          '${r.boitesClousEtriers} boîte${r.boitesClousEtriers > 1 ? 's' : ''} '
              '(${r.etriers * r.spec.clousParEtrier} clous, boîtes de ${r.spec.clousParBoite})',
        ),
      if (r.poutres != null) ...[
        (
          'Poutres',
          '${r.poutres!.spec.nombre} de ${r.poutres!.spec.plis} plis en '
              '${r.poutres!.spec.section}, ${formatLongueur(r.poutres!.longueur, metrique: metrique)} '
              '(${r.poutres!.planchesDePoutre} planches)',
        ),
        (
          'Pieux vissés',
          '${r.poutres!.nombrePieux} · entraxe '
              '${formatLongueur(r.poutres!.entraxePieux, metrique: metrique)} · '
              'premier à ${formatLongueur(r.poutres!.spec.retraitPieux, metrique: metrique)} du bord',
        ),
        if (r.poutres!.pattes != null)
          (
            'Pattes en 6×6',
            '${r.poutres!.nombrePieux} de '
                '${formatLongueur(r.poutres!.spec.hauteurPatte, metrique: metrique)}',
          ),
      ],
      (
        'Portée la plus longue',
        formatLongueur(r.porteeMax, metrique: metrique),
      ),
      if (terrasse case final t?) ...[
        (
          'Composite ${t.produit.nom}',
          '${t.cadre.length} planches de cadre, ${t.centre.length} planches au centre '
              '(${t.rangees} rangées)',
        ),
        (
          'Fascia',
          '${formatLongueur(t.fascias.fold(0.0, (a, f) => a + f.longueur), metrique: metrique)} '
              'de ${formatLongueur(t.hauteurFascia, metrique: metrique)}',
        ),
        (
          'Attaches ${t.produit.attache}',
          '${t.attaches} (${t.boitesAttaches} boîte${t.boitesAttaches > 1 ? 's' : ''})',
        ),
        if (t.blocs > 0)
          (
            'Blocage du cadre',
            '${t.blocs} blocs de ${formatLongueur(t.longueurBloc, metrique: metrique)} '
                'en ${projet.plancher.section.nom}',
          ),
      ] else
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
            if (r.poutres != null) ...[
              const SizedBox(height: 8),
              Text(
                'Poutres (${r.poutres!.spec.section} traité)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final e in r.poutres!.bois.parLongueur.entries)
                Text(
                  '${e.value} × ${formatPlanche(e.key, metrique: metrique)}',
                ),
              if (r.poutres!.pattes != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Pattes (6×6 traité)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final e in r.poutres!.pattes!.parLongueur.entries)
                  Text(
                    '${e.value} × ${formatPlanche(e.key, metrique: metrique)}',
                  ),
              ],
            ],
            BlocMessages([
              ...r.avertissements,
              ...?r.poutres?.avertissements.map((a) => 'Poutres : $a'),
              ...?terrasse?.avertissements,
            ]),
          ],
        ),
      ),
    );
  }
}
