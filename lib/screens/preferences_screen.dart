import 'package:flutter/material.dart';

import '../services/preferences.dart';

/// Préférences personnelles (enregistrées sur cet appareil).
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences')),
      body: ValueListenableBuilder<SystemeUnites>(
        valueListenable: Preferences.unites,
        builder: (context, unites, _) => RadioGroup<SystemeUnites>(
          groupValue: unites,
          onChanged: (v) {
            if (v != null) Preferences.choisirUnites(v);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Unités de mesure',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              RadioListTile<SystemeUnites>(
                key: ValueKey('unites_imperial'),
                value: SystemeUnites.imperial,
                title: Text('Impérial'),
                subtitle: Text(
                  'Pieds, pouces et fractions ; béton en pi et po',
                ),
              ),
              RadioListTile<SystemeUnites>(
                key: ValueKey('unites_metrique'),
                value: SystemeUnites.metrique,
                title: Text('Métrique'),
                subtitle: Text(
                  'Mètres, centimètres et millimètres ; béton en m³',
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'S\'applique aux calculatrices de charpente, de béton et de '
                  'matériaux. La touche Conv affiche toujours les pieds, pouces '
                  'et mètres. Réglage propre à cet appareil.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
