// Correction des heures d'un employé par un admin (tableau admin) : modèle de saisie,
// formulaire d'une journée et appel à corrigerFeuilleTemps (le serveur calcule les heures).
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/correction_feuille.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/regles_paie.dart';
import 'package:construction_app/screens/admin/employe_historique_screen.dart';
import 'package:construction_app/screens/admin/modifier_jour_sheet.dart';
import 'package:construction_app/screens/admin/semaine_detail_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _admin() => Employee(
  id: 'admin1',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Zoé Proprio',
  role: EmployeeRole.admin,
  estProprietaire: true,
);

const _chantiers = [
  Chantier(id: 'c1', companyId: 'A', nom: 'Chalet Nord', adresse: '1 rue A'),
  Chantier(id: 'c2', companyId: 'A', nom: 'Garage Sud', adresse: '2 rue B'),
  Chantier(
    id: 'c3',
    companyId: 'A',
    nom: 'Vieux Hangar',
    adresse: '3 rue C',
    archive: true,
  ),
];

Map<String, dynamic> _jourLundi() => {
  'nomJour': 'Lundi',
  'chantierId': 'c1',
  'chantierNom': 'Chalet Nord',
  'estAucun': false,
  'heureDebutMinutes': 420,
  'heureFinMinutes': 900,
  'pauseMatin': true,
  'diner': true,
  'heuresTravaillees': 7.75,
  'tempsVoyagementMinutes': null,
  'voyagementPayeHeures': 0,
  'verrouille': true,
};

List<Map<String, dynamic>> _jours() => [
  _jourLundi(),
  {
    'nomJour': 'Mardi',
    'chantierId': 'c2',
    'chantierNom': 'Garage Sud',
    'estAucun': false,
    'heureDebutMinutes': 480,
    'heureFinMinutes': 960,
    'pauseMatin': false,
    'diner': true,
    'heuresTravaillees': 8.0,
    'tempsVoyagementMinutes': 90,
    'voyagementPayeHeures': 0.5,
    'verrouille': true,
  },
  // Mercredi : rien de saisi.
  {'nomJour': 'Mercredi', 'estAucun': false},
  {'nomJour': 'Jeudi', 'estAucun': true, 'chantierNom': 'Jour non travaillé'},
];

Map<String, dynamic> _fiche() => {
  'employeeId': 'emp1',
  'employeeNom': 'Félix Mercier',
  'companyId': 'A',
  'lundiDate': '2026-10-12',
  'jours': _jours(),
  'totalHeures': 15.75,
  'totalVoyagementPaye': 0.5,
};

class _Appels {
  final List<MapEntry<String, Map<String, dynamic>>> faits = [];
  Object? erreur;
  Map<String, dynamic> reponse = {'totalHeures': 16.5};

  Future<Map<String, dynamic>> appeler(
    String nom,
    Map<String, dynamic> donnees,
  ) async {
    faits.add(MapEntry(nom, donnees));
    final e = erreur;
    if (e != null) throw e;
    return reponse;
  }
}

/// Outils : les roues d'heures sont remplacées par des valeurs prévues d'avance.
OutilsEditionJour _outils(
  _Appels appels, {
  int? debut,
  int? fin,
  int? voyagement,
}) => OutilsEditionJour(
  appelerFonction: appels.appeler,
  chargerChantiers: () async => _chantiers,
  choisirHeure: (context, titre, initial) async =>
      titre == 'Heure de début' ? debut : fin,
  choisirDuree: (context, titre, initial) async => voyagement,
);

Future<void> _ouvrirSemaine(
  WidgetTester tester,
  _Appels appels, {
  OutilsEditionJour? outils,
  List<Map<String, dynamic>>? fiches,
}) async {
  AppSession.notifier.value = _admin();
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SemaineDetailScreen(
        lundiDate: '2026-10-12',
        flux: Stream.value([
          for (final f in fiches ?? [_fiche()]) MapEntry('emp1_2026-10-12', f),
        ]),
        outils: outils ?? _outils(appels),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toucherJour(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('jour_emp1_2026-10-12_$index')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    AppSession.notifier.value = null;
    AppSession.reglesPaie.value = ReglesPaie.defaut;
  });

  group('Modèle : saisie d\'une journée', () {
    test('absente ou vide : une journée vide', () {
      expect(SaisieJour.depuisJour(null).estVide, isTrue);
      expect(
        SaisieJour.depuisJour(const {'nomJour': 'Mercredi'}).estVide,
        isTrue,
      );
      expect(SaisieJour.depuisJour(const {'estAucun': false}).estVide, isTrue);
    });

    test('jour non travaillé', () {
      final s = SaisieJour.depuisJour(const {
        'estAucun': true,
        'chantierId': 'x',
      });
      expect(s.estAucun, isTrue);
      expect(s.chantierId, isNull);
      expect(s.versDonnees(), {'estAucun': true});
    });

    test('journée enregistrée : saisie reprise, sans les heures calculées', () {
      final s = SaisieJour.depuisJour(_jours()[1]);
      expect(s.chantierId, 'c2');
      expect(s.debutMinutes, 480);
      expect(s.finMinutes, 960);
      expect(s.pauseMatin, isFalse);
      expect(s.diner, isTrue);
      expect(s.voyagementMinutes, 90);
      final d = s.versDonnees();
      expect(d.keys.toSet(), {
        'estAucun',
        'chantierId',
        'heureDebutMinutes',
        'heureFinMinutes',
        'pauseMatin',
        'diner',
        'tempsVoyagementMinutes',
      });
      expect(d.containsKey('heuresTravaillees'), isFalse);
      expect(d.containsKey('voyagementPayeHeures'), isFalse);
      expect(d.containsKey('verrouille'), isFalse);
    });

    test('pauses absentes : prises par défaut ; nombres décimaux acceptés ; chantier vide ignoré', () {
      final s = SaisieJour.depuisJour(const {
        'chantierId': '',
        'heureDebutMinutes': 420.0,
        'heureFinMinutes': 900,
      });
      expect(s.pauseMatin, isTrue);
      expect(s.diner, isTrue);
      expect(s.chantierId, isNull);
      expect(s.debutMinutes, 420);
    });

    test('voyagement nul : envoyé comme « aucun »', () {
      expect(
        const SaisieJour(voyagementMinutes: 0)
            .versDonnees()['tempsVoyagementMinutes'],
        isNull,
      );
      expect(
        const SaisieJour(voyagementMinutes: 45)
            .versDonnees()['tempsVoyagementMinutes'],
        45,
      );
    });

    test('validation : chantier, heures et ordre', () {
      expect(SaisieJour.vide.erreur, isNull);
      expect(const SaisieJour(estAucun: true).erreur, isNull);
      expect(
        const SaisieJour(debutMinutes: 420).erreur,
        'Choisissez un chantier.',
      );
      expect(
        const SaisieJour(chantierId: 'c1', debutMinutes: 420).erreur,
        'Indiquez l\'heure de début et l\'heure de fin.',
      );
      expect(
        const SaisieJour(chantierId: 'c1', finMinutes: 900).erreur,
        'Indiquez l\'heure de début et l\'heure de fin.',
      );
      expect(
        const SaisieJour(
          chantierId: 'c1',
          debutMinutes: 900,
          finMinutes: 900,
        ).erreur,
        'L\'heure de fin doit suivre l\'heure de début.',
      );
      expect(
        const SaisieJour(
          chantierId: 'c1',
          debutMinutes: 900,
          finMinutes: 420,
        ).erreur,
        'L\'heure de fin doit suivre l\'heure de début.',
      );
      expect(
        const SaisieJour(
          chantierId: 'c1',
          debutMinutes: 420,
          finMinutes: 900,
          voyagementMinutes: 721,
        ).erreur,
        'Le voyagement ne peut pas dépasser 12 h.',
      );
      expect(
        const SaisieJour(
          chantierId: 'c1',
          debutMinutes: 420,
          finMinutes: 900,
          voyagementMinutes: 720,
        ).erreur,
        isNull,
      );
    });

    test('copieAvec : peut effacer une valeur', () {
      const s = SaisieJour(
        chantierId: 'c1',
        debutMinutes: 420,
        finMinutes: 900,
      );
      expect(s.copieAvec(chantierId: null).chantierId, isNull);
      expect(s.copieAvec(finMinutes: null).finMinutes, isNull);
      expect(s.copieAvec(debutMinutes: 480).debutMinutes, 480);
      expect(s.copieAvec().debutMinutes, 420);
    });

    test('égalité : 0 et absent sont le même voyagement', () {
      expect(const SaisieJour(voyagementMinutes: 0), const SaisieJour());
      expect(
        const SaisieJour(voyagementMinutes: 30) == const SaisieJour(),
        isFalse,
      );
    });

    test('affichages : 07:00, 1 h 30, Aucun', () {
      expect(heureAffichee(420), '07:00');
      expect(heureAffichee(null), '--:--');
      expect(heureAffichee(0), '00:00');
      expect(dureeAffichee(null), 'Aucun');
      expect(dureeAffichee(0), 'Aucun');
      expect(dureeAffichee(45), '45 min');
      expect(dureeAffichee(120), '2 h');
      expect(dureeAffichee(90), '1 h 30');
      expect(dureeAffichee(65), '1 h 05');
    });
  });

  group('Jours envoyés au serveur', () {
    test('toujours cinq jours, le jour modifié remplacé, les autres tels qu\'enregistrés', () {
      final jours = joursPourCorrection(
        existants: _jours(),
        index: 2,
        saisie: const SaisieJour(
          chantierId: 'c1',
          debutMinutes: 420,
          finMinutes: 900,
        ),
      );
      expect(jours, hasLength(5));
      expect(jours[0]['chantierId'], 'c1');
      expect(jours[0]['heureFinMinutes'], 900);
      expect(jours[1]['tempsVoyagementMinutes'], 90);
      expect(jours[1]['pauseMatin'], false);
      expect(jours[2]['chantierId'], 'c1', reason: 'le jour modifié');
      expect(jours[3], {'estAucun': true});
      expect(
        jours[4],
        SaisieJour.vide.versDonnees(),
        reason: 'jour absent : vide',
      );
    });

    test('jamais de valeur calculée envoyée (heures, voyagement payé, verrouillage)', () {
      for (final jour in joursPourCorrection(
        existants: _jours(),
        index: 0,
        saisie: const SaisieJour(estAucun: true),
      )) {
        for (final interdit in [
          'heuresTravaillees',
          'voyagementPayeHeures',
          'verrouille',
          'chantierNom',
          'nomJour',
          'totalHeures',
        ]) {
          expect(jour.containsKey(interdit), isFalse, reason: interdit);
        }
      }
    });

    test(
      'feuille de moins de cinq jours : les jours manquants restent vides',
      () {
        final jours = joursPourCorrection(
          existants: [_jourLundi()],
          index: 0,
          saisie: const SaisieJour(estAucun: true),
        );
        expect(jours, hasLength(5));
        expect(
          jours
              .skip(1)
              .every((j) => j['estAucun'] == false && j['chantierId'] == null),
          isTrue,
        );
      },
    );
  });

  group('Tableau de la semaine', () {
    testWidgets('l\'astuce invite à toucher une journée', (tester) async {
      await _ouvrirSemaine(tester, _Appels());
      expect(find.byKey(const ValueKey('semaine_astuce')), findsOneWidget);
      expect(find.text('Félix Mercier'), findsOneWidget);
      expect(find.text('7.75'), findsWidgets);
    });

    testWidgets(
      'toucher le lundi : formulaire prérempli avec la saisie enregistrée',
      (tester) async {
        await _ouvrirSemaine(tester, _Appels());
        await _toucherJour(tester, 0);
        expect(find.text('Modifier les heures'), findsOneWidget);
        expect(find.text('Félix Mercier • Lundi 12/10'), findsOneWidget);
        expect(find.text('Chalet Nord'), findsOneWidget);
        expect(find.text('07:00'), findsOneWidget);
        expect(find.text('15:00'), findsOneWidget);
        expect(find.byKey(const ValueKey('jour_explication')), findsOneWidget);
        // Voyagement : non payé par la compagnie et aucun saisi → pas proposé.
        expect(find.byKey(const ValueKey('jour_voyagement')), findsNothing);
      },
    );

    testWidgets(
      'modifier l\'heure de fin : le serveur reçoit la saisie complète',
      (tester) async {
        final appels = _Appels()..reponse = {'totalHeures': 16.5};
        await _ouvrirSemaine(tester, appels, outils: _outils(appels, fin: 960));
        await _toucherJour(tester, 0);
        await tester.tap(find.byKey(const ValueKey('jour_fin')));
        await tester.pumpAndSettle();
        expect(find.text('16:00'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();

        expect(appels.faits, hasLength(1));
        expect(appels.faits.single.key, 'corrigerFeuilleTemps');
        final d = appels.faits.single.value;
        expect(d['employeeId'], 'emp1');
        expect(d['lundiDate'], '2026-10-12');
        final jours = d['jours'] as List;
        expect(jours, hasLength(5));
        expect(jours[0]['heureFinMinutes'], 960);
        expect(jours[0]['heureDebutMinutes'], 420);
        expect(jours[0]['chantierId'], 'c1');
        expect(jours[1]['heureDebutMinutes'], 480, reason: 'mardi inchangé');
        expect(jours[1]['tempsVoyagementMinutes'], 90);
        expect(jours[3], {
          'estAucun': true,
        }, reason: 'jeudi non travaillé conservé');
        // Le formulaire se ferme et le total recalculé par le serveur est annoncé.
        expect(find.text('Modifier les heures'), findsNothing);
        expect(
          find.text(
            'Heures de Félix Mercier modifiées : total de la semaine 16.50 h.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('journée vide : choisir un chantier et les heures', (
      tester,
    ) async {
      final appels = _Appels();
      await _ouvrirSemaine(
        tester,
        appels,
        outils: _outils(appels, debut: 450, fin: 1020),
      );
      await _toucherJour(tester, 2);
      expect(find.text('Félix Mercier • Mercredi 14/10'), findsOneWidget);
      expect(find.text('--:--'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('jour_chantier')));
      await tester.pumpAndSettle();
      expect(
        find.text('Vieux Hangar'),
        findsNothing,
        reason: 'un chantier archivé ne se propose plus',
      );
      await tester.tap(find.text('Garage Sud').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_debut')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_fin')));
      await tester.pumpAndSettle();
      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
      await tester.pumpAndSettle();

      final jour = (appels.faits.single.value['jours'] as List)[2] as Map;
      expect(jour['chantierId'], 'c2');
      expect(jour['heureDebutMinutes'], 450);
      expect(jour['heureFinMinutes'], 1020);
      expect(jour['pauseMatin'], true);
      expect(jour['diner'], true);
      expect(jour['estAucun'], false);
    });

    testWidgets('pauses : décocher le dîner est envoyé', (tester) async {
      final appels = _Appels();
      await _ouvrirSemaine(tester, appels);
      await _toucherJour(tester, 0);
      await tester.tap(find.byKey(const ValueKey('jour_diner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
      await tester.pumpAndSettle();
      final jour = (appels.faits.single.value['jours'] as List)[0] as Map;
      expect(jour['diner'], false);
      expect(jour['pauseMatin'], false);
    });

    testWidgets(
      '« Jour non travaillé » : les champs disparaissent, seul estAucun est envoyé',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(tester, appels);
        await _toucherJour(tester, 0);
        await tester.tap(find.byKey(const ValueKey('jour_non_travaille')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('jour_chantier')), findsNothing);
        expect(find.byKey(const ValueKey('jour_debut')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect((appels.faits.single.value['jours'] as List)[0], {
          'estAucun': true,
        });
      },
    );

    testWidgets(
      'décocher « Jour non travaillé » sans rien changer : aucun changement',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(tester, appels);
        await _toucherJour(tester, 3); // jeudi : non travaillé
        expect(find.byKey(const ValueKey('jour_chantier')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(find.text('Aucun changement à enregistrer.'), findsOneWidget);
        expect(appels.faits, isEmpty);
      },
    );

    testWidgets(
      'jour non travaillé → travaillé : les champs reviennent vides',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(tester, appels);
        await _toucherJour(tester, 3);
        await tester.tap(find.byKey(const ValueKey('jour_non_travaille')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('jour_chantier')), findsOneWidget);
        expect(find.text('--:--'), findsNWidgets(2));
      },
    );

    testWidgets(
      'validation : chantier manquant, puis fin avant début ; aucun appel',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(
          tester,
          appels,
          outils: _outils(appels, debut: 900, fin: 420),
        );
        await _toucherJour(tester, 2);
        await tester.tap(find.byKey(const ValueKey('jour_debut')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(find.text('Choisissez un chantier.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('jour_chantier')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chalet Nord').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_fin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(
          find.text('L\'heure de fin doit suivre l\'heure de début.'),
          findsOneWidget,
        );
        expect(appels.faits, isEmpty);
      },
    );

    testWidgets('journée vide laissée vide : rien à enregistrer', (
      tester,
    ) async {
      final appels = _Appels();
      await _ouvrirSemaine(tester, appels);
      await _toucherJour(tester, 2);
      await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Aucun changement à enregistrer.'), findsOneWidget);
      expect(appels.faits, isEmpty);
    });

    testWidgets(
      'jour non travaillé décoché sans rien saisir : explication, aucun appel',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(tester, appels);
        await _toucherJour(tester, 3); // jeudi : non travaillé
        await tester.tap(find.byKey(const ValueKey('jour_non_travaille')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Indiquez un chantier et les heures, ou gardez « Jour non travaillé ».',
          ),
          findsOneWidget,
        );
        expect(appels.faits, isEmpty);
      },
    );

    testWidgets(
      'refus du serveur : le message s\'affiche, le formulaire reste ouvert',
      (tester) async {
        final appels = _Appels()..erreur = Exception('refus');
        await _ouvrirSemaine(tester, appels, outils: _outils(appels, fin: 960));
        await _toucherJour(tester, 0);
        await tester.tap(find.byKey(const ValueKey('jour_fin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('jour_erreur')), findsOneWidget);
        expect(find.textContaining('Erreur de réseau'), findsOneWidget);
        expect(find.text('Modifier les heures'), findsOneWidget);
        // On peut réessayer.
        appels.erreur = null;
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        expect(appels.faits, hasLength(2));
        expect(find.text('Modifier les heures'), findsNothing);
      },
    );

    testWidgets('annuler : aucun appel', (tester) async {
      final appels = _Appels();
      await _ouvrirSemaine(tester, appels, outils: _outils(appels, fin: 960));
      await _toucherJour(tester, 0);
      await tester.tap(find.byKey(const ValueKey('jour_fin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_annuler')));
      await tester.pumpAndSettle();
      expect(appels.faits, isEmpty);
      expect(find.text('Modifier les heures'), findsNothing);
    });

    testWidgets(
      'chantier archivé depuis : il reste sélectionné et marqué (archivé)',
      (tester) async {
        final fiche = _fiche();
        (fiche['jours'] as List)[0] = {
          ..._jourLundi(),
          'chantierId': 'c3',
          'chantierNom': 'Vieux Hangar',
        };
        final appels = _Appels();
        await _ouvrirSemaine(tester, appels, fiches: [fiche]);
        await _toucherJour(tester, 0);
        expect(find.text('Vieux Hangar (archivé)'), findsOneWidget);
      },
    );

    testWidgets('chantier devenu introuvable : son nom enregistré est montré', (
      tester,
    ) async {
      final fiche = _fiche();
      (fiche['jours'] as List)[0] = {
        ..._jourLundi(),
        'chantierId': 'disparu',
        'chantierNom': 'Ancien Projet',
      };
      await _ouvrirSemaine(tester, _Appels(), fiches: [fiche]);
      await _toucherJour(tester, 0);
      expect(find.text('Ancien Projet'), findsOneWidget);
    });

    testWidgets(
      'chantiers impossibles à charger : message, enregistrement non proposé sans chantier',
      (tester) async {
        final appels = _Appels();
        await _ouvrirSemaine(
          tester,
          appels,
          outils: OutilsEditionJour(
            appelerFonction: appels.appeler,
            chargerChantiers: () async => throw Exception('hors ligne'),
          ),
        );
        await _toucherJour(tester, 0);
        expect(
          find.byKey(const ValueKey('jour_erreur_chantiers')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'voyagement : proposé si la compagnie le paie ; la durée choisie est envoyée',
      (tester) async {
        AppSession.reglesPaie.value = const ReglesPaie(voyagementActif: true);
        final appels = _Appels();
        await _ouvrirSemaine(
          tester,
          appels,
          outils: _outils(appels, voyagement: 120),
        );
        await _toucherJour(tester, 0);
        expect(find.byKey(const ValueKey('jour_voyagement')), findsOneWidget);
        expect(find.text('Aucun'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('jour_voyagement')));
        await tester.pumpAndSettle();
        expect(find.text('2 h'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        final jour = (appels.faits.single.value['jours'] as List)[0] as Map;
        expect(jour['tempsVoyagementMinutes'], 120);
      },
    );

    testWidgets(
      'voyagement déjà saisi : proposé même si la compagnie ne le paie plus',
      (tester) async {
        await _ouvrirSemaine(tester, _Appels());
        await _toucherJour(tester, 1); // mardi : 90 min
        expect(find.byKey(const ValueKey('jour_voyagement')), findsOneWidget);
        expect(find.text('1 h 30'), findsOneWidget);
      },
    );

    testWidgets('voyagement remis à zéro : envoyé comme aucun', (tester) async {
      final appels = _Appels();
      await _ouvrirSemaine(
        tester,
        appels,
        outils: _outils(appels, voyagement: 0),
      );
      await _toucherJour(tester, 1);
      await tester.tap(find.byKey(const ValueKey('jour_voyagement')));
      await tester.pumpAndSettle();
      expect(find.text('Aucun'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
      await tester.pumpAndSettle();
      final jour = (appels.faits.single.value['jours'] as List)[1] as Map;
      expect(jour['tempsVoyagementMinutes'], isNull);
    });

    testWidgets('sans réponse chiffrée du serveur : message simple', (
      tester,
    ) async {
      final appels = _Appels()..reponse = {};
      await _ouvrirSemaine(tester, appels, outils: _outils(appels, fin: 960));
      await _toucherJour(tester, 0);
      await tester.tap(find.byKey(const ValueKey('jour_fin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Heures de Félix Mercier modifiées.'), findsOneWidget);
    });
  });

  group('Semaine d\'un employé', () {
    Future<void> ouvrir(
      WidgetTester tester,
      _Appels appels, {
      Stream<Map<String, dynamic>?>? flux,
    }) async {
      AppSession.notifier.value = _admin();
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SemaineEmployeScreen(
            titre: 'Semaine du 12/10 au 18/10/2026',
            employeeId: 'emp1',
            employeeNom: 'Félix Mercier',
            lundiDate: '2026-10-12',
            joursInitiaux: _jours(),
            fluxFeuille: (_) => flux ?? Stream.value(_fiche()),
            outils: _outils(appels, fin: 960),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('cinq lignes, même si la feuille en a moins', (tester) async {
      await ouvrir(tester, _Appels());
      for (final jour in ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi']) {
        expect(find.text(jour), findsOneWidget, reason: jour);
      }
      expect(find.text('Non travaillé'), findsOneWidget);
      expect(find.text('Chalet Nord'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('employe_astuce')), findsOneWidget);
    });

    testWidgets(
      'toucher une ligne ouvre le formulaire de ce jour et enregistre',
      (tester) async {
        final appels = _Appels();
        await ouvrir(tester, appels);
        await tester.tap(find.text('Lundi'));
        await tester.pumpAndSettle();
        expect(find.text('Félix Mercier • Lundi 12/10'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('jour_fin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('jour_enregistrer')));
        await tester.pumpAndSettle();
        final d = appels.faits.single.value;
        expect(d['employeeId'], 'emp1');
        expect(((d['jours'] as List)[0] as Map)['heureFinMinutes'], 960);
        expect(find.textContaining('Heures modifiées'), findsOneWidget);
      },
    );

    testWidgets('la feuille se met à jour en direct après la correction', (
      tester,
    ) async {
      final appels = _Appels();
      final mises = Stream<Map<String, dynamic>?>.fromIterable([
        _fiche(),
        {
          ..._fiche(),
          'jours': [
            {
              ..._jourLundi(),
              'heureFinMinutes': 960,
              'heuresTravaillees': 8.75,
            },
            ..._jours().skip(1),
          ],
        },
      ]);
      await ouvrir(tester, appels, flux: mises);
      expect(find.text('16:00'), findsWidgets);
      expect(find.text('8.75'), findsOneWidget);
    });
  });
}
