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
