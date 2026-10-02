import 'package:firebase_core/firebase_core.dart';

/// D'où vient une erreur Firebase : le stockage (fichiers), la base de données
/// ou autre. Sert à dire à l'utilisateur, et à nous, où ça bloque.
String sourceErreurFirebase(FirebaseException e) => switch (e.plugin) {
  'firebase_storage' => 'stockage des fichiers',
  'cloud_firestore' => 'base de données',
  'cloud_functions' => 'serveur',
  _ => e.plugin,
};

/// « stockage des fichiers : unauthorized », « base de données : permission-denied ».
String detailErreurFirebase(Object e) {
  if (e is FirebaseException) {
    return '${sourceErreurFirebase(e)} : ${e.code}';
  }
  return e.runtimeType.toString();
}

/// Refus d'accès (règles de sécurité) plutôt qu'une panne de réseau.
bool estRefusFirebase(Object e) =>
    e is FirebaseException &&
    (e.code == 'unauthorized' || e.code == 'permission-denied');
