// Calculatrice (charpente) : la touche Conv tient sur une ligne, et la touche ANGLE (degrés)
// complète RUN, RISE et DIAG : les deux dernières valeurs entrées donnent les deux autres.
import 'dart:math';

import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Preferences.unites.value = SystemeUnites.imperial;
    CalculatriceScreen.mode.value = ModeCalculatrice.charpente;
  });

  Future<void> ouvrir(
    WidgetTester t, {
    Size taille = const Size(1080, 2400),
  }) async {
    t.view.physicalSize = taille;
    t.view.devicePixelRatio = taille.width > 500 ? 2.5 : 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalculatriceScreen(key: UniqueKey())),
      ),
    );
  }

  Future<void> taper(WidgetTester t, List<String> touches) async {
    for (final k in touches) {
      final touche = find.byKey(ValueKey('touche_$k'));
      expect(touche, findsOneWidget, reason: 'touche « $k »');
      await t.tap(touche);
      await t.pump();
    }
  }

  /// Les textes affichés sur une touche (libellé, puis valeur).
  List<String> touche(WidgetTester t, String k) => [
    for (final w in t.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('touche_$k')),
        matching: find.byType(Text),
      ),
    ))
      w.data!,
  ];

  bool affiche(String texte) =>
      find.textContaining(texte).evaluate().isNotEmpty;

  group('touche Conv', () {
    testWidgets(
      'sur une seule ligne, même sur un petit téléphone (360 de large)',
      (t) async {
        await ouvrir(t, taille: const Size(360, 560));
        final conv = find.descendant(
          of: find.byKey(const ValueKey('touche_Conv')),
          matching: find.byType(Text),
        );
        final texte = t.widget<Text>(conv);
        expect(texte.maxLines, 1);
        expect(texte.softWrap, isFalse);
        // Une ligne de 20 : jamais la hauteur de deux lignes.
        expect(t.getSize(conv).height, lessThan(30));
        // Le libellé rétrécit au besoin : il reste dans sa touche.
        final bouton = t.getRect(find.byKey(const ValueKey('touche_Conv')));
        final libelle = t.getRect(conv);
        expect(
          bouton.left <= libelle.left && libelle.right <= bouton.right,
          isTrue,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('Conv fonctionne toujours', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'Po', 'Conv']);
      expect(affiche('0.305 m'), isTrue);
    });
  });

  group('DIAG appuyé de nouveau : longueur, pente sur 12, angle', () {
    List<String> vue(WidgetTester t) => [
      for (final w in t.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('lcd_vue_diag')),
          matching: find.byType(Text),
        ),
      ))
        w.data!,
    ];

    testWidgets('chaque appui passe à la vue suivante, puis revient', (
      t,
    ) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '3', '0', 'ANGLE']);
      expect(find.byKey(const ValueKey('lcd_vue_diag')), findsNothing);
      await taper(t, ['DIAG']);
      expect(vue(t), ['DIAG', '13\' 10 1/4"']);
      await taper(t, ['DIAG']);
      expect(vue(t), ['PITCH', '6.93/12']);
      await taper(t, ['DIAG']);
      expect(vue(t), ['ANGLE', '30.0°']);
      await taper(t, ['DIAG']);
      expect(vue(t), ['DIAG', '13\' 10 1/4"']);
      // La diagonale n'a pas changé.
      expect(touche(t, 'DIAG'), ['DIAG', '166 1/4"']);
    });

    testWidgets('on calcule avec la diagonale rappelée : DIAG × 2', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '3', '0', 'ANGLE', 'DIAG', 'DIAG']);
      await taper(t, ['×', '2', '=']);
      expect(find.byKey(const ValueKey('lcd_vue_diag')), findsNothing);
      expect(affiche('27\' 8 9/16"'), isTrue); // 166,28 × 2 = 332,55
    });

    testWidgets(
      'un chiffre quitte la vue ; une valeur tapée est gardée comme DIAG',
      (t) async {
        await ouvrir(t);
        await taper(t, ['1', '2', 'RUN', '6', 'RISE', 'DIAG']);
        expect(vue(t).first, 'DIAG');
        await taper(t, ['1', '5']);
        expect(find.byKey(const ValueKey('lcd_vue_diag')), findsNothing);
        await taper(t, ['DIAG']);
        // 15 tapé : c'est la nouvelle diagonale (RISE et DIAG décident).
        expect(touche(t, 'DIAG'), ['DIAG', '15"']);
        expect(touche(t, 'RUN'), ['RUN', '13 3/4"']);
      },
    );

    testWidgets('diagonale seule (pas de pente) : la longueur seulement', (
      t,
    ) async {
      await ouvrir(t);
      await taper(t, ['1', '2', '0', 'DIAG', 'DIAG']);
      expect(vue(t).first, 'DIAG');
      await taper(t, ['DIAG']);
      expect(vue(t).first, 'DIAG');
    });

    testWidgets('sans diagonale : rien ne s\'affiche', (t) async {
      await ouvrir(t);
      await taper(t, ['DIAG']);
      expect(find.byKey(const ValueKey('lcd_vue_diag')), findsNothing);
    });

    testWidgets('en métrique : la pente sur 12, avec le %', (t) async {
      Preferences.unites.value = SystemeUnites.metrique;
      await ouvrir(t);
      await taper(t, ['3', '0', '0', '0', 'mm', 'RUN', '3', '0', 'ANGLE']);
      await taper(t, ['DIAG', 'DIAG']);
      expect(vue(t), ['PITCH (57.7 %)', '6.93/12']);
    });
  });

  group('touche ANGLE (degrés)', () {
    testWidgets('présente à côté de RUN, RISE et DIAG', (t) async {
      await ouvrir(t);
      expect(touche(t, 'ANGLE'), ['ANGLE', '—']);
      final y = t.getCenter(find.byKey(const ValueKey('touche_RUN'))).dy;
      expect(t.getCenter(find.byKey(const ValueKey('touche_ANGLE'))).dy, y);
    });

    testWidgets('RUN 144" et 30° : RISE et DIAG calculés', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '3', '0', 'ANGLE']);
      // RISE = 144 × tan 30° = 83,14 ; DIAG = 144 / cos 30° = 166,28.
      expect(touche(t, 'ANGLE'), ['ANGLE', '30.0°']);
      expect(touche(t, 'RISE'), ['RISE', '83 1/8"']);
      expect(touche(t, 'DIAG'), ['DIAG', '166 1/4"']);
      expect(affiche('PITCH 6.93/12 · 30.0°'), isTrue);
    });

    testWidgets('l\'angle d\'abord, puis RUN : même résultat', (t) async {
      await ouvrir(t);
      await taper(t, ['3', '0', 'ANGLE', '1', '4', '4', 'RUN']);
      expect(touche(t, 'RISE'), ['RISE', '83 1/8"']);
      expect(touche(t, 'DIAG'), ['DIAG', '166 1/4"']);
    });

    testWidgets('DIAG 120" à 45° : RUN et RISE égaux', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', '0', 'DIAG', '4', '5', 'ANGLE']);
      final cote = 120 * cos(pi / 4); // 84,85
      expect(cote, closeTo(84.85, 0.01));
      expect(touche(t, 'RUN'), ['RUN', '84 7/8"']);
      expect(touche(t, 'RISE'), ['RISE', '84 7/8"']);
    });

    testWidgets('RISE 48" à 20° : RUN et DIAG', (t) async {
      await ouvrir(t);
      await taper(t, ['4', '8', 'RISE', '2', '0', 'ANGLE']);
      // RUN = 48 / tan 20° = 131,88 ; DIAG = 48 / sin 20° = 140,34.
      expect(touche(t, 'RUN'), ['RUN', '131 7/8"']);
      expect(touche(t, 'DIAG'), ['DIAG', '140 5/16"']); // 140,34
    });

    testWidgets('RUN et RISE donnent l\'angle', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '6', 'RISE']);
      expect(touche(t, 'ANGLE'), ['ANGLE', '26.6°']);
      expect(touche(t, 'DIAG'), ['DIAG', '13 7/16"']);
    });

    testWidgets('les deux dernières valeurs entrées décident', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '6', 'RISE']);
      // Puis DIAG 15 : RISE et DIAG sont les deux dernières ; RUN est recalculé.
      await taper(t, ['1', '5', 'DIAG']);
      expect(touche(t, 'RISE'), ['RISE', '6"']);
      expect(touche(t, 'RUN'), ['RUN', '13 3/4"']); // √(225 − 36) = 13,75
      expect(touche(t, 'ANGLE'), ['ANGLE', '23.6°']); // asin(6 / 15)
      // Puis un angle : DIAG et l'angle décident.
      await taper(t, ['3', '0', 'ANGLE']);
      expect(touche(t, 'RISE'), ['RISE', '7 1/2"']); // 15 × sin 30°
    });

    testWidgets('une seule valeur : rien n\'est déduit', (t) async {
      await ouvrir(t);
      await taper(t, ['3', '0', 'ANGLE']);
      expect(touche(t, 'RUN'), ['RUN', '—']);
      expect(touche(t, 'DIAG'), ['DIAG', '—']);
    });

    testWidgets('angle hors de 0 à 90° : refusé, rien ne change', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '9', '5', 'ANGLE']);
      expect(affiche('Angle entre 0 et 90°'), isTrue);
      expect(touche(t, 'ANGLE'), ['ANGLE', '—']);
      expect(touche(t, 'RUN'), ['RUN', '144"']);
    });

    testWidgets('DIAG plus court que RUN : dit, rien n\'est déduit', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '1', '0', 'DIAG']);
      expect(affiche('DIAG plus court que RUN'), isTrue);
      expect(touche(t, 'RISE'), ['RISE', '—']);
      expect(touche(t, 'ANGLE'), ['ANGLE', '—']);
    });

    testWidgets('AC efface aussi l\'angle', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '3', '0', 'ANGLE', 'AC']);
      expect(touche(t, 'ANGLE'), ['ANGLE', '—']);
      expect(touche(t, 'RUN'), ['RUN', '—']);
      // Après AC, une seule valeur : rien n'est déduit de l'ancien triangle.
      await taper(t, ['1', '2', 'RUN']);
      expect(touche(t, 'DIAG'), ['DIAG', '—']);
    });

    testWidgets(
      'en métrique, après RUN la saisie repart de zéro (pas 3000 + 1000)',
      (t) async {
        Preferences.unites.value = SystemeUnites.metrique;
        await ouvrir(t);
        await taper(t, [
          '3',
          '0',
          '0',
          '0',
          'mm',
          'RUN',
          '1',
          '0',
          '0',
          '0',
          'mm',
          'RISE',
        ]);
        expect(touche(t, 'RUN'), ['RUN', '3000 mm']);
        expect(touche(t, 'RISE'), ['RISE', '1000 mm']);
      },
    );

    testWidgets('en métrique : RUN 3000 mm à 30°', (t) async {
      Preferences.unites.value = SystemeUnites.metrique;
      await ouvrir(t);
      await taper(t, ['3', '0', '0', '0', 'mm', 'RUN', '3', '0', 'ANGLE']);
      // RISE = 3000 × tan 30° = 1732,05 mm.
      expect(touche(t, 'RISE'), ['RISE', '1732.0508 mm']);
      expect(affiche('PENTE 57.7 % · 30.0°'), isTrue);
    });
  });
}
