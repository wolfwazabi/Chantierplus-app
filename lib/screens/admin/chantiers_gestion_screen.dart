import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/chantier.dart';
import '../../services/app_session.dart';
import '../../services/materiel_general_source.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/recherche_chantier.dart';
import 'chantier_admin_actions.dart';
import 'dossier_chantier_screen.dart';
import 'materiel_general_screen.dart';

/// Filtre de la liste des chantiers.
enum FiltreChantiers { actifs, archives, tous }

/// Garde les chantiers selon le filtre et la recherche (nom ou adresse).
List<Chantier> filtrerChantiers(
  List<Chantier> chantiers,
  FiltreChantiers filtre,
  String requete,
) {
  return chantiers.where((c) {
    final okFiltre = switch (filtre) {
      FiltreChantiers.tous => true,
      FiltreChantiers.actifs => !c.archive,
      FiltreChantiers.archives => c.archive,
    };
    return okFiltre && chantierCorrespond(c, requete);
  }).toList();
}

/// Section Admin « Chantiers » : tout ce qui touche un chantier au même endroit.
/// La liste (recherche, actifs / archivés) mène à la page du chantier : résumé des
/// heures, photos, documents (dépôt et suppression), export, modification et
/// archivage. « Général » (matériel de la remorque, sans chantier) reste toujours
/// en tête de la liste.
class ChantiersGestionScreen extends StatefulWidget {
  /// Remplace la lecture des chantiers dans Firestore (tests).
  @visibleForTesting
  final Stream<List<Chantier>>? fluxChantiers;

  /// Remplace la page d'un chantier ouverte au toucher (tests).
  @visibleForTesting
  final Widget Function(Chantier chantier)? pageChantier;

  /// Remplace Firestore pour le matériel Général et sa pastille (tests).
  @visibleForTesting
  final SourceMaterielGeneral? sourceMateriel;

  const ChantiersGestionScreen({
    super.key,
    this.fluxChantiers,
    this.pageChantier,
    this.sourceMateriel,
  });

  @override
  State<ChantiersGestionScreen> createState() => _ChantiersGestionScreenState();
}

class _ChantiersGestionScreenState extends State<ChantiersGestionScreen> {
  FiltreChantiers _filtre = FiltreChantiers.actifs;
  String _requete = '';

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Chantiers')),
      body: companyId == null || !AppSession.estAdmin
          ? const Center(child: Text('Réservé aux administrateurs.'))
          : StreamBuilder<List<Chantier>>(
              stream:
                  widget.fluxChantiers ??
                  FirebaseFirestore.instance
                      .collection('chantiers')
                      .where('companyId', isEqualTo: companyId)
                      .snapshots()
                      .map(
                        (s) => [
                          for (final d in s.docs)
                            Chantier.fromFirestore(d.id, d.data()),
                        ],
                      ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Impossible de charger les chantiers.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tous = [...snapshot.data!]
                  ..sort((a, b) => a.nom.compareTo(b.nom));
                final visibles = filtrerChantiers(tous, _filtre, _requete);
                final nbActifs = tous.where((c) => !c.archive).length;
                final nbArchives = tous.length - nbActifs;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        key: const ValueKey('filtre_chantiers'),
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
                      child: SegmentedButton<FiltreChantiers>(
                        key: const ValueKey('segments_chantiers'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: FiltreChantiers.actifs,
                            label: Text('Actifs ($nbActifs)'),
                          ),
                          ButtonSegment(
                            value: FiltreChantiers.archives,
                            label: Text('Archivés ($nbArchives)'),
                          ),
                          const ButtonSegment(
                            value: FiltreChantiers.tous,
                            label: Text('Tous'),
                          ),
                        ],
                        selected: {_filtre},
                        onSelectionChanged: (s) =>
                            setState(() => _filtre = s.first),
                      ),
                    ),
                    // Général : toujours premier (jamais archivé, jamais dans les heures).
                    if (_filtre != FiltreChantiers.archives &&
                        chantierCorrespond(chantierGeneral, _requete))
                      _TuileGeneral(source: widget.sourceMateriel),
                    Expanded(
                      child: visibles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  tous.isEmpty
                                      ? 'Aucun chantier. Ajoutez-en un avec le bouton Ajouter.'
                                      : 'Aucun chantier ne correspond.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: visibles.length,
                              itemBuilder: (context, i) =>
                                  _TuileChantier(
                                    chantier: visibles[i],
                                    pageChantier: widget.pageChantier,
                                  ),
                            ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: companyId == null || !AppSession.estAdmin
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('chantier_ajouter'),
              onPressed: () => ouvrirFormulaireChantier(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
    );
  }
}

/// « Général » : le matériel de la remorque, séparé par contremaître et admin.
/// La pastille de couleur compte les changements que l'admin n'a pas vus.
class _TuileGeneral extends StatelessWidget {
  final SourceMaterielGeneral? source;
  const _TuileGeneral({this.source});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NonVusGeneral(
          source: source,
          builder: (context, nonVus) => ListTile(
            key: const ValueKey('chantier_general'),
            tileColor: ThemeCompagnie.teintePale(
              Theme.of(context).colorScheme.primary,
              0.12,
            ),
            leading: Icon(
              Icons.local_shipping_outlined,
              color: ThemeCompagnie.accentDe(context),
            ),
            title: Text(
              chantierGeneral.nom,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Matériel de la remorque, séparé par contremaître et admin',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PastilleNonVus(nonVus, key: const ValueKey('pastille_general')),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MaterielGeneralScreen(source: source),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Un chantier de la liste : un toucher ouvre sa page ; le menu permet de le
/// modifier, de l'archiver ou de le restaurer.
class _TuileChantier extends StatelessWidget {
  final Chantier chantier;
  final Widget Function(Chantier chantier)? pageChantier;
  const _TuileChantier({required this.chantier, this.pageChantier});

  @override
  Widget build(BuildContext context) {
    final c = chantier;
    return ListTile(
      key: ValueKey('chantier_${c.id}'),
      leading: Icon(
        c.archive ? Icons.inventory_2_outlined : Icons.folder_open,
        color: ThemeCompagnie.accentDe(context),
      ),
      title: Text(c.nom),
      subtitle: Text(
        [if (c.adresse.isNotEmpty) c.adresse, if (c.archive) 'Archivé'].join(' • '),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              pageChantier?.call(c) ?? DossierChantierScreen(chantier: c),
        ),
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('menu_${c.id}'),
        onSelected: (v) {
          if (v == 'modifier') {
            ouvrirFormulaireChantier(
              context,
              docId: c.id,
              donnees: {'nom': c.nom, 'adresse': c.adresse},
            );
          } else {
            archiverOuRestaurerChantier(
              context,
              docId: c.id,
              nom: c.nom,
              archiver: v == 'archiver',
            );
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
          PopupMenuItem(
            value: c.archive ? 'restaurer' : 'archiver',
            child: Text(c.archive ? 'Restaurer' : 'Archiver'),
          ),
        ],
      ),
    );
  }
}
