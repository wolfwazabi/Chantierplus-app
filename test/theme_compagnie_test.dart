import 'dart:math';

import 'package:construction_app/services/theme_compagnie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rapport de contraste WCAG entre deux couleurs (1 à 21).
double contrasteTest(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  group('format « #RRGGBB »', () {
    test('lecture : avec ou sans #, majuscules ou minuscules', () {
      expect(ThemeCompagnie.depuisHex('#2F4A34'), const Color(0xFF2F4A34));
      expect(ThemeCompagnie.depuisHex('c62828'), const Color(0xFFC62828));
      expect(ThemeCompagnie.depuisHex(' #1565c0 '), const Color(0xFF1565C0));
    });

    test('valeurs invalides refusées', () {
      for (final v in [
        null,
        '',
        '#12345',
        '#1234567',
        'vert',
        '#GGGGGG',
        '#FFF',
      ]) {
        expect(ThemeCompagnie.depuisHex(v), isNull, reason: '$v');
      }
    });

    test(
      'écriture : toujours « #RRGGBB » en majuscules (format des règles)',
      () {
        expect(ThemeCompagnie.versHex(const Color(0xFF2F4A34)), '#2F4A34');
        expect(ThemeCompagnie.versHex(const Color(0xFF0000FF)), '#0000FF');
        expect(
          RegExp(r'^#[0-9A-F]{6}$')
              .hasMatch(ThemeCompagnie.versHex(const Color(0xFFABCDEF))),
          isTrue,
        );
      },
    );

    test('aller-retour sans perte pour toute la palette', () {
      for (final c in ThemeCompagnie.palette.values) {
        expect(ThemeCompagnie.depuisHex(ThemeCompagnie.versHex(c)), c);
      }
    });
  });

  group('lisibilité (WCAG)', () {
    // Palette + couleurs extrêmes qu'une compagnie pourrait saisir.
    final couleurs = {
      ...ThemeCompagnie.palette,
      'Blanc': const Color(0xFFFFFFFF),
      'Jaune vif': const Color(0xFFFFFF00),
      'Rose pâle': const Color(0xFFFFC0CB),
      'Cyan': const Color(0xFF00FFFF),
      'Gris moyen': const Color(0xFF808080),
      'Noir': const Color(0xFF000000),
    };

    for (final MapEntry(key: nom, value: c) in couleurs.entries) {
      test('$nom : texte des boutons lisible (≥ 4,5:1)', () {
        final texte = ThemeCompagnie.texteSur(c);
        expect(
          contrasteTest(c, texte),
          greaterThanOrEqualTo(4.5),
          reason: '$nom ${ThemeCompagnie.versHex(c)}',
        );
      });

      test('$nom : touches de fonction lisibles (≥ 4,5:1)', () {
        final v = ThemeCompagnie.variante(c);
        expect(
          contrasteTest(v, ThemeCompagnie.texteSur(v)),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$nom : accent lisible sur le fond crème (≥ 3:1)', () {
        expect(
          contrasteTest(ThemeCompagnie.accent(c), ThemeCompagnie.fondCreme),
          greaterThanOrEqualTo(3.0),
        );
      });
    }
  });

  test('appliquer : valeur invalide ou absente → vert par défaut', () {
    ThemeCompagnie.appliquer('#C62828');
    expect(ThemeCompagnie.couleur.value, const Color(0xFFC62828));
    ThemeCompagnie.appliquer('pas-une-couleur');
    expect(ThemeCompagnie.couleur.value, ThemeCompagnie.couleurParDefaut);
    ThemeCompagnie.appliquer(null);
    expect(ThemeCompagnie.couleur.value, ThemeCompagnie.couleurParDefaut);
  });
}
