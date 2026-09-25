import 'package:cloud_functions/cloud_functions.dart';

/// Accès aux Cloud Functions, hébergées à Montréal.
///
/// Les anciennes versions de l'app appellent us-central1 (région par défaut) ;
/// les fonctions dont elles ont besoin y restent déployées en parallèle.
class Fonctions {
  static const region = 'northamerica-northeast1';

  static FirebaseFunctions get instance =>
      FirebaseFunctions.instanceFor(region: region);

  static Future<Map<String, dynamic>> appeler(
    String nom, [
    Map<String, dynamic>? donnees,
  ]) async {
    final resultat = await instance.httpsCallable(nom).call(donnees);
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
