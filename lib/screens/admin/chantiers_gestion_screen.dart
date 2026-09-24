import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/app_session.dart';

class ChantiersGestionScreen extends StatelessWidget {
  const ChantiersGestionScreen({super.key});

  void _confirmerSuppression(BuildContext context, String docId, String nom) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce chantier ?'),
        content: Text('$nom sera retiré de la liste. Les photos/travaux/matériel déjà associés resteront consultables via l\'historique existant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FirebaseFirestore.instance.collection('chantiers').doc(docId).delete();
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _ouvrirFormulaire(BuildContext context, {String? docId, Map<String, dynamic>? donnees}) {
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
                controller: nomCtrl,
                decoration: const InputDecoration(labelText: 'Nom du chantier', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: adresseCtrl,
                decoration: const InputDecoration(labelText: 'Adresse', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
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
                      await FirebaseFirestore.instance.collection('chantiers').doc(docId).update({
                        'nom': nom,
                        'adresse': adresse,
                      });
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

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Gérer les chantiers')),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : StreamBuilder<QuerySnapshot>(
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
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) => ((a.data() as Map)['nom'] ?? '').compareTo((b.data() as Map)['nom'] ?? ''));

                if (docs.isEmpty) {
                  return const Center(child: Text('Aucun chantier. Ajoutez-en un avec le bouton +.'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.construction, color: Colors.orange),
                      title: Text(data['nom'] ?? ''),
                      subtitle: Text(data['adresse'] ?? ''),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'modifier') {
                            _ouvrirFormulaire(context, docId: doc.id, donnees: data);
                          } else if (v == 'supprimer') {
                            _confirmerSuppression(context, doc.id, data['nom'] ?? '');
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                          PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirFormulaire(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}