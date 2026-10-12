import 'package:cloud_firestore/cloud_firestore.dart';

/// Fiches des employés de la compagnie (identifiant + données), en direct.
typedef FluxFiches = Stream<List<MapEntry<String, Map<String, dynamic>>>>;

/// Appel d'une Cloud Function (remplaçable dans les tests).
typedef AppelFonction =
    Future<Map<String, dynamic>> Function(
      String nom,
      Map<String, dynamic> donnees,
    );

/// Toutes les fiches de la compagnie, anciens employés compris : les écrans filtrent
/// (Firestore ne sait pas chercher un champ absent).
FluxFiches fluxFichesEmployes(String companyId) => FirebaseFirestore.instance
    .collection('employees')
    .where('companyId', isEqualTo: companyId)
    .snapshots()
    .map((s) => [for (final d in s.docs) MapEntry(d.id, d.data())]);
