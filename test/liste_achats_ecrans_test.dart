// Appui long sur le matériel Général (marquer « non lu », transférer à la Liste
// d'achats), page Admin → Liste d'achats et sa tuile. Firestore est remplacé par des
// doubles de test (voir doubles/faux_materiel.dart).
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/liste_achats.dart';
import 'package:construction_app/models/materiel_general.dart';
import 'package:construction_app/screens/admin/admin_home_screen.dart';
import 'package:construction_app/screens/admin/liste_achats_screen.dart';
import 'package:construction_app/screens/admin/materiel_general_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/faux_materiel.dart';

Finder _cle(String k) => find.byKey(ValueKey(k));
Finder _entete(String auteur) => find
    .descendant(of: _cle('groupe_$auteur'), matching: find.byType(ListTile))
    .first;
Employee _emp(String id, String nom, EmployeeRole role) =>
    Employee(id: id, companyId: 'A', companyNom: 'Alpha', nom: nom, role: role);

void main() {
  tearDown(() => AppSession.notifier.value = null);

  // ===========================================================================
  group('Admin → Général : appui long', () {
    final admin = _emp('adminA', 'Admin A', EmployeeRole.admin);
    // Tout est déjà vu : la pastille ne s'allume que par ce que l'admin marque.
    final vus = {'plusA': tTest(15), 'plusB': tTest(15), 'adminA': tTest(15)};

    Future<FauxSource> ouvrir(
      WidgetTester tester, {
      List<EntreeMateriel>? donnees,
      Map<String, DateTime>? vusInitiaux,
      Set<String>? nonLus,
    }) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppSession.notifier.value = admin;
      final source = FauxSource(donnees ?? jeuTest(), vusInitiaux ?? vus, nonLus);
      await tester.pumpWidget(MaterialApp(home: MaterielGeneralScreen(source: source)));
      await tester.pumpAndSettle();
      return source;
    }

    String? pastille(String auteur) {
      final textes = find.descendant(of: _cle('pastille_groupe_$auteur'), matching: find.byType(Text));
      return textes.evaluate().isEmpty ? null : (textes.evaluate().single.widget as Text).data;
    }

    Future<void> ouvrirGroupe(WidgetTester tester, String auteur) async {
      await tester.tap(_entete(auteur));
      await tester.pumpAndSettle();
    }

    testWidgets('appui long sur une demande : « non lu » et « Liste d\'achats »', (tester) async {
      await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      expect(find.text('Marquer comme non lu'), findsOneWidget);
      expect(find.text('Transférer à la Liste d\'achats'), findsOneWidget);
      expect(_cle('action_non_lu'), findsOneWidget);
      expect(_cle('action_transferer'), findsOneWidget);
    });

    testWidgets('« Marquer comme non lu » : la pastille de la personne s\'allume', (tester) async {
      final source = await ouvrir(tester);
      expect(pastille('plusB'), isNull);
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_non_lu'));
      await tester.pumpAndSettle();
      expect(source.nonLusPoses, [['b1']]);
      expect(pastille('plusB'), '1');
      expect(pastille('plusA'), isNull);
      expect(_cle('nouveau_b1'), findsOneWidget);
      expect(find.text('Marqué comme non lu.'), findsOneWidget);
    });

    testWidgets('la pastille de la tuile Général suit aussi (toutes personnes confondues)', (tester) async {
      final source = await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_non_lu'));
      await tester.pumpAndSettle();
      final total = grouperParAuteur(source.donnees, moiId: 'adminA', vus: source.visitesActuelles.vus, nonLus: source.visitesActuelles.nonLus);
      expect(totalNonVus(total), 1);
    });

    testWidgets('rouvrir le groupe le lit : le drapeau tombe, la pastille s\'éteint, « Nouveau » reste pendant la visite', (tester) async {
      final source = await ouvrir(tester, nonLus: {'b1'});
      expect(pastille('plusB'), '1');
      await ouvrirGroupe(tester, 'plusB');
      expect(source.marques, ['plusB']);
      expect(source.leves.single, {'b1'});
      expect(pastille('plusB'), isNull);
      expect(source.visitesActuelles.nonLus, isEmpty);
      expect(_cle('nouveau_b1'), findsOneWidget);
    });

    testWidgets('un drapeau sur une demande qui n\'existe plus est nettoyé à la prochaine ouverture', (tester) async {
      final source = await ouvrir(tester, nonLus: {'b1', 'disparue'});
      await ouvrirGroupe(tester, 'plusB');
      expect(source.leves.single, {'b1', 'disparue'});
      expect(source.visitesActuelles.nonLus, isEmpty);
    });

    testWidgets('appui long sur une personne : marque ses demandes à acheter « non lu »', (tester) async {
      final source = await ouvrir(tester);
      await tester.longPress(_entete('plusA'));
      await tester.pumpAndSettle();
      expect(_cle('action_groupe_non_lu'), findsOneWidget);
      await tester.tap(_cle('action_groupe_non_lu'));
      await tester.pumpAndSettle();
      // a3 et a1 sont à acheter ; a2 est déjà obtenue.
      expect(source.nonLusPoses.single.toSet(), {'a1', 'a3'});
      expect(pastille('plusA'), '2');
      expect(pastille('plusB'), isNull);
      expect(find.text('2 demandes marquées comme non lues.'), findsOneWidget);
    });

    testWidgets('appui long sur une personne sans rien à acheter : message, aucune écriture', (tester) async {
      final source = await ouvrir(tester, donnees: [entreeTest('o1', auteur: 'plusB', nom: 'Bernard', complete: true)]);
      await tester.longPress(_entete('plusB'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_groupe_non_lu'));
      await tester.pumpAndSettle();
      expect(source.nonLusPoses, isEmpty);
      expect(find.text('Rien à marquer : aucune demande à acheter.'), findsOneWidget);
    });

    testWidgets('échec : message clair, rien ne s\'allume', (tester) async {
      final source = await ouvrir(tester);
      source.echecNonLu = true;
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_non_lu'));
      await tester.pumpAndSettle();
      expect(find.text('Impossible de marquer comme non lu. Réessayez.'), findsOneWidget);
      expect(pastille('plusB'), isNull);
    });

    testWidgets('« Transférer à la Liste d\'achats » : la demande RESTE, marquée, signée par l\'admin', (tester) async {
      final source = await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusB');
      expect(find.textContaining('Demandé le'), findsOneWidget);
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_transferer'));
      await tester.pumpAndSettle();
      expect(source.transferees, ['b1']);
      expect(source.signaturesTransfert, ['adminA']);
      // Elle reste dans Général, avec la mention.
      expect(find.text('Bâche'), findsOneWidget);
      expect(find.text('Dans la Liste d\'achats (transféré par Admin A)'), findsOneWidget);
      expect(find.text('« Bâche » transféré à la Liste d\'achats.'), findsOneWidget);
      // Elle n'est plus « à acheter » : le groupe le dit.
      expect(find.text('1 dans la Liste d\'achats'), findsOneWidget);
      expect(find.text('Rien à acheter'), findsNothing);
      // Les autres n'ont pas bougé.
      expect(source.donnees.where((e) => e.transfere).map((e) => e.id), ['b1']);
      // Un geste de l'admin lui-même n'allume pas sa pastille.
      expect(pastille('plusB'), isNull);
    });

    testWidgets('le total « à acheter » ne compte plus la demande transférée', (tester) async {
      await ouvrir(tester);
      expect(find.text('4 à acheter • 3 personnes'), findsOneWidget);
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_transferer'));
      await tester.pumpAndSettle();
      expect(find.text('3 à acheter • 3 personnes'), findsOneWidget);
    });

    testWidgets('une demande déjà transférée n\'offre plus le transfert ni « obtenu » (ça se fait dans la Liste d\'achats)', (tester) async {
      await ouvrir(
        tester,
        donnees: [
          entreeTest('t1', auteur: 'plusB', nom: 'Bernard', texte: 'Bâche', transfere: true, transfereParNom: 'Admin A'),
        ],
      );
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_t1'));
      await tester.pumpAndSettle();
      expect(_cle('action_non_lu'), findsOneWidget);
      expect(_cle('action_transferer'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_entree_t1'));
      await tester.pumpAndSettle();
      expect(find.text('Transférer à la Liste d\'achats'), findsNothing);
      expect(find.text('Marquer comme obtenu'), findsNothing);
      expect(find.text('Marquer comme non lu'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('une demande obtenue n\'offre pas le transfert', (tester) async {
      await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusA');
      await tester.ensureVisible(_cle('entree_a2'));
      await tester.longPress(_cle('entree_a2'));
      await tester.pumpAndSettle();
      expect(_cle('action_non_lu'), findsOneWidget);
      expect(_cle('action_transferer'), findsNothing);
    });

    testWidgets('transfert impossible : message, la demande reste', (tester) async {
      final source = await ouvrir(tester);
      source.echecTransfert = true;
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('action_transferer'));
      await tester.pumpAndSettle();
      expect(find.text('Transfert impossible. Réessayez.'), findsOneWidget);
      expect(find.text('Bâche'), findsOneWidget);
      expect(find.textContaining('Dans la Liste d\'achats'), findsNothing);
    });

    testWidgets('fermer la feuille sans choisir : rien ne se passe', (tester) async {
      final source = await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusB');
      await tester.longPress(_cle('entree_b1'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(source.nonLusPoses, isEmpty);
      expect(source.transferees, isEmpty);
      expect(find.text('Bâche'), findsOneWidget);
    });

    testWidgets('le menu ⋮ de la demande offre aussi « non lu » et « Liste d\'achats »', (tester) async {
      final source = await ouvrir(tester);
      await ouvrirGroupe(tester, 'plusB');
      await tester.tap(_cle('menu_entree_b1'));
      await tester.pumpAndSettle();
      expect(find.text('Marquer comme non lu'), findsOneWidget);
      expect(find.text('Transférer à la Liste d\'achats'), findsOneWidget);
      await tester.tap(find.text('Transférer à la Liste d\'achats'));
      await tester.pumpAndSettle();
      expect(source.transferees, ['b1']);
    });
  });

  // ===========================================================================
  group('Admin → Liste d\'achats', () {
    ArticleAchat a(
      String id, {
      String par = 'plusA',
      String nom = 'Plus A',
      bool complete = false,
      int jour = 1,
      String quantite = '',
    }) => ArticleAchat(
      id: id,
      texte: 'Article $id',
      quantite: quantite,
      demandeParId: par,
      demandeParNom: nom,
      transfereParNom: 'Admin A',
      complete: complete,
      dateAjout: tTest(jour),
      dateComplete: complete ? tTest(jour + 2) : null,
    );

    Future<FauxAchats> ouvrir(
      WidgetTester tester, {
      List<ArticleAchat>? articles,
      Employee? moi,
    }) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppSession.notifier.value = moi ?? _emp('adminA', 'Admin A', EmployeeRole.admin);
      final source = FauxAchats(
        articles ??
            [
              a('1', par: 'plusB', nom: 'Bernard', jour: 2, quantite: '2 rouleaux'),
              a('2', par: 'plusA', nom: 'Plus A', jour: 1),
              a('3', par: 'plusA', nom: 'Plus A', jour: 5),
              a('4', par: 'plusA', nom: 'Plus A', complete: true, jour: 1),
            ],
      );
      await tester.pumpWidget(MaterialApp(home: ListeAchatsScreen(source: source)));
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('réservée aux admins : un contremaître n\'y accède pas et rien n\'est lu', (tester) async {
      final source = await ouvrir(tester, moi: _emp('plusA', 'Plus A', EmployeeRole.plus));
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
      expect(source.abonnements, 0);
    });

    testWidgets('liste vide : explique comment y transférer du matériel', (tester) async {
      await ouvrir(tester, articles: const []);
      expect(_cle('achats_vide'), findsOneWidget);
      expect((tester.widget<Text>(_cle('achats_vide'))).data, contains('appuyez longtemps'));
    });

    testWidgets('séparée par équipe (ordre alphabétique), total à acheter, récent d\'abord', (tester) async {
      await ouvrir(tester);
      expect(_cle('equipe_plusA'), findsOneWidget);
      expect(_cle('equipe_plusB'), findsOneWidget);
      // Total : 2 de Plus A + 1 de Bernard.
      expect((tester.widget<Text>(_cle('achats_total'))).data, '3 à acheter');
      // Bernard avant Plus A.
      expect(tester.getTopLeft(_cle('equipe_plusB')).dy, lessThan(tester.getTopLeft(_cle('equipe_plusA')).dy));
      // Dans Plus A : l'article 3 (récent) avant le 2.
      expect(tester.getTopLeft(_cle('article_3')).dy, lessThan(tester.getTopLeft(_cle('article_2')).dy));
      expect(find.textContaining('Quantité : 2 rouleaux'), findsOneWidget);
      expect(find.textContaining('Transféré par Admin A'), findsWidgets);
    });

    testWidgets('les articles achetés sont à part, repliés', (tester) async {
      await ouvrir(tester);
      expect(find.text('Achetés (1)'), findsOneWidget);
      expect(_cle('article_4'), findsNothing);
      await tester.ensureVisible(_cle('achetes'));
      await tester.tap(find.text('Achetés (1)'));
      await tester.pumpAndSettle();
      expect(_cle('article_4'), findsOneWidget);
      expect(find.textContaining('Demandé par Plus A'), findsOneWidget);
    });

    testWidgets('marquer acheté : l\'article passe dans « Achetés » et le total baisse', (tester) async {
      final source = await ouvrir(tester);
      await tester.tap(_cle('menu_article_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marquer comme acheté'));
      await tester.pumpAndSettle();
      expect(source.achetes, ['1:true']);
      expect(source.employes, ['adminA']); // la demande d'origine est signée par cet admin
      expect((tester.widget<Text>(_cle('achats_total'))).data, '2 à acheter');
      expect(find.text('Achetés (2)'), findsOneWidget);
      expect(_cle('equipe_plusB'), findsNothing); // plus rien à acheter pour Bernard
    });

    testWidgets('remettre à acheter un article acheté', (tester) async {
      final source = await ouvrir(tester);
      await tester.ensureVisible(_cle('achetes'));
      await tester.tap(find.text('Achetés (1)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_cle('menu_article_4'));
      await tester.tap(_cle('menu_article_4'));
      await tester.pumpAndSettle();
      expect(find.text('Marquer comme acheté'), findsNothing);
      await tester.tap(find.text('Remettre à acheter'));
      await tester.pumpAndSettle();
      expect(source.achetes, ['4:false']);
      expect((tester.widget<Text>(_cle('achats_total'))).data, '4 à acheter');
      expect(find.text('Achetés (1)'), findsNothing);
    });

    testWidgets('retirer : confirmation d\'abord ; annuler ne retire rien', (tester) async {
      final source = await ouvrir(tester);
      await tester.tap(_cle('menu_article_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la liste'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer cet article ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(source.retires, isEmpty);
      expect(_cle('article_1'), findsOneWidget);

      await tester.tap(_cle('menu_article_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer de la liste'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('confirmer_action'));
      await tester.pumpAndSettle();
      expect(source.retires, ['1']);
      expect(_cle('article_1'), findsNothing);
      expect(find.text('Article retiré.'), findsOneWidget);
    });

    testWidgets('échec d\'une modification : message, pas de plantage', (tester) async {
      final source = await ouvrir(tester);
      source.echecAchete = true;
      await tester.tap(_cle('menu_article_1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marquer comme acheté'));
      await tester.pumpAndSettle();
      expect(find.text('Modification impossible. Réessayez.'), findsOneWidget);
    });

    testWidgets('lecture impossible : message', (tester) async {
      AppSession.notifier.value = _emp('adminA', 'Admin A', EmployeeRole.admin);
      final source = FauxAchats(const [])..erreurLecture = true;
      await tester.pumpWidget(MaterialApp(home: ListeAchatsScreen(source: source)));
      await tester.pumpAndSettle();
      expect(find.text('Impossible de charger la liste.'), findsOneWidget);
    });
  });

  // ===========================================================================
  group('écran Admin : tuile « Liste d\'achats »', () {
    testWidgets('présente, avec « Chantiers » toujours là, et ouvre la page', (tester) async {
      AppSession.notifier.value = _emp('adminA', 'Admin A', EmployeeRole.admin);
      final achats = FauxAchats([
        ArticleAchat(id: 'x', texte: 'Sangles', demandeParId: 'plusA', demandeParNom: 'Plus A', dateAjout: tTest(1)),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminHomeScreen(sourceMateriel: SourceMaterielGeneralVide(), sourceAchats: achats),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chantiers'), findsOneWidget);
      expect(find.text('Liste d\'achats'), findsOneWidget);
      expect(find.text('Matériel à acheter, transféré depuis Général'), findsOneWidget);
      // « Liste d'achats » vient juste après « Chantiers ».
      expect(
        tester.getTopLeft(find.text('Chantiers')).dy,
        lessThan(tester.getTopLeft(find.text('Liste d\'achats')).dy),
      );
      await tester.tap(find.text('Liste d\'achats'));
      await tester.pumpAndSettle();
      expect(find.byType(ListeAchatsScreen), findsOneWidget);
      expect(find.text('Article x'), findsNothing);
      expect(find.text('Sangles'), findsOneWidget);
    });
  });
}
