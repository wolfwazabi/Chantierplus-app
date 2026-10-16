import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chantier.dart';
import '../../models/resume_chantier.dart';
import '../../services/app_session.dart';
import '../../services/fonctions.dart';
import '../../services/theme_compagnie.dart';
import '../chantier_screen.dart' show PhotosChantierTab;
import '../documents/documents_chantier.dart';
import '../extras/extras_tab.dart';
import '../liste_entrees_tab.dart';
import 'chantier_admin_actions.dart';
import 'resume_heures_carte.dart';
import '../../widgets/actualiser.dart';

/// Page d'un chantier pour l'admin, avec tout ce qui le concerne, et où il gère les données :
///  - Résumé : heures, export du dossier (ZIP) ;
///  - Photos : en ajouter (appareil ou galerie), agrandir, sélectionner et supprimer ;
///  - Extras, Travaux, Matériel : en ajouter, les modifier, les supprimer (mêmes écrans que sur
///    le terrain ; un extra ne se supprime que par un admin) ;
///  - Documents : déposer, ouvrir et supprimer des plans, devis, etc.
/// Le menu en haut permet de modifier ou d'archiver le chantier. Fonctionne aussi
/// pour un chantier archivé (le dossier reste complet).
class DossierChantierScreen extends StatefulWidget {
  final Chantier chantier;

  /// Tests : remplacent les lectures Firestore et fonctions (le chantier en
  /// direct et le contenu de chaque onglet).
  @visibleForTesting
  final Stream<Chantier?>? fluxChantier;
  @visibleForTesting
  final Widget Function(String companyId, Chantier c)? contenuResume;
  @visibleForTesting
  final Widget Function(String companyId, Chantier c)? contenuPhotos;
  @visibleForTesting
  final Widget Function(String companyId, Chantier c)? contenuDocuments;

  /// Tests : le contenu des onglets 'extras', 'travaux' et 'materiel'.
  @visibleForTesting
  final Widget Function(String onglet, String companyId, Chantier c)?
  contenuOnglet;

  const DossierChantierScreen({
    super.key,
    required this.chantier,
    this.fluxChantier,
    this.contenuResume,
    this.contenuPhotos,
    this.contenuDocuments,
    this.contenuOnglet,
  });

  @override
  State<DossierChantierScreen> createState() => _DossierChantierScreenState();
}

class _DossierChantierScreenState extends State<DossierChantierScreen> {
  ResumeChantier? _resume;
  String? _erreur;
  bool _chargement = true;
  bool _exportEnCours = false;

  @override
  void initState() {
    super.initState();
    if (widget.contenuResume == null) _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final data = await Fonctions.appeler('resumeChantier', {
        'chantierId': widget.chantier.id,
      });
      if (!mounted) return;
      setState(() {
        _resume = ResumeChantier.fromMap(data);
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = Fonctions.message(e, 'Impossible de charger le résumé.');
        _chargement = false;
      });
    }
  }

  Future<void> _exporter() async {
    setState(() => _exportEnCours = true);
    final messager = ScaffoldMessenger.of(context);
    try {
      final data = await Fonctions.appeler('exporterChantier', {
        'chantierId': widget.chantier.id,
      });
      final export = ExportChantier.fromMap(data);
      final lien = Uri.tryParse(export.url);
      if (lien == null || lien.scheme != 'https') {
        throw Exception('lien invalide');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dossier prêt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${export.nom}\n${formatTaille(export.taille)} • '
                '${export.fichiers} fichier${export.fichiers > 1 ? 's' : ''}',
              ),
              const SizedBox(height: 10),
              const Text(
                'Le téléchargement s\'ouvre dans le navigateur. Enregistrez le '
                'fichier ZIP, puis ouvrez Resume.html (résumé imprimable) et '
                'Dossier.xlsx (Excel, heures et tableaux). Le lien expire dans '
                'quelques heures.',
                style: TextStyle(fontSize: 13),
              ),
              if (export.ignores.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${export.ignores.length} fichier'
                  '${export.ignores.length > 1 ? 's' : ''} non inclus '
                  '(voir fichiers_non_inclus.txt dans le ZIP).',
                  key: const ValueKey('export_ignores'),
                  style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await launchUrl(
                  lien,
                  mode: LaunchMode.externalApplication,
                );
                if (!ok) {
                  messager.showSnackBar(
                    const SnackBar(
                      content: Text('Impossible d\'ouvrir le téléchargement.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Télécharger'),
            ),
          ],
        ),
      );
    } catch (e) {
      messager.showSnackBar(
        SnackBar(
          content: Text(Fonctions.message(e, 'L\'export a échoué. Réessayez.')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  /// Onglet Résumé : état du chantier, export, heures (les extras, le matériel et les travaux
  /// ont leurs onglets, où on les gère).
  Widget _ongletResume(Chantier c, String companyId) {
    return PageActualisable(
      onRefresh: _charger,
      child: ListView(
        key: const ValueKey('onglet_resume'),
        padding: const EdgeInsets.all(16),
        children: [
          if (c.archive)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Chantier archivé',
                    key: const ValueKey('bandeau_archive'),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          if (c.adresse.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                c.adresse,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('dossier_exporter'),
              onPressed: _exportEnCours ? null : _exporter,
              icon: _exportEnCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.archive_outlined),
              label: Text(
                _exportEnCours
                    ? 'Préparation de l\'export…'
                    : 'Exporter le dossier (ZIP)',
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              'Résumé des heures, extras, matériel, photos et documents, à garder '
              'sur l\'ordinateur de la compagnie.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_erreur != null)
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.cloud_off),
                title: Text(_erreur!),
                trailing: TextButton(
                  onPressed: _charger,
                  child: const Text('Réessayer'),
                ),
              ),
            )
          else if (_resume != null)
            ResumeHeuresCarte(resume: _resume!),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;
    if (companyId == null || !AppSession.estAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chantier.nom)),
        body: const Center(child: Text('Réservé aux administrateurs.')),
      );
    }
    // Le chantier est suivi en direct : le nom, l'adresse et l'archivage
    // modifiés depuis le menu se voient tout de suite.
    return StreamBuilder<Chantier?>(
      stream:
          widget.fluxChantier ??
          FirebaseFirestore.instance
              .collection('chantiers')
              .doc(widget.chantier.id)
              .snapshots()
              .map((d) {
                final data = d.data();
                return data == null
                    ? null
                    : Chantier.fromFirestore(widget.chantier.id, data);
              }),
      builder: (context, snap) {
        final c = snap.data ?? widget.chantier;
        final theme = Theme.of(context);
        final couleursOnglets = ThemeCompagnie.ongletsSurBarre(
          theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        );
        Widget onglet(String nom, Widget Function() reel) =>
            widget.contenuOnglet?.call(nom, companyId, c) ?? reel();
        return DefaultTabController(
          length: 6,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.nom, overflow: TextOverflow.ellipsis),
              actions: [
                PopupMenuButton<String>(
                  key: const ValueKey('dossier_menu'),
                  onSelected: (v) {
                    if (v == 'modifier') {
                      ouvrirFormulaireChantier(
                        context,
                        docId: c.id,
                        donnees: {'nom': c.nom, 'adresse': c.adresse},
                      );
                    } else {
                      archiverOuRestaurerChantier(
                        context,
                        docId: c.id,
                        nom: c.nom,
                        archiver: !c.archive,
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'modifier',
                      child: Text('Modifier le chantier'),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        c.archive
                            ? 'Restaurer le chantier'
                            : 'Archiver le chantier',
                      ),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(
                key: const ValueKey('onglets_chantier'),
                // Lisibles sur la barre de la compagnie (pas vert sur vert).
                labelColor: couleursOnglets.actif,
                unselectedLabelColor: couleursOnglets.inactif,
                indicatorColor: couleursOnglets.actif,
                // Six onglets : ils défilent sur un téléphone.
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.assessment_outlined), text: 'Résumé'),
                  Tab(icon: Icon(Icons.photo_library_outlined), text: 'Photos'),
                  Tab(icon: Icon(Icons.add_task), text: 'Extras'),
                  Tab(icon: Icon(Icons.assignment_outlined), text: 'Travaux'),
                  Tab(
                    icon: Icon(Icons.shopping_cart_outlined),
                    text: 'Matériel',
                  ),
                  Tab(
                    icon: Icon(Icons.description_outlined),
                    text: 'Documents',
                  ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _GardeEnVie(
                  child:
                      widget.contenuResume?.call(companyId, c) ??
                      _ongletResume(c, companyId),
                ),
                _GardeEnVie(
                  // Ajouter des photos (appareil ou galerie), les agrandir, en supprimer.
                  child:
                      widget.contenuPhotos?.call(companyId, c) ??
                      PhotosChantierTab(
                        key: const ValueKey('onglet_photos'),
                        chantierId: c.id,
                        companyId: companyId,
                        connecte: true,
                      ),
                ),
                _GardeEnVie(
                  child: onglet(
                    'extras',
                    () => ExtrasTab(
                      key: ValueKey('extras_${c.id}'),
                      chantierId: c.id,
                      companyId: companyId,
                      connecte: true,
                    ),
                  ),
                ),
                _GardeEnVie(
                  child: onglet(
                    'travaux',
                    () => ListeEntreesTab(
                      key: ValueKey('travaux_${c.id}'),
                      chantierId: c.id,
                      companyId: companyId,
                      connecte: true,
                      collection: 'chantier_travaux',
                      libelleChampAjout: 'Décrire le travail à compléter',
                      libelleComplete: 'Marquer comme complété',
                      libelleActif: 'Remettre en travaux',
                      icone: Icons.assignment,
                      avecQuantite: false,
                    ),
                  ),
                ),
                _GardeEnVie(
                  child: onglet(
                    'materiel',
                    () => ListeEntreesTab(
                      key: ValueKey('materiel_${c.id}'),
                      chantierId: c.id,
                      companyId: companyId,
                      connecte: true,
                      collection: 'chantier_materiel',
                      libelleChampAjout: 'Décrire le matériel manquant',
                      libelleComplete: 'Marquer comme obtenu',
                      libelleActif: 'Remettre comme manquant',
                      icone: Icons.shopping_cart,
                      avecQuantite: true,
                    ),
                  ),
                ),
                _GardeEnVie(
                  // Dépôt, ouverture et suppression des documents (admin).
                  child:
                      widget.contenuDocuments?.call(companyId, c) ??
                      DocumentsChantier(
                        key: ValueKey('docs_${c.id}'),
                        companyId: companyId,
                        chantierId: c.id,
                        peutGerer: true,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Garde l'état d'un onglet quand on passe à un autre (un envoi de document en
/// cours, une sélection de photos).
class _GardeEnVie extends StatefulWidget {
  final Widget child;
  const _GardeEnVie({required this.child});

  @override
  State<_GardeEnVie> createState() => _GardeEnVieState();
}

class _GardeEnVieState extends State<_GardeEnVie>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
