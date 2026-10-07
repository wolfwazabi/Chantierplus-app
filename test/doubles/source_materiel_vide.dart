import 'package:construction_app/models/materiel_general.dart';
import 'package:construction_app/services/materiel_general_source.dart';

/// Matériel Général sans aucune demande ni visite : pour les tests d'écrans Admin
/// qui ne s'intéressent pas à Général (aucun accès à Firebase).
class SourceMaterielGeneralVide implements SourceMaterielGeneral {
  @override
  Stream<List<EntreeMateriel>> entrees(String companyId) =>
      Stream.value(const <EntreeMateriel>[]);

  @override
  Stream<Map<String, DateTime>> vus(String employeId) =>
      Stream.value(const <String, DateTime>{});

  @override
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
  }) async {}

  @override
  Future<void> definirObtenue(
    EntreeMateriel entree,
    bool obtenue, {
    required String employeId,
  }) async {}

  @override
  Future<void> supprimer(EntreeMateriel entree) async {}
}
