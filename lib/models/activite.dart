import 'package:cloud_firestore/cloud_firestore.dart';

import 'chantier.dart';

/// Ce que l'admin suit dans le fil « Activité ».
enum TypeActivite { heures, photo, materiel, travaux, extra, document, achat }

extension LibelleTypeActivite on TypeActivite {
  String get libelle => switch (this) {
    TypeActivite.heures => 'Heures',
    TypeActivite.photo => 'Photos',
    TypeActivite.materiel => 'Matériel',
    TypeActivite.travaux => 'Travaux',
    TypeActivite.extra => 'Extras',
    TypeActivite.document => 'Documents',
    TypeActivite.achat => 'Achats',
  };
}

/// Un changement : qui, quoi, où, quand.
class Activite {
  /// Identifiant unique : « photo:abc123 ».
  final String id;
  final TypeActivite type;
  final DateTime date;

  /// Qui a fait le geste ('' si l'ancienne version de l'application ne le disait pas).
  final String acteurId;
  final String acteurNom;
  final String chantierId;
  final String chantierNom;

  /// Heures : le nom de l'employé à qui appartient la feuille.
  final String sujetId;
  final String sujetNom;

  /// Heures : la feuille vient d'être créée (« Heures entrées ») ou modifiée.
  final bool modification;

  /// Précision affichée sous la phrase : le texte du matériel, le nom du document…
  final String detail;

  const Activite({
    required this.id,
    required this.type,
    required this.date,
    this.acteurId = '',
    this.acteurNom = '',
    this.chantierId = '',
    this.chantierNom = '',
    this.sujetId = '',
    this.sujetNom = '',
    this.modification = false,
    this.detail = '',
  });

  Activite avecChantierNom(String nom) => Activite(
    id: id,
    type: type,
    date: date,
    acteurId: acteurId,
    acteurNom: acteurNom,
    chantierId: chantierId,
    chantierNom: nom,
    sujetId: sujetId,
    sujetNom: sujetNom,
    modification: modification,
    detail: detail,
  );
}

String _texte(Object? v) => v is String ? v.trim() : '';

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

/// « 2026-10-12 » → « 12/10 ».
String _jourCourt(String iso) {
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? iso : '${m[2]}/${m[1]}';
}

/// Les changements décrits par un document, ou null s'il n'a pas (encore) de date
/// (écriture en cours).
class FabriqueActivite {
  const FabriqueActivite._();

  static Activite? photo(String id, Map<String, dynamic> d) {
    final date = _date(d['dateAjout']);
    if (date == null) return null;
    return Activite(
      id: 'photo:$id',
      type: TypeActivite.photo,
      date: date,
      acteurId: _texte(d['ajoutePar']),
      acteurNom: _texte(d['ajouteParNom']),
      chantierId: _texte(d['chantierId']),
    );
  }

  /// Matériel (un chantier ou Général) et travaux : une demande ajoutée.
  static Activite? entree(
    TypeActivite type,
    String id,
    Map<String, dynamic> d,
  ) {
    final date = _date(d['dateAjout']);
    if (date == null) return null;
    final quantite = _texte(d['quantite']);
    final texte = _texte(d['texte']);
    return Activite(
      id: '${type.name}:$id',
      type: type,
      date: date,
      acteurId: _texte(d['ajoutePar']),
      acteurNom: _texte(d['ajouteParNom']),
      chantierId: _texte(d['chantierId']),
      detail: quantite.isEmpty ? texte : '$texte ($quantite)',
    );
  }

  static Activite? extra(String id, Map<String, dynamic> d) {
    final date = _date(d['dateAjout']);
    if (date == null) return null;
    return Activite(
      id: 'extra:$id',
      type: TypeActivite.extra,
      date: date,
      acteurId: _texte(d['ajoutePar']),
      acteurNom: _texte(d['ajouteParNom']),
      chantierId: _texte(d['chantierId']),
      detail: _texte(d['description']),
    );
  }

  static Activite? document(String id, Map<String, dynamic> d) {
    final date = _date(d['dateAjout']);
    if (date == null) return null;
    return Activite(
      id: 'document:$id',
      type: TypeActivite.document,
      date: date,
      acteurId: _texte(d['ajoutePar']),
      acteurNom: _texte(d['ajouteParNom']),
      chantierId: _texte(d['chantierId']),
      detail: _texte(d['nom']),
    );
  }

  /// Une demande de matériel Général transférée à la Liste d'achats.
  static Activite? achat(String id, Map<String, dynamic> d) {
    final date = _date(d['dateAjout']);
    if (date == null) return null;
    return Activite(
      id: 'achat:$id',
      type: TypeActivite.achat,
      date: date,
      acteurId: _texte(d['transfereParId']),
      acteurNom: _texte(d['transfereParNom']),
      detail: _texte(d['texte']),
    );
  }

  /// Une feuille de temps : créée (« Heures entrées ») ou modifiée, par l'employé lui-même
  /// ou par un admin. Une feuille plus ancienne, sans ces informations, compte comme une
  /// modification par l'employé.
  static Activite? heures(String id, Map<String, dynamic> d) {
    final date = _date(d['dateModification']);
    if (date == null) return null;
    final creeLe = _date(d['creeLe']);
    final employeId = _texte(d['employeeId']);
    final employeNom = _texte(d['employeeNom']);
    final acteurId = _texte(d['modifieParId']);
    final acteurNom = _texte(d['modifieParNom']);
    final lundi = _texte(d['lundiDate']);
    return Activite(
      id: 'heures:$id',
      type: TypeActivite.heures,
      date: date,
      acteurId: acteurId.isNotEmpty ? acteurId : employeId,
      acteurNom: acteurNom.isNotEmpty ? acteurNom : employeNom,
      sujetId: employeId,
      sujetNom: employeNom,
      modification: creeLe == null || creeLe != date,
      detail: [
        if (employeNom.isNotEmpty) employeNom,
        if (lundi.isNotEmpty) 'semaine du ${_jourCourt(lundi)}',
      ].join(' • '),
    );
  }
}

String _par(Activite a) => a.acteurNom.isEmpty ? 'un employé' : a.acteurNom;

String _sur(Activite a) {
  if (a.chantierId == idChantierGeneral) return ' sur Général';
  if (a.chantierNom.isNotEmpty) return ' sur projet ${a.chantierNom}';
  return '';
}

/// La phrase du fil : « Nouvelle photo sur projet Brouillard par Jeremy ».
String phraseActivite(Activite a) {
  switch (a.type) {
    case TypeActivite.heures:
      if (!a.modification) return 'Heures entrées par ${_par(a)}';
      final parAutre =
          a.sujetId.isNotEmpty &&
          a.acteurId.isNotEmpty &&
          a.sujetId != a.acteurId;
      return parAutre
          ? 'Heures de ${a.sujetNom} modifiées par ${_par(a)}'
          : 'Changements apportés aux heures par ${_par(a)}';
    case TypeActivite.photo:
      return 'Nouvelle photo${_sur(a)} par ${_par(a)}';
    case TypeActivite.materiel:
      return 'Nouveau matériel manquant${_sur(a)} par ${_par(a)}';
    case TypeActivite.travaux:
      return 'Nouveau travail à faire${_sur(a)} par ${_par(a)}';
    case TypeActivite.extra:
      return 'Nouvel extra${_sur(a)} par ${_par(a)}';
    case TypeActivite.document:
      return 'Nouveau document${_sur(a)} par ${_par(a)}';
    case TypeActivite.achat:
      return 'Matériel transféré à la Liste d\'achats par ${_par(a)}';
  }
}

/// « 17:10 2026/07/09 » (heure locale).
String dateActivite(DateTime d) {
  final l = d.toLocal();
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${l.hour}:${deux(l.minute)} ${l.year}/${deux(l.month)}/${deux(l.day)}';
}

/// Un changement est « nouveau » s'il date d'après la dernière visite de l'admin et n'est
/// pas de lui. Sans visite enregistrée, rien n'est nouveau (le fil s'initialise).
bool estNouvelle(Activite a, DateTime? vuJusqua, String moiId) =>
    vuJusqua != null &&
    a.date.isAfter(vuJusqua) &&
    (a.acteurId.isEmpty || a.acteurId != moiId);

int nombreNouvelles(
  Iterable<Activite> activites,
  DateTime? vuJusqua,
  String moiId,
) => activites.where((a) => estNouvelle(a, vuJusqua, moiId)).length;

/// Les nouveautés de chaque chantier (identifiant du chantier → nombre). Les changements
/// sans chantier (heures, achats) n'y figurent pas.
Map<String, int> nouvellesParChantier(
  Iterable<Activite> activites,
  DateTime? vuJusqua,
  String moiId,
) {
  final parChantier = <String, int>{};
  for (final a in activites) {
    if (a.chantierId.isNotEmpty && estNouvelle(a, vuJusqua, moiId)) {
      parChantier.update(a.chantierId, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return parChantier;
}

/// Du plus récent au plus ancien, sans doublon, au plus [max] éléments.
List<Activite> ordonnerActivites(
  Iterable<Activite> activites, {
  int max = 150,
}) {
  final vus = <String>{};
  final liste = [
    for (final a in activites)
      if (vus.add(a.id)) a,
  ]..sort((a, b) => b.date.compareTo(a.date));
  return liste.length > max ? liste.sublist(0, max) : liste;
}
