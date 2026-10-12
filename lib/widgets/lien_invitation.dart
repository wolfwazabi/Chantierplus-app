import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Solution de repli si le courriel n'a pas pu partir : le lien (usage unique, 7 jours)
/// est montré une seule fois à l'admin, qui le transmet à l'employé.
Future<void> afficherLienDeSecours(
  BuildContext context,
  String nom,
  String lien,
) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Courriel non envoyé'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Le courriel n\'a pas pu partir. Transmettez ce lien à $nom '
            '(texto, par exemple) pour qu\'il crée son NIP. Il ne sera plus '
            'affiché, fonctionne une seule fois et expire dans 7 jours.',
          ),
          const SizedBox(height: 12),
          SelectableText(lien, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: lien)),
          child: const Text('Copier le lien'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('C\'est noté'),
        ),
      ],
    ),
  );
}
