import 'package:cloud_firestore/cloud_firestore.dart';

import 'employee.dart';
import 'materiel_general.dart';
import 'photos_entree.dart';

/// Un article de la Liste d'achats (Admin → Liste d'achats) : une demande de
/// matériel Général qu'un admin a transférée pour qu'elle soit achetée.
/// Garde qui l'a demandée (équipe) et qui l'a transférée.
class ArticleAchat {
  final String id;
  final String texte;
  final String quantite;

  /// Toutes les photos de la demande d'origine.
  final List<String> photos;
  final String demandeParId;
  final String demandeParNom;
  final String transfereParNom;
  final bool complete;
  final DateTime? dateAjout;
  final DateTime? dateComplete;

  /// La demande de matériel Général d'où vient l'article ('' si inconnue).
  final String origineId;

  const ArticleAchat({
    required this.id,
    required this.texte,
    this.quantite = '',
    this.photos = const [],
    this.demandeParId = '',
    this.demandeParNom = '',
    this.transfereParNom = '',
    this.complete = false,
    this.dateAjout,
    this.dateComplete,
    this.origineId = '',
  });

  factory ArticleAchat.fromMap(String id, Map<String, dynamic> d) {
    String texteDe(Object? v) => v is String ? v : '';
    DateTime? dateDe(Object? v) => v is Timestamp
        ? v.toDate()
        : (v is DateTime ? v : null);
    return ArticleAchat(
      id: id,
      texte: texteDe(d['texte']),
      quantite: d['quantite'] == null ? '' : d['quantite'].toString(),
      photos: photosDe(d),
      demandeParId: texteDe(d['demandeParId']),
      demandeParNom: texteDe(d['demandeParNom']),
      transfereParNom: texteDe(d['transfereParNom']),
      complete: d['complete'] == true,
      dateAjout: dateDe(d['dateAjout']),
      dateComplete: dateDe(d['dateComplete']),
      origineId: texteDe(d['origineId']),
    );
  }

  /// La première photo (la vignette).
  String? get photoUrl => photos.isEmpty ? null : photos.first;
}

const String nomDemandeurInconnu = 'Demandeur inconnu';

/// Le nom à afficher pour un demandeur (équipe).
String nomDemandeur(ArticleAchat a) =>
    a.demandeParNom.isNotEmpty ? a.demandeParNom : nomDemandeurInconnu;

/// Données du nouvel article quand [admin] transfère la demande [e] à la Liste
/// d'achats (les règles Firestore exigent exactement ces champs).
Map<String, dynamic> donneesTransfert(EntreeMateriel e, Employee admin) => {
  'companyId': admin.companyId,
  'texte': e.texte,
  if (e.quantite.isNotEmpty) 'quantite': e.quantite,
  ...champsPhotos(e.photos),
  'demandeParId': e.auteurId,
  'demandeParNom': e.auteurNom,
  'transfereParId': admin.id,
  'transfereParNom': admin.nom,
  'origine': 'general',
  'origineId': e.id,
  'complete': false,
  'dateAjout': FieldValue.serverTimestamp(),
};

/// Les articles regroupés par demandeur (équipe), à acheter d'abord.
class GroupeDemandeur {
  final String demandeParId;
  final String nom;
  final List<ArticleAchat> articles;
  const GroupeDemandeur({
    required this.demandeParId,
    required this.nom,
    required this.articles,
  });
}

int _recents(ArticleAchat a, ArticleAchat b) {
  final da = a.dateAjout;
  final db = b.dateAjout;
  if (da == null && db == null) return 0;
  if (da == null) return -1;
  if (db == null) return 1;
  return db.compareTo(da);
}

/// Articles encore à acheter, séparés par demandeur (ordre alphabétique), le plus
/// récent d'abord dans chaque groupe.
List<GroupeDemandeur> grouperParDemandeur(List<ArticleAchat> articles) {
  final parId = <String, List<ArticleAchat>>{};
  for (final a in articles.where((a) => !a.complete)) {
    (parId[a.demandeParId] ??= []).add(a);
  }
  final groupes = [
    for (final e in parId.entries)
      GroupeDemandeur(
        demandeParId: e.key,
        nom: nomDemandeur(e.value.firstWhere((a) => a.demandeParNom.isNotEmpty, orElse: () => e.value.first)),
        articles: [...e.value]..sort(_recents),
      ),
  ];
  groupes.sort((a, b) {
    final c = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
    return c != 0 ? c : a.demandeParId.compareTo(b.demandeParId);
  });
  return groupes;
}

/// Articles déjà achetés, le plus récemment achetés d'abord.
List<ArticleAchat> articlesAchetes(List<ArticleAchat> articles) {
  final liste = articles.where((a) => a.complete).toList();
  liste.sort((a, b) {
    final da = a.dateComplete ?? a.dateAjout;
    final db = b.dateComplete ?? b.dateAjout;
    if (da == null && db == null) return 0;
    if (da == null) return -1;
    if (db == null) return 1;
    return db.compareTo(da);
  });
  return liste;
}
