// Le clavier se ferme en touchant une zone vide, sans gêner les boutons, les champs
// ni les listes.
import 'package:construction_app/widgets/fermer_clavier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FocusNode foyerA;
  late FocusNode foyerB;
  int boutons = 0;
  int tuiles = 0;

  setUp(() {
    foyerA = FocusNode();
    foyerB = FocusNode();
    boutons = 0;
    tuiles = 0;
  });
  tearDown(() {
    foyerA.dispose();
    foyerB.dispose();
  });

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Comme dans l'app : autour de tout l'écran.
        builder: (context, child) => FermerClavier(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: const ValueKey('a'), focusNode: foyerA),
              TextField(key: const ValueKey('b'), focusNode: foyerB),
              ElevatedButton(
                key: const ValueKey('bouton'),
                onPressed: () => boutons++,
                child: const Text('Ajouter'),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      key: const ValueKey('tuile'),
                      title: const Text('Une demande'),
                      onTap: () => tuiles++,
                    ),
                    const SizedBox(height: 600, key: ValueKey('vide')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('toucher une zone vide ferme le clavier (le champ perd le focus)', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    expect(foyerA.hasFocus, isTrue);
    await tester.tapAt(const Offset(400, 500)); // dans la liste, sous les tuiles
    await tester.pump();
    expect(foyerA.hasFocus, isFalse);
  });

  testWidgets('toucher l\'espace vide d\'une liste ferme aussi le clavier', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();
    expect(foyerB.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('vide')));
    await tester.pump();
    expect(foyerB.hasFocus, isFalse);
  });

  testWidgets('un bouton garde son effet', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bouton')));
    await tester.pump();
    expect(boutons, 1);
  });

  testWidgets('une tuile de liste garde son effet', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('tuile')));
    await tester.pump();
    expect(tuiles, 1);
  });

  testWidgets('toucher un autre champ passe le focus à ce champ (pas de clavier fermé puis rouvert)', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pump();
    expect(foyerA.hasFocus, isFalse);
    expect(foyerB.hasFocus, isTrue);
  });

  testWidgets('toucher dans le champ déjà actif le garde actif', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    expect(foyerA.hasFocus, isTrue);
  });

  testWidgets('sans champ actif : un toucher dans le vide ne fait rien de mal', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('vide')));
    await tester.pump();
    expect(foyerA.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('faire défiler la liste ne ferme pas le clavier par erreur de toucher', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    // Un glissement n'est pas un toucher : le champ garde son focus.
    expect(foyerA.hasFocus, isTrue);
  });
}
