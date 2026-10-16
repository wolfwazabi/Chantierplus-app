import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../../services/fonctions.dart';
import '../../widgets/confirmer_action.dart';

/// Actions d'un admin sur un chantier, partagées par la liste des chantiers et la
/// page d'un chantier : créer, modifier, archiver, restaurer, supprimer définitivement.

/// Formulaire (feuille du bas) pour créer un chantier, ou modifier celui de
/// [docId] avec les valeurs [donnees].
void ouvrirFormulaireChantier(
  BuildContext context, {
  String? docId,
  Map<String, dynamic>? donnees,
}) {
  final nomCtrl = TextEditingController(text: donnees?['nom'] ?? '');
  final adresseCtrl = TextEditingController(text: donnees?['adresse'] ?? '');

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
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
            Text(
              docId == null ? 'Nouveau chantier' : 'Modifier le chantier',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('chantier_nom'),
              controller: nomCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom du chantier',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('chantier_adresse'),
              controller: adresseCtrl,
              decoration: const InputDecoration(
                labelText: 'Adresse',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('chantier_enregistrer'),
                onPressed: () async {
                  final nom = nomCtrl.text.trim();
                  final adresse = adresseCtrl.text.trim();
                  if (nom.isEmpty) return;

                  final companyId = AppSession.current?.companyId;
                  if (companyId == null) return;

                  if (docId == null) {
                    await FirebaseFirestore.instance
                        .collection('chantiers')
                        .add({
                          'companyId': companyId,
                          'nom': nom,
                          'adresse': adresse,
                        });
                  } else {
                    await FirebaseFirestore.instance
                        .collection('chantiers')
                        .doc(docId)
                        .update({'nom': nom, 'adresse': adresse});
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(docId == null ? 'Créer' : 'Enregistrer'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Archive ou restaure un chantier ; dit à l'admin ce qui s'est passé.
/// Retourne vrai si la modification a réussi.
Future<bool> definirArchiveChantier(
  BuildContext context,
  String docId,
  bool archive,
) async {
  final messager = ScaffoldMessenger.of(context);
  try {
    await FirebaseFirestore.instance.collection('chantiers').doc(docId).update({
      'archive': archive,
    });
    messager.showSnackBar(
      SnackBar(
        content: Text(archive ? 'Chantier archivé.' : 'Chantier restauré.'),
      ),
    );
    return true;
  } catch (_) {
    messager.showSnackBar(
      const SnackBar(
        content: Text('Impossible de modifier le chantier. Réessayez.'),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }
}

/// Un chantier s'archive d'abord (ses photos, documents et heures sont conservés) et peut
/// être restauré ; seul un chantier archivé peut ensuite être supprimé définitivement. Demande confirmation avant
/// d'archiver ; restaurer se fait sans confirmation.
Future<bool> archiverOuRestaurerChantier(
  BuildContext context, {
  required String docId,
  required String nom,
  required bool archiver,
}) async {
  if (archiver) {
    final ok = await confirmerAction(
      context,
      titre: 'Archiver ce chantier ?',
      texte:
          '$nom ne sera plus proposé dans les feuilles de temps, les photos et '
          'les documents. Rien n\'est supprimé : vous pouvez le restaurer à '
          'tout moment.',
      action: 'Archiver',
      destructive: false,
    );
    if (!ok || !context.mounted) return false;
  }
  return definirArchiveChantier(context, docId, archiver);
}

/// Le nom tapé et celui du chantier : espaces, majuscules et accents ignorés (comme le serveur).
bool memeNomChantier(String tape, String nom) {
  String n(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return n(tape).isNotEmpty && n(tape) == n(nom);
}

/// Appel du serveur pour supprimer un chantier (remplaçable dans les tests). Jusqu'à 9 min
/// côté serveur pour un gros chantier : le client attend 10 min.
@visibleForTesting
Future<Map<String, dynamic>> Function(Map<String, dynamic> donnees)
appelerSuppressionChantier = (donnees) => Fonctions.appelerAvecDelai(
  'supprimerChantier',
  donnees,
  const Duration(minutes: 10),
);

/// Supprime DÉFINITIVEMENT un chantier archivé (admins) : le nom tapé confirme. Photos,
/// documents, extras, travaux, matériel et commandes sont effacés ; les heures restent dans les
/// feuilles de temps. [exporterDAbord] (page du chantier) : le bouton « Exporter d'abord » ferme
/// la boîte et lance l'export ZIP. Retourne vrai si le chantier est supprimé.
Future<bool> supprimerChantierDefinitivement(
  BuildContext context, {
  required String docId,
  required String nom,
  VoidCallback? exporterDAbord,
}) async {
  final messager = ScaffoldMessenger.of(context);
  final r = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogueSuppressionChantier(
      docId: docId,
      nom: nom,
      exporter: exporterDAbord != null,
    ),
  );
  if (r == 'exporter') {
    exporterDAbord?.call();
    return false;
  }
  if (r != 'supprime') return false;
  messager.showSnackBar(
    SnackBar(content: Text('« $nom » est supprimé définitivement.')),
  );
  return true;
}

class _DialogueSuppressionChantier extends StatefulWidget {
  final String docId;
  final String nom;
  final bool exporter;
  const _DialogueSuppressionChantier({
    required this.docId,
    required this.nom,
    required this.exporter,
  });

  @override
  State<_DialogueSuppressionChantier> createState() =>
      _DialogueSuppressionChantierState();
}

class _DialogueSuppressionChantierState
    extends State<_DialogueSuppressionChantier> {
  final _nom = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _supprimer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await appelerSuppressionChantier({
        'chantierId': widget.docId,
        'confirmationNom': _nom.text,
      });
      if (mounted) Navigator.pop(context, 'supprime');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = Fonctions.message(e, 'La suppression a échoué. Réessayez.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = memeNomChantier(_nom.text, widget.nom);
    return PopScope(
      canPop: !_enCours,
      child: AlertDialog(
        title: Text('Supprimer « ${widget.nom} » définitivement ?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tout ce qui appartient à ce chantier sera effacé pour de bon : '
                'photos, documents, extras, travaux à compléter, matériel et '
                'commandes. Les heures des employés restent dans leurs feuilles '
                'de temps.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Pensez à exporter le dossier (ZIP) avant : il ne pourra plus '
                'l\'être ensuite.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (widget.exporter)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('suppression_exporter'),
                    onPressed: _enCours
                        ? null
                        : () => Navigator.pop(context, 'exporter'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Exporter d\'abord'),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Pour confirmer, tapez le nom du chantier : ${widget.nom}'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('suppression_nom'),
                controller: _nom,
                enabled: !_enCours,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: widget.nom,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _erreur = null),
              ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _erreur!,
                    key: const ValueKey('suppression_erreur'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_enCours)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Suppression en cours… (jusqu\'à quelques minutes)',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _enCours ? null : () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('suppression_confirmer'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: ok && !_enCours ? _supprimer : null,
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }
}
