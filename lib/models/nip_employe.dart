/// Un NIP existe-t-il pour cet employé ? Le serveur tient `nipCree` (le NIP haché, lui, est
/// dans une collection que personne ne peut lire). Pendant la transition, un ancien
/// `pinHash` non vide compte aussi : l'application fonctionne avant, pendant et après la
/// migration.
bool nipCree(Map<String, dynamic> donnees) {
  if (donnees['nipCree'] == true) return true;
  final ancien = donnees['pinHash'];
  return ancien is String && ancien.isNotEmpty;
}
