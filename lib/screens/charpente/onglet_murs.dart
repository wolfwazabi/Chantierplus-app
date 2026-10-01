import 'package:flutter/material.dart';

import '../../charpente/mur.dart';
import '../../charpente/panneaux.dart';
import '../../charpente/plancher.dart' show SpecInvalide, espacementsStandards;
import '../../charpente/projet.dart';
import '../../charpente/unites.dart';
import '../../services/preferences.dart';
import 'champs.dart';
import 'vue_3d.dart';

/// Onglet « Murs » : murs du contour ou murs libres, ouvertures, matériaux.
class OngletMurs extends StatelessWidget {
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  final ValueChanged<ProjetCharpente> onChange;

  /// Un toucher sur l'aperçu ouvre la vue 3D.
  final VoidCallback? ouvrir3D;

  const OngletMurs({
    super.key,
    required this.projet,
    required this.resultats,
    required this.onChange,
    this.ouvrir3D,
  });

  ParametresMursProjet get _m => projet.murs;
  ParametresMurs get _p => projet.murs.params;
  bool get _metrique => Preferences.estMetrique;

  void _set(ParametresMursProjet m) => onChange(projet.copieAvec(murs: m));
  void _setParams(ParametresMurs p) => _set(_m.copieAvec(params: p));

  @override
  Widget build(BuildContext context) {
    final res = resultats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SwitchListTile(
          key: const ValueKey('murs_actifs'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Inclure des murs'),
          subtitle: const Text(
            'Montants, lisses, ouvertures, linteaux, feuilles, membrane, '
            'fourrures et revêtement',
          ),
          value: projet.mursActifs,
          onChanged: (v) => onChange(projet.copieAvec(mursActifs: v)),
        ),
        if (projet.mursActifs) ...[
          if (res.erreurMurs != null)
            BlocMessages([res.erreurMurs!], erreur: true),
          if (res.murs != null)
            Vue3D(
              key: const ValueKey('murs_apercu'),
              scene: res.scene,
              controles: false,
              interactif: false,
              onTap: ouvrir3D,
              hauteur: 240,
            ),
          const SizedBox(height: 12),
          SegmentedButton<ModeMurs>(
            key: const ValueKey('murs_mode'),
            segments: const [
              ButtonSegment(
                value: ModeMurs.contour,
                label: Text('Contour du plancher'),
                icon: Icon(Icons.crop_square),
              ),
              ButtonSegment(
                value: ModeMurs.libres,
                label: Text('Murs libres'),
                icon: Icon(Icons.horizontal_rule),
              ),
            ],
            selected: {_m.mode},
            onSelectionChanged: (s) => _set(_m.copieAvec(mode: s.first)),
          ),
          const SizedBox(height: 4),
          Text(
            _m.mode == ModeMurs.contour
                ? 'Un mur par côté de la forme du plancher ; aux coins d\'équerre, '
                      'un mur passe et l\'autre s\'y appuie.'
                : 'Murs indépendants (mur isolé, cloison) : ils s\'affichent côte à côte.',
            style: const TextStyle(fontSize: 12),
          ),
          const TitreSection('Ossature'),
          if (_m.mode == ModeMurs.contour)
            ChampLongueur(
              key: const ValueKey('murs_hauteur'),
              label: 'Hauteur des murs',
              aide:
                  'Du dessus du sous-plancher au dessus de la dernière lisse '
                  '(ex. 97 1/8" : 2 lisses hautes + montant de 92 5/8")',
              valeur: _m.hauteur,
              min: 24,
              max: 240,
              onChange: (v) => _set(_m.copieAvec(hauteur: v)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SectionBois>(
                  key: ValueKey('murs_section_${_p.section.nom}'),
                  initialValue: _p.section,
                  decoration: const InputDecoration(
                    labelText: 'Section des montants',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final s in sectionsMurs)
                      DropdownMenuItem(value: s, child: Text(s.nom)),
                  ],
                  onChanged: (s) =>
                      s == null ? null : _setParams(_p.copieAvec(section: s)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('lisses_${_p.lissesHautes}'),
                  initialValue: _p.lissesHautes,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lisses hautes',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 (simple)')),
                    DropdownMenuItem(value: 2, child: Text('2 (double)')),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : _setParams(_p.copieAvec(lissesHautes: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Entraxe des montants'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final e in espacementsStandards)
                ChoiceChip(
                  key: ValueKey('murs_entraxe_$e'),
                  label: Text(
                    '${formatNombre(e, decimales: 1)} po (${(e * 25.4).round()} mm)',
                  ),
                  selected: (_p.espacement - e).abs() < 1e-9,
                  onSelected: (_) => _setParams(_p.copieAvec(espacement: e)),
                ),
            ],
          ),
          SwitchListTile(
            key: const ValueKey('murs_precoupes'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Montants précoupés'),
            subtitle: const Text(
              '92 5/8, 104 5/8 ou 116 5/8 po : achetés tout coupés',
            ),
            value: _p.precoupes,
            onChanged: (v) => _setParams(_p.copieAvec(precoupes: v)),
          ),
          const TitreSection(
            'Feuilles des murs',
            aide: 'Posées à la verticale, joints sur le centre des montants.',
          ),
          DropdownButtonFormField<FormatPanneau>(
            key: ValueKey('murs_format_${_p.panneau.id}'),
            initialValue: _p.panneau,
            decoration: const InputDecoration(
              labelText: 'Format des feuilles',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            isExpanded: true,
            items: [
              for (final f in formatsPanneaux)
                DropdownMenuItem(
                  value: f,
                  child: Text(f.nom, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (f) =>
                f == null ? null : _setParams(_p.copieAvec(panneau: f)),
          ),
          if (_p.panneau.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _p.panneau.note!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const TitreSection('Ouvertures et linteaux'),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SectionBois>(
                  key: ValueKey('linteau_${_p.linteau.nom}'),
                  initialValue: _p.linteau,
                  decoration: const InputDecoration(
                    labelText: 'Section du linteau',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final s in sectionsLinteaux)
                      DropdownMenuItem(value: s, child: Text(s.nom)),
                  ],
                  onChanged: (s) =>
                      s == null ? null : _setParams(_p.copieAvec(linteau: s)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('plis_${_p.plisLinteau}'),
                  initialValue: _p.plisLinteau,
                  decoration: const InputDecoration(
                    labelText: 'Épaisseurs',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (var i = 1; i <= 3; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) => v == null
                      ? null
                      : _setParams(_p.copieAvec(plisLinteau: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Le dimensionnement du linteau n\'est pas vérifié par l\'application : '
            'choisissez-le selon les tables du Code ou un ingénieur.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Text('Montants de linteau (jacks) de chaque côté'),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            key: const ValueKey('jacks'),
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {_p.jacksParCote},
            onSelectionChanged: (s) =>
                _setParams(_p.copieAvec(jacksParCote: s.first)),
          ),
          const TitreSection('Murs'),
          if (_m.mode == ModeMurs.contour)
            ..._mursDuContour(context)
          else
            ..._mursLibres(context),
          _avancees(context),
          if (res.murs != null) ...[
            const TitreSection('Résultats'),
            _ResultatsMurs(res.murs!, _p),
          ],
        ],
      ],
    );
  }

  // --- Murs du contour --------------------------------------------------------

  List<Widget> _mursDuContour(BuildContext context) {
    if (resultats.contour == null) {
      return [
        const Text(
          'Entrez d\'abord une forme de plancher valide (onglet Plancher).',
        ),
      ];
    }
    List<SpecMur> specs;
    try {
      specs = specsMurs(projet, resultats.contour);
    } on SpecInvalide {
      return const [];
    }
    return [
      for (final s in specs)
        _CarteMur(
          cle: 'mur_${s.cote}',
          titre:
              '${s.nom} — ${formatLongueur(s.longueur, metrique: _metrique)}',
          sousTitre: _sousTitre(s, _m.ouverturesContour[s.cote] ?? const []),
          mur: s,
          ouvertures: _m.ouverturesContour[s.cote] ?? const [],
          onOuvertures: (l) => _set(
            _m.copieAvec(
              ouverturesContour: {..._m.ouverturesContour, s.cote!: l},
            ),
          ),
          editeurMur: null,
        ),
    ];
  }

  String _sousTitre(SpecMur s, List<Ouverture> o) => o.isEmpty
      ? 'Aucune ouverture'
      : '${o.length} ouverture${o.length > 1 ? 's' : ''}';

  // --- Murs libres ------------------------------------------------------------

  List<Widget> _mursLibres(BuildContext context) {
    final libres = _m.libres;
    return [
      for (var i = 0; i < libres.length; i++)
        _CarteMur(
          cle: 'libre_$i',
          titre:
              '${libres[i].nom} — ${formatLongueur(libres[i].longueur, metrique: _metrique)}',
          sousTitre: _sousTitre(libres[i], libres[i].ouvertures),
          mur: libres[i],
          ouvertures: libres[i].ouvertures,
          onOuvertures: (l) => _set(
            _m.copieAvec(
              libres: [...libres]..[i] = _avecOuvertures(libres[i], l),
            ),
          ),
          editeurMur: _EditeurMurLibre(
            mur: libres[i],
            onChange: (m) => _set(_m.copieAvec(libres: [...libres]..[i] = m)),
            onSupprimer: () =>
                _set(_m.copieAvec(libres: [...libres]..removeAt(i))),
          ),
        ),
      OutlinedButton.icon(
        key: const ValueKey('ajouter_mur'),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un mur'),
        onPressed: libres.length >= 40
            ? null
            : () => _set(
                _m.copieAvec(
                  libres: [
                    ...libres,
                    SpecMur(
                      nom: 'Mur ${libres.length + 1}',
                      longueur: 192,
                      hauteur: _m.hauteur,
                    ),
                  ],
                ),
              ),
      ),
    ];
  }

  SpecMur _avecOuvertures(SpecMur m, List<Ouverture> o) => SpecMur(
    nom: m.nom,
    longueur: m.longueur,
    hauteur: m.hauteur,
    ouvertures: o,
    montantsCoinDebut: m.montantsCoinDebut,
    montantsCoinFin: m.montantsCoinFin,
    intersections: m.intersections,
  );

  // --- Options avancées -------------------------------------------------------

  Widget _avancees(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('murs_avancees'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Options avancées'),
      subtitle: const Text('Fourrures, revêtement, membrane, marges d\'achat'),
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChampNombre(
                label: 'Entraxe des fourrures',
                valeur: _p.fourrureEntraxe,
                min: 6,
                max: 48,
                decimales: 1,
                suffixe: 'po',
                onChange: (v) => _setParams(_p.copieAvec(fourrureEntraxe: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChampLongueur(
                label: 'Épaisseur du revêtement',
                valeur: _p.revetementEpaisseur,
                min: 0.1,
                max: 6,
                aide: ' ',
                onChange: (v) =>
                    _setParams(_p.copieAvec(revetementEpaisseur: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChampLongueur(
                label: 'Fourrure : épaisseur',
                valeur: _p.fourrureEpaisseur,
                min: 0.25,
                max: 3,
                aide: ' ',
                onChange: (v) => _setParams(_p.copieAvec(fourrureEpaisseur: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChampLongueur(
                label: 'Fourrure : largeur',
                valeur: _p.fourrureLargeur,
                min: 1,
                max: 6,
                aide: ' ',
                onChange: (v) => _setParams(_p.copieAvec(fourrureLargeur: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ChampLongueur(
          label: 'Feuilles : débord sous le mur',
          valeur: _p.debordPlancher,
          min: 0,
          max: 24,
          aide: 'Les feuilles, la membrane et le revêtement descendent sur la rive du plancher',
          onChange: (v) => _setParams(_p.copieAvec(debordPlancher: v)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChampNombre(
                label: 'Marge feuilles',
                valeur: _p.margeFeuillesPct,
                min: 0,
                max: 50,
                decimales: 0,
                suffixe: '%',
                onChange: (v) => _setParams(_p.copieAvec(margeFeuillesPct: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChampNombre(
                label: 'Marge membrane',
                valeur: _p.margeMembranePct,
                min: 0,
                max: 50,
                decimales: 0,
                suffixe: '%',
                onChange: (v) => _setParams(_p.copieAvec(margeMembranePct: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChampNombre(
                label: 'Marge revêtement',
                valeur: _p.margeRevetementPct,
                min: 0,
                max: 50,
                decimales: 0,
                suffixe: '%',
                onChange: (v) =>
                    _setParams(_p.copieAvec(margeRevetementPct: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// =============================================================================
// Un mur : ouvertures
// =============================================================================

class _CarteMur extends StatelessWidget {
  final String cle;
  final String titre;
  final String sousTitre;
  final SpecMur mur;
  final List<Ouverture> ouvertures;
  final ValueChanged<List<Ouverture>> onOuvertures;

  /// Réglages propres à un mur libre (nom, longueur, hauteur, coins).
  final Widget? editeurMur;

  const _CarteMur({
    required this.cle,
    required this.titre,
    required this.sousTitre,
    required this.mur,
    required this.ouvertures,
    required this.onOuvertures,
    required this.editeurMur,
  });

  Future<void> _editer(
    BuildContext context, {
    int? indice,
    TypeOuverture? type,
  }) async {
    final r = await showModalBottomSheet<Ouverture>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditeurOuverture(
          initiale: indice == null ? null : ouvertures[indice],
          type: type ?? ouvertures[indice!].type,
          longueurMur: mur.longueur,
          hauteurMur: mur.hauteur,
        ),
      ),
    );
    if (r == null) {
      return;
    }
    final l = [...ouvertures];
    if (indice == null) {
      l.add(r);
    } else {
      l[indice] = r;
    }
    onOuvertures(l);
  }

  @override
  Widget build(BuildContext context) {
    final metrique = Preferences.estMetrique;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey('carte_$cle'),
        title: Text(titre),
        subtitle: Text(sousTitre),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          ?editeurMur,
          for (var i = 0; i < ouvertures.length; i++)
            ListTile(
              key: ValueKey('${cle}_ouverture_$i'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                ouvertures[i].type == TypeOuverture.porte
                    ? Icons.door_front_door_outlined
                    : Icons.window_outlined,
              ),
              title: Text(
                '${ouvertures[i].libelle} '
                '${formatLongueur(ouvertures[i].largeurCadre, metrique: metrique)} × '
                '${formatLongueur(ouvertures[i].hauteurCadre, metrique: metrique)}',
              ),
              subtitle: Text(
                'Centre à ${formatLongueur(ouvertures[i].position, metrique: metrique)} du début'
                '${ouvertures[i].type == TypeOuverture.fenetre ? ', allège ${formatLongueur(ouvertures[i].allege, metrique: metrique)}' : ''}'
                '\nBaie : ${formatLongueur(ouvertures[i].largeurBaie, metrique: metrique)} × '
                '${formatLongueur(ouvertures[i].hauteurBaie, metrique: metrique)}',
              ),
              isThreeLine: true,
              onTap: () => _editer(context, indice: i),
              trailing: IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onOuvertures([...ouvertures]..removeAt(i)),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('${cle}_ajouter_porte'),
                icon: const Icon(Icons.door_front_door_outlined),
                label: const Text('Porte'),
                onPressed: ouvertures.length >= 30
                    ? null
                    : () => _editer(context, type: TypeOuverture.porte),
              ),
              OutlinedButton.icon(
                key: ValueKey('${cle}_ajouter_fenetre'),
                icon: const Icon(Icons.window_outlined),
                label: const Text('Fenêtre'),
                onPressed: ouvertures.length >= 30
                    ? null
                    : () => _editer(context, type: TypeOuverture.fenetre),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditeurMurLibre extends StatelessWidget {
  final SpecMur mur;
  final ValueChanged<SpecMur> onChange;
  final VoidCallback onSupprimer;
  const _EditeurMurLibre({
    required this.mur,
    required this.onChange,
    required this.onSupprimer,
  });

  SpecMur _avec({
    String? nom,
    double? longueur,
    double? hauteur,
    int? coinDebut,
    int? coinFin,
    List<double>? intersections,
  }) => SpecMur(
    nom: nom ?? mur.nom,
    longueur: longueur ?? mur.longueur,
    hauteur: hauteur ?? mur.hauteur,
    ouvertures: mur.ouvertures,
    montantsCoinDebut: coinDebut ?? mur.montantsCoinDebut,
    montantsCoinFin: coinFin ?? mur.montantsCoinFin,
    intersections: intersections ?? mur.intersections,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: mur.nom,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Nom du mur',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
          onChanged: (v) =>
              onChange(_avec(nom: v.trim().isEmpty ? 'Mur' : v.trim())),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChampLongueur(
                label: 'Longueur',
                valeur: mur.longueur,
                min: 6,
                max: 1200,
                onChange: (v) => onChange(_avec(longueur: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChampLongueur(
                label: 'Hauteur',
                valeur: mur.hauteur,
                min: 24,
                max: 240,
                onChange: (v) => onChange(_avec(hauteur: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Coins(
                label: 'Montants de coin au début',
                valeur: mur.montantsCoinDebut,
                onChange: (v) => onChange(_avec(coinDebut: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Coins(
                label: 'Montants de coin à la fin',
                valeur: mur.montantsCoinFin,
                onChange: (v) => onChange(_avec(coinFin: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ChampTexteListe(
          label: 'Cloisons en T (positions de leur axe)',
          valeurs: mur.intersections,
          onChange: (l) => onChange(_avec(intersections: l)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer ce mur'),
            onPressed: onSupprimer,
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class _Coins extends StatelessWidget {
  final String label;
  final int valeur;
  final ValueChanged<int> onChange;
  const _Coins({
    required this.label,
    required this.valeur,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('0')),
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
          ],
          selected: {valeur},
          onSelectionChanged: (s) => onChange(s.first),
        ),
      ],
    );
  }
}

/// Liste de longueurs séparées par des virgules ou des points-virgules.
class ChampTexteListe extends StatefulWidget {
  final String label;
  final List<double> valeurs;
  final ValueChanged<List<double>> onChange;
  const ChampTexteListe({
    super.key,
    required this.label,
    required this.valeurs,
    required this.onChange,
  });

  @override
  State<ChampTexteListe> createState() => _ChampTexteListeState();
}

class _ChampTexteListeState extends State<ChampTexteListe> {
  late final TextEditingController _ctrl;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.valeurs
          .map((v) => formatLongueur(v, metrique: Preferences.estMetrique))
          .join('; '),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _modifie(String t) {
    final morceaux = t
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final valeurs = <double>[];
    try {
      for (final m in morceaux) {
        valeurs.add(lireLongueur(m, metrique: Preferences.estMetrique));
      }
    } on MesureInvalide catch (e) {
      setState(() => _erreur = e.message);
      return;
    }
    if (valeurs.length > 10) {
      setState(() => _erreur = '10 cloisons au plus.');
      return;
    }
    setState(() => _erreur = null);
    widget.onChange(valeurs);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: 'Séparées par « ; » (ex. : 8\'; 12\'6"). Deux montants d\'appui chacune.',
        helperMaxLines: 2,
        errorText: _erreur,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: _modifie,
    );
  }
}

// =============================================================================
// Éditeur d'une ouverture
// =============================================================================

class _Modele {
  final String nom;
  final double largeur;
  final double hauteur;
  const _Modele(this.nom, this.largeur, this.hauteur);
}

const _portes = [
  _Modele('30 × 80 po', 30, 80),
  _Modele('32 × 80 po', 32, 80),
  _Modele('36 × 80 po', 36, 80),
  _Modele('Double 60 × 80 po', 60, 80),
];
const _fenetres = [
  _Modele('24 × 36 po', 24, 36),
  _Modele('36 × 48 po', 36, 48),
  _Modele('48 × 48 po', 48, 48),
  _Modele('60 × 48 po', 60, 48),
  _Modele('72 × 60 po', 72, 60),
];

class _EditeurOuverture extends StatefulWidget {
  final Ouverture? initiale;
  final TypeOuverture type;
  final double longueurMur;
  final double hauteurMur;
  const _EditeurOuverture({
    required this.initiale,
    required this.type,
    required this.longueurMur,
    required this.hauteurMur,
  });

  @override
  State<_EditeurOuverture> createState() => _EditeurOuvertureState();
}

class _EditeurOuvertureState extends State<_EditeurOuverture> {
  late String _nom;
  late double _largeur;
  late double _hauteur;
  late double _allege;
  late double _position;
  late double _jeuL;
  late double _jeuH;
  int _version = 0;

  bool get _porte => widget.type == TypeOuverture.porte;

  @override
  void initState() {
    super.initState();
    final o = widget.initiale;
    _nom = o?.nom ?? '';
    _largeur = o?.largeurCadre ?? (_porte ? 36 : 36);
    _hauteur = o?.hauteurCadre ?? (_porte ? 80 : 48);
    _allege = o?.allege ?? 36;
    _position = o?.position ?? widget.longueurMur / 2;
    _jeuL = o?.jeuLargeur ?? JeuxBaie.largeurDefaut;
    _jeuH = o?.jeuHauteur ?? JeuxBaie.hauteurDefaut;
  }

  Ouverture get _ouverture => Ouverture(
    type: widget.type,
    nom: _nom,
    largeurCadre: _largeur,
    hauteurCadre: _hauteur,
    allege: _porte ? 0 : _allege,
    position: _position,
    jeuLargeur: _jeuL,
    jeuHauteur: _jeuH,
  );

  @override
  Widget build(BuildContext context) {
    final metrique = Preferences.estMetrique;
    final o = _ouverture;
    final avertissements = <String>[
      if (_jeuL < JeuxBaie.largeurMin - 1e-6 ||
          _jeuL > JeuxBaie.largeurMax + 1e-6)
        'Jeu en largeur hors de la plage de la fiche GCR (1/2" à 1 1/2").',
      if (_jeuH < JeuxBaie.hauteurMin - 1e-6 ||
          _jeuH > JeuxBaie.hauteurMax + 1e-6)
        'Jeu en hauteur hors de la plage de la fiche GCR (1" à 1 3/4").',
      if (o.baieG < 0 || o.baieD > widget.longueurMur)
        'L\'ouverture dépasse le mur (${formatLongueur(widget.longueurMur, metrique: metrique)}).',
      if (o.baieHaut > widget.hauteurMur)
        'L\'ouverture dépasse la hauteur du mur.',
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initiale == null
                  ? (_porte ? 'Nouvelle porte' : 'Nouvelle fenêtre')
                  : (_porte ? 'Modifier la porte' : 'Modifier la fenêtre'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in (_porte ? _portes : _fenetres))
                  ActionChip(
                    label: Text(m.nom),
                    onPressed: () => setState(() {
                      _largeur = m.largeur;
                      _hauteur = m.hauteur;
                      _version++;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChampLongueur(
                    key: ValueKey('larg_$_version'),
                    label: 'Largeur du cadre',
                    valeur: _largeur,
                    aide: 'Dormant, sans le jeu',
                    onChange: (v) => setState(() => _largeur = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChampLongueur(
                    key: ValueKey('haut_$_version'),
                    label: 'Hauteur du cadre',
                    valeur: _hauteur,
                    aide: 'Dormant, sans le jeu',
                    onChange: (v) => setState(() => _hauteur = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!_porte) ...[
                  Expanded(
                    child: ChampLongueur(
                      label: 'Allège',
                      valeur: _allege,
                      min: 0,
                      max: 240,
                      aide: 'Plancher au bas du cadre',
                      onChange: (v) => setState(() => _allege = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ChampLongueur(
                    key: ValueKey('pos_$_version'),
                    label: 'Position du centre',
                    valeur: _position,
                    min: 0,
                    aide:
                        'Du début de l\'ossature du mur (${formatLongueur(widget.longueurMur, metrique: metrique)} au total)',
                    onChange: (v) => setState(() => _position = v),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _position = widget.longueurMur / 2;
                  _version++;
                }),
                child: const Text('Centrer sur le mur'),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ChampLongueur(
                    label: 'Jeu en largeur (total)',
                    valeur: _jeuL,
                    min: 0,
                    max: 6,
                    aide: 'GCR : 1/2" à 1 1/2"',
                    onChange: (v) => setState(() => _jeuL = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChampLongueur(
                    label: 'Jeu en hauteur (total)',
                    valeur: _jeuH,
                    min: 0,
                    max: 6,
                    aide: 'GCR : 1" à 1 3/4"',
                    onChange: (v) => setState(() => _jeuH = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Baie (ouverture brute) : '
                '${formatLongueur(o.largeurBaie, metrique: metrique)} × '
                '${formatLongueur(o.hauteurBaie, metrique: metrique)}\n'
                'De ${formatLongueur(o.baieBas, metrique: metrique)} à '
                '${formatLongueur(o.baieHaut, metrique: metrique)} du plancher.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            BlocMessages(avertissements),
            const SizedBox(height: 8),
            Text(
              'Source des jeux : fiche technique GCR FT-9.7.6.1 (norme '
              'CAN/CSA-A440.4) : la baie dépasse le dormant de 1/2" à 1 1/2" en '
              'largeur et de 1" à 1 3/4" en hauteur.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('ouverture_ok'),
                  onPressed: () => Navigator.pop(context, _ouverture),
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Résultats
// =============================================================================

class _ResultatsMurs extends StatelessWidget {
  final ResultatMurs r;
  final ParametresMurs p;
  const _ResultatsMurs(this.r, this.p);

  @override
  Widget build(BuildContext context) {
    final metrique = Preferences.estMetrique;
    final ossature =
        r.compter(TypeMembre.montant) +
        r.compter(TypeMembre.montantCoin) +
        r.compter(TypeMembre.roi);
    Widget titre(String t) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.murs.length} mur${r.murs.length > 1 ? 's' : ''} : '
              '$ossature montants, ${r.compter(TypeMembre.jack)} montants de linteau, '
              '${r.compter(TypeMembre.linteau)} pièces de linteau',
            ),
            titre('Bois (${p.section.nom})'),
            for (final e in r.precoupes.entries)
              Text(
                '${e.value} × ${p.section.nom} précoupé ${formatImperial(e.key)}',
              ),
            for (final e in r.boisOssature.parLongueur.entries)
              Text('${e.value} × ${formatPlanche(e.key, metrique: metrique)}'),
            if (r.boisLinteaux.planches.isNotEmpty) ...[
              titre('Linteaux (${p.linteau.nom})'),
              for (final e in r.boisLinteaux.parLongueur.entries)
                Text(
                  '${e.value} × ${formatPlanche(e.key, metrique: metrique)}',
                ),
            ],
            titre('Feuilles'),
            Text(
              '${r.feuillesACommander} × ${p.panneau.nom} '
              '(${r.feuillesUtilisees} utilisées)',
            ),
            titre('Fourrures'),
            for (final e in r.fourrures.parLongueur.entries)
              Text('${e.value} × ${formatPlanche(e.key, metrique: metrique)}'),
            titre('Membrane et revêtement'),
            Text(
              '${r.rouleauxMembrane} rouleau${r.rouleauxMembrane > 1 ? 'x' : ''} de membrane '
              '(${formatNombre(r.aireMembranePi2, decimales: 0)} pi² avec marge)',
            ),
            Text(
              'Revêtement : ${formatNombre(r.aireRevetementPi2, decimales: 0)} pi² '
              '(${formatNombre(r.aireRevetementPi2 * 0.09290304, decimales: 1)} m²)',
            ),
            BlocMessages(r.avertissements),
          ],
        ),
      ),
    );
  }
}
