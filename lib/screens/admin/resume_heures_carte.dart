import 'package:flutter/material.dart';

import '../../models/extra_chantier.dart';
import '../../models/resume_chantier.dart';

/// Carte « Heures » d'un dossier de chantier : total, période, voyagement payé
/// et heures par employé. Pour préparer une facture.
class ResumeHeuresCarte extends StatelessWidget {
  final ResumeChantier resume;
  const ResumeHeuresCarte({super.key, required this.resume});

  @override
  Widget build(BuildContext context) {
    final r = resume;
    final periode = r.premierJour == null
        ? 'Aucune heure saisie sur ce chantier.'
        : 'Du ${dateAffichee(r.premierJour!)} au ${dateAffichee(r.dernierJour!)} • '
              '${r.joursTravailles} jour${r.joursTravailles > 1 ? 's' : ''} de travail';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Heures',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatHeures(r.totalHeures)} h',
                  key: const ValueKey('resume_total_heures'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text('travaillées'),
                ),
              ],
            ),
            if (r.totalVoyagementPaye > 0)
              Text(
                '+ ${formatHeures(r.totalVoyagementPaye)} h de voyagement payé',
                key: const ValueKey('resume_voyagement'),
              ),
            const SizedBox(height: 4),
            Text(
              periode,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (r.parEmploye.isNotEmpty) ...[
              const Divider(height: 24),
              for (final e in r.parEmploye)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    key: ValueKey('resume_employe_${e.nom}'),
                    children: [
                      Expanded(child: Text(e.nom)),
                      Text(
                        '${e.jours} j',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 78,
                        child: Text(
                          '${formatHeures(e.heures)} h',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
