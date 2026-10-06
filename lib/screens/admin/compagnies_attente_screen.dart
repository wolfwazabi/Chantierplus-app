import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_session.dart';
import '../../services/fonctions.dart';
import 'confirmation_suppression_compagnie.dart';

class CompagniesAttenteScreen extends StatelessWidget {
  const CompagniesAttenteScreen({super.key});

  /// Supprime la compagnie, ses employés et toutes ses données, après la double
  /// vérification (lecture des conséquences, puis saisie du numéro). Le serveur
  /// revérifie le numéro et protège la compagnie du Proprio. Si elle s'interrompt,
  /// relancer la suppression la termine.
  Future<void> _supprimer(
    BuildContext context,
    String companyId,
    Map<String, dynamic> data,
  ) async {
    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context, rootNavigator: true);
    final numero = '${data['numero'] ?? ''}';
    final nom = '${data['nomEntreprise'] ?? ''}';
    final ok = await confirmerSuppressionCompagnie(
      context,
      nom: nom,
      numero: numero,
    );
    if (!ok || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Suppression en cours…\nNe fermez pas l\'application.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await Fonctions.appelerAvecDelai('supprimerCompagnie', {
        'companyId': companyId,
        'confirmationNumero': numero,
      }, const Duration(minutes: 9));
      navigateur.pop();
      messager.showSnackBar(
        SnackBar(content: Text('Compagnie « $nom » supprimée.')),
      );
    } catch (e) {
      navigateur.pop();
      messager.showSnackBar(
        SnackBar(
          content: Text(
            Fonctions.message(
              e,
              'La suppression a échoué. Relancez-la : elle reprend là où '
              'elle s\'est arrêtée.',
            ),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

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
                case 'suppression':
                  couleur = Colors.grey;
                  libelle = 'Suppression en cours';
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
                      // La compagnie du Proprio ne se supprime pas (le serveur
                      // le refuse aussi) ; les autres, quel que soit leur statut.
                      if (doc.id != AppSession.current?.companyId)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey('supprimer_compagnie_${doc.id}'),
                            onPressed: () => _supprimer(context, doc.id, data),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text(
                              statut == 'suppression'
                                  ? 'Reprendre la suppression'
                                  : 'Supprimer la compagnie',
                            ),
                          ),
                        ),
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
