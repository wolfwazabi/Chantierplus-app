import 'package:construction_app/models/regles_paie.dart';
import 'package:construction_app/screens/admin/regles_paie_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppSession.reglesPaie.value = ReglesPaie.defaut);

  Future<void> ouvrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReglesPaieScreen()));
  }

  String texte(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(ValueKey(cle))).data!;

  testWidgets('défaut : 7 h 45 payées, voyagement désactivé et masqué', (
    tester,
  ) async {
    await ouvrir(tester);
    expect(texte(tester, 'exemple_journee'), contains('7 h 45'));
    expect(find.byKey(const ValueKey('voyagement_seuil_valeur')), findsNothing);
    // Rien de modifié : enregistrement désactivé.
    final bouton = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('enregistrer_regles')),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('activer le voyagement affiche seuil et pourcentage', (
    tester,
  ) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('voyagement_actif')));
    await tester.pump();
    expect(texte(tester, 'voyagement_seuil_valeur'), '60 min / jour');
    expect(texte(tester, 'voyagement_pourcentage_valeur'), '50 %');
    // 2 h de voyagement, seuil 60 min : 1 h au-delà du seuil, payée à 50 %.
    expect(
      texte(tester, 'exemple_voyagement'),
      'Exemple : 2 h de voyagement → 1 h au-delà du seuil, payées à 50 % = 0 h 30.',
    );
    expect(
      find.byKey(const ValueKey('explication_voyagement')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('voyagement_pourcentage_plus')));
    await tester.pump();
    expect(texte(tester, 'voyagement_pourcentage_valeur'), '55 %');
    expect(texte(tester, 'exemple_voyagement'), contains('55 % = 0 h 33'));

    final bouton = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('enregistrer_regles')),
    );
    expect(bouton.onPressed, isNotNull);
  });

  testWidgets('seuil de 30 min : 1 h 30 payée sur 2 h de voyagement', (
    tester,
  ) async {
    AppSession.reglesPaie.value = const ReglesPaie(
      voyagementActif: true,
      voyagementSeuilMinutes: 30,
      voyagementPourcentage: 100,
    );
    await ouvrir(tester);
    expect(
      texte(tester, 'exemple_voyagement'),
      'Exemple : 2 h de voyagement → 1 h 30 au-delà du seuil, payées à 100 % = 1 h 30.',
    );
  });

  testWidgets('seuil de 2 h ou plus : l\'exemple dit « rien »', (tester) async {
    AppSession.reglesPaie.value = const ReglesPaie(
      voyagementActif: true,
      voyagementSeuilMinutes: 120,
    );
    await ouvrir(tester);
    expect(texte(tester, 'exemple_voyagement'), contains('rien'));
  });

  testWidgets(
    'semaines : la semaine courante s\'ajuste, les précédentes ne changent jamais',
    (tester) async {
      await ouvrir(tester);
      expect(
        texte(tester, 'texte_semaines'),
        contains('les semaines précédentes ne changent jamais'),
      );
      expect(texte(tester, 'aide_recalcul'), contains('ne sont jamais modifiées'));
      // Rien de modifié et pas de session admin : le bouton existe, aucun appel.
      expect(find.byKey(const ValueKey('recalculer_semaine')), findsOneWidget);
    },
  );

  testWidgets('recalcul : désactivé tant que les règles ne sont pas enregistrées', (
    tester,
  ) async {
    await ouvrir(tester);
    OutlinedButton recalcul() => tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('recalculer_semaine')),
    );
    expect(recalcul().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('voyagement_actif')));
    await tester.pump();
    // Règles modifiées mais pas enregistrées : on enregistre d'abord.
    expect(recalcul().onPressed, isNull);
  });

  testWidgets('pause payée : la journée compte 8 h', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.byKey(const ValueKey('pause_payee')));
    await tester.pump();
    expect(texte(tester, 'exemple_journee'), contains('8 h payées'));
  });

  testWidgets('bornes : pas sous 0 ni au-dessus du maximum', (tester) async {
    AppSession.reglesPaie.value = const ReglesPaie(
      pauseMatinMinutes: 0,
      pauseMatinPayee: false,
      dinerMinutes: ReglesPaie.maxMinutesPause,
      dinerPaye: true,
      voyagementActif: true,
      voyagementSeuilMinutes: 60,
      voyagementPourcentage: ReglesPaie.maxPourcentage,
    );
    await ouvrir(tester);
    IconButton bouton(String cle) =>
        tester.widget<IconButton>(find.byKey(ValueKey(cle)));
    expect(bouton('pause_minutes_moins').onPressed, isNull);
    expect(bouton('diner_minutes_plus').onPressed, isNull);
    expect(bouton('voyagement_pourcentage_plus').onPressed, isNull);
  });
}
