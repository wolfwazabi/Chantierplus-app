// Matériel « Général » côté écrans : choix toujours premier dans la liste, un
// contremaître ne voit que SA liste (l'admin a les filtres), liste Admin séparée par
// personne avec pastille « changement non vu ». Tout Firestore est remplacé par des
// doubles de test (voir doubles/faux_materiel.dart).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/materiel_general.dart';
import 'package:construction_app/screens/admin/admin_home_screen.dart';
import 'package:construction_app/screens/admin/chantiers_gestion_screen.dart';
import 'package:construction_app/screens/admin/materiel_general_screen.dart';
import 'package:construction_app/screens/chantier_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:construction_app/widgets/recherche_chantier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/faux_activite.dart';
import 'doubles/faux_materiel.dart';

DateTime _t(int jour, [int heure = 8]) => tTest(jour, heure);
final _e = entreeTest;
List<EntreeMateriel> _jeu() => jeuTest();
Finder _cle(String k) => find.byKey(ValueKey(k));

/// L'en-tête d'un groupe (pas son centre : ouvert, le centre tombe sur une demande).
Finder _entete(String auteur) => find
    .descendant(of: _cle('groupe_$auteur'), matching: find.byType(ListTile))
    .first;

Employee _emp(String id, String nom, EmployeeRole role) =>
    Employee(id: id, companyId: 'A', companyNom: 'Alpha', nom: nom, role: role);

void main() {
  tearDown(() => AppSession.notifier.value = null);

  // ===========================================================================
  group('Admin → Général : séparé par contremaître et admin', () {
    Future<FauxSource> ouvrir(
      WidgetTester tester, {
      List<EntreeMateriel>? donnees,
      Map<String, DateTime>? vus,
      Employee? moi,
    }) async {
      AppSession.notifier.value =
          moi ?? _emp('adminA', 'Admin A', EmployeeRole.admin);
      final source = FauxSource(donnees ?? _jeu(), vus);
      await tester.pumpWidget(
        MaterialApp(home: MaterielGeneralScreen(source: source)),
      );
      await tester.pumpAndSettle();
      return source;
    }

    String? pastille(String auteur) {
      final textes = find.descendant(
        of: _cle('pastille_groupe_$auteur'),
        matching: find.byType(Text),
      );
      return textes.evaluate().isEmpty
          ? null
          : (textes.evaluate().single.widget as Text).data;
    }

    testWidgets('réservé aux admins (le contremaître n\'y a pas accès)', (
      tester,
    ) async {
      final source = await ouvrir(
        tester,
        moi: _emp('plusA', 'Plus A', EmployeeRole.plus),
      );
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
      expect(source.abonnementsEntrees, 0); // rien n'est même lu
    });

    testWidgets(
      'un groupe par personne, en ordre alphabétique, avec le total à acheter',
      (tester) async {
        await ouvrir(tester);
        expect(_cle('groupe_plusA'), findsOneWidget);
        expect(_cle('groupe_plusB'), findsOneWidget);
        expect(_cle('groupe_adminA'), findsOneWidget);
        // Admin A, Bernard, Plus A.
        final y = [
          for (final id in ['adminA', 'plusB', 'plusA'])
            tester.getTopLeft(_cle('groupe_$id')).dy,
        ];
        expect(y[0], lessThan(y[1]));
        expect(y[1], lessThan(y[2]));
        expect(find.text('Plus A'), findsOneWidget);
        expect(find.text('Bernard'), findsOneWidget);
        // plusA : 2 à acheter + 1 obtenue ; total = 2 + 1 + 1 = 4 (personnes : 3).
        expect(find.text('2 à acheter • 1 obtenu'), findsOneWidget);
        expect(find.text('4 à acheter • 3 personnes'), findsOneWidget);
      },
    );

    testWidgets(
      'pastille : nombre de changements non vus, par personne (pas pour mes propres ajouts)',
      (tester) async {
        await ouvrir(tester);
        expect(pastille('plusA'), '3');
        expect(pastille('plusB'), '1');
        expect(pastille('adminA'), isNull);
      },
    );

    testWidgets(
      'le contenu d\'un groupe est caché tant qu\'on ne l\'ouvre pas',
      (tester) async {
        await ouvrir(tester);
        expect(_cle('entree_a1'), findsNothing);
        expect(_cle('entree_b1'), findsNothing);
      },
    );

    testWidgets(
      'ouvrir un groupe : sa liste, « Nouveau », et la pastille disparaît (seulement la sienne)',
      (tester) async {
        final source = await ouvrir(tester);
        await tester.tap(_cle('groupe_plusA'));
        await tester.pumpAndSettle();
        // À acheter d'abord (récent en premier), puis l'obtenue.
        expect(find.text('Clous 3 po'), findsOneWidget);
        expect(find.text('Sangles'), findsOneWidget);
        expect(find.text('Cordes'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Clous 3 po')).dy,
          lessThan(tester.getTopLeft(find.text('Sangles')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Sangles')).dy,
          lessThan(tester.getTopLeft(find.text('Cordes')).dy),
        );
        expect(find.textContaining('Quantité : 2 boîtes'), findsOneWidget);
        // Vu : une seule écriture, pour CETTE personne.
        expect(source.marques, ['plusA']);
        expect(pastille('plusA'), isNull);
        expect(pastille('plusB'), '1');
        // Les demandes nouvelles restent marquées pendant que la page est ouverte.
        for (final id in ['a1', 'a2', 'a3']) {
          expect(_cle('nouveau_$id'), findsOneWidget, reason: id);
        }
        expect(_cle('nouveau_b1'), findsNothing);
      },
    );

    testWidgets(
      'refermer puis rouvrir : plus de « Nouveau » (déjà vu), aucune écriture de plus',
      (tester) async {
        final source = await ouvrir(tester);
        await tester.tap(_entete('plusA'));
        await tester.pumpAndSettle();
        expect(_cle('nouveau_a1'), findsOneWidget);
        await tester.tap(_entete('plusA'));
        await tester.pumpAndSettle();
        expect(_cle('entree_a1'), findsNothing); // refermé
        await tester.tap(_entete('plusA'));
        await tester.pumpAndSettle();
        expect(_cle('entree_a1'), findsOneWidget); // rouvert
        expect(_cle('nouveau_a1'), findsNothing);
        expect(source.marques, ['plusA']);
      },
    );

    testWidgets(
      'mon propre groupe : rien de nouveau, donc aucune écriture « vu »',
      (tester) async {
        final source = await ouvrir(tester);
        await tester.tap(_cle('groupe_adminA'));
        await tester.pumpAndSettle();
        expect(find.text('Marteau'), findsOneWidget);
        expect(source.marques, isEmpty);
      },
    );

    testWidgets('déjà vu avant : pas de pastille au départ', (tester) async {
      await ouvrir(tester, vus: {'plusA': _t(15), 'plusB': _t(15)});
      expect(pastille('plusA'), isNull);
      expect(pastille('plusB'), isNull);
    });

    testWidgets(
      'une nouvelle demande arrive après la visite : la pastille revient',
      (tester) async {
        final source = await ouvrir(
          tester,
          vus: {'plusA': _t(15), 'plusB': _t(15)},
        );
        expect(pastille('plusA'), isNull);
        source.pousser([
          ..._jeu(),
          _e('a4', ajout: _t(18), texte: 'Niveau laser'),
        ]);
        await tester.pumpAndSettle();
        expect(pastille('plusA'), '1');
        expect(pastille('plusB'), isNull);
      },
    );

    testWidgets('une modification par la même personne rallume la pastille', (
      tester,
    ) async {
      final source = await ouvrir(
        tester,
        vus: {'plusA': _t(15), 'plusB': _t(15)},
      );
      source.pousser([
        _e(
          'a1',
          ajout: _t(1),
          modif: _t(19),
          modifiePar: 'plusA',
          texte: 'Sangles 2 po',
        ),
        ..._jeu().skip(1),
      ]);
      await tester.pumpAndSettle();
      expect(pastille('plusA'), '1');
    });

    testWidgets(
      'marquer comme obtenu : action envoyée, et pas de pastille pour moi sur mon propre geste',
      (tester) async {
        final source = await ouvrir(
          tester,
          vus: {'plusA': _t(15), 'plusB': _t(15)},
        );
        await tester.tap(_cle('groupe_plusA'));
        await tester.pumpAndSettle();
        await tester.tap(_cle('menu_entree_a1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marquer comme obtenu'));
        await tester.pumpAndSettle();
        expect(source.obtenues, ['a1:true']);
        expect(find.text('1 à acheter • 2 obtenus'), findsOneWidget);
        expect(pastille('plusA'), isNull);
      },
    );

    testWidgets('une demande obtenue peut être remise comme manquante', (
      tester,
    ) async {
      final source = await ouvrir(tester);
      await tester.tap(_cle('groupe_plusA'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_cle('menu_entree_a2'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_entree_a2'));
      await tester.pumpAndSettle();
      expect(find.text('Marquer comme obtenu'), findsNothing);
      await tester.tap(find.text('Remettre comme manquant'));
      await tester.pumpAndSettle();
      expect(source.obtenues, ['a2:false']);
    });

    testWidgets(
      'supprimer : confirmation d\'abord ; annuler ne supprime rien',
      (tester) async {
        final source = await ouvrir(tester);
        await tester.tap(_cle('groupe_plusB'));
        await tester.pumpAndSettle();
        await tester.tap(_cle('menu_entree_b1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Supprimer'));
        await tester.pumpAndSettle();
        expect(find.text('Supprimer cette demande ?'), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(source.supprimees, isEmpty);
        expect(find.text('Bâche'), findsOneWidget);

        await tester.tap(_cle('menu_entree_b1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Supprimer'));
        await tester.pumpAndSettle();
        await tester.tap(_cle('confirmer_action'));
        await tester.pumpAndSettle();
        expect(source.supprimees, ['b1']);
        expect(find.text('Bâche'), findsNothing);
        expect(find.text('Demande supprimée.'), findsOneWidget);
      },
    );

    testWidgets('échec d\'une action : message, pas de plantage', (
      tester,
    ) async {
      final source = await ouvrir(tester);
      source.echecObtenue = true;
      await tester.tap(_cle('groupe_plusB'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marquer comme obtenu'));
      await tester.pumpAndSettle();
      expect(find.text('Modification impossible. Réessayez.'), findsOneWidget);
    });

    testWidgets(
      'échec de l\'écriture « vu » (ex. règles pas déployées) : la liste s\'ouvre quand même',
      (tester) async {
        final source = await ouvrir(tester);
        source.echecMarquer = true;
        await tester.tap(_cle('groupe_plusB'));
        await tester.pumpAndSettle();
        expect(find.text('Bâche'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('aucune demande : message d\'invitation', (tester) async {
      await ouvrir(tester, donnees: const []);
      expect(_cle('general_vide'), findsOneWidget);
      expect(_cle('groupe_plusA'), findsNothing);
    });

    testWidgets('lecture impossible : message', (tester) async {
      AppSession.notifier.value = _emp('adminA', 'Admin A', EmployeeRole.admin);
      final source = FauxSource(_jeu())..erreurLecture = true;
      await tester.pumpWidget(
        MaterialApp(home: MaterielGeneralScreen(source: source)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Impossible de charger le matériel.'), findsOneWidget);
    });
  });

  // ===========================================================================
  group(
    'Admin → Chantiers : « Général » toujours premier, avec la pastille',
    () {
      const reels = [
        Chantier(
          id: 'c1',
          companyId: 'A',
          nom: 'Atelier',
          adresse: '1 rue des Pins',
        ),
        Chantier(
          id: 'c2',
          companyId: 'A',
          nom: 'Zèbre',
          adresse: '2 rue du Lac',
        ),
        Chantier(
          id: 'c3',
          companyId: 'A',
          nom: 'Ancien',
          adresse: '3 rue Vieille',
          archive: true,
        ),
      ];

      Future<FauxSource> ouvrir(
        WidgetTester tester, {
        List<Chantier> chantiers = reels,
        Map<String, DateTime>? vus,
      }) async {
        AppSession.notifier.value = _emp(
          'adminA',
          'Admin A',
          EmployeeRole.admin,
        );
        final source = FauxSource(_jeu(), vus);
        await tester.pumpWidget(
          MaterialApp(
            home: ChantiersGestionScreen(
              fluxChantiers: Stream.value(chantiers),
              sourceMateriel: source,
              sourceActivite: SourceActiviteFausse(),
              pageChantier: (c) => Scaffold(body: Text('PAGE ${c.id}')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return source;
      }

      testWidgets(
        'Général est au-dessus de tous les chantiers, même « Atelier » (A avant G)',
        (tester) async {
          await ouvrir(tester);
          final general = tester.getTopLeft(_cle('chantier_general')).dy;
          expect(general, lessThan(tester.getTopLeft(find.text('Atelier')).dy));
          expect(general, lessThan(tester.getTopLeft(find.text('Zèbre')).dy));
        },
      );

      testWidgets('visible en Actifs et en Tous ; pas dans Archivés', (
        tester,
      ) async {
        await ouvrir(tester);
        expect(_cle('chantier_general'), findsOneWidget);
        await tester.tap(find.text('Tous'));
        await tester.pumpAndSettle();
        expect(_cle('chantier_general'), findsOneWidget);
        await tester.tap(find.text('Archivés (1)'));
        await tester.pumpAndSettle();
        expect(_cle('chantier_general'), findsNothing);
      });

      testWidgets('visible même sans aucun chantier', (tester) async {
        await ouvrir(tester, chantiers: const []);
        expect(_cle('chantier_general'), findsOneWidget);
      });

      testWidgets(
        'la recherche le garde s\'il correspond (« remorque », « gén »), le cache sinon',
        (tester) async {
          await ouvrir(tester);
          await tester.enterText(_cle('filtre_chantiers'), 'remorque');
          await tester.pumpAndSettle();
          expect(_cle('chantier_general'), findsOneWidget);
          await tester.enterText(_cle('filtre_chantiers'), 'gen');
          await tester.pumpAndSettle();
          expect(_cle('chantier_general'), findsOneWidget);
          await tester.enterText(_cle('filtre_chantiers'), 'zèbre');
          await tester.pumpAndSettle();
          expect(_cle('chantier_general'), findsNothing);
          expect(find.text('Zèbre'), findsOneWidget);
        },
      );

      testWidgets(
        'pastille = total des changements non vus ; pas de pastille quand tout est vu',
        (tester) async {
          await ouvrir(tester);
          expect(
            find.descendant(
              of: _cle('pastille_general'),
              matching: find.text('4'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('tout vu : aucune pastille', (tester) async {
        await ouvrir(
          tester,
          vus: {'plusA': _t(15), 'plusB': _t(15), 'adminA': _t(15)},
        );
        expect(
          find.descendant(
            of: _cle('pastille_general'),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
      });

      testWidgets(
        'un toucher ouvre le matériel Général (pas la page d\'un chantier)',
        (tester) async {
          await ouvrir(tester);
          await tester.tap(_cle('chantier_general'));
          await tester.pumpAndSettle();
          expect(find.byType(MaterielGeneralScreen), findsOneWidget);
          expect(find.textContaining('PAGE'), findsNothing);
          expect(find.text('Bernard'), findsOneWidget);
        },
      );

      testWidgets(
        'la pastille disparaît quand on revient d\'avoir ouvert chaque groupe',
        (tester) async {
          await ouvrir(tester);
          await tester.tap(_cle('chantier_general'));
          await tester.pumpAndSettle();
          await tester.tap(_cle('groupe_plusA'));
          await tester.pumpAndSettle();
          await tester.tap(_cle('groupe_plusB'));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: _cle('pastille_general'),
              matching: find.byType(Text),
            ),
            findsNothing,
          );
        },
      );
    },
  );

  // ===========================================================================
  group('écran Admin : pastille sur « Chantiers »', () {
    Future<FauxSource> ouvrir(
      WidgetTester tester, {
      Employee? moi,
      Map<String, DateTime>? vus,
    }) async {
      AppSession.notifier.value =
          moi ?? _emp('adminA', 'Admin A', EmployeeRole.admin);
      final source = FauxSource(_jeu(), vus);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminHomeScreen(
              sourceMateriel: source,
              sourceActivite: SourceActiviteFausse(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('du matériel non vu : pastille sur la tuile Chantiers', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(
        find.descendant(
          of: _cle('pastille_chantiers'),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tout vu : pas de pastille', (tester) async {
      await ouvrir(tester, vus: {'plusA': _t(15), 'plusB': _t(15)});
      expect(
        find.descendant(
          of: _cle('pastille_chantiers'),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('autre rôle que admin : rien n\'est suivi', (tester) async {
      final source = await ouvrir(
        tester,
        moi: _emp('plusA', 'Plus A', EmployeeRole.plus),
      );
      expect(source.abonnementsEntrees, 0);
    });
  });

  // ===========================================================================
  group('recherche de chantier : Général reste premier', () {
    testWidgets(
      'même placé en dernier dans la liste, malgré l ordre alphabétique',
      (tester) async {
        const atelier = Chantier(
          id: 'c1',
          companyId: 'A',
          nom: 'Atelier',
          adresse: '',
        );
        const zebre = Chantier(
          id: 'c2',
          companyId: 'A',
          nom: 'Zèbre',
          adresse: '',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BoutonRechercheChantier(
                chantiers: const [
                  atelier,
                  zebre,
                  chantierGeneral,
                ], // Général en dernier
                onChoisi: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(_cle('bouton_recherche_chantier'));
        await tester.pumpAndSettle();
        final y = [
          for (final n in ['Général', 'Atelier', 'Zèbre'])
            tester.getTopLeft(find.widgetWithText(ListTile, n)).dy,
        ];
        expect(y[0], lessThan(y[1]));
        expect(y[1], lessThan(y[2]));
      },
    );

    testWidgets(
      'sans Général dans la liste (feuille de temps) : ordre alphabétique, aucun Général',
      (tester) async {
        const atelier = Chantier(
          id: 'c1',
          companyId: 'A',
          nom: 'Atelier',
          adresse: '',
        );
        const zebre = Chantier(
          id: 'c2',
          companyId: 'A',
          nom: 'Zèbre',
          adresse: '',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BoutonRechercheChantier(
                chantiers: const [zebre, atelier],
                onChoisi: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(_cle('bouton_recherche_chantier'));
        await tester.pumpAndSettle();
        expect(find.text('Général'), findsNothing);
        expect(
          tester.getTopLeft(find.widgetWithText(ListTile, 'Atelier')).dy,
          lessThan(
            tester.getTopLeft(find.widgetWithText(ListTile, 'Zèbre')).dy,
          ),
        );
      },
    );
  });

  // ===========================================================================
  group('Chantiers : choix « Général » (contremaître : sa liste seulement ; admin : filtres)', () {
    const chantiers = [
      Chantier(
        id: 'c1',
        companyId: 'A',
        nom: 'Atelier',
        adresse: '1 rue des Pins',
      ),
      Chantier(id: 'c2', companyId: 'A', nom: 'Zèbre', adresse: '2 rue du Lac'),
      Chantier(
        id: 'c3',
        companyId: 'A',
        nom: 'Ancien',
        adresse: '',
        archive: true,
      ),
    ];
    final ajouts = <(String, Map<String, dynamic>)>[];
    final modifs = <(String, String, Map<String, dynamic>)>[];
    bool echecAjout = false;

    // Les demandes du moment : plusA, Bernard (plusB), un admin ; une obtenue pour plusA
    // et une obtenue pour Bernard.
    List<MapEntry<String, Map<String, dynamic>>> donnees() => [
      MapEntry('m1', {
        'texte': 'Sangles',
        'quantite': '4',
        'complete': false,
        'ajoutePar': 'plusA',
        'ajouteParNom': 'Plus A',
        'dateAjout': Timestamp.fromDate(_t(3)),
      }),
      MapEntry('m2', {
        'texte': 'Bâche',
        'complete': false,
        'ajoutePar': 'plusB',
        'ajouteParNom': 'Bernard',
        'dateAjout': Timestamp.fromDate(_t(2)),
      }),
      MapEntry('m3', {
        'texte': 'Marteau',
        'complete': false,
        'ajoutePar': 'adminA',
        'ajouteParNom': 'Admin A',
        'dateAjout': Timestamp.fromDate(_t(1)),
      }),
      MapEntry('m4', {
        'texte': 'Vieux clous',
        'complete': true,
        'ajoutePar': 'plusA',
        'ajouteParNom': 'Plus A',
        'dateAjout': Timestamp.fromDate(_t(1)),
      }),
      MapEntry('m5', {
        'texte': 'Colle secrète',
        'complete': true,
        'ajoutePar': 'plusB',
        'ajouteParNom': 'Bernard',
        'dateAjout': Timestamp.fromDate(_t(1)),
      }),
    ];

    final contremaitre = _emp('plusA', 'Plus A', EmployeeRole.plus);
    final admin = _emp('adminA', 'Admin A', EmployeeRole.admin);

    Future<void> ouvrir(
      WidgetTester tester, {
      Employee? moi,
      List<MapEntry<String, Map<String, dynamic>>>? flux,
    }) async {
      ajouts.clear();
      modifs.clear();
      echecAjout = false;
      AppSession.notifier.value = moi ?? contremaitre;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChantierScreen(
              fluxChantiers: Stream.value(chantiers),
              fluxMateriel: Stream.value(flux ?? donnees()),
              // Les autres onglets ne touchent pas à Firebase ; Matériel est le vrai.
              contenuOnglet: (nom, id) =>
                  nom == 'materiel' ? null : Text('ONGLET $nom $id'),
              ajouterEntree: (collection, data) async {
                if (echecAjout) throw StateError('refusé');
                ajouts.add((collection, data));
              },
              modifierEntree: (collection, id, data) async {
                modifs.add((collection, id, data));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisirGeneral(WidgetTester tester) async {
      await tester.tap(find.byType(DropdownButtonFormField<Chantier>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Général').last);
      await tester.pumpAndSettle();
    }

    testWidgets(
      '« Général » est toujours le premier choix, devant « Atelier » (A avant G)',
      (tester) async {
        await ouvrir(tester);
        final items = tester
            .widget<DropdownButton<Chantier>>(
              find.byType(DropdownButton<Chantier>),
            )
            .items!;
        expect(items.map((i) => i.value!.nom), ['Général', 'Atelier', 'Zèbre']);
        expect(items.first.value, chantierGeneral);
        // Un chantier archivé n'est pas proposé.
        expect(items.any((i) => i.value!.id == 'c3'), isFalse);
      },
    );

    testWidgets('le premier chantier reste choisi au départ (pas Général)', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('ONGLET photos c1'), findsOneWidget);
      expect(_cle('aide_general'), findsNothing);
    });

    testWidgets(
      'choisir Général : seulement le matériel (ni photos, ni travaux, ni extras, ni calcul)',
      (tester) async {
        await ouvrir(tester);
        await choisirGeneral(tester);
        expect(find.byType(TabBar), findsNothing);
        for (final t in [
          'Photos',
          'Travaux à compléter',
          'Extras',
          'Documents',
          'Calcul',
        ]) {
          expect(find.text(t), findsNothing, reason: t);
        }
        expect(_cle('aide_general'), findsOneWidget);
        expect(find.text('Sangles'), findsOneWidget); // le matériel s'affiche
        expect(find.textContaining('ONGLET'), findsNothing);
      },
    );

    testWidgets('revenir à un chantier : les 6 onglets reviennent', (
      tester,
    ) async {
      await ouvrir(tester);
      await choisirGeneral(tester);
      await tester.tap(find.byType(DropdownButtonFormField<Chantier>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zèbre').last);
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('ONGLET photos c2'), findsOneWidget);
      expect(_cle('aide_general'), findsNothing);
    });

    testWidgets('la recherche « … » propose Général en premier et le choisit', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(_cle('bouton_recherche_chantier'));
      await tester.pumpAndSettle();
      Finder tuile(String n) => find.widgetWithText(ListTile, n);
      final y = [
        for (final n in ['Général', 'Atelier', 'Zèbre'])
          tester.getTopLeft(tuile(n)).dy,
      ];
      expect(y[0], lessThan(y[1]));
      expect(y[1], lessThan(y[2]));
      await tester.enterText(_cle('champ_recherche_chantier'), 'remorque');
      await tester.pumpAndSettle();
      expect(tuile('Atelier'), findsNothing);
      await tester.tap(tuile('Général'));
      await tester.pumpAndSettle();
      expect(_cle('aide_general'), findsOneWidget);
    });

    // -------------------------------------------------------------- contremaître
    group('contremaître : ne voit que SA liste', () {
      testWidgets(
        'seulement ses demandes, même si le serveur en envoyait d\'autres',
        (tester) async {
          await ouvrir(tester);
          await choisirGeneral(tester);
          expect(find.text('Sangles'), findsOneWidget);
          for (final autre in ['Bâche', 'Marteau']) {
            expect(find.text(autre), findsNothing, reason: autre);
          }
          // L'obtenue est dans l'historique, pas dans la liste.
          expect(find.text('Vieux clous'), findsNothing);
        },
      );

      testWidgets('aucun filtre, aucun nom d\'un autre, aucun « Par … »', (
        tester,
      ) async {
        await ouvrir(tester);
        await choisirGeneral(tester);
        for (final cle in [
          'filtre_moi',
          'filtre_tous',
          'filtre_plusB',
          'filtre_adminA',
        ]) {
          expect(_cle(cle), findsNothing, reason: cle);
        }
        expect(find.text('Bernard'), findsNothing);
        expect(find.text('Admin A'), findsNothing);
        expect(find.textContaining('Par '), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
      });

      testWidgets(
        'le même court texte d\'aide que pour un admin (rien sur la confidentialité)',
        (tester) async {
          await ouvrir(tester);
          await choisirGeneral(tester);
          final texte = (tester.widget<Text>(_cle('aide_general'))).data!;
          expect(
            texte,
            'Général : le matériel dont vous avez besoin pour la remorque ou sans chantier précis.',
          );
        },
      );

      testWidgets('historique : seulement le sien', (tester) async {
        await ouvrir(tester);
        await choisirGeneral(tester);
        await tester.tap(find.text('Voir l\'historique'));
        await tester.pumpAndSettle();
        expect(find.text('Vieux clous'), findsOneWidget);
        expect(find.text('Colle secrète'), findsNothing); // obtenue de Bernard
      });

      testWidgets(
        'rien de sa part : message sans « Tous » (il n\'a pas ce bouton)',
        (tester) async {
          await ouvrir(tester, flux: donnees().sublist(1, 3));
          await choisirGeneral(tester);
          expect(
            find.text('Aucun matériel actif dans votre liste Général.'),
            findsOneWidget,
          );
          expect(find.textContaining('Tous'), findsNothing);
        },
      );

      testWidgets(
        'un admin a SA liste privée aussi : le contremaître ne voit pas la sienne',
        (tester) async {
          await ouvrir(tester);
          await choisirGeneral(tester);
          expect(find.text('Marteau'), findsNothing);
        },
      );
    });

    // ------------------------------------------------------------------- admin
    group('admin : mes ajouts, tous, ou une personne', () {
      testWidgets('par défaut, seulement mes ajouts ; même texte d\'aide', (
        tester,
      ) async {
        await ouvrir(tester, moi: admin);
        await choisirGeneral(tester);
        expect(find.text('Marteau'), findsOneWidget);
        expect(find.text('Sangles'), findsNothing);
        expect(find.text('Bâche'), findsNothing);
        expect(
          (tester.widget<Text>(_cle('aide_general'))).data,
          'Général : le matériel dont vous avez besoin pour la remorque ou sans chantier précis.',
        );
      });

      testWidgets(
        'filtres : Mes ajouts, Tous, puis une puce par autre personne',
        (tester) async {
          await ouvrir(tester, moi: admin);
          await choisirGeneral(tester);
          expect(_cle('filtre_moi'), findsOneWidget);
          expect(_cle('filtre_tous'), findsOneWidget);
          expect(_cle('filtre_plusA'), findsOneWidget);
          expect(_cle('filtre_plusB'), findsOneWidget);
          // Pas de puce en double pour moi.
          expect(_cle('filtre_adminA'), findsNothing);
          expect(find.text('Bernard'), findsOneWidget);
          expect(find.text('Plus A'), findsOneWidget);
        },
      );

      testWidgets(
        '« Tous » montre tout le monde, avec « Par … » sur chaque demande',
        (tester) async {
          await ouvrir(tester, moi: admin);
          await choisirGeneral(tester);
          await tester.tap(_cle('filtre_tous'));
          await tester.pumpAndSettle();
          for (final t in ['Sangles', 'Bâche', 'Marteau']) {
            expect(find.text(t), findsOneWidget, reason: t);
          }
          expect(find.text('Par Bernard'), findsOneWidget);
          expect(find.text('Par Plus A'), findsOneWidget);
          expect(find.text('Par Admin A'), findsOneWidget);
        },
      );

      testWidgets('une puce montre seulement cette personne', (tester) async {
        await ouvrir(tester, moi: admin);
        await choisirGeneral(tester);
        await tester.tap(_cle('filtre_plusB'));
        await tester.pumpAndSettle();
        expect(find.text('Bâche'), findsOneWidget);
        expect(find.text('Sangles'), findsNothing);
        expect(find.text('Marteau'), findsNothing);
        // Le nom est déjà dans la puce : pas de « Par … » redondant.
        expect(find.text('Par Bernard'), findsNothing);
        await tester.tap(_cle('filtre_moi'));
        await tester.pumpAndSettle();
        expect(find.text('Marteau'), findsOneWidget);
        expect(find.text('Bâche'), findsNothing);
      });

      testWidgets('l\'historique suit le même filtre', (tester) async {
        await ouvrir(tester, moi: admin);
        await choisirGeneral(tester);
        await tester.tap(find.text('Voir l\'historique'));
        await tester.pumpAndSettle();
        expect(
          find.text('Aucun historique dans Général.'),
          findsOneWidget,
        ); // rien d'obtenu pour moi
        await tester.tap(_cle('filtre_plusA'));
        await tester.pumpAndSettle();
        expect(find.text('Vieux clous'), findsOneWidget);
        expect(find.text('Colle secrète'), findsNothing);
      });

      testWidgets('rien de ma part : message qui indique « Tous »', (
        tester,
      ) async {
        await ouvrir(tester, moi: admin, flux: donnees().sublist(0, 2));
        await choisirGeneral(tester);
        expect(
          find.textContaining('Aucun matériel de votre part dans Général'),
          findsOneWidget,
        );
        expect(_cle('filtre_tous'), findsOneWidget);
      });

      testWidgets('liste Général vide pour tout le monde', (tester) async {
        await ouvrir(tester, moi: admin, flux: const []);
        await choisirGeneral(tester);
        await tester.tap(_cle('filtre_tous'));
        await tester.pumpAndSettle();
        expect(find.text('Aucun matériel actif dans Général.'), findsOneWidget);
      });
    });

    // ------------------------------------------------------------ écritures
    testWidgets(
      'ajouter du matériel Général : l\'entrée porte MON id et MON nom',
      (tester) async {
        await ouvrir(tester);
        await choisirGeneral(tester);
        await tester.enterText(find.byType(TextField).first, 'Rallonge 50 pi');
        await tester.enterText(find.byType(TextField).at(1), '2');
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();
        expect(ajouts.length, 1);
        final (collection, data) = ajouts.single;
        expect(collection, 'chantier_materiel');
        expect(data['chantierId'], '_general');
        expect(data['companyId'], 'A');
        expect(data['texte'], 'Rallonge 50 pi');
        expect(data['quantite'], '2');
        expect(data['ajoutePar'], 'plusA');
        expect(data['ajouteParNom'], 'Plus A');
        expect(data['complete'], false);
        // Le champ est vidé.
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '',
        );
      },
    );

    testWidgets('un admin qui ajoute signe de son nom', (tester) async {
      await ouvrir(tester, moi: admin);
      await choisirGeneral(tester);
      await tester.enterText(find.byType(TextField).first, 'Perceuse');
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(ajouts.single.$2['ajoutePar'], 'adminA');
      expect(ajouts.single.$2['ajouteParNom'], 'Admin A');
      expect(ajouts.single.$2.containsKey('quantite'), isFalse);
    });

    testWidgets(
      'échec de l\'ajout : message, le texte reste, on peut réessayer',
      (tester) async {
        await ouvrir(tester);
        await choisirGeneral(tester);
        echecAjout = true;
        await tester.enterText(find.byType(TextField).first, 'Perceuse');
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();
        expect(find.textContaining('n\'a pas pu être ajoutée'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Perceuse',
        );
        echecAjout = false;
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();
        expect(ajouts.length, 1);
      },
    );

    testWidgets('marquer obtenu dans Général : signé (modifiePar, dateModif)', (
      tester,
    ) async {
      await ouvrir(tester);
      await choisirGeneral(tester);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marquer comme obtenu'));
      await tester.pumpAndSettle();
      final (collection, id, data) = modifs.single;
      expect(collection, 'chantier_materiel');
      expect(id, 'm1');
      expect(data['complete'], true);
      expect(data['modifiePar'], 'plusA');
      expect(data.containsKey('dateModif'), isTrue);
    });

    testWidgets('modifier une demande Général : signé aussi', (tester) async {
      await ouvrir(tester);
      await choisirGeneral(tester);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Sangles'),
        'Sangles 2 po',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final (_, id, data) = modifs.single;
      expect(id, 'm1');
      expect(data['texte'], 'Sangles 2 po');
      expect(data['modifiePar'], 'plusA');
      expect(data.containsKey('dateModif'), isTrue);
    });

    testWidgets(
      'matériel d\'un VRAI chantier : pas de filtre ni de signature ; l\'auteur sert au fil Activité',
      (tester) async {
        await ouvrir(tester);
        await tester.tap(find.widgetWithText(Tab, 'Matériel'));
        await tester.pumpAndSettle();
        expect(_cle('filtre_tous'), findsNothing);
        expect(_cle('filtre_moi'), findsNothing);
        // Toutes les demandes du flux s'affichent (pas de filtre par personne).
        expect(find.text('Sangles'), findsOneWidget);
        expect(find.text('Bâche'), findsOneWidget);
        expect(find.text('Par Bernard'), findsNothing);

        await tester.enterText(find.byType(TextField).first, 'Clous');
        await tester.tap(find.text('Ajouter'));
        await tester.pumpAndSettle();
        final data = ajouts.single.$2;
        expect(data['chantierId'], 'c1');
        // L'auteur est maintenant noté (fil « Activité » de l'admin), sans changer la liste.
        expect(data.containsKey('ajoutePar'), isTrue);
        expect(data.containsKey('ajouteParNom'), isTrue);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marquer comme obtenu'));
        await tester.pumpAndSettle();
        expect(modifs.single.$3.keys.toSet(), {'complete', 'dateComplete'});
      },
    );

    testWidgets('liste vide d\'un vrai chantier : textes inchangés', (
      tester,
    ) async {
      await ouvrir(tester, flux: const []);
      await tester.tap(find.widgetWithText(Tab, 'Matériel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aucune entrée active pour ce chantier.'),
        findsOneWidget,
      );
    });
  });
}
