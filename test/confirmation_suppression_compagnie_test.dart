import 'package:construction_app/screens/admin/confirmation_suppression_compagnie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool? resultat;

  Future<void> ouvrir(WidgetTester tester) async {
    resultat = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('ouvrir'),
                onPressed: () async => resultat =
                    await confirmerSuppressionCompagnie(
                      context,
                      nom: 'Construction Test',
                      numero: '1005',
                    ),
                child: const Text('Supprimer'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ouvrir')));
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(ValueKey(k));

  bool confirmerActif(WidgetTester tester) =>
      tester.widget<FilledButton>(cle('suppression_confirmer')).onPressed !=
      null;

  Future<void> saisir(WidgetTester tester, String texte) async {
    await tester.enterText(cle('suppression_numero'), texte);
    await tester.pump();
  }

  testWidgets('étape 1 : nom, numéro et conséquences, sans rien supprimer encore', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(find.text('Supprimer « Construction Test » ?'), findsOneWidget);
    expect(find.text('Compagnie n° 1005'), findsOneWidget);
    for (final c in consequencesSuppressionCompagnie) {
      expect(find.text('• $c'), findsOneWidget);
    }
    expect(find.textContaining('irréversible'), findsOneWidget);
    // Le numéro n'est pas encore demandé.
    expect(cle('suppression_numero'), findsNothing);
    expect(resultat, isNull);
  });

  testWidgets('annuler à l\'étape 1 : refusé, la 2e étape n\'apparaît pas', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('suppression_annuler_1'));
    await tester.pumpAndSettle();
    expect(resultat, isFalse);
    expect(cle('suppression_numero'), findsNothing);
  });

  testWidgets('étape 2 : le bouton reste désactivé tant que le numéro n\'est pas exact', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('suppression_continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Dernière vérification'), findsOneWidget);
    expect(confirmerActif(tester), isFalse);
    for (final faux in ['', '1', '100', '10055', '1004', '1006', 'abcd', '1 005']) {
      await saisir(tester, faux);
      expect(confirmerActif(tester), isFalse, reason: 'numéro « $faux »');
    }
    // Le nom de la compagnie ne remplace pas son numéro.
    await saisir(tester, 'Construction Test');
    expect(confirmerActif(tester), isFalse);
    expect(resultat, isNull);
  });

  testWidgets('numéro exact (espaces autour tolérés) : la suppression est confirmée', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('suppression_continuer'));
    await tester.pumpAndSettle();
    await saisir(tester, ' 1005 ');
    expect(confirmerActif(tester), isTrue);
    await tester.tap(cle('suppression_confirmer'));
    await tester.pumpAndSettle();
    expect(resultat, isTrue);
  });

  testWidgets('annuler à l\'étape 2 : refusé', (tester) async {
    await ouvrir(tester);
    await tester.tap(cle('suppression_continuer'));
    await tester.pumpAndSettle();
    await saisir(tester, '1005');
    await tester.tap(cle('suppression_annuler_2'));
    await tester.pumpAndSettle();
    expect(resultat, isFalse);
  });

  testWidgets('fermer le dialogue en touchant à côté : refusé', (tester) async {
    await ouvrir(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(resultat, isFalse);
  });
}
