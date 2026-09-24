import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_session.dart';

class EmployeHistoriqueScreen extends StatelessWidget {
  final String employeeId;
  final String employeeNom;
  const EmployeHistoriqueScreen({
    super.key,
    required this.employeeId,
    required this.employeeNom,
  });

  String _formatSemaine(String lundiIso) {
    final lundi = DateTime.parse(lundiIso);
    final dimanche = lundi.add(const Duration(days: 6));
    return 'Semaine du ${lundi.day}/${lundi.month} au ${dimanche.day}/${dimanche.month}/${dimanche.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(employeeNom)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('feuilles_temps')
            .where('companyId', isEqualTo: AppSession.current?.companyId)
            .where('employeeId', isEqualTo: employeeId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final da =
                  (a.data() as Map<String, dynamic>)['lundiDate'] as String? ??
                  '';
              final db =
                  (b.data() as Map<String, dynamic>)['lundiDate'] as String? ??
                  '';
              return db.compareTo(da);
            });

          if (docs.isEmpty) {
            return const Center(
              child: Text('Aucune feuille de temps pour cet employé.'),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final lundiDate = data['lundiDate'] as String? ?? '';
              final totalHeures =
                  (data['totalHeures'] as num?)?.toDouble() ?? 0;

              return ListTile(
                leading: const Icon(
                  Icons.calendar_month,
                  color: const Color(0xFF8A3B24),
                ),
                title: Text(_formatSemaine(lundiDate)),
                subtitle: Text('Total : ${totalHeures.toStringAsFixed(2)} h'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _JourDetailScreen(
                        titre: _formatSemaine(lundiDate),
                        jours: List<Map<String, dynamic>>.from(
                          data['jours'] ?? [],
                        ),
                      ),
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

class _JourDetailScreen extends StatelessWidget {
  final String titre;
  final List<Map<String, dynamic>> jours;
  const _JourDetailScreen({required this.titre, required this.jours});

  String _formatHeure(int? minutes) {
    if (minutes == null) return '--:--';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatDuree(int? minutes) {
    if (minutes == null || minutes == 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Jour')),
            DataColumn(label: Text('Chantier')),
            DataColumn(label: Text('Début')),
            DataColumn(label: Text('Fin')),
            DataColumn(label: Text('Voyagement')),
            DataColumn(label: Text('Heures')),
          ],
          rows: jours.map((j) {
            final heures = (j['heuresTravaillees'] as num?)?.toDouble();
            return DataRow(
              cells: [
                DataCell(Text(j['nomJour'] ?? '')),
                DataCell(Text(j['chantierNom'] ?? '-')),
                DataCell(Text(_formatHeure(j['heureDebutMinutes'] as int?))),
                DataCell(Text(_formatHeure(j['heureFinMinutes'] as int?))),
                DataCell(
                  Text(_formatDuree(j['tempsVoyagementMinutes'] as int?)),
                ),
                DataCell(
                  Text(heures != null ? heures.toStringAsFixed(2) : '-'),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
