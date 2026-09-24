import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_session.dart';
import 'semaine_detail_screen.dart';

class SemaineListeScreen extends StatelessWidget {
  const SemaineListeScreen({super.key});

  String _formatSemaine(String lundiIso) {
    final lundi = DateTime.parse(lundiIso);
    final dimanche = lundi.add(const Duration(days: 6));
    return 'Semaine du ${lundi.day}/${lundi.month} au ${dimanche.day}/${dimanche.month}/${dimanche.year}';
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Heures employés')),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : StreamBuilder<QuerySnapshot>(
              // Le filtre companyId est obligatoire : les Security Rules ne filtrent
              // pas les résultats, elles refusent toute requête qui pourrait
              // retourner un document d'une autre compagnie.
              stream: FirebaseFirestore.instance
                  .collection('feuilles_temps')
                  .where('companyId', isEqualTo: companyId)
                  .orderBy('lundiDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur : ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final Map<String, Set<String>> semaines = {};
                for (final doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final lundiDate = data['lundiDate'] as String?;
                  final employeeId = data['employeeId'] as String?;
                  if (lundiDate == null) continue;
                  semaines.putIfAbsent(lundiDate, () => {});
                  if (employeeId != null) semaines[lundiDate]!.add(employeeId);
                }

                final semainesTriees = semaines.keys.toList()
                  ..sort((a, b) => b.compareTo(a));

                if (semainesTriees.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucune feuille de temps soumise pour l\'instant.',
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: semainesTriees.length,
                  itemBuilder: (context, index) {
                    final semaine = semainesTriees[index];
                    final nbEmployes = semaines[semaine]!.length;
                    return ListTile(
                      leading: const Icon(
                        Icons.calendar_month,
                        color: Colors.orange,
                      ),
                      title: Text(_formatSemaine(semaine)),
                      subtitle: Text(
                        '$nbEmployes employé${nbEmployes > 1 ? "s" : ""}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SemaineDetailScreen(lundiDate: semaine),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
