import 'package:construction_app/screens/admin/grille_photos_dossier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final photos = [
    for (var i = 1; i <= 5; i++)
      PhotoDossier('p$i', 'https://exemple.invalid/$i.jpg', 'chantiers/A/c/photos/$i.jpg'),
  ];
  late List<List<String>> appels;

  Finder cle(String k) => find.byKey(ValueKey(k));

  Future<void> ouvrir(
    WidgetTester tester, {
    List<PhotoDossier>? liste,
    Future<void> Function(List<PhotoDossier>)? onSupprimer,
  }) async {
    appels = [];
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrillePhotosDossier(
              photos: liste ?? photos,
              onSupprimer:
                  onSupprimer ??
                  (choisies) async => appels.add([for (final p in choisies) p.id]),
            ),
          ),
        ),
      ),
    );
  }

  bool actif(WidgetTester tester, String k) =>
      tester.widget<ButtonStyleButton>(cle(k)).onPressed != null;

  testWidgets('au départ : photos affichées, aucune sélection, rien à supprimer', (
    tester,
  ) async {
    await ouvrir(tester);
    for (final p in photos) {
      expect(cle('photo_${p.id}'), findsOneWidget);
    }
    expect(cle('photos_selectionner'), findsOneWidget);
    expect(cle('photos_supprimer_selection'), findsNothing);
  });

  testWidgets('sélection : appui long puis touches, compteur et bouton à jour', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.longPress(cle('photo_p2'));
    await tester.pump();
    expect(find.text('1 sélectionnée'), findsOneWidget);
    expect(cle('choisie_p2'), findsOneWidget);
    expect(cle('libre_p1'), findsOneWidget);

    await tester.tap(cle('photo_p4'));
    await tester.pump();
    expect(find.text('2 sélectionnées'), findsOneWidget);

    // Toucher une photo choisie la retire.
    await tester.tap(cle('photo_p2'));
    await tester.pump();
    expect(find.text('1 sélectionnée'), findsOneWidget);
    expect(cle('libre_p2'), findsOneWidget);
  });

  testWidgets('« Sélectionner » : rien de choisi, suppression désactivée', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('photos_selectionner'));
    await tester.pump();
    expect(find.text('Touchez les photos à supprimer'), findsOneWidget);
    expect(actif(tester, 'photos_supprimer_selection'), isFalse);
    await tester.tap(cle('photos_annuler_selection'));
    await tester.pump();
    expect(cle('photos_selectionner'), findsOneWidget);
  });

  testWidgets('suppression de plusieurs photos : confirmation, puis seules les photos choisies partent', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.longPress(cle('photo_p1'));
    await tester.pump();
    await tester.tap(cle('photo_p3'));
    await tester.pump();
    await tester.tap(cle('photos_supprimer_selection'));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer ces 2 photos ?'), findsOneWidget);
    expect(find.textContaining('irréversible'), findsOneWidget);
    expect(appels, isEmpty, reason: 'rien ne part avant la confirmation');
    await tester.tap(cle('confirmer_action'));
    await tester.pumpAndSettle();

    expect(appels, [
      ['p1', 'p3'],
    ]);
    // Retour à l'affichage normal.
    expect(cle('photos_selectionner'), findsOneWidget);
  });

  testWidgets('annuler la confirmation : rien n\'est supprimé, la sélection reste', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.longPress(cle('photo_p1'));
    await tester.pump();
    await tester.tap(cle('photos_supprimer_selection'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette photo ?'), findsOneWidget);
    await tester.tap(find.text('Annuler').last);
    await tester.pumpAndSettle();
    expect(appels, isEmpty);
    expect(find.text('1 sélectionnée'), findsOneWidget);
  });

  testWidgets('une photo touchée s\'agrandit ; « Supprimer » demande confirmation', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('photo_p5'));
    await tester.pumpAndSettle();
    expect(cle('photo_supprimer'), findsOneWidget);

    await tester.tap(cle('photo_supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette photo ?'), findsOneWidget);
    expect(appels, isEmpty);
    await tester.tap(cle('confirmer_action'));
    await tester.pumpAndSettle();
    expect(appels, [
      ['p5'],
    ]);
  });

  testWidgets('fermer l\'agrandissement sans supprimer : rien ne part', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(cle('photo_p5'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(cle('photo_supprimer'), findsNothing);
    expect(appels, isEmpty);
  });

  testWidgets('consultation seulement : ni sélection, ni bouton Supprimer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrillePhotosDossier(
              photos: photos,
              peutSupprimer: false,
              colonnes: 3,
              onSupprimer: (_) async => fail('suppression non permise'),
            ),
          ),
        ),
      ),
    );
    expect(cle('photos_selectionner'), findsNothing);
    await tester.longPress(cle('photo_p1'));
    await tester.pump();
    expect(cle('photos_supprimer_selection'), findsNothing);
    // La photo s'agrandit quand même, sans bouton pour la supprimer.
    await tester.tap(cle('photo_p1'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(cle('photo_supprimer'), findsNothing);
  });

  testWidgets('une photo supprimée ailleurs sort de la sélection', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.longPress(cle('photo_p1'));
    await tester.pump();
    await tester.tap(cle('photo_p2'));
    await tester.pump();
    expect(find.text('2 sélectionnées'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrillePhotosDossier(
              photos: photos.where((p) => p.id != 'p1').toList(),
              onSupprimer: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('1 sélectionnée'), findsOneWidget);
  });
}
