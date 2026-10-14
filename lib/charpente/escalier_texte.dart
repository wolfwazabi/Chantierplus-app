import 'escalier.dart';
import 'escalier_composite.dart';
import 'unites.dart';

/// Une ligne de la liste de matériaux d'un escalier.
class LigneMaterielEscalier {
  final int quantite;
  final String article;
  final String detail;
  const LigneMaterielEscalier(this.quantite, this.article, this.detail);

  @override
  String toString() => '$quantite × $article';
}

/// Matériaux de la structure de l'escalier : limons, marches, contremarches.
List<LigneMaterielEscalier> materielEscalier(
  ResultatEscalier r, {
  required bool metrique,
}) {
  String l(double po) => formatLongueur(po, metrique: metrique);
  final s = r.spec;
  return [
    LigneMaterielEscalier(
      r.nombreLimons,
      '${s.section.nom} × ${formatPlanche(r.longueurCommerciale, metrique: metrique)} (limons)',
      'Coupe : ${l(r.longueurLimon)} chacun, entraxe ${l(r.espacementReel)}',
    ),
    if (s.composite != null)
      ..._materielComposite(r, metrique)
    else ...[
      LigneMaterielEscalier(
        r.nombreMarches,
        'Marches de ${l(s.largeur)} de long',
        'Profondeur ${l(r.profondeurMarche)} (giron ${l(r.giron)} + nez ${l(s.nez)}), '
            'épaisseur ${l(s.epaisseurMarche)}',
      ),
      if (s.contremarchesFermees)
        LigneMaterielEscalier(
          r.nombreContremarches,
          'Contremarches de ${l(s.largeur)} de long',
          'Hauteur ${l(r.contremarche)}, épaisseur ${l(s.epaisseurContremarche)}',
        ),
    ],
  ];
}

/// Marches en composite : planches des marches en cadre, fascias des contremarches, 2x de
/// backing derrière chaque contremarche, attaches cachées, vis et bouchons des vis apparentes.
/// Le détail est sur la première ligne de chaque article.
List<LigneMaterielEscalier> _materielComposite(
  ResultatEscalier r,
  bool metrique,
) {
  String l(double po) => formatLongueur(po, metrique: metrique);
  String p(double po) => formatPlanche(po, metrique: metrique);
  final s = r.spec;
  final c = calculerComposite(r);
  final produit = c.produit;
  final n = c.rangsCentre;
  final parMarche =
      '${l(produit.largeur)} × ${l(produit.epaisseur)} ; écart de ${l(produit.ecart)} entre '
      'planches côte à côte, ${l(produit.ecartBout)} au bout contre le cadre. '
      'Par marche, en cadre : nez de ${l(s.largeur)}, 2 côtés de '
      '${l(r.profondeurMarche)} en onglet'
      '${n == 0 ? '' : ', $n planche${n > 1 ? 's' : ''} de ${l(c.longueurCentre)} au centre'}';
  final contremarches =
      '${r.nombreContremarches} contremarches de ${l(s.largeur)}, refendues à '
      '${l(r.contremarche)}';
  List<LigneMaterielEscalier> lignes(
    Map<double, int> parLongueur,
    String Function(double) article,
    String detail,
  ) => [
    for (final (i, e) in parLongueur.entries.indexed)
      LigneMaterielEscalier(e.value, article(e.key), i == 0 ? detail : ''),
  ];
  return [
    ...lignes(
      c.planches.parLongueur,
      (lg) => 'Planches ${produit.nom} × ${p(lg)} (marches)',
      parMarche,
    ),
    ...lignes(
      c.fascias.parLongueur,
      (lg) =>
          'Fascias ${produit.marque} ${l(c.hauteurFascia)} × ${p(lg)} (contremarches)',
      contremarches,
    ),
    ...lignes(
      c.backing.parLongueur,
      (lg) =>
          '${c.sectionBacking} traité × ${p(lg)} (backing des contremarches)',
      'Derrière chaque fascia : $contremarches',
    ),
    if (c.blocs != null)
      ...lignes(
        c.blocs!.parLongueur,
        (lg) => '2x12 traité × ${p(lg)} (à plat aux côtés des marches)',
        '${r.nombreMarches * c.blocsParMarche} morceaux de ${l(c.longueurBloc)}, '
        '${c.blocsParMarche == 2 ? 'un de chaque côté de chaque marche' : 'un sous chaque marche'}, '
        'entre le limon de côté et le suivant, sous la planche de côté',
      ),
    if (c.attaches > 0)
      LigneMaterielEscalier(
        c.boitesAttaches,
        'Boîte${c.boitesAttaches > 1 ? 's' : ''} d\'attaches cachées '
            '${produit.attache} (${produit.attachesParBoite})',
        '${c.attaches} attaches : une par limon intérieur à chaque joint des planches '
            'du centre',
      ),
    LigneMaterielEscalier(
      c.visApparentes,
      produit.avecBouchons
          ? 'Vis et bouchons (${produit.fixationSurface})'
          : 'Vis (${produit.fixationSurface})',
      '${produit.avecBouchons ? 'Vis en surface cachées par un bouchon' : 'Vis en surface'} : '
      '$visParLimonParPlanche par limon dans le nez'
      '${c.attaches == 0 && c.rangsCentre > 0 ? ' et dans les planches du centre' : ''}, '
      '$visParCote par côté de marche'
      '${produit.attachesSurMarches ? '' : ' (attaches cachées interdites sur les marches)'}',
    ),
    LigneMaterielEscalier(
      c.visFascia,
      'Vis de fascia de la couleur',
      '$visFasciaParLimon par limon dans chaque fascia, dans le backing',
    ),
  ];
}

/// Texte à copier : dimensions, coupes, traçage et matériaux.
String texteEscalier(ResultatEscalier r, {required bool metrique}) {
  String l(double po) => formatLongueur(po, metrique: metrique);
  final s = r.spec;
  final b = StringBuffer()
    ..writeln('ESCALIER — LIMONS')
    ..writeln(
      'Hauteur totale (plancher fini à plancher fini) : ${l(s.hauteurTotale)}',
    )
    ..writeln('Largeur : ${l(s.largeur)}')
    ..writeln(
      '${r.nombreContremarches} contremarches de ${l(r.contremarche)} '
      '(${formatNombre(poucesEnMm(r.contremarche), decimales: 1)} mm)',
    )
    ..writeln(
      '${r.nombreMarches} marches : giron ${l(r.giron)} '
      '(${formatNombre(poucesEnMm(r.giron), decimales: 1)} mm), '
      'profondeur ${l(r.profondeurMarche)}',
    )
    ..writeln('Course : ${l(r.course)}')
    ..writeln('Pente : ${formatAngle(r.angle)}')
    ..writeln()
    ..writeln('LIMON (${s.section.nom})')
    ..writeln(
      'Planche à commander : ${formatPlanche(r.longueurCommerciale, metrique: metrique)}',
    )
    ..writeln('Longueur de coupe : ${l(r.longueurLimon)}')
    ..writeln('Gorge sous les entailles : ${l(r.gorge)}')
    ..writeln('Coupe de départ (aplomb) : ${l(r.hauteurDepart)} de haut')
    ..writeln('Pied : coupe de niveau de ${l(r.coupePied)}')
    ..writeln(
      'Tête : coupe d\'aplomb de ${l(r.coupeTete)} contre la poutre du haut',
    )
    ..writeln(
      'Pointe du haut : ${l(r.hauteurPointeHaute)} au-dessus du plancher du bas',
    )
    ..writeln()
    ..writeln('TRAÇAGE (depuis le plancher fini du bas)')
    ..writeln('Marche | Dessus | Siège du limon | Course');
  for (final t in r.table) {
    b.writeln(
      '${t.marche} | ${l(r.arrondi(t.hauteurDessus))} | '
      '${l(r.arrondi(t.hauteurSiege))} | ${l(r.arrondi(t.course))}',
    );
  }
  b
    ..writeln()
    ..writeln('MATÉRIAUX');
  for (final m in materielEscalier(r, metrique: metrique)) {
    b.writeln('${m.quantite} × ${m.article} — ${m.detail}');
  }
  b
    ..writeln()
    ..writeln(
      'VÉRIFICATIONS (CNB 2015, section 9.8, Code de construction du Québec)',
    );
  for (final v in r.verifications) {
    final marque = switch (v.niveau) {
      Niveau.ok => 'OK',
      Niveau.info => 'À VÉRIFIER',
      Niveau.avertissement => 'ATTENTION',
      Niveau.erreur => 'NON CONFORME',
    };
    b.writeln(
      '[$marque] ${v.message}${v.reference == null ? '' : ' (${v.reference})'}',
    );
  }
  b
    ..writeln()
    ..writeln(
      'Calcul des dimensions seulement : il ne remplace pas la validation de '
      'l\'inspecteur, de la GCR ou d\'un ingénieur.',
    );
  return b.toString();
}
