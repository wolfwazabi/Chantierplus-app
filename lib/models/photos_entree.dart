import 'package:cloud_firestore/cloud_firestore.dart';

/// Nombre maximal de photos d'une demande de matériel, d'un travail ou d'un extra.
const int maxPhotosParEntree = 6;

/// Les photos d'un document : `photoUrls` (toutes, dans l'ordre) ou, pour les
/// anciens documents, la seule `photoUrl`.
List<String> photosDe(Map<String, dynamic> d) {
  final liste = d['photoUrls'];
  if (liste is List) {
    final urls = [
      for (final u in liste)
        if (u is String && u.isNotEmpty) u,
    ];
    if (urls.isNotEmpty) return urls;
  }
  final une = d['photoUrl'];
  return une is String && une.isNotEmpty ? [une] : const [];
}

/// Champs Firestore d'une liste de photos : `photoUrl` (la première, pour l'export
/// et les anciennes versions) et `photoUrls` (toutes). Rien si la liste est vide.
Map<String, dynamic> champsPhotos(List<String> urls) {
  final gardees = urls.take(maxPhotosParEntree).toList();
  if (gardees.isEmpty) return const {};
  return {'photoUrl': gardees.first, 'photoUrls': gardees};
}

/// Même chose pour une modification : une liste vide retire toutes les photos.
Map<String, dynamic> champsPhotosModification(List<String> urls) {
  if (urls.isEmpty) {
    return {
      'photoUrl': FieldValue.delete(),
      'photoUrls': FieldValue.delete(),
    };
  }
  return champsPhotos(urls);
}
