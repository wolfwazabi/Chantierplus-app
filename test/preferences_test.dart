import 'package:construction_app/screens/preferences_screen.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => Preferences.unites.value = SystemeUnites.imperial);

  test('par défaut : impérial', () async {
    SharedPreferences.setMockInitialValues({});
    await Preferences.charger();
    expect(Preferences.estMetrique, isFalse);
  });

  test('le choix est enregistré puis relu au démarrage', () async {
    SharedPreferences.setMockInitialValues({});
    await Preferences.choisirUnites(SystemeUnites.metrique);
    Preferences.unites.value = SystemeUnites.imperial; // « redémarrage »
    await Preferences.charger();
    expect(Preferences.estMetrique, isTrue);
  });

  test('valeur enregistrée inconnue : impérial', () async {
    SharedPreferences.setMockInitialValues({'preferences.unites': 'nautique'});
    await Preferences.charger();
    expect(Preferences.estMetrique, isFalse);
  });

  testWidgets('écran Préférences : choisir Métrique puis Impérial', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PreferencesScreen()));
    await tester.tap(find.byKey(const ValueKey('unites_metrique')));
    await tester.pump();
    expect(Preferences.estMetrique, isTrue);
    await tester.tap(find.byKey(const ValueKey('unites_imperial')));
    await tester.pump();
    expect(Preferences.estMetrique, isFalse);
  });
}
