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
  });

  // Liste de touches à partir d'un texte : chaque caractère est une touche,
  // sauf les unités « Pi » et « Po » écrites entre crochets : '5[Pi]6[Po]'.
  List<String> t(String expression) {
    final touches = <String>[];
    final re = RegExp(r'\[(Pi|Po)\]|.');
    for (final m in re.allMatches(expression.replaceAll(' ', ''))) {
      touches.add(m.group(1) ?? m.group(0)!);
    }
    return touches;
  }

  group('Priorité des opérations', () {
    final cas = <String, String>{
      '2+3×4': '14',
      '10−2×3': '4',
      '20÷4+1': '6',
      '2×3+4×5': '26',
      '100−10÷2': '95',
      '1+2×(3+4)': '15',
      '(2+3)×4': '20',
      '2×3×4': '24',
      '10−4−3': '3',
      '100÷10÷2': '5',
      '5+2(3)': '11',
      '1+(2+3)(4−1)': '16',
      '2×(3+(4−1)×2)': '18',
      '1.5+2.5×2': '6.5',
    };
    for (final MapEntry(key: expression, value: attendu) in cas.entries) {
      testWidgets('$expression = $attendu', (tester) async {
        await verifierResultat(tester, t(expression), attendu);
      });
    }

    testWidgets('pieds et pouces : 5\' + 6" × 2 = 6\' 0"', (tester) async {
      await verifierResultat(tester, t('5[Pi]+6[Po]×2'), "6' 0\"");
    });

    testWidgets('pieds et pouces : 8\' − 2\' 6" ÷ 2 = 6\' 9"', (tester) async {
      await verifierResultat(tester, t('8[Pi]−2[Pi]6[Po]÷2'), "6' 9\"");
    });

    testWidgets('opérateur final ignoré : 2+3× = 5', (tester) async {
      await verifierResultat(tester, t('2+3×'), '5');
    });

    testWidgets('parenthèse non fermée, fermée automatiquement : 2×(3+4 = 14', (
      tester,
    ) async {
      await verifierResultat(tester, t('2×(3+4'), '14');
    });

    testWidgets('continuer après = : (2+3×4) = 14, puis + 1 = 15', (
      tester,
    ) async {
      await ouvrir(tester);
      await taper(tester, [...t('2+3×4'), '=', '+', '1', '=']);
      final resultat = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 38,
      );
      expect(tester.widget<Text>(resultat).data, '15');
    });
  });

  group('√, x², x³, % : sur le dernier nombre, ou sur la réponse après =', () {
    // Formule affichée pendant la saisie (texte de taille 26 sur le LCD).
    String formule(WidgetTester tester) => tester
        .widget<Text>(
          find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 26),
        )
        .data!
        .trim();

    final cas = <List<String>, String>{
      // Dernier nombre saisi
      [...t('2+3×4'), 'x²', '=']: '50',
      [...t('2+2'), 'x³', '=']: '10',
      [...t('1+9'), '√x', '=']: '4',
      [...t('200×15'), '%', '=']: '30',
      ['2', 'x²', 'x²', '=']: '16',
      // Groupe juste fermé
      [...t('(2+3)'), 'x²', '=']: '25',
      [...t('(20+5)'), '√x', '×', '2', '=']: '10',
      [...t('1+(1+1)'), 'x³', '=']: '9',
      // Après = : sur la réponse (affichée tout de suite)
      [...t('2+3×4'), '=', 'x²']: '196',
      [...t('2+3×4'), '=', 'x²', '+', '4', '=']: '200',
    };
    for (final MapEntry(key: touches, value: attendu) in cas.entries) {
      testWidgets('${touches.join(' ')} = $attendu', (tester) async {
        await ouvrir(tester);
        await taper(tester, touches);
        final resultat = find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 38,
        );
        expect(
          tester.widget<Text>(resultat).data,
          attendu,
          reason: touches.join(' '),
        );
      });
    }

    testWidgets('la formule affiche l\'exposant sur le bon nombre', (
      tester,
    ) async {
      await ouvrir(tester);
      await taper(tester, [...t('2+3×4'), 'x²']);
      expect(formule(tester), '2 + 3 × 4²');
      await taper(tester, ['+', '(', '1', '+', '8', ')', '√x']);
      expect(formule(tester), '2 + 3 × 4² + √(1 + 8)');
    });

    testWidgets(
      'pieds et pouces : √ de 9" est affiché entre parenthèses si besoin',
      (tester) async {
        await ouvrir(tester);
        await taper(tester, [...t('1[Pi]6[Po]'), 'x²']);
        expect(formule(tester), '(1\' 6")²');
      },
    );

    testWidgets(
      '√ d\'un nombre négatif : refusé, l\'expression reste intacte',
      (tester) async {
        await ouvrir(tester);
        await taper(tester, [...t('(1−5)'), '√x', '=']);
        final resultat = find.byWidgetPredicate(
          (w) => w is Text && w.style?.fontSize == 38,
        );
        expect(tester.widget<Text>(resultat).data, '-4');
      },
    );

    testWidgets('sans nombre (juste après un opérateur) : sans effet', (
      tester,
    ) async {
      await ouvrir(tester);
      await taper(tester, [...t('5+'), 'x²', '3', '=']);
      final resultat = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 38,
      );
      expect(tester.widget<Text>(resultat).data, '8');
    });
  });

  group('Division par zéro', () {
    testWidgets('division par zéro : message d\'erreur au lieu d\'un faux 0', (
      tester,
    ) async {
      await ouvrir(tester);
      await taper(tester, [...t('8÷0'), '=']);
      expect(find.text('Division par zéro'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 38),
        findsNothing,
      );
      // Une nouvelle saisie efface l'erreur.
      await taper(tester, ['5', '=']);
      expect(find.text('Division par zéro'), findsNothing);
    });

    testWidgets('division par zéro dans un groupe : 1+2÷(3−3) → erreur', (
      tester,
    ) async {
      await ouvrir(tester);
      await taper(tester, [...t('1+2÷(3−3)'), '=']);
      expect(find.text('Division par zéro'), findsOneWidget);
    });
  });
}
