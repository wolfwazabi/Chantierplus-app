import 'escalier.dart';
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
  ];
}

/// Texte à copier : dimensions, coupes, traçage et matériaux.
String texteEscalier(ResultatEscalier r, {required bool metrique}) {
  String l(double po) => formatLongueur(po, metrique: metrique);
  final s = r.spec;
  final b = StringBuffer()
    ..writeln('ESCALIER — LIMONS')
    ..writeln('Hauteur totale (plancher fini à plancher fini) : ${l(s.hauteurTotale)}')
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
    ..writeln('Course horizontale : ${l(r.course)}')
    ..writeln('Pente : ${formatAngle(r.angle)}')
    ..writeln()
    ..writeln('LIMON (${s.section.nom})')
    ..writeln('Planche à commander : ${formatPlanche(r.longueurCommerciale, metrique: metrique)}')
    ..writeln('Longueur de coupe : ${l(r.longueurLimon)}')
    ..writeln('Gorge sous les entailles : ${l(r.gorge)}')
    ..writeln('Coupe de départ (aplomb) : ${l(r.hauteurDepart)} de haut')
    ..writeln('Pied : coupe de niveau de ${l(r.coupePied)}')
    ..writeln('Tête : coupe d\'aplomb de ${l(r.coupeTete)} contre la poutre du haut')
    ..writeln('Pointe du haut : ${l(r.hauteurPointeHaute)} au-dessus du plancher du bas')
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
    ..writeln('VÉRIFICATIONS (CNB 2015, section 9.8, Code de construction du Québec)');
  for (final v in r.verifications) {
    final marque = switch (v.niveau) {
      Niveau.ok => 'OK',
      Niveau.info => 'À VÉRIFIER',
      Niveau.avertissement => 'ATTENTION',
      Niveau.erreur => 'NON CONFORME',
    };
    b.writeln('[$marque] ${v.message}${v.reference == null ? '' : ' (${v.reference})'}');
  }
  b
    ..writeln()
    ..writeln(
      'Calcul des dimensions seulement : il ne remplace pas la validation de '
      'l\'inspecteur, de la GCR ou d\'un ingénieur.',
    );
  return b.toString();
}
