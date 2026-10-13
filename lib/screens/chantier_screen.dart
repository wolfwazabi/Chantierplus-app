import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chantier.dart';
import '../models/employee.dart';
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
import 'liste_entrees_tab.dart';
import '../services/theme_compagnie.dart';
import '../widgets/photos_multiples.dart';
import '../widgets/actualiser.dart';

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

  /// Tests : envoi des photos et sélecteurs de photos du matériel.
  @visibleForTesting
  final Televerser? televerserPhoto;
  @visibleForTesting
  final PrendrePhoto? prendrePhoto;
  @visibleForTesting
  final ChoisirPhotos? choisirPhotos;

  const ChantierScreen({
    super.key,
    this.fluxChantiers,
    this.contenuOnglet,
    this.fluxMateriel,
    this.ajouterEntree,
    this.modifierEntree,
    this.televerserPhoto,
    this.prendrePhoto,
    this.choisirPhotos,
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
    () => ListeEntreesTab(
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
      televerser: widget.televerserPhoto,
      prendrePhoto: widget.prendrePhoto,
      choisirPhotos: widget.choisirPhotos,
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

        return FluxActualisable<List<Chantier>>(
          creerFlux: () =>
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

            final chantiers = [...snapshot.data!.where((c) => !c.archive)]
              ..sort((a, b) => a.nom.compareTo(b.nom));

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
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
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
                          () => ListeEntreesTab(
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
          child: FluxActualisable<QuerySnapshot>(
            creerFlux: () => FirebaseFirestore.instance
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
