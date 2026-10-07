import 'dart:math';

import 'package:flutter/material.dart';

/// Couleur de l'application choisie par chaque compagnie.
///
/// Stockée dans companies/{id}.couleurTheme au format « #RRGGBB » ;
/// modifiable par les admins de la compagnie (voir firestore.rules).
/// Tout le thème (barres, boutons, onglets, calculatrice) en découle.
class ThemeCompagnie {
  /// Vert d'origine de l'application, utilisé hors compagnie (particuliers,
  /// écran de connexion) et tant qu'une compagnie n'a rien choisi.
  static const Color couleurParDefaut = Color(0xFF2F4A34);

  static const Color fondCreme = Color(0xFFEAE2D0);
  static const Color surfaceCreme = Color(0xFFDDD2B8);
  static const Color texteFonce = Color(0xFF1E1E1A);

  /// Couleur active, écoutée par l'application pour se redessiner.
  static final ValueNotifier<Color> couleur = ValueNotifier(couleurParDefaut);

  /// Palette proposée : couleurs assez soutenues pour les barres et boutons.
  static const Map<String, Color> palette = {
    'Vert forêt': Color(0xFF2F4A34),
    'Vert': Color(0xFF2E7D32),
    'Bleu marine': Color(0xFF1F3A5F),
    'Bleu': Color(0xFF1565C0),
    'Turquoise': Color(0xFF00796B),
    'Rouge': Color(0xFFC62828),
    'Bourgogne': Color(0xFF7B1F2B),
    'Orange': Color(0xFFE65100),
    'Jaune chantier': Color(0xFFF2B705),
    'Brun': Color(0xFF5D4037),
    'Violet': Color(0xFF5E35B1),
    'Gris anthracite': Color(0xFF37474F),
    'Noir': Color(0xFF1C1C1C),
  };

  static final RegExp _formatHex = RegExp(r'^#?[0-9A-Fa-f]{6}$');

  /// « #2F4A34 » ou « 2f4a34 » → couleur ; null si le format est invalide.
  static Color? depuisHex(String? texte) {
    if (texte == null) return null;
    final t = texte.trim();
    if (!_formatHex.hasMatch(t)) return null;
    return Color(0xFF000000 | int.parse(t.replaceFirst('#', ''), radix: 16));
  }

  /// Couleur → « #2F4A34 » (majuscules, format exigé par les règles).
  static String versHex(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Rapport de contraste WCAG entre deux couleurs (1 à 21).
  static double contraste(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  static const Color _blanc = Color(0xFFFFFFFF);
  static const Color _noir = Color(0xFF000000);

  /// Texte lisible sur [fond] (≥ 4,5:1, norme WCAG AA) : le crème habituel
  /// s'il est assez lisible, sinon le plus contrasté entre blanc et noir
  /// (l'un des deux atteint toujours au moins 4,58:1).
  static Color texteSur(Color fond) {
    if (contraste(fond, fondCreme) >= 4.5) return fondCreme;
    return contraste(fond, _blanc) >= contraste(fond, _noir) ? _blanc : _noir;
  }

  /// Couleurs d'une barre d'onglets placée dans la barre du haut (AppBar) de
  /// couleur [barre] : l'onglet choisi en pleine couleur de texte, les autres un
  /// peu atténués mais toujours lisibles (≥ 4,5:1). Sans cela, l'onglet choisi
  /// prend la couleur principale, donc la même que la barre (vert sur vert).
  static ({Color actif, Color inactif}) ongletsSurBarre(Color barre) {
    final actif = texteSur(barre);
    var force = 0.72;
    var inactif = Color.alphaBlend(actif.withValues(alpha: force), barre);
    while (contraste(inactif, barre) < 4.5 && force < 1.0) {
      force = min(1.0, force + 0.04);
      inactif = Color.alphaBlend(actif.withValues(alpha: force), barre);
    }
    return (actif: actif, inactif: inactif);
  }

  /// Variante plus claire pour les touches de fonction de la calculatrice.
  static Color variante(Color c) {
    final hsl = HSLColor.fromColor(c);
    final clarte = hsl.lightness < 0.5
        ? (hsl.lightness + 0.12).clamp(0.0, 1.0)
        : (hsl.lightness - 0.12).clamp(0.0, 1.0);
    return hsl.withLightness(clarte).toColor();
  }

  /// Teinte très pâle de la couleur (fond de l'écran de la calculatrice,
  /// indicateur d'onglet) : texte foncé toujours lisible dessus.
  static Color teintePale(Color c, [double force = 0.28]) =>
      Color.alphaBlend(c.withValues(alpha: force), fondCreme);

  /// Met à jour la couleur active à partir de la valeur Firestore.
  static void appliquer(String? hex) {
    couleur.value = depuisHex(hex) ?? couleurParDefaut;
  }

  static void reinitialiser() => couleur.value = couleurParDefaut;

  /// Thème Material complet à partir de la couleur de la compagnie.
  static ThemeData construire(Color principale) {
    final surPrincipale = texteSur(principale);
    const inactif = Color(0xFF8A8066);
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: fondCreme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: principale,
        primary: principale,
        onPrimary: surPrincipale,
        secondary: variante(principale),
        onSecondary: texteSur(variante(principale)),
        surface: surfaceCreme,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: principale,
        foregroundColor: surPrincipale,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceCreme,
        indicatorColor: principale.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selectionne = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selectionne ? _lisibleSurCreme(principale) : inactif,
            fontWeight: selectionne ? FontWeight.w600 : FontWeight.normal,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selectionne = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selectionne ? _lisibleSurCreme(principale) : inactif,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: principale,
          foregroundColor: surPrincipale,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: principale,
        foregroundColor: surPrincipale,
      ),
    );
  }

  /// La couleur telle quelle si elle se lit sur le fond crème (≥ 3:1, texte
  /// en gras et icônes), sinon assombrie jusqu'à l'être (ex. jaune chantier).
  static Color _lisibleSurCreme(Color c) {
    var hsl = HSLColor.fromColor(c);
    while (contraste(hsl.toColor(), fondCreme) < 3.0 && hsl.lightness > 0) {
      hsl = hsl.withLightness(max(0, hsl.lightness - 0.05));
    }
    return hsl.toColor();
  }

  /// Couleur d'accent (icônes, textes) lisible sur le fond crème.
  static Color accent(Color c) => _lisibleSurCreme(c);

  /// Accent de la compagnie à partir du thème courant.
  static Color accentDe(BuildContext context) =>
      accent(Theme.of(context).colorScheme.primary);
}
