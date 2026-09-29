import 'package:construction_app/screens/calculatrice_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nouvelle disposition (modèle 1), M−, /, métrique et béton.
void main() {
  setUp(() {
    Preferences.unites.value = SystemeUnites.imperial;
    CalculatriceScreen.mode.value = ModeCalculatrice.charpente;
  });

  Future<void> ouvrir(WidgetTester tester, {bool metrique = false}) async {
    Preferences.unites.value = metrique
        ? SystemeUnites.metrique
        : SystemeUnites.imperial;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalculatriceScreen(key: UniqueKey())),
      ),
    );
  }

  Future<void> taper(WidgetTester tester, List<String> touches) async {
    for (final t in touches) {
      final touche = find.byKey(ValueKey('touche_$t'));
      expect(touche, findsOneWidget, reason: 'touche « $t » introuvable');
      await tester.tap(touche);
      await tester.pump();
    }
  }

  Finder resultat() =>
      find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 50);

  String texteResultat(WidgetTester tester) =>
      tester.widget<Text>(resultat()).data!;

  group('Disposition (modèle 1)', () {
    testWidgets('toutes les touches du modèle 1 sont présentes', (
      tester,
    ) async {
      await ouvrir(tester);
      for (final t in [
        'M+',
        'M−',
        'MR',
        'MC',
        'RUN',
        'RISE',
        'DIAG',
        'Conv',
        'Pi',
        'Po',
        '/',
        '⌫',
        '(',
        ')',
        'x²',
        '√x',
        '7',
        '8',
        '9',
        '÷',
        '4',
        '5',
        '6',
        '×',
        '1',
        '2',
        '3',
        '−',
        'AC',
        '0',
        '.',
        '+',
        'x³',
        '%',
        '=',
      ]) {
        expect(find.byKey(ValueKey('touche_$t')), findsOneWidget, reason: t);
      }
    });

    testWidgets('plus de barre Conversion / Matériaux en haut', (tester) async {
      await ouvrir(tester);
      expect(find.text('Conversion'), findsNothing);
      expect(find.text('Matériaux'), findsNothing);
    });

    testWidgets('/ : 5 Po 1 / 2 = 5 1/2"', (tester) async {
      await ouvrir(tester);
      await taper(tester, ['5', 'Po', '1', '/', '2', '=']);
      expect(texteResultat(tester), '5 1/2"');
    });
  });

  group('Mémoire', () {
    testWidgets('M+ puis M− puis MR : 10 − 3 = 7', (tester) async {
      await ouvrir(tester);
      await taper(tester, ['1', '0', 'M+', 'AC', '3', 'M−', 'AC', 'MR']);
      expect(texteResultat(tester), '7');
    });

    testWidgets('M− sur une mémoire vide : 0 − 4 = −4', (tester) async {
      await ouvrir(tester);
      await taper(tester, ['4', 'M−', 'AC', 'MR']);
      expect(texteResultat(tester), '-4');
    });
  });

  group('Métrique', () {
    testWidgets('touches m, cm, mm à la place de Pi, Po, /', (tester) async {
      await ouvrir(tester, metrique: true);
      for (final t in ['m', 'cm', 'mm']) {
        expect(find.byKey(ValueKey('touche_$t')), findsOneWidget, reason: t);
      }
      for (final t in ['Pi', 'Po', '/']) {
        expect(find.byKey(ValueKey('touche_$t')), findsNothing, reason: t);
      }
    });

    final cas = <List<String>, String>{
      ['2', 'm', '3', '5', 'cm', '4', 'mm', '=']: '2 m 35 cm 4 mm',
      ['1', 'm', '5', '0', 'cm', '×', '2', '=']: '3 m',
      ['7', '5', 'cm', '+', '2', '5', 'cm', '=']: '1 m',
      ['2', 'm', '−', '3', '5', 'mm', '=']: '1 m 96 cm 5 mm',
      ['4', 'mm', '÷', '8', '=']: '0.5 mm',
      ['1', 'm', '−', '3', 'm', '=']: '-2 m',
    };
    for (final MapEntry(key: touches, value: attendu) in cas.entries) {
      testWidgets('${touches.join(' ')} → $attendu', (tester) async {
        await ouvrir(tester, metrique: true);
        await taper(tester, touches);
        expect(texteResultat(tester), attendu);
      });
    }

    testWidgets('toucher la réponse : m cm mm → m → mm', (tester) async {
      await ouvrir(tester, metrique: true);
      await taper(tester, ['2', 'm', '3', '5', 'cm', '4', 'mm', '=']);
      expect(texteResultat(tester), '2 m 35 cm 4 mm');
      await tester.tap(resultat());
      await tester.pump();
      expect(texteResultat(tester), '2.354 m');
      await tester.tap(resultat());
      await tester.pump();
      expect(texteResultat(tester), '2354 mm');
      await tester.tap(resultat());
      await tester.pump();
      expect(texteResultat(tester), '2 m 35 cm 4 mm');
    });

    testWidgets('Conv affiche toujours pi-po, pouces et mètres', (
      tester,
    ) async {
      await ouvrir(tester, metrique: true);
      await taper(tester, ['3', '0', '4', '.', '8', 'mm', 'Conv']);
      expect(find.text("1' 0\""), findsOneWidget);
      expect(find.text('12 po'), findsOneWidget);
      expect(find.text('0.305 m'), findsOneWidget);
    });

    testWidgets('changer d\'unités efface le calcul en cours', (tester) async {
      await ouvrir(tester, metrique: true);
      await taper(tester, ['2', 'm', '+']);
      Preferences.unites.value = SystemeUnites.imperial;
      await tester.pump();
      expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);
      await taper(tester, ['5', '=']);
      expect(texteResultat(tester), '5');
    });
  });

  group('Béton', () {
    Future<void> entrer(
      WidgetTester tester,
      List<String> chiffres, [
      String? unite,
    ]) async {
      if (unite != null) await taper(tester, ['unite_$unite']);
      await taper(tester, [...chiffres, '↵']);
    }

    testWidgets('impérial : 10 pi × 10 pi × 4 po', (tester) async {
      await ouvrir(tester);
      CalculatriceScreen.mode.value = ModeCalculatrice.beton;
      await tester.pump();
      expect(find.text('Longueur'), findsOneWidget);
      await entrer(tester, ['1', '0']);
      await entrer(tester, ['1', '0']);
      await entrer(tester, ['4']);
      expect(find.text('Volume : 1.23 vg³ (33.33 pi³)'), findsOneWidget);
      expect(find.text('0.944 m³'), findsOneWidget);
      expect(find.text('Sacs de 30 kg : 68'), findsOneWidget);
    });

    testWidgets('métrique : 3 m × 3 m × 10 cm', (tester) async {
      await ouvrir(tester, metrique: true);
      CalculatriceScreen.mode.value = ModeCalculatrice.beton;
      await tester.pump();
      await entrer(tester, ['3']);
      await entrer(tester, ['3']);
      await entrer(tester, ['1', '0']);
      expect(find.text('Volume : 0.900 m³'), findsOneWidget);
      expect(find.text('Sacs de 30 kg : 65'), findsOneWidget);
    });

    testWidgets(
      'métrique : unités au choix (cm pour la longueur, mm pour l\'épaisseur)',
      (tester) async {
        await ouvrir(tester, metrique: true);
        CalculatriceScreen.mode.value = ModeCalculatrice.beton;
        await tester.pump();
        await entrer(tester, ['3', '0', '0'], 'cm');
        await entrer(tester, ['3']);
        await entrer(tester, ['1', '0', '0'], 'mm');
        expect(find.text('Volume : 0.900 m³'), findsOneWidget);
      },
    );

    testWidgets('retour en charpente : clavier de charpente', (tester) async {
      await ouvrir(tester);
      CalculatriceScreen.mode.value = ModeCalculatrice.beton;
      await tester.pump();
      CalculatriceScreen.mode.value = ModeCalculatrice.charpente;
      await tester.pump();
      expect(find.byKey(const ValueKey('touche_Pi')), findsOneWidget);
    });
  });
}
