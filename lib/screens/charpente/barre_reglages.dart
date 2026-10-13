import 'package:flutter/material.dart';

import '../../services/theme_compagnie.dart';

/// « Mes réglages habituels », au-dessus des réglages d'un onglet : dit si le calcul suit les
/// habitudes ; « Garder » en fait les réglages des prochains calculs, « Remettre » les rétablit.
/// Clés : `habitudes_<cle>`, `habitudes_garder_<cle>`, `habitudes_remettre_<cle>`.
class BarreReglagesHabituels extends StatelessWidget {
  final String cle;

  /// Des réglages habituels sont gardés pour cet onglet.
  final bool existe;

  /// Le calcul suit ces réglages.
  final bool suivis;

  final VoidCallback onGarder;
  final VoidCallback onRemettre;

  const BarreReglagesHabituels({
    super.key,
    required this.cle,
    required this.existe,
    required this.suivis,
    required this.onGarder,
    required this.onRemettre,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ThemeCompagnie.accentDe(context);
    final texte = !existe
        ? 'Aucun réglage habituel'
        : suivis
        ? 'Vos réglages habituels'
        : 'Différents de vos habitudes';
    final petit = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    return Container(
      key: ValueKey('habitudes_$cle'),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            suivis ? Icons.bookmark : Icons.bookmark_border,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(texte, style: theme.textTheme.bodyMedium),
            ),
          ),
          if (existe && !suivis)
            TextButton(
              key: ValueKey('habitudes_remettre_$cle'),
              style: petit,
              onPressed: onRemettre,
              child: const Text('Remettre'),
            ),
          if (!suivis)
            TextButton(
              key: ValueKey('habitudes_garder_$cle'),
              style: petit,
              onPressed: onGarder,
              child: Text(existe ? 'Garder' : 'Garder ceux-ci'),
            ),
        ],
      ),
    );
  }
}
