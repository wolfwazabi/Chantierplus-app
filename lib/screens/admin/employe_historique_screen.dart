import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/correction_feuille.dart';
import '../../services/app_session.dart';
import '../../services/theme_compagnie.dart';
import 'modifier_jour_sheet.dart';
import 'semaine_detail_screen.dart' show FluxFeuilles;
import '../../widgets/actualiser.dart';

/// La feuille d'une semaine d'un employé, en direct (null si elle n'existe pas).
typedef FluxFeuille = Stream<Map<String, dynamic>?> Function(String lundiDate);

class EmployeHistoriqueScreen extends StatelessWidget {
  final String employeeId;
  final String employeeNom;

  /// Tests : remplacent la lecture des feuilles et les outils du formulaire.
  @visibleForTesting
  final FluxFeuilles? flux;
  @visibleForTesting
  final FluxFeuille? fluxFeuille;
  @visibleForTesting
  final OutilsEditionJour? outils;

  const EmployeHistoriqueScreen({
    super.key,
    required this.employeeId,
    required this.employeeNom,
    this.flux,
    this.fluxFeuille,
    this.outils,
  });

  String _formatSemaine(String lundiIso) {
    final lundi = DateTime.parse(lundiIso);
    final dimanche = lundi.add(const Duration(days: 6));
    return 'Semaine du ${lundi.day}/${lundi.month} au ${dimanche.day}/${dimanche.month}/${dimanche.year}';
  }

  FluxFeuilles _fluxFirestore() => FirebaseFirestore.instance
      .collection('feuilles_temps')
      .where('companyId', isEqualTo: AppSession.current?.companyId)
      .where('employeeId', isEqualTo: employeeId)
      .snapshots()
      .map((s) => [for (final d in s.docs) MapEntry(d.id, d.data())]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(employeeNom)),
      body: FluxActualisable<List<MapEntry<String, Map<String, dynamic>>>>(
        creerFlux: () => flux ?? _fluxFirestore(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.toList()
            ..sort((a, b) {
              final da = a.value['lundiDate'] as String? ?? '';
              final db = b.value['lundiDate'] as String? ?? '';
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
              final data = docs[index].value;
              final lundiDate = data['lundiDate'] as String? ?? '';
              final totalHeures =
                  (data['totalHeures'] as num?)?.toDouble() ?? 0;
              final voyagementPaye =
                  (data['totalVoyagementPaye'] as num?)?.toDouble() ?? 0;

              return ListTile(
                key: ValueKey('semaine_$lundiDate'),
                leading: Icon(
                  Icons.calendar_month,
                  color: ThemeCompagnie.accentDe(context),
                ),
                title: Text(_formatSemaine(lundiDate)),
                subtitle: Text(
                  'Total : ${totalHeures.toStringAsFixed(2)} h'
                  '${voyagementPaye > 0 ? ' (dont ${voyagementPaye.toStringAsFixed(2)} h de voyagement)' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SemaineEmployeScreen(
                        titre: _formatSemaine(lundiDate),
                        employeeId: employeeId,
                        employeeNom: employeeNom,
                        lundiDate: lundiDate,
                        joursInitiaux: List<Map<String, dynamic>>.from(
                          data['jours'] ?? [],
                        ),
                        fluxFeuille: fluxFeuille,
                        outils: outils,
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

/// Les cinq jours d'une semaine d'un employé. Toucher un jour permet à l'admin de modifier
/// les heures (le serveur recalcule les heures payées).
class SemaineEmployeScreen extends StatelessWidget {
  final String titre;
  final String employeeId;
  final String employeeNom;
  final String lundiDate;
  final List<Map<String, dynamic>> joursInitiaux;
  @visibleForTesting
  final FluxFeuille? fluxFeuille;
  @visibleForTesting
  final OutilsEditionJour? outils;

  const SemaineEmployeScreen({
    super.key,
    required this.titre,
    required this.employeeId,
    required this.employeeNom,
    required this.lundiDate,
    required this.joursInitiaux,
    this.fluxFeuille,
    this.outils,
  });

  Stream<Map<String, dynamic>?> get _flux =>
      fluxFeuille?.call(lundiDate) ??
      FirebaseFirestore.instance
          .collection('feuilles_temps')
          .doc('${employeeId}_$lundiDate')
          .snapshots()
          .map((s) => s.data());

  String _formatDuree(int? minutes) {
    if (minutes == null || minutes == 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  Future<void> _modifier(
    BuildContext context,
    List<Map<String, dynamic>> jours,
    int index,
  ) async {
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
              ? 'Heures modifiées.'
              : 'Heures modifiées : total de la semaine ${total.toStringAsFixed(2)} h.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: StreamBuilder<Map<String, dynamic>?>(
        initialData: {'jours': joursInitiaux},
        stream: _flux,
        builder: (context, snapshot) {
          final jours = List<Map<String, dynamic>>.from(
            snapshot.data?['jours'] ?? joursInitiaux,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Touchez une journée pour modifier les heures.',
                  key: ValueKey('employe_astuce'),
                  style: TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Jour')),
                        DataColumn(label: Text('Chantier')),
                        DataColumn(label: Text('Début')),
                        DataColumn(label: Text('Fin')),
                        DataColumn(label: Text('Voyagement')),
                        DataColumn(label: Text('Voy. payé')),
                        DataColumn(label: Text('Heures')),
                      ],
                      rows: [
                        for (var i = 0; i < joursParFeuille; i++)
                          _ligne(
                            context,
                            i,
                            i < jours.length ? jours[i] : const {},
                            jours,
                          ),
                      ],
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

  DataRow _ligne(
    BuildContext context,
    int i,
    Map<String, dynamic> j,
    List<Map<String, dynamic>> jours,
  ) {
    // Férié : 8 h payées, sans chantier.
    final heures =
        (j['heuresTravaillees'] as num?)?.toDouble() ??
        (j['estFerie'] == true
            ? (j['heuresFeriees'] as num?)?.toDouble() ?? heuresFerie
            : null);
    final voyPaye = (j['voyagementPayeHeures'] as num?)?.toDouble();
    final estAucun = j['estAucun'] == true;
    void ouvrir() => _modifier(context, jours, i);
    return DataRow(
      key: ValueKey('ligne_jour_$i'),
      cells: [
        DataCell(Text(j['nomJour'] ?? nomsJoursFeuille[i]), onTap: ouvrir),
        DataCell(
          Text(estAucun ? 'Non travaillé' : (j['chantierNom'] ?? '-')),
          onTap: ouvrir,
        ),
        DataCell(
          Text(heureAffichee(_entier(j['heureDebutMinutes']))),
          onTap: ouvrir,
        ),
        DataCell(
          Text(heureAffichee(_entier(j['heureFinMinutes']))),
          onTap: ouvrir,
        ),
        DataCell(
          Text(_formatDuree(_entier(j['tempsVoyagementMinutes']))),
          onTap: ouvrir,
        ),
        DataCell(
          Text(
            voyPaye != null && voyPaye > 0 ? voyPaye.toStringAsFixed(2) : '-',
          ),
          onTap: ouvrir,
        ),
        DataCell(
          Text(heures != null ? heures.toStringAsFixed(2) : '-'),
          onTap: ouvrir,
        ),
      ],
    );
  }

  static int? _entier(Object? v) => v is num ? v.toInt() : null;
}
