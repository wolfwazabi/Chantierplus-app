import 'package:cloud_firestore/cloud_firestore.dart';

import 'chantier.dart';
import 'employee.dart';

/// Une demande de matériel (collection `chantier_materiel`).
///
/// Pour la liste « Général » (remorque, sans chantier), chaque entrée porte son
/// auteur (contremaître ou admin) et, après un changement, qui l'a fait et quand :
/// la liste se sépare par personne et un admin voit ce qui est nouveau pour lui.
class EntreeMateriel {
  final String id;
  final String texte;
  final String quantite;
  final String? photoUrl;
  final bool complete;

  /// Auteur de la demande ('' si inconnu : entrée sans auteur).
  final String auteurId;
  final String auteurNom;
  final DateTime? dateAjout;
  final DateTime? dateModif;
  final String? modifiePar;
  final DateTime? dateComplete;

  const EntreeMateriel({
    required this.id,
    required this.texte,
    this.quantite = '',
    this.photoUrl,
    this.complete = false,
    this.auteurId = '',
    this.auteurNom = '',
    this.dateAjout,
    this.dateModif,
    this.modifiePar,
    this.dateComplete,
  });

  factory EntreeMateriel.fromMap(String id, Map<String, dynamic> d) {
    String texteDe(Object? v) => v is String ? v : '';
    final photo = d['photoUrl'];
    final modif = d['modifiePar'];
    return EntreeMateriel(
      id: id,
      texte: texteDe(d['texte']),
      quantite: d['quantite'] == null ? '' : d['quantite'].toString(),
      photoUrl: photo is String && photo.isNotEmpty ? photo : null,
      complete: d['complete'] == true,
      auteurId: texteDe(d['ajoutePar']),
      auteurNom: texteDe(d['ajouteParNom']),
      dateAjout: _date(d['dateAjout']),
      dateModif: _date(d['dateModif']),
      modifiePar: modif is String && modif.isNotEmpty ? modif : null,
      dateComplete: _date(d['dateComplete']),
    );
  }

  /// Dernier changement : la modification, sinon l'ajout. Absent tant que le
  /// serveur n'a pas donné l'heure (écriture en cours).
  DateTime? get dateChangement => dateModif ?? dateAjout;

  /// Qui a fait le dernier changement (l'auteur si l'entrée n'a pas changé).
  String get changePar => modifiePar ?? auteurId;

  static DateTime? _date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}

/// Un changement est « non vu » par [moiId] si quelqu'un d'autre l'a fait après
/// la dernière visite [vuLe] de cette personne (jamais visitée : tout est nouveau).
bool estNonVu(EntreeMateriel e, {required String moiId, DateTime? vuLe}) {
  final quand = e.dateChangement;
  if (quand == null) return false;
  if (e.changePar == moiId) return false;
  return vuLe == null || quand.isAfter(vuLe);
}

/// Les demandes d'une même personne (un groupe par contremaître ou admin).
class GroupeAuteur {
  final String auteurId;
  final String nom;

  /// À acheter d'abord (le plus récent en premier), puis les obtenues.
  final List<EntreeMateriel> entrees;

  /// Changements que [moiId] n'a pas encore vus dans ce groupe.
  final int nonVus;

  const GroupeAuteur({
    required this.auteurId,
    required this.nom,
    required this.entrees,
    required this.nonVus,
  });

  int get aAcheter => entrees.where((e) => !e.complete).length;
  int get obtenues => entrees.length - aAcheter;
}

const String nomAuteurInconnu = 'Auteur inconnu';

/// Clé d'un auteur dans le document « déjà vu » (un nom de champ ne peut pas être vide).
String cleVu(String auteurId) => auteurId.isEmpty ? '_inconnu' : auteurId;

int _comparerRecents(EntreeMateriel a, EntreeMateriel b) {
  final da = a.dateChangement;
  final db = b.dateChangement;
  if (da == null && db == null) return 0;
  if (da == null) return -1; // en cours d'écriture : tout récent
  if (db == null) return 1;
  return db.compareTo(da);
}

/// Sépare les demandes par auteur, dans l'ordre alphabétique des noms (un ordre
/// stable : un groupe ne saute pas de place quand on l'ouvre). [vus] : dernière
/// visite de [moiId] pour chaque auteur (voir [cleVu]).
List<GroupeAuteur> grouperParAuteur(
  List<EntreeMateriel> entrees, {
  required String moiId,
  Map<String, DateTime> vus = const {},
}) {
  final parAuteur = <String, List<EntreeMateriel>>{};
  for (final e in entrees) {
    (parAuteur[e.auteurId] ??= []).add(e);
  }
  final groupes = <GroupeAuteur>[];
  parAuteur.forEach((auteurId, liste) {
    final recents = [...liste]..sort(_comparerRecents);
    final nom = recents
        .map((e) => e.auteurNom)
        .firstWhere((n) => n.isNotEmpty, orElse: () => nomAuteurInconnu);
    final ordonnees = [
      ...recents.where((e) => !e.complete),
      ...recents.where((e) => e.complete),
    ];
    groupes.add(
      GroupeAuteur(
        auteurId: auteurId,
        nom: nom,
        entrees: ordonnees,
        nonVus: liste
            .where((e) => estNonVu(e, moiId: moiId, vuLe: vus[cleVu(auteurId)]))
            .length,
      ),
    );
  });
  groupes.sort((a, b) {
    final parNom = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
    return parNom != 0 ? parNom : a.auteurId.compareTo(b.auteurId);
  });
  return groupes;
}

/// Total des changements non vus (pastille de la tuile « Général »).
int totalNonVus(List<GroupeAuteur> groupes) =>
    groupes.fold(0, (somme, g) => somme + g.nonVus);

/// Lit le document « déjà vu » d'un admin : { auteur: dernière visite }.
Map<String, DateTime> vusDepuisDonnees(Map<String, dynamic>? data) {
  final brut = data?['vus'];
  final resultat = <String, DateTime>{};
  if (brut is Map) {
    brut.forEach((cle, valeur) {
      if (cle is String && valeur is Timestamp) {
        resultat[cle] = valeur.toDate();
      } else if (cle is String && valeur is DateTime) {
        resultat[cle] = valeur;
      }
    });
  }
  return resultat;
}

/// Entrées d'un seul auteur ([auteurId] null : toutes).
List<EntreeMateriel> filtrerParAuteur(
  List<EntreeMateriel> entrees,
  String? auteurId,
) => auteurId == null
    ? entrees
    : entrees.where((e) => e.auteurId == auteurId).toList();

// -----------------------------------------------------------------------------
// Données écrites dans Firestore (les règles exigent exactement ces champs).
// -----------------------------------------------------------------------------

/// Nouvelle entrée de travaux ou de matériel. Pour Général, l'auteur est
/// obligatoire (id et nom de l'employé connecté) ; pour un chantier, jamais.
Map<String, dynamic> donneesNouvelleEntree({
  required String companyId,
  required String chantierId,
  required String texte,
  String? quantite,
  String? photoUrl,
  Employee? auteur,
}) {
  final general = chantierId == idChantierGeneral;
  if (general && auteur == null) {
    throw ArgumentError('Un auteur est requis pour le matériel Général.');
  }
  return {
    'companyId': companyId,
    'chantierId': chantierId,
    'texte': texte,
    'complete': false,
    'dateAjout': FieldValue.serverTimestamp(),
    'photoUrl': ?photoUrl,
    if (quantite != null && quantite.isNotEmpty) 'quantite': quantite,
    if (general) ...{'ajoutePar': auteur!.id, 'ajouteParNom': auteur.nom},
  };
}

/// Signature d'un changement sur une entrée Général : qui et quand.
Map<String, dynamic> signatureModification(String? modifieParId) => {
  'dateModif': FieldValue.serverTimestamp(),
  'modifiePar': ?modifieParId,
};

/// Marquer une entrée comme obtenue ou la remettre comme manquante.
Map<String, dynamic> donneesCompletion({
  required bool complete,
  required bool general,
  String? modifieParId,
}) => {
  'complete': complete,
  'dateComplete': complete ? FieldValue.serverTimestamp() : FieldValue.delete(),
  if (general) ...signatureModification(modifieParId),
};

/// Modification du texte, de la quantité ou de la photo d'une entrée.
Map<String, dynamic> donneesModification({
  required String texte,
  String? quantite,
  String? photoUrl,
  required bool general,
  String? modifieParId,
}) => {
  'texte': texte,
  'quantite': ?quantite,
  'photoUrl': ?photoUrl,
  if (general) ...signatureModification(modifieParId),
};
