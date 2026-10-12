import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/extra_chantier.dart';
import '../../services/app_session.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/photos_multiples.dart';
import 'formulaire_extra.dart';

/// Onglet « Extras » d'un chantier : travaux supplémentaires effectués
/// (description, nombre d'hommes, temps, date, jusqu'à 6 photos).
/// Admin et contremaître les saisissent ; seul un admin les supprime.
class ExtrasTab extends StatefulWidget {
  final String chantierId;
  final String companyId;
  final bool connecte;

  /// Tests : remplacent la lecture, les écritures, l'envoi des photos et leurs
  /// sélecteurs.
  @visibleForTesting
  final Stream<List<ExtraChantier>>? flux;
  @visibleForTesting
  final Future<void> Function(Map<String, dynamic> donnees)? ajouterDoc;
  @visibleForTesting
  final Future<void> Function(String id, Map<String, dynamic> donnees)? modifierDoc;
  @visibleForTesting
  final Future<void> Function(String id)? supprimerDoc;
  @visibleForTesting
  final Televerser? televerser;
  @visibleForTesting
  final SupprimerPhoto? supprimerFichier;
  @visibleForTesting
  final PrendrePhoto? prendrePhoto;
  @visibleForTesting
  final ChoisirPhotos? choisirPhotos;

  const ExtrasTab({
    super.key,
    required this.chantierId,
    required this.companyId,
    required this.connecte,
    this.flux,
    this.ajouterDoc,
    this.modifierDoc,
    this.supprimerDoc,
    this.televerser,
    this.supprimerFichier,
    this.prendrePhoto,
    this.choisirPhotos,
  });

  @override
  State<ExtrasTab> createState() => _ExtrasTabState();
}

class _ExtrasTabState extends State<ExtrasTab> {
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('chantier_extras');

  String get _dossierPhotos =>
      'chantiers/${widget.companyId}/${widget.chantierId}/chantier_extras';

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  Future<List<PhotoEnvoyee>> _envoyer(List<PhotoEnAttente> photos) =>
      televerserPhotos(
        photos,
        dossier: _dossierPhotos,
        televerser: widget.televerser,
        supprimer: widget.supprimerFichier,
      );

  Future<void> _supprimerFichiers(Iterable<String> chemins) =>
      supprimerPhotosStorage(
        chemins.where((c) => c.isNotEmpty),
        supprimer: widget.supprimerFichier,
      );

  Future<bool> _ajouter(ExtraSaisie saisie) async {
    final employe = AppSession.current;
    if (employe == null) return false;
    var envoyees = <PhotoEnvoyee>[];
    try {
      envoyees = await _envoyer(saisie.nouvelles);
      final donnees = <String, dynamic>{
        'companyId': widget.companyId,
        'chantierId': widget.chantierId,
        'description': saisie.description,
        'mainOeuvre': saisie.mainOeuvre,
        'dateTravaux': dateIso(saisie.date),
        ...champsPhotosExtra(
          [for (final p in envoyees) p.url],
          [for (final p in envoyees) p.chemin],
        ),
        'ajoutePar': employe.id,
        'ajouteParNom': employe.nom,
        'dateAjout': FieldValue.serverTimestamp(),
      };
      final ajouter = widget.ajouterDoc;
      if (ajouter != null) {
        await ajouter(donnees);
      } else {
        await _collection.add(donnees);
      }
      _message('Extra ajouté.');
      return true;
    } catch (_) {
      // Pas de photo orpheline si la fiche n'a pas pu être créée.
      await _supprimerFichiers([for (final p in envoyees) p.chemin]);
      _message('Impossible d\'ajouter l\'extra. Réessayez.', erreur: true);
      return false;
    }
  }

  Future<bool> _modifier(ExtraChantier extra, ExtraSaisie saisie) async {
    var envoyees = <PhotoEnvoyee>[];
    try {
      final maj = <String, dynamic>{
        'description': saisie.description,
        'mainOeuvre': saisie.mainOeuvre,
        'dateTravaux': dateIso(saisie.date),
      };
      // Photos gardées (avec leur chemin) puis nouvelles ; touchées seulement si
      // elles ont changé.
      final gardees = saisie.conservees;
      final changees =
          saisie.nouvelles.isNotEmpty ||
          gardees.length != extra.photos.length ||
          !_memeListe(gardees, extra.photos);
      var retirees = <String>[];
      if (changees) {
        envoyees = await _envoyer(saisie.nouvelles);
        maj.addAll(
          champsPhotosExtraModification(
            [...gardees, for (final p in envoyees) p.url],
            [
              for (final u in gardees) extra.cheminDe(u) ?? '',
              for (final p in envoyees) p.chemin,
            ],
          ),
        );
        retirees = [
          for (var i = 0; i < extra.photos.length; i++)
            if (!gardees.contains(extra.photos[i]) && i < extra.chemins.length)
              extra.chemins[i],
        ];
      }
      final modifier = widget.modifierDoc;
      if (modifier != null) {
        await modifier(extra.id, maj);
      } else {
        await _collection.doc(extra.id).update(maj);
      }
      // Les photos retirées ne sont supprimées qu'une fois la fiche à jour.
      await _supprimerFichiers(retirees);
      _message('Extra modifié.');
      return true;
    } catch (_) {
      await _supprimerFichiers([for (final p in envoyees) p.chemin]);
      _message('Impossible de modifier l\'extra. Réessayez.', erreur: true);
      return false;
    }
  }

  static bool _memeListe(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
                prendrePhoto: widget.prendrePhoto,
                choisirPhotos: widget.choisirPhotos,
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
          'Cette action est irréversible : la description, le temps et les '
          'photos seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const ValueKey('extra_confirmer_suppression'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final supprimer = widget.supprimerDoc;
                if (supprimer != null) {
                  await supprimer(extra.id);
                } else {
                  await _collection.doc(extra.id).delete();
                }
                await _supprimerFichiers(extra.chemins);
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

  Stream<List<ExtraChantier>> get _lecture =>
      widget.flux ??
      _collection
          .where('companyId', isEqualTo: widget.companyId)
          .where('chantierId', isEqualTo: widget.chantierId)
          .orderBy('dateAjout', descending: true)
          .snapshots()
          .map(
            (s) => [
              for (final d in s.docs) ExtraChantier.fromFirestore(d.id, d.data()),
            ],
          );

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
            prendrePhoto: widget.prendrePhoto,
            choisirPhotos: widget.choisirPhotos,
            onValider: _ajouter,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<ExtraChantier>>(
            stream: _lecture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Impossible de charger les extras.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final extras = snapshot.data!;
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
                          key: ValueKey('extra_${e.id}'),
                          isThreeLine: true,
                          leading: e.photos.isNotEmpty
                              ? VignettePhotos(urls: e.photos)
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
                            key: ValueKey('extra_menu_${e.id}'),
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
