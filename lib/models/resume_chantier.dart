/// Heures d'un employé sur un chantier.
class HeuresEmploye {
  final String nom;
  final double heures;
  final double voyagementPaye;
  final int jours;

  const HeuresEmploye({
    required this.nom,
    required this.heures,
    required this.voyagementPaye,
    required this.jours,
  });

  factory HeuresEmploye.fromMap(Map<String, dynamic> m) => HeuresEmploye(
    nom: (m['nom'] ?? '').toString(),
    heures: _nombre(m['heures']),
    voyagementPaye: _nombre(m['voyagementPaye']),
    jours: _nombre(m['jours']).toInt(),
  );
}

/// Résumé d'un chantier calculé par le serveur (fonction resumeChantier) à
/// partir des feuilles de temps de la compagnie.
class ResumeChantier {
  final String nom;
  final String adresse;
  final bool archive;
  final double totalHeures;
  final double totalVoyagementPaye;
  final int joursTravailles;
  final int journeesHomme;
  final String? premierJour;
  final String? dernierJour;
  final List<HeuresEmploye> parEmploye;
  final int nbExtras;
  final int nbMateriel;
  final int nbPhotos;

  const ResumeChantier({
    required this.nom,
    required this.adresse,
    required this.archive,
    required this.totalHeures,
    required this.totalVoyagementPaye,
    required this.joursTravailles,
    required this.journeesHomme,
    required this.premierJour,
    required this.dernierJour,
    required this.parEmploye,
    required this.nbExtras,
    required this.nbMateriel,
    required this.nbPhotos,
  });

  factory ResumeChantier.fromMap(Map<String, dynamic> m) {
    final chantier = _carte(m['chantier']);
    final heures = _carte(m['heures']);
    final nombres = _carte(m['nombres']);
    final employes = heures['parEmploye'];
    return ResumeChantier(
      nom: (chantier['nom'] ?? '').toString(),
      adresse: (chantier['adresse'] ?? '').toString(),
      archive: chantier['archive'] == true,
      totalHeures: _nombre(heures['totalHeures']),
      totalVoyagementPaye: _nombre(heures['totalVoyagementPaye']),
      joursTravailles: _nombre(heures['joursTravailles']).toInt(),
      journeesHomme: _nombre(heures['journeesHomme']).toInt(),
      premierJour: heures['premierJour'] as String?,
      dernierJour: heures['dernierJour'] as String?,
      parEmploye: employes is List
          ? [for (final e in employes) HeuresEmploye.fromMap(_carte(e))]
          : const [],
      nbExtras: _nombre(nombres['extras']).toInt(),
      nbMateriel: _nombre(nombres['materiel']).toInt(),
      nbPhotos: _nombre(nombres['photos']).toInt(),
    );
  }
}

/// Résultat de l'export : lien de téléchargement à durée limitée.
class ExportChantier {
  final String url;
  final String nom;
  final int taille;
  final int fichiers;
  final List<String> ignores;

  const ExportChantier({
    required this.url,
    required this.nom,
    required this.taille,
    required this.fichiers,
    required this.ignores,
  });

  factory ExportChantier.fromMap(Map<String, dynamic> m) {
    final ignores = m['ignores'];
    return ExportChantier(
      url: (m['url'] ?? '').toString(),
      nom: (m['nom'] ?? 'dossier.zip').toString(),
      taille: _nombre(m['taille']).toInt(),
      fichiers: _nombre(m['fichiers']).toInt(),
      ignores: ignores is List
          ? [for (final i in ignores) i.toString()]
          : const [],
    );
  }
}

Map<String, dynamic> _carte(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

double _nombre(Object? v) => v is num && v.isFinite ? v.toDouble() : 0;

/// « 23.5 » → « 23,5 » ; « 8 » → « 8 » (sans zéros inutiles, virgule décimale).
String formatHeures(double h) {
  final s = h.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceFirst('.', ',');
}

/// Taille lisible : « 850 Ko », « 12,4 Mo ».
String formatTaille(int octets) {
  if (octets < 1024) return '$octets o';
  if (octets < 1024 * 1024) return '${(octets / 1024).round()} Ko';
  final mo = octets / (1024 * 1024);
  return '${mo.toStringAsFixed(1).replaceFirst('.', ',')} Mo';
}
