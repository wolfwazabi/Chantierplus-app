// Anciens employés : le retrait garde une fiche minimale 24 mois (loi 25), la liste des
// employés ne montre que les actifs, l'écran « Anciens employés » réactive ou supprime.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/ancien_employe.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/anciens_employes_screen.dart';
import 'package:construction_app/screens/admin/employes_liste_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Employee _admin() => Employee(
  id: 'e5',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Zoé Proprio',
  role: EmployeeRole.admin,
  estProprietaire: true,
);

Timestamp _ts(int a, int m, int j) => Timestamp.fromDate(DateTime(a, m, j));

List<MapEntry<String, Map<String, dynamic>>> _fiches() => [
  MapEntry('e1', {
    'nom': 'Alice Tremblay',
    'courriel': 'alice@exemple.ca',
    'role': 'employe',
    'pinHash': 'h',
  }),
  MapEntry('e2', {
    'nom': 'Bob Gagnon',
    'courriel': 'bob@exemple.ca',
    'role': 'plus',
    'actif': true,
  }),
  MapEntry('e3', {
    'nom': 'Carl Ancien',
    'courriel': 'carl@exemple.ca',
    'role': 'employe',
    'actif': false,
    'retireLe': _ts(2026, 3, 1),
    'supprimeApresLe': _ts(2028, 3, 1),
    'motifRetrait': 'saisonnier',
  }),
  MapEntry('e4', {
    'nom': 'Dina Ancienne',
    'courriel': 'dina@exemple.ca',
    'role': 'plus',
    'actif': false,
    'retireLe': _ts(2026, 9, 15),
    'supprimeApresLe': _ts(2028, 9, 15),
    'motifRetrait': 'maladie : cancer', // hors liste : jamais affiché tel quel
  }),
  MapEntry('e5', {
    'nom': 'Zoé Proprio',
    'courriel': 'zoe@exemple.ca',
    'role': 'admin',
    'estProprietaire': true,
    'pinHash': 'h',
  }),
];

/// Flux qu'on peut écouter plus d'une fois (la liste et l'écran des anciens se partagent le même).
Stream<List<MapEntry<String, Map<String, dynamic>>>> _flux(
  List<MapEntry<String, Map<String, dynamic>>> fiches,
) => Stream.multi((c) => c.add(fiches));

class _Appels {
  final List<MapEntry<String, Map<String, dynamic>>> faits = [];
  Object? erreur;
  Map<String, dynamic> reponse = {'ok': true};

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

Future<void> _ouvrirListe(WidgetTester tester, _Appels appels) async {
  AppSession.notifier.value = _admin();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: EmployesListeScreen(
        flux: _flux(_fiches()),
        appelerFonction: appels.appeler,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ouvrirAnciens(
  WidgetTester tester,
  _Appels appels, {
  List<MapEntry<String, Map<String, dynamic>>>? fiches,
}) async {
  AppSession.notifier.value = _admin();
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: AnciensEmployesScreen(
        flux: _flux(fiches ?? _fiches()),
        appelerFonction: appels.appeler,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('Modèle : anciens employés', () {
    test('actif sauf si la fiche dit actif: false (les fiches existantes n\'ont pas le champ)', () {
      expect(employeActif({'nom': 'A'}), isTrue);
      expect(employeActif({'actif': true}), isTrue);
      expect(employeActif({'actif': false}), isFalse);
      expect(employeActif({'actif': null}), isTrue);
      expect(employeActif({'actif': 'non'}), isTrue);
    });

    test('motifs : liste fermée de six, libellés en français, hors liste = non précisé', () {
      expect(motifsRetrait.keys, [
        'non-precise',
        'saisonnier',
        'depart-volontaire',
        'fin-contrat',
        'absence-prolongee',
        'autre',
      ]);
      expect(libelleMotifRetrait('saisonnier'), 'Employé saisonnier');
      expect(libelleMotifRetrait('absence-prolongee'), 'Absence prolongée');
      for (final v in [null, '', 'maladie', 'Saisonnier', 3, true]) {
        expect(libelleMotifRetrait(v), 'Non précisé', reason: '$v');
      }
    });

    test('fiche d\'un ancien employé : champs manquants sans plantage', () {
      final e = AncienEmploye.depuis('x', {'actif': false});
      expect(e.nom, '');
      expect(e.courriel, '');
      expect(e.retireLe, isNull);
      expect(e.retireLeAffiche, '—');
      expect(e.supprimeApresLeAffiche, '—');
      expect(e.motif, 'Non précisé');
    });

    test('dates affichées jour/mois/année', () {
      final e = AncienEmploye.depuis('x', {
        'actif': false,
        'retireLe': _ts(2026, 3, 1),
        'supprimeApresLe': _ts(2028, 3, 1),
      });
      expect(e.retireLeAffiche, '01/03/2026');
      expect(e.supprimeApresLeAffiche, '01/03/2028');
    });

    test('seulement les anciens, le plus récemment retiré d\'abord', () {
      final liste = anciensEmployes(_fiches());
      expect(liste.map((e) => e.id), ['e4', 'e3']);
    });

    test('sans date de retrait : à la fin, par nom', () {
      final liste = anciensEmployes([
        MapEntry('b', {'nom': 'Zèbre', 'actif': false}),
        MapEntry('a', {'nom': 'abeille', 'actif': false}),
        MapEntry('c', {'nom': 'Daté', 'actif': false, 'retireLe': _ts(2026, 1, 1)}),
      ]);
      expect(liste.map((e) => e.id), ['c', 'a', 'b']);
    });
  });

  group('Liste des employés', () {
    testWidgets('les anciens employés n\'y figurent plus', (tester) async {
      await _ouvrirListe(tester, _Appels());
      expect(find.text('Alice Tremblay'), findsOneWidget);
      expect(find.text('Bob Gagnon'), findsOneWidget);
      expect(find.text('Zoé Proprio'), findsOneWidget);
      expect(find.text('Carl Ancien'), findsNothing);
      expect(find.text('Dina Ancienne'), findsNothing);
    });

    testWidgets('« Invitation en attente » seulement sans NIP (comme avant)', (tester) async {
      await _ouvrirListe(tester, _Appels());
      expect(find.text('Invitation en attente : NIP pas encore créé'), findsOneWidget);
    });

    testWidgets('si tout le monde est ancien : « Aucun employé »', (tester) async {
      AppSession.notifier.value = _admin();
      await tester.pumpWidget(
        MaterialApp(
          home: EmployesListeScreen(
            flux: Stream.value([
              MapEntry('x', {'nom': 'Ancien', 'actif': false}),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aucun employé pour l\'instant.'), findsOneWidget);
    });

    testWidgets('« Retirer » n\'est pas proposé pour le super-admin ni pour soi-même', (tester) async {
      await _ouvrirListe(tester, _Appels());
      await tester.tap(find.byKey(const ValueKey('employe_menu_e5')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Retirer'), findsNothing);
    });

    testWidgets('l\'icône « Anciens employés » ouvre l\'écran des anciens', (tester) async {
      await _ouvrirListe(tester, _Appels());
      await tester.tap(find.byKey(const ValueKey('employes_anciens')));
      await tester.pumpAndSettle();
      expect(find.byType(AnciensEmployesScreen), findsOneWidget);
      expect(find.text('Carl Ancien'), findsOneWidget);
      expect(find.text('Alice Tremblay'), findsNothing);
    });
  });

  group('Retrait d\'un employé', () {
    Future<void> ouvrirDialogue(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('employe_menu_e1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
    }

    testWidgets('le dialogue informe : accès coupé, 24 mois, suppression possible, registres', (tester) async {
      await _ouvrirListe(tester, _Appels());
      await ouvrirDialogue(tester);
      expect(find.text('Retirer cet employé ?'), findsOneWidget);
      expect(find.textContaining('Alice Tremblay sera immédiatement déconnecté'), findsOneWidget);
      expect(find.textContaining('Son NIP est détruit'), findsOneWidget);
      expect(find.textContaining('24 mois'), findsOneWidget);
      expect(find.textContaining('supprimés automatiquement'), findsOneWidget);
      expect(find.textContaining('supprimer sa fiche tout de suite'), findsOneWidget);
      expect(find.textContaining('registres de la compagnie'), findsOneWidget);
    });

    testWidgets('sans toucher au motif : « non-precise » ; confirmation et message', (tester) async {
      final appels = _Appels();
      await _ouvrirListe(tester, appels);
      await ouvrirDialogue(tester);
      expect(find.text('Non précisé'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('employe_confirmer_retrait')));
      await tester.pumpAndSettle();
      expect(appels.faits, hasLength(1));
      expect(appels.faits.single.key, 'retirerAccesEmploye');
      expect(appels.faits.single.value, {'employeeId': 'e1', 'motif': 'non-precise'});
      expect(find.textContaining('n\'a plus accès'), findsOneWidget);
      expect(find.textContaining('Anciens employés'), findsWidgets);
    });

    testWidgets('le motif choisi dans la liste fermée est envoyé', (tester) async {
      for (final entree in motifsRetrait.entries.where((e) => e.key != 'non-precise')) {
        final appels = _Appels();
        await _ouvrirListe(tester, appels);
        await ouvrirDialogue(tester);
        await tester.tap(find.byKey(const ValueKey('employe_motif_retrait')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entree.value).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('employe_confirmer_retrait')));
        await tester.pumpAndSettle();
        expect(appels.faits.single.value['motif'], entree.key, reason: entree.value);
      }
    });

    testWidgets('le motif est une liste : aucun champ de texte libre dans le dialogue', (tester) async {
      await _ouvrirListe(tester, _Appels());
      await ouvrirDialogue(tester);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), findsNothing);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), findsNothing);
    });

    testWidgets('Annuler : aucun appel', (tester) async {
      final appels = _Appels();
      await _ouvrirListe(tester, appels);
      await ouvrirDialogue(tester);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(appels.faits, isEmpty);
    });

    testWidgets('refus du serveur : message d\'erreur, la liste reste', (tester) async {
      final appels = _Appels()..erreur = Exception('refus');
      await _ouvrirListe(tester, appels);
      await ouvrirDialogue(tester);
      await tester.tap(find.byKey(const ValueKey('employe_confirmer_retrait')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erreur de réseau'), findsOneWidget);
      expect(find.text('Alice Tremblay'), findsOneWidget);
    });
  });

  group('Écran « Anciens employés »', () {
    testWidgets('seulement les anciens : retrait, suppression automatique, motif', (tester) async {
      await _ouvrirAnciens(tester, _Appels());
      expect(find.text('Carl Ancien'), findsOneWidget);
      expect(find.text('Dina Ancienne'), findsOneWidget);
      expect(find.text('Alice Tremblay'), findsNothing);
      expect(find.text('Zoé Proprio'), findsNothing);
      expect(find.textContaining('Retiré le 01/03/2026 • Employé saisonnier'), findsOneWidget);
      expect(find.textContaining('Suppression automatique le 01/03/2028'), findsOneWidget);
      expect(find.textContaining('carl@exemple.ca'), findsOneWidget);
      // Une valeur hors liste n'est jamais affichée telle quelle.
      expect(find.textContaining('Retiré le 15/09/2026 • Non précisé'), findsOneWidget);
      expect(find.textContaining('maladie'), findsNothing);
      expect(find.textContaining('cancer'), findsNothing);
    });

    testWidgets('le plus récemment retiré en premier', (tester) async {
      await _ouvrirAnciens(tester, _Appels());
      final dina = tester.getTopLeft(find.byKey(const ValueKey('ancien_e4'))).dy;
      final carl = tester.getTopLeft(find.byKey(const ValueKey('ancien_e3'))).dy;
      expect(dina, lessThan(carl));
    });

    testWidgets('explication : 24 mois, puis suppression automatique', (tester) async {
      await _ouvrirAnciens(tester, _Appels());
      expect(find.byKey(const ValueKey('anciens_explication')), findsOneWidget);
      expect(find.textContaining('24 mois'), findsOneWidget);
    });

    testWidgets('personne : message vide', (tester) async {
      await _ouvrirAnciens(tester, _Appels(), fiches: [_fiches().first]);
      expect(find.byKey(const ValueKey('anciens_vide')), findsOneWidget);
    });

    testWidgets('réactiver : confirmation, appel, message', (tester) async {
      final appels = _Appels()..reponse = {'id': 'e3', 'courrielEnvoye': true};
      await _ouvrirAnciens(tester, appels);
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réactiver'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lien pour créer un nouveau NIP'), findsOneWidget);
      expect(find.textContaining('L\'ancien NIP n\'est pas conservé'), findsOneWidget);
      expect(appels.faits, isEmpty, reason: 'rien avant la confirmation');
      await tester.tap(find.byKey(const ValueKey('ancien_confirmer_reactivation')));
      await tester.pumpAndSettle();
      expect(appels.faits.single.key, 'reactiverEmploye');
      expect(appels.faits.single.value, {'employeeId': 'e3'});
      expect(find.textContaining('Carl Ancien est réactivé'), findsOneWidget);
    });

    testWidgets('réactiver : courriel impossible → le lien de secours est montré', (tester) async {
      final appels = _Appels()
        ..reponse = {
          'id': 'e3',
          'courrielEnvoye': false,
          'lienInvitation': 'https://exemple.test/creer#e=e3&t=jeton',
        };
      await _ouvrirAnciens(tester, appels);
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réactiver'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ancien_confirmer_reactivation')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Courriel non envoyé'), findsOneWidget);
      expect(find.textContaining('https://exemple.test/creer'), findsOneWidget);
    });

    testWidgets('réactiver : annuler n\'appelle rien ; une erreur affiche son message', (tester) async {
      final appels = _Appels();
      await _ouvrirAnciens(tester, appels);
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réactiver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(appels.faits, isEmpty);

      appels.erreur = Exception('refus');
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réactiver'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ancien_confirmer_reactivation')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Erreur de réseau'), findsOneWidget);
    });

    testWidgets('supprimer la fiche : avertissement d\'irréversibilité, puis suppression', (tester) async {
      final appels = _Appels();
      await _ouvrirAnciens(tester, appels);
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer la fiche maintenant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('irréversible'), findsOneWidget);
      expect(find.textContaining('registres de la compagnie'), findsOneWidget);
      expect(appels.faits, isEmpty);
      await tester.tap(find.byKey(const ValueKey('ancien_confirmer_suppression')));
      await tester.pumpAndSettle();
      expect(appels.faits.single.key, 'supprimerEmploye');
      expect(appels.faits.single.value, {'employeeId': 'e4'});
      expect(find.text('Fiche supprimée.'), findsOneWidget);
    });

    testWidgets('supprimer : annuler n\'appelle rien', (tester) async {
      final appels = _Appels();
      await _ouvrirAnciens(tester, appels);
      await tester.tap(find.byKey(const ValueKey('ancien_menu_e4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer la fiche maintenant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(appels.faits, isEmpty);
    });
  });
}
