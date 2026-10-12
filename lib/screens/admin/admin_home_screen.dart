import 'package:flutter/material.dart';

import '../../services/liste_achats_source.dart';
import '../../services/materiel_general_source.dart';
import '../../services/theme_compagnie.dart';
import 'couleur_compagnie_screen.dart';
import 'liste_achats_screen.dart';
import 'materiel_general_screen.dart';
import 'regles_paie_screen.dart';
import 'semaine_liste_screen.dart';
import 'employes_liste_screen.dart';
import 'chantiers_gestion_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  /// Remplace Firestore pour la pastille du matériel Général (tests).
  @visibleForTesting
  final SourceMaterielGeneral? sourceMateriel;

  /// Remplace Firestore pour la Liste d'achats (tests).
  @visibleForTesting
  final SourceListeAchats? sourceAchats;

  const AdminHomeScreen({super.key, this.sourceMateriel, this.sourceAchats});

  @override
  Widget build(BuildContext context) {
    final accent = ThemeCompagnie.accentDe(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Admin',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(Icons.access_time, color: accent),
            title: const Text('Heures employés'),
            subtitle: const Text('Voir les heures soumises par semaine'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => SemaineListeScreen()));
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.rule, color: accent),
            title: const Text('Heures et voyagement'),
            subtitle: const Text('Pauses, dîner et voyagement payés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReglesPaieScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.construction, color: accent),
            title: const Text('Chantiers'),
            subtitle: const Text(
              'Ajouter, modifier, archiver · photos, documents, heures et export',
            ),
            // Pastille : du matériel Général a changé depuis votre dernière visite.
            trailing: NonVusGeneral(
              source: sourceMateriel,
              builder: (context, nonVus) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PastilleNonVus(
                    nonVus,
                    key: const ValueKey('pastille_chantiers'),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ChantiersGestionScreen(sourceMateriel: sourceMateriel),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.shopping_cart_checkout, color: accent),
            title: const Text('Liste d\'achats'),
            subtitle: const Text('Matériel à acheter, transféré depuis Général'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ListeAchatsScreen(source: sourceAchats),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.people, color: accent),
            title: const Text('Gestion des employés'),
            subtitle: const Text('Ajouter, modifier ou retirer des comptes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => EmployesListeScreen()));
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.palette_outlined, color: accent),
            title: const Text('Couleur de l\'application'),
            subtitle: const Text('Aux couleurs de votre compagnie'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CouleurCompagnieScreen(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
