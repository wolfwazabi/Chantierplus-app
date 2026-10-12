import 'package:cloud_firestore/cloud_firestore.dart';

import 'extra_chantier.dart';

/// Motifs de départ : liste FERMÉE, comme sur le serveur (jamais de texte libre : un
/// champ libre recevrait des renseignements de santé, qui sont sensibles ; « absence
/// prolongée » couvre la maladie sans la nommer).
const Map<String, String> motifsRetrait = {
  'non-precise': 'Non précisé',
  'saisonnier': 'Employé saisonnier',
  'depart-volontaire': 'Départ volontaire',
  'fin-contrat': 'Fin de contrat',
  'absence-prolongee': 'Absence prolongée',
  'autre': 'Autre',
};

/// Un employé est actif sauf si sa fiche dit `actif: false` (accès retiré, fiche gardée
/// un temps limité dans « Anciens employés »). Les fiches existantes n'ont pas le champ.
bool employeActif(Map<String, dynamic> donnees) => donnees['actif'] != false;

/// Libellé d'un motif ; une valeur hors liste est ignorée (« Non précisé »).
String libelleMotifRetrait(Object? valeur) =>
    (valeur is String ? motifsRetrait[valeur] : null) ??
    motifsRetrait['non-precise']!;

DateTime? _date(Object? valeur) => valeur is Timestamp ? valeur.toDate() : null;

String _jour(DateTime? d) => d == null ? '—' : dateAffichee(dateIso(d));

/// Fiche d'un ancien employé : le strict nécessaire pour le réactiver.
class AncienEmploye {
  final String id;
  final String nom;
  final String courriel;
  final DateTime? retireLe;
  final DateTime? supprimeApresLe;
  final String motif;

  const AncienEmploye({
    required this.id,
    required this.nom,
    required this.courriel,
    required this.retireLe,
    required this.supprimeApresLe,
    required this.motif,
  });

  factory AncienEmploye.depuis(String id, Map<String, dynamic> donnees) =>
      AncienEmploye(
        id: id,
        nom: donnees['nom'] is String ? donnees['nom'] as String : '',
        courriel: donnees['courriel'] is String
            ? donnees['courriel'] as String
            : '',
        retireLe: _date(donnees['retireLe']),
        supprimeApresLe: _date(donnees['supprimeApresLe']),
        motif: libelleMotifRetrait(donnees['motifRetrait']),
      );

  String get retireLeAffiche => _jour(retireLe);
  String get supprimeApresLeAffiche => _jour(supprimeApresLe);
}

/// Les anciens employés d'une liste de fiches (plus récemment retirés d'abord, puis par nom).
List<AncienEmploye> anciensEmployes(
  Iterable<MapEntry<String, Map<String, dynamic>>> fiches,
) {
  final liste = [
    for (final f in fiches)
      if (!employeActif(f.value)) AncienEmploye.depuis(f.key, f.value),
  ];
  liste.sort((a, b) {
    final ra = a.retireLe;
    final rb = b.retireLe;
    if (ra != null && rb != null && ra != rb) return rb.compareTo(ra);
    if (ra == null && rb != null) return 1;
    if (ra != null && rb == null) return -1;
    return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
  });
  return liste;
}
