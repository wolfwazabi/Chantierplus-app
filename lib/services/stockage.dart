import 'package:firebase_storage/firebase_storage.dart';

/// Stockage des photos et documents : bucket dédié à Montréal
/// (northamerica-northeast1), comme la base Firestore et les fonctions.
///
/// L'ancien bucket par défaut (Caroline du Sud, États-Unis) est verrouillé et
/// vide : ne jamais utiliser `FirebaseStorage.instance` (un test vérifie qu'il
/// n'y en a plus dans le code).
class Stockage {
  static const bucket = 'gs://chantierplus-mtl';

  static FirebaseStorage get instance =>
      FirebaseStorage.instanceFor(bucket: bucket);
}
