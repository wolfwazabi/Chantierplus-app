import 'package:cloud_functions/cloud_functions.dart';

/// Accès aux Cloud Functions, hébergées à Montréal (comme la base Firestore).
class Fonctions {
  static const region = 'northamerica-northeast1';

  static FirebaseFunctions get instance =>
      FirebaseFunctions.instanceFor(region: region);

  static Future<Map<String, dynamic>> appeler(
    String nom, [
    Map<String, dynamic>? donnees,
  ]) => appelerAvecDelai(nom, donnees, const Duration(seconds: 60));

  /// Pour les fonctions longues (suppression d'une compagnie : jusqu'à 9 min
  /// côté serveur) : le délai par défaut de 60 s couperait l'attente du client
  /// alors que le serveur poursuit son travail.
  static Future<Map<String, dynamic>> appelerAvecDelai(
    String nom,
    Map<String, dynamic>? donnees,
    Duration delai,
  ) async {
    final resultat = await instance
        .httpsCallable(nom, options: HttpsCallableOptions(timeout: delai))
        .call(donnees);
    final data = resultat.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Message à afficher pour une erreur de fonction (déjà rédigé côté serveur).
  static String message(
    Object erreur, [
    String defaut = 'Une erreur est survenue. Réessayez.',
  ]) {
    if (erreur is FirebaseFunctionsException) {
      // « internal » : erreur imprévue côté serveur, message non destiné à l'usager.
      if (erreur.code == 'internal') return defaut;
      return erreur.message?.isNotEmpty == true ? erreur.message! : defaut;
    }
    return 'Erreur de réseau. Vérifiez votre connexion et réessayez.';
  }
}
