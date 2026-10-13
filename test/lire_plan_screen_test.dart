// « Calculer à partir d'un plan » : choix des fichiers, lecture, confirmation des valeurs
// incertaines, corrections, aperçu 3D et matériaux calculés.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:construction_app/charpente/lecture_plan.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:construction_app/screens/charpente/lire_plan_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:construction_app/services/selecteur_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'doubles/faux_plans.dart';

const _f2Largeur = 'murs.ouverturesContour.1.0.largeur';
const _f2Allege = 'murs.ouverturesContour.1.0.allege';

Finder _cle(String c) => find.byKey(ValueKey(c));

/// Ce que l'appel au serveur a reçu.
class _Appels {
  final List<List<PlanFichier>> fichiers = [];
  final List<String> precisions = [];
}

AppelLecturePlan _serveur(
  Map<String, dynamic> reponse, {
  _Appels? appels,
  Completer<void>? attendre,
}) => (fichiers, precisions) async {
  appels?.fichiers.add(fichiers);
  appels?.precisions.add(precisions);
  if (attendre != null) await attendre.future;
  return reponse;
};

AppelLecturePlan _serveurEnErreur(Object erreur) =>
    (fichiers, precisions) async => throw erreur;

/// L'écran dans un hôte qui garde ce qu'il rend (le projet appliqué).
class _Hote {
  ProjetCharpente? projet;
  bool ferme = false;
}

Widget _app(
  _Hote hote, {
  required AppelLecturePlan appeler,
  SelecteurPlans? selecteur,
  bool calculExistant = false,
}) => MaterialApp(
  home: Builder(
    builder: (ctx) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            hote.projet = await Navigator.of(ctx).push<ProjetCharpente>(
              MaterialPageRoute(
                builder: (_) => LirePlanScreen(
                  appeler: appeler,
                  selecteur: selecteur ?? SelecteurPlansFaux(),
                  calculExistant: calculExistant,
                ),
              ),
            );
            hote.ferme = true;
          },
          child: const Text('ouvrir'),
        ),
      ),
    ),
  ),
);

Future<void> _ouvrir(
  WidgetTester t,
  _Hote hote, {
  required AppelLecturePlan appeler,
  SelecteurPlans? selecteur,
  bool calculExistant = false,
}) async {
  t.view.physicalSize = const Size(900, 24000);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    _app(
      hote,
      appeler: appeler,
      selecteur: selecteur,
      calculExistant: calculExistant,
    ),
  );
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
}

SelecteurPlansFaux _unPdf() => SelecteurPlansFaux(
  fichiers: [
    ChoixPlans([planFaux('rez-de-chaussee.pdf', octets: 250000)]),
  ],
);

/// Choisit un PDF, lance la lecture et attend la revue.
Future<_Appels> _jusqueALaRevue(
  WidgetTester t,
  _Hote hote, {
  Map<String, dynamic>? reponse,
  bool calculExistant = false,
}) async {
  final appels = _Appels();
  await _ouvrir(
    t,
    hote,
    appeler: _serveur(reponse ?? lectureGarage(), appels: appels),
    selecteur: _unPdf(),
    calculExistant: calculExistant,
  );
  await t.tap(_cle('plan_choisir_fichier'));
  await t.pumpAndSettle();
  await t.tap(_cle('plan_analyser'));
  await t.pumpAndSettle();
  return appels;
}

Finder _champ(String chemin) => find.descendant(
  of: _cle('champ_$chemin'),
  matching: find.byType(TextField),
);

bool _actif(WidgetTester t, String cle) =>
    t.widget<FilledButton>(find.byKey(ValueKey(cle))).onPressed != null;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  group('choix des fichiers', () {
    testWidgets('au départ : rien à lire, consignes et confidentialité', (
      t,
    ) async {
      await _ouvrir(t, _Hote(), appeler: _serveur(lectureGarage()));
      expect(find.text('Calculer à partir d\'un plan'), findsOneWidget);
      expect(_actif(t, 'plan_analyser'), isFalse);
      expect(
        find.textContaining('Chantier+ ne le conserve pas'),
        findsOneWidget,
      );
      expect(find.textContaining('Jusqu\'à 5 fichiers'), findsOneWidget);
      expect(find.textContaining('toiture'), findsOneWidget);
      expect(find.text('Fichiers joints'), findsNothing);
    });

    testWidgets(
      'un PDF choisi apparaît avec sa taille ; le retirer désactive la lecture',
      (t) async {
        await _ouvrir(
          t,
          _Hote(),
          appeler: _serveur(lectureGarage()),
          selecteur: _unPdf(),
        );
        await t.tap(_cle('plan_choisir_fichier'));
        await t.pumpAndSettle();
        expect(find.text('rez-de-chaussee.pdf'), findsOneWidget);
        expect(find.text('244 Ko'), findsOneWidget);
        expect(_actif(t, 'plan_analyser'), isTrue);
        await t.tap(_cle('plan_retirer_0'));
        await t.pumpAndSettle();
        expect(find.text('rez-de-chaussee.pdf'), findsNothing);
        expect(_actif(t, 'plan_analyser'), isFalse);
      },
    );

    testWidgets('photo et galerie s\'ajoutent à la suite', (t) async {
      final sel = SelecteurPlansFaux(
        photos: [
          ChoixPlans([planFaux('photo1.jpg')]),
        ],
        galerie: [
          ChoixPlans([planFaux('page2.png'), planFaux('page3.webp')]),
        ],
      );
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage()),
        selecteur: sel,
      );
      await t.tap(_cle('plan_prendre_photo'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_choisir_photos'));
      await t.pumpAndSettle();
      expect(find.text('photo1.jpg'), findsOneWidget);
      expect(find.text('page2.png'), findsOneWidget);
      expect(find.text('page3.webp'), findsOneWidget);
      expect(sel.appelsPhoto, 1);
      expect(sel.appelsGalerie, 1);
      expect(_cle('plan_fichier_2'), findsOneWidget);
    });

    testWidgets('fichiers refusés par le sélecteur : listés avec la raison', (
      t,
    ) async {
      final sel = SelecteurPlansFaux(
        fichiers: [
          ChoixPlans(
            [planFaux('ok.pdf')],
            [
              'anime.gif : format non accepté (PDF, JPEG, PNG ou WebP seulement)',
            ],
          ),
        ],
      );
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage()),
        selecteur: sel,
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      expect(find.text('ok.pdf'), findsOneWidget);
      expect(
        find.textContaining('Refusé — anime.gif : format non accepté'),
        findsOneWidget,
      );
    });

    testWidgets('l\'écran revérifie format, taille, vide, nombre et total', (
      t,
    ) async {
      final sel = SelecteurPlansFaux(
        fichiers: [
          ChoixPlans([
            planFaux('trop-gros.pdf', octets: tailleMaxFichierPlan + 1),
            planFaux('anime.gif'),
            planFaux('vide.pdf', octets: 0),
            planFaux('a.pdf', octets: 7 * 1024 * 1024),
            planFaux('b.pdf', octets: 7 * 1024 * 1024),
          ]),
        ],
      );
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage()),
        selecteur: sel,
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.text('b.pdf'), findsNothing);
      expect(
        find.textContaining('trop-gros.pdf : trop volumineux'),
        findsOneWidget,
      );
      expect(
        find.textContaining('anime.gif : format non accepté'),
        findsOneWidget,
      );
      expect(find.textContaining('vide.pdf : fichier vide'), findsOneWidget);
      expect(
        find.textContaining('b.pdf : le total dépasserait 12.0 Mo'),
        findsOneWidget,
      );
    });

    testWidgets('au plus 5 fichiers', (t) async {
      final sel = SelecteurPlansFaux(
        fichiers: [
          ChoixPlans([for (var i = 1; i <= 5; i++) planFaux('p$i.pdf')]),
          ChoixPlans([planFaux('de-trop.pdf')]),
        ],
      );
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage()),
        selecteur: sel,
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      expect(find.text('p5.pdf'), findsOneWidget);
      expect(find.text('de-trop.pdf'), findsNothing);
      expect(
        find.textContaining('de-trop.pdf : 5 fichiers au maximum'),
        findsOneWidget,
      );
    });

    testWidgets('le sélecteur qui échoue : message, rien ne casse', (t) async {
      final sel = SelecteurPlansFaux()
        ..erreur = Exception('permission refusée');
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage()),
        selecteur: sel,
      );
      await t.tap(_cle('plan_prendre_photo'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Impossible d\'ouvrir le sélecteur'),
        findsOneWidget,
      );
      expect(_actif(t, 'plan_analyser'), isFalse);
    });

    testWidgets('annuler le sélecteur (aucun fichier) : rien ne change', (
      t,
    ) async {
      await _ouvrir(t, _Hote(), appeler: _serveur(lectureGarage()));
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      expect(find.text('Fichiers joints'), findsNothing);
      expect(find.textContaining('Refusé'), findsNothing);
    });
  });

  group('lecture par l\'assistant', () {
    testWidgets('envoie les fichiers et les précisions (sans espaces autour)', (
      t,
    ) async {
      final appels = await _jusqueALaRevueAvecPrecisions(t);
      expect(appels.fichiers.single.single.nom, 'rez-de-chaussee.pdf');
      expect(appels.fichiers.single.single.taille, 250000);
      expect(appels.precisions.single, 'Seulement le garage');
    });

    testWidgets('sans précisions : chaîne vide', (t) async {
      final appels = await _jusqueALaRevue(t, _Hote());
      expect(appels.precisions.single, '');
    });

    testWidgets('pendant l\'attente : message de patience et bouton Annuler', (
      t,
    ) async {
      final attendre = Completer<void>();
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage(), attendre: attendre),
        selecteur: _unPdf(),
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_analyser'));
      await t.pump();
      expect(find.text('Lecture du plan en cours…'), findsOneWidget);
      expect(_cle('plan_annuler_analyse'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      attendre.complete();
      await t.pumpAndSettle();
      expect(find.text('Plan lu'), findsOneWidget);
    });

    testWidgets('annuler : retour au choix, le résultat tardif est ignoré', (
      t,
    ) async {
      final attendre = Completer<void>();
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur(lectureGarage(), attendre: attendre),
        selecteur: _unPdf(),
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_analyser'));
      await t.pump();
      await t.tap(_cle('plan_annuler_analyse'));
      await t.pumpAndSettle();
      expect(_cle('plan_analyser'), findsOneWidget);
      expect(find.text('rez-de-chaussee.pdf'), findsOneWidget);
      attendre.complete();
      await t.pumpAndSettle();
      expect(find.text('Plan lu'), findsNothing);
      expect(_cle('plan_analyser'), findsOneWidget);
    });

    testWidgets(
      'erreur du serveur : son message, on reste au choix avec les fichiers',
      (t) async {
        await _ouvrir(
          t,
          _Hote(),
          appeler: _serveurEnErreur(
            FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'Ce document ne semble pas contenir un plan de construction lisible.',
            ),
          ),
          selecteur: _unPdf(),
        );
        await t.tap(_cle('plan_choisir_fichier'));
        await t.pumpAndSettle();
        await t.tap(_cle('plan_analyser'));
        await t.pumpAndSettle();
        expect(
          find.textContaining('ne semble pas contenir un plan'),
          findsOneWidget,
        );
        expect(find.text('rez-de-chaussee.pdf'), findsOneWidget);
        expect(_actif(t, 'plan_analyser'), isTrue);
      },
    );

    testWidgets(
      'erreur interne, réseau coupé, réponse illisible : messages sobres',
      (t) async {
        Future<void> essayer(Object erreur, String attendu) async {
          await _ouvrir(
            t,
            _Hote(),
            appeler: _serveurEnErreur(erreur),
            selecteur: _unPdf(),
          );
          await t.tap(_cle('plan_choisir_fichier'));
          await t.pumpAndSettle();
          await t.tap(_cle('plan_analyser'));
          await t.pumpAndSettle();
          expect(find.textContaining(attendu), findsOneWidget);
          // Referme l'écran pour le cas suivant.
          await t.pageBack();
          await t.pumpAndSettle();
        }

        await essayer(
          FirebaseFunctionsException(
            code: 'internal',
            message: 'stack trace secrète',
          ),
          'La lecture du plan a échoué',
        );
        expect(find.textContaining('stack trace'), findsNothing);
        await essayer(Exception('socket'), 'Erreur de réseau');
        await essayer(
          const FormatException('x'),
          'La réponse de l\'assistant est illisible',
        );
      },
    );

    testWidgets('réponse sans projet exploitable : message, retour au choix', (
      t,
    ) async {
      await _ouvrir(
        t,
        _Hote(),
        appeler: _serveur({'explication': 'rien', 'valeurs': []}),
        selecteur: _unPdf(),
      );
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_analyser'));
      await t.pumpAndSettle();
      expect(find.textContaining('illisible'), findsOneWidget);
      expect(find.text('Plan lu'), findsNothing);
    });

    testWidgets('après une erreur, on peut réessayer', (t) async {
      var essai = 0;
      Future<Map<String, dynamic>> appel(List<PlanFichier> f, String p) async {
        essai++;
        if (essai == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Momentanément indisponible.',
          );
        }
        return lectureGarage();
      }

      await _ouvrir(t, _Hote(), appeler: appel, selecteur: _unPdf());
      await t.tap(_cle('plan_choisir_fichier'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_analyser'));
      await t.pumpAndSettle();
      expect(find.textContaining('Momentanément indisponible'), findsOneWidget);
      await t.tap(_cle('plan_analyser'));
      await t.pumpAndSettle();
      expect(find.text('Plan lu'), findsOneWidget);
      expect(find.textContaining('Momentanément indisponible'), findsNothing);
    });
  });

  group('revue de la lecture', () {
    testWidgets('les sections : à confirmer, à vérifier, hypothèses, résumé', (
      t,
    ) async {
      await _jusqueALaRevue(t, _Hote());
      expect(find.text('Plan lu'), findsOneWidget);
      expect(find.textContaining('Garage de 24 pi × 20 pi'), findsOneWidget);
      expect(
        find.text(
          'Niveau lu : Rez-de-chaussée, page 2 • Échelle : 1/4 po = 1 pi',
        ),
        findsOneWidget,
      );
      expect(find.text('À confirmer (2)'), findsOneWidget);
      expect(find.text('À vérifier (5)'), findsOneWidget);
      expect(find.text('Hypothèses de l\'assistant'), findsOneWidget);
      expect(
        find.text('• Entraxe des solives de 16 po supposé.'),
        findsOneWidget,
      );
      expect(find.text('Ce que l\'assistant a lu'), findsOneWidget);
      expect(
        find.text('1 porte et 2 fenêtres relevées au plan'),
        findsOneWidget,
      );
      expect(find.text('Cotes lues sur le plan (8)'), findsOneWidget);
    });

    testWidgets('le résumé : plancher, chaque mur, chaque porte et fenêtre', (
      t,
    ) async {
      await _jusqueALaRevue(t, _Hote());
      final long = formatLongueur(288, metrique: false);
      final large = formatLongueur(240, metrique: false);
      expect(
        find.text('Plancher : $long × $large, solives 2×10 à 16 po c/c'),
        findsOneWidget,
        reason: 'plancher',
      );
      expect(find.textContaining('Mur 1 : $long de long'), findsOneWidget);
      expect(find.textContaining('Mur 2 : $large de long'), findsOneWidget);
      final f1 = find.textContaining(
        '• Fenêtre F1 : ${formatLongueur(36, metrique: false)} × ${formatLongueur(48, metrique: false)}, allège ${formatLongueur(36, metrique: false)}',
      );
      expect(f1, findsOneWidget);
      expect(
        find.textContaining(
          '• Porte P1 : ${formatLongueur(36, metrique: false)} × ${formatLongueur(80, metrique: false)}, centrée à',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '• Fenêtre F2 : ${formatLongueur(24, metrique: false)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'une valeur incertaine : repère, raison, cote imprimée, valeur du plan',
      (t) async {
        await _jusqueALaRevue(t, _Hote());
        final fiche = _cle('valeur_$_f2Largeur');
        expect(
          find.descendant(
            of: fiche,
            matching: find.text('Mur 2 — Fenêtre F2 — largeur'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: fiche,
            matching: find.textContaining('Le plan indique « 3\'-0" »'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: fiche,
            matching: find.text('Lu sur le plan : « 3\'-0" »'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: fiche,
            matching: find.text(
              'Valeur du plan : ${formatLongueur(36, metrique: false)}',
            ),
          ),
          findsOneWidget,
        );
        expect(_cle('utiliser_$_f2Largeur'), findsOneWidget);
        expect(
          find.descendant(
            of: _cle('valeur_$_f2Allege'),
            matching: find.text('Allège illisible sur la coupe.'),
          ),
          findsOneWidget,
        );
        expect(
          _cle('utiliser_$_f2Allege'),
          findsNothing,
          reason: 'pas de valeur du plan pour l\'allège',
        );
      },
    );

    testWidgets(
      'appliquer reste bloqué tant qu\'une valeur incertaine n\'est pas confirmée',
      (t) async {
        final hote = _Hote();
        await _jusqueALaRevue(t, hote);
        expect(_actif(t, 'plan_appliquer'), isFalse);
        expect(
          find.text('Confirmez les 2 valeurs incertaines pour continuer.'),
          findsOneWidget,
        );

        await t.tap(_cle('confirmer_$_f2Largeur'));
        await t.pumpAndSettle();
        expect(_actif(t, 'plan_appliquer'), isFalse);
        expect(
          find.text('Confirmez la valeur incertaine pour continuer.'),
          findsOneWidget,
        );
        expect(_cle('revoir_$_f2Largeur'), findsOneWidget);

        await t.tap(_cle('confirmer_$_f2Allege'));
        await t.pumpAndSettle();
        expect(_actif(t, 'plan_appliquer'), isTrue);
        expect(_cle('plan_restantes'), findsNothing);

        // Revoir une valeur bloque de nouveau.
        await t.tap(_cle('revoir_$_f2Allege'));
        await t.pumpAndSettle();
        expect(_actif(t, 'plan_appliquer'), isFalse);
        expect(hote.ferme, isFalse);
      },
    );

    testWidgets('les valeurs « à vérifier » ne bloquent pas', (t) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote);
      await t.tap(_cle('confirmer_$_f2Largeur'));
      await t.tap(_cle('confirmer_$_f2Allege'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: _cle('valeur_murs.hauteur'),
          matching: find.text('Confirmer cette valeur'),
        ),
        findsOneWidget,
        reason: 'toujours non confirmée',
      );
      expect(_actif(t, 'plan_appliquer'), isTrue);
    });

    testWidgets('appliquer : le projet confirmé revient à l\'écran de calcul', (
      t,
    ) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote);
      await t.tap(_cle('confirmer_$_f2Largeur'));
      await t.tap(_cle('confirmer_$_f2Allege'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(hote.ferme, isTrue);
      final p = hote.projet!;
      expect(p.nom, 'Garage Tremblay');
      expect(p.mursActifs, isTrue);
      expect((p.plancher.forme as FormeRectangle).longueur, 288);
      expect(p.murs.ouverturesContour[1]!.single.largeurCadre, 24);
    });

    testWidgets('retour sans appliquer : rien n\'est rendu', (t) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(hote.ferme, isTrue);
      expect(hote.projet, isNull);
    });

    testWidgets('confiance faible : avertissement', (t) async {
      final r = lectureGarage()..['confiance'] = 'faible';
      await _jusqueALaRevue(t, _Hote(), reponse: r);
      expect(find.textContaining('Lecture peu sûre'), findsOneWidget);
    });

    testWidgets('confiance élevée ou moyenne : pas d\'avertissement', (
      t,
    ) async {
      await _jusqueALaRevue(t, _Hote());
      expect(find.textContaining('Lecture peu sûre'), findsNothing);
    });

    testWidgets(
      'rien d\'incertain : appliquer tout de suite, sans section « à confirmer »',
      (t) async {
        final r = lectureGarage();
        r['valeurs'] = [
          {
            'chemin': 'plancher.forme.longueur',
            'niveau': 'lu',
            'lecture': '24\'-0"',
            'verifiee': true,
          },
        ];
        await _jusqueALaRevue(t, _Hote(), reponse: r);
        expect(find.textContaining('À confirmer'), findsNothing);
        expect(find.textContaining('À vérifier'), findsNothing);
        expect(_actif(t, 'plan_appliquer'), isTrue);
      },
    );

    testWidgets(
      'les cotes lues se déplient : valeur, cote du plan, « vérifié »',
      (t) async {
        await _jusqueALaRevue(t, _Hote());
        await t.tap(_cle('plan_cotes_lues'));
        await t.pumpAndSettle();
        expect(find.text('Plancher — longueur'), findsOneWidget);
        expect(
          find.text(
            '${formatLongueur(288, metrique: false)} — plan : « 24\'-0" » (conversion vérifiée)',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(8));
      },
    );
  });

  group('corrections', () {
    testWidgets(
      'corriger une valeur : le résumé suit, la confirmation est à refaire',
      (t) async {
        final hote = _Hote();
        await _jusqueALaRevue(t, hote);
        await t.tap(_cle('confirmer_$_f2Largeur'));
        await t.pumpAndSettle();
        expect(_cle('revoir_$_f2Largeur'), findsOneWidget);

        await t.enterText(_champ(_f2Largeur), '3\'');
        await t.pumpAndSettle();
        expect(
          _cle('confirmer_$_f2Largeur'),
          findsOneWidget,
          reason: 'à reconfirmer',
        );
        expect(
          find.textContaining(
            '• Fenêtre F2 : ${formatLongueur(36, metrique: false)} ×',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            '• Fenêtre F2 : ${formatLongueur(24, metrique: false)}',
          ),
          findsNothing,
        );

        await t.tap(_cle('confirmer_$_f2Largeur'));
        await t.tap(_cle('confirmer_$_f2Allege'));
        await t.pumpAndSettle();
        await t.tap(_cle('plan_appliquer'));
        await t.pumpAndSettle();
        expect(hote.projet!.murs.ouverturesContour[1]!.single.largeurCadre, 36);
      },
    );

    testWidgets(
      '« Utiliser cette valeur » : la valeur du plan est reprise et confirmée',
      (t) async {
        final hote = _Hote();
        await _jusqueALaRevue(t, hote);
        await t.tap(_cle('utiliser_$_f2Largeur'));
        await t.pumpAndSettle();
        expect(_cle('revoir_$_f2Largeur'), findsOneWidget);
        expect(
          find.descendant(
            of: _cle('valeur_$_f2Largeur'),
            matching: find.byIcon(Icons.check_circle),
          ),
          findsOneWidget,
        );
        await t.tap(_cle('confirmer_$_f2Allege'));
        await t.pumpAndSettle();
        await t.tap(_cle('plan_appliquer'));
        await t.pumpAndSettle();
        expect(hote.projet!.murs.ouverturesContour[1]!.single.largeurCadre, 36);
      },
    );

    testWidgets(
      'valeur hors des bornes : le champ signale l\'erreur, la valeur reste',
      (t) async {
        final hote = _Hote();
        await _jusqueALaRevue(t, hote);
        await t.enterText(_champ(_f2Largeur), '0');
        await t.pumpAndSettle();
        expect(find.textContaining('Entre'), findsWidgets);
        await t.tap(_cle('confirmer_$_f2Largeur'));
        await t.tap(_cle('confirmer_$_f2Allege'));
        await t.pumpAndSettle();
        await t.tap(_cle('plan_appliquer'));
        await t.pumpAndSettle();
        expect(hote.projet!.murs.ouverturesContour[1]!.single.largeurCadre, 24);
      },
    );

    testWidgets('texte illisible dans le champ : message, la valeur reste', (
      t,
    ) async {
      await _jusqueALaRevue(t, _Hote());
      await t.enterText(_champ(_f2Largeur), 'abc');
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(_champ(_f2Largeur)).decoration!.errorText,
        isNotNull,
      );
      // La valeur du projet n'a pas changé : le résumé montre toujours 2 pi.
      expect(
        find.textContaining(
          '• Fenêtre F2 : ${formatLongueur(24, metrique: false)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('les matériaux suivent chaque correction', (t) async {
      await _jusqueALaRevue(t, _Hote());
      final avant = calculerProjet(LecturePlan.depuis(lectureGarage()).projet)
          .commande;
      expect(avant.estVide, isFalse);
      expect(_cle('plan_materiaux'), findsOneWidget);
      for (final l in avant.lignes) {
        expect(
          find.text('${l.quantiteTexte} × ${l.article}'),
          findsWidgets,
          reason: l.article,
        );
      }

      // Une fenêtre plus large : le calcul des murs change (le linteau, les montants).
      await t.enterText(_champ(_f2Largeur), '8\'');
      await t.pumpAndSettle();
      final apres = calculerProjet(
        LecturePlan.depuis(lectureGarage()).modifier(_f2Largeur, 96).projet,
      ).commande;
      expect(
        [for (final l in apres.lignes) '${l.quantiteTexte} × ${l.article}'],
        isNot([
          for (final l in avant.lignes) '${l.quantiteTexte} × ${l.article}',
        ]),
      );
      for (final l in apres.lignes) {
        expect(
          find.text('${l.quantiteTexte} × ${l.article}'),
          findsWidgets,
          reason: l.article,
        );
      }
    });

    testWidgets('un choix (section des solives) se corrige dans une liste', (
      t,
    ) async {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'plancher.section',
        'niveau': 'incertain',
        'raison': 'Note du plan illisible.',
      });
      final hote = _Hote();
      await _jusqueALaRevue(t, hote, reponse: r);
      expect(find.text('À confirmer (3)'), findsOneWidget);
      await t.tap(
        find.descendant(
          of: _cle('valeur_plancher.section'),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('2×8').last);
      await t.pumpAndSettle();
      expect(
        find.text(
          'Plancher : ${formatLongueur(288, metrique: false)} × ${formatLongueur(240, metrique: false)}, solives 2×8 à 16 po c/c',
        ),
        findsOneWidget,
      );
      for (final c in ['plancher.section', _f2Largeur, _f2Allege]) {
        await t.tap(_cle('confirmer_$c'));
        await t.pumpAndSettle();
      }
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(hote.projet!.plancher.section.nom, '2×8');
    });

    testWidgets(
      'recommencer : retour au choix, fichiers et précisions gardés',
      (t) async {
        await _jusqueALaRevueAvecPrecisions(t);
        await t.tap(_cle('plan_recommencer'));
        await t.pumpAndSettle();
        expect(_cle('plan_analyser'), findsOneWidget);
        expect(find.text('rez-de-chaussee.pdf'), findsOneWidget);
        expect(find.textContaining('Seulement le garage'), findsOneWidget);
        expect(find.text('Plan lu'), findsNothing);
      },
    );
  });

  group('poutres, pieux et étriers', () {
    Map<String, dynamic> avecPoutres() {
      final r = lectureGarage();
      (((r['projet'] as Map)['plancher']) as Map)['poutres'] = {
        'nombre': 2,
        'plis': 3,
        'section': '2×8',
        'pieux': 3,
        'retraitPieux': 12,
        'hauteurPatte': 0,
      };
      (r['valeurs'] as List).addAll([
        {
          'chemin': 'plancher.poutres.pieux',
          'niveau': 'incertain',
          'raison': 'Pieux cachés par la cote.',
        },
      ]);
      return r;
    }

    testWidgets('pieux par poutre : un nombre entier, corrigé puis confirmé', (
      t,
    ) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote, reponse: avecPoutres());
      expect(find.text('Plancher — pieux par poutre'), findsOneWidget);
      await t.enterText(_champ('plancher.poutres.pieux'), '4');
      await t.pumpAndSettle();
      for (final c in ['plancher.poutres.pieux', _f2Largeur, _f2Allege]) {
        await t.tap(_cle('confirmer_$c'));
        await t.pumpAndSettle();
      }
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(hote.projet!.plancher.poutres!.pieuxParPoutre, 4);
    });

    testWidgets('étriers : liste Aucun / Un bout / Deux bouts', (t) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote);
      final carte = _cle('valeur_plancher.etriers');
      expect(
        find.descendant(
          of: carte,
          matching: find.text('Plancher — étriers de solive'),
        ),
        findsOneWidget,
      );
      await t.tap(
        find.descendant(
          of: carte,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Un bout'), findsWidgets);
      await t.tap(find.text('Un bout').last);
      await t.pumpAndSettle();
      for (final c in [_f2Largeur, _f2Allege]) {
        await t.tap(_cle('confirmer_$c'));
        await t.pumpAndSettle();
      }
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(hote.projet!.plancher.etriers.name, 'unBout');
    });
  });

  group('ce qui ne passe pas dans les murs', () {
    /// La fenêtre F2 du garage, trop haute pour son linteau (allège 40 + 90 po dans un mur de 8 pi).
    Map<String, dynamic> f2TropHaute() {
      final r = lectureGarage();
      final o =
          ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
      (o['1'] as List)[0]['hauteur'] = 90;
      for (final v in r['valeurs'] as List) {
        if (v['chemin'] == 'murs.ouverturesContour.1.0.hauteur') {
          v['niveau'] = 'incertain';
          v['raison'] = 'Ne passe pas sous la lisse haute.';
          v['verifiee'] = false;
        }
      }
      return r;
    }

    testWidgets('la liste complète, en rouge, avec le calcul', (t) async {
      await _jusqueALaRevue(t, _Hote(), reponse: f2TropHaute());
      expect(
        find.text('Ce qui ne passe pas dans les murs (1)'),
        findsOneWidget,
      );
      expect(_cle('plan_problemes_murs'), findsOneWidget);
      expect(
        find.textContaining(
          'Mur 2 : Fenêtre F2 : le linteau 2×8 ne passe pas sous la lisse haute',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('il manque'), findsOneWidget);
    });

    testWidgets('corriger la hauteur fait disparaître le problème', (t) async {
      await _jusqueALaRevue(t, _Hote(), reponse: f2TropHaute());
      await t.enterText(_champ('murs.ouverturesContour.1.0.hauteur'), '3\'');
      await t.pumpAndSettle();
      expect(_cle('plan_problemes_murs'), findsNothing);
      expect(find.textContaining('Ce qui ne passe pas'), findsNothing);
    });

    testWidgets('le garage : rien qui ne passe pas', (t) async {
      await _jusqueALaRevue(t, _Hote());
      expect(_cle('plan_problemes_murs'), findsNothing);
    });
  });

  group('avertissements', () {
    testWidgets(
      'une fenêtre sur un mur qui n\'existe pas : message rouge, jamais en silence',
      (t) async {
        final r = lectureGarage();
        final o =
            ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
        o['7'] = [
          {
            'type': 'fenetre',
            'nom': 'F9',
            'largeur': 36,
            'hauteur': 48,
            'allege': 36,
            'position': 60,
            'jeuLargeur': 1,
            'jeuHauteur': 1.5,
          },
        ];
        await _jusqueALaRevue(t, _Hote(), reponse: r);
        expect(_cle('plan_avertissements'), findsOneWidget);
        expect(find.textContaining('Fenêtre F9'), findsOneWidget);
        expect(find.textContaining('mur 8'), findsOneWidget);
      },
    );

    testWidgets('le garage : aucun avertissement', (t) async {
      await _jusqueALaRevue(t, _Hote());
      expect(_cle('plan_avertissements'), findsNothing);
    });

    testWidgets('l\'hypothèse sur les jeux est affichée', (t) async {
      await _jusqueALaRevue(t, _Hote());
      expect(
        find.textContaining('Jeux autour des portes et fenêtres'),
        findsOneWidget,
      );
    });
  });

  group('aperçu 3D et erreurs de calcul', () {
    testWidgets('aperçu 3D du résultat, agrandissable au toucher', (t) async {
      await _jusqueALaRevue(t, _Hote());
      expect(_cle('plan_apercu_3d'), findsOneWidget);
      await t.tap(_cle('plan_apercu_3d'));
      await t.pumpAndSettle();
      expect(find.text('Aperçu 3D'), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Plan lu'), findsOneWidget);
    });

    testWidgets(
      'le calcul signale un problème : message et « Appliquer et corriger »',
      (t) async {
        // Une fenêtre de 40 pi sur un mur de 20 pi.
        final r = lectureGarage();
        final o =
            ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
        (o['1'] as List)[0]['largeur'] = 480;
        await _jusqueALaRevue(t, _Hote(), reponse: r);
        expect(find.textContaining('Murs :'), findsOneWidget);
        expect(find.text('Appliquer et corriger'), findsOneWidget);
      },
    );

    testWidgets('plancher seul : pas de murs dans le résumé', (t) async {
      final r = lectureGarage();
      (r['projet'] as Map)['mursActifs'] = false;
      r['valeurs'] = [];
      await _jusqueALaRevue(t, _Hote(), reponse: r);
      expect(find.textContaining('Mur 1'), findsNothing);
      expect(find.textContaining('relevée'), findsNothing);
      expect(
        find.byKey(const ValueKey('plan_resume_plancher')),
        findsOneWidget,
      );
    });
  });

  group('remplacer un calcul en cours', () {
    testWidgets('demande confirmation ; annuler laisse l\'écran ouvert', (
      t,
    ) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote, calculExistant: true);
      await t.tap(_cle('confirmer_$_f2Largeur'));
      await t.tap(_cle('confirmer_$_f2Allege'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(find.text('Remplacer le calcul en cours ?'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(find.text('Plan lu'), findsOneWidget);
      expect(hote.ferme, isFalse);

      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_remplacer'));
      await t.pumpAndSettle();
      expect(hote.ferme, isTrue);
      expect(hote.projet!.nom, 'Garage Tremblay');
    });

    testWidgets('pas de calcul en cours : aucune question', (t) async {
      final hote = _Hote();
      await _jusqueALaRevue(t, hote);
      await t.tap(_cle('confirmer_$_f2Largeur'));
      await t.tap(_cle('confirmer_$_f2Allege'));
      await t.pumpAndSettle();
      await t.tap(_cle('plan_appliquer'));
      await t.pumpAndSettle();
      expect(find.text('Remplacer le calcul en cours ?'), findsNothing);
      expect(hote.ferme, isTrue);
    });
  });
}

/// Comme [_jusqueALaRevue], avec des précisions tapées (et des espaces autour).
Future<_Appels> _jusqueALaRevueAvecPrecisions(WidgetTester t) async {
  final appels = _Appels();
  await _ouvrir(
    t,
    _Hote(),
    appeler: _serveur(lectureGarage(), appels: appels),
    selecteur: _unPdf(),
  );
  await t.tap(_cle('plan_choisir_fichier'));
  await t.pumpAndSettle();
  await t.enterText(_cle('plan_precisions'), '  Seulement le garage  ');
  await t.tap(_cle('plan_analyser'));
  await t.pumpAndSettle();
  return appels;
}
