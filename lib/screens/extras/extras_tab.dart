import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/extra_chantier.dart';
import '../../services/app_session.dart';
import '../../services/photos.dart';
import '../../services/stockage.dart';
import '../../services/theme_compagnie.dart';
import 'formulaire_extra.dart';

/// Onglet « Extras » d'un chantier : travaux supplémentaires effectués
/// (description, nombre d'hommes, temps, date, photo facultative).
/// Admin et contremaître les saisissent ; seul un admin les supprime.
class ExtrasTab extends StatefulWidget {
  final String chantierId;
  final String companyId;
  final bool connecte;

  const ExtrasTab({
    super.key,
    required this.chantierId,
    required this.companyId,
    required this.connecte,
  });

  @override
  State<ExtrasTab> createState() => _ExtrasTabState();
}

class _ExtrasTabState extends State<ExtrasTab> {
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('chantier_extras');

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  /// Envoie la photo (dans l'app seulement, jamais dans la pellicule), puis
  /// supprime la copie temporaire. Retourne (url, chemin).
  Future<(String, String)> _envoyerPhoto(XFile photo) async {
    try {
      final octets = await photo.readAsBytes();
      final nom = '${DateTime.now().millisecondsSinceEpoch}_extra.jpg';
      final chemin =
          'chantiers/${widget.companyId}/${widget.chantierId}/chantier_extras/$nom';
      final ref = Stockage.instance.ref().child(chemin);
      await ref.putData(octets, SettableMetadata(contentType: 'image/jpeg'));
      return (await ref.getDownloadURL(), chemin);
    } finally {
      await Photos.supprimerTemporaire(photo);
    }
  }

  Future<void> _supprimerFichier(String? chemin) async {
    if (chemin == null) return;
    try {
      await Stockage.instance.ref().child(chemin).delete();
    } catch (_) {}
  }

  Future<bool> _ajouter(ExtraSaisie saisie) async {
    final employe = AppSession.current;
    if (employe == null) return false;
    String? chemin;
    try {
      String? url;
      if (saisie.nouvellePhoto != null) {
        final envoi = await _envoyerPhoto(saisie.nouvellePhoto!);
        url = envoi.$1;
        chemin = envoi.$2;
      }
      await _collection.add({
        'companyId': widget.companyId,
        'chantierId': widget.chantierId,
        'description': saisie.description,
        'mainOeuvre': saisie.mainOeuvre,
        'dateTravaux': dateIso(saisie.date),
        if (url != null) 'photoUrl': url,
        if (chemin != null) 'cheminPhoto': chemin,
        'ajoutePar': employe.id,
        'ajouteParNom': employe.nom,
        'dateAjout': FieldValue.serverTimestamp(),
      });
      _message('Extra ajouté.');
      return true;
    } catch (_) {
      // Pas de photo orpheline si la fiche n'a pas pu être créée.
      await _supprimerFichier(chemin);
      _message('Impossible d\'ajouter l\'extra. Réessayez.', erreur: true);
      return false;
    }
  }

  Future<bool> _modifier(ExtraChantier extra, ExtraSaisie saisie) async {
    String? nouveauChemin;
    try {
      final maj = <String, dynamic>{
        'description': saisie.description,
        'mainOeuvre': saisie.mainOeuvre,
        'dateTravaux': dateIso(saisie.date),
      };
      if (saisie.nouvellePhoto != null) {
        final envoi = await _envoyerPhoto(saisie.nouvellePhoto!);
        maj['photoUrl'] = envoi.$1;
        maj['cheminPhoto'] = envoi.$2;
        nouveauChemin = envoi.$2;
      } else if (saisie.retirerPhoto) {
        maj['photoUrl'] = FieldValue.delete();
        maj['cheminPhoto'] = FieldValue.delete();
      }
      await _collection.doc(extra.id).update(maj);
      // L'ancienne photo n'est supprimée qu'une fois la fiche à jour.
      if (nouveauChemin != null || saisie.retirerPhoto) {
        await _supprimerFichier(extra.cheminPhoto);
      }
      _message('Extra modifié.');
      return true;
    } catch (_) {
      await _supprimerFichier(nouveauChemin);
      _message('Impossible de modifier l\'extra. Réessayez.', erreur: true);
      return false;
    }
  }

  void _ouvrirEdition(ExtraChantier extra) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Modifier l\'extra',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              FormulaireExtra(
                initial: extra,
                connecte: widget.connecte,
                libelleBouton: 'Enregistrer',
                onValider: (saisie) async {
                  final ok = await _modifier(extra, saisie);
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                  return ok;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmerSuppression(ExtraChantier extra) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet extra ?'),
        content: const Text(
          'Cette action est irréversible : la description, le temps et la '
          'photo seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _collection.doc(extra.id).delete();
                await _supprimerFichier(extra.cheminPhoto);
                _message('Extra supprimé.');
              } catch (_) {
                _message('Suppression impossible.', erreur: true);
              }
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _voirPhoto(String url) {
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

  @override
  Widget build(BuildContext context) {
    final peutSupprimer = AppSession.estAdmin;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: FormulaireExtra(
            connecte: widget.connecte,
            libelleBouton: 'Ajouter',
            onValider: _ajouter,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _collection
                .where('companyId', isEqualTo: widget.companyId)
                .where('chantierId', isEqualTo: widget.chantierId)
                .orderBy('dateAjout', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Impossible de charger les extras.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final extras = snapshot.data!.docs
                  .map((d) => ExtraChantier.fromFirestore(d.id, d.data()))
                  .toList();
              if (extras.isEmpty) {
                return Center(
                  child: Text(
                    'Aucun extra pour ce chantier.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${extras.length} extra${extras.length > 1 ? 's' : ''}',
                        key: const ValueKey('extras_nombre'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: extras.length,
                      itemBuilder: (context, i) {
                        final e = extras[i];
                        return ListTile(
                          isThreeLine: true,
                          leading: e.photoUrl != null
                              ? GestureDetector(
                                  onTap: () => _voirPhoto(e.photoUrl!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      e.photoUrl!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.add_task,
                                  color: ThemeCompagnie.accentDe(context),
                                ),
                          title: Text(e.description),
                          subtitle: Text(
                            '${e.mainOeuvre}\n'
                            '${dateAffichee(e.dateTravaux)}'
                            '${e.ajouteParNom.isEmpty ? '' : ' • ${e.ajouteParNom}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: PopupMenuButton<String>(
                            enabled: widget.connecte,
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'modifier') {
                                _ouvrirEdition(e);
                              } else if (v == 'supprimer') {
                                _confirmerSuppression(e);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'modifier',
                                child: Text('Modifier'),
                              ),
                              if (peutSupprimer)
                                const PopupMenuItem(
                                  value: 'supprimer',
                                  child: Text(
                                    'Supprimer',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
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
