// Calculatrice : les unités de l'autre système en petites touches (m, cm, mm en impérial ;
// Pi, Po, / en métrique), au-dessus de celles du système choisi. Utile pour Conv : on tape la
// mesure dans ses unités et la calculatrice la ramène à son unité de base.
import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:construction_app/screens/charpente/ecran_escalier.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Preferences.unites.value = SystemeUnites.imperial;
    CalculatriceScreen.mode.value = ModeCalculatrice.charpente;
  });

  Future<void> ouvrir(WidgetTester t, {bool metrique = false}) async {
    Preferences.unites.value = metrique
        ? SystemeUnites.metrique
        : SystemeUnites.imperial;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
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

  String resultat(WidgetTester t) => t
      .widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 42),
      )
      .data!;

  bool affiche(String texte) =>
      find.textContaining(texte).evaluate().isNotEmpty;

  group('disposition : 5 colonnes comme le Construction Master', () {
    // Chaque rangée, de gauche à droite (sous la petite rangée de la mémoire).
    const grille = [
      ['PITCH', 'RISE', 'RUN', 'DIAG', 'Conv'],
      ['m', 'cm', 'mm', 'x²', 'x³'],
      ['Pi', 'Po', '/', '⌫', 'AC'],
      ['(', '7', '8', '9', '÷'],
      [')', '4', '5', '6', '×'],
      ['%', '1', '2', '3', '−'],
      ['√x', '0', '.', '=', '+'],
    ];

    for (final metrique in [false, true]) {
      testWidgets(
        'toutes les cases remplies, alignées en colonnes (${metrique ? 'métrique' : 'impérial'})',
        (t) async {
          await ouvrir(t, metrique: metrique);
          Rect r(String k) => t.getRect(find.byKey(ValueKey('touche_$k')));
          for (var i = 0; i < grille.length; i++) {
            for (var j = 0; j < 5; j++) {
              final k = grille[i][j];
              expect(
                find.byKey(ValueKey('touche_$k')),
                findsOneWidget,
                reason: k,
              );
              // Même rangée : même hauteur ; même colonne : même position.
              expect(
                r(k).center.dy,
                closeTo(r(grille[i][0]).center.dy, 1),
                reason: k,
              );
              expect(
                r(k).center.dx,
                closeTo(r(grille[0][j]).center.dx, 1),
                reason: k,
              );
              expect(r(k).height, closeTo(r('7').height, 1), reason: k);
              if (i > 0) {
                expect(
                  r(k).top,
                  greaterThan(r(grille[i - 1][j]).bottom - 1),
                  reason: k,
                );
              }
            }
          }
          // Plus de touche ANGLE ni de petite rangée d'unités.
          expect(find.byKey(const ValueKey('touche_ANGLE')), findsNothing);
        },
      );
    }

    testWidgets(
      'des touches plus hautes qu\'avant sur un téléphone ordinaire',
      (t) async {
        t.view.physicalSize = const Size(360 * 3, 740 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: CalculatriceScreen())),
        );
        await t.pump();
        // Avant : environ 45 de haut ; maintenant plus de 55.
        expect(
          t.getSize(find.byKey(const ValueKey('touche_7'))).height,
          greaterThan(55),
        );
      },
    );
  });

  group('impérial : m, cm, mm pour Conv', () {
    testWidgets('3048 mm Conv : 10 pi, 120 po, 3,048 m', (t) async {
      await ouvrir(t);
      await taper(t, ['3', '0', '4', '8', 'mm', 'Conv']);
      expect(resultat(t), '10\' 0"');
      expect(affiche('120 po'), isTrue);
      expect(affiche('3.048 m'), isTrue);
      expect(affiche('304.8 cm'), isTrue);
    });

    testWidgets('1 m = 3\' 3 3/8"', (t) async {
      await ouvrir(t);
      await taper(t, ['1', 'm', '=']);
      expect(resultat(t), '3\' 3 3/8"');
    });

    testWidgets('mêlées : 1 pi + 30 cm = 1\' 11 13/16"', (t) async {
      await ouvrir(t);
      await taper(t, ['1', 'Pi', '3', '0', 'cm', '=']);
      expect(resultat(t), '1\' 11 13/16"');
    });

    testWidgets('dans un calcul : 2 m − 6 pi = 6 3/4"', (t) async {
      await ouvrir(t);
      await taper(t, ['2', 'm', '−', '6', 'Pi', '=']);
      // 78,74 − 72 = 6,74 po.
      expect(resultat(t), '6 3/4"');
    });

    testWidgets('pour RUN aussi : 3 m RUN', (t) async {
      await ouvrir(t);
      await taper(t, ['3', 'm', 'RUN']);
      final valeur = t
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('touche_RUN')),
              matching: find.byType(Text),
            ),
          )
          .last
          .data;
      expect(valeur, '118 1/8"'); // 3000 mm = 118,11 po
    });

    testWidgets('⌫ efface aussi une unité métrique', (t) async {
      await ouvrir(t);
      await taper(t, ['3', '0', 'cm', '⌫', '=']);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 42),
        findsNothing,
      );
    });
  });

  group('métrique : Pi, Po, / en petites touches', () {
    testWidgets('1 pi = 30 cm 4,8 mm', (t) async {
      await ouvrir(t, metrique: true);
      await taper(t, ['1', 'Pi', '=']);
      expect(resultat(t), '30 cm 4.8 mm');
    });

    testWidgets('1 1/2 po = 3 cm 8,1 mm', (t) async {
      await ouvrir(t, metrique: true);
      await taper(t, ['1', 'Po', '1', '/', '2', '=']);
      expect(resultat(t), '3 cm 8.1 mm');
    });

    testWidgets('8 pi Conv : 2,438 m', (t) async {
      await ouvrir(t, metrique: true);
      await taper(t, ['8', 'Pi', 'Conv']);
      expect(affiche('2.438 m'), isTrue);
      expect(affiche('96 po'), isTrue);
    });
  });

  group('mode Escalier, à côté de Béton', () {
    tearDown(() => CalculatriceScreen.mode.value = ModeCalculatrice.charpente);

    testWidgets(
      'le calculateur d\'escalier du chantier, et il garde ses valeurs',
      (t) async {
        await ouvrir(t);
        final boutons = [
          for (final m in ['charpente', 'beton', 'escalier'])
            t.getCenter(find.byKey(ValueKey('mode_$m'))).dx,
        ];
        expect(boutons, orderedEquals([...boutons]..sort()));
        expect(find.text('Escalier'), findsOneWidget);

        await t.tap(find.byKey(const ValueKey('mode_escalier')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('escalier_hauteur')), findsOneWidget);
        expect(find.byKey(const ValueKey('touche_7')), findsNothing);
        // La version simple : les limons seulement (ni composite ni matériaux).
        expect(
          t.widget<EcranEscalier>(find.byType(EcranEscalier)).simple,
          isTrue,
        );
        expect(t.takeException(), isNull);

        // Une hauteur changée reste après un passage par la charpente.
        await t.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('escalier_hauteur')),
            matching: find.byType(TextField),
          ),
          "8'",
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('mode_charpente')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('touche_7')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('mode_escalier')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('escalier_hauteur')),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          "8'",
        );
      },
    );

    testWidgets('le calcul de la charpente reste aussi', (t) async {
      await ouvrir(t);
      await taper(t, ['1', '2', 'Po', '+', '3']);
      await t.tap(find.byKey(const ValueKey('mode_escalier')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('mode_charpente')));
      await t.pumpAndSettle();
      expect(affiche('12" + 3'), isTrue);
    });
  });

  testWidgets('petit téléphone : la rangée de plus ne déborde pas', (t) async {
    t.view.physicalSize = const Size(360, 560);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: CalculatriceScreen())),
    );
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
