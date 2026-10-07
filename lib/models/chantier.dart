/// Identifiant réservé du « chantier » Général : le matériel dont un contremaître
/// a besoin pour sa remorque, sans chantier précis. Jamais un vrai chantier (les
/// identifiants Firestore ne commencent pas par « _ ») : il n'existe pas dans la
/// collection `chantiers`, donc il n'est jamais proposé pour les heures. Les
/// règles Firestore l'acceptent seulement pour `chantier_materiel`.
const String idChantierGeneral = '_general';

/// Le choix « Général » de la liste de matériel (écran Chantiers).
const Chantier chantierGeneral = Chantier(
  id: idChantierGeneral,
  companyId: '',
  nom: 'Général',
  adresse: 'Remorque, matériel sans chantier',
);

/// Les vrais chantiers seulement : « Général » n'est jamais un chantier où
/// inscrire des heures. (Il n'est pas dans Firestore ; ce filtre est une garde de
/// plus pour la feuille de temps.)
List<Chantier> sansGeneral(Iterable<Chantier> chantiers) =>
    chantiers.where((c) => c.id != idChantierGeneral).toList();

class Chantier {
  final String id;
  final String companyId;
  final String nom;
  final String adresse;

  /// Chantier retiré de la liste : il garde ses photos, documents et heures,
  /// mais ne se choisit plus. Jamais supprimé.
  final bool archive;

  const Chantier({
    required this.id,
    required this.companyId,
    required this.nom,
    required this.adresse,
    this.archive = false,
  });

  factory Chantier.fromFirestore(String id, Map<String, dynamic> data) {
    return Chantier(
      id: id,
      companyId: data['companyId'] ?? '',
      nom: data['nom'] ?? '',
      adresse: data['adresse'] ?? '',
      archive: data['archive'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is Chantier && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$nom — $adresse';
}
