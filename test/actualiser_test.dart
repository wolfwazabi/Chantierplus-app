// Tirer vers le bas pour actualiser : l'outil commun et les écrans qui l'utilisent.
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/anciens_employes_screen.dart';
import 'package:construction_app/screens/admin/employes_liste_screen.dart';
import 'package:construction_app/screens/admin/semaine_detail_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:construction_app/widgets/actualiser.dart';
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

/// Tire vers le bas, comme un doigt, puis laisse l'indicateur finir.
Future<void> _tirer(WidgetTester tester, Finder sur) async {
  await tester.fling(sur, const Offset(0, 400), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Un flux qu'on peut écouter plusieurs fois et dont on compte les écoutes.
class _Ecoutes<T> {
  int ecoutes = 0;
  final T valeur;
  _Ecoutes(this.valeur);
  Stream<T> get flux => Stream<T>.multi((c) {
    ecoutes++;
    c.add(valeur);
  });
}

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('FluxActualisable', () {
    testWidgets(
      'tirer vers le bas relance la lecture et affiche les données fraîches',
      (tester) async {
        var appels = 0;
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const DefilementActualisable(),
            home: Scaffold(
              body: FluxActualisable<int>(
                creerFlux: () => Stream.value(++appels),
                builder: (context, snap) => snap.hasData
                    ? ListView(children: [Text('valeur ${snap.data}')])
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('valeur 1'), findsOneWidget);
        expect(appels, 1);

        await _tirer(tester, find.byType(ListView));
        expect(appels, 2, reason: 'une nouvelle lecture');
        expect(find.text('valeur 2'), findsOneWidget);
        expect(find.text('valeur 1'), findsNothing);
      },
    );

    testWidgets('même une liste d\'un seul élément se tire (page courte)', (
      tester,
    ) async {
      var appels = 0;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: Scaffold(
            body: FluxActualisable<int>(
              creerFlux: () => Stream.value(++appels),
              builder: (context, snap) =>
                  ListView(children: [Text('${snap.data}')]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tirer(tester, find.byType(ListView));
      expect(appels, 2);
    });

    testWidgets('un message centré (liste vide, erreur) se tire aussi', (
      tester,
    ) async {
      var appels = 0;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: Scaffold(
            body: FluxActualisable<int>(
              creerFlux: () => Stream.value(++appels),
              builder: (context, snap) =>
                  const Center(child: Text('Aucun chantier')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aucun chantier'), findsOneWidget);
      await _tirer(tester, find.text('Aucun chantier'));
      expect(appels, 2);
      expect(find.text('Aucun chantier'), findsOneWidget);
    });

    testWidgets('l\'indicateur de chargement n\'est pas transformé en liste', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FluxActualisable<int>(
              creerFlux: () => const Stream<int>.empty(),
              builder: (context, snap) =>
                  const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets(
      'pendant l\'actualisation, les données déjà affichées restent (pas de clignotement)',
      (tester) async {
        var appels = 0;
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const DefilementActualisable(),
            home: Scaffold(
              body: FluxActualisable<int>(
                creerFlux: () =>
                    appels++ == 0 ? Stream.value(1) : const Stream<int>.empty(),
                builder: (context, snap) => snap.hasData
                    ? ListView(children: [Text('valeur ${snap.data}')])
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tirer(tester, find.byType(ListView));
        // Le nouveau flux n'a encore rien dit : on garde l'ancienne valeur, pas un spinner.
        expect(find.text('valeur 1'), findsOneWidget);
      },
    );
  });

  group('PageActualisable', () {
    testWidgets('appelle onRefresh au geste', (tester) async {
      var n = 0;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: Scaffold(
            body: PageActualisable(
              onRefresh: () async => n++,
              child: ListView(children: const [Text('contenu')]),
            ),
          ),
        ),
      );
      await _tirer(tester, find.text('contenu'));
      expect(n, 1);
    });
  });

  group('Écrans', () {
    testWidgets('liste des employés : tirer relance la lecture', (
      tester,
    ) async {
      AppSession.notifier.value = _admin();
      final source = _Ecoutes([
        MapEntry<String, Map<String, dynamic>>('e1', {
          'nom': 'Alice',
          'courriel': 'a@exemple.ca',
          'role': 'employe',
          'nipCree': true,
        }),
      ]);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: EmployesListeScreen(flux: source.flux),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(source.ecoutes, 1);
      await _tirer(tester, find.byType(ListView));
      expect(source.ecoutes, 2);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('anciens employés : le message « aucun » se tire aussi', (
      tester,
    ) async {
      AppSession.notifier.value = _admin();
      final source = _Ecoutes(<MapEntry<String, Map<String, dynamic>>>[]);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const DefilementActualisable(),
          home: AnciensEmployesScreen(flux: source.flux),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('anciens_vide')), findsOneWidget);
      await _tirer(tester, find.byKey(const ValueKey('anciens_vide')));
      expect(source.ecoutes, 2);
    });

    testWidgets(
      'tableau de la semaine : tirer relance la lecture des feuilles',
      (tester) async {
        AppSession.notifier.value = _admin();
        final source = _Ecoutes([
          MapEntry<String, Map<String, dynamic>>('emp1_2026-10-12', {
            'employeeId': 'emp1',
            'employeeNom': 'Félix Mercier',
            'lundiDate': '2026-10-12',
            'jours': <Map<String, dynamic>>[],
            'totalHeures': 0,
          }),
        ]);
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            scrollBehavior: const DefilementActualisable(),
            home: SemaineDetailScreen(
              lundiDate: '2026-10-12',
              flux: source.flux,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _tirer(tester, find.text('Félix Mercier'));
        expect(source.ecoutes, 2);
        expect(find.text('Félix Mercier'), findsOneWidget);
      },
    );
  });
}
