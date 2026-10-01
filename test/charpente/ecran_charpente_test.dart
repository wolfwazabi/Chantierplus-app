import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:construction_app/screens/charpente/assistant_charpente.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/screens/materiaux/calcul_chantier.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget enfant) => MaterialApp(home: Scaffold(body: enfant));

Widget _charpente() => _app(
  const CharpenteScreen(
    companyId: 'A',
    chantierId: 'chA',
    connecte: true,
    listeEnregistrees: Text('(aucune commande)'),
  ),
);

Finder _champ(String cle) => find.descendant(
  of: find.byKey(ValueKey(cle)),
  matching: find.byType(TextField),
);

Future<void> _ouvrir(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(900, 7000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  await t.pumpAndSettle();
}

/// Les listes ne construisent que ce qui est visible : l'écran de test est très
/// haut (téléphone étroit mais long), donc tout est construit ; on s'assure
/// seulement que l'élément est dans la zone visible.
Future<void> _voir(WidgetTester t, Finder f) async {
  expect(f, findsWidgets);
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
}

Future<void> _onglet(WidgetTester t, String libelle) async {
  await t.tap(find.widgetWithText(Tab, libelle));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  group('plancher', () {
    testWidgets(
      'résultats du projet par défaut (13 pi × 10 pi 6 po, 16 po c/c)',
      (t) async {
        await _ouvrir(t, _charpente());
        expect(find.text('Forme du plancher'), findsOneWidget);
        await _voir(t, find.text('Résultats'));
        expect(find.text('Résultats'), findsOneWidget);
        // 13 pi × 10 pi 6 po à 16 po c/c : 10 solives + 1 de rive à chaque bout.
        expect(find.text('Solives'), findsWidgets);
        final r = calculerPlancher(
          SpecPlancher(
            forme: Polygone.rectangle(156, 126),
            etriers: ModeEtriers.deuxBouts,
          ),
        );
        expect(find.textContaining('${r.nombreSolives}'), findsWidgets);
        expect(
          find.textContaining(formatLongueur(r.porteeMax, metrique: false)),
          findsWidgets,
        );
      },
    );

    testWidgets('changer la longueur recalcule', (t) async {
      await _ouvrir(t, _charpente());
      await t.enterText(_champ('rect_longueur'), "20'");
      await t.pumpAndSettle();
      final r = calculerPlancher(
        SpecPlancher(
          forme: Polygone.rectangle(240, 126),
          etriers: ModeEtriers.deuxBouts,
        ),
      );
      expect(r.nombreSolives, greaterThan(10));
      expect(find.textContaining('${r.nombreSolives}'), findsWidgets);
    });

    testWidgets('longueur invalide : message, rien ne change', (t) async {
      await _ouvrir(t, _charpente());
      await t.enterText(_champ('rect_longueur'), 'abc');
      await t.pumpAndSettle();
      expect(find.textContaining('Nombre invalide'), findsOneWidget);
    });

    testWidgets(
      'côtés et angles : forme à 5 côtés avec côté et angles calculés',
      (t) async {
        await _ouvrir(t, _charpente());
        await t.tap(find.text('Côtés et angles'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('cote_0')), findsOneWidget);
        // Ajoute deux côtés : 5 côtés au total avec le côté de fermeture.
        await _voir(t, find.byKey(const ValueKey('ajouter_cote')));
        await t.tap(find.byKey(const ValueKey('ajouter_cote')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('cote_3')), findsOneWidget);
        expect(find.textContaining('Forme obtenue'), findsOneWidget);
        expect(find.textContaining('(calculé)'), findsWidgets);
      },
    );

    testWidgets('forme impossible : erreur claire', (t) async {
      await _ouvrir(t, _charpente());
      await t.tap(find.text('Côtés et angles'));
      await t.pumpAndSettle();
      // Un angle de 1° au premier coin : la forme ne se ferme pas.
      await t.enterText(_champ('cote_0'), "100'");
      await t.enterText(_champ('angle_0'), '1');
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    });

    testWidgets('direction des solives : automatique, puis angle choisi', (
      t,
    ) async {
      await _ouvrir(t, _charpente());
      await _voir(t, find.byKey(const ValueKey('direction')));
      await t.tap(find.text('Choisir l\'angle'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('angle_solives')), findsOneWidget);
    });

    testWidgets('les options (rive double, étriers, entremises) se règlent', (
      t,
    ) async {
      await _ouvrir(t, _charpente());
      await _voir(t, find.byKey(const ValueKey('rive_double')));
      await t.tap(find.byKey(const ValueKey('rive_double')));
      await t.pumpAndSettle();
      await _voir(t, find.byKey(const ValueKey('entremises')));
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('entremises')),
          matching: find.text('2'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Entremises'), findsWidgets);
    });
  });

  group('murs', () {
    testWidgets(
      'murs du contour, fenêtre ajoutée : linteau dans les résultats',
      (t) async {
        await _ouvrir(t, _charpente());
        await _onglet(t, 'Murs');
        await t.tap(find.byKey(const ValueKey('murs_actifs')));
        await t.pumpAndSettle();
        expect(find.text('Contour du plancher'), findsOneWidget);
        // Premier mur : ouvre la carte et ajoute une fenêtre de 36 × 48 po.
        await _voir(t, find.byKey(const ValueKey('carte_mur_0')));
        await t.tap(find.byKey(const ValueKey('carte_mur_0')));
        await t.pumpAndSettle();
        await _voir(t, find.byKey(const ValueKey('mur_0_ajouter_fenetre')));
        await t.tap(find.byKey(const ValueKey('mur_0_ajouter_fenetre')));
        await t.pumpAndSettle();
        expect(find.text('Nouvelle fenêtre'), findsOneWidget);
        expect(find.textContaining('Baie (ouverture brute)'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('ouverture_ok')));
        await t.pumpAndSettle();
        expect(find.textContaining('1 ouverture'), findsOneWidget);
        await _voir(t, find.text('Linteaux (2×8)'));
        expect(find.text('Linteaux (2×8)'), findsOneWidget);
      },
    );

    testWidgets('ouverture : jeu hors de la plage GCR signalé', (t) async {
      await _ouvrir(t, _charpente());
      await _onglet(t, 'Murs');
      await t.tap(find.byKey(const ValueKey('murs_actifs')));
      await t.pumpAndSettle();
      await _voir(t, find.byKey(const ValueKey('carte_mur_0')));
      await t.tap(find.byKey(const ValueKey('carte_mur_0')));
      await t.pumpAndSettle();
      await _voir(t, find.byKey(const ValueKey('mur_0_ajouter_porte')));
      await t.tap(find.byKey(const ValueKey('mur_0_ajouter_porte')));
      await t.pumpAndSettle();
      expect(find.textContaining('hors de la plage'), findsNothing);
      // Jeu de 3 po en largeur : hors plage.
      final jeu = find.widgetWithText(TextField, '1"').first;
      await t.enterText(jeu, '3"');
      await t.pumpAndSettle();
      expect(find.textContaining('hors de la plage'), findsOneWidget);
    });

    testWidgets('murs libres : ajouter un mur', (t) async {
      await _ouvrir(t, _charpente());
      await _onglet(t, 'Murs');
      await t.tap(find.byKey(const ValueKey('murs_actifs')));
      await t.pumpAndSettle();
      await t.tap(find.text('Murs libres'));
      await t.pumpAndSettle();
      await _voir(t, find.byKey(const ValueKey('ajouter_mur')));
      await t.tap(find.byKey(const ValueKey('ajouter_mur')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('carte_libre_0')), findsOneWidget);
    });

    testWidgets('Isobrace R-4 : la note du produit s\'affiche', (t) async {
      await _ouvrir(t, _charpente());
      await _onglet(t, 'Murs');
      await t.tap(find.byKey(const ValueKey('murs_actifs')));
      await t.pumpAndSettle();
      final liste = find.byKey(const ValueKey('murs_format_4x9'));
      await _voir(t, liste);
      await t.tap(liste);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('OSB isolant R-4').last);
      await t.pumpAndSettle();
      expect(find.textContaining('R4,15'), findsOneWidget);
    });
  });

  group('vue 3D', () {
    testWidgets(
      'toucher une pièce affiche sa fiche ; couche « solives » seulement',
      (t) async {
        await _ouvrir(t, _charpente());
        await _onglet(t, '3D');
        expect(find.byKey(const ValueKey('vue3d_principale')), findsOneWidget);
        // Toutes les couches du plancher : on touche une pièce quelque part sur le plancher.
        final zone = find.descendant(
          of: find.byKey(const ValueKey('vue3d_principale')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter != null &&
                w.painter.runtimeType.toString() == '_Peintre',
          ),
        );
        final c = t.getCenter(zone.first);
        await t.tapAt(c);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('vue_fiche')), findsOneWidget);
        // Fermer la fiche.
        await t.tap(find.byTooltip('Fermer'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('vue_fiche')), findsNothing);
      },
    );

    testWidgets('les couches : « Aucun » vide l\'écran, la vue se réajuste', (
      t,
    ) async {
      await _ouvrir(t, _charpente());
      await _onglet(t, '3D');
      await t.tap(find.byKey(const ValueKey('etape_Plancher_1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('etape_Plancher_1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('vue_dessus')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('vue_cotes')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('vue_legende')));
      await t.pumpAndSettle();
      expect(find.text('Légende'), findsOneWidget);
      expect(find.text('Solives de rive'), findsOneWidget);
    });

    testWidgets('rien à afficher sans plancher ni murs', (t) async {
      await _ouvrir(t, _charpente());
      await _voir(t, find.byKey(const ValueKey('plancher_actif')));
      await t.tap(find.byKey(const ValueKey('plancher_actif')));
      await t.pumpAndSettle();
      await _onglet(t, '3D');
      expect(find.textContaining('Rien à afficher'), findsOneWidget);
    });

    testWidgets('l\'aperçu du formulaire ouvre la vue 3D', (t) async {
      await _ouvrir(t, _charpente());
      await t.tap(find.byKey(const ValueKey('plancher_apercu')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vue3d_principale')), findsOneWidget);
    });
  });

  group('commande', () {
    testWidgets('liste du plancher, ligne ajoutée à la main, retirée', (
      t,
    ) async {
      await _ouvrir(t, _charpente());
      await _onglet(t, 'Commande');
      expect(find.text('BOIS D\'ŒUVRE'.toLowerCase()), findsNothing);
      expect(find.textContaining('2×10 × '), findsWidgets);
      expect(find.textContaining('Étrier de solive pour 2×10'), findsOneWidget);
      expect(find.textContaining('Sous-plancher 4 × 8 pi'), findsOneWidget);
      // Ajout manuel.
      await _voir(t, find.byKey(const ValueKey('commande_ajouter_ligne')));
      await t.tap(find.byKey(const ValueKey('commande_ajouter_ligne')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('ligne_article')),
        'Clous annelés (boîte)',
      );
      await t.enterText(find.byKey(const ValueKey('ligne_quantite')), '2');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ligne_ok')));
      await t.pumpAndSettle();
      expect(find.textContaining('2 × Clous annelés (boîte)'), findsOneWidget);
      // Retrait de la ligne.
      await t.tap(find.byTooltip('Retirer cette ligne'));
      await t.pumpAndSettle();
      expect(find.textContaining('Clous annelés'), findsNothing);
    });

    testWidgets(
      'quantité nulle ou article vide : le bouton Ajouter reste désactivé',
      (t) async {
        await _ouvrir(t, _charpente());
        await _onglet(t, 'Commande');
        await _voir(t, find.byKey(const ValueKey('commande_ajouter_ligne')));
        await t.tap(find.byKey(const ValueKey('commande_ajouter_ligne')));
        await t.pumpAndSettle();
        FilledButton ok() =>
            t.widget<FilledButton>(find.byKey(const ValueKey('ligne_ok')));
        expect(ok().onPressed, isNull);
        await t.enterText(find.byKey(const ValueKey('ligne_article')), 'Colle');
        await t.enterText(find.byKey(const ValueKey('ligne_quantite')), '0');
        await t.pumpAndSettle();
        expect(ok().onPressed, isNull);
        await t.enterText(find.byKey(const ValueKey('ligne_quantite')), '1,5');
        await t.pumpAndSettle();
        expect(ok().onPressed, isNotNull);
      },
    );

    testWidgets('hors ligne : enregistrement désactivé', (t) async {
      await _ouvrir(
        t,
        _app(
          const CharpenteScreen(
            companyId: 'A',
            chantierId: 'chA',
            connecte: false,
            listeEnregistrees: Text('(aucune commande)'),
          ),
        ),
      );
      await _onglet(t, 'Commande');
      await _voir(t, find.byKey(const ValueKey('commande_enregistrer')));
      final b = t.widget<FilledButton>(
        find.byKey(const ValueKey('commande_enregistrer')),
      );
      expect(b.onPressed, isNull);
      expect(find.textContaining('Hors ligne'), findsOneWidget);
    });

    testWidgets('sans plancher ni murs : rien à commander', (t) async {
      await _ouvrir(t, _charpente());
      await _voir(t, find.byKey(const ValueKey('plancher_actif')));
      await t.tap(find.byKey(const ValueKey('plancher_actif')));
      await t.pumpAndSettle();
      await _onglet(t, 'Commande');
      expect(find.textContaining('Rien à commander'), findsOneWidget);
      final b = t.widget<FilledButton>(
        find.byKey(const ValueKey('commande_enregistrer')),
      );
      expect(b.onPressed, isNull);
    });
  });

  group('état et unités', () {
    testWidgets('le calcul est gardé sur l\'appareil et retrouvé', (t) async {
      await _ouvrir(t, _charpente());
      await t.enterText(
        find.byKey(const ValueKey('charpente_nom')),
        'Garage Tremblay',
      );
      await t.enterText(_champ('rect_longueur'), "20'");
      await t.pumpAndSettle(const Duration(seconds: 2));
      // Nouvel écran : le brouillon est relu.
      await t.pumpWidget(_app(const SizedBox()));
      await t.pumpWidget(_charpente());
      await t.pumpAndSettle();
      final nom = t.widget<TextField>(
        find.byKey(const ValueKey('charpente_nom')),
      );
      expect(nom.controller!.text, 'Garage Tremblay');
      final champ = t.widget<TextField>(_champ('rect_longueur'));
      expect(champ.controller!.text, "20'");
    });

    testWidgets('« Nouveau calcul » efface après confirmation', (t) async {
      await _ouvrir(t, _charpente());
      await t.enterText(
        find.byKey(const ValueKey('charpente_nom')),
        'À effacer',
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('charpente_nouveau')));
      await t.pumpAndSettle();
      expect(find.text('Nouveau calcul ?'), findsOneWidget);
      await t.tap(find.text('Effacer'));
      await t.pumpAndSettle();
      final nom = t.widget<TextField>(
        find.byKey(const ValueKey('charpente_nom')),
      );
      expect(nom.controller!.text, isEmpty);
    });

    testWidgets('métrique : les champs de longueur parlent en mètres', (
      t,
    ) async {
      Preferences.unites.value = SystemeUnites.metrique;
      await _ouvrir(t, _charpente());
      final champ = t.widget<TextField>(_champ('rect_longueur'));
      expect(champ.controller!.text, contains('m'));
      expect(champ.controller!.text, isNot(contains("'")));
      // 156 po = 3,962 m.
      await t.enterText(_champ('rect_longueur'), '6 m');
      await t.pumpAndSettle();
      expect(find.textContaining('Nombre invalide'), findsNothing);
    });
  });

  group('onglet Calcul du chantier', () {
    testWidgets('feuilles ou charpente', (t) async {
      await _ouvrir(
        t,
        _app(
          const CalculChantier(
            companyId: 'A',
            chantierId: 'chA',
            connecte: true,
            listeEnregistrees: Text('(aucune commande)'),
          ),
        ),
      );
      expect(find.text('Surface à couvrir'), findsOneWidget);
      await t.tap(find.text('Charpente'));
      await t.pumpAndSettle();
      expect(find.text('Nom du calcul'), findsOneWidget);
      await t.tap(find.text('Feuilles'));
      await t.pumpAndSettle();
      expect(find.text('Surface à couvrir'), findsOneWidget);
    });

    testWidgets('feuilles : 4 × 9 pi et OSB isolant R-4 sont proposés', (
      t,
    ) async {
      await _ouvrir(
        t,
        _app(
          const CalculChantier(
            companyId: 'A',
            chantierId: 'chA',
            connecte: true,
            listeEnregistrees: Text('(aucune commande)'),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('materiaux_format')));
      await t.pumpAndSettle();
      expect(find.textContaining('4 × 9 pi'), findsWidgets);
      expect(find.textContaining('Isobrace'), findsWidgets);
    });
  });

  group('assistant IA', () {
    Map<String, dynamic> reponse() => {
      'explication': 'Garage avec fenêtre et porte.',
      'hypotheses': ['Entraxe de 16 po supposé.', 'Porte centrée sur le mur.'],
      'projet': jsonDecode(
        File('test/charpente/projet_assistant.json').readAsStringSync(),
      ),
    };

    Widget ecran(AppelAssistant appel, {bool connecte = true}) => _app(
      CharpenteScreen(
        companyId: 'A',
        chantierId: 'chA',
        connecte: connecte,
        listeEnregistrees: const Text('(aucune commande)'),
        appelAssistant: appel,
      ),
    );

    Future<void> ouvrirAssistant(WidgetTester t, String texte) async {
      await t.tap(find.byKey(const ValueKey('charpente_assistant')));
      await t.pumpAndSettle();
      expect(find.text('Assistant IA'), findsWidgets);
      await t.enterText(find.byKey(const ValueKey('assistant_texte')), texte);
      await t.pumpAndSettle();
    }

    testWidgets('description → aperçu avec hypothèses → projet appliqué', (
      t,
    ) async {
      final appels = <(String, String?)>[];
      await _ouvrir(
        t,
        ecran((texte, actuel) async {
          appels.add((texte, actuel));
          return reponse();
        }),
      );
      await ouvrirAssistant(t, 'garage de 13 par 10 pi 6 avec une fenêtre');
      await t.tap(find.byKey(const ValueKey('assistant_interpreter')));
      await t.pumpAndSettle();
      expect(appels, hasLength(1));
      expect(appels.single.$1, 'garage de 13 par 10 pi 6 avec une fenêtre');
      expect(
        appels.single.$2,
        isNull,
      ); // « Interpréter » ne transmet pas le calcul actuel
      expect(
        find.text('Ce que l’assistant a compris'.replaceAll('’', "'")),
        findsOneWidget,
      );
      expect(find.text('Garage avec fenêtre et porte.'), findsOneWidget);
      expect(find.textContaining('Entraxe de 16 po supposé.'), findsOneWidget);
      expect(
        find.textContaining('Murs : 4 murs, 2 ouverture(s)'),
        findsOneWidget,
      );
      // Rien n'est appliqué avant la confirmation.
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('charpente_nom')))
            .controller!
            .text,
        isEmpty,
      );
      await t.tap(find.byKey(const ValueKey('assistant_appliquer')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('charpente_nom')))
            .controller!
            .text,
        'Garage Tremblay',
      );
      await _onglet(t, 'Murs');
      expect(find.text('Contour du plancher'), findsOneWidget);
      await _onglet(t, 'Commande');
      expect(find.textContaining('Isobrace'), findsWidgets);
    });

    testWidgets('« Modifier le calcul actuel » transmet le projet en cours', (
      t,
    ) async {
      String? recu;
      await _ouvrir(
        t,
        ecran((texte, actuel) async {
          recu = actuel;
          return reponse();
        }),
      );
      await t.enterText(
        find.byKey(const ValueKey('charpente_nom')),
        'Mon projet',
      );
      await t.pumpAndSettle();
      await ouvrirAssistant(t, 'passe l’entraxe à 12 po'.replaceAll('’', "'"));
      await t.tap(find.byKey(const ValueKey('assistant_modifier')));
      await t.pumpAndSettle();
      expect(recu, isNotNull);
      final j = jsonDecode(recu!) as Map<String, dynamic>;
      expect(j['v'], 1);
      expect(j['nom'], 'Mon projet');
    });

    testWidgets(
      'serveur : assistant non activé, réseau coupé, réponse illisible',
      (t) async {
        var cas = 0;
        await _ouvrir(
          t,
          ecran((texte, actuel) async {
            cas++;
            if (cas == 1) {
              throw FirebaseFunctionsException(
                message: "L'assistant IA n'est pas encore activé.",
                code: 'failed-precondition',
              );
            }
            if (cas == 2) {
              throw Exception('hors ligne');
            }
            return {
              'explication': 'x',
              'projet': {'v': 1},
            };
          }),
        );
        await ouvrirAssistant(t, 'plancher 10 par 13');
        await t.tap(find.byKey(const ValueKey('assistant_interpreter')));
        await t.pumpAndSettle();
        expect(find.textContaining('pas encore activé'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('assistant_interpreter')));
        await t.pumpAndSettle();
        expect(find.textContaining('Erreur de réseau'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('assistant_interpreter')));
        await t.pumpAndSettle();
        expect(find.textContaining('illisible'), findsOneWidget);
        expect(find.byKey(const ValueKey('assistant_appliquer')), findsNothing);
      },
    );

    testWidgets(
      'texte trop court : bouton désactivé ; hors ligne : assistant désactivé',
      (t) async {
        await _ouvrir(t, ecran((a, b) async => reponse()));
        await t.tap(find.byKey(const ValueKey('charpente_assistant')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const ValueKey('assistant_interpreter')),
              )
              .onPressed,
          isNull,
        );
        await t.enterText(find.byKey(const ValueKey('assistant_texte')), 'abc');
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const ValueKey('assistant_interpreter')),
              )
              .onPressed,
          isNull,
        );
        await t.enterText(
          find.byKey(const ValueKey('assistant_texte')),
          'abcde',
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const ValueKey('assistant_interpreter')),
              )
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'hors ligne : bouton de l’assistant inactif'.replaceAll('’', "'"),
      (t) async {
        await _ouvrir(t, ecran((a, b) async => reponse(), connecte: false));
        final b = t.widget<IconButton>(
          find.byKey(const ValueKey('charpente_assistant')),
        );
        expect(b.onPressed, isNull);
      },
    );
  });
}
