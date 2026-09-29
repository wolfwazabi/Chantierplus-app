import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests de la calculatrice de charpente : on appuie sur les vraies touches
/// et on lit le résultat affiché.
void main() {
  Future<void> ouvrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // Clé unique : chaque calcul repart d'une calculatrice neuve.
      MaterialApp(
        home: Scaffold(body: CalculatriceScreen(key: UniqueKey())),
      ),
    );
  }

  /// Appuie sur une suite de touches, ex. ['(', '5', '6', 'Po', '×', '2', ')'].
  Future<void> taper(WidgetTester tester, List<String> touches) async {
    for (final t in touches) {
      final touche = find.byKey(ValueKey('touche_$t'));
      expect(touche, findsOneWidget, reason: 'touche « $t » introuvable');
      await tester.tap(touche);
      await tester.pump();
    }
  }

  Future<void> verifierResultat(
    WidgetTester tester,
    List<String> touches,
    String attendu,
  ) async {
    await ouvrir(tester);
    await taper(tester, [...touches, '=']);
    // Le résultat est le grand texte de l'écran LCD (taille 38), à ne pas
    // confondre avec les libellés des touches (« 5 », « 4 »…).
    final resultat = find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontSize == 38,
    );
    expect(
      resultat,
      findsOneWidget,
      reason: 'aucun résultat affiché pour ${touches.join(' ')}',
    );
    expect(
      tester.widget<Text>(resultat).data,
      attendu,
      reason: touches.join(' '),
    );
  }

  group('Parenthèses', () {
    testWidgets(
      '(56" × 2) + 56\' = 65\' 4" (bogue signalé : le + était ignoré)',
      (tester) async {
        await verifierResultat(tester, [
          '(',
          '5',
          '6',
          'Po',
          '×',
          '2',
          ')',
          '+',
          '5',
          '6',
          'Pi',
        ], "65' 4\"");
      },
    );

    testWidgets(
      'chaque opérateur après une parenthèse fermée est pris en compte',
      (tester) async {
        await verifierResultat(tester, [
          '(',
          '2',
          '+',
          '3',
          ')',
          '−',
          '1',
        ], '4');
        await verifierResultat(tester, [
          '(',
          '2',
          '+',
          '3',
          ')',
          '×',
          '4',
        ], '20');
        await verifierResultat(tester, [
          '(',
          '2',
          '+',
          '3',
          ')',
          '÷',
          '5',
        ], '1');
      },
    );

    testWidgets(
      'un nombre juste après « ) » multiplie le groupe : (2+3)4 = 20',
      (tester) async {
        await verifierResultat(tester, ['(', '2', '+', '3', ')', '4'], '20');
      },
    );

    testWidgets('deux groupes côte à côte se multiplient : (2+3)(1+1) = 10', (
      tester,
    ) async {
      await verifierResultat(tester, [
        '(',
        '2',
        '+',
        '3',
        ')',
        '(',
        '1',
        '+',
        '1',
        ')',
      ], '10');
    });

    testWidgets(
      'un nombre juste avant « ( » multiplie le groupe : 2(3+1) = 8',
      (tester) async {
        await verifierResultat(tester, ['2', '(', '3', '+', '1', ')'], '8');
        await verifierResultat(tester, [
          '2',
          'Pi',
          '(',
          '1',
          '+',
          '1',
          ')',
        ], "4' 0\"");
      },
    );

    testWidgets('groupe après un opérateur : 10 − (2 + 3) = 5', (tester) async {
      await verifierResultat(tester, [
        '1',
        '0',
        '−',
        '(',
        '2',
        '+',
        '3',
        ')',
      ], '5');
    });

    testWidgets(
      'changer d\'opérateur après « ) » garde le dernier : (2+3) + × 4 = 20',
      (tester) async {
        await verifierResultat(tester, [
          '(',
          '2',
          '+',
          '3',
          ')',
          '+',
          '×',
          '4',
        ], '20');
      },
    );
  });

  group('Calculs de base (non-régression)', () {
    testWidgets('pieds et pouces : 5\' 6" + 7" = 6\' 1"', (tester) async {
      await verifierResultat(tester, [
        '5',
        'Pi',
        '6',
        'Po',
        '+',
        '7',
        'Po',
      ], "6' 1\"");
    });

    testWidgets('décimal sans unités : 2 + 3 × 4 (gauche à droite) = 20', (
      tester,
    ) async {
      await verifierResultat(tester, ['2', '+', '3', '×', '4'], '20');
    });
  });
}
