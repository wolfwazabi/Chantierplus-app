import 'dart:io';

/// Supprime le fichier s'il existe ; ne lève jamais d'erreur.
Future<void> supprimerFichier(String chemin) async {
  try {
    final f = File(chemin);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
