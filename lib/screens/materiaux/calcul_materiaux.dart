import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/preferences.dart';

/// Format de feuille (gypse, contreplaqué, OSB…) : dimensions en pieds.
class FormatFeuille {
  final String nom;
  final double largeurPi;
  final double longueurPi;
  const FormatFeuille(this.nom, this.largeurPi, this.longueurPi);

  double get surfacePi2 => largeurPi * longueurPi;
  double get surfaceM2 => surfacePi2 * 0.09290304;
}

const formatsFeuilles = [
  FormatFeuille('4 × 8 pi', 4, 8),
  FormatFeuille('4 × 9 pi', 4, 9),
  FormatFeuille('4 × 10 pi', 4, 10),
  FormatFeuille('4 × 12 pi', 4, 12),
  FormatFeuille('OSB isolant R-4 (Isobrace) 4 × 9 pi', 4, 9),
];

/// Nombre de feuilles pour couvrir [surface] (pi² ou m² selon [metrique]),
/// perte incluse, arrondi à la feuille supérieure.
int nombreDeFeuilles({
  required double surface,
  required FormatFeuille format,
  required double pertePourcent,
  required bool metrique,
}) {
  if (surface <= 0) return 0;
  final parFeuille = metrique ? format.surfaceM2 : format.surfacePi2;
  final aCouvrir = surface * (1 + pertePourcent / 100);
  // Petite tolérance : 64 pi² en 4×8 donne 2 feuilles, pas 3.
  return (aCouvrir / parFeuille - 1e-9).ceil();
}

/// Calcul de matériaux en feuilles (onglet Chantier).
class CalculMateriaux extends StatefulWidget {
  const CalculMateriaux({super.key});

  @override
  State<CalculMateriaux> createState() => _CalculMateriauxState();
}

class _CalculMateriauxState extends State<CalculMateriaux> {
  final _surfaceCtrl = TextEditingController();
  final _perteCtrl = TextEditingController(text: '10');
  FormatFeuille _format = formatsFeuilles.first;

  @override
  void dispose() {
    _surfaceCtrl.dispose();
    _perteCtrl.dispose();
    super.dispose();
  }

  double? _lire(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SystemeUnites>(
      valueListenable: Preferences.unites,
      builder: (context, unites, _) {
        final metrique = unites == SystemeUnites.metrique;
        final unite = metrique ? 'm²' : 'pi²';
        final surface = _lire(_surfaceCtrl);
        final perte = _lire(_perteCtrl) ?? 0;
        final feuilles = surface == null || perte < 0
            ? null
            : nombreDeFeuilles(
                surface: surface,
                format: _format,
                pertePourcent: perte,
                metrique: metrique,
              );
        final nombre = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Feuilles de gypse, contreplaqué ou OSB',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('materiaux_surface'),
              controller: _surfaceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [nombre],
              decoration: InputDecoration(
                labelText: 'Surface à couvrir',
                suffixText: unite,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FormatFeuille>(
              key: const ValueKey('materiaux_format'),
              initialValue: _format,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Format de feuille',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final f in formatsFeuilles)
                  DropdownMenuItem(
                    value: f,
                    child: Text(
                      metrique
                          ? '${f.nom} (${f.surfaceM2.toStringAsFixed(2)} m²)'
                          : '${f.nom} (${f.surfacePi2.toStringAsFixed(0)} pi²)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (f) => setState(() => _format = f ?? _format),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('materiaux_perte'),
              controller: _perteCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [nombre],
              decoration: const InputDecoration(
                labelText: 'Perte',
                suffixText: '%',
                helperText: 'Coupes et chutes ; 10 à 15 % est courant.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: feuilles == null
                    ? const Text('Entrez la surface à couvrir.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$feuilles feuille${feuilles > 1 ? 's' : ''} de ${_format.nom}',
                            key: const ValueKey('materiaux_resultat'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pour ${surface!.toStringAsFixed(1)} $unite, '
                            '${perte.toStringAsFixed(0)} % de perte incluse.',
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
