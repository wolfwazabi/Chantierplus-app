import 'package:flutter/material.dart';

/// Un onglet de la barre du bas.
class OngletBarre {
  final String label;
  final IconData icone;
  final IconData iconeSelectionne;
  const OngletBarre(this.label, this.icone, this.iconeSelectionne);
}

/// Barre d'onglets du bas, plus basse que la NavigationBar de Material (56 px
/// au lieu de 80) pour laisser plus de place à l'écran.
///
/// Les étiquettes se réduisent pour tenir sur une ligne (« Calculatrice »,
/// « Compagnies » avec six onglets) et gardent la même police sélectionnées ou
/// non : l'icône ne change donc jamais de hauteur quand on change d'onglet.
class BarreOnglets extends StatelessWidget {
  final List<OngletBarre> onglets;
  final int indexSelectionne;
  final ValueChanged<int> onSelection;

  static const double hauteur = 56;

  const BarreOnglets({
    super.key,
    required this.onglets,
    required this.indexSelectionne,
    required this.onSelection,
  });

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Material(
      color: couleurs.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: hauteur,
          child: Row(
            children: [
              for (var i = 0; i < onglets.length; i++)
                Expanded(
                  child: _Onglet(
                    onglet: onglets[i],
                    selectionne: i == indexSelectionne,
                    onTap: () => onSelection(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onglet extends StatelessWidget {
  final OngletBarre onglet;
  final bool selectionne;
  final VoidCallback onTap;

  const _Onglet({
    required this.onglet,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final couleur = selectionne ? couleurs.primary : couleurs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selectionne,
      label: onglet.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('onglet_${onglet.label}'),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pastille derrière l'icône de l'onglet actif ; même place dans
            // tous les cas, donc aucun saut.
            Container(
              width: 52,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selectionne
                    ? couleurs.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selectionne ? onglet.iconeSelectionne : onglet.icone,
                key: ValueKey('icone_${onglet.label}'),
                size: 22,
                color: couleur,
              ),
            ),
            SizedBox(
              height: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    onglet.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: couleur,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
