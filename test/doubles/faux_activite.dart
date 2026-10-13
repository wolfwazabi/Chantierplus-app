import 'package:construction_app/models/activite.dart';
import 'package:construction_app/services/activite_source.dart';

/// Un fil « Activité » en mémoire pour les tests, sans Firestore.
class SourceActiviteFausse implements SourceActivite {
  List<Activite> activites;
  DateTime? vus;

  /// Ce que l'écran a enregistré comme « vu ».
  final List<({String employeId, String companyId, DateTime jusqua})> marques =
      [];

  /// Nombre d'écoutes ouvertes sur le fil (pour vérifier l'actualisation).
  int ecoutes = 0;

  SourceActiviteFausse({this.activites = const [], this.vus});

  @override
  Stream<List<Activite>> evenements(String companyId) => Stream.multi((c) {
    ecoutes++;
    c.add(activites);
  });

  @override
  Stream<DateTime?> vuJusqua(String employeId) =>
      Stream.multi((c) => c.add(vus));

  @override
  Future<void> marquerVu({
    required String employeId,
    required String companyId,
    required DateTime jusqua,
  }) async {
    marques.add((employeId: employeId, companyId: companyId, jusqua: jusqua));
    vus = jusqua;
  }
}
