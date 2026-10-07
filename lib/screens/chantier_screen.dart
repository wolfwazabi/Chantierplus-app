import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chantier.dart';
import '../models/employee.dart';
import '../models/materiel_general.dart';
import '../services/app_session.dart';
import 'documents/documents_chantier.dart';
import 'materiaux/calcul_chantier.dart';
import '../widgets/recherche_chantier.dart';
import '../services/erreurs_firebase.dart';
import '../services/fichiers_chantier.dart';
import '../services/photos.dart';
import 'admin/grille_photos_dossier.dart';
import '../services/stockage.dart';
import 'extras/extras_tab.dart';
import '../services/theme_compagnie.dart';

class ChantierScreen extends StatefulWidget {
  /// Tests : remplace la lecture des chantiers dans Firestore.
  @visibleForTesting
  final Stream<List<Chantier>>? fluxChantiers;

  /// Tests : remplace le contenu d'un onglet ('photos', 'travaux', 'extras',
  /// 'materiel', 'documents' ou 'calcul') pour le chantier [chantierId] ; null =
  /// le vrai onglet.
  @visibleForTesting
  final Widget? Function(String onglet, String chantierId)? contenuOnglet;

  /// Tests : demandes de matériel affichées (identifiant → données), et les
  /// écritures (ajout, modification) à la place de Firestore.
  @visibleForTesting
  final Stream<List<MapEntry<String, Map<String, dynamic>>>>? fluxMateriel;
  @visibleForTesting
  final Future<void> Function(String collection, Map<String, dynamic> data)?
  ajouterEntree;
  @visibleForTesting
  final Future<void> Function(
    String collection,
    String id,
    Map<String, dynamic> data,
  )?
  modifierEntree;

  const ChantierScreen({
    super.key,
    this.fluxChantiers,
    this.contenuOnglet,
    this.fluxMateriel,
    this.ajouterEntree,
    this.modifierEntree,
  });

  @override
  State<ChantierScreen> createState() => _ChantierScreenState();
}

class _ChantierScreenState extends State<ChantierScreen> {
  Chantier? _chantierSelectionne;

  /// Contenu d'un onglet : celui des tests s'il y en a un.
  Widget _onglet(String nom, String chantierId, Widget Function() reel) =>
      widget.contenuOnglet?.call(nom, chantierId) ?? reel();

  /// Liste du matériel manquant du chantier (ou de Général).
  Widget _materiel(
    String chantierId,
    String companyId,
    bool connecte, {
    bool general = false,
  }) => _onglet(
    'materiel',
    chantierId,
    () => _ListeTab(
      chantierId: chantierId,
      companyId: companyId,
      connecte: connecte,
      collection: 'chantier_materiel',
      libelleChampAjout: 'Décrire le matériel manquant',
      libelleComplete: 'Marquer comme obtenu',
      libelleActif: 'Remettre comme manquant',
      icone: Icons.shopping_cart,
      avecQuantite: true,
      general: general,
      flux: widget.fluxMateriel,
      ajouter: widget.ajouterEntree,
      modifier: widget.modifierEntree,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Employee?>(
      valueListenable: AppSession.notifier,
      builder: (context, employee, _) {
        final companyId = employee?.companyId;
        final connecte = employee != null;

        if (companyId == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Connectez-vous pour voir les chantiers de votre compagnie.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return StreamBuilder<List<Chantier>>(
          stream:
              widget.fluxChantiers ??
              FirebaseFirestore.instance
                  .collection('chantiers')
                  .where('companyId', isEqualTo: companyId)
                  .snapshots()
                  .map(
                    (s) => [
                      for (final d in s.docs)
                        Chantier.fromFirestore(d.id, d.data()),
                    ],
                  ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Erreur : ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final chantiers = [
              ...snapshot.data!.where((c) => !c.archive),
            ]..sort((a, b) => a.nom.compareTo(b.nom));

            if (chantiers.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucun chantier n\'a été créé. Un administrateur peut en ajouter dans Admin → Chantiers.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // « Général » n'est pas un chantier de la liste : il reste choisi.
            if (_chantierSelectionne == null ||
                (_chantierSelectionne!.id != idChantierGeneral &&
                    !chantiers.any((c) => c.id == _chantierSelectionne!.id))) {
              _chantierSelectionne = chantiers.first;
            }
            final general = _chantierSelectionne!.id == idChantierGeneral;

            final selecteur = Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Chantier>(
                      // La clé suit la valeur : la liste affiche aussi
                      // un chantier choisi par la recherche « … ».
                      key: ValueKey('chantier_${_chantierSelectionne?.id}'),
                      initialValue: _chantierSelectionne,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Chantier',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          general
                              ? Icons.local_shipping_outlined
                              : Icons.construction,
                        ),
                      ),
                      items: [
                        // Seulement pour le matériel (remorque, sans chantier).
                        DropdownMenuItem(
                          key: const ValueKey('choix_general'),
                          value: chantierGeneral,
                          child: Text(
                            chantierGeneral.nom,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        for (final c in chantiers)
                          DropdownMenuItem(
                            value: c,
                            child: Text(c.nom, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (valeur) {
                        setState(() => _chantierSelectionne = valeur);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  BoutonRechercheChantier(
                    // Général reste premier dans la recherche aussi.
                    chantiers: [chantierGeneral, ...chantiers],
                    onChoisi: (c) => setState(() => _chantierSelectionne = c),
                  ),
                ],
              ),
            );

            // Général : seulement la liste de matériel (les photos, travaux,
            // extras, documents et calculs appartiennent à un vrai chantier).
            if (general) {
              return Column(
                children: [
                  selecteur,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Général : le matériel dont vous avez besoin pour la '
                            'remorque ou sans chantier précis.',
                            key: ValueKey('aide_general'),
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _materiel(
                      idChantierGeneral,
                      companyId,
                      connecte,
                      general: true,
                    ),
                  ),
                ],
              );
            }

            final chantierId = _chantierSelectionne!.id;
            return DefaultTabController(
              length: 6,
              child: Column(
                children: [
                  selecteur,
                  TabBar(
                    labelColor: ThemeCompagnie.accentDe(context),
                    indicatorColor: ThemeCompagnie.accentDe(context),
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    tabs: [
                      Tab(icon: Icon(Icons.photo_camera), text: 'Photos'),
                      Tab(
                        icon: Icon(Icons.assignment),
                        text: 'Travaux à compléter',
                      ),
                      Tab(icon: Icon(Icons.add_task), text: 'Extras'),
                      Tab(icon: Icon(Icons.shopping_cart), text: 'Matériel'),
                      Tab(icon: Icon(Icons.folder_open), text: 'Documents'),
                      Tab(icon: Icon(Icons.calculate), text: 'Calcul'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _onglet(
                          'photos',
                          chantierId,
                          () => _PhotosTab(
                            chantierId: chantierId,
                            companyId: companyId,
                            connecte: connecte,
                          ),
                        ),
                        _onglet(
                          'travaux',
                          chantierId,
                          () => _ListeTab(
                            chantierId: chantierId,
                            companyId: companyId,
                            connecte: connecte,
                            collection: 'chantier_travaux',
                            libelleChampAjout: 'Décrire le travail à compléter',
                            libelleComplete: 'Marquer comme complété',
                            libelleActif: 'Remettre en travaux',
                            icone: Icons.assignment,
                            avecQuantite: false,
                          ),
                        ),
                        _onglet(
                          'extras',
                          chantierId,
                          () => ExtrasTab(
                            key: ValueKey('extras_$chantierId'),
                            chantierId: chantierId,
                            companyId: companyId,
                            connecte: connecte,
                          ),
                        ),
                        _materiel(chantierId, companyId, connecte),
                        // Consultation seulement : le dépôt se fait dans Admin → Chantiers → Documents.
                        _onglet(
                          'documents',
                          chantierId,
                          () => DocumentsChantier(
                            key: ValueKey('docs_$chantierId'),
                            companyId: companyId,
                            chantierId: chantierId,
                            peutGerer: false,
                          ),
                        ),
                        // Calcul de feuilles et de charpente (plancher, murs, 3D, commande).
                        _onglet(
                          'calcul',
                          chantierId,
                          () => CalculChantier(
                            key: ValueKey('calcul_$chantierId'),
                            companyId: companyId,
                            chantierId: chantierId,
                            connecte: connecte,
                          ),
                        ),
                      ],
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
}

// ==================== ONGLET PHOTOS ====================

class _PhotosTab extends StatefulWidget {
  final String chantierId;
  final String companyId;
  final bool connecte;
  const _PhotosTab({
    required this.chantierId,
    required this.companyId,
    required this.connecte,
  });

  @override
  State<_PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<_PhotosTab> {
  bool _enversEnCours = false;
  double _progression = 0;

  /// Photo prise avec l'app : envoyée au serveur, jamais enregistrée dans la
  /// pellicule du téléphone.
  Future<void> _prendrePhoto() async {
    final image = await Photos.prendre();
    if (image == null) return;
    await _envoyer([image]);
  }

  Future<void> _ajouterPhotos() async {
    final images = await Photos.choisirPlusieurs();
    if (images.isEmpty) return;
    await _envoyer(images);
  }

  Future<void> _envoyer(List<XFile> images) async {
    setState(() {
      _enversEnCours = true;
      _progression = 0;
    });

    var echecs = 0;
    String? premiereCause;
    for (int i = 0; i < images.length; i++) {
      try {
        await _uploaderUnePhoto(images[i]);
      } catch (e) {
        echecs++;
        premiereCause ??= detailErreurFirebase(e);
      } finally {
        // La copie temporaire ne reste pas dans le téléphone.
        await Photos.supprimerTemporaire(images[i]);
      }
      if (mounted) setState(() => _progression = (i + 1) / images.length);
    }

    if (!mounted) return;
    setState(() => _enversEnCours = false);
    if (echecs > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            echecs == 1
                ? 'Une photo n\'a pas pu être envoyée ($premiereCause). Réessayez.'
                : '$echecs photos n\'ont pas pu être envoyées ($premiereCause). Réessayez.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploaderUnePhoto(XFile image) async {
    final Uint8List bytes = await image.readAsBytes();
    final nomFichier = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    final chemin =
        'chantiers/${widget.companyId}/${widget.chantierId}/photos/$nomFichier';

    final ref = Stockage.instance.ref().child(chemin);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection('chantier_photos').add({
      'companyId': widget.companyId,
      'chantierId': widget.chantierId,
      'url': url,
      'cheminStorage': chemin,
      'dateAjout': FieldValue.serverTimestamp(),
    });
  }

  /// Supprime les photos choisies (déjà confirmées) : fichier du Storage puis
  /// fiche, et dit à l'utilisateur ce qui a réussi.
  Future<void> _supprimer(List<PhotoDossier> photos) async {
    final messager = ScaffoldMessenger.of(context);
    final resultat = await supprimerElementsChantier(
      'chantier_photos',
      photos.map((p) => p.element),
    );
    messager.showSnackBar(
      SnackBar(
        content: Text(
          messageSuppression(
            resultat,
            singulier: 'photo supprimée',
            pluriel: 'photos supprimées',
          ),
        ),
        backgroundColor: resultat.toutSupprime ? null : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: !widget.connecte
              ? const SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: null,
                    child: Text('Connectez-vous pour ajouter des photos'),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        key: const ValueKey('photos_prendre'),
                        onPressed: _enversEnCours ? null : _prendrePhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: Text(
                          _enversEnCours
                              ? 'Envoi… ${(_progression * 100).toInt()}%'
                              : 'Prendre une photo',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        key: const ValueKey('photos_galerie'),
                        onPressed: _enversEnCours ? null : _ajouterPhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galerie'),
                      ),
                    ),
                  ],
                ),
        ),
        if (_enversEnCours)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(value: _progression),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chantier_photos')
                .where('companyId', isEqualTo: widget.companyId)
                .where('chantierId', isEqualTo: widget.chantierId)
                .orderBy('dateAjout', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur : ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Aucune photo pour ce chantier.'),
                );
              }
              // Admin et contremaître (les règles Firestore et Storage les
              // autorisent) : « Sélectionner » ou appui long, ou la photo
              // agrandie, pour supprimer une ou plusieurs photos.
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  GrillePhotosDossier(
                    key: const ValueKey('photos_grille'),
                    colonnes: 3,
                    peutSupprimer: widget.connecte && AppSession.estPlusOuAdmin,
                    photos: [
                      for (final d in docs)
                        PhotoDossier(
                          d.id,
                          ((d.data() as Map<String, dynamic>)['url'] ?? '')
                              .toString(),
                          (d.data() as Map<String, dynamic>)['cheminStorage']
                              as String?,
                        ),
                    ],
                    onSupprimer: _supprimer,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ==================== ONGLET LISTE (Travaux / Matériel) ====================

class _ListeTab extends StatefulWidget {
  final String chantierId;
  final String companyId;
  final bool connecte;
  final String collection;
  final String libelleChampAjout;
  final String libelleComplete;
  final String libelleActif;
  final IconData icone;
  final bool avecQuantite;

  /// Liste « Général » (remorque, sans chantier) : chaque entrée porte son auteur
  /// et la liste se filtre par personne.
  final bool general;

  /// Tests : remplacent la lecture et les écritures Firestore.
  final Stream<List<MapEntry<String, Map<String, dynamic>>>>? flux;
  final Future<void> Function(String collection, Map<String, dynamic> data)?
  ajouter;
  final Future<void> Function(
    String collection,
    String id,
    Map<String, dynamic> data,
  )?
  modifier;

  const _ListeTab({
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
  });

  @override
  State<_ListeTab> createState() => _ListeTabState();
}

class _ListeTabState extends State<_ListeTab> {
  final _controleurTexte = TextEditingController();
  final _controleurQuantite = TextEditingController();
  XFile? _photoChoisie;
  Uint8List? _photoApercu;
  bool _envoiEnCours = false;
  bool _afficherHistorique = false;

  /// Général : l'auteur affiché (par défaut moi-même ; null = tout le monde).
  String? _filtreAuteur;

  @override
  void initState() {
    super.initState();
    if (widget.general) _filtreAuteur = AppSession.current?.id;
  }

  Future<void> _choisirPhoto({
    required void Function(XFile, Uint8List) onChoisie,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      // Photo prise avec l'app : jamais copiée dans la pellicule du téléphone.
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choisir depuis la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? image = source == ImageSource.camera
        ? await Photos.prendre()
        : await Photos.choisir();
    if (image == null) return;
    final bytes = await image.readAsBytes();
    onChoisie(image, bytes);
  }

  void _retirerPhoto() {
    final abandonnee = _photoChoisie;
    if (abandonnee != null) Photos.supprimerTemporaire(abandonnee);
    setState(() {
      _photoChoisie = null;
      _photoApercu = null;
    });
  }

  Future<String?> _uploaderPhoto(XFile photo) async {
    try {
      final bytes = await photo.readAsBytes();
      final nomFichier =
          '${DateTime.now().millisecondsSinceEpoch}_${photo.name}';
      final chemin =
          'chantiers/${widget.companyId}/${widget.chantierId}/${widget.collection}/$nomFichier';
      final ref = Stockage.instance.ref().child(chemin);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } finally {
      // La copie temporaire ne reste pas dans le téléphone.
      await Photos.supprimerTemporaire(photo);
    }
  }

  Future<void> _ajouterEntree() async {
    final texte = _controleurTexte.text.trim();
    if (texte.isEmpty) return;

    setState(() => _envoiEnCours = true);

    final avaitPhoto = _photoChoisie != null;
    try {
      String? photoUrl;
      if (_photoChoisie != null) {
        photoUrl = await _uploaderPhoto(_photoChoisie!);
      }

      // Général : l'entrée porte son auteur (id et nom de l'employé connecté).
      final data = donneesNouvelleEntree(
        companyId: widget.companyId,
        chantierId: widget.chantierId,
        texte: texte,
        quantite: widget.avecQuantite ? _controleurQuantite.text.trim() : null,
        photoUrl: photoUrl,
        auteur: widget.general ? AppSession.current : null,
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
      // Le texte reste à l'écran pour réessayer ; la copie temporaire de la
      // photo est déjà supprimée, il faut la choisir de nouveau.
      if (!mounted) return;
      setState(() {
        _envoiEnCours = false;
        if (avaitPhoto) {
          _photoChoisie = null;
          _photoApercu = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'L\'entrée n\'a pas pu être ajoutée (${detailErreurFirebase(e)}). '
            'Réessayez${avaitPhoto ? ' et rajoutez la photo' : ''}.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    _controleurTexte.clear();
    _controleurQuantite.clear();
    setState(() {
      _photoChoisie = null;
      _photoApercu = null;
      _envoiEnCours = false;
    });
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
    XFile? nouvellePhoto;
    Uint8List? nouvelApercu;
    String? photoUrlActuelle = data['photoUrl'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Description',
                    ),
                  ),
                  if (widget.avecQuantite) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantiteCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Quantité',
                        hintText: 'ex: 1 boîte de 25, 2 rouleaux',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (nouvelApercu != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              nouvelApercu!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else if (photoUrlActuelle != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              photoUrlActuelle,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _choisirPhoto(
                          onChoisie: (photo, bytes) {
                            setModalState(() {
                              nouvellePhoto = photo;
                              nouvelApercu = bytes;
                            });
                          },
                        ),
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('Changer la photo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        String? photoUrl;
                        if (nouvellePhoto != null) {
                          photoUrl = await _uploaderPhoto(nouvellePhoto!);
                        }
                        await _ecrireModification(
                          docId,
                          donneesModification(
                            texte: texteCtrl.text.trim(),
                            quantite: widget.avecQuantite
                                ? quantiteCtrl.text.trim()
                                : null,
                            photoUrl: photoUrl,
                            general: widget.general,
                            modifieParId: AppSession.current?.id,
                          ),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Enregistrer'),
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
                children: [
                  if (_photoApercu != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _photoApercu!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            icon: const Icon(
                              Icons.cancel,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: _retirerPhoto,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: connecte
                        ? () => _choisirPhoto(
                            onChoisie: (photo, bytes) {
                              setState(() {
                                _photoChoisie = photo;
                                _photoApercu = bytes;
                              });
                            },
                          )
                        : null,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(
                      _photoApercu == null
                          ? 'Ajouter une photo'
                          : 'Changer la photo',
                    ),
                  ),
                  const Spacer(),
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
                      SizedBox(width: 8),
                      Expanded(
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
          child: StreamBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
            stream:
                widget.flux ??
                FirebaseFirestore.instance
                    .collection(widget.collection)
                    .where('companyId', isEqualTo: widget.companyId)
                    .where('chantierId', isEqualTo: widget.chantierId)
                    .orderBy('dateAjout', descending: true)
                    .snapshots()
                    .map(
                      (s) => [
                        for (final d in s.docs) MapEntry(d.id, d.data()),
                      ],
                    ),
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
              // Général : seulement les ajouts de la personne choisie.
              if (widget.general && _filtreAuteur != null) {
                docs = docs
                    .where((doc) => doc.value['ajoutePar'] == _filtreAuteur)
                    .toList();
              }

              if (docs.isEmpty) {
                return _avecFiltres(
                  toutes,
                  Center(
                    child: Padding(
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
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.value;
                  final complete = data['complete'] == true;
                  final photoUrl = data['photoUrl'] as String?;
                  final quantite = data['quantite'] as String?;
                  final dateComplete = data['dateComplete'] as Timestamp?;

                  return ListTile(
                    leading: photoUrl != null
                        ? GestureDetector(
                            onTap: () => _voirPhotoPleinEcran(photoUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                photoUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : Icon(
                            widget.icone,
                            color: complete
                                ? Colors.grey
                                : ThemeCompagnie.accentDe(context),
                          ),
                    title: Text(
                      data['texte'] ?? '',
                      style: TextStyle(
                        decoration: complete
                            ? TextDecoration.lineThrough
                            : null,
                        color: complete ? Colors.grey : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (quantite != null && quantite.isNotEmpty)
                          Text('Quantité : $quantite'),
                        if (widget.general &&
                            _filtreAuteur == null &&
                            (data['ajouteParNom'] ?? '').toString().isNotEmpty)
                          Text(
                            'Par ${data['ajouteParNom']}',
                            key: ValueKey('auteur_${doc.key}'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (complete && dateComplete != null)
                          Text(
                            'Réglé le ${_formatDate(dateComplete)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
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
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: connecte
                              ? () => _confirmerSuppression(doc.key)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Message de la liste vide de Général, selon la personne affichée.
  String _texteVideGeneral() {
    if (_afficherHistorique) return 'Aucun historique dans Général.';
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
    if (!widget.general) return contenu;
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

  void _voirPhotoPleinEcran(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.network(url)),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
