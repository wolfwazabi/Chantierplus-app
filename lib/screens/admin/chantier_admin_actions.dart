import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../../widgets/confirmer_action.dart';

/// Actions d'un admin sur un chantier, partagées par la liste des chantiers et la
/// page d'un chantier : créer, modifier, archiver, restaurer.

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
                    await FirebaseFirestore.instance.collection('chantiers').add({
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

/// Un chantier ne se supprime pas : il s'archive (ses photos, documents et
/// heures sont conservés) et peut être restauré. Demande confirmation avant
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
