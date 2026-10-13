// Le NIP haché n'est plus lisible par les admins : l'application lit `nipCree` (ou, pendant la
// transition, un ancien `pinHash` non vide) pour savoir si un NIP existe.
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/nip_employe.dart';
import 'package:construction_app/screens/admin/employe_formulaire_screen.dart';
import 'package:construction_app/screens/admin/employes_liste_screen.dart';
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

const _base = {'nom': 'Rémi Rappel', 'courriel': 'remi@exemple.ca', 'role': 'employe'};

Future<void> _ouvrirFormulaire(
  WidgetTester tester,
  Map<String, dynamic> donnees,
) async {
  AppSession.notifier.value = _admin();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EmployeFormulaireScreen(
                    docId: 'e1',
                    donneesExistantes: donnees,
                    appelerFonction: (nom, d) async => {'ok': true},
                  ),
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
}

Future<void> _ouvrirListe(
  WidgetTester tester,
  List<Map<String, dynamic>> fiches,
) async {
  AppSession.notifier.value = _admin();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: EmployesListeScreen(
        flux: Stream.value([
          for (var i = 0; i < fiches.length; i++) MapEntry('e$i', fiches[i]),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('nipCree', () {
    test('le booléen du serveur, ou un ancien pinHash non vide', () {
      expect(nipCree({'nipCree': true}), isTrue);
      expect(nipCree({'pinHash': 'abc'}), isTrue);
      expect(nipCree({'nipCree': true, 'pinHash': 'abc'}), isTrue);
    });

    test('pas de NIP : faux, absent, ancien champ vide ou illisible', () {
      expect(nipCree({}), isFalse);
      expect(nipCree({'nipCree': false}), isFalse);
      expect(nipCree({'nipCree': false, 'pinHash': ''}), isFalse);
      expect(nipCree({'pinHash': ''}), isFalse);
      expect(nipCree({'pinHash': null}), isFalse);
      expect(nipCree({'pinHash': 12}), isFalse);
      expect(nipCree({'nipCree': 'true'}), isFalse);
      expect(nipCree({'nipCree': 1}), isFalse);
    });
  });

  group('Formulaire : renvoyer l\'invitation ou réinitialiser', () {
    testWidgets('nipCree: true (sans pinHash) → « Réinitialiser le NIP »', (t) async {
      await _ouvrirFormulaire(t, {..._base, 'nipCree': true});
      expect(find.text('Réinitialiser le NIP'), findsOneWidget);
      expect(find.text('Renvoyer l\'invitation'), findsNothing);
    });

    testWidgets('ancien pinHash → « Réinitialiser le NIP » (avant la migration)', (t) async {
      await _ouvrirFormulaire(t, {..._base, 'pinHash': 'h'});
      expect(find.text('Réinitialiser le NIP'), findsOneWidget);
    });

    testWidgets('nipCree: false, ou aucun champ → « Renvoyer l\'invitation »', (t) async {
      await _ouvrirFormulaire(t, {..._base, 'nipCree': false});
      expect(find.text('Renvoyer l\'invitation'), findsOneWidget);
      expect(find.text('Réinitialiser le NIP'), findsNothing);
    });

    testWidgets('aucun champ du tout → « Renvoyer l\'invitation »', (t) async {
      await _ouvrirFormulaire(t, _base);
      expect(find.text('Renvoyer l\'invitation'), findsOneWidget);
    });
  });

  group('Liste : « Invitation en attente »', () {
    const attente = 'Invitation en attente : NIP pas encore créé';

    testWidgets('nipCree: true → rien', (t) async {
      await _ouvrirListe(t, [
        {..._base, 'nom': 'Alice', 'nipCree': true},
      ]);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text(attente), findsNothing);
    });

    testWidgets('ancien pinHash → rien (transition)', (t) async {
      await _ouvrirListe(t, [
        {..._base, 'nom': 'Alice', 'pinHash': 'h'},
      ]);
      expect(find.text(attente), findsNothing);
    });

    testWidgets('nipCree: false ou aucun champ → en attente', (t) async {
      await _ouvrirListe(t, [
        {..._base, 'nom': 'Alice', 'nipCree': false},
        {..._base, 'nom': 'Bob'},
        {..._base, 'nom': 'Carl', 'nipCree': true},
      ]);
      expect(find.text(attente), findsNWidgets(2));
    });
  });
}
