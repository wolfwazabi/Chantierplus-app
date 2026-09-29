import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/widgets/recherche_chantier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tremblay = Chantier(
  id: 'c1',
  companyId: 'A',
  nom: 'Résidence Tremblay',
  adresse: '123, rue Saint-Jérôme, Laval',
);
const condos = Chantier(
  id: 'c2',
  companyId: 'A',
  nom: 'Condos Bellevue',
  adresse: '45 boul. des Laurentides, Laval',
);
const sansAdresse = Chantier(
  id: 'c3',
  companyId: 'A',
  nom: 'Garage Roy',
  adresse: '',
);
const chantiers = [tremblay, condos, sansAdresse];

void main() {
  group('normaliserRecherche', () {
    test('minuscules, sans accents, ponctuation → espaces', () {
      expect(
        normaliserRecherche('123, rue Saint-Jérôme'),
        '123 rue saint jerome',
      );
      expect(normaliserRecherche('  ÇA  ÉTÉ  '), 'ca ete');
      expect(normaliserRecherche('Cœur'), 'coeur');
    });
  });

  group('chantierCorrespond', () {
    test('par nom (partiel, sans accents, sans majuscules)', () {
      expect(chantierCorrespond(tremblay, 'tremb'), isTrue);
      expect(chantierCorrespond(tremblay, 'RESIDENCE'), isTrue);
      expect(chantierCorrespond(condos, 'tremb'), isFalse);
    });

    test('par adresse (numéro, rue, ville)', () {
      expect(chantierCorrespond(tremblay, '123'), isTrue);
      expect(
        chantierCorrespond(tremblay, 'st jerome'),
        isFalse,
        reason: 'pas de devinette d\'abréviations',
      );
      expect(chantierCorrespond(tremblay, 'saint-jerome'), isTrue);
      expect(chantierCorrespond(condos, 'laurentides'), isTrue);
    });

    test(
      'plusieurs mots : tous doivent correspondre, dans n\'importe quel ordre',
      () {
        expect(chantierCorrespond(tremblay, 'laval 123'), isTrue);
        expect(chantierCorrespond(condos, 'laval 123'), isFalse);
        expect(chantierCorrespond(condos, 'bellevue laval'), isTrue);
      },
    );

    test('mélange nom + adresse', () {
      expect(chantierCorrespond(tremblay, 'tremblay laval'), isTrue);
    });

    test('requête vide ou ponctuation seule : tout correspond', () {
      expect(chantierCorrespond(sansAdresse, ''), isTrue);
      expect(chantierCorrespond(sansAdresse, ' , - '), isTrue);
    });
  });

  group('fenêtre de recherche', () {
    Future<Chantier?> ouvrirEtChoisir(
      WidgetTester tester,
      String requete,
      String texteAToucher,
    ) async {
      Chantier? choisi;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoutonRechercheChantier(
              chantiers: chantiers,
              onChoisi: (c) => choisi = c,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bouton_recherche_chantier')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('champ_recherche_chantier')),
        requete,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(texteAToucher));
      await tester.pumpAndSettle();
      return choisi;
    }

    testWidgets('chercher par adresse renvoie le bon chantier', (tester) async {
      final choisi = await ouvrirEtChoisir(
        tester,
        'jerome',
        'Résidence Tremblay',
      );
      expect(choisi?.id, 'c1');
    });

    testWidgets('chercher par nom renvoie le bon chantier', (tester) async {
      final choisi = await ouvrirEtChoisir(
        tester,
        'bellevue',
        'Condos Bellevue',
      );
      expect(choisi?.id, 'c2');
    });

    testWidgets(
      'la liste se filtre : un chantier qui ne correspond pas disparaît',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BoutonRechercheChantier(
                chantiers: chantiers,
                onChoisi: (_) {},
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('bouton_recherche_chantier')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Garage Roy'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('champ_recherche_chantier')),
          'laval',
        );
        await tester.pumpAndSettle();
        expect(find.text('Garage Roy'), findsNothing);
        expect(find.text('Condos Bellevue'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('champ_recherche_chantier')),
          'zzz',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Aucun chantier ne correspond'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Entrée choisit le chantier quand il est le seul résultat', (
      tester,
    ) async {
      Chantier? choisi;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoutonRechercheChantier(
              chantiers: chantiers,
              onChoisi: (c) => choisi = c,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bouton_recherche_chantier')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('champ_recherche_chantier')),
        'roy',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(choisi?.id, 'c3');
    });

    testWidgets('bouton désactivé quand la sélection est verrouillée', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoutonRechercheChantier(chantiers: chantiers, onChoisi: null),
          ),
        ),
      );
      final bouton = tester.widget<IconButton>(
        find.byKey(const ValueKey('bouton_recherche_chantier')),
      );
      expect(bouton.onPressed, isNull);
    });
  });
}
