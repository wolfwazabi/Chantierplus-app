import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chantier.dart';
import '../models/materiel_general.dart';

/// Accès aux données du matériel « Général » (admin) : les demandes de tous les
/// contremaîtres et admins, ce que l'admin a déjà vu, et ses actions. Une
/// interface pour que les écrans se testent sans Firebase.
abstract class SourceMaterielGeneral {
  /// Toutes les demandes Général de la compagnie, en direct.
  Stream<List<EntreeMateriel>> entrees(String companyId);

  /// Dernière visite de [employeId] pour chaque auteur, en direct. Une erreur
  /// de lecture donne « rien de vu » plutôt que de bloquer l'écran.
  Stream<Map<String, DateTime>> vus(String employeId);

  /// Note que [employeId] vient de voir la liste de [auteurId].
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
  });

  /// Marque une demande comme obtenue (achetée) ou la remet comme manquante.
  Future<void> definirObtenue(
    EntreeMateriel entree,
    bool obtenue, {
    required String employeId,
  });

  Future<void> supprimer(EntreeMateriel entree);
}

class SourceMaterielGeneralFirestore implements SourceMaterielGeneral {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Stream<List<EntreeMateriel>> entrees(String companyId) => _db
      .collection('chantier_materiel')
      .where('companyId', isEqualTo: companyId)
      .where('chantierId', isEqualTo: idChantierGeneral)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) EntreeMateriel.fromMap(d.id, d.data())],
      );

  @override
  Stream<Map<String, DateTime>> vus(String employeId) => _db
      .collection('materiel_general_vus')
      .doc(employeId)
      .snapshots()
      .map((d) => vusDepuisDonnees(d.data()))
      .handleError((_) {});

  @override
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
  }) => _db.collection('materiel_general_vus').doc(employeId).set({
    'companyId': companyId,
    'vus': {cleVu(auteurId): FieldValue.serverTimestamp()},
  }, SetOptions(merge: true));

  @override
  Future<void> definirObtenue(
    EntreeMateriel entree,
    bool obtenue, {
    required String employeId,
  }) => _db
      .collection('chantier_materiel')
      .doc(entree.id)
      .update(
        donneesCompletion(
          complete: obtenue,
          general: true,
          modifieParId: employeId,
        ),
      );

  @override
  Future<void> supprimer(EntreeMateriel entree) =>
      _db.collection('chantier_materiel').doc(entree.id).delete();
}
