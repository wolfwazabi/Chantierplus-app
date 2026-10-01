/// Panneaux de revêtement (contreplaqué, OSB, panneaux isolants). POUCES.
class FormatPanneau {
  final String id;
  final String nom;
  final double longueur;
  final double largeur;

  /// Épaisseur totale en pouces (information).
  final double? epaisseur;

  /// Valeur isolante R (système impérial), si le panneau est isolant.
  final double? valeurR;

  /// Texte d'information (composition, fabricant).
  final String? note;

  const FormatPanneau({
    required this.id,
    required this.nom,
    required this.longueur,
    this.largeur = 48,
    this.epaisseur,
    this.valeurR,
    this.note,
  });

  double get surfacePi2 => longueur * largeur / 144;
  double get surfaceM2 => surfacePi2 * 0.09290304;
  bool get estIsolant => valeurR != null;
}

const panneau4x8 = FormatPanneau(id: '4x8', nom: '4 × 8 pi', longueur: 96);
const panneau4x9 = FormatPanneau(id: '4x9', nom: '4 × 9 pi', longueur: 108);
const panneau4x10 = FormatPanneau(id: '4x10', nom: '4 × 10 pi', longueur: 120);
const panneau4x12 = FormatPanneau(id: '4x12', nom: '4 × 12 pi', longueur: 144);

/// Panneau OSB avec isolant R-4 intégré : polystyrène expansé (EPS) laminé sur
/// un OSB perforé de 7/16 po. Produit offert au Québec (Isolofoam, vendu aussi
/// sous le nom OSB.Comfort R4). Source : fiche technique du fabricant.
const panneauIsobraceR4 = FormatPanneau(
  id: 'isobrace_r4',
  nom: 'OSB isolant R-4 (Isobrace) 4 × 9 pi',
  longueur: 108,
  epaisseur: 1.3125, // 1-5/16 po
  valeurR: 4.15,
  note:
      'EPS laminé sur OSB perforé de 7/16 po, 1-5/16 po d\'épaisseur, R4,15. '
      'Clous d\'au moins 2-1/2 po, aux 6 po c/c en rive et 12 po c/c dans le champ.',
);

/// Formats offerts pour les feuilles de plancher et de mur.
const formatsPanneaux = [
  panneau4x8,
  panneau4x9,
  panneau4x10,
  panneau4x12,
  panneauIsobraceR4,
];

FormatPanneau? panneauParId(String id) {
  for (final p in formatsPanneaux) {
    if (p.id == id) {
      return p;
    }
  }
  return null;
}
