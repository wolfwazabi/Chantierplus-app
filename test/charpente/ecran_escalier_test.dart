import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_texte.dart';
import 'package:construction_app/screens/charpente/ecran_escalier.dart';
import 'package:construction_app/screens/charpente/schema_limon.dart';
import 'package:construction_app/screens/materiaux/calcul_chantier.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _cle(String k) => find.byKey(ValueKey(k));
Finder _champ(String cle) =>
    find.descendant(of: _cle(cle), matching: find.byType(TextField));
Finder _texte(String t) => find.textContaining(t, findRichText: true);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });
  tearDown(() => Preferences.unites.value = SystemeUnites.imperial);

  Future<void> ouvrir(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 16000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: EcranEscalier())));
    await t.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester t, String cle, String texte) async {
    await t.enterText(_champ(cle), texte);
    await t.pumpAndSettle();
  }

  group('écran', () {
    testWidgets('valeurs de départ : 9 pi, 15 contremarches de 7 3/16 po, conforme', (t) async {
      await ouvrir(t);
      expect(_texte('15 contremarches'), findsOneWidget);
      expect(_texte('7 3/16"'), findsWidgets);
      expect(_texte('14 marches'), findsOneWidget);
      expect(_texte('4 limons en 2×12'), findsOneWidget);
      expect(find.byType(SchemaLimon), findsOneWidget);
      // Rien en rouge : toutes les dimensions sont dans le Code.
      expect(find.descendant(of: _cle('escalier_erreurs'), matching: find.byIcon(Icons.error_outline)), findsNothing);
      expect(_cle('escalier_verifications'), findsOneWidget);
    });

    testWidgets('hauteur de 8 pi 6 po : 14 contremarches', (t) async {
      await ouvrir(t);
      await saisir(t, 'escalier_hauteur', '8\'6"');
      expect(_texte('14 contremarches'), findsOneWidget);
      expect(_texte('13 marches'), findsOneWidget);
    });

    testWidgets('giron de 10 po (254 mm) : refusé, 1 mm sous le minimum', (t) async {
      await ouvrir(t);
      await saisir(t, 'escalier_giron', '10"');
      expect(
        find.descendant(of: _cle('escalier_erreurs'), matching: _texte('Giron de 10"')),
        findsOneWidget,
      );
      // Les dimensions sont tout de même calculées.
      expect(_texte('15 contremarches'), findsOneWidget);
    });

    testWidgets('nombre de contremarches imposé', (t) async {
      await ouvrir(t);
      expect(_cle('escalier_nombre'), findsNothing);
      await t.tap(_cle('escalier_nombre_impose'));
      await t.pumpAndSettle();
      await saisir(t, 'escalier_nombre', '16');
      expect(_texte('16 contremarches'), findsOneWidget);
      expect(_texte('6 3/4"'), findsWidgets);
    });

    testWidgets('autres choix : un toucher impose ce nombre', (t) async {
      await ouvrir(t);
      expect(_cle('escalier_variante_16'), findsOneWidget);
      await t.ensureVisible(_cle('escalier_variante_16'));
      await t.tap(_cle('escalier_variante_16'));
      await t.pumpAndSettle();
      expect(_texte('16 contremarches'), findsOneWidget);
      expect(find.byKey(const ValueKey('escalier_nombre')), findsOneWidget);
    });

    testWidgets('course disponible : le giron en découle', (t) async {
      await ouvrir(t);
      await t.tap(find.text('Course disponible'));
      await t.pumpAndSettle();
      expect(_cle('escalier_giron'), findsNothing);
      expect(_cle('escalier_course'), findsOneWidget);
      await saisir(t, 'escalier_course', '135"');
      // 108 po sur 135 po de course : 14 contremarches, giron 135 ÷ 13 = 10 3/8 po.
      expect(_texte('14 contremarches'), findsOneWidget);
      expect(_texte('giron 10 3/8"'), findsWidgets);
    });

    testWidgets('escalier commun : contremarche maximale de 180 mm', (t) async {
      await ouvrir(t);
      await t.tap(find.text('Commun'));
      await t.pumpAndSettle();
      // Hauteur de 9 pi : 7 3/16 po = 182,9 mm > 180 mm... le calcul choisit 16 (6 3/4 po).
      expect(_texte('16 contremarches'), findsOneWidget);
    });

    testWidgets('table de traçage : une ligne par marche, sans cumul', (t) async {
      await ouvrir(t);
      await t.ensureVisible(_cle('escalier_trace'));
      await t.tap(_cle('escalier_trace'));
      await t.pumpAndSettle();
      // Marche 14 : 14 × 7,2 po = 100,8 po → 8' 4 13/16".
      expect(_texte('8\' 4 13/16"'), findsWidgets);
    });

    testWidgets('valeur impossible : message clair, pas d\'écran cassé', (t) async {
      await ouvrir(t);
      await t.tap(_cle('escalier_nombre_impose'));
      await t.pumpAndSettle();
      await saisir(t, 'escalier_hauteur', '2\'');
      await saisir(t, 'escalier_nombre', '40');
      // 24 po ÷ 40 = 0,6 po : la marche (1 1/2 po) serait plus épaisse que la contremarche.
      expect(_cle('escalier_erreur'), findsOneWidget);
      expect(_texte('plus épaisse'), findsNothing);
      expect(_texte('inférieure à la hauteur de contremarche'), findsOneWidget);
    });

    testWidgets('métrique : mesures en mm et m', (t) async {
      Preferences.unites.value = SystemeUnites.metrique;
      await ouvrir(t);
      // Hauteur de départ 108 po = 2,743 m ; 15 contremarches de 183 mm.
      expect(_texte('15 contremarches'), findsOneWidget);
      expect(_texte('183 mm'), findsWidgets);
      await saisir(t, 'escalier_hauteur', '2,6');
      // 2600 mm : 14 contremarches de 186 mm.
      expect(_texte('14 contremarches'), findsOneWidget);
      expect(_texte('186 mm'), findsWidgets);
      expect(_texte('1 mm'), findsWidgets); // précision du traçage
    });

    testWidgets('copier : le texte du calcul est placé dans le presse-papiers', (t) async {
      String? copie;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copie = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await ouvrir(t);
      await t.ensureVisible(_cle('escalier_copier'));
      await t.tap(_cle('escalier_copier'));
      await t.pumpAndSettle();
      expect(copie, isNotNull);
      expect(copie, contains('15 contremarches'));
      expect(copie, contains('MATÉRIAUX'));
      expect(find.text('Calcul copié.'), findsOneWidget);
    });
  });

  group('onglet Calcul du chantier', () {
    testWidgets('segment « Escalier »', (t) async {
      t.view.physicalSize = const Size(900, 16000);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CalculChantier(
              companyId: 'A',
              chantierId: 'chA',
              connecte: true,
              listeEnregistrees: Text('(aucune commande)'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(_cle('escalier_hauteur'), findsNothing); // IndexedStack : construit mais caché
      await t.tap(find.text('Escalier'));
      await t.pumpAndSettle();
      expect(_cle('escalier_hauteur'), findsOneWidget);
    });
  });

  group('texte exporté et matériaux', () {
    final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108));

    test('matériaux : limons, marches ; contremarches seulement si fermées', () {
      final m = materielEscalier(r, metrique: false);
      expect(m.length, 2);
      expect(m[0].quantite, 4);
      expect(m[0].article, contains('2×12'));
      expect(m[0].article, contains("16'"));
      expect(m[1].quantite, 14);
      expect(m[1].article, contains("3'"));
      expect(m[1].detail, contains('11"')); // 10 1/4 + 3/4
      final fermees = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, contremarchesFermees: true),
      );
      final mf = materielEscalier(fermees, metrique: false);
      expect(mf.length, 3);
      expect(mf[2].quantite, 15);
    });

    test('texte : dimensions, coupes, une ligne de traçage par marche, vérifications', () {
      final t = texteEscalier(r, metrique: false);
      expect(t, contains('15 contremarches de 7 3/16"'));
      expect(t, contains('14 marches'));
      expect(t, contains('Planche à commander'));
      expect('\n'.allMatches(t.split('TRAÇAGE')[1].split('MATÉRIAUX')[0]).length, greaterThan(14));
      expect(t, contains('[OK]'));
      expect(t, isNot(contains('NON CONFORME')));
      expect(t, contains('CNB 2015'));
    });

    test('texte : un escalier hors Code est marqué NON CONFORME', () {
      final mauvais = calculerEscalier(const SpecEscalier(hauteurTotale: 108, giron: 8));
      expect(texteEscalier(mauvais, metrique: false), contains('NON CONFORME'));
    });

    test('texte en métrique (calcul et texte avec le même système d\'unités)', () {
      final metrique = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108),
        metrique: true,
      );
      final t = texteEscalier(metrique, metrique: true);
      expect(t, contains('183 mm'));
      expect(t, isNot(contains('/16')));
      expect(t, isNot(contains('"')));
    });
  });
}
