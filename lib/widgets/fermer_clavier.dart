import 'package:flutter/material.dart';

/// Ferme le clavier quand on touche une zone vide de l'écran, partout dans l'app
/// (sur iPhone, un clavier numérique n'a pas de touche pour se fermer).
///
/// Un toucher sur un bouton, un champ ou une liste garde son effet habituel : seul
/// un toucher que personne d'autre n'utilise ferme le clavier.
class FermerClavier extends StatelessWidget {
  final Widget child;
  const FermerClavier({super.key, required this.child});

  /// Enlève le focus du champ en cours de saisie (ce qui ferme le clavier).
  static void fermer() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: fermer,
      child: child,
    );
  }
}
