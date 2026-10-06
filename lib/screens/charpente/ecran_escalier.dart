import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../charpente/escalier.dart';
import '../../charpente/escalier_texte.dart';
import '../../charpente/unites.dart';
import '../../services/preferences.dart';
import 'champs.dart';
import 'schema_limon.dart';

/// Calcul des limons d'un escalier droit : nombre et hauteur des contremarches,
/// giron, longueur et coupes des limons, table de traçage, vérification des
/// dimensions du Code (CNB 2015, section 9.8) et liste de matériaux.
class EcranEscalier extends StatefulWidget {
  const EcranEscalier({super.key});

  @override
  State<EcranEscalier> createState() => _EcranEscalierState();
}

class _EcranEscalierState extends State<EcranEscalier> {
  double _hauteur = 108; // 9 pi
  double _largeur = 36;
  UsageEscalier _usage = UsageEscalier.prive;
  ModeCourse _mode = ModeCourse.gironFixe;
  double _giron = 10.25;
  double _course = 144;
  double _souhaitee = 7.25;
  bool _nombreImpose = false;
  int _nombre = 15;
  double _epaisseurMarche = 1.5;
  double _nez = 0.75;
  bool _fermees = false;
  double _epaisseurContremarche = 0.75;
  SectionLimon _section = SectionLimon.s2x12;
  double _entraxe = 16;

  SpecEscalier _spec(bool metrique) => SpecEscalier(
    hauteurTotale: _hauteur,
    largeur: _largeur,
    usage: _usage,
    mode: _mode,
    giron: _giron,
    courseDisponible: _course,
    contremarcheSouhaitee: _souhaitee,
    nombreContremarches: _nombreImpose ? _nombre : null,
    epaisseurMarche: _epaisseurMarche,
    nez: _nez,
    contremarchesFermees: _fermees,
    epaisseurContremarche: _epaisseurContremarche,
    section: _section,
    espacementMax: _entraxe,
    // Traçage au 1/16 po ou au millimètre, selon le système d'unités.
    precisionTrace: metrique ? 1 / mmParPouce : 1 / 16,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SystemeUnites>(
      valueListenable: Preferences.unites,
      builder: (context, _, _) {
        final metrique = Preferences.estMetrique;
        ResultatEscalier? res;
        String? erreur;
        try {
          res = calculerEscalier(_spec(metrique), metrique: metrique);
        } on EscalierInvalide catch (e) {
          erreur = e.message;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            ..._formulaire(),
            if (erreur != null)
              BlocMessages([erreur], erreur: true, key: const ValueKey('escalier_erreur'))
            else if (res != null)
              ..._resultats(res, metrique),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- Formulaire

  List<Widget> _formulaire() {
    const espace = SizedBox(height: 12);
    return [
      const TitreSection(
        'Dimensions',
        aide: 'Du plancher fini du bas au plancher fini du haut.',
      ),
      ChampLongueur(
        key: const ValueKey('escalier_hauteur'),
        label: 'Hauteur totale',
        valeur: _hauteur,
        min: 4,
        max: 400,
        onChange: (v) => setState(() => _hauteur = v),
      ),
      espace,
      ChampLongueur(
        key: const ValueKey('escalier_largeur'),
        label: 'Largeur libre de l\'escalier',
        valeur: _largeur,
        min: 12,
        max: 240,
        onChange: (v) => setState(() => _largeur = v),
      ),
      espace,
      SegmentedButton<UsageEscalier>(
        key: const ValueKey('escalier_usage'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: UsageEscalier.prive, label: Text('Privé (logement)')),
          ButtonSegment(value: UsageEscalier.commun, label: Text('Commun')),
        ],
        selected: {_usage},
        onSelectionChanged: (s) => setState(() => _usage = s.first),
      ),
      const TitreSection('Marches'),
      SegmentedButton<ModeCourse>(
        key: const ValueKey('escalier_mode'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: ModeCourse.gironFixe, label: Text('Giron voulu')),
          ButtonSegment(
            value: ModeCourse.courseDisponible,
            label: Text('Course disponible'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      espace,
      if (_mode == ModeCourse.gironFixe)
        ChampLongueur(
          key: const ValueKey('escalier_giron'),
          label: 'Giron (nez à nez)',
          valeur: _giron,
          min: 4,
          max: 24,
          onChange: (v) => setState(() => _giron = v),
        )
      else
        ChampLongueur(
          key: const ValueKey('escalier_course'),
          label: 'Course horizontale disponible',
          aide:
              'De la face de la 1re contremarche à la face du plancher du haut.',
          valeur: _course,
          min: 4,
          max: 1200,
          onChange: (v) => setState(() => _course = v),
        ),
      espace,
      ChampLongueur(
        key: const ValueKey('escalier_souhaitee'),
        label: 'Contremarche visée',
        aide: 'Sert à choisir le nombre de contremarches.',
        valeur: _souhaitee,
        min: 3,
        max: 12,
        onChange: (v) => setState(() => _souhaitee = v),
      ),
      SwitchListTile(
        key: const ValueKey('escalier_nombre_impose'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Choisir le nombre de contremarches'),
        subtitle: const Text('Sinon, le calcul le choisit.'),
        value: _nombreImpose,
        onChanged: (v) => setState(() => _nombreImpose = v),
      ),
      if (_nombreImpose)
        ChampNombre(
          key: const ValueKey('escalier_nombre'),
          label: 'Nombre de contremarches',
          valeur: _nombre.toDouble(),
          min: 2,
          max: 100,
          decimales: 0,
          onChange: (v) => setState(() => _nombre = v.round()),
        ),
      espace,
      ChampLongueur(
        key: const ValueKey('escalier_ep_marche'),
        label: 'Épaisseur de la marche',
        valeur: _epaisseurMarche,
        min: 0.25,
        max: 4,
        onChange: (v) => setState(() => _epaisseurMarche = v),
      ),
      espace,
      ChampLongueur(
        key: const ValueKey('escalier_nez'),
        label: 'Nez de marche (saillie)',
        aide: 'Le Code limite la saillie à 25 mm.',
        valeur: _nez,
        min: 0,
        max: 4,
        onChange: (v) => setState(() => _nez = v),
      ),
      SwitchListTile(
        key: const ValueKey('escalier_fermees'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Contremarches fermées'),
        value: _fermees,
        onChanged: (v) => setState(() => _fermees = v),
      ),
      if (_fermees)
        ChampLongueur(
          key: const ValueKey('escalier_ep_contre'),
          label: 'Épaisseur de la contremarche',
          valeur: _epaisseurContremarche,
          min: 0.25,
          max: 2,
          onChange: (v) => setState(() => _epaisseurContremarche = v),
        ),
      const TitreSection('Limons'),
      SegmentedButton<SectionLimon>(
        key: const ValueKey('escalier_section'),
        showSelectedIcon: false,
        segments: [
          for (final s in SectionLimon.values)
            ButtonSegment(value: s, label: Text(s.nom)),
        ],
        selected: {_section},
        onSelectionChanged: (s) => setState(() => _section = s.first),
      ),
      espace,
      ChampLongueur(
        key: const ValueKey('escalier_entraxe'),
        label: 'Entraxe maximal des limons',
        aide: '16 po pour des marches en 2 po d\'épaisseur.',
        valeur: _entraxe,
        min: 6,
        max: 48,
        onChange: (v) => setState(() => _entraxe = v),
      ),
    ];
  }

  // ------------------------------------------------------------------ Résultats

  List<Widget> _resultats(ResultatEscalier r, bool metrique) {
    String l(double po) => formatLongueur(po, metrique: metrique);
    String mm(double po) => '${formatNombre(poucesEnMm(po), decimales: 1)} mm';
    final s = r.spec;
    return [
      BlocMessages(
        [for (final v in r.erreurs) v.message],
        erreur: true,
        key: const ValueKey('escalier_erreurs'),
      ),
      BlocMessages(
        [for (final v in r.avertissements) v.message],
        key: const ValueKey('escalier_avertissements'),
      ),
      const TitreSection('Escalier'),
      _Carte(
        cle: 'escalier_resume',
        lignes: [
          _Ligne(
            '${r.nombreContremarches} contremarches',
            '${l(r.contremarche)}  (${mm(r.contremarche)})',
            fort: true,
          ),
          _Ligne(
            '${r.nombreMarches} marches',
            'giron ${l(r.giron)}  (${mm(r.giron)})',
            fort: true,
          ),
          _Ligne('Profondeur de la marche', '${l(r.profondeurMarche)}  (giron + nez)'),
          _Ligne('Course horizontale', l(r.course)),
          _Ligne('Pente', formatAngle(r.angle)),
        ],
      ),
      if (r.variantes.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Autres choix conformes', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final v in r.variantes)
              ActionChip(
                key: ValueKey('escalier_variante_${v.nombreContremarches}'),
                label: Text(
                  '${v.nombreContremarches} × ${l(v.contremarche)}, '
                  'giron ${l(v.giron)}',
                ),
                onPressed: () => setState(() {
                  _nombreImpose = true;
                  _nombre = v.nombreContremarches;
                }),
              ),
          ],
        ),
      ],
      const TitreSection('Limons'),
      _Carte(
        cle: 'escalier_limons',
        lignes: [
          _Ligne(
            '${r.nombreLimons} limons en ${s.section.nom}',
            'planche de ${formatPlanche(r.longueurCommerciale, metrique: metrique)}',
            fort: true,
          ),
          _Ligne('Longueur de coupe', l(r.longueurLimon)),
          _Ligne('Entraxe', l(r.espacementReel)),
          _Ligne('Gorge sous les entailles', l(r.gorge)),
        ],
      ),
      const SizedBox(height: 8),
      SchemaLimon(resultat: r, metrique: metrique),
      const TitreSection(
        'Coupes',
        aide: 'Repère : plancher fini du bas, face de la 1re contremarche.',
      ),
      _Carte(
        cle: 'escalier_coupes',
        lignes: [
          _Ligne('Pied', 'coupe de niveau de ${l(r.coupePied)} sur le plancher'),
          _Ligne(
            'Coupe d\'aplomb du bas',
            '${l(r.hauteurDepart)} de haut  (contremarche − épaisseur de la marche)',
          ),
          _Ligne('Tête', 'coupe d\'aplomb de ${l(r.coupeTete)} contre la poutre du haut'),
          _Ligne('Pointe du haut', '${l(r.hauteurPointeHaute)} au-dessus du plancher du bas'),
          _Ligne(
            'Angles (depuis la coupe d\'équerre)',
            'aplomb ${formatAngle(r.anglePlomb)} · niveau ${formatAngle(r.angleNiveau)}',
          ),
        ],
      ),
      ExpansionTile(
        key: const ValueKey('escalier_trace'),
        tilePadding: EdgeInsets.zero,
        title: const Text('Table de traçage'),
        subtitle: Text(
          'Mesures depuis le plancher du bas, arrondies à '
          '${metrique ? '1 mm' : '1/16 po'}, sans cumul d\'erreur.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          Table(
            columnWidths: const {0: FixedColumnWidth(54)},
            children: [
              TableRow(
                children: [
                  for (final t in const ['Marche', 'Dessus', 'Siège du limon', 'Course'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                ],
              ),
              for (final t in r.table)
                TableRow(
                  children: [
                    for (final c in [
                      '${t.marche}',
                      l(r.arrondi(t.hauteurDessus)),
                      l(r.arrondi(t.hauteurSiege)),
                      l(r.arrondi(t.course)),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(c, style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
      const TitreSection('Matériaux'),
      _Carte(
        cle: 'escalier_materiaux',
        lignes: [
          for (final m in materielEscalier(r, metrique: metrique))
            _Ligne('${m.quantite} × ${m.article}', m.detail),
        ],
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('escalier_copier'),
          icon: const Icon(Icons.copy),
          label: const Text('Copier le calcul'),
          onPressed: () async {
            final messager = ScaffoldMessenger.of(context);
            await Clipboard.setData(
              ClipboardData(text: texteEscalier(r, metrique: metrique)),
            );
            messager.showSnackBar(const SnackBar(content: Text('Calcul copié.')));
          },
        ),
      ),
      const TitreSection(
        'Vérification du Code',
        aide: 'CNB 2015, section 9.8, tel qu\'adopté au Québec.',
      ),
      Column(
        key: const ValueKey('escalier_verifications'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final v in r.verifications) _LigneVerification(v)],
      ),
      const SizedBox(height: 12),
      Text(
        'Ce calcul vérifie les dimensions de l\'escalier. Il ne remplace pas la '
        'validation de l\'inspecteur, de la Garantie de construction résidentielle '
        'ou d\'un ingénieur (portées, fixation, garde-corps, mains courantes).',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

class _Ligne {
  final String titre;
  final String valeur;
  final bool fort;
  const _Ligne(this.titre, this.valeur, {this.fort = false});
}

class _Carte extends StatelessWidget {
  final String cle;
  final List<_Ligne> lignes;
  const _Carte({required this.cle, required this.lignes});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey(cle),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: l.titre,
                        style: TextStyle(
                          fontWeight: l.fort ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      TextSpan(text: '  ${l.valeur}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LigneVerification extends StatelessWidget {
  final Verification v;
  const _LigneVerification(this.v);

  @override
  Widget build(BuildContext context) {
    final (icone, couleur) = switch (v.niveau) {
      Niveau.ok => (Icons.check_circle, Colors.green),
      Niveau.info => (Icons.info_outline, Colors.blueGrey),
      Niveau.avertissement => (Icons.warning_amber, Colors.orange),
      Niveau.erreur => (Icons.cancel, Colors.red),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v.reference == null ? v.message : '${v.message} (${v.reference})',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
