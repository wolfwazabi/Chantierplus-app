// Calculatrice (charpente), comme le Construction Master : la touche PITCH entre la pente
// (6 Po PITCH = 6/12 ; 6 PITCH = 6°) et, appuyée sans rien de tapé, la montre en pouces sur 12,
// en pente, en % de pente puis en degrés. DIAG rappelle la longueur seulement. Conv tient sur
// une ligne.
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

  /// Le rappel affiché (titre, valeur), vide s'il n'y en a pas.
  List<String> rappel(WidgetTester t) => [
    for (final w in t.widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('lcd_rappel')),
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

  group('touche PITCH', () {
    testWidgets('à la place d\'ANGLE, à côté de RUN, RISE et DIAG', (t) async {
      await ouvrir(t);
      expect(find.byKey(const ValueKey('touche_ANGLE')), findsNothing);
      expect(touche(t, 'PITCH'), ['PITCH', '—']);
      final y = t.getCenter(find.byKey(const ValueKey('touche_RUN'))).dy;
      expect(t.getCenter(find.byKey(const ValueKey('touche_PITCH'))).dy, y);
    });

    testWidgets('6 Po PITCH : un pitch de 6/12', (t) async {
      await ouvrir(t);
      await taper(t, ['6', 'Po', 'PITCH']);
      expect(touche(t, 'PITCH'), ['PITCH', '6']);
      expect(affiche('PITCH 6'), isTrue);
    });

    testWidgets('6 PITCH (sans unité) : 6°, soit 1 1/4/12', (t) async {
      await ouvrir(t);
      await taper(t, ['6', 'PITCH']);
      expect(touche(t, 'PITCH'), ['PITCH', '1 1/4']);
      await taper(t, ['PITCH', 'PITCH', 'PITCH', 'PITCH']);
      expect(rappel(t), ['PITCH', '6.00°']);
    });

    testWidgets(
      'appuyé de nouveau : pouces sur 12, pente, % de pente, degrés (comme le CM)',
      (t) async {
        await ouvrir(t);
        // 17,2° : les valeurs du Construction Master (3 11/16, 0.309552, 30.955171, 17.20°).
        await taper(t, ['1', '7', '.', '2', 'PITCH']);
        expect(find.byKey(const ValueKey('lcd_rappel')), findsNothing);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['PITCH', '3 11/16']);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['PENTE', '0.309552']);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['% PENTE', '30.955171']);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['PITCH', '17.20°']);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['PITCH', '3 11/16']);
        // La pente n'a pas changé.
        expect(touche(t, 'PITCH'), ['PITCH', '3 11/16']);
      },
    );

    testWidgets('RUN 144" et 6/12 : RISE 72" et DIAG 161"', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '6', 'Po', 'PITCH']);
      expect(touche(t, 'RISE'), ['RISE', '72"']);
      expect(touche(t, 'DIAG'), ['DIAG', '161"']);
    });

    testWidgets('la pente d\'abord, puis RUN : même résultat', (t) async {
      await ouvrir(t);
      await taper(t, ['6', 'Po', 'PITCH', '1', '4', '4', 'RUN']);
      expect(touche(t, 'RISE'), ['RISE', '72"']);
      expect(touche(t, 'DIAG'), ['DIAG', '161"']);
    });

    testWidgets(
      'une unité sur RUN ne fait pas de 6 PITCH un 6/12 : ce sont des degrés',
      (t) async {
        await ouvrir(t);
        await taper(t, ['1', '4', '4', 'Po', 'RUN', '6', 'PITCH']);
        expect(touche(t, 'PITCH'), ['PITCH', '1 1/4']);
        expect(touche(t, 'RISE'), ['RISE', '15 1/8"']); // 144 × tan 6°
        expect(touche(t, 'DIAG'), ['DIAG', '144 13/16"']);
      },
    );

    testWidgets('RUN et RISE donnent la pente', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '6', 'RISE']);
      expect(touche(t, 'PITCH'), ['PITCH', '6']);
      expect(touche(t, 'DIAG'), ['DIAG', '13 7/16"']);
    });

    testWidgets('les deux dernières valeurs entrées décident', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '6', 'RISE']);
      // Puis DIAG 15 : RISE et DIAG décident ; RUN est recalculé.
      await taper(t, ['1', '5', 'DIAG']);
      expect(touche(t, 'RISE'), ['RISE', '6"']);
      expect(touche(t, 'RUN'), ['RUN', '13 3/4"']); // √(225 − 36) = 13,75
      // Puis une pente : DIAG et la pente décident.
      await taper(t, ['3', '0', 'PITCH']);
      expect(touche(t, 'RISE'), ['RISE', '7 1/2"']); // 15 × sin 30°
    });

    testWidgets('une seule valeur : rien n\'est déduit', (t) async {
      await ouvrir(t);
      await taper(t, ['6', 'Po', 'PITCH']);
      expect(touche(t, 'RUN'), ['RUN', '—']);
      expect(touche(t, 'DIAG'), ['DIAG', '—']);
    });

    testWidgets('90° ou plus : refusé, rien ne change', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '9', '5', 'PITCH']);
      expect(affiche('Pitch en degrés : moins de 90°'), isTrue);
      expect(touche(t, 'PITCH'), ['PITCH', '—']);
      expect(touche(t, 'RUN'), ['RUN', '144"']);
    });

    testWidgets('on calcule avec la valeur rappelée', (t) async {
      await ouvrir(t);
      await taper(t, ['6', 'Po', 'PITCH', 'PITCH', 'PITCH']); // pente 0,5
      await taper(t, ['×', '2', '=']);
      expect(find.byKey(const ValueKey('lcd_rappel')), findsNothing);
      // Le grand chiffre du résultat (police de 42) : 0,5 × 2 = 1.
      final resultat = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 42,
      );
      expect(t.widget<Text>(resultat).data, '1');
    });

    testWidgets('AC efface aussi la pente', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '6', 'Po', 'PITCH', 'AC']);
      expect(touche(t, 'PITCH'), ['PITCH', '—']);
      expect(touche(t, 'RUN'), ['RUN', '—']);
      await taper(t, ['1', '2', 'RUN']);
      expect(touche(t, 'DIAG'), ['DIAG', '—']);
    });
  });

  group('DIAG : la mesure seulement', () {
    testWidgets('rien de tapé : la longueur, et elle reste la longueur', (
      t,
    ) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '6', 'Po', 'PITCH', 'DIAG']);
      expect(rappel(t), ['DIAG', '13\' 5"']);
      await taper(t, ['DIAG']);
      expect(rappel(t), ['DIAG', '13\' 5"']);
      expect(touche(t, 'DIAG'), ['DIAG', '161"']);
    });

    testWidgets('on calcule avec la diagonale rappelée : DIAG × 2', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '4', '4', 'RUN', '6', 'Po', 'PITCH', 'DIAG']);
      await taper(t, ['×', '2', '=']);
      expect(affiche('26\' 10"'), isTrue); // 161 × 2 = 322 po
    });

    testWidgets(
      'un chiffre quitte le rappel ; une valeur tapée devient la DIAG',
      (t) async {
        await ouvrir(t);
        await taper(t, ['1', '2', 'RUN', '6', 'RISE', 'DIAG']);
        expect(rappel(t).first, 'DIAG');
        await taper(t, ['1', '5']);
        expect(find.byKey(const ValueKey('lcd_rappel')), findsNothing);
        await taper(t, ['DIAG']);
        expect(touche(t, 'DIAG'), ['DIAG', '15"']);
        expect(touche(t, 'RUN'), ['RUN', '13 3/4"']);
      },
    );

    testWidgets('sans diagonale : rien ne s\'affiche', (t) async {
      await ouvrir(t);
      await taper(t, ['DIAG']);
      expect(find.byKey(const ValueKey('lcd_rappel')), findsNothing);
    });

    testWidgets('DIAG plus courte que RUN : dit, rien n\'est déduit', (
      t,
    ) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'RUN', '1', '0', 'DIAG']);
      expect(affiche('DIAG plus court que RUN'), isTrue);
      expect(touche(t, 'RISE'), ['RISE', '—']);
      expect(touche(t, 'PITCH'), ['PITCH', '—']);
    });
  });

  group('métrique', () {
    setUp(() => Preferences.unites.value = SystemeUnites.metrique);

    testWidgets('après RUN, la saisie repart de zéro (pas 3000 + 1000)', (
      t,
    ) async {
      await ouvrir(t);
      await taper(t, [
        '3', '0', '0', '0', 'mm', 'RUN', //
        '1', '0', '0', '0', 'mm', 'RISE',
      ]);
      expect(touche(t, 'RUN'), ['RUN', '3000 mm']);
      expect(touche(t, 'RISE'), ['RISE', '1000 mm']);
    });

    testWidgets(
      '500 mm PITCH : 500 mm de montée par mètre ; la pente sur 12 aussi',
      (t) async {
        await ouvrir(t);
        await taper(t, [
          '3',
          '0',
          '0',
          '0',
          'mm',
          'RUN',
          '5',
          '0',
          '0',
          'mm',
          'PITCH',
        ]);
        expect(touche(t, 'RISE'), ['RISE', '1500 mm']);
        expect(touche(t, 'PITCH'), ['PITCH', '6.00']);
        expect(affiche('PENTE 50.0 %'), isTrue);
        await taper(t, ['PITCH']);
        expect(rappel(t), ['PITCH', '6.00']);
      },
    );

    testWidgets('30 PITCH : 30° aussi en métrique', (t) async {
      await ouvrir(t);
      await taper(t, ['3', '0', '0', '0', 'mm', 'RUN', '3', '0', 'PITCH']);
      // RISE = 3000 × tan 30° = 1732,05 mm.
      expect(touche(t, 'RISE'), ['RISE', '1732.0508 mm']);
    });
  });
}
