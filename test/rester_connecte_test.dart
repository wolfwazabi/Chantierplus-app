import 'package:construction_app/services/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.resterConnecte = true;
  });

  test('« rester connecté » est coché par défaut', () async {
    await Preferences.charger();
    expect(Preferences.resterConnecte, isTrue);
  });

  test('décocher est mémorisé et relu au prochain lancement', () async {
    await Preferences.choisirResterConnecte(false);
    expect(Preferences.resterConnecte, isFalse);

    // Nouveau lancement : la valeur vient du stockage.
    Preferences.resterConnecte = true;
    await Preferences.charger();
    expect(Preferences.resterConnecte, isFalse);

    await Preferences.choisirResterConnecte(true);
    Preferences.resterConnecte = false;
    await Preferences.charger();
    expect(Preferences.resterConnecte, isTrue);
  });
}
