import 'package:flutter/material.dart';

import '../../services/theme_compagnie.dart';
import 'couleur_compagnie_screen.dart';
import 'regles_paie_screen.dart';
import 'semaine_liste_screen.dart';
import 'employes_liste_screen.dart';
import 'chantiers_gestion_screen.dart';
import 'documents_admin_screen.dart';
import 'dossiers_chantiers_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

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
            title: const Text('Gérer les chantiers'),
            subtitle: const Text('Ajouter, modifier ou retirer des chantiers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChantiersGestionScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.receipt_long_outlined, color: accent),
            title: const Text('Dossiers de chantier'),
            subtitle: const Text(
              'Résumé, facturation et export (archivés compris)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DossiersChantiersScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.folder_open, color: accent),
            title: const Text('Documents des chantiers'),
            subtitle: const Text('Déposer des plans, devis, photos…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DocumentsAdminScreen()),
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
