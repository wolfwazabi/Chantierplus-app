import 'package:flutter/material.dart';

/// Un message (liste vide, erreur) qu'on peut aussi tirer vers le bas pour actualiser :
/// la zone défile toujours, même si elle ne contient presque rien.
Widget messageActualisable(Widget message) => LayoutBuilder(
  builder: (context, contraintes) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(
        height: contraintes.maxHeight.isFinite ? contraintes.maxHeight : 300,
        child: Center(child: message),
      ),
    ],
  ),
);

/// Pour les listes : à mettre sur le défilement pour que le geste fonctionne même quand
/// il y a peu d'éléments.
const ScrollPhysics defilementActualisable = AlwaysScrollableScrollPhysics();

/// Remplace un StreamBuilder : même construction, plus un geste « tirer vers le bas pour
/// actualiser » qui RELANCE la lecture (nouvelle écoute des données). Le contenu doit être
/// défilable (liste avec [defilementActualisable], ou [messageActualisable] pour un message).
class FluxActualisable<T> extends StatefulWidget {
  /// Crée la lecture ; rappelée à chaque actualisation.
  final Stream<T> Function() creerFlux;
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot)
  builder;

  /// Appelé à chaque actualisation (tests).
  final VoidCallback? surActualisation;

  const FluxActualisable({
    super.key,
    required this.creerFlux,
    required this.builder,
    this.surActualisation,
  });

  @override
  State<FluxActualisable<T>> createState() => _FluxActualisableState<T>();
}

class _FluxActualisableState<T> extends State<FluxActualisable<T>> {
  late Stream<T> _flux = _nouvelleEcoute();

  /// Un flux TOUJOURS neuf (même si la page garde le sien dans une variable) : le
  /// StreamBuilder ne se réabonne que si l'objet change.
  Stream<T> _nouvelleEcoute() => widget.creerFlux().map((e) => e);

  Future<void> _actualiser() async {
    widget.surActualisation?.call();
    // Nouvelle lecture : le StreamBuilder garde les données affichées en attendant les
    // fraîches (aucun écran de chargement qui clignote).
    setState(() => _flux = _nouvelleEcoute());
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _actualiser,
      child: StreamBuilder<T>(
        stream: _flux,
        builder: (context, snapshot) {
          final contenu = widget.builder(context, snapshot);
          // Un message centré (liste vide, erreur) devient tirable, lui aussi ; l'indicateur
          // de chargement reste tel quel.
          if (contenu is Center &&
              contenu.child is! CircularProgressIndicator) {
            final message = contenu.child;
            if (message != null) return messageActualisable(message);
          }
          return contenu;
        },
      ),
    );
  }
}

/// Comportement de défilement de l'application : toute page défile toujours, même courte,
/// pour que « tirer vers le bas pour actualiser » marche partout (sur iOS, l'effet
/// élastique habituel est conservé).
class DefilementActualisable extends MaterialScrollBehavior {
  const DefilementActualisable();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}

/// Tirer vers le bas pour actualiser une page chargée une seule fois (appel serveur,
/// lecture unique). Le contenu doit être défilable.
class PageActualisable extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const PageActualisable({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      RefreshIndicator(onRefresh: onRefresh, child: child);
}
