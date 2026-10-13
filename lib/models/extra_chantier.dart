import 'package:cloud_firestore/cloud_firestore.dart';

import 'photos_entree.dart';

/// Extra d'un chantier : travaux supplémentaires effectués (description,
/// main-d'œuvre et temps en texte libre, date, jusqu'à [maxPhotosParEntree] photos).
class ExtraChantier {
  final String id;
  final String companyId;
  final String chantierId;
  final String description;

  /// Texte libre : « 3 gars, 1 compagnon, 1 apprenti — 4 h ».
  final String mainOeuvre;

  /// Date des travaux, « AAAA-MM-JJ ».
  final String dateTravaux;

  /// Les photos (liens) et leurs chemins dans le Storage, dans le même ordre.
  final List<String> photos;
  final List<String> chemins;
  final String ajouteParNom;
  final DateTime? dateAjout;

  const ExtraChantier({
    required this.id,
    required this.companyId,
    required this.chantierId,
    required this.description,
    required this.mainOeuvre,
    required this.dateTravaux,
    this.photos = const [],
    this.chemins = const [],
    this.ajouteParNom = '',
    this.dateAjout,
  });

  factory ExtraChantier.fromFirestore(String id, Map<String, dynamic> data) {
    final ajout = data['dateAjout'];
    final liens = photosDe(data);
    return ExtraChantier(
      id: id,
      companyId: data['companyId'] ?? '',
      chantierId: data['chantierId'] ?? '',
      description: data['description'] ?? '',
      mainOeuvre: data['mainOeuvre'] ?? '',
      dateTravaux: data['dateTravaux'] ?? '',
      photos: liens,
      chemins: cheminsPhotosDe(data, liens.length),
      ajouteParNom: data['ajouteParNom'] ?? '',
      dateAjout: ajout is Timestamp ? ajout.toDate() : null,
    );
  }

  /// La première photo (la vignette).
  String? get photoUrl => photos.isEmpty ? null : photos.first;

  /// Le chemin de la photo [url] dans le Storage (null si inconnu).
  String? cheminDe(String url) {
    final i = photos.indexOf(url);
    return i < 0 || i >= chemins.length || chemins[i].isEmpty
        ? null
        : chemins[i];
  }
}

/// Les chemins Storage des photos d'un extra, alignés sur ses liens : `cheminsPhotos`
/// (toutes) ou, pour un ancien extra, le seul `cheminPhoto` ; '' si inconnu.
List<String> cheminsPhotosDe(Map<String, dynamic> data, int nombre) {
  final liste = data['cheminsPhotos'];
  if (liste is List && liste.length == nombre) {
    return [for (final c in liste) c is String ? c : ''];
  }
  final un = data['cheminPhoto'];
  return [for (var i = 0; i < nombre; i++) i == 0 && un is String ? un : ''];
}

/// Champs Firestore des photos d'un extra : la première (`photoUrl`, `cheminPhoto`,
/// pour l'export et les anciennes versions) et toutes (`photoUrls`, `cheminsPhotos`).
Map<String, dynamic> champsPhotosExtra(
  List<String> urls,
  List<String> chemins,
) {
  final n = urls.length < chemins.length ? urls.length : chemins.length;
  final u = urls.take(n).take(maxPhotosParEntree).toList();
  final c = chemins.take(u.length).toList();
  if (u.isEmpty) return const {};
  return {
    'photoUrl': u.first,
    'cheminPhoto': c.first,
    'photoUrls': u,
    'cheminsPhotos': c,
  };
}

/// Même chose pour une modification : une liste vide retire toutes les photos.
Map<String, dynamic> champsPhotosExtraModification(
  List<String> urls,
  List<String> chemins,
) {
  if (urls.isEmpty) {
    return {
      'photoUrl': FieldValue.delete(),
      'cheminPhoto': FieldValue.delete(),
      'photoUrls': FieldValue.delete(),
      'cheminsPhotos': FieldValue.delete(),
    };
  }
  return champsPhotosExtra(urls, chemins);
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
