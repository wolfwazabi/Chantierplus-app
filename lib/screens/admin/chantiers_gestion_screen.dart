import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/chantier.dart';
import '../../services/app_session.dart';
import '../../widgets/recherche_chantier.dart';
import '../../services/theme_compagnie.dart';

class ChantiersGestionScreen extends StatefulWidget {
  const ChantiersGestionScreen({super.key});

  @override
  State<ChantiersGestionScreen> createState() => _ChantiersGestionScreenState();
}

class _ChantiersGestionScreenState extends State<ChantiersGestionScreen> {
  /// Filtre de la liste (nom ou adresse), même logique que la recherche « … ».
  String _requete = '';

  /// Un chantier ne se supprime pas : il s'archive (ses photos, documents et
  /// heures sont conservés) et peut être restauré.
  void _confirmerArchivage(BuildContext context, String docId, String nom) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archiver ce chantier ?'),
        content: Text(
          '$nom ne sera plus proposé dans les feuilles de temps, les photos et '
          'les documents. Rien n\'est supprimé : vous pouvez le restaurer '
          'à tout moment dans « Archivés ».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _definirArchive(docId, true);
            },
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
  }

  Future<void> _definirArchive(String docId, bool archive) async {
    final messager = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('chantiers')
          .doc(docId)
          .update({'archive': archive});
      messager.showSnackBar(
        SnackBar(
          content: Text(archive ? 'Chantier archivé.' : 'Chantier restauré.'),
        ),
      );
    } catch (_) {
      messager.showSnackBar(
        const SnackBar(
          content: Text('Impossible de modifier le chantier. Réessayez.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _ouvrirFormulaire(
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du chantier',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
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

  /// Chantiers archivés : repliés, avec « Restaurer ».
  Widget _sectionArchives(List<QueryDocumentSnapshot> archives) {
    if (archives.isEmpty) return const SizedBox(height: 80);
    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: ExpansionTile(
        key: const ValueKey('chantiers_archives'),
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text('Archivés (${archives.length})'),
        children: [
          for (final doc in archives)
            ListTile(
              key: ValueKey('archive_${doc.id}'),
              title: Text((doc.data() as Map)['nom'] ?? ''),
              subtitle: Text((doc.data() as Map)['adresse'] ?? ''),
              trailing: TextButton(
                onPressed: () => _definirArchive(doc.id, false),
                child: const Text('Restaurer'),
              ),
            ),
        ],
      ),
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
                  return const Center(
                    child: Text('Impossible de charger les chantiers.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs.toList()
                  ..sort(
                    (a, b) => ((a.data() as Map)['nom'] ?? '').compareTo(
                      (b.data() as Map)['nom'] ?? '',
                    ),
                  );

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucun chantier. Ajoutez-en un avec le bouton +.',
                    ),
                  );
                }

                final visibles = docs.where((d) {
                  final chantier = Chantier.fromFirestore(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  );
                  return !chantier.archive &&
                      chantierCorrespond(chantier, _requete);
                }).toList();
                final archives = docs.where((d) {
                  final chantier = Chantier.fromFirestore(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  );
                  return chantier.archive &&
                      chantierCorrespond(chantier, _requete);
                }).toList();
                final nbActifs = docs
                    .where((d) => (d.data() as Map)['archive'] != true)
                    .length;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        key: const ValueKey('filtre_chantiers'),
                        decoration: InputDecoration(
                          labelText: 'Rechercher par nom ou adresse',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          suffixText: _requete.isEmpty
                              ? null
                              : '${visibles.length} / $nbActifs',
                        ),
                        onChanged: (v) => setState(() => _requete = v),
                      ),
                    ),
                    Expanded(
                      child: visibles.isEmpty && archives.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Aucun chantier ne correspond à ce nom ou à cette adresse.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visibles.length + 1,
                              itemBuilder: (context, index) {
                                if (index == visibles.length) {
                                  return _sectionArchives(archives);
                                }
                                final doc = visibles[index];
                                final data = doc.data() as Map<String, dynamic>;
                                return ListTile(
                                  leading: Icon(
                                    Icons.construction,
                                    color: ThemeCompagnie.accentDe(context),
                                  ),
                                  title: Text(data['nom'] ?? ''),
                                  subtitle: Text(data['adresse'] ?? ''),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'modifier') {
                                        _ouvrirFormulaire(
                                          context,
                                          docId: doc.id,
                                          donnees: data,
                                        );
                                      } else if (v == 'archiver') {
                                        _confirmerArchivage(
                                          context,
                                          doc.id,
                                          data['nom'] ?? '',
                                        );
                                      }
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(
                                        value: 'modifier',
                                        child: Text('Modifier'),
                                      ),
                                      PopupMenuItem(
                                        value: 'archiver',
                                        child: Text('Archiver'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirFormulaire(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}
