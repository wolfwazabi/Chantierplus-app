import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chantier.dart';
import '../models/employee.dart';
import '../services/app_session.dart';
import 'documents/documents_chantier.dart';
import 'materiaux/calcul_materiaux.dart';
import '../widgets/recherche_chantier.dart';
import '../services/theme_compagnie.dart';

class ChantierScreen extends StatefulWidget {
  const ChantierScreen({super.key});

  @override
  State<ChantierScreen> createState() => _ChantierScreenState();
}

class _ChantierScreenState extends State<ChantierScreen> {
  Chantier? _chantierSelectionne;

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

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chantiers')
              .where('companyId', isEqualTo: companyId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Erreur : ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final chantiers =
                snapshot.data!.docs
                    .map(
                      (d) => Chantier.fromFirestore(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .toList()
                  ..sort((a, b) => a.nom.compareTo(b.nom));

            if (chantiers.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucun chantier n\'a été créé. Un administrateur peut en ajouter dans Admin → Gérer les chantiers.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (_chantierSelectionne == null ||
                !chantiers.any((c) => c.id == _chantierSelectionne!.id)) {
              _chantierSelectionne = chantiers.first;
            }

            return DefaultTabController(
              length: 5,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Chantier>(
                            // La clé suit la valeur : la liste affiche aussi
                            // un chantier choisi par la recherche « … ».
                            key: ValueKey(
                              'chantier_${_chantierSelectionne?.id}',
                            ),
                            initialValue: _chantierSelectionne,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Chantier',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.construction),
                            ),
                            items: chantiers.map((c) {
                              return DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c.nom,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (valeur) {
                              setState(() => _chantierSelectionne = valeur);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        BoutonRechercheChantier(
                          chantiers: chantiers,
                          onChoisi: (c) =>
                              setState(() => _chantierSelectionne = c),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    labelColor: ThemeCompagnie.accentDe(context),
                    indicatorColor: ThemeCompagnie.accentDe(context),
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    tabs: [
                      Tab(icon: Icon(Icons.photo_camera), text: 'Photos'),
                      Tab(icon: Icon(Icons.assignment), text: 'Travaux'),
                      Tab(icon: Icon(Icons.shopping_cart), text: 'Matériel'),
                      Tab(icon: Icon(Icons.folder_open), text: 'Documents'),
                      Tab(icon: Icon(Icons.calculate), text: 'Calcul'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _PhotosTab(
                          chantierId: _chantierSelectionne!.id,
                          companyId: companyId,
                          connecte: connecte,
                        ),
                        _ListeTab(
                          chantierId: _chantierSelectionne!.id,
                          companyId: companyId,
                          connecte: connecte,
                          collection: 'chantier_travaux',
                          libelleChampAjout: 'Décrire le travail à compléter',
                          libelleComplete: 'Marquer comme complété',
                          libelleActif: 'Remettre en travaux',
                          icone: Icons.assignment,
                          avecQuantite: false,
                        ),
                        _ListeTab(
                          chantierId: _chantierSelectionne!.id,
                          companyId: companyId,
                          connecte: connecte,
                          collection: 'chantier_materiel',
                          libelleChampAjout: 'Décrire le matériel manquant',
                          libelleComplete: 'Marquer comme obtenu',
                          libelleActif: 'Remettre comme manquant',
                          icone: Icons.shopping_cart,
                          avecQuantite: true,
                        ),
                        // Consultation seulement : le dépôt se fait dans l'onglet Admin.
                        DocumentsChantier(
                          key: ValueKey('docs_${_chantierSelectionne!.id}'),
                          companyId: companyId,
                          chantierId: _chantierSelectionne!.id,
                          peutGerer: false,
                        ),
                        // Calcul de matériaux (feuilles), ex-onglet de la calculatrice.
                        const CalculMateriaux(),
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

  Future<void> _ajouterPhotos() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 80);
    if (images.isEmpty) return;

    setState(() {
      _enversEnCours = true;
      _progression = 0;
    });

    for (int i = 0; i < images.length; i++) {
      await _uploaderUnePhoto(images[i]);
      setState(() => _progression = (i + 1) / images.length);
    }

    setState(() => _enversEnCours = false);
  }

  Future<void> _uploaderUnePhoto(XFile image) async {
    final Uint8List bytes = await image.readAsBytes();
    final nomFichier = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    final chemin =
        'chantiers/${widget.companyId}/${widget.chantierId}/photos/$nomFichier';

    final ref = FirebaseStorage.instance.ref().child(chemin);
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

  Future<void> _supprimerPhoto(String docId, String cheminStorage) async {
    await FirebaseFirestore.instance
        .collection('chantier_photos')
        .doc(docId)
        .delete();
    try {
      await FirebaseStorage.instance.ref().child(cheminStorage).delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (!widget.connecte || _enversEnCours)
                  ? null
                  : _ajouterPhotos,
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                !widget.connecte
                    ? 'Connectez-vous pour ajouter des photos'
                    : (_enversEnCours
                          ? 'Envoi en cours... ${(_progression * 100).toInt()}%'
                          : 'Ajouter des photos'),
              ),
            ),
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
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return GestureDetector(
                    onLongPress: widget.connecte
                        ? () => _confirmerSuppression(
                            doc.id,
                            data['cheminStorage'],
                          )
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(data['url'], fit: BoxFit.cover),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmerSuppression(String docId, String cheminStorage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _supprimerPhoto(docId, cheminStorage);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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

  Future<void> _choisirPhoto({
    required void Function(XFile, Uint8List) onChoisie,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
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
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    onChoisie(image, bytes);
  }

  void _retirerPhoto() {
    setState(() {
      _photoChoisie = null;
      _photoApercu = null;
    });
  }

  Future<String?> _uploaderPhoto(XFile photo) async {
    final bytes = await photo.readAsBytes();
    final nomFichier = '${DateTime.now().millisecondsSinceEpoch}_${photo.name}';
    final chemin =
        'chantiers/${widget.companyId}/${widget.chantierId}/${widget.collection}/$nomFichier';
    final ref = FirebaseStorage.instance.ref().child(chemin);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> _ajouterEntree() async {
    final texte = _controleurTexte.text.trim();
    if (texte.isEmpty) return;

    setState(() => _envoiEnCours = true);

    String? photoUrl;
    if (_photoChoisie != null) {
      photoUrl = await _uploaderPhoto(_photoChoisie!);
    }

    final data = <String, dynamic>{
      'companyId': widget.companyId,
      'chantierId': widget.chantierId,
      'texte': texte,
      'complete': false,
      'dateAjout': FieldValue.serverTimestamp(),
      if (photoUrl != null) 'photoUrl': photoUrl,
    };

    if (widget.avecQuantite) {
      final quantite = _controleurQuantite.text.trim();
      if (quantite.isNotEmpty) {
        data['quantite'] = quantite;
      }
    }

    await FirebaseFirestore.instance.collection(widget.collection).add(data);

    _controleurTexte.clear();
    _controleurQuantite.clear();
    setState(() {
      _photoChoisie = null;
      _photoApercu = null;
      _envoiEnCours = false;
    });
  }

  Future<void> _marquerComplete(String docId, bool complete) async {
    await FirebaseFirestore.instance
        .collection(widget.collection)
        .doc(docId)
        .update({
          'complete': complete,
          'dateComplete': complete
              ? FieldValue.serverTimestamp()
              : FieldValue.delete(),
        });
  }

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
                        final updateData = <String, dynamic>{
                          'texte': texteCtrl.text.trim(),
                        };
                        if (widget.avecQuantite) {
                          updateData['quantite'] = quantiteCtrl.text.trim();
                        }
                        if (nouvellePhoto != null) {
                          updateData['photoUrl'] = await _uploaderPhoto(
                            nouvellePhoto!,
                          );
                        }
                        await FirebaseFirestore.instance
                            .collection(widget.collection)
                            .doc(docId)
                            .update(updateData);
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
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(widget.collection)
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
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final complete = data['complete'] == true;
                return complete == _afficherHistorique;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    _afficherHistorique
                        ? 'Aucun historique pour ce chantier.'
                        : 'Aucune entrée active pour ce chantier.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
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
                              _ouvrirEdition(doc.id, data);
                            } else if (valeur == 'complete') {
                              _marquerComplete(doc.id, true);
                            } else if (valeur == 'actif') {
                              _marquerComplete(doc.id, false);
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
                              ? () => _confirmerSuppression(doc.id)
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
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
