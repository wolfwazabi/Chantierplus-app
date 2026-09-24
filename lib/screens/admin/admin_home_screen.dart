import 'package:flutter/material.dart';

import 'semaine_liste_screen.dart';
import 'employes_liste_screen.dart';
import 'chantiers_gestion_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            leading: const Icon(Icons.access_time, color: Colors.orange),
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
            leading: const Icon(Icons.construction, color: Colors.orange),
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
            leading: const Icon(Icons.people, color: Colors.orange),
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
      ],
    );
  }
}
