/// Produits de terrasse en composite (ou PVC) : ce que dit la fiche du fabricant pour poser des
/// marches d'escalier. Tout est en POUCES.
class ProduitComposite {
  /// Identifiant gardé dans les calculs enregistrés.
  final String id;
  final String marque;
  final String gamme;

  /// Planche rainurée (attaches cachées) : largeur et épaisseur réelles.
  final double largeur;
  final double epaisseur;

  /// Écart entre deux planches côte à côte, donné par l'attache cachée.
  final double ecart;

  /// Écart au bout d'une planche qui finit contre une planche de cadrage (ou de transition).
  final double ecartBout;

  /// L'attache cachée du fabricant (pour les vis cachées) et le nombre par boîte.
  final String attache;
  final int attachesParBoite;

  /// Les bouchons qui cachent les vis apparentes (nez et côtés des marches) : le système
  /// (vis + bouchons de la couleur) et le nombre de bouchons par boîte.
  final String bouchons;
  final int bouchonsParBoite;

  /// Longueurs vendues.
  final List<double> longueurs;

  /// Fascia (contremarches) : hauteurs et longueurs vendues.
  final List<double> hauteursFascia;
  final List<double> longueursFascia;

  /// Entraxe maximal des limons sous des marches de ce produit.
  final double entraxeMaxLimons;

  /// D'où viennent ces valeurs (fiche ou guide d'installation du fabricant).
  final String source;

  const ProduitComposite({
    required this.id,
    required this.marque,
    required this.gamme,
    required this.largeur,
    required this.epaisseur,
    required this.ecart,
    required this.ecartBout,
    required this.attache,
    required this.attachesParBoite,
    required this.bouchons,
    required this.bouchonsParBoite,
    required this.longueurs,
    required this.hauteursFascia,
    required this.longueursFascia,
    required this.entraxeMaxLimons,
    required this.source,
  });

  String get nom => gamme.isEmpty ? marque : '$marque $gamme';
}

/// Un produit courant quand la marque n'est pas choisie : planche de 5 1/2 × 1 po, écart de
/// 3/16 po, fascia de 7 1/4 et 11 1/4 po en 12 pi, limons à 12 po.
const produitCompositeGenerique = ProduitComposite(
  id: 'generique',
  marque: 'Composite courant',
  gamme: '',
  largeur: 5.5,
  epaisseur: 1.0,
  ecart: 3 / 16,
  ecartBout: 1 / 8,
  attache: 'attache cachée du fabricant',
  attachesParBoite: 90,
  bouchons: 'vis et bouchons de la couleur',
  bouchonsParBoite: 100,
  longueurs: [144, 192, 240],
  hauteursFascia: [7.25, 11.25],
  longueursFascia: [144],
  entraxeMaxLimons: 12,
  source: 'Valeurs courantes ; vérifier la fiche du produit posé.',
);

/// Les produits proposés (le générique en premier).
const produitsComposite = <ProduitComposite>[produitCompositeGenerique];

/// Le produit d'un identifiant (le générique s'il est inconnu).
ProduitComposite produitComposite(String? id) => produitsComposite.firstWhere(
  (p) => p.id == id,
  orElse: () => produitCompositeGenerique,
);
