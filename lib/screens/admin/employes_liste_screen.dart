import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_session.dart';
import '../../services/fonctions.dart';
import 'employe_formulaire_screen.dart';

class EmployesListeScreen extends StatelessWidget {
  const EmployesListeScreen({super.key});

  String _libelleRole(Map<String, dynamic> data) {
    if (data['estProprietaire'] == true) return 'Super-admin';
    switch (data['role']) {
      case 'admin':
        return 'Administrateur';
      case 'plus':
        return 'Contremaître';
      default:
        return 'Employé';
    }
  }

  Color _couleurRole(Map<String, dynamic> data) {
    if (data['estProprietaire'] == true) return Colors.purple.shade600;
    switch (data['role']) {
      case 'admin':
        return Colors.red.shade600;
      case 'plus':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  void _confirmerSuppression(BuildContext context, String docId, String nom) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cet employé ?'),
        content: Text(
          '$nom sera immédiatement déconnecté et ne pourra plus se reconnecter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Protection du propriétaire et nettoyage des sessions : côté serveur.
              try {
                await Fonctions.appeler('supprimerEmploye', {
                  'employeeId': docId,
                });
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Fonctions.message(e, 'Erreur lors du retrait.'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Retirer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des employés')),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('employees')
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
                  ..sort(
                    (a, b) => ((a.data() as Map)['nom'] ?? '').compareTo(
                      (b.data() as Map)['nom'] ?? '',
                    ),
                  );

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aucun employé pour l\'instant.'),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final nom = data['nom'] ?? '';
                    final estProprietaire = data['estProprietaire'] == true;
                    final estMoi = doc.id == AppSession.current?.id;
                    // Seul le super-admin de la compagnie gère les autres admins.
                    final gerable =
                        estMoi ||
                        data['role'] != 'admin' ||
                        AppSession.estProprietaire;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _couleurRole(data),
                        child: Text(
                          nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(nom),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_libelleRole(data)),
                          Text(
                            data['courriel'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          // Pas encore de NIP : lien d'invitation non utilisé.
                          if (data['pinHash'] == null)
                            const Text(
                              'Invitation en attente : NIP pas encore créé',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9A5B00),
                              ),
                            ),
                        ],
                      ),
                      trailing: !gerable
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (valeur) {
                                if (valeur == 'modifier') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EmployeFormulaireScreen(
                                        docId: doc.id,
                                        donneesExistantes: data,
                                      ),
                                    ),
                                  );
                                } else if (valeur == 'supprimer') {
                                  _confirmerSuppression(context, doc.id, nom);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'modifier',
                                  child: Text('Modifier'),
                                ),
                                if (!estProprietaire && !estMoi)
                                  const PopupMenuItem(
                                    value: 'supprimer',
                                    child: Text('Retirer'),
                                  ),
                              ],
                            ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmployeFormulaireScreen()),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
      ),
    );
  }
}
