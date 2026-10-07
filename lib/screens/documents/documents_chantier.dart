import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_session.dart';
import '../../services/erreurs_firebase.dart';
import '../../services/stockage.dart';
import '../../services/theme_compagnie.dart';

/// Taille maximale d'un document (identique à storage.rules / firestore.rules).
const int tailleMaxDocument = 50 * 1024 * 1024;

/// Extensions acceptées (identiques à storage.rules) → type MIME envoyé.
/// HTML, SVG, XML, JavaScript et exécutables sont volontairement exclus.
const Map<String, String> typesDocuments = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'xlsm': 'application/vnd.ms-excel.sheet.macroEnabled.12',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'odp': 'application/vnd.oasis.opendocument.presentation',
  'rtf': 'application/rtf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'gif': 'image/gif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'bmp': 'image/bmp',
  'dwg': 'application/octet-stream',
  'dxf': 'application/octet-stream',
  'dwf': 'application/octet-stream',
  'ifc': 'application/octet-stream',
  'rvt': 'application/octet-stream',
  'skp': 'application/octet-stream',
  'zip': 'application/zip',
};

/// Liste des documents d'un chantier. [peutGerer] (admins) permet le dépôt
/// et la suppression ; sinon, consultation seulement (contremaîtres).
/// Les règles de sécurité appliquent ces mêmes droits côté serveur.
class DocumentsChantier extends StatefulWidget {
  final String companyId;
  final String chantierId;
  final bool peutGerer;

  /// Tests : remplace la lecture des documents dans Firestore (identifiant de la
  /// fiche → ses données).
  @visibleForTesting
  final Stream<List<MapEntry<String, Map<String, dynamic>>>>? fluxDocuments;

  const DocumentsChantier({
    super.key,
    required this.companyId,
    required this.chantierId,
    required this.peutGerer,
    this.fluxDocuments,
  });

  @override
  State<DocumentsChantier> createState() => _DocumentsChantierState();
}

class _DocumentsChantierState extends State<DocumentsChantier> {
  String? _envoiEnCours; // nom du fichier en cours d'envoi
  int _envoisRestants = 0;

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('chantier_documents');

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  static String _extension(String nom) {
    final i = nom.lastIndexOf('.');
    return i < 0 ? '' : nom.substring(i + 1).toLowerCase();
  }

  /// Nom de stockage sûr : horodatage + caractères simples seulement.
  static String _nomStockage(String nom) {
    final propre = nom
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final tronque = propre.length > 180
        ? propre.substring(propre.length - 180)
        : propre;
    return '${DateTime.now().millisecondsSinceEpoch}_$tronque';
  }

  static String formaterTaille(num octets) {
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) return '${(octets / 1024).toStringAsFixed(0)} Ko';
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _deposer() async {
    final List<PlatformFile> fichiers;
    try {
      fichiers = await FilePicker.pickFiles(
        dialogTitle: 'Choisir des documents',
        type: FileType.custom,
        allowedExtensions: typesDocuments.keys.toList(),
      );
    } catch (_) {
      _message('Impossible d\'ouvrir le sélecteur de fichiers.', erreur: true);
      return;
    }
    if (fichiers.isEmpty) return;

    setState(() => _envoisRestants = fichiers.length);
    var reussis = 0;
    final refuses = <String>[];

    for (final fichier in fichiers) {
      setState(() => _envoiEnCours = fichier.name);
      final erreur = await _deposerUn(fichier);
      if (erreur == null) {
        reussis++;
      } else {
        refuses.add('${fichier.name} : $erreur');
      }
      if (mounted) setState(() => _envoisRestants--);
    }

    if (!mounted) return;
    setState(() => _envoiEnCours = null);
    if (refuses.isEmpty) {
      _message(
        reussis == 1 ? 'Document déposé.' : '$reussis documents déposés.',
      );
    } else {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${refuses.length} document(s) non déposé(s)'),
          content: SingleChildScrollView(child: Text(refuses.join('\n\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Retourne null si le dépôt a réussi, sinon la raison du refus.
  Future<String?> _deposerUn(PlatformFile fichier) async {
    final employe = AppSession.current;
    if (employe == null) return 'session expirée, reconnectez-vous';

    final typeMime = typesDocuments[_extension(fichier.name)];
    if (typeMime == null) return 'format non accepté';

    final taille = await fichier.length() ?? 0;
    if (taille <= 0) return 'fichier vide';
    if (taille > tailleMaxDocument) {
      return 'trop volumineux (${formaterTaille(taille)}, maximum ${formaterTaille(tailleMaxDocument)})';
    }

    final chemin =
        'chantiers/${widget.companyId}/${widget.chantierId}/documents/${_nomStockage(fichier.name)}';
    final ref = Stockage.instance.ref(chemin);

    try {
      final octets = await fichier.readAsBytes();
      await ref.putData(octets, SettableMetadata(contentType: typeMime));
      final url = await ref.getDownloadURL();
      final nom = fichier.name.length > 200
          ? fichier.name.substring(0, 200)
          : fichier.name;
      try {
        await _collection.add({
          'companyId': widget.companyId,
          'chantierId': widget.chantierId,
          'nom': nom,
          'cheminStorage': chemin,
          'url': url,
          'taille': octets.length,
          'typeMime': typeMime,
          'ajoutePar': employe.id,
          'dateAjout': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Pas de fichier orphelin si la fiche n'a pas pu être créée.
        try {
          await ref.delete();
        } catch (_) {}
        rethrow;
      }
      return null;
    } on FirebaseException catch (e) {
      // On dit d'où vient le refus : stockage des fichiers ou base de données.
      return estRefusFirebase(e)
          ? 'refusé par le ${sourceErreurFirebase(e)} (${e.code}) : droits insuffisants ou format non accepté'
          : 'erreur (${detailErreurFirebase(e)}), réessayez';
    } catch (_) {
      return 'erreur inattendue, réessayez';
    }
  }

  Future<void> _ouvrir(Map<String, dynamic> data) async {
    final url = Uri.tryParse(data['url'] as String? ?? '');
    if (url == null || url.scheme != 'https') {
      _message('Lien du document invalide.', erreur: true);
      return;
    }
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _message('Aucune application ne peut ouvrir ce document.', erreur: true);
    }
  }

  Future<void> _supprimer(String docId, Map<String, dynamic> data) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text(
          '« ${data['nom']} » sera supprimé définitivement pour tous.',
        ),
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
    if (confirme != true) return;
    try {
      await _collection.doc(docId).delete();
      final chemin = data['cheminStorage'] as String?;
      if (chemin != null) {
        try {
          await Stockage.instance.ref(chemin).delete();
        } catch (_) {}
      }
      _message('Document supprimé.');
    } catch (_) {
      _message('Suppression impossible.', erreur: true);
    }
  }

  static IconData _icone(String nom) {
    switch (_extension(nom)) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'odt':
      case 'rtf':
      case 'txt':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'xlsm':
      case 'ods':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow;
      case 'dwg':
      case 'dxf':
      case 'dwf':
      case 'ifc':
      case 'rvt':
      case 'skp':
        return Icons.architecture;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.image;
    }
  }

  static String _date(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.peutGerer)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _envoiEnCours != null ? null : _deposer,
                icon: const Icon(Icons.upload_file),
                label: const Text('Déposer des documents'),
              ),
            ),
          ),
        if (_envoiEnCours != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(
                  'Envoi de « $_envoiEnCours » ($_envoisRestants restant${_envoisRestants > 1 ? 's' : ''})',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
            stream:
                widget.fluxDocuments ??
                _collection
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
                return const Center(
                  child: Text('Impossible de charger les documents.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!;
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.peutGerer
                          ? 'Aucun document. Déposez des plans, devis, photos…'
                          : 'Aucun document pour ce chantier.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.value;
                  final nom = data['nom'] as String? ?? '';
                  return ListTile(
                    leading: Icon(
                      _icone(nom),
                      color: ThemeCompagnie.accentDe(context),
                    ),
                    title: Text(nom, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${formaterTaille((data['taille'] as num?) ?? 0)} • ${_date(data['dateAjout'] as Timestamp?)}',
                    ),
                    onTap: () => _ouvrir(data),
                    trailing: widget.peutGerer
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer',
                            onPressed: () => _supprimer(doc.key, data),
                          )
                        : const Icon(Icons.open_in_new, size: 20),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
