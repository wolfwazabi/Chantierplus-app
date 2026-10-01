import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../charpente/commande.dart';
import '../../charpente/projet.dart';
import '../../models/commande_chantier.dart';
import '../../services/app_session.dart';
import 'champs.dart';

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Onglet « Commande » : liste d'achat du projet, lignes ajoutées à la main,
/// copie / courriel pour le fournisseur et commandes enregistrées du chantier.
class OngletCommande extends StatefulWidget {
  final ProjetCharpente projet;
  final ResultatsProjet resultats;
  final List<LigneCommande> manuelles;
  final ValueChanged<List<LigneCommande>> onManuelles;
  final String companyId;
  final String chantierId;
  final bool connecte;

  /// Rouvre le calcul d'une commande enregistrée.
  final ValueChanged<ProjetCharpente> onOuvrirProjet;

  /// Remplace la liste des commandes enregistrées (tests, sans Firestore).
  @visibleForTesting
  final Widget? listeEnregistrees;

  const OngletCommande({
    super.key,
    required this.projet,
    required this.resultats,
    required this.manuelles,
    required this.onManuelles,
    required this.companyId,
    required this.chantierId,
    required this.connecte,
    required this.onOuvrirProjet,
    this.listeEnregistrees,
  });

  @override
  State<OngletCommande> createState() => _OngletCommandeState();
}

class _OngletCommandeState extends State<OngletCommande> {
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('chantier_commandes');

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  Commande get _commande => Commande(
    fusionnerLignes([...widget.resultats.commande.lignes, ...widget.manuelles]),
    widget.resultats.commande.avertissements,
  );

  String _titre() => widget.projet.nom.trim().isEmpty
      ? 'Liste de matériaux'
      : widget.projet.nom.trim();

  Future<void> _copier(String texte) async {
    await Clipboard.setData(ClipboardData(text: texte));
    _message('Liste copiée.');
  }

  Future<void> _courriel(String titre, String texte) async {
    // Les liens mailto: ont une longueur limitée : au-delà, la liste est
    // copiée pour être collée dans le courriel.
    final trop = texte.length > 1800;
    if (trop) {
      await Clipboard.setData(ClipboardData(text: texte));
    }
    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(titre)}'
      '&body=${Uri.encodeComponent(trop ? '(collez la liste copiée ici)' : texte)}',
    );
    try {
      final ok = await launchUrl(uri);
      if (!ok) {
        _message('Aucune application de courriel trouvée.', erreur: true);
      } else if (trop) {
        _message('Liste copiée : collez-la dans le courriel.');
      }
    } catch (_) {
      _message('Impossible d\'ouvrir le courriel.', erreur: true);
    }
  }

  Future<void> _ajouterLigne() async {
    final r = await showDialog<LigneCommande>(
      context: context,
      builder: (ctx) => const _DialogueLigne(),
    );
    if (r != null) {
      widget.onManuelles([...widget.manuelles, r]);
    }
  }

  Future<void> _enregistrer() async {
    final commande = _commande;
    if (commande.estVide) {
      return;
    }
    final employe = AppSession.current;
    if (employe == null) {
      _message('Connexion requise.', erreur: true);
      return;
    }
    final saisie = await showDialog<_SaisieCommande>(
      context: context,
      builder: (ctx) => _DialogueEnregistrer(
        nomInitial: widget.projet.nom.trim().isEmpty
            ? 'Commande du ${_date(DateTime.now())}'
            : widget.projet.nom.trim(),
      ),
    );
    if (saisie == null) {
      return;
    }
    try {
      final projet = jsonEncode(widget.projet.toJson());
      await _collection.add({
        'companyId': widget.companyId,
        'chantierId': widget.chantierId,
        'nom': saisie.nom,
        'lignes': [for (final l in commande.lignes) l.toJson()],
        if (projet.length <= 150000) 'projet': projet,
        'statut': 'brouillon',
        if (saisie.fournisseur.isNotEmpty) 'fournisseur': saisie.fournisseur,
        if (saisie.notes.isNotEmpty) 'notes': saisie.notes,
        'ajoutePar': employe.id,
        'ajouteParNom': employe.nom,
        'dateAjout': FieldValue.serverTimestamp(),
      });
      _message('Commande enregistrée.');
    } catch (_) {
      _message('Enregistrement impossible.', erreur: true);
    }
  }

  void _ouvrir(CommandeChantier c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _DetailCommande(
        commande: c,
        ref: _collection.doc(c.id),
        onCopier: _copier,
        onCourriel: _courriel,
        onOuvrirProjet: (p) {
          Navigator.pop(ctx);
          widget.onOuvrirProjet(p);
        },
        message: _message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final commande = _commande;
    final res = widget.resultats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (res.aDesErreurs)
          BlocMessages([
            if (res.erreurPlancher != null) 'Plancher : ${res.erreurPlancher}',
            if (res.erreurMurs != null) 'Murs : ${res.erreurMurs}',
          ], erreur: true),
        if (commande.estVide)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Rien à commander pour le moment : complétez le plancher ou les murs, '
              'ou ajoutez une ligne à la main.',
            ),
          )
        else ...[
          for (final cat in CategorieCommande.values)
            _Categorie(
              categorie: cat,
              lignes: [
                for (final l in commande.lignes)
                  if (l.categorie == cat) l,
              ],
              onRetirer: (l) {
                final i = widget.manuelles.indexOf(l);
                if (i >= 0) {
                  widget.onManuelles([...widget.manuelles]..removeAt(i));
                }
              },
            ),
          if (commande.piecesDeBois > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Total : ${commande.piecesDeBois} pièces de bois d\'œuvre.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('commande_ajouter_ligne'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une ligne'),
              onPressed: widget.manuelles.length >= 100 ? null : _ajouterLigne,
            ),
            OutlinedButton.icon(
              key: const ValueKey('commande_copier'),
              icon: const Icon(Icons.copy),
              label: const Text('Copier'),
              onPressed: commande.estVide
                  ? null
                  : () => _copier(commande.enTexte(titre: _titre())),
            ),
            OutlinedButton.icon(
              key: const ValueKey('commande_courriel'),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Courriel'),
              onPressed: commande.estVide
                  ? null
                  : () =>
                        _courriel(_titre(), commande.enTexte(titre: _titre())),
            ),
            FilledButton.icon(
              key: const ValueKey('commande_enregistrer'),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer la commande'),
              onPressed: commande.estVide || !widget.connecte
                  ? null
                  : _enregistrer,
            ),
          ],
        ),
        if (!widget.connecte)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Hors ligne : l\'enregistrement est désactivé.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        BlocMessages(commande.avertissements),
        const TitreSection('Commandes enregistrées'),
        widget.listeEnregistrees ??
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _collection
                  .where('companyId', isEqualTo: widget.companyId)
                  .where('chantierId', isEqualTo: widget.chantierId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Impossible de charger les commandes.');
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final liste =
                    [
                      for (final d in snapshot.data!.docs)
                        CommandeChantier.fromFirestore(d.id, d.data()),
                    ]..sort(
                      (a, b) => (b.dateAjout ?? DateTime.now()).compareTo(
                        a.dateAjout ?? DateTime.now(),
                      ),
                    );
                if (liste.isEmpty) {
                  return const Text(
                    'Aucune commande enregistrée pour ce chantier.',
                  );
                }
                return Column(
                  children: [
                    for (final c in liste)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          key: ValueKey('commande_${c.id}'),
                          title: Text(c.nom),
                          subtitle: Text(
                            '${c.dateAjout == null ? '' : '${_date(c.dateAjout!)} · '}'
                            '${c.lignes.length} ligne${c.lignes.length > 1 ? 's' : ''}'
                            '${c.fournisseur.isEmpty ? '' : ' · ${c.fournisseur}'}'
                            '${c.ajouteParNom.isEmpty ? '' : ' · ${c.ajouteParNom}'}',
                          ),
                          trailing: Chip(
                            label: Text(
                              CommandeChantier.libelleStatut(c.statut),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onTap: () => _ouvrir(c),
                        ),
                      ),
                  ],
                );
              },
            ),
      ],
    );
  }
}

class _Categorie extends StatelessWidget {
  final CategorieCommande categorie;
  final List<LigneCommande> lignes;
  final ValueChanged<LigneCommande> onRetirer;
  const _Categorie({
    required this.categorie,
    required this.lignes,
    required this.onRetirer,
  });

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitreSection(libelleCategorie(categorie)),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final l in lignes)
                ListTile(
                  dense: true,
                  title: Text('${l.quantiteTexte} × ${l.article}'),
                  subtitle: l.usage.isEmpty ? null : Text(l.usage),
                  trailing: l.manuelle
                      ? IconButton(
                          tooltip: 'Retirer cette ligne',
                          icon: const Icon(Icons.close),
                          onPressed: () => onRetirer(l),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Dialogues
// =============================================================================

class _DialogueLigne extends StatefulWidget {
  const _DialogueLigne();

  @override
  State<_DialogueLigne> createState() => _DialogueLigneState();
}

class _DialogueLigneState extends State<_DialogueLigne> {
  final _article = TextEditingController();
  final _quantite = TextEditingController(text: '1');
  CategorieCommande _categorie = CategorieCommande.quincaillerie;

  @override
  void dispose() {
    _article.dispose();
    _quantite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = double.tryParse(_quantite.text.trim().replaceAll(',', '.'));
    final valide =
        _article.text.trim().isNotEmpty && q != null && q > 0 && q <= 1e6;
    return AlertDialog(
      title: const Text('Ajouter une ligne'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('ligne_article'),
              controller: _article,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Article',
                hintText: 'Ex. : clous annelés 3 1/4 po (boîte)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('ligne_quantite'),
              controller: _quantite,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantité',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CategorieCommande>(
              initialValue: _categorie,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Catégorie',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in CategorieCommande.values)
                  DropdownMenuItem(
                    value: c,
                    child: Text(
                      libelleCategorie(c),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (c) => setState(() => _categorie = c ?? _categorie),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('ligne_ok'),
          onPressed: valide
              ? () => Navigator.pop(
                  context,
                  LigneCommande(
                    categorie: _categorie,
                    article: _article.text.trim(),
                    quantite: q,
                    usage: 'Ajout manuel',
                    manuelle: true,
                  ),
                )
              : null,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _SaisieCommande {
  final String nom;
  final String fournisseur;
  final String notes;
  const _SaisieCommande(this.nom, this.fournisseur, this.notes);
}

class _DialogueEnregistrer extends StatefulWidget {
  final String nomInitial;
  const _DialogueEnregistrer({required this.nomInitial});

  @override
  State<_DialogueEnregistrer> createState() => _DialogueEnregistrerState();
}

class _DialogueEnregistrerState extends State<_DialogueEnregistrer> {
  late final TextEditingController _nom = TextEditingController(
    text: widget.nomInitial,
  );
  final _fournisseur = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    _fournisseur.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enregistrer la commande'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('commande_nom'),
              controller: _nom,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Nom de la commande',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fournisseur,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Fournisseur (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('commande_nom_ok'),
          onPressed: _nom.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _SaisieCommande(
                    _nom.text.trim(),
                    _fournisseur.text.trim(),
                    _notes.text.trim(),
                  ),
                ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _DetailCommande extends StatelessWidget {
  final CommandeChantier commande;
  final DocumentReference<Map<String, dynamic>> ref;
  final Future<void> Function(String texte) onCopier;
  final Future<void> Function(String titre, String texte) onCourriel;
  final ValueChanged<ProjetCharpente> onOuvrirProjet;
  final void Function(String, {bool erreur}) message;

  const _DetailCommande({
    required this.commande,
    required this.ref,
    required this.onCopier,
    required this.onCourriel,
    required this.onOuvrirProjet,
    required this.message,
  });

  Future<void> _statut(BuildContext context, String statut) async {
    try {
      await ref.update({
        'statut': statut,
        if (statut == 'commandee') 'dateCommande': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        Navigator.pop(context);
      }
      message('Statut : ${CommandeChantier.libelleStatut(statut)}.');
    } catch (_) {
      message('Modification impossible.', erreur: true);
    }
  }

  Future<void> _supprimer(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette commande ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      await ref.delete();
      if (context.mounted) {
        Navigator.pop(context);
      }
      message('Commande supprimée.');
    } catch (_) {
      message(
        'Suppression refusée : seul un admin supprime une commande déjà passée.',
        erreur: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final texte = commande.commande.enTexte(titre: commande.nom);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(commande.nom, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${CommandeChantier.libelleStatut(commande.statut)}'
              '${commande.dateAjout == null ? '' : ' · créée le ${_date(commande.dateAjout!)}'}'
              '${commande.dateCommande == null ? '' : ' · commandée le ${_date(commande.dateCommande!)}'}',
            ),
            if (commande.fournisseur.isNotEmpty)
              Text('Fournisseur : ${commande.fournisseur}'),
            if (commande.notes.isNotEmpty) Text('Notes : ${commande.notes}'),
            const Divider(),
            SelectableText(texte),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copier'),
                  onPressed: () => onCopier(texte),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Courriel'),
                  onPressed: () => onCourriel(commande.nom, texte),
                ),
                if (commande.projet != null)
                  OutlinedButton.icon(
                    key: const ValueKey('commande_rouvrir'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rouvrir le calcul'),
                    onPressed: () {
                      try {
                        onOuvrirProjet(
                          ProjetCharpente.fromJson(
                            jsonDecode(commande.projet!),
                          ),
                        );
                      } on FormatException {
                        message(
                          'Ce calcul ne peut plus être rouvert.',
                          erreur: true,
                        );
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (commande.statut != 'commandee')
                  FilledButton.tonal(
                    key: const ValueKey('commande_marquer_commandee'),
                    onPressed: () => _statut(context, 'commandee'),
                    child: const Text('Marquer comme commandée'),
                  ),
                if (commande.statut != 'recue')
                  FilledButton.tonal(
                    key: const ValueKey('commande_marquer_recue'),
                    onPressed: () => _statut(context, 'recue'),
                    child: const Text('Marquer comme reçue'),
                  ),
                if (commande.statut != 'brouillon')
                  TextButton(
                    onPressed: () => _statut(context, 'brouillon'),
                    child: const Text('Remettre en brouillon'),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('commande_supprimer'),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () => _supprimer(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
