// Suppression d'un fichier temporaire (copie faite par le sélecteur de photos).
// dart:io n'existe pas sur le web : import conditionnel.
export 'fichier_temporaire_stub.dart'
    if (dart.library.io) 'fichier_temporaire_io.dart';
