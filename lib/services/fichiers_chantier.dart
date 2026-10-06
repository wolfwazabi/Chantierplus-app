import 'package:cloud_firestore/cloud_firestore.dart';

import 'stockage.dart';

/// Une photo ou un document de chantier : sa fiche Firestore et, s'il y en a un,
/// son fichier dans le Storage.
class ElementChantier {
  final String id;
  final String? cheminStorage;
  const ElementChantier(this.id, this.cheminStorage);
}

class ResultatSuppression {
  final int supprimes;
  final int echecs;
  const ResultatSuppression(this.supprimes, this.echecs);

  bool get toutSupprime => echecs == 0;
}

typedef SupprimerFichier = Future<void> Function(String chemin);
typedef SupprimerFiche = Future<void> Function(String collection, String id);

/// Collections dont l'admin peut supprimer les éléments depuis le dossier.
const collectionsSupprimables = {'chantier_photos', 'chantier_documents'};

Future<void> _supprimerFichierStorage(String chemin) =>
    Stockage.instance.ref(chemin).delete();

Future<void> _supprimerFicheFirestore(String collection, String id) =>
    FirebaseFirestore.instance.collection(collection).doc(id).delete();

/// Supprime des photos ou des documents de chantier, un à un.
///
/// Le fichier part d'abord : s'il ne peut pas être supprimé (réseau, droits),
/// la fiche reste et l'admin peut réessayer. Dans l'ordre inverse, une copie
/// resterait accessible par son lien sans plus apparaître dans l'application.
/// Un fichier déjà absent du Storage n'est pas une erreur. Un échec sur un
/// élément n'empêche pas de traiter les suivants.
Future<ResultatSuppression> supprimerElementsChantier(
  String collection,
  Iterable<ElementChantier> elements, {
  SupprimerFichier? supprimerFichier,
  SupprimerFiche? supprimerFiche,
}) async {
  if (!collectionsSupprimables.contains(collection)) {
    throw ArgumentError.value(collection, 'collection');
  }
  final fichier = supprimerFichier ?? _supprimerFichierStorage;
  final fiche = supprimerFiche ?? _supprimerFicheFirestore;
  var supprimes = 0;
  var echecs = 0;
  for (final e in elements) {
    try {
      final chemin = e.cheminStorage;
      if (chemin != null && chemin.isNotEmpty) {
        try {
          await fichier(chemin);
        } on FirebaseException catch (err) {
          if (err.code != 'object-not-found') rethrow;
        }
      }
      await fiche(collection, e.id);
      supprimes++;
    } catch (_) {
      echecs++;
    }
  }
  return ResultatSuppression(supprimes, echecs);
}

/// Message pour l'admin après une suppression. [singulier] et [pluriel] sont
/// des participes accordés : « photo supprimée » / « photos supprimées ».
String messageSuppression(
  ResultatSuppression r, {
  required String singulier,
  required String pluriel,
}) {
  if (r.supprimes == 0 && r.echecs == 0) return 'Rien à supprimer.';
  if (r.toutSupprime) {
    return r.supprimes == 1 ? '1 $singulier.' : '${r.supprimes} $pluriel.';
  }
  if (r.supprimes == 0) {
    return 'Suppression impossible. Vérifiez votre connexion et réessayez.';
  }
  final faits = r.supprimes == 1 ? '1 $singulier' : '${r.supprimes} $pluriel';
  final nonFaits = r.echecs == 1
      ? '1 n\'a pas pu l\'être'
      : '${r.echecs} n\'ont pas pu l\'être';
  return '$faits ; $nonFaits. Réessayez.';
}
