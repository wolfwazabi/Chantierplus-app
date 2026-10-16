// Mise à jour de l'app : la dernière version annoncée, la pastille sur « Compte » et le
// bouton « Mettre à jour l'app » sous « Préférences ».
import 'dart:async';

import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/compte_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:construction_app/services/version_app.dart';
import 'package:construction_app/widgets/barre_onglets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _employe(EmployeeRole role) => Employee(
  id: 'e1',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Alex',
  role: role,
);

/// Branche le service sur un faux Firestore : [derniere] émet la dernière version
/// connue ; les annonces sont notées dans [annonces].
StreamController<int?> _brancher({
  required int buildLocal,
  required List<(String, int)> annonces,
}) {
  final derniere = StreamController<int?>.broadcast();
  VersionApp.buildLocal = buildLocal;
  VersionApp.plateformeForcee = 'ios';
  VersionApp.fluxDerniere = (_) => derniere.stream;
  VersionApp.annoncer = (p, b) async => annonces.add((p, b));
  return derniere;
}

void main() {
  tearDown(() async {
    await VersionApp.reinitialiser();
    AppSession.notifier.value = null;
  });

  group('dernière version', () {
    test(
      'build de développement (0) : rien n\'est écouté ni proposé',
      () async {
        var lu = false;
        VersionApp.plateformeForcee = 'ios';
        VersionApp.buildLocal = 0;
        VersionApp.fluxDerniere = (_) {
          lu = true;
          return const Stream.empty();
        };
        VersionApp.demarrer();
        expect(lu, isFalse);
        expect(VersionApp.majDisponible.value, isFalse);
      },
    );

    test('Android et web : pas encore de canal de mise à jour', () {
      VersionApp.buildLocal = 12;
      expect(VersionApp.plateforme, isNull); // tests : ni iPhone ni forcé
      expect(VersionApp.lien('android'), isNull);
      expect(
        VersionApp.lien('ios').toString(),
        'itms-beta://beta.itunes.apple.com/v1/app/6817907454',
      );
    });

    test(
      'une version plus récente annoncée : mise à jour disponible',
      () async {
        final annonces = <(String, int)>[];
        final derniere = _brancher(buildLocal: 12, annonces: annonces);
        VersionApp.demarrer();
        derniere.add(13);
        await pumpEventQueue();
        expect(VersionApp.majDisponible.value, isTrue);
        derniere.add(12); // la même : à jour
        await pumpEventQueue();
        expect(VersionApp.majDisponible.value, isFalse);
        expect(annonces, isEmpty); // employé déconnecté : il n'annonce rien
        await derniere.close();
      },
    );

    test(
      'un admin qui a une version plus récente l\'annonce, une fois chargée',
      () async {
        final annonces = <(String, int)>[];
        final derniere = _brancher(buildLocal: 14, annonces: annonces);
        AppSession.notifier.value = _employe(EmployeeRole.admin);
        await VersionApp.annoncerSiPlusRecente();
        expect(annonces, isEmpty); // la dernière version n'est pas encore lue
        VersionApp.demarrer();
        derniere.add(12);
        await pumpEventQueue();
        expect(annonces, [('ios', 14)]);
        expect(VersionApp.majDisponible.value, isFalse);
        // Aucune version annoncée encore : il l'annonce aussi.
        annonces.clear();
        derniere.add(null);
        await pumpEventQueue();
        expect(annonces, [('ios', 14)]);
        // Déjà annoncée (ou plus récente ailleurs) : rien.
        annonces.clear();
        derniere.add(14);
        await pumpEventQueue();
        derniere.add(15);
        await pumpEventQueue();
        expect(annonces, isEmpty);
        expect(VersionApp.majDisponible.value, isTrue);
        await derniere.close();
      },
    );

    test('employé ou contremaître : n\'annonce pas', () async {
      final annonces = <(String, int)>[];
      final derniere = _brancher(buildLocal: 14, annonces: annonces);
      for (final role in [EmployeeRole.employe, EmployeeRole.plus]) {
        AppSession.notifier.value = _employe(role);
        VersionApp.demarrer();
        derniere.add(12);
        await pumpEventQueue();
      }
      expect(annonces, isEmpty);
      await derniere.close();
    });

    test('une annonce refusée (un autre l\'a faite) ne lance rien', () async {
      VersionApp.buildLocal = 14;
      VersionApp.plateformeForcee = 'ios';
      final derniere = StreamController<int?>();
      VersionApp.fluxDerniere = (_) => derniere.stream;
      VersionApp.annoncer = (_, _) async => throw StateError('refusé');
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      VersionApp.demarrer();
      derniere.add(12);
      await pumpEventQueue();
      await VersionApp.annoncerSiPlusRecente();
      await derniere.close();
    });
  });

  group('pastille et bouton', () {
    testWidgets('pastille sur l\'onglet « Compte » seulement', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BarreOnglets(
              indexSelectionne: 0,
              onSelection: (_) {},
              onglets: const [
                OngletBarre('Temps', Icons.access_time, Icons.access_time),
                OngletBarre(
                  'Compte',
                  Icons.person_outline,
                  Icons.person,
                  pastille: true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        t
            .widget<Badge>(find.byKey(const ValueKey('pastille_Compte')))
            .isLabelVisible,
        isTrue,
      );
      expect(
        t
            .widget<Badge>(find.byKey(const ValueKey('pastille_Temps')))
            .isLabelVisible,
        isFalse,
      );
    });

    testWidgets(
      'Compte : « Mettre à jour l\'app » sous « Préférences », ouvre TestFlight',
      (t) async {
        final liens = <Uri>[];
        VersionApp.plateformeForcee = 'ios';
        VersionApp.ouvrirLien = (u) async {
          liens.add(u);
          return true;
        };
        AppSession.notifier.value = _employe(EmployeeRole.employe);
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: CompteScreen())),
        );
        // À jour : pas de bouton.
        expect(find.byKey(const ValueKey('bouton_mise_a_jour')), findsNothing);

        VersionApp.majDisponible.value = true;
        await t.pump();
        final bouton = find.byKey(const ValueKey('bouton_mise_a_jour'));
        expect(bouton, findsOneWidget);
        expect(find.text('Mettre à jour l\'app'), findsOneWidget);
        // Juste sous « Préférences ».
        final pref = t.getRect(
          find.byKey(const ValueKey('bouton_preferences')),
        );
        final maj = t.getRect(bouton);
        expect(maj.top, greaterThan(pref.bottom));
        expect(
          t.getRect(find.text('Se déconnecter')).top,
          greaterThan(maj.bottom),
        );

        await t.tap(bouton);
        await t.pumpAndSettle();
        expect(liens.map((u) => u.toString()), [
          'itms-beta://beta.itunes.apple.com/v1/app/6817907454',
        ]);
      },
    );

    testWidgets('TestFlight introuvable : l\'autre lien, puis un message', (
      t,
    ) async {
      final liens = <Uri>[];
      VersionApp.plateformeForcee = 'ios';
      VersionApp.ouvrirLien = (u) async {
        liens.add(u);
        return false;
      };
      VersionApp.majDisponible.value = true;
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: CompteScreen())),
      );
      await t.tap(find.byKey(const ValueKey('bouton_mise_a_jour')));
      await t.pumpAndSettle();
      expect(liens, hasLength(2));
      expect(liens.last.scheme, 'https');
      expect(find.textContaining('TestFlight'), findsOneWidget);
    });
  });
}
