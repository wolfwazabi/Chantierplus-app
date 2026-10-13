import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/correction_feuille.dart';
import '../../services/app_session.dart';
import 'employe_historique_screen.dart';
import 'modifier_jour_sheet.dart';
import '../../widgets/actualiser.dart';

/// Une feuille de temps de la semaine (identifiant du document + données).
typedef FluxFeuilles = Stream<List<MapEntry<String, Map<String, dynamic>>>>;

/// Tableau admin d'une semaine : une ligne par employé, une colonne par jour. Toucher une
/// journée permet à l'admin de modifier les heures de l'employé (le serveur recalcule).
class SemaineDetailScreen extends StatelessWidget {
  final String lundiDate;

  /// Tests : remplacent la lecture des feuilles et les outils du formulaire.
  @visibleForTesting
  final FluxFeuilles? flux;
  @visibleForTesting
  final OutilsEditionJour? outils;

  const SemaineDetailScreen({
    super.key,
    required this.lundiDate,
    this.flux,
    this.outils,
  });

  String _formatSemaine() {
    final lundi = DateTime.parse(lundiDate);
    final dimanche = lundi.add(const Duration(days: 6));
    return 'Semaine du ${lundi.day}/${lundi.month} au ${dimanche.day}/${dimanche.month}/${dimanche.year}';
  }

  FluxFeuilles _fluxFirestore(String companyId) => FirebaseFirestore.instance
      .collection('feuilles_temps')
      .where('companyId', isEqualTo: companyId)
      .where('lundiDate', isEqualTo: lundiDate)
      .snapshots()
      .map((s) => [for (final d in s.docs) MapEntry(d.id, d.data())]);

  Future<void> _modifier(
    BuildContext context, {
    required String employeeId,
    required String employeeNom,
    required List<Map<String, dynamic>> jours,
    required int index,
  }) async {
    final messages = ScaffoldMessenger.of(context);
    final reponse = await modifierJourEmploye(
      context,
      employeeId: employeeId,
      employeeNom: employeeNom,
      lundiDate: lundiDate,
      jours: jours,
      index: index,
      outils: outils,
    );
    if (reponse == null) return;
    final total = (reponse['totalHeures'] as num?)?.toDouble();
    messages.showSnackBar(
      SnackBar(
        content: Text(
          total == null
              ? 'Heures de $employeeNom modifiées.'
              : 'Heures de $employeeNom modifiées : total de la semaine '
                    '${total.toStringAsFixed(2)} h.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: Text(_formatSemaine())),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : FluxActualisable<List<MapEntry<String, Map<String, dynamic>>>>(
              creerFlux: () => flux ?? _fluxFirestore(companyId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur : ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aucune donnée pour cette semaine.'),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Touchez une journée pour modifier les heures de l\'employé.',
                        key: ValueKey('semaine_astuce'),
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: Text('Employé')),
                              ...nomsJoursFeuille.map(
                                (j) =>
                                    DataColumn(label: Text(j.substring(0, 3))),
                              ),
                              const DataColumn(label: Text('Voy. payé')),
                              const DataColumn(label: Text('Total')),
                            ],
                            rows: docs.map((entree) {
                              final data = entree.value;
                              final employeeId =
                                  data['employeeId'] as String? ?? '';
                              final employeeNom =
                                  data['employeeNom'] as String? ?? '';
                              final jours = List<Map<String, dynamic>>.from(
                                data['jours'] ?? [],
                              );
                              final totalHeures =
                                  (data['totalHeures'] as num?)?.toDouble() ??
                                  0;
                              final voyagementPaye =
                                  (data['totalVoyagementPaye'] as num?)
                                      ?.toDouble() ??
                                  0;

                              final heuresParJour = <String, double?>{};
                              for (final j in jours) {
                                final nomJour = j['nomJour'] as String?;
                                final h = (j['heuresTravaillees'] as num?)
                                    ?.toDouble();
                                if (nomJour != null) heuresParJour[nomJour] = h;
                              }

                              return DataRow(
                                key: ValueKey('ligne_${entree.key}'),
                                cells: [
                                  DataCell(
                                    InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EmployeHistoriqueScreen(
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
                                  for (
                                    var i = 0;
                                    i < nomsJoursFeuille.length;
                                    i++
                                  )
                                    DataCell(
                                      Text(
                                        heuresParJour[nomsJoursFeuille[i]] !=
                                                null
                                            ? heuresParJour[nomsJoursFeuille[i]]!
                                                  .toStringAsFixed(2)
                                            : '-',
                                        key: ValueKey('jour_${entree.key}_$i'),
                                      ),
                                      onTap: () => _modifier(
                                        context,
                                        employeeId: employeeId,
                                        employeeNom: employeeNom,
                                        jours: jours,
                                        index: i,
                                      ),
                                    ),
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
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
