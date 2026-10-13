import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les groupes de réglages repliés de l'onglet affiché (`groupe_…`).
List<String> groupesDeReglages() => [
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w is ExpansionTile &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('groupe_'),
          )
          .evaluate())
    ((e.widget.key! as ValueKey<String>).value),
];

/// Ouvre les groupes de réglages (tous, ou ceux de [cles] sans le préfixe `groupe_`), pour
/// atteindre les champs qu'ils contiennent.
Future<void> deplierReglages(WidgetTester t, [List<String>? cles]) async {
  final aOuvrir = cles == null
      ? groupesDeReglages()
      : [for (final c in cles) 'groupe_$c'];
  for (final cle in aOuvrir) {
    final titre = find
        .descendant(
          of: find.byKey(ValueKey(cle)),
          matching: find.byType(ListTile),
        )
        .first;
    await t.ensureVisible(titre);
    await t.pumpAndSettle();
    await t.tap(titre);
    await t.pumpAndSettle();
  }
}
