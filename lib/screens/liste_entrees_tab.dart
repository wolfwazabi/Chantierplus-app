import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/materiel_general.dart';
import '../models/photos_entree.dart';
import '../services/app_session.dart';
import '../services/erreurs_firebase.dart';
import '../services/theme_compagnie.dart';
import '../widgets/fermer_clavier.dart';
import '../widgets/photos_multiples.dart';
import '../widgets/actualiser.dart';

/// Onglet liste d'un chantier (Travaux à compléter, Matériel) ou liste « Général »
/// (matériel de la remorque, sans chantier). Chaque entrée a un texte, une quantité
/// (matériel) et jusqu'à [maxPhotosParEntree] photos.
///
/// Général : chaque entrée porte son auteur ; un contremaître ne voit que ses
/// demandes, un admin voit tout le monde (puces de filtre). Une demande transférée à
/// la Liste d'achats reste visible pour son auteur, mais seul un admin la modifie.
class ListeEntreesTab extends StatefulWidget {
  final String chantierId;
  final String companyId;
  final bool connecte;
  final String collection;
  final String libelleChampAjout;
  final String libelleComplete;
  final String libelleActif;
  final IconData icone;
  final bool avecQuantite;

  /// Liste « Général » (remorque, sans chantier).
  final bool general;

  /// Tests : remplacent la lecture, les écritures, l'envoi des photos et les
  /// sélecteurs de photos.
  @visibleForTesting
  final Stream<List<MapEntry<String, Map<String, dynamic>>>>? flux;
  @visibleForTesting
  final Future<void> Function(String collection, Map<String, dynamic> data)?
  ajouter;
  @visibleForTesting
  final Future<void> Function(
    String collection,
    String id,
    Map<String, dynamic> data,
  )?
  modifier;
  @visibleForTesting
  final Televerser? televerser;
  @visibleForTesting
  final PrendrePhoto? prendrePhoto;
  @visibleForTesting
  final ChoisirPhotos? choisirPhotos;

  const ListeEntreesTab({
    super.key,
    required this.chantierId,
    required this.companyId,
    required this.connecte,
    required this.collection,
    required this.libelleChampAjout,
    required this.libelleComplete,
    required this.libelleActif,
    required this.icone,
    required this.avecQuantite,
    this.general = false,
    this.flux,
    this.ajouter,
    this.modifier,
    this.televerser,
    this.prendrePhoto,
    this.choisirPhotos,
  });

  @override
  State<ListeEntreesTab> createState() => _ListeEntreesTabState();
}

class _ListeEntreesTabState extends State<ListeEntreesTab> {
  final _controleurTexte = TextEditingController();
  final _controleurQuantite = TextEditingController();
  final _photos = ControleurPhotos();
  bool _envoiEnCours = false;
  bool _afficherHistorique = false;

  /// Général : l'auteur affiché (par défaut moi-même ; null = tout le monde).
  /// Seuls les admins peuvent changer ; un contremaître ne voit que sa liste.
  String? _filtreAuteur;

  Stream<List<MapEntry<String, Map<String, dynamic>>>>? _fluxCache;
  String? _fluxCle;

  /// La lecture en direct, créée une seule fois (et de nouveau si le chantier
  /// ou la personne change).
  Stream<List<MapEntry<String, Map<String, dynamic>>>> get _flux {
    final cle =
        '${widget.collection}|${widget.companyId}|${widget.chantierId}|'
        '${AppSession.current?.id}|${AppSession.estAdmin}';
    if (_fluxCle != cle) {
      _fluxCle = cle;
      _fluxCache = _creerFlux();
    }
    return _fluxCache!;
  }

  Stream<List<MapEntry<String, Map<String, dynamic>>>> _creerFlux() {
    final base = FirebaseFirestore.instance
        .collection(widget.collection)
        .where('companyId', isEqualTo: widget.companyId)
        .where('chantierId', isEqualTo: widget.chantierId);
    List<MapEntry<String, Map<String, dynamic>>> lire(
      QuerySnapshot<Map<String, dynamic>> s,
    ) => [for (final d in s.docs) MapEntry(d.id, d.data())];
    if (!widget.general) {
      return base.orderBy('dateAjout', descending: true).snapshots().map(lire);
    }
    // Général : un contremaître ne demande que SA liste (les règles refusent le
    // reste) ; un admin, toutes. Tri ici : aucun index à créer.
    final auteur = auteurImposeALaRequete(
      estAdmin: AppSession.estAdmin,
      moiId: AppSession.current?.id,
    );
    final requete = auteur == null
        ? base
        : base.where('ajoutePar', isEqualTo: auteur);
    return requete.snapshots().map((s) => ordonnerParRecence(lire(s)));
  }

  @override
  void initState() {
    super.initState();
    if (widget.general) _filtreAuteur = AppSession.current?.id;
  }

  @override
  void dispose() {
    _controleurTexte.dispose();
    _controleurQuantite.dispose();
    _photos.dispose();
    super.dispose();
  }

  String get _dossierPhotos =>
      'chantiers/${widget.companyId}/${widget.chantierId}/${widget.collection}';

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  Future<void> _ajouterEntree() async {
    final texte = _controleurTexte.text.trim();
    if (texte.isEmpty) return;

    setState(() => _envoiEnCours = true);

    try {
      final liens = await envoyerPhotos(
        _photos.nouvelles,
        dossier: _dossierPhotos,
        televerser: widget.televerser,
      );

      // L'entrée porte son auteur (id et nom de l'employé connecté) : Général en a
      //      besoin pour séparer les listes, le fil « Activité » pour dire qui.
      final data = donneesNouvelleEntree(
        companyId: widget.companyId,
        chantierId: widget.chantierId,
        texte: texte,
        quantite: widget.avecQuantite ? _controleurQuantite.text.trim() : null,
        photos: liens,
        auteur: AppSession.current,
      );
      final ajouter = widget.ajouter;
      if (ajouter != null) {
        await ajouter(widget.collection, data);
      } else {
        await FirebaseFirestore.instance
            .collection(widget.collection)
            .add(data);
      }
    } catch (e) {
      // Le texte et les photos restent à l'écran pour réessayer.
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      _message(
        'L\'entrée n\'a pas pu être ajoutée (${detailErreurFirebase(e)}). Réessayez.',
        erreur: true,
      );
      return;
    }

    if (!mounted) return;
    _controleurTexte.clear();
    _controleurQuantite.clear();
    _photos.vider();
    setState(() => _envoiEnCours = false);
  }

  Future<void> _ecrireModification(String docId, Map<String, dynamic> data) {
    final modifier = widget.modifier;
    if (modifier != null) return modifier(widget.collection, docId, data);
    return FirebaseFirestore.instance
        .collection(widget.collection)
        .doc(docId)
        .update(data);
  }

  Future<void> _marquerComplete(String docId, bool complete) =>
      _ecrireModification(
        docId,
        donneesCompletion(
          complete: complete,
          general: widget.general,
          modifieParId: AppSession.current?.id,
        ),
      );

  Future<void> _supprimerEntree(String docId) async {
    await FirebaseFirestore.instance
        .collection(widget.collection)
        .doc(docId)
        .delete();
  }

  void _confirmerSuppression(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette entrée ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _supprimerEntree(docId);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _ouvrirEdition(String docId, Map<String, dynamic> data) {
    final texteCtrl = TextEditingController(text: data['texte'] ?? '');
    final quantiteCtrl = TextEditingController(
      text: data['quantite']?.toString() ?? '',
    );
    final photos = ControleurPhotos(existantes: photosDe(data));
    var enregistrement = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modifier l\'entrée',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: texteCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FermerClavier.fermer(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Description',
                    ),
                  ),
                  if (widget.avecQuantite) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantiteCtrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FermerClavier.fermer(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Quantité',
                        hintText: 'ex: 1 boîte de 25, 2 rouleaux',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SelecteurPhotos(
                    controleur: photos,
                    prendre: widget.prendrePhoto,
                    choisir: widget.choisirPhotos,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('modifier_enregistrer'),
                      onPressed: enregistrement
                          ? null
                          : () async {
                              setModalState(() => enregistrement = true);
                              try {
                                List<String>? finales;
                                if (photos.modifiees) {
                                  final nouveaux = await envoyerPhotos(
                                    photos.nouvelles,
                                    dossier: _dossierPhotos,
                                    televerser: widget.televerser,
                                  );
                                  finales = [...photos.existantes, ...nouveaux];
                                }
                                await _ecrireModification(
                                  docId,
                                  donneesModification(
                                    texte: texteCtrl.text.trim(),
                                    quantite: widget.avecQuantite
                                        ? quantiteCtrl.text.trim()
                                        : null,
                                    photos: finales,
                                    general: widget.general,
                                    modifieParId: AppSession.current?.id,
                                  ),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                if (ctx.mounted) {
                                  setModalState(() => enregistrement = false);
                                }
                                _message(
                                  'Modification impossible (${detailErreurFirebase(e)}). Réessayez.',
                                  erreur: true,
                                );
                              }
                            },
                      child: Text(
                        enregistrement ? 'Enregistrement…' : 'Enregistrer',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final jj = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$jj/$mm/${d.year} à $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    final connecte = widget.connecte;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _controleurTexte,
                      enabled: connecte,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FermerClavier.fermer(),
                      decoration: InputDecoration(
                        hintText: widget.libelleChampAjout,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (widget.avecQuantite) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _controleurQuantite,
                        enabled: connecte,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FermerClavier.fermer(),
                        decoration: const InputDecoration(
                          hintText: 'Qté (ex: 1 boîte de 25)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: SelecteurPhotos(
                      controleur: _photos,
                      actif: connecte && !_envoiEnCours,
                      prendre: widget.prendrePhoto,
                      choisir: widget.choisirPhotos,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (!connecte || _envoiEnCours)
                        ? null
                        : _ajouterEntree,
                    icon: _envoiEnCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
              if (!connecte) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ThemeCompagnie.teintePale(
                      Theme.of(context).colorScheme.primary,
                      0.12,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.login,
                        color: ThemeCompagnie.accentDe(context),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Connectez-vous pour ajouter ou modifier des éléments.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _afficherHistorique ? 'Historique' : 'Liste active',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _afficherHistorique = !_afficherHistorique,
                    ),
                    icon: Icon(
                      _afficherHistorique ? Icons.list : Icons.history,
                    ),
                    label: Text(
                      _afficherHistorique
                          ? 'Voir la liste active'
                          : 'Voir l\'historique',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FluxActualisable<List<MapEntry<String, Map<String, dynamic>>>>(
            creerFlux: () => widget.flux ?? _flux,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur : ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final toutes = snapshot.data!;
              var docs = toutes
                  .where(
                    (doc) =>
                        (doc.value['complete'] == true) == _afficherHistorique,
                  )
                  .toList();
              // Général : un contremaître ne voit QUE ses ajouts ; un admin, ceux
              // de la personne choisie (ou de tout le monde).
              final auteurVu = !widget.general
                  ? null
                  : (AppSession.estAdmin
                        ? _filtreAuteur
                        : AppSession.current?.id);
              if (auteurVu != null) {
                docs = docs
                    .where((doc) => doc.value['ajoutePar'] == auteurVu)
                    .toList();
              }

              if (docs.isEmpty) {
                return _avecFiltres(
                  toutes,
                  messageActualisable(
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.general
                            ? _texteVideGeneral()
                            : (_afficherHistorique
                                  ? 'Aucun historique pour ce chantier.'
                                  : 'Aucune entrée active pour ce chantier.'),
                        key: const ValueKey('liste_vide'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                );
              }
              return _avecFiltres(
                toutes,
                ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) =>
                      _tuile(docs[index], connecte),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Une entrée de la liste.
  Widget _tuile(MapEntry<String, Map<String, dynamic>> doc, bool connecte) {
    final data = doc.value;
    final complete = data['complete'] == true;
    final photos = photosDe(data);
    final quantite = data['quantite'] as String?;
    final dateComplete = data['dateComplete'] as Timestamp?;
    // Transférée à la Liste d'achats : seul un admin la modifie, jusqu'à ce qu'elle
    // soit faite (elle reste visible pour son auteur).
    final transfere = data['transfere'] == true;
    final bloquee = transfere && !AppSession.estAdmin;
    final nomTransfert = (data['transfereParNom'] ?? '').toString();

    return ListTile(
      key: ValueKey('entree_${doc.key}'),
      leading: photos.isNotEmpty
          ? VignettePhotos(urls: photos)
          : Icon(
              transfere && !complete
                  ? Icons.shopping_cart_checkout
                  : widget.icone,
              color: complete ? Colors.grey : ThemeCompagnie.accentDe(context),
            ),
      title: Text(
        data['texte'] ?? '',
        style: TextStyle(
          decoration: complete ? TextDecoration.lineThrough : null,
          color: complete ? Colors.grey : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quantite != null && quantite.isNotEmpty)
            Text('Quantité : $quantite'),
          if (widget.general &&
              AppSession.estAdmin &&
              _filtreAuteur == null &&
              (data['ajouteParNom'] ?? '').toString().isNotEmpty)
            Text(
              'Par ${data['ajouteParNom']}',
              key: ValueKey('auteur_${doc.key}'),
              style: const TextStyle(fontSize: 12),
            ),
          if (transfere && !complete)
            Text(
              nomTransfert.isEmpty
                  ? 'Dans la Liste d\'achats'
                  : 'Dans la Liste d\'achats (transféré par $nomTransfert)',
              key: ValueKey('transfere_${doc.key}'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ThemeCompagnie.accentDe(context),
              ),
            ),
          if (complete && dateComplete != null)
            Text(
              'Réglé le ${_formatDate(dateComplete)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
      trailing: bloquee
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  key: ValueKey('menu_${doc.key}'),
                  enabled: connecte,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (valeur) {
                    if (valeur == 'modifier') {
                      _ouvrirEdition(doc.key, data);
                    } else if (valeur == 'complete') {
                      _marquerComplete(doc.key, true);
                    } else if (valeur == 'actif') {
                      _marquerComplete(doc.key, false);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'modifier',
                      child: Text('Modifier'),
                    ),
                    if (!complete)
                      PopupMenuItem(
                        value: 'complete',
                        child: Text(widget.libelleComplete),
                      )
                    else
                      PopupMenuItem(
                        value: 'actif',
                        child: Text(widget.libelleActif),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: connecte
                      ? () => _confirmerSuppression(doc.key)
                      : null,
                ),
              ],
            ),
    );
  }

  /// Message de la liste vide de Général, selon la personne affichée.
  String _texteVideGeneral() {
    if (_afficherHistorique) return 'Aucun historique dans Général.';
    if (!AppSession.estAdmin) {
      return 'Aucun matériel actif dans votre liste Général.';
    }
    if (_filtreAuteur == null) return 'Aucun matériel actif dans Général.';
    if (_filtreAuteur == AppSession.current?.id) {
      return 'Aucun matériel de votre part dans Général. Touchez « Tous » '
          'pour voir celui des autres.';
    }
    return 'Aucun matériel actif de cette personne.';
  }

  /// Général : choisir qui on voit — mes ajouts, tout le monde, ou une autre
  /// personne (contremaître ou admin) qui a déjà ajouté du matériel.
  Widget _avecFiltres(
    List<MapEntry<String, Map<String, dynamic>>> toutes,
    Widget contenu,
  ) {
    // Les filtres sont réservés aux admins : un contremaître n'a que sa liste.
    if (!widget.general || !AppSession.estAdmin) return contenu;
    final moi = AppSession.current;
    final autres = <String, String>{};
    for (final e in toutes) {
      final id = e.value['ajoutePar'];
      final nom = e.value['ajouteParNom'];
      if (id is String && id.isNotEmpty && id != moi?.id && nom is String) {
        autres[id] ??= nom;
      }
    }
    final ordonnes = autres.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    Widget puce(String cle, String libelle, String? auteur) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('filtre_$cle'),
        label: Text(libelle),
        selected: _filtreAuteur == auteur,
        onSelected: (_) => setState(() => _filtreAuteur = auteur),
      ),
    );
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              if (moi != null) puce('moi', 'Mes ajouts', moi.id),
              puce('tous', 'Tous', null),
              for (final a in ordonnes) puce(a.key, a.value, a.key),
            ],
          ),
        ),
        Expanded(child: contenu),
      ],
    );
  }
}
