// Fil « Activité » de l'admin : phrases, nouveautés (pastilles), lecture réunie et écran.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/activite.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/activite_screen.dart';
import 'package:construction_app/screens/admin/admin_home_screen.dart';
import 'package:construction_app/services/activite_source.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:construction_app/widgets/actualiser.dart';
import 'package:construction_app/widgets/pastille.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/faux_activite.dart';
import 'doubles/faux_materiel.dart';

Employee _admin() => Employee(
  id: 'adminA',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Zoé Admin',
  role: EmployeeRole.admin,
  estProprietaire: true,
);

Timestamp _ts(int a, int m, int j, int h, int min) =>
    Timestamp.fromDate(DateTime(a, m, j, h, min));

DateTime _d(int m, int j, int h, int min) => DateTime(2026, m, j, h, min);

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('Phrases du fil', () {
    test('les exemples de l\'admin, mot pour mot', () {
      expect(
        phraseActivite(
          Activite(
            id: 'h1',
            type: TypeActivite.heures,
            date: _d(7, 10, 6, 24),
            acteurId: 'f',
            acteurNom: 'Félix',
            sujetId: 'f',
            sujetNom: 'Félix',
            modification: true,
          ),
        ),
        'Changements apportés aux heures par Félix',
      );
      expect(
        phraseActivite(
          Activite(
            id: 'p1',
            type: TypeActivite.photo,
            date: _d(7, 9, 17, 10),
            acteurNom: 'Jeremy',
            chantierId: 'c1',
            chantierNom: 'Brouillard',
          ),
        ),
        'Nouvelle photo sur projet Brouillard par Jeremy',
      );
      expect(
        phraseActivite(
          Activite(
            id: 'm1',
            type: TypeActivite.materiel,
            date: _d(7, 9, 17, 1),
            acteurNom: 'Jeremy',
            chantierId: 'c1',
            chantierNom: 'Brouillard',
          ),
        ),
        'Nouveau matériel manquant sur projet Brouillard par Jeremy',
      );
      expect(
        phraseActivite(
          Activite(
            id: 'h2',
            type: TypeActivite.heures,
            date: _d(7, 6, 15, 30),
            acteurId: 'j',
            acteurNom: 'Jeff',
            sujetId: 'j',
            sujetNom: 'Jeff',
          ),
        ),
        'Heures entrées par Jeff',
      );
    });

    test('heures corrigées par un admin : on dit de qui', () {
      final a = Activite(
        id: 'h',
        type: TypeActivite.heures,
        date: _d(10, 12, 8, 0),
        acteurId: 'admin',
        acteurNom: 'Zoé',
        sujetId: 'felix',
        sujetNom: 'Félix Mercier',
        modification: true,
      );
      expect(phraseActivite(a), 'Heures de Félix Mercier modifiées par Zoé');
    });

    test('chaque sorte de changement', () {
      Activite a(
        TypeActivite t, {
        String chantier = '',
        String nom = 'Marie',
      }) => Activite(
        id: 'x',
        type: t,
        date: _d(1, 1, 1, 1),
        acteurNom: nom,
        chantierId: chantier.isEmpty ? '' : 'c',
        chantierNom: chantier,
      );
      expect(
        phraseActivite(a(TypeActivite.travaux, chantier: 'Garage')),
        'Nouveau travail à faire sur projet Garage par Marie',
      );
      expect(
        phraseActivite(a(TypeActivite.extra, chantier: 'Garage')),
        'Nouvel extra sur projet Garage par Marie',
      );
      expect(
        phraseActivite(a(TypeActivite.document, chantier: 'Garage')),
        'Nouveau document sur projet Garage par Marie',
      );
      expect(
        phraseActivite(a(TypeActivite.achat)),
        'Matériel transféré à la Liste d\'achats par Marie',
      );
    });

    test('Général, chantier inconnu, acteur inconnu (anciennes versions)', () {
      expect(
        phraseActivite(
          Activite(
            id: 'g',
            type: TypeActivite.materiel,
            date: DateTime.utc(2026),
            acteurNom: 'Paul',
            chantierId: '_general',
          ),
        ),
        'Nouveau matériel manquant sur Général par Paul',
      );
      expect(
        phraseActivite(
          Activite(id: 'i', type: TypeActivite.photo, date: DateTime.utc(2026)),
        ),
        'Nouvelle photo par un employé',
      );
      expect(
        phraseActivite(
          Activite(
            id: 'i',
            type: TypeActivite.photo,
            date: DateTime.utc(2026),
            acteurNom: 'Paul',
            chantierId: 'disparu',
          ),
        ),
        'Nouvelle photo par Paul',
      );
    });

    test(
      'heures sans information (ancienne feuille) : changement par l\'employé',
      () {
        final a = FabriqueActivite.heures('emp1_2026-10-12', {
          'employeeId': 'emp1',
          'employeeNom': 'Félix',
          'lundiDate': '2026-10-12',
          'dateModification': _ts(2026, 10, 12, 8, 0),
        })!;
        expect(a.modification, isTrue);
        expect(a.acteurNom, 'Félix');
        expect(phraseActivite(a), 'Changements apportés aux heures par Félix');
        expect(a.detail, 'Félix • semaine du 12/10');
      },
    );

    test(
      'date : heure sans zéro, puis année/mois/jour (comme les exemples)',
      () {
        expect(dateActivite(_d(7, 10, 6, 24)), '6:24 2026/07/10');
        expect(dateActivite(_d(7, 9, 17, 10)), '17:10 2026/07/09');
        expect(dateActivite(_d(1, 2, 0, 5)), '0:05 2026/01/02');
      },
    );
  });

  group('Fabrique : un document devient un changement', () {
    test('photo', () {
      final a = FabriqueActivite.photo('p1', {
        'chantierId': 'c1',
        'ajoutePar': 'jer',
        'ajouteParNom': 'Jeremy',
        'dateAjout': _ts(2026, 7, 9, 17, 10),
      })!;
      expect(a.id, 'photo:p1');
      expect(a.type, TypeActivite.photo);
      expect(a.acteurNom, 'Jeremy');
      expect(a.chantierId, 'c1');
      expect(a.date, _d(7, 9, 17, 10));
    });

    test('matériel avec quantité, travaux sans', () {
      final m = FabriqueActivite.entree(TypeActivite.materiel, 'm1', {
        'chantierId': 'c1',
        'texte': 'Clous 3 po',
        'quantite': '12 boîtes',
        'dateAjout': _ts(2026, 7, 9, 17, 1),
      })!;
      expect(m.detail, 'Clous 3 po (12 boîtes)');
      expect(m.id, 'materiel:m1');
      final t = FabriqueActivite.entree(TypeActivite.travaux, 't1', {
        'chantierId': 'c1',
        'texte': 'Coffrage',
        'dateAjout': _ts(2026, 7, 9, 17, 2),
      })!;
      expect(t.detail, 'Coffrage');
      expect(t.id, 'travaux:t1');
    });

    test('extra, document, achat', () {
      expect(
        FabriqueActivite.extra('e', {
          'description': 'Cloison',
          'ajouteParNom': 'Luc',
          'ajoutePar': 'l',
          'chantierId': 'c1',
          'dateAjout': _ts(2026, 1, 1, 1, 1),
        })!.detail,
        'Cloison',
      );
      expect(
        FabriqueActivite.document('d', {
          'nom': 'Plan.pdf',
          'ajoutePar': 'a',
          'ajouteParNom': 'Zoé',
          'chantierId': 'c1',
          'dateAjout': _ts(2026, 1, 1, 1, 1),
        })!.acteurNom,
        'Zoé',
      );
      final achat = FabriqueActivite.achat('x', {
        'texte': 'Sangles',
        'transfereParId': 'adm',
        'transfereParNom': 'Zoé',
        'dateAjout': _ts(2026, 1, 1, 1, 1),
      })!;
      expect(achat.acteurId, 'adm');
      expect(achat.chantierId, '');
    });

    test('sans date (écriture en cours) : rien', () {
      expect(FabriqueActivite.photo('p', {'chantierId': 'c'}), isNull);
      expect(FabriqueActivite.heures('h', {'employeeId': 'e'}), isNull);
      expect(
        FabriqueActivite.entree(TypeActivite.materiel, 'm', {
          'dateAjout': null,
        }),
        isNull,
      );
    });

    test('heures : première saisie, puis modification', () {
      final creation = _ts(2026, 10, 12, 8, 0);
      final premiere = FabriqueActivite.heures('h', {
        'employeeId': 'e',
        'employeeNom': 'Jeff',
        'creeLe': creation,
        'dateModification': creation,
        'modifieParId': 'e',
        'modifieParNom': 'Jeff',
      })!;
      expect(premiere.modification, isFalse);
      final ensuite = FabriqueActivite.heures('h', {
        'employeeId': 'e',
        'employeeNom': 'Jeff',
        'creeLe': creation,
        'dateModification': _ts(2026, 10, 12, 9, 30),
        'modifieParId': 'admin',
        'modifieParNom': 'Zoé',
      })!;
      expect(ensuite.modification, isTrue);
      expect(ensuite.acteurNom, 'Zoé');
      expect(ensuite.sujetNom, 'Jeff');
    });

    test('valeurs illisibles : pas de plantage', () {
      final a = FabriqueActivite.photo('p', {
        'dateAjout': _ts(2026, 1, 1, 1, 1),
        'ajouteParNom': 42,
        'chantierId': null,
      })!;
      expect(a.acteurNom, '');
      expect(a.chantierId, '');
    });
  });

  group('Nouveautés', () {
    final vu = _d(10, 12, 12, 0);
    Activite a(String id, DateTime date, {String acteur = 'felix'}) => Activite(
      id: id,
      type: TypeActivite.photo,
      date: date,
      acteurId: acteur,
    );

    test('après la dernière visite et pas de moi', () {
      expect(estNouvelle(a('1', _d(10, 12, 12, 1)), vu, 'adminA'), isTrue);
      expect(estNouvelle(a('2', _d(10, 12, 11, 59)), vu, 'adminA'), isFalse);
      expect(
        estNouvelle(a('3', vu), vu, 'adminA'),
        isFalse,
        reason: 'pile à la visite : déjà vu',
      );
    });

    test(
      'mes propres gestes ne s\'allument jamais ; un acteur inconnu, oui',
      () {
        expect(
          estNouvelle(
            a('1', _d(10, 12, 13, 0), acteur: 'adminA'),
            vu,
            'adminA',
          ),
          isFalse,
        );
        expect(
          estNouvelle(a('2', _d(10, 12, 13, 0), acteur: ''), vu, 'adminA'),
          isTrue,
        );
      },
    );

    test('jamais visité : rien n\'est nouveau (on ne signale pas tout l\'historique)', () {
      expect(estNouvelle(a('1', _d(10, 12, 13, 0)), null, 'adminA'), isFalse);
    });

    test('le nombre', () {
      final liste = [
        a('1', _d(10, 12, 13, 0)),
        a('2', _d(10, 12, 14, 0)),
        a('3', _d(10, 12, 9, 0)),
        a('4', _d(10, 12, 15, 0), acteur: 'adminA'),
      ];
      expect(nombreNouvelles(liste, vu, 'adminA'), 2);
      expect(nombreNouvelles(const [], vu, 'adminA'), 0);
    });

    test('ordre : le plus récent d\'abord, sans doublon, limité', () {
      final liste = ordonnerActivites([
        a('a', _d(1, 1, 1, 1)),
        a('b', _d(3, 3, 3, 3)),
        a('a', _d(1, 1, 1, 1)),
        a('c', _d(2, 2, 2, 2)),
      ]);
      expect(liste.map((x) => x.id), ['b', 'c', 'a']);
      expect(ordonnerActivites(liste, max: 2).map((x) => x.id), ['b', 'c']);
    });
  });

  group('Réunir les lectures', () {
    Activite p(String id, int h, {String chantier = ''}) => Activite(
      id: id,
      type: TypeActivite.photo,
      date: _d(10, 12, h, 0),
      chantierId: chantier,
    );

    test('une liste unique, triée, avec le nom des chantiers', () async {
      final a = StreamController<List<Activite>>();
      final b = StreamController<List<Activite>>();
      final noms = StreamController<Map<String, String>>();
      final recu = <List<Activite>>[];
      final abonnement = fusionnerActivites([
        a.stream,
        b.stream,
      ], nomsChantiers: noms.stream).listen(recu.add);
      a.add([p('a1', 8, chantier: 'c1')]);
      b.add([p('b1', 9)]);
      await Future<void>.delayed(Duration.zero);
      expect(recu, isEmpty, reason: 'on attend les noms avant d\'afficher');
      noms.add({'c1': 'Brouillard'});
      await Future<void>.delayed(Duration.zero);
      expect(recu.last.map((x) => x.id), ['b1', 'a1']);
      expect(recu.last.last.chantierNom, 'Brouillard');
      expect(recu.last.first.chantierNom, '');
      // Un nouveau changement arrive.
      a.add([p('a1', 8, chantier: 'c1'), p('a2', 10)]);
      await Future<void>.delayed(Duration.zero);
      expect(recu.last.map((x) => x.id), ['a2', 'b1', 'a1']);
      await abonnement.cancel();
      await a.close();
      await b.close();
      await noms.close();
    });

    test('une lecture refusée n\'empêche pas d\'afficher les autres', () async {
      final bonne = Stream.value([p('x', 9)]);
      final refusee = Stream<List<Activite>>.error(
        StateError('permission-denied'),
      );
      final liste = await fusionnerActivites([bonne, refusee]).first;
      expect(liste.map((x) => x.id), ['x']);
    });

    test(
      'les noms de chantiers refusés : le fil s\'affiche quand même',
      () async {
        final liste = await fusionnerActivites(
          [
            Stream.value([p('x', 9, chantier: 'c1')]),
          ],
          nomsChantiers: Stream<Map<String, String>>.error(StateError('refus')),
        ).first;
        expect(liste.single.chantierNom, '');
      },
    );

    test('plafond du nombre d\'éléments', () async {
      final liste = await fusionnerActivites([
        Stream.value([for (var i = 0; i < 10; i++) p('p$i', i)]),
      ], max: 4).first;
      expect(liste, hasLength(4));
      expect(liste.first.id, 'p9');
    });

    test('annuler l\'écoute annule toutes les lectures', () async {
      var annulees = 0;
      Stream<List<Activite>> source() =>
          StreamController<List<Activite>>(onCancel: () => annulees++).stream;
      final abonnement = fusionnerActivites(
        [source(), source()],
        nomsChantiers: StreamController<Map<String, String>>(
          onCancel: () => annulees++,
        ).stream,
      ).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await abonnement.cancel();
      expect(annulees, 3);
    });

    test('aucune lecture : liste vide', () async {
      expect(await fusionnerActivites(const []).first, isEmpty);
    });
  });

  group('Écran Activité', () {
    final jeff = Activite(
      id: 'heures:j',
      type: TypeActivite.heures,
      date: _d(10, 12, 15, 30),
      acteurId: 'jeff',
      acteurNom: 'Jeff',
      sujetId: 'jeff',
      sujetNom: 'Jeff',
      detail: 'Jeff • semaine du 12/10',
    );
    final photo = Activite(
      id: 'photo:p',
      type: TypeActivite.photo,
      date: _d(10, 12, 17, 10),
      acteurId: 'jer',
      acteurNom: 'Jeremy',
      chantierId: 'c1',
      chantierNom: 'Brouillard',
    );
    final materiel = Activite(
      id: 'materiel:m',
      type: TypeActivite.materiel,
      date: _d(10, 12, 17, 1),
      acteurId: 'jer',
      acteurNom: 'Jeremy',
      chantierId: 'c1',
      chantierNom: 'Brouillard',
      detail: 'Clous 3 po',
    );
    final mienne = Activite(
      id: 'document:d',
      type: TypeActivite.document,
      date: _d(10, 12, 18, 0),
      acteurId: 'adminA',
      acteurNom: 'Zoé Admin',
      chantierId: 'c1',
      chantierNom: 'Brouillard',
      detail: 'Plan.pdf',
    );

    Future<SourceActiviteFausse> ouvrir(
      WidgetTester tester, {
      List<Activite>? activites,
      DateTime? vus,
      bool admin = true,
    }) async {
      if (admin) AppSession.notifier.value = _admin();
      final source = SourceActiviteFausse(
        activites: ordonnerActivites(
          activites ?? [jeff, photo, materiel, mienne],
        ),
        vus: vus,
      );
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActiviteScreen(source: source),
                    ),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('réservé aux admins', (tester) async {
      await ouvrir(tester, admin: false);
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
    });

    testWidgets(
      'les changements, du plus récent au plus ancien, avec leur date',
      (tester) async {
        await ouvrir(tester, vus: _d(10, 12, 12, 0));
        expect(
          find.text('Nouveau document sur projet Brouillard par Zoé Admin'),
          findsOneWidget,
        );
        expect(
          find.text('Nouvelle photo sur projet Brouillard par Jeremy'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Nouveau matériel manquant sur projet Brouillard par Jeremy',
          ),
          findsOneWidget,
        );
        expect(find.text('Heures entrées par Jeff'), findsOneWidget);
        expect(find.textContaining('17:10 2026/10/12'), findsOneWidget);
        expect(find.textContaining('15:30 2026/10/12'), findsOneWidget);
        // Le détail est sous la phrase.
        expect(find.textContaining('Clous 3 po'), findsOneWidget);
        // Ordre : document (18 h), photo (17 h 10), matériel (17 h 01), heures (15 h 30).
        final ys = [
          for (final id in ['document:d', 'photo:p', 'materiel:m', 'heures:j'])
            tester.getTopLeft(find.byKey(ValueKey('activite_$id'))).dy,
        ];
        expect(ys, [...ys]..sort());
      },
    );

    testWidgets(
      'une pastille à côté de chaque nouveauté, jamais pour mes gestes ni l\'ancien',
      (tester) async {
        await ouvrir(tester, vus: _d(10, 12, 16, 0));
        // Nouveaux depuis 16 h et pas de moi : la photo (17 h 10) et le matériel (17 h 01).
        expect(
          find.byKey(const ValueKey('activite_point_photo:p')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('activite_point_materiel:m')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('activite_point_heures:j')),
          findsNothing,
          reason: 'avant la visite',
        );
        expect(
          find.byKey(const ValueKey('activite_point_document:d')),
          findsNothing,
          reason: 'c\'est mon geste',
        );
      },
    );

    testWidgets(
      'première visite : rien n\'est nouveau, et on enregistre la visite',
      (tester) async {
        final source = await ouvrir(tester, vus: null);
        expect(find.byType(PointNouveau), findsNothing);
        await tester.pump();
        expect(source.marques, isNotEmpty);
        expect(source.marques.first.jusqua, _d(10, 12, 18, 0));
        expect(source.marques.first.employeId, 'adminA');
        expect(source.marques.first.companyId, 'A');
      },
    );

    testWidgets(
      'quitter la page marque tout comme vu (jusqu\'au plus récent)',
      (tester) async {
        final source = await ouvrir(tester, vus: _d(10, 12, 16, 0));
        expect(find.byType(PointNouveau), findsNWidgets(2));
        expect(
          source.marques,
          isEmpty,
          reason: 'pendant la visite, les pastilles restent',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(source.marques, hasLength(1));
        expect(source.marques.single.jusqua, _d(10, 12, 18, 0));
      },
    );

    testWidgets(
      'rien de plus récent que la dernière visite : rien n\'est réenregistré',
      (tester) async {
        final source = await ouvrir(tester, vus: _d(10, 12, 18, 0));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(source.marques, isEmpty);
      },
    );

    testWidgets(
      '« Tout marquer comme vu » éteint les pastilles tout de suite',
      (tester) async {
        final source = await ouvrir(tester, vus: _d(10, 12, 16, 0));
        expect(find.byType(PointNouveau), findsNWidgets(2));
        await tester.tap(find.byKey(const ValueKey('activite_tout_vu')));
        await tester.pumpAndSettle();
        expect(find.byType(PointNouveau), findsNothing);
        expect(source.marques.single.jusqua, _d(10, 12, 18, 0));
        // En quittant : déjà enregistré, pas de second enregistrement.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(source.marques, hasLength(1));
      },
    );

    testWidgets('filtres par sorte de changement, avec leur pastille', (
      tester,
    ) async {
      await ouvrir(tester, vus: _d(10, 12, 16, 0));
      expect(
        find.byKey(const ValueKey('activite_pastille_photo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activite_pastille_materiel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('activite_pastille_heures')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('activite_filtre_photo')));
      await tester.pumpAndSettle();
      expect(
        find.text('Nouvelle photo sur projet Brouillard par Jeremy'),
        findsOneWidget,
      );
      expect(find.text('Heures entrées par Jeff'), findsNothing);
      expect(
        find.text('Nouveau matériel manquant sur projet Brouillard par Jeremy'),
        findsNothing,
      );
      // Retoucher le filtre : retour à tout.
      await tester.tap(find.byKey(const ValueKey('activite_filtre_photo')));
      await tester.pumpAndSettle();
      expect(find.text('Heures entrées par Jeff'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activite_filtre_heures')));
      await tester.pumpAndSettle();
      expect(find.text('Heures entrées par Jeff'), findsOneWidget);
      expect(
        find.text('Nouvelle photo sur projet Brouillard par Jeremy'),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('activite_filtre_tout')));
      await tester.pumpAndSettle();
      expect(
        find.text('Nouvelle photo sur projet Brouillard par Jeremy'),
        findsOneWidget,
      );
    });

    testWidgets('rien à montrer : message', (tester) async {
      await ouvrir(tester, activites: const [], vus: _d(10, 12, 12, 0));
      expect(find.byKey(const ValueKey('activite_vide')), findsOneWidget);
    });

    testWidgets('un filtre sans résultat : message', (tester) async {
      await ouvrir(tester, vus: _d(10, 12, 12, 0));
      // Écran large : toutes les pastilles de filtre sont visibles.
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activite_filtre_extra')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activite_vide')), findsOneWidget);
    });

    testWidgets('tirer vers le bas relance la lecture', (tester) async {
      final source = await ouvrir(tester, vus: _d(10, 12, 12, 0));
      expect(source.ecoutes, 1);
      await tester.fling(
        find.byType(ListView).last,
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(source.ecoutes, 2);
      expect(find.text('Heures entrées par Jeff'), findsOneWidget);
    });
  });

  group('Admin : tuile Activité', () {
    Future<SourceActiviteFausse> ouvrir(
      WidgetTester tester, {
      DateTime? vus,
      bool admin = true,
      List<Activite>? activites,
    }) async {
      if (admin) AppSession.notifier.value = _admin();
      final source = SourceActiviteFausse(
        activites:
            activites ??
            [
              Activite(
                id: 'photo:1',
                type: TypeActivite.photo,
                date: _d(10, 12, 17, 0),
                acteurId: 'jer',
                acteurNom: 'Jeremy',
              ),
              Activite(
                id: 'photo:2',
                type: TypeActivite.photo,
                date: _d(10, 12, 18, 0),
                acteurId: 'jer',
                acteurNom: 'Jeremy',
              ),
              Activite(
                id: 'photo:3',
                type: TypeActivite.photo,
                date: _d(10, 12, 9, 0),
                acteurId: 'jer',
                acteurNom: 'Jeremy',
              ),
            ],
        vus: vus,
      );
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminHomeScreen(
              sourceMateriel: SourceMaterielGeneralVide(),
              sourceActivite: source,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('la tuile est en tête, avec le nombre de nouveautés', (
      tester,
    ) async {
      await ouvrir(tester, vus: _d(10, 12, 12, 0));
      expect(find.text('Activité'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pastille_activite')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Activité')).dy,
        lessThan(tester.getTopLeft(find.text('Heures employés')).dy),
      );
    });

    testWidgets('tout vu : pas de pastille', (tester) async {
      await ouvrir(tester, vus: _d(10, 12, 19, 0));
      expect(find.text('Activité'), findsOneWidget);
      expect(find.byType(Semantics).evaluate().isNotEmpty, isTrue);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('jamais visité : pas de pastille', (tester) async {
      await ouvrir(tester, vus: null);
      expect(find.text('3'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets(
      'pas un admin (aucune session) : pas de pastille, rien n\'est lu',
      (tester) async {
        final source = await ouvrir(
          tester,
          admin: false,
          vus: _d(10, 12, 12, 0),
        );
        expect(find.text('2'), findsNothing);
        expect(source.ecoutes, 0);
      },
    );

    testWidgets('toucher la tuile ouvre le fil', (tester) async {
      await ouvrir(tester, vus: _d(10, 12, 12, 0));
      await tester.tap(find.text('Activité'));
      await tester.pumpAndSettle();
      expect(find.byType(ActiviteScreen), findsOneWidget);
      expect(find.byType(PointNouveau), findsNWidgets(2));
    });
  });
}
