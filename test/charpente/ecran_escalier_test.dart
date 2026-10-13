import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_solveur.dart';
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
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: EcranEscalier())),
    );
    await t.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester t, String cle, String texte) async {
    await t.enterText(_champ(cle), texte);
    await t.pumpAndSettle();
  }

  group('écran', () {
    testWidgets(
      'valeurs de départ : 9 pi, 15 contremarches de 7 3/16 po, conforme',
      (t) async {
        await ouvrir(t);
        expect(_texte('15 contremarches'), findsOneWidget);
        expect(_texte('7 3/16"'), findsWidgets);
        expect(_texte('14 marches'), findsOneWidget);
        expect(_texte('4 limons en 2×12'), findsOneWidget);
        expect(find.byType(SchemaLimon), findsOneWidget);
        // Rien en rouge : toutes les dimensions sont dans le Code.
        expect(
          find.descendant(
            of: _cle('escalier_erreurs'),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
        );
        expect(_cle('escalier_verifications'), findsOneWidget);
      },
    );

    testWidgets(
      'schémas des coupes et de la pente : gabarit, pied et tête du limon',
      (t) async {
        await ouvrir(t);
        expect(_cle('schema_coupes'), findsOneWidget);
        for (final cle in ['schema_gabarit', 'schema_pied', 'schema_tete']) {
          expect(_cle(cle), findsOneWidget, reason: cle);
        }
        // Légendes chiffrées : pente, coupe d'aplomb du bas, coupe de niveau, tête.
        expect(_texte('Pente 35,1°'), findsOneWidget);
        expect(_texte('11 7/16"'), findsWidgets);
        expect(_texte('Pointe du haut'), findsWidgets);
      },
    );

    testWidgets('hauteur de 8 pi 6 po : 14 contremarches', (t) async {
      await ouvrir(t);
      await saisir(t, 'escalier_hauteur', '8\'6"');
      expect(_texte('14 contremarches'), findsOneWidget);
      expect(_texte('13 marches'), findsOneWidget);
    });

    testWidgets('giron de 10 po (254 mm) : refusé, 1 mm sous le minimum', (
      t,
    ) async {
      await ouvrir(t);
      await saisir(t, 'escalier_giron', '10"');
      expect(
        find.descendant(
          of: _cle('escalier_erreurs'),
          matching: _texte('Giron de 10"'),
        ),
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

    testWidgets('table de traçage : une ligne par marche, sans cumul', (
      t,
    ) async {
      await ouvrir(t);
      await t.ensureVisible(_cle('escalier_trace'));
      await t.tap(_cle('escalier_trace'));
      await t.pumpAndSettle();
      // Marche 14 : 14 × 7,2 po = 100,8 po → 8' 4 13/16".
      expect(_texte('8\' 4 13/16"'), findsWidgets);
    });

    testWidgets('valeur impossible : message clair, pas d\'écran cassé', (
      t,
    ) async {
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

    testWidgets(
      'copier : le texte du calcul est placé dans le presse-papiers',
      (t) async {
        String? copie;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copie = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await ouvrir(t);
        await t.ensureVisible(_cle('escalier_copier'));
        await t.tap(_cle('escalier_copier'));
        await t.pumpAndSettle();
        expect(copie, isNotNull);
        expect(copie, contains('15 contremarches'));
        expect(copie, contains('MATÉRIAUX'));
        expect(find.text('Calcul copié.'), findsOneWidget);
      },
    );
  });

  group('à partir de ce que je connais', () {
    Future<void> activer(WidgetTester t) async {
      await ouvrir(t);
      await t.tap(_cle('escalier_mode_donnees'));
      await t.pumpAndSettle();
    }

    Future<void> basculer(WidgetTester t, DonneeEscalier d) async {
      await t.ensureVisible(_cle('escalier_donnee_${d.name}'));
      await t.tap(_cle('escalier_donnee_${d.name}'));
      await t.pumpAndSettle();
    }

    String ligne(WidgetTester t, DonneeEscalier d) => t
        .widget<Text>(_cle('escalier_solution_${d.name}'))
        .textSpan!
        .toPlainText();

    testWidgets('le mode est éteint au départ : l\'écran d\'avant, inchangé', (
      t,
    ) async {
      await ouvrir(t);
      expect(_cle('escalier_hauteur'), findsOneWidget);
      expect(_cle('escalier_mode'), findsOneWidget);
      expect(_cle('escalier_donnee_hauteur'), findsNothing);
      expect(_cle('escalier_solution'), findsNothing);
    });

    testWidgets(
      'activé : les 5 données à cocher, hauteur et course connues au départ',
      (t) async {
        await activer(t);
        for (final d in DonneeEscalier.values) {
          expect(
            _cle('escalier_donnee_${d.name}'),
            findsOneWidget,
            reason: d.name,
          );
        }
        expect(_cle('escalier_d_hauteur'), findsOneWidget);
        expect(_cle('escalier_d_course'), findsOneWidget);
        expect(_cle('escalier_d_giron'), findsNothing);
        // Les contrôles d'avant sont remplacés.
        expect(_cle('escalier_hauteur'), findsNothing);
        expect(_cle('escalier_mode'), findsNothing);
        expect(_cle('escalier_nombre_impose'), findsNothing);
      },
    );

    testWidgets(
      'hauteur 9 pi + course 12 pi : 15 contremarches, le reste est « trouvé »',
      (t) async {
        await activer(t);
        // 108 / 144 : n = 15 (7,2 po, giron 144 ÷ 14 = 10,29 po ; 2R + G = 24,69 po).
        expect(_cle('escalier_solution'), findsOneWidget);
        expect(_texte('15 contremarches'), findsWidgets);
        expect(ligne(t, DonneeEscalier.hauteur), contains('(donnée)'));
        expect(ligne(t, DonneeEscalier.course), contains('(donnée)'));
        expect(ligne(t, DonneeEscalier.giron), contains('(trouvée)'));
        expect(ligne(t, DonneeEscalier.contremarche), contains('(trouvée)'));
        expect(ligne(t, DonneeEscalier.nombre), contains('15'));
        expect(ligne(t, DonneeEscalier.nombre), contains('(trouvée)'));
        // Tout le calcul des limons suit.
        expect(_texte('4 limons en 2×12'), findsOneWidget);
        expect(find.byType(SchemaLimon), findsOneWidget);
      },
    );

    testWidgets(
      'hauteur + course de 135 po : 14 contremarches, giron 10 3/8 po',
      (t) async {
        await activer(t);
        await saisir(t, 'escalier_d_course', '135"');
        expect(_texte('14 contremarches'), findsWidgets);
        expect(ligne(t, DonneeEscalier.giron), contains('10 3/8"'));
      },
    );

    testWidgets('hauteur + giron : la course est trouvée', (t) async {
      await activer(t);
      await basculer(t, DonneeEscalier.course); // décoché
      await basculer(t, DonneeEscalier.giron); // coché
      expect(_cle('escalier_d_course'), findsNothing);
      expect(_cle('escalier_d_giron'), findsOneWidget);
      expect(ligne(t, DonneeEscalier.giron), contains('(donnée)'));
      expect(ligne(t, DonneeEscalier.course), contains('(trouvée)'));
      expect(
        ligne(t, DonneeEscalier.course),
        contains('11\' 11 1/2"'),
      ); // 14 × 10 1/4 = 143 1/2 po
      expect(_texte('15 contremarches'), findsWidgets);
    });

    testWidgets('hauteur seule : l\'escalier idéal (giron 10 5/8 po)', (
      t,
    ) async {
      await activer(t);
      await basculer(t, DonneeEscalier.course); // plus que la hauteur
      expect(ligne(t, DonneeEscalier.giron), contains('10 5/8"'));
      expect(ligne(t, DonneeEscalier.nombre), contains('15'));
      expect(_texte('Giron idéal'), findsOneWidget);
    });

    testWidgets('course + giron, sans la hauteur : la hauteur est trouvée', (
      t,
    ) async {
      await activer(t);
      await basculer(t, DonneeEscalier.hauteur); // décochée
      await basculer(t, DonneeEscalier.giron); // cochée avec la course
      await saisir(t, 'escalier_d_giron', '10 1/2"');
      expect(ligne(t, DonneeEscalier.hauteur), contains('(trouvée)'));
      // 144 po / 10,5 → 14 marches, 15 contremarches de 7 3/8 po : 9' 2 5/8".
      expect(ligne(t, DonneeEscalier.hauteur), contains('9\' 2 5/8"'));
      expect(_texte('Hauteur trouvée'), findsOneWidget);
      // Le calcul des limons part de CETTE hauteur : 15 contremarches de 7 3/8 po.
      expect(_texte('15 contremarches'), findsWidgets);
      expect(
        find.descendant(
          of: _cle('escalier_resume'),
          matching: _texte('7 3/8"'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('changer la hauteur donnée refait tout le calcul', (t) async {
      await activer(t);
      await saisir(t, 'escalier_d_hauteur', '8\'6"');
      // 102 po sur 144 po : 14 contremarches (7,29 po), giron 144 ÷ 13 = 11,08 po.
      expect(ligne(t, DonneeEscalier.nombre), contains('14'));
      expect(
        find.descendant(
          of: _cle('escalier_resume'),
          matching: _texte('14 contremarches'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('données insuffisantes : message clair, écran intact', (
      t,
    ) async {
      await activer(t);
      await basculer(t, DonneeEscalier.hauteur);
      await basculer(t, DonneeEscalier.course);
      await basculer(t, DonneeEscalier.giron);
      await basculer(t, DonneeEscalier.contremarche);
      expect(_cle('escalier_erreur'), findsOneWidget);
      expect(_texte('Données insuffisantes'), findsOneWidget);
      expect(t.takeException(), isNull);
      // On ajoute la hauteur : le calcul revient.
      await basculer(t, DonneeEscalier.hauteur);
      expect(_cle('escalier_erreur'), findsNothing);
      expect(_cle('escalier_solution'), findsOneWidget);
    });

    testWidgets('autres choix : un toucher impose ce nombre de contremarches', (
      t,
    ) async {
      await activer(t);
      await basculer(t, DonneeEscalier.course);
      await basculer(t, DonneeEscalier.giron); // hauteur + giron 10 1/4
      expect(_cle('escalier_choix_14'), findsOneWidget);
      await t.ensureVisible(_cle('escalier_choix_14'));
      await t.tap(_cle('escalier_choix_14'));
      await t.pumpAndSettle();
      expect(_cle('escalier_d_nombre'), findsOneWidget);
      expect(ligne(t, DonneeEscalier.nombre), contains('(donnée)'));
      expect(_texte('14 contremarches'), findsWidgets);
    });

    testWidgets('hors du Code : le calcul le dit (giron de 8 po)', (t) async {
      await activer(t);
      await basculer(t, DonneeEscalier.course);
      await basculer(t, DonneeEscalier.giron);
      await saisir(t, 'escalier_d_giron', '8"');
      expect(
        find.descendant(
          of: _cle('escalier_erreurs'),
          matching: _texte('Giron de 8"'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('métrique : mesures et explications en mm, sans pouces', (
      t,
    ) async {
      Preferences.unites.value = SystemeUnites.metrique;
      await activer(t);
      expect(ligne(t, DonneeEscalier.giron), contains('mm'));
      expect(ligne(t, DonneeEscalier.giron), isNot(contains('"')));
      await basculer(
        t,
        DonneeEscalier.course,
      ); // hauteur seule : « Giron idéal : … »
      final note = find.descendant(
        of: _cle('escalier_solution'),
        matching: find.textContaining('Giron idéal', findRichText: true),
      );
      expect(note, findsOneWidget);
      final w = t.widget(note);
      final texte = w is RichText ? w.text.toPlainText() : (w as Text).data!;
      expect(texte, contains('mm'));
      expect(texte, isNot(contains('"')));
    });

    testWidgets('on éteint le mode : l\'écran d\'avant revient', (t) async {
      await activer(t);
      await t.tap(_cle('escalier_mode_donnees'));
      await t.pumpAndSettle();
      expect(_cle('escalier_hauteur'), findsOneWidget);
      expect(_cle('escalier_solution'), findsNothing);
      expect(_texte('15 contremarches'), findsOneWidget);
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
      expect(
        _cle('escalier_hauteur'),
        findsNothing,
      ); // IndexedStack : construit mais caché
      await t.tap(find.text('Escalier'));
      await t.pumpAndSettle();
      expect(_cle('escalier_hauteur'), findsOneWidget);
    });
  });

  group('texte exporté et matériaux', () {
    final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108));

    test(
      'matériaux : limons, marches ; contremarches seulement si fermées',
      () {
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
      },
    );

    test('texte : dimensions, coupes, une ligne de traçage par marche, vérifications', () {
      final t = texteEscalier(r, metrique: false);
      expect(t, contains('15 contremarches de 7 3/16"'));
      expect(t, contains('14 marches'));
      expect(t, contains('Planche à commander'));
      expect(
        '\n'.allMatches(t.split('TRAÇAGE')[1].split('MATÉRIAUX')[0]).length,
        greaterThan(14),
      );
      expect(t, contains('[OK]'));
      expect(t, isNot(contains('NON CONFORME')));
      expect(t, contains('CNB 2015'));
    });

    test('texte : un escalier hors Code est marqué NON CONFORME', () {
      final mauvais = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108, giron: 8),
      );
      expect(texteEscalier(mauvais, metrique: false), contains('NON CONFORME'));
    });

    test(
      'texte en métrique (calcul et texte avec le même système d\'unités)',
      () {
        final metrique = calculerEscalier(
          const SpecEscalier(hauteurTotale: 108),
          metrique: true,
        );
        final t = texteEscalier(metrique, metrique: true);
        expect(t, contains('183 mm'));
        expect(t, isNot(contains('/16')));
        expect(t, isNot(contains('"')));
      },
    );
  });
}
