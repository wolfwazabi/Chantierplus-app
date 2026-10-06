import 'package:flutter/material.dart';

/// Demande une confirmation avant une action irréversible. Retourne true
/// seulement si l'utilisateur appuie sur le bouton d'action.
Future<bool> confirmerAction(
  BuildContext context, {
  required String titre,
  required String texte,
  required String action,
  bool destructive = true,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const ValueKey('confirmer_action'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            action,
            style: destructive ? const TextStyle(color: Colors.red) : null,
          ),
        ),
      ],
    ),
  );
  return confirme == true;
}
