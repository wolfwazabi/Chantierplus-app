import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/chantier.dart';
import '../../services/app_session.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/recherche_chantier.dart';
import 'dossier_chantier_screen.dart';

/// Filtre de la liste des dossiers.
enum FiltreDossiers { tous, actifs, archives }

/// Garde les chantiers selon le filtre et la recherche (nom ou adresse).
List<Chantier> filtrerDossiers(
  List<Chantier> chantiers,
  FiltreDossiers filtre,
  String requete,
) {
  return chantiers.where((c) {
    final okFiltre = switch (filtre) {
      FiltreDossiers.tous => true,
      FiltreDossiers.actifs => !c.archive,
      FiltreDossiers.archives => c.archive,
    };
    return okFiltre && chantierCorrespond(c, requete);
  }).toList();
}

/// Section Admin « Dossiers de chantier » : tous les chantiers, archivés
/// compris, pour consulter un résumé et exporter le dossier.
class DossiersChantiersScreen extends StatefulWidget {
  const DossiersChantiersScreen({super.key});

  @override
  State<DossiersChantiersScreen> createState() =>
      _DossiersChantiersScreenState();
}

class _DossiersChantiersScreenState extends State<DossiersChantiersScreen> {
  FiltreDossiers _filtre = FiltreDossiers.tous;
  String _requete = '';

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;
    return Scaffold(
      appBar: AppBar(title: const Text('Dossiers de chantier')),
      body: companyId == null || !AppSession.estAdmin
          ? const Center(child: Text('Réservé aux administrateurs.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                final tous =
                    snapshot.data!.docs
                        .map((d) => Chantier.fromFirestore(d.id, d.data()))
                        .toList()
                      ..sort((a, b) => a.nom.compareTo(b.nom));
                final visibles = filtrerDossiers(tous, _filtre, _requete);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        key: const ValueKey('filtre_dossiers'),
                        decoration: const InputDecoration(
                          labelText: 'Rechercher par nom ou adresse',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _requete = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SegmentedButton<FiltreDossiers>(
                        key: const ValueKey('segments_dossiers'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: FiltreDossiers.tous,
                            label: Text('Tous'),
                          ),
                          ButtonSegment(
                            value: FiltreDossiers.actifs,
                            label: Text('Actifs'),
                          ),
                          ButtonSegment(
                            value: FiltreDossiers.archives,
                            label: Text('Archivés'),
                          ),
                        ],
                        selected: {_filtre},
                        onSelectionChanged: (s) =>
                            setState(() => _filtre = s.first),
                      ),
                    ),
                    Expanded(
                      child: visibles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  tous.isEmpty
                                      ? 'Aucun chantier.'
                                      : 'Aucun chantier ne correspond.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: visibles.length,
                              itemBuilder: (context, i) {
                                final c = visibles[i];
                                return ListTile(
                                  key: ValueKey('dossier_${c.id}'),
                                  leading: Icon(
                                    c.archive
                                        ? Icons.inventory_2_outlined
                                        : Icons.folder_open,
                                    color: ThemeCompagnie.accentDe(context),
                                  ),
                                  title: Text(c.nom),
                                  subtitle: Text(
                                    [
                                      if (c.adresse.isNotEmpty) c.adresse,
                                      if (c.archive) 'Archivé',
                                    ].join(' • '),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DossierChantierScreen(chantier: c),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
