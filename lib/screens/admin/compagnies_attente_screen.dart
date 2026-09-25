import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/fonctions.dart';

class CompagniesAttenteScreen extends StatelessWidget {
  const CompagniesAttenteScreen({super.key});

  Future<void> _repondre(
    BuildContext context,
    String companyId,
    bool approuver,
  ) async {
    try {
      await Fonctions.appeler('approuverCompagnie', {
        'companyId': companyId,
        'approuver': approuver,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approuver ? 'Compagnie approuvée.' : 'Compagnie refusée.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Fonctions.message(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes de compagnies')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('companies')
            .orderBy('dateCreation', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aucune compagnie pour l\'instant.'),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final statut = data['statut'] ?? 'attente';

              Color couleur;
              String libelle;
              switch (statut) {
                case 'approuvee':
                  couleur = Colors.green;
                  libelle = 'Approuvée';
                  break;
                case 'refusee':
                  couleur = Colors.red;
                  libelle = 'Refusée';
                  break;
                default:
                  couleur = Colors.orange;
                  libelle = 'En attente';
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              data['nomEntreprise'] ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: couleur.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              libelle,
                              style: TextStyle(
                                color: couleur,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('N° ${data['numero']}  •  ${data['secteur'] ?? ''}'),
                      Text(
                        '${data['nomLegal'] ?? ''}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      if (data['nombreEmployes'] != null)
                        Text('${data['nombreEmployes']} employés'),
                      if (data['telephone'] != null &&
                          (data['telephone'] as String).isNotEmpty)
                        Text(data['telephone']),
                      if (statut == 'attente') ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _repondre(context, doc.id, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Refuser'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () =>
                                    _repondre(context, doc.id, true),
                                child: const Text('Approuver'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
