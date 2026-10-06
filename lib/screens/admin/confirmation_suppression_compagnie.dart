import 'package:flutter/material.dart';

/// Ce que supprime la suppression d'une compagnie (affiché à la 1re étape).
const consequencesSuppressionCompagnie = [
  'tous ses employés, admins et contremaîtres (leurs accès)',
  'ses chantiers, photos et documents',
  'ses feuilles de temps, extras, matériel et commandes',
  'tous ses fichiers enregistrés',
];

/// Double vérification avant de supprimer une compagnie. Retourne true
/// seulement si l'utilisateur passe les deux étapes :
///  1. lire ce qui sera supprimé et choisir « Continuer » ;
///  2. saisir le numéro exact de la compagnie.
/// Le serveur vérifie ce numéro une troisième fois.
Future<bool> confirmerSuppressionCompagnie(
  BuildContext context, {
  required String nom,
  required String numero,
}) async {
  final continuer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Supprimer « $nom » ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compagnie n° $numero',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text('Seront supprimés définitivement :'),
            const SizedBox(height: 4),
            for (final c in consequencesSuppressionCompagnie) Text('• $c'),
            const SizedBox(height: 10),
            const Text(
              'Cette action est irréversible. Aucune copie n\'est conservée.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('suppression_annuler_1'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const ValueKey('suppression_continuer'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continuer', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (continuer != true || !context.mounted) return false;
  final confirme = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogueNumero(nom: nom, numero: numero),
  );
  return confirme == true;
}

class _DialogueNumero extends StatefulWidget {
  final String nom;
  final String numero;
  const _DialogueNumero({required this.nom, required this.numero});

  @override
  State<_DialogueNumero> createState() => _DialogueNumeroState();
}

class _DialogueNumeroState extends State<_DialogueNumero> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _correct =>
      widget.numero.isNotEmpty && _ctrl.text.trim() == widget.numero;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dernière vérification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pour supprimer « ${widget.nom} », saisissez son numéro de '
            'compagnie : ${widget.numero}',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('suppression_numero'),
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Numéro de la compagnie',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('suppression_annuler_2'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('suppression_confirmer'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _correct ? () => Navigator.pop(context, true) : null,
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
