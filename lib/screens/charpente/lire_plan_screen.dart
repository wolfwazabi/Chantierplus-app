import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../charpente/commande.dart';
import '../../charpente/lecture_plan.dart';
import '../../charpente/mur.dart';
import '../../charpente/projet.dart';
import '../../charpente/unites.dart';
import '../../services/fonctions.dart';
import '../../services/preferences.dart';
import '../../services/selecteur_plans.dart';
import 'champs.dart';
import 'vue_3d.dart';

/// Appel du serveur : plans joints et précisions → réponse brute de `lirePlanCharpente`.
typedef AppelLecturePlan = Future<Map<String, dynamic>> Function(
  List<PlanFichier> fichiers,
  String precisions,
);

Future<Map<String, dynamic>> appelLecturePlanParDefaut(
  List<PlanFichier> fichiers,
  String precisions,
) => Fonctions.appelerAvecDelai('lirePlanCharpente', {
  'fichiers': [
    for (final f in fichiers) {'nom': f.nom, 'donnees': base64Encode(f.octets)},
  ],
  if (precisions.isNotEmpty) 'precisions': precisions,
}, const Duration(seconds: 320));

enum _Etape { choix, analyse, revue }

/// « Calculer à partir d'un plan » : on joint un PDF ou des photos du plan, l'assistant le lit,
/// puis on vérifie ce qu'il a lu avant d'appliquer. Les valeurs qu'il juge incertaines (ou dont
/// la cote imprimée ne correspond pas) doivent être confirmées à la main. L'application calcule
/// ensuite le bois ; l'aperçu 3D permet de comparer le résultat au plan.
class LirePlanScreen extends StatefulWidget {
  final AppelLecturePlan appeler;
  final SelecteurPlans selecteur;

  /// Un calcul est déjà en cours : l'appliquer le remplace (on demande confirmation).
  final bool calculExistant;

  const LirePlanScreen({
    super.key,
    this.appeler = appelLecturePlanParDefaut,
    this.selecteur = const SelecteurPlansReel(),
    this.calculExistant = false,
  });

  @override
  State<LirePlanScreen> createState() => _LirePlanScreenState();
}

class _LirePlanScreenState extends State<LirePlanScreen> {
  final _precisions = TextEditingController();
  final List<PlanFichier> _fichiers = [];
  _Etape _etape = _Etape.choix;
  List<String> _problemes = [];
  String? _erreur;

  LecturePlan? _lecture;
  ResultatsProjet? _resultats;

  /// Chaque analyse a son numéro : le résultat d'une analyse abandonnée est ignoré.
  int _numeroAnalyse = 0;

  @override
  void dispose() {
    _precisions.dispose();
    super.dispose();
  }

  int get _tailleTotale => _fichiers.fold(0, (a, f) => a + f.taille);

  // ---------------------------------------------------------------------------
  // Choix des fichiers
  // ---------------------------------------------------------------------------

  Future<void> _choisir(Future<ChoixPlans> Function() choisir) async {
    final ChoixPlans choix;
    try {
      choix = await choisir();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _problemes = ['Impossible d\'ouvrir le sélecteur de fichiers.'],
      );
      return;
    }
    if (!mounted) return;
    final problemes = [...choix.refus];
    for (final f in choix.fichiers) {
      final raison = raisonRefusPlan(f.nom, f.taille);
      if (raison != null) {
        problemes.add('${f.nom} : $raison');
      } else if (_fichiers.length >= maxFichiersPlan) {
        problemes.add('${f.nom} : $maxFichiersPlan fichiers au maximum.');
      } else if (_tailleTotale + f.taille > tailleMaxTotalPlan) {
        problemes.add(
          '${f.nom} : le total dépasserait '
          '${formaterTaillePlan(tailleMaxTotalPlan)}.',
        );
      } else {
        _fichiers.add(f);
      }
    }
    setState(() {
      _problemes = problemes;
      _erreur = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Lecture par l'assistant
  // ---------------------------------------------------------------------------

  Future<void> _analyser() async {
    final numero = ++_numeroAnalyse;
    setState(() {
      _etape = _Etape.analyse;
      _erreur = null;
    });
    try {
      final r = await widget.appeler(
        List.of(_fichiers),
        _precisions.text.trim(),
      );
      if (!mounted || numero != _numeroAnalyse) return;
      final lecture = LecturePlan.depuis(r);
      setState(() {
        _lecture = lecture;
        _recalculer();
        _etape = _Etape.revue;
      });
    } on FormatException {
      _echec(
        numero,
        'La réponse de l\'assistant est illisible. Réessayez avec une image plus nette.',
      );
    } catch (e) {
      _echec(
        numero,
        Fonctions.message(
          e,
          'La lecture du plan a échoué. Réessayez dans un moment.',
        ),
      );
    }
  }

  void _echec(int numero, String message) {
    if (!mounted || numero != _numeroAnalyse) return;
    setState(() {
      _etape = _Etape.choix;
      _erreur = message;
    });
  }

  void _annulerAnalyse() {
    _numeroAnalyse++;
    setState(() => _etape = _Etape.choix);
  }

  void _recommencer() {
    setState(() {
      _lecture = null;
      _resultats = null;
      _etape = _Etape.choix;
    });
  }

  void _recalculer() {
    _resultats = calculerProjet(
      _lecture!.projet,
      metrique: Preferences.estMetrique,
    );
  }

  void _changer(LecturePlan lecture) {
    setState(() {
      // Confirmer une valeur ne change pas le projet : pas de nouveau calcul (ni de nouvelle
      // scène 3D, qui remettrait la vue à zéro).
      final projetChange = !identical(lecture.projet, _lecture?.projet);
      _lecture = lecture;
      if (projetChange) _recalculer();
    });
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculer à partir d\'un plan'),
        actions: [
          if (_etape == _Etape.revue)
            IconButton(
              key: const ValueKey('plan_recommencer'),
              tooltip: 'Choisir d\'autres fichiers',
              icon: const Icon(Icons.restart_alt),
              onPressed: _recommencer,
            ),
        ],
      ),
      body: switch (_etape) {
        _Etape.choix => _vueChoix(context),
        _Etape.analyse => _vueAnalyse(context),
        _Etape.revue => _vueRevue(context),
      },
    );
  }

  Widget _vueChoix(BuildContext context) {
    final peutAnalyser = _fichiers.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Joignez le plan du projet (PDF ou photos). L\'assistant lit les '
          'dimensions, les portes et les fenêtres ; vous vérifiez ce qu\'il a '
          'lu, puis l\'application calcule les matériaux.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('plan_choisir_fichier'),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Choisir un PDF ou une image'),
              onPressed: () => _choisir(widget.selecteur.choisirFichiers),
            ),
            OutlinedButton.icon(
              key: const ValueKey('plan_prendre_photo'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Photographier'),
              onPressed: () => _choisir(widget.selecteur.prendrePhoto),
            ),
            OutlinedButton.icon(
              key: const ValueKey('plan_choisir_photos'),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galerie'),
              onPressed: () => _choisir(widget.selecteur.choisirPhotos),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Jusqu\'à $maxFichiersPlan fichiers, '
          '${formaterTaillePlan(tailleMaxFichierPlan)} chacun '
          '(${formaterTaillePlan(tailleMaxTotalPlan)} au total). '
          'Une page par photo, bien à plat et bien éclairée.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_erreur != null) BlocMessages([_erreur!], erreur: true),
        if (_problemes.isNotEmpty)
          BlocMessages([for (final p in _problemes) 'Refusé — $p']),
        if (_fichiers.isNotEmpty) ...[
          const TitreSection('Fichiers joints'),
          for (var i = 0; i < _fichiers.length; i++)
            ListTile(
              key: ValueKey('plan_fichier_$i'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                _fichiers[i].nom.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf
                    : Icons.image_outlined,
              ),
              title: Text(_fichiers[i].nom, overflow: TextOverflow.ellipsis),
              subtitle: Text(formaterTaillePlan(_fichiers[i].taille)),
              trailing: IconButton(
                key: ValueKey('plan_retirer_$i'),
                tooltip: 'Retirer',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _fichiers.removeAt(i)),
              ),
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('plan_precisions'),
          controller: _precisions,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Précisions (facultatif)',
            hintText: 'Ex. : seulement le garage ; le plan du rez-de-chaussée est à la page 2',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('plan_analyser'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Lire le plan'),
          onPressed: peutAnalyser ? _analyser : null,
        ),
        const SizedBox(height: 12),
        Text(
          'Le plan est envoyé de façon sécurisée à l\'assistant IA pour être lu. '
          'Chantier+ ne le conserve pas. Le calcul couvre le plancher et les murs '
          '(portes et fenêtres comprises) ; la toiture, les fondations et les '
          'escaliers ne sont pas calculés à partir du plan.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _vueAnalyse(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              'Lecture du plan en cours…',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cela prend de 20 secondes à 2 minutes selon le nombre de pages.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const ValueKey('plan_annuler_analyse'),
              onPressed: _annulerAnalyse,
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Revue ------------------------------------------------------------------

  Widget _vueRevue(BuildContext context) {
    final l = _lecture!;
    final res = _resultats!;
    final aConfirmer = l.aConfirmer;
    final aVerifier = l.aVerifier;
    final restantes = l.restantes;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              Text('Plan lu', style: Theme.of(context).textTheme.titleLarge),
              if (l.explication.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.explication),
                ),
              if (l.niveauLu.isNotEmpty || l.echelle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (l.niveauLu.isNotEmpty) 'Niveau lu : ${l.niveauLu}',
                      if (l.echelle.isNotEmpty) 'Échelle : ${l.echelle}',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (problemesDesOuvertures(l.projet) case final problemes
                  when problemes.isNotEmpty) ...[
                TitreSection(
                  'Ce qui ne passe pas dans les murs (${problemes.length})',
                  aide:
                      'Comparez avec le plan : ces portes ou fenêtres n\'entrent pas telles quelles '
                      'dans la charpente calculée. Corrigez la valeur lue, ou réglez-le dans l\'onglet Murs.',
                ),
                BlocMessages(
                  key: const ValueKey('plan_problemes_murs'),
                  problemes,
                  erreur: true,
                ),
              ],
              if (l.avertissements.isNotEmpty)
                BlocMessages(
                  key: const ValueKey('plan_avertissements'),
                  l.avertissements,
                  erreur: true,
                ),
              if (l.confiance == ConfianceLecture.faible)
                const BlocMessages([
                  'Lecture peu sûre : comparez chaque valeur avec le plan avant d\'appliquer.',
                ]),
              if (aConfirmer.isNotEmpty) ...[
                TitreSection(
                  'À confirmer (${aConfirmer.length})',
                  aide:
                      'Ces valeurs ne sont pas sûres. Vérifiez-les sur le plan, corrigez '
                      'au besoin, puis confirmez chacune.',
                ),
                for (final v in aConfirmer)
                  _fiche(context, l, v, bloquante: true),
              ],
              if (aVerifier.isNotEmpty) ...[
                TitreSection(
                  'À vérifier (${aVerifier.length})',
                  aide: 'Valeurs déduites d\'autres cotes ou de l\'échelle. Un coup d\'œil suffit.',
                ),
                for (final v in aVerifier)
                  _fiche(context, l, v, bloquante: false),
              ],
              if (l.hypotheses.isNotEmpty) ...[
                const TitreSection('Hypothèses de l\'assistant'),
                for (final h in l.hypotheses)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• $h'),
                  ),
              ],
              ..._resume(context, l, res),
              ..._apercu3D(context, res),
              ..._materiaux(context, res),
              const SizedBox(height: 8),
              Text(
                'L\'application calcule le bois à partir de ces valeurs. Vérifiez toujours '
                'avec le plan avant de commander.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _barreAppliquer(context, restantes, res),
      ],
    );
  }

  Widget _barreAppliquer(
    BuildContext context,
    int restantes,
    ResultatsProjet res,
  ) {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (restantes > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    restantes == 1
                        ? 'Confirmez la valeur incertaine pour continuer.'
                        : 'Confirmez les $restantes valeurs incertaines pour continuer.',
                    key: const ValueKey('plan_restantes'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (res.aDesErreurs)
                BlocMessages([
                  if (res.erreurPlancher != null)
                    'Plancher : ${res.erreurPlancher}',
                  if (res.erreurMurs != null)
                    // La liste complète est plus haut : on ne la répète pas ici.
                    switch (problemesDesOuvertures(_lecture!.projet).length) {
                      0 => 'Murs : ${res.erreurMurs}',
                      1 =>
                        'Murs : 1 porte ou fenêtre à régler (voir la liste).',
                      final n =>
                        'Murs : $n problèmes à régler (voir la liste).',
                    },
                ], erreur: true),
              FilledButton.icon(
                key: const ValueKey('plan_appliquer'),
                icon: const Icon(Icons.checklist),
                label: Text(
                  res.aDesErreurs
                      ? 'Appliquer et corriger'
                      : 'Appliquer et voir la commande',
                ),
                onPressed: restantes == 0 ? _appliquer : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Une valeur à confirmer ou à vérifier : ce qui a été lu, pourquoi c'est incertain, le champ
  /// pour corriger, et le bouton de confirmation.
  Widget _fiche(
    BuildContext context,
    LecturePlan l,
    ValeurLue v, {
    required bool bloquante,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final confirmee = l.estConfirmee(v.chemin);
    final genre = genreDuChemin(v.chemin)!;
    final valeur = l.valeurDe(v.chemin);
    final fond = confirmee
        ? const Color(0xFFE6F4EA)
        : (bloquante
              ? const Color(0xFFFFF3CD)
              : scheme.surfaceContainerHighest);
    return Card(
      key: ValueKey('valeur_${v.chemin}'),
      color: fond,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    libelleChemin(l.projetJson, v.chemin),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (confirmee)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            if (v.raison.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(v.raison, style: const TextStyle(fontSize: 12)),
              ),
            if (v.lecture.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Lu sur le plan : « ${v.lecture} »',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (v.valeurPlan != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Valeur du plan : ${formatLongueur(v.valeurPlan!, metrique: Preferences.estMetrique)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('utiliser_${v.chemin}'),
                    onPressed: () => _utiliserValeurDuPlan(v),
                    child: const Text('Utiliser cette valeur'),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            _editeur(l, v, genre, valeur),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: confirmee
                  ? TextButton(
                      key: ValueKey('revoir_${v.chemin}'),
                      onPressed: () =>
                          _changer(_lecture!.annulerConfirmation(v.chemin)),
                      child: const Text('Revoir'),
                    )
                  : FilledButton.tonal(
                      key: ValueKey('confirmer_${v.chemin}'),
                      onPressed: () => _changer(_lecture!.confirmer(v.chemin)),
                      child: const Text('Confirmer cette valeur'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _appliquer() async {
    final l = _lecture;
    if (l == null || !l.toutConfirme) return;
    if (widget.calculExistant) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remplacer le calcul en cours ?'),
          content: const Text(
            'Le plancher et les murs du calcul en cours seront remplacés par ceux du plan. '
            'Les lignes ajoutées à la main sont conservées.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('plan_remplacer'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    Navigator.pop(context, l.projet);
  }

  void _utiliserValeurDuPlan(ValeurLue v) {
    // Un geste explicite de l'utilisateur : la valeur du plan est aussi confirmée.
    try {
      _changer(_lecture!.modifier(v.chemin, v.valeurPlan!).confirmer(v.chemin));
    } on FormatException {
      // Valeur du plan hors des bornes permises : rien ne change.
    }
  }

  /// Corrige une valeur ; une valeur refusée (hors bornes) est ignorée, le champ affiche l'erreur.
  void _corriger(String chemin, Object valeur) {
    try {
      _changer(_lecture!.modifier(chemin, valeur));
    } on FormatException {
      // Le champ de saisie affiche déjà le message.
    }
  }

  Widget _editeur(
    LecturePlan l,
    ValeurLue v,
    GenreValeur genre,
    Object? valeur,
  ) {
    final chemin = v.chemin;
    switch (genre) {
      case GenreValeur.longueur:
        final (min, max) = bornesDuChemin(chemin);
        return ChampLongueur(
          key: ValueKey('champ_$chemin'),
          label: 'Valeur lue',
          valeur: valeur is num ? valeur.toDouble() : 0,
          min: min,
          max: max,
          onChange: (x) => _corriger(chemin, x),
        );
      case GenreValeur.angle:
      case GenreValeur.nombre:
      case GenreValeur.entier:
        final (min, max) = bornesDuChemin(chemin);
        return ChampNombre(
          key: ValueKey('champ_$chemin'),
          label: 'Valeur lue',
          valeur: valeur is num ? valeur.toDouble() : 0,
          min: min,
          max: max,
          decimales: genre == GenreValeur.entier ? 0 : 1,
          suffixe: switch (genre) {
            GenreValeur.angle => '°',
            GenreValeur.entier => null,
            _ => 'po',
          },
          onChange: (x) => _corriger(chemin, x),
        );
      case GenreValeur.choix:
        return DropdownButtonFormField<String>(
          key: ValueKey('champ_${chemin}_$valeur'),
          initialValue: valeur is String ? valeur : null,
          decoration: const InputDecoration(
            labelText: 'Valeur lue',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final c in choixDuChemin(chemin))
              DropdownMenuItem(value: c, child: Text(_libelleChoix(c))),
          ],
          onChanged: (c) {
            if (c != null) _corriger(chemin, c);
          },
        );
    }
  }

  // --- Résumé de ce qui a été lu ------------------------------------------------

  List<Widget> _resume(
    BuildContext context,
    LecturePlan l,
    ResultatsProjet res,
  ) {
    final metrique = Preferences.estMetrique;
    final p = l.projet;
    final lignes = <Widget>[];

    if (p.plancherActif && res.contour != null) {
      final b = res.contour!.boite;
      final dims = res.contour!.nombre == 4 && res.contour!.estRectangle
          ? '${formatLongueur(b.largeur, metrique: metrique)} × '
                '${formatLongueur(b.hauteur, metrique: metrique)}'
          : '${res.contour!.nombre} côtés, '
                '${formatNombre(res.contour!.aire / 144, decimales: 0)} pi²';
      lignes.add(
        Text(
          'Plancher : $dims, solives ${p.plancher.section.nom} à '
          '${formatNombre(p.plancher.espacement, decimales: 1)} po c/c',
          key: const ValueKey('plan_resume_plancher'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    final murs = res.murs;
    if (p.mursActifs && murs != null) {
      for (final m in murs.murs) {
        lignes.add(const SizedBox(height: 6));
        lignes.add(
          Text(
            '${m.spec.nom} : ${formatLongueur(m.spec.longueur + m.spec.retraitDebut + m.spec.retraitFin, metrique: metrique)} '
            'de long, ${formatLongueur(m.spec.hauteur, metrique: metrique)} de haut',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
        for (final o in m.spec.ouvertures) {
          lignes.add(
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                '• ${nomOuverture(o)} : ${formatLongueur(o.largeurCadre, metrique: metrique)} × '
                '${formatLongueur(o.hauteurCadre, metrique: metrique)}'
                '${o.type == TypeOuverture.fenetre ? ', allège ${formatLongueur(o.allege, metrique: metrique)}' : ''}'
                ', centrée à ${formatLongueur(o.position + m.spec.retraitDebut, metrique: metrique)} du coin',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          );
        }
      }
    }
    if (lignes.isEmpty) return const [];

    final nbPortes = murs == null
        ? 0
        : murs.murs.fold(
            0,
            (a, m) =>
                a +
                m.spec.ouvertures
                    .where((o) => o.type == TypeOuverture.porte)
                    .length,
          );
    final nbFenetres = murs == null
        ? 0
        : murs.murs.fold(
            0,
            (a, m) =>
                a +
                m.spec.ouvertures
                    .where((o) => o.type == TypeOuverture.fenetre)
                    .length,
          );
    return [
      TitreSection(
        'Ce que l\'assistant a lu',
        aide: murs == null
            ? null
            : '$nbPortes porte${nbPortes > 1 ? 's' : ''} et '
                  '$nbFenetres fenêtre${nbFenetres > 1 ? 's' : ''} relevée${nbPortes + nbFenetres > 1 ? 's' : ''} au plan',
      ),
      ...lignes,
      ..._cotesLues(l),
    ];
  }

  /// Les cotes lues sans équivoque : ce que le plan dit, et si l'application a pu le vérifier.
  List<Widget> _cotesLues(LecturePlan l) {
    final lues = l.lues;
    if (lues.isEmpty) return const [];
    return [
      ExpansionTile(
        key: const ValueKey('plan_cotes_lues'),
        tilePadding: EdgeInsets.zero,
        title: Text('Cotes lues sur le plan (${lues.length})'),
        children: [
          for (final v in lues)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                v.verifiee ? Icons.check_circle_outline : Icons.circle_outlined,
                size: 18,
                color: v.verifiee ? Colors.green : null,
              ),
              title: Text(libelleChemin(l.projetJson, v.chemin)),
              subtitle: Text(
                '${_texteValeur(l, v)}'
                '${v.lecture.isEmpty ? '' : ' — plan : « ${v.lecture} »'}'
                '${v.verifiee ? ' (conversion vérifiée)' : ''}',
              ),
            ),
        ],
      ),
    ];
  }

  String _texteValeur(LecturePlan l, ValeurLue v) {
    final x = l.valeurDe(v.chemin);
    final metrique = Preferences.estMetrique;
    return switch (genreDuChemin(v.chemin)!) {
      GenreValeur.longueur =>
        x is num ? formatLongueur(x.toDouble(), metrique: metrique) : '—',
      GenreValeur.angle => x is num ? formatAngle(x.toDouble()) : '—',
      GenreValeur.nombre =>
        x is num ? '${formatNombre(x.toDouble(), decimales: 1)} po' : '—',
      GenreValeur.entier => x is num ? '${x.round()}' : '—',
      GenreValeur.choix => x is String ? _libelleChoix(x) : '—',
    };
  }

  String _libelleChoix(String c) => switch (c) {
    'porte' => 'Porte',
    'fenetre' => 'Fenêtre',
    'aucun' => 'Aucun',
    'unBout' => 'Un bout',
    'deuxBouts' => 'Deux bouts',
    _ => c,
  };

  // --- Aperçu 3D et matériaux -----------------------------------------------------

  List<Widget> _apercu3D(BuildContext context, ResultatsProjet res) {
    if (res.plancher == null && res.murs == null) return const [];
    return [
      const TitreSection(
        'Aperçu 3D',
        aide: 'Comparez avec le plan : formes, portes et fenêtres. Touchez pour l\'agrandir.',
      ),
      Vue3D(
        key: const ValueKey('plan_apercu_3d'),
        scene: res.scene,
        controles: false,
        interactif: false,
        hauteur: 260,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Aperçu 3D')),
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: Vue3D(scene: res.scene),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _materiaux(BuildContext context, ResultatsProjet res) {
    final commande = res.commande;
    if (commande.estVide) return const [];
    return [
      const TitreSection(
        'Matériaux calculés',
        aide: 'Mis à jour à chaque correction.',
      ),
      Column(
        key: const ValueKey('plan_materiaux'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in CategorieCommande.values)
            if (commande.lignes.any((x) => x.categorie == c)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  libelleCategorie(c),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final x in commande.lignes.where((x) => x.categorie == c))
                Text('${x.quantiteTexte} × ${x.article}'),
            ],
        ],
      ),
      if (commande.avertissements.isNotEmpty)
        BlocMessages(commande.avertissements),
    ];
  }
}
