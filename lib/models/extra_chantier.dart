import 'package:cloud_firestore/cloud_firestore.dart';

/// Extra d'un chantier : travaux supplémentaires effectués (description,
/// main-d'œuvre et temps en texte libre, date, photo facultative).
class ExtraChantier {
  final String id;
  final String companyId;
  final String chantierId;
  final String description;

  /// Texte libre : « 3 gars, 1 compagnon, 1 apprenti — 4 h ».
  final String mainOeuvre;

  /// Date des travaux, « AAAA-MM-JJ ».
  final String dateTravaux;
  final String? photoUrl;
  final String? cheminPhoto;
  final String ajouteParNom;
  final DateTime? dateAjout;

  const ExtraChantier({
    required this.id,
    required this.companyId,
    required this.chantierId,
    required this.description,
    required this.mainOeuvre,
    required this.dateTravaux,
    this.photoUrl,
    this.cheminPhoto,
    this.ajouteParNom = '',
    this.dateAjout,
  });

  factory ExtraChantier.fromFirestore(String id, Map<String, dynamic> data) {
    final ajout = data['dateAjout'];
    return ExtraChantier(
      id: id,
      companyId: data['companyId'] ?? '',
      chantierId: data['chantierId'] ?? '',
      description: data['description'] ?? '',
      mainOeuvre: data['mainOeuvre'] ?? '',
      dateTravaux: data['dateTravaux'] ?? '',
      photoUrl: data['photoUrl'] as String?,
      cheminPhoto: data['cheminPhoto'] as String?,
      ajouteParNom: data['ajouteParNom'] ?? '',
      dateAjout: ajout is Timestamp ? ajout.toDate() : null,
    );
  }
}

/// Longueurs maximales (mêmes bornes que firestore.rules).
const int maxDescription = 2000;
const int maxMainOeuvre = 300;

String dateIso(DateTime d) {
  final a = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final j = d.day.toString().padLeft(2, '0');
  return '$a-$m-$j';
}

/// « 2026-10-01 » → « 01/10/2026 » ; texte inchangé s'il n'est pas une date.
String dateAffichee(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? iso : '${m[3]}/${m[2]}/${m[1]}';
}

DateTime? lireDateIso(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return null;
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return dateIso(d) == iso ? d : null;
}
