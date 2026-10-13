import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chantier.dart';
import '../models/employee.dart';
import '../models/liste_achats.dart';
import '../models/materiel_general.dart';

/// Accès aux données du matériel « Général » (admin) : les demandes de tous les
/// contremaîtres et admins, ce que l'admin a déjà vu ou marqué « non lu », et ses
/// actions. Une interface pour que les écrans se testent sans Firebase.
abstract class SourceMaterielGeneral {
  /// Toutes les demandes Général de la compagnie, en direct.
  Stream<List<EntreeMateriel>> entrees(String companyId);

  /// Ce que [employeId] a vu et ce qu'il a marqué « non lu », en direct. Une
  /// erreur de lecture donne « rien de vu » plutôt que de bloquer l'écran.
  Stream<VisitesGeneral> visites(String employeId);

  /// Note que [employeId] vient de voir la liste de [auteurId] ; [idsALever] :
  /// les demandes dont le drapeau « non lu » tombe (celles du groupe ouvert).
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
    Iterable<String> idsALever = const [],
  });

  /// Marque ces demandes « non lu » pour [employeId] (appui long).
  Future<void> marquerNonLu({
    required String companyId,
    required String employeId,
    required Iterable<String> entreeIds,
  });

  /// Marque une demande comme obtenue (achetée) ou la remet comme manquante.
  Future<void> definirObtenue(
    EntreeMateriel entree,
    bool obtenue, {
    required String employeId,
  });

  Future<void> supprimer(EntreeMateriel entree);

  /// Transfère la demande à la Liste d'achats : crée l'article et marque la demande
  /// « transférée », d'un seul geste (tout ou rien). La demande reste visible pour son
  /// auteur jusqu'à ce qu'elle soit marquée faite.
  Future<void> transfererAuxAchats(EntreeMateriel entree, Employee admin);
}

class SourceMaterielGeneralFirestore implements SourceMaterielGeneral {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _visites(String employeId) =>
      _db.collection('materiel_general_vus').doc(employeId);

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
  Stream<VisitesGeneral> visites(String employeId) =>
      _visites(employeId)
          .snapshots()
          .map((d) => visitesDepuisDonnees(d.data()))
          .handleError((_) {});

  @override
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
    Iterable<String> idsALever = const [],
  }) {
    final ids = idsALever.toList();
    return _visites(employeId).set({
      'companyId': companyId,
      'vus': {cleVu(auteurId): FieldValue.serverTimestamp()},
      if (ids.isNotEmpty)
        'nonLus': {for (final id in ids) id: FieldValue.delete()},
    }, SetOptions(merge: true));
  }

  @override
  Future<void> marquerNonLu({
    required String companyId,
    required String employeId,
    required Iterable<String> entreeIds,
  }) => _visites(employeId).set({
    'companyId': companyId,
    'nonLus': {for (final id in entreeIds) id: true},
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

  @override
  Future<void> transfererAuxAchats(EntreeMateriel entree, Employee admin) {
    final lot = _db.batch();
    lot.set(
      _db.collection('liste_achats').doc(),
      donneesTransfert(entree, admin),
    );
    lot.update(
      _db.collection('chantier_materiel').doc(entree.id),
      donneesMarquerTransfert(admin),
    );
    return lot.commit();
  }
}
