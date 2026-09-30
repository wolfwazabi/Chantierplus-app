import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Système d'unités de l'utilisateur.
enum SystemeUnites { imperial, metrique }

/// Préférences personnelles, enregistrées sur l'appareil.
///
/// Un employé se connecte avec un compte anonyme propre à chaque appareil :
/// une préférence stockée localement vaut donc autant qu'une préférence liée
/// au compte, sans règle de sécurité supplémentaire.
class Preferences {
  static const _cleUnites = 'preferences.unites';

  /// Système d'unités courant, écouté par la calculatrice et les calculs.
  static final ValueNotifier<SystemeUnites> unites = ValueNotifier(
    SystemeUnites.imperial,
  );

  static bool get estMetrique => unites.value == SystemeUnites.metrique;

  static const _cleResterConnecte = 'preferences.resterConnecte';

  /// « Rester connecté » : si décoché à la connexion, l'app déconnecte
  /// l'utilisateur à son prochain lancement (téléphone partagé, par exemple).
  /// Coché par défaut.
  static bool resterConnecte = true;

  static Future<void> choisirResterConnecte(bool valeur) async {
    resterConnecte = valeur;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cleResterConnecte, valeur);
    } catch (_) {}
  }

  /// Lit les préférences enregistrées (au démarrage de l'app).
  static Future<void> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      resterConnecte = prefs.getBool(_cleResterConnecte) ?? true;
      unites.value = prefs.getString(_cleUnites) == SystemeUnites.metrique.name
          ? SystemeUnites.metrique
          : SystemeUnites.imperial;
    } catch (_) {
      // Stockage indisponible : on garde l'impérial par défaut.
    }
  }

  static Future<void> choisirUnites(SystemeUnites systeme) async {
    unites.value = systeme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleUnites, systeme.name);
    } catch (_) {}
  }
}
