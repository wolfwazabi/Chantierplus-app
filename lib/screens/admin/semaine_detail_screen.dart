import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_session.dart';
import 'employe_historique_screen.dart';

class SemaineDetailScreen extends StatelessWidget {
  final String lundiDate;
  const SemaineDetailScreen({super.key, required this.lundiDate});

  String _formatSemaine() {
    final lundi = DateTime.parse(lundiDate);
    final dimanche = lundi.add(const Duration(days: 6));
    return 'Semaine du ${lundi.day}/${lundi.month} au ${dimanche.day}/${dimanche.month}/${dimanche.year}';
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: Text(_formatSemaine())),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('feuilles_temps')
                  .where('companyId', isEqualTo: companyId)
                  .where('lundiDate', isEqualTo: lundiDate)
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
                    child: Text('Aucune donnée pour cette semaine.'),
                  );
                }

                const joursOrdre = [
                  'Lundi',
                  'Mardi',
                  'Mercredi',
                  'Jeudi',
                  'Vendredi',
                ];

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Employé')),
                      ...joursOrdre.map(
                        (j) => DataColumn(label: Text(j.substring(0, 3))),
                      ),
                      const DataColumn(label: Text('Voy. payé')),
                      const DataColumn(label: Text('Total')),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final employeeId = data['employeeId'] as String? ?? '';
                      final employeeNom = data['employeeNom'] as String? ?? '';
                      final jours = List<Map<String, dynamic>>.from(
                        data['jours'] ?? [],
                      );
                      final totalHeures =
                          (data['totalHeures'] as num?)?.toDouble() ?? 0;
                      final voyagementPaye =
                          (data['totalVoyagementPaye'] as num?)?.toDouble() ??
                          0;

                      final heuresParJour = <String, double?>{};
                      for (final j in jours) {
                        final nomJour = j['nomJour'] as String?;
                        final h = (j['heuresTravaillees'] as num?)?.toDouble();
                        if (nomJour != null) heuresParJour[nomJour] = h;
                      }

                      return DataRow(
                        cells: [
                          DataCell(
                            InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EmployeHistoriqueScreen(
                                      employeeId: employeeId,
                                      employeeNom: employeeNom,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                employeeNom,
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          ...joursOrdre.map((j) {
                            final h = heuresParJour[j];
                            return DataCell(
                              Text(h != null ? h.toStringAsFixed(2) : '-'),
                            );
                          }),
                          DataCell(
                            Text(
                              voyagementPaye > 0
                                  ? voyagementPaye.toStringAsFixed(2)
                                  : '-',
                            ),
                          ),
                          DataCell(
                            Text(
                              totalHeures.toStringAsFixed(2),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}
