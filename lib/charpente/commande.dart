import 'empaquetage.dart';
import 'mur.dart';
import 'plancher.dart';
import 'unites.dart';

/// Liste d'achat : tout le bois, les feuilles, la quincaillerie, la membrane et
/// le revêtement d'un projet (plancher + murs), regroupés par article.

enum CategorieCommande { bois, panneaux, quincaillerie, finition }

String libelleCategorie(CategorieCommande c) => switch (c) {
  CategorieCommande.bois => 'Bois d\'œuvre',
  CategorieCommande.panneaux => 'Feuilles',
  CategorieCommande.quincaillerie => 'Quincaillerie',
  CategorieCommande.finition => 'Membrane, fourrures et revêtement',
};

/// Une ligne de commande : [quantite] [unite] de [article].
class LigneCommande {
  final CategorieCommande categorie;
  final String article;

  /// Nombre de pièces, ou aire / longueur selon [unite].
  final double quantite;

  /// « » : pièces ; « pi² » ; « rouleaux » …
  final String unite;

  /// Où ça sert : « Plancher », « Murs », « Plancher, Murs » ; texte libre pour
  /// les lignes ajoutées à la main.
  final String usage;
  final bool manuelle;

  const LigneCommande({
    required this.categorie,
    required this.article,
    required this.quantite,
    this.unite = '',
    this.usage = '',
    this.manuelle = false,
  });

  String get quantiteTexte {
    final q = quantite == quantite.roundToDouble()
        ? quantite.round().toString()
        : formatNombre(quantite, decimales: 1);
    return unite.isEmpty ? q : '$q $unite';
  }

  Map<String, dynamic> toJson() => {
    'categorie': categorie.name,
    'article': article,
    'quantite': quantite,
    'unite': unite,
    'usage': usage,
    'manuelle': manuelle,
  };

  /// Lance [FormatException] si la ligne est mal formée.
  factory LigneCommande.fromJson(Object? j) {
    if (j is! Map) {
      throw const FormatException('ligne de commande invalide');
    }
    final categorie = CategorieCommande.values.where(
      (c) => c.name == j['categorie'],
    );
    final article = j['article'];
    final quantite = j['quantite'];
    final unite = j['unite'] ?? '';
    final usage = j['usage'] ?? '';
    if (categorie.isEmpty ||
        article is! String ||
        article.trim().isEmpty ||
        article.length > 200 ||
        quantite is! num ||
        !quantite.isFinite ||
        quantite <= 0 ||
        quantite > 1e7 ||
        unite is! String ||
        unite.length > 20 ||
        usage is! String ||
        usage.length > 100) {
      throw const FormatException('ligne de commande invalide');
    }
    return LigneCommande(
      categorie: categorie.first,
      article: article.trim(),
      quantite: quantite.toDouble(),
      unite: unite,
      usage: usage,
      manuelle: j['manuelle'] == true,
    );
  }
}

class Commande {
  final List<LigneCommande> lignes;
  final List<String> avertissements;
  const Commande(this.lignes, [this.avertissements = const []]);

  bool get estVide => lignes.isEmpty;

  /// Nombre de pièces de bois d'œuvre (pour l'aperçu).
  int get piecesDeBois => lignes
      .where((l) => l.categorie == CategorieCommande.bois && l.unite.isEmpty)
      .fold(0, (a, l) => a + l.quantite.round());

  /// Texte prêt à envoyer au fournisseur.
  String enTexte({String titre = 'Liste de matériaux'}) {
    final b = StringBuffer(titre)..writeln();
    for (final c in CategorieCommande.values) {
      final dans = lignes.where((l) => l.categorie == c).toList();
      if (dans.isEmpty) {
        continue;
      }
      b
        ..writeln()
        ..writeln(libelleCategorie(c).toUpperCase());
      for (final l in dans) {
        b.writeln('${l.quantiteTexte} × ${l.article}');
      }
    }
    return b.toString().trimRight();
  }
}

/// Fusionne les lignes de même article et même unité (quantités additionnées,
/// usages réunis) et les trie : catégorie, puis ordre d'apparition.
List<LigneCommande> fusionnerLignes(List<LigneCommande> brutes) {
  final cles = <String, int>{};
  final out = <LigneCommande>[];
  for (final l in brutes) {
    if (l.manuelle) {
      // Lignes ajoutées à la main : jamais fusionnées (chacune se retire seule).
      out.add(l);
      continue;
    }
    final cle = '${l.categorie.name}|${l.article}|${l.unite}';
    final i = cles[cle];
    if (i == null) {
      cles[cle] = out.length;
      out.add(l);
    } else {
      final a = out[i];
      final usages = {
        ...a.usage.split(', ').where((u) => u.isNotEmpty),
        ...l.usage.split(', ').where((u) => u.isNotEmpty),
      };
      out[i] = LigneCommande(
        categorie: a.categorie,
        article: a.article,
        quantite: a.quantite + l.quantite,
        unite: a.unite,
        usage: usages.join(', '),
        manuelle: a.manuelle,
      );
    }
  }
  final ordre = {for (final (i, c) in CategorieCommande.values.indexed) c: i};
  // Tri stable : catégorie seulement.
  final indexees = out.indexed.toList()
    ..sort((a, b) {
      final c = ordre[a.$2.categorie]!.compareTo(ordre[b.$2.categorie]!);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, l) in indexees) l];
}

String _pouces(double p) {
  final seiz = (p * 16).round();
  final entier = seiz ~/ 16;
  var n = seiz % 16;
  var d = 16;
  while (n != 0 && n.isEven) {
    n ~/= 2;
    d ~/= 2;
  }
  if (n == 0) {
    return '$entier po';
  }
  return entier == 0 ? '$n/$d po' : '$entier $n/$d po';
}

/// « 2×10 × 12' » ; en métrique, « 2×10 × 3,66 m ».
String _planche(String section, double longueur, bool metrique) =>
    '$section × ${formatPlanche(longueur, metrique: metrique)}';

void _bois(
  List<LigneCommande> out,
  ResultatDecoupe d,
  String section,
  String usage,
  bool metrique, {
  String prefixe = '',
  String suffixe = '',
}) {
  for (final e in d.parLongueur.entries) {
    out.add(
      LigneCommande(
        categorie: CategorieCommande.bois,
        article: '$prefixe${_planche(section, e.key, metrique)}$suffixe',
        quantite: e.value.toDouble(),
        usage: usage,
      ),
    );
  }
}

/// Construit la liste d'achat. [plancher] et [murs] sont facultatifs (au moins
/// l'un des deux). [sectionPlancher] : section des solives, des rives et des
/// entremises.
Commande construireCommande({
  ResultatPlancher? plancher,
  SectionBois sectionPlancher = section2x10,
  ResultatMurs? murs,
  bool metrique = false,
}) {
  final brutes = <LigneCommande>[];
  final avert = <String>[];

  if (plancher != null) {
    _bois(brutes, plancher.bois, sectionPlancher.nom, 'Plancher', metrique);
    if (plancher.etriers > 0) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.quincaillerie,
          article: 'Étrier de solive pour ${sectionPlancher.nom}',
          quantite: plancher.etriers.toDouble(),
          usage: 'Plancher',
        ),
      );
      // Clous d'étriers : les clous nécessaires plus la marge, en boîtes.
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.quincaillerie,
          article:
              'Clous d\'étriers 10d × 1 1/2 po (boîte d\'environ ${plancher.spec.clousParBoite})',
          quantite: plancher.boitesClousEtriers.toDouble(),
          usage: 'Plancher',
        ),
      );
    }
    final poutres = plancher.poutres;
    if (poutres != null) {
      _bois(
        brutes,
        poutres.bois,
        poutres.spec.section,
        'Poutres',
        metrique,
        suffixe: ' traité',
      );
      if (poutres.pattes != null) {
        _bois(
          brutes,
          poutres.pattes!,
          '6×6',
          'Pattes (pieux)',
          metrique,
          suffixe: ' traité',
        );
      }
      avert.addAll(poutres.avertissements.map((a) => 'Poutres : $a'));
    }
    final pn = plancher.panneaux;
    if (pn.feuillesACommander > 0) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.panneaux,
          article: 'Sous-plancher ${pn.format.nom}',
          quantite: pn.feuillesACommander.toDouble(),
          usage: 'Plancher',
        ),
      );
    }
    avert.addAll(plancher.avertissements.map((a) => 'Plancher : $a'));
  }

  if (murs != null) {
    final p = murs.parametres;
    for (final e in murs.precoupes.entries) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.bois,
          article: '${p.section.nom} précoupé ${_pouces(e.key)}',
          quantite: e.value.toDouble(),
          usage: 'Murs',
        ),
      );
    }
    _bois(brutes, murs.boisOssature, p.section.nom, 'Murs', metrique);
    _bois(
      brutes,
      murs.boisLinteaux,
      p.linteau.nom,
      'Murs (linteaux)',
      metrique,
    );
    if (murs.feuillesACommander > 0) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.panneaux,
          article: p.panneau.nom,
          quantite: murs.feuillesACommander.toDouble(),
          usage: 'Murs',
        ),
      );
    }
    final fourrure =
        'Fourrure ${_pouces(p.fourrureEpaisseur)} × ${_pouces(p.fourrureLargeur)}';
    for (final e in murs.fourrures.parLongueur.entries) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.finition,
          article: _planche(fourrure, e.key, metrique),
          quantite: e.value.toDouble(),
          usage: 'Murs',
        ),
      );
    }
    if (murs.rouleauxMembrane > 0) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.finition,
          article:
              'Membrane (rouleau de ${formatNombre(p.aireRouleauPi2, decimales: 0)} pi²)',
          quantite: murs.rouleauxMembrane.toDouble(),
          usage: 'Murs',
        ),
      );
    }
    if (murs.aireRevetementPi2 > 0) {
      brutes.add(
        LigneCommande(
          categorie: CategorieCommande.finition,
          article: 'Revêtement extérieur (aire avec marge)',
          quantite: murs.aireRevetementPi2.ceilToDouble(),
          unite: 'pi²',
          usage: 'Murs',
        ),
      );
    }
    avert.addAll(murs.avertissements.map((a) => 'Murs : $a'));
  }

  return Commande(fusionnerLignes(brutes), avert);
}
