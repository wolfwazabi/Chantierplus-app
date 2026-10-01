import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chantier.dart';
import '../../models/extra_chantier.dart';
import '../../models/resume_chantier.dart';
import '../../services/app_session.dart';
import '../../services/fonctions.dart';
import '../../services/theme_compagnie.dart';
import 'resume_heures_carte.dart';

/// Dossier d'un chantier pour l'admin : résumé des heures, extras, matériel et
/// photos, même si le chantier est archivé. Permet de préparer la facture et
/// d'exporter tout le dossier (ZIP) pour le garder sur l'ordinateur.
class DossierChantierScreen extends StatefulWidget {
  final Chantier chantier;
  const DossierChantierScreen({super.key, required this.chantier});

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
    _charger();
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

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;
    final c = widget.chantier;
    return Scaffold(
      appBar: AppBar(title: Text(c.nom, overflow: TextOverflow.ellipsis)),
      body: companyId == null || !AppSession.estAdmin
          ? const Center(child: Text('Réservé aux administrateurs.'))
          : ListView(
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
                  padding: EdgeInsets.only(top: 6, bottom: 12),
                  child: Text(
                    'Résumé des heures, extras, matériel et photos, à garder sur l\'ordinateur de la compagnie.',
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
                const SizedBox(height: 8),
                _SectionExtras(companyId: companyId, chantierId: c.id),
                _SectionMateriel(companyId: companyId, chantierId: c.id),
                _SectionTravaux(companyId: companyId, chantierId: c.id),
                _SectionDocuments(companyId: companyId, chantierId: c.id),
                _SectionPhotos(companyId: companyId, chantierId: c.id),
              ],
            ),
    );
  }
}

Query<Map<String, dynamic>> _requete(
  String collection,
  String companyId,
  String chantierId,
) => FirebaseFirestore.instance
    .collection(collection)
    .where('companyId', isEqualTo: companyId)
    .where('chantierId', isEqualTo: chantierId)
    .orderBy('dateAjout', descending: true);

void _voirPhoto(BuildContext context, String url) {
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

Widget _titreSection(String titre, int? n) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
  child: Text(
    n == null ? titre : '$titre ($n)',
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  ),
);

Widget _vide(String texte) => Padding(
  padding: const EdgeInsets.all(8),
  child: Text(texte, style: TextStyle(color: Colors.grey.shade600)),
);

class _SectionExtras extends StatelessWidget {
  final String companyId;
  final String chantierId;
  const _SectionExtras({required this.companyId, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requete('chantier_extras', companyId, chantierId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _vide('Impossible de charger les extras.');
        final extras = (snap.data?.docs ?? [])
            .map((d) => ExtraChantier.fromFirestore(d.id, d.data()))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection('Extras', snap.hasData ? extras.length : null),
            if (snap.hasData && extras.isEmpty) _vide('Aucun extra.'),
            for (final e in extras)
              Card(
                child: ListTile(
                  leading: e.photoUrl != null
                      ? GestureDetector(
                          onTap: () => _voirPhoto(context, e.photoUrl!),
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
                                child: Icon(Icons.broken_image_outlined),
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
                    '${e.mainOeuvre}\n${dateAffichee(e.dateTravaux)}'
                    '${e.ajouteParNom.isEmpty ? '' : ' • ${e.ajouteParNom}'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionMateriel extends StatelessWidget {
  final String companyId;
  final String chantierId;
  const _SectionMateriel({required this.companyId, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requete('chantier_materiel', companyId, chantierId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _vide('Impossible de charger le matériel.');
        final docs = snap.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection('Matériel', snap.hasData ? docs.length : null),
            if (snap.hasData && docs.isEmpty) _vide('Aucun matériel.'),
            for (final d in docs)
              Card(
                child: ListTile(
                  leading: Icon(
                    d.data()['complete'] == true
                        ? Icons.check_circle
                        : Icons.shopping_cart_outlined,
                    color: d.data()['complete'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text((d.data()['texte'] ?? '').toString()),
                  subtitle: Text(
                    [
                      if ((d.data()['quantite'] ?? '').toString().isNotEmpty)
                        'Quantité : ${d.data()['quantite']}',
                      d.data()['complete'] == true ? 'Obtenu' : 'À obtenir',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTravaux extends StatelessWidget {
  final String companyId;
  final String chantierId;
  const _SectionTravaux({required this.companyId, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requete('chantier_travaux', companyId, chantierId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _vide('Impossible de charger les travaux.');
        final docs = snap.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection(
              'Travaux à compléter',
              snap.hasData ? docs.length : null,
            ),
            if (snap.hasData && docs.isEmpty)
              _vide('Aucun travail à compléter.'),
            for (final d in docs)
              Card(
                child: ListTile(
                  leading: Icon(
                    d.data()['complete'] == true
                        ? Icons.check_circle
                        : Icons.assignment_outlined,
                    color: d.data()['complete'] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text((d.data()['texte'] ?? '').toString()),
                  subtitle: Text(
                    d.data()['complete'] == true ? 'Complété' : 'À compléter',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionDocuments extends StatelessWidget {
  final String companyId;
  final String chantierId;
  const _SectionDocuments({required this.companyId, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requete('chantier_documents', companyId, chantierId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _vide('Impossible de charger les documents.');
        final docs = snap.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection('Documents', snap.hasData ? docs.length : null),
            if (snap.hasData && docs.isEmpty) _vide('Aucun document.'),
            for (final d in docs)
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: ThemeCompagnie.accentDe(context),
                  ),
                  title: Text((d.data()['nom'] ?? '').toString()),
                  subtitle: Text(
                    formatTaille(((d.data()['taille'] ?? 0) as num).toInt()),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionPhotos extends StatelessWidget {
  final String companyId;
  final String chantierId;
  const _SectionPhotos({required this.companyId, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requete('chantier_photos', companyId, chantierId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _vide('Impossible de charger les photos.');
        final docs = snap.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titreSection('Photos', snap.hasData ? docs.length : null),
            if (snap.hasData && docs.isEmpty) _vide('Aucune photo.'),
            if (docs.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final url = (docs[i].data()['url'] ?? '').toString();
                  return GestureDetector(
                    onTap: () => _voirPhoto(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
