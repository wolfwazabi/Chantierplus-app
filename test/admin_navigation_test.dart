// Section Admin « Chantiers » : un seul endroit pour tout ce qui touche un chantier
// (liste, résumé, photos, documents, modification, archivage, export).
import 'dart:async';

import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/admin_home_screen.dart';
import 'package:construction_app/screens/admin/chantier_admin_actions.dart';
import 'package:construction_app/screens/admin/chantiers_gestion_screen.dart';
import 'package:construction_app/screens/admin/dossier_chantier_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/faux_activite.dart';
import 'doubles/faux_materiel.dart';

const _chalet = Chantier(
  id: 'c1',
  companyId: 'A',
  nom: 'Chalet Nord',
  adresse: '1 rue des Pins',
);
const _garage = Chantier(
  id: 'c2',
  companyId: 'A',
  nom: 'Garage Tremblay',
  adresse: '12 chemin du Lac',
);
const _vieux = Chantier(
  id: 'c3',
  companyId: 'A',
  nom: 'Ancien duplex',
  adresse: '5 boul. Laval',
  archive: true,
);

Employee _employe(EmployeeRole role) => Employee(
  id: 'e1',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Alex',
  role: role,
);

Finder _cle(String k) => find.byKey(ValueKey(k));

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('écran Admin', () {
    testWidgets('une seule tuile « Chantiers » remplace les trois anciennes', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminHomeScreen())),
      );
      expect(find.text('Chantiers'), findsOneWidget);
      expect(find.text('Gérer les chantiers'), findsNothing);
      expect(find.text('Dossiers de chantier'), findsNothing);
      expect(find.text('Documents des chantiers'), findsNothing);
      // Le reste de l'écran est inchangé.
      expect(find.text('Heures employés'), findsOneWidget);
      expect(find.text('Gestion des employés'), findsOneWidget);
      expect(
        find.textContaining('photos, documents, heures et export'),
        findsOneWidget,
      );
    });

    testWidgets('la tuile ouvre la liste des chantiers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdminHomeScreen())),
      );
      await tester.tap(find.text('Chantiers'));
      await tester.pumpAndSettle();
      expect(find.byType(ChantiersGestionScreen), findsOneWidget);
    });
  });

  group('liste des chantiers', () {
    Future<void> ouvrir(
      WidgetTester tester, {
      List<Chantier> chantiers = const [_garage, _chalet, _vieux],
      Employee? employe,
      Widget Function(Chantier)? page,
    }) async {
      AppSession.notifier.value = employe ?? _employe(EmployeeRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          home: ChantiersGestionScreen(
            fluxChantiers: Stream.value(chantiers),
            sourceMateriel: SourceMaterielGeneralVide(),
            sourceActivite: SourceActiviteFausse(),
            pageChantier: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('réservée aux admins', (tester) async {
      await ouvrir(tester, employe: _employe(EmployeeRole.plus));
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
      expect(_cle('chantier_ajouter'), findsNothing);
    });

    testWidgets('actifs par défaut, triés par nom ; archivés à part', (
      tester,
    ) async {
      await ouvrir(tester);
      expect(find.text('Chalet Nord'), findsOneWidget);
      expect(find.text('Garage Tremblay'), findsOneWidget);
      expect(find.text('Ancien duplex'), findsNothing);
      // Tri : Chalet avant Garage.
      expect(
        tester.getTopLeft(find.text('Chalet Nord')).dy,
        lessThan(tester.getTopLeft(find.text('Garage Tremblay')).dy),
      );
      expect(find.text('Actifs (2)'), findsOneWidget);
      expect(find.text('Archivés (1)'), findsOneWidget);
    });

    testWidgets('filtres : archivés, tous, actifs', (tester) async {
      await ouvrir(tester);
      await tester.tap(find.text('Archivés (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Ancien duplex'), findsOneWidget);
      expect(find.text('Chalet Nord'), findsNothing);
      expect(find.textContaining('Archivé'), findsWidgets);

      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Ancien duplex'), findsOneWidget);
      expect(find.text('Chalet Nord'), findsOneWidget);

      await tester.tap(find.text('Actifs (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Ancien duplex'), findsNothing);
    });

    testWidgets('recherche par nom ou adresse', (tester) async {
      await ouvrir(tester);
      await tester.enterText(_cle('filtre_chantiers'), 'lac');
      await tester.pumpAndSettle();
      expect(find.text('Garage Tremblay'), findsOneWidget);
      expect(find.text('Chalet Nord'), findsNothing);
      await tester.enterText(_cle('filtre_chantiers'), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun chantier ne correspond.'), findsOneWidget);
    });

    testWidgets('aucun chantier : invitation à en ajouter', (tester) async {
      await ouvrir(tester, chantiers: const []);
      expect(find.textContaining('Aucun chantier'), findsOneWidget);
      expect(_cle('chantier_ajouter'), findsOneWidget);
    });

    testWidgets('un toucher ouvre la page de CE chantier', (tester) async {
      await ouvrir(
        tester,
        page: (c) =>
            Scaffold(appBar: AppBar(), body: Text('PAGE ${c.id} ${c.nom}')),
      );
      await tester.tap(find.text('Garage Tremblay'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE c2 Garage Tremblay'), findsOneWidget);
      // Retour à la liste.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Garage Tremblay'), findsOneWidget);
      expect(find.textContaining('PAGE'), findsNothing);
    });

    testWidgets('un chantier archivé s\'ouvre aussi (dossier complet)', (
      tester,
    ) async {
      await ouvrir(tester, page: (c) => Scaffold(body: Text('PAGE ${c.id}')));
      await tester.tap(find.text('Archivés (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ancien duplex'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE c3'), findsOneWidget);
    });

    testWidgets('menu : modifier, et archiver (actif) ou restaurer (archivé)', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(_cle('menu_c1'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Archiver'), findsOneWidget);
      expect(find.text('Restaurer'), findsNothing);
      await tester.tapAt(const Offset(5, 5)); // ferme le menu
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archivés (1)'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_c3'));
      await tester.pumpAndSettle();
      expect(find.text('Restaurer'), findsOneWidget);
      expect(find.text('Archiver'), findsNothing);
    });

    testWidgets('« Modifier » ouvre le formulaire avec le nom et l\'adresse', (
      tester,
    ) async {
      await ouvrir(tester);
      await tester.tap(_cle('menu_c1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le chantier'), findsOneWidget);
      expect(
        tester.widget<TextField>(_cle('chantier_nom')).controller!.text,
        'Chalet Nord',
      );
      expect(
        tester.widget<TextField>(_cle('chantier_adresse')).controller!.text,
        '1 rue des Pins',
      );
    });

    testWidgets('« Ajouter » ouvre un formulaire vide', (tester) async {
      await ouvrir(tester);
      await tester.tap(_cle('chantier_ajouter'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau chantier'), findsOneWidget);
      expect(
        tester.widget<TextField>(_cle('chantier_nom')).controller!.text,
        '',
      );
    });
  });

  group('page d\'un chantier', () {
    final controleur = StreamController<Chantier?>.broadcast();
    tearDownAll(controleur.close);

    Future<void> ouvrir(
      WidgetTester tester, {
      Chantier chantier = _chalet,
      Employee? employe,
      Stream<Chantier?>? flux,
    }) async {
      AppSession.notifier.value = employe ?? _employe(EmployeeRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          home: DossierChantierScreen(
            chantier: chantier,
            fluxChantier: flux ?? Stream.value(chantier),
            contenuResume: (_, c) =>
                Text('RESUME ${c.id}', key: const ValueKey('r')),
            contenuPhotos: (_, c) =>
                Text('PHOTOS ${c.id}', key: const ValueKey('p')),
            contenuDocuments: (_, c) =>
                Text('DOCS ${c.id}', key: const ValueKey('d')),
            contenuOnglet: (onglet, _, c) =>
                Text('${onglet.toUpperCase()} ${c.id}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'six onglets : Résumé, Photos, Extras, Travaux, Matériel, Documents (on y gère les données)',
      (tester) async {
        await ouvrir(tester);
        expect(find.text('Chalet Nord'), findsOneWidget); // titre
        for (final t in [
          'Résumé',
          'Photos',
          'Extras',
          'Travaux',
          'Matériel',
          'Documents',
        ]) {
          expect(find.widgetWithText(Tab, t), findsOneWidget, reason: t);
        }
        expect(find.text('RESUME c1'), findsOneWidget);
        for (final (onglet, contenu) in [
          ('Photos', 'PHOTOS c1'),
          ('Extras', 'EXTRAS c1'),
          ('Travaux', 'TRAVAUX c1'),
          ('Matériel', 'MATERIEL c1'),
          ('Documents', 'DOCS c1'),
        ]) {
          await tester.tap(find.widgetWithText(Tab, onglet));
          await tester.pumpAndSettle();
          expect(find.text(contenu), findsOneWidget, reason: onglet);
        }
      },
    );

    testWidgets('menu : modifier, archiver (chantier actif)', (tester) async {
      await ouvrir(tester);
      await tester.tap(_cle('dossier_menu'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier le chantier'), findsOneWidget);
      expect(find.text('Archiver le chantier'), findsOneWidget);
      expect(find.text('Restaurer le chantier'), findsNothing);
    });

    testWidgets('chantier archivé : « Restaurer le chantier »', (tester) async {
      await ouvrir(tester, chantier: _vieux);
      await tester.tap(_cle('dossier_menu'));
      await tester.pumpAndSettle();
      expect(find.text('Restaurer le chantier'), findsOneWidget);
      expect(find.text('Archiver le chantier'), findsNothing);
    });

    testWidgets('suit le chantier en direct : nouveau nom, puis archivé', (
      tester,
    ) async {
      await ouvrir(tester, flux: controleur.stream);
      // Sans valeur du flux : le chantier reçu s'affiche.
      expect(find.text('Chalet Nord'), findsOneWidget);
      controleur.add(
        const Chantier(
          id: 'c1',
          companyId: 'A',
          nom: 'Chalet Nord (agrandi)',
          adresse: '1 rue des Pins',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chalet Nord (agrandi)'), findsOneWidget);
      controleur.add(
        const Chantier(
          id: 'c1',
          companyId: 'A',
          nom: 'Chalet Nord (agrandi)',
          adresse: '',
          archive: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_cle('dossier_menu'));
      await tester.pumpAndSettle();
      expect(find.text('Restaurer le chantier'), findsOneWidget);
    });

    testWidgets('réservée aux admins', (tester) async {
      await ouvrir(tester, employe: _employe(EmployeeRole.plus));
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('suppression définitive d\'un chantier archivé', () {
    final appels = <Map<String, dynamic>>[];
    Object? echec;
    setUp(() {
      appels.clear();
      echec = null;
      appelerSuppressionChantier = (donnees) async {
        appels.add(donnees);
        if (echec != null) throw echec!;
        return {'ok': true};
      };
    });

    Future<void> ouvrirListe(WidgetTester tester) async {
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          home: ChantiersGestionScreen(
            fluxChantiers: Stream.value(const [_garage, _chalet, _vieux]),
            sourceMateriel: SourceMaterielGeneralVide(),
            sourceActivite: SourceActiviteFausse(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ouvrirDialogue(WidgetTester tester) async {
      await ouvrirListe(tester);
      await tester.tap(find.text('Archivés (1)'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_c3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer définitivement'));
      await tester.pumpAndSettle();
    }

    FilledButton bouton(WidgetTester tester) =>
        tester.widget<FilledButton>(_cle('suppression_confirmer'));

    test('le nom tapé : espaces, majuscules et accents ignorés', () {
      expect(memeNomChantier('  chalet   NORD ', 'Chalet Nord'), isTrue);
      expect(
        memeNomChantier('Ecole Saint-Jerome', 'École Saint-Jérôme'),
        isTrue,
      );
      expect(memeNomChantier('Chalet Sud', 'Chalet Nord'), isFalse);
      expect(memeNomChantier('   ', ''), isFalse);
    });

    testWidgets('proposée seulement pour un chantier archivé', (tester) async {
      await ouvrirListe(tester);
      await tester.tap(_cle('menu_c1'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer définitivement'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivés (1)'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('menu_c3'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer définitivement'), findsOneWidget);
    });

    testWidgets('le nom doit être tapé ; puis le serveur supprime', (
      tester,
    ) async {
      await ouvrirDialogue(tester);
      expect(
        find.text('Supprimer « Ancien duplex » définitivement ?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Les heures des employés restent'),
        findsOneWidget,
      );
      expect(bouton(tester).onPressed, isNull);
      await tester.enterText(_cle('suppression_nom'), 'Ancien triplex');
      await tester.pump();
      expect(bouton(tester).onPressed, isNull);
      await tester.enterText(_cle('suppression_nom'), ' ancien DUPLEX');
      await tester.pump();
      expect(bouton(tester).onPressed, isNotNull);
      await tester.tap(_cle('suppression_confirmer'));
      await tester.pumpAndSettle();
      expect(appels, [
        {'chantierId': 'c3', 'confirmationNom': ' ancien DUPLEX'},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('« Ancien duplex » est supprimé définitivement.'),
        findsOneWidget,
      );
    });

    testWidgets('refus du serveur : le message reste dans la boîte', (
      tester,
    ) async {
      echec = Exception('réseau');
      await ouvrirDialogue(tester);
      await tester.enterText(_cle('suppression_nom'), 'Ancien duplex');
      await tester.pump();
      await tester.tap(_cle('suppression_confirmer'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_cle('suppression_erreur'), findsOneWidget);
      // Annuler : rien d'autre.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(appels, hasLength(1));
    });

    testWidgets(
      'page du chantier archivé : « Supprimer définitivement » et « Exporter d\'abord »',
      (tester) async {
        AppSession.notifier.value = _employe(EmployeeRole.admin);
        await tester.pumpWidget(
          MaterialApp(
            home: DossierChantierScreen(
              chantier: _vieux,
              fluxChantier: Stream.value(_vieux),
              contenuResume: (_, c) => Text('RESUME ${c.id}'),
              contenuPhotos: (_, c) => Text('PHOTOS ${c.id}'),
              contenuDocuments: (_, c) => Text('DOCS ${c.id}'),
              contenuOnglet: (onglet, _, c) =>
                  Text('${onglet.toUpperCase()} ${c.id}'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_cle('dossier_menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Supprimer définitivement'));
        await tester.pumpAndSettle();
        expect(_cle('suppression_exporter'), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        // Chantier actif : pas proposé.
        await tester.pumpWidget(
          MaterialApp(
            home: DossierChantierScreen(
              chantier: _chalet,
              fluxChantier: Stream.value(_chalet),
              contenuResume: (_, c) => Text('RESUME ${c.id}'),
              contenuPhotos: (_, c) => Text('PHOTOS ${c.id}'),
              contenuDocuments: (_, c) => Text('DOCS ${c.id}'),
              contenuOnglet: (onglet, _, c) =>
                  Text('${onglet.toUpperCase()} ${c.id}'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_cle('dossier_menu'));
        await tester.pumpAndSettle();
        expect(find.text('Supprimer définitivement'), findsNothing);
      },
    );
  });
}
