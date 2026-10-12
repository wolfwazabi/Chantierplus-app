// Formulaire d'un employé (Admin → Employés) : « Renvoyer l'invitation » pour qui n'a pas
// encore créé son NIP (rien n'est effacé), « Réinitialiser le NIP » pour qui en a un.
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/employe_formulaire_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _admin() => Employee(
  id: 'admin1',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Alex',
  role: EmployeeRole.admin,
  estProprietaire: true,
);

class _Appels {
  final List<Map<String, dynamic>> envoyes = [];
  Object? erreur;
  Map<String, dynamic> reponse = {'id': 'e1', 'courrielEnvoye': true};

  Future<Map<String, dynamic>> appeler(
    String nom,
    Map<String, dynamic> donnees,
  ) async {
    expect(nom, 'enregistrerEmploye');
    envoyes.add(donnees);
    final e = erreur;
    if (e != null) throw e;
    return reponse;
  }
}

Future<void> _ouvrir(
  WidgetTester tester,
  _Appels appels, {
  required Map<String, dynamic> donnees,
}) async {
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
                    appelerFonction: appels.appeler,
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

const _sansNip = {
  'nom': 'Rémi Rappel',
  'courriel': 'remi@exemple.ca',
  'role': 'employe',
};
const _avecNip = {..._sansNip, 'pinHash': 'abc123'};

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('EmployeFormulaireScreen : renvoi de l\'invitation', () {
    testWidgets('sans NIP : « Renvoyer l\'invitation » remplace « Réinitialiser »', (
      tester,
    ) async {
      await _ouvrir(tester, _Appels(), donnees: _sansNip);
      expect(find.text('Renvoyer l\'invitation'), findsOneWidget);
      expect(find.text('Réinitialiser le NIP'), findsNothing);
    });

    testWidgets('avec un NIP : seulement « Réinitialiser le NIP »', (tester) async {
      await _ouvrir(tester, _Appels(), donnees: _avecNip);
      expect(find.text('Réinitialiser le NIP'), findsOneWidget);
      expect(find.text('Renvoyer l\'invitation'), findsNothing);
    });

    testWidgets('le bouton envoie renvoiInvitation (sans réinitialiser) et ferme l\'écran', (
      tester,
    ) async {
      final appels = _Appels();
      await _ouvrir(tester, appels, donnees: _sansNip);
      await tester.tap(find.text('Renvoyer l\'invitation'));
      await tester.pumpAndSettle();

      expect(appels.envoyes, hasLength(1));
      final d = appels.envoyes.single;
      expect(d['employeeId'], 'e1');
      expect(d['renvoiInvitation'], true);
      expect(d['reinitialiserNip'], false);
      expect(d['courriel'], 'remi@exemple.ca');
      expect(d['role'], 'employe');
      expect(find.text('Invitation renvoyée à remi@exemple.ca.'), findsOneWidget);
      expect(find.byType(EmployeFormulaireScreen), findsNothing);
    });

    testWidgets('« Enregistrer » n\'envoie jamais de renvoi', (tester) async {
      final appels = _Appels();
      await _ouvrir(tester, appels, donnees: _sansNip);
      await tester.tap(find.text('Enregistrer les modifications'));
      await tester.pumpAndSettle();
      expect(appels.envoyes.single.containsKey('renvoiInvitation'), isFalse);
      expect(appels.envoyes.single['reinitialiserNip'], false);
    });

    testWidgets('refus du serveur : le message s\'affiche et l\'écran reste ouvert', (
      tester,
    ) async {
      final appels = _Appels()..erreur = Exception('refus');
      await _ouvrir(tester, appels, donnees: _sansNip);
      await tester.tap(find.text('Renvoyer l\'invitation'));
      await tester.pumpAndSettle();
      expect(find.byType(EmployeFormulaireScreen), findsOneWidget);
      expect(find.textContaining('Erreur de réseau'), findsOneWidget);
    });

    testWidgets('courriel qui n\'a pas pu partir : le lien de secours est montré', (
      tester,
    ) async {
      final appels = _Appels()
        ..reponse = {
          'id': 'e1',
          'courrielEnvoye': false,
          'lienInvitation': 'https://exemple.test/creer#e=e1&t=jeton',
        };
      await _ouvrir(tester, appels, donnees: _sansNip);
      await tester.tap(find.text('Renvoyer l\'invitation'));
      // La boîte de dialogue reste ouverte (curseur du texte sélectionnable) :
      // pas de pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Courriel non envoyé'), findsOneWidget);
      expect(find.textContaining('https://exemple.test/creer'), findsOneWidget);
    });

    testWidgets('courriel invalide : rien n\'est envoyé', (tester) async {
      final appels = _Appels();
      await _ouvrir(
        tester,
        appels,
        donnees: {..._sansNip, 'courriel': 'pas-un-courriel'},
      );
      await tester.tap(find.text('Renvoyer l\'invitation'));
      await tester.pumpAndSettle();
      expect(appels.envoyes, isEmpty);
      expect(find.text('Courriel invalide.'), findsOneWidget);
    });
  });
}
