import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../charpente/escalier.dart';
import '../../charpente/unites.dart';

/// Les mesures écrites sur les schémas des coupes (déjà formatées, dans le système
/// d'unités choisi). Séparées du dessin pour pouvoir être vérifiées.
class EtiquettesCoupes {
  /// Gabarit (équerre) : les trois côtés du triangle et la pente.
  final String contremarche;
  final String giron;
  final String diagonale;
  final String pente;
  final String angleHaut;

  /// Pied du limon.
  final String aplombBas;
  final String niveauPied;

  /// Tête du limon.
  final String aplombTete;
  final String pointeHaute;

  /// Écarts des coupes avec la coupe d'équerre (en degrés).
  final String anglePlomb;
  final String angleNiveau;

  const EtiquettesCoupes({
    required this.contremarche,
    required this.giron,
    required this.diagonale,
    required this.pente,
    required this.angleHaut,
    required this.aplombBas,
    required this.niveauPied,
    required this.aplombTete,
    required this.pointeHaute,
    required this.anglePlomb,
    required this.angleNiveau,
  });
}

EtiquettesCoupes etiquettesCoupes(
  ResultatEscalier r, {
  required bool metrique,
}) {
  String l(double po) => formatLongueur(po, metrique: metrique);
  return EtiquettesCoupes(
    contremarche: l(r.contremarche),
    giron: l(r.giron),
    diagonale: l(r.diagonale),
    pente: formatAngle(r.angle),
    angleHaut: formatAngle(90 - r.angle),
    aplombBas: l(r.hauteurDepart),
    niveauPied: l(r.coupePied),
    aplombTete: l(r.coupeTete),
    pointeHaute: l(r.hauteurPointeHaute),
    anglePlomb: formatAngle(r.anglePlomb),
    angleNiveau: formatAngle(r.angleNiveau),
  );
}

/// Schémas des coupes : le gabarit (triangle de l'équerre avec la pente), le pied
/// du limon (coupe d'aplomb et coupe de niveau) et sa tête (coupe d'aplomb et pointe).
class SchemaCoupes extends StatelessWidget {
  /// Tests et aperçus : famille de police des étiquettes dessinées (null : celle de
  /// l'appareil).
  @visibleForTesting
  static String? famillePolice;

  final ResultatEscalier resultat;
  final bool metrique;
  const SchemaCoupes({
    super.key,
    required this.resultat,
    required this.metrique,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = etiquettesCoupes(resultat, metrique: metrique);
    final styleLegende = Theme.of(context).textTheme.bodySmall;
    Widget panneau(
      String cle,
      String titre,
      CustomPainter peintre,
      String legende,
    ) {
      return Column(
        key: ValueKey(cle),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(titre, style: Theme.of(context).textTheme.labelLarge),
          ),
          AspectRatio(
            aspectRatio: 1.9,
            child: CustomPaint(
              painter: peintre,
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(legende, style: styleLegende),
          ),
        ],
      );
    }

    final couleurs = _Couleurs(
      bois: const Color(0xFFD9B27C),
      marche: const Color(0xFF9C6B3A),
      trait: scheme.onSurface,
      cote: scheme.primary,
      fond: scheme.surfaceContainerHighest,
    );
    return Column(
      key: const ValueKey('schema_coupes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        panneau(
          'schema_gabarit',
          'Gabarit : pente et mesures de l\'équerre',
          _PeintreGabarit(resultat, e, couleurs),
          'Pente ${e.pente}. À l\'équerre : contremarche ${e.contremarche} d\'un côté, '
              'giron ${e.giron} de l\'autre (diagonale ${e.diagonale}). La coupe '
              'd\'aplomb s\'écarte de ${e.anglePlomb} de la coupe d\'équerre, la coupe '
              'de niveau de ${e.angleNiveau}.',
        ),
        panneau(
          'schema_pied',
          'Pied du limon',
          _PeintrePied(resultat, e, couleurs),
          'Coupe d\'aplomb de ${e.aplombBas} (contremarche moins l\'épaisseur de la '
              'marche) ; coupe de niveau de ${e.niveauPied} posée sur le plancher du bas.',
        ),
        panneau(
          'schema_tete',
          'Tête du limon',
          _PeintreTete(resultat, e, couleurs),
          'Coupe d\'aplomb de ${e.aplombTete} contre la poutre du haut ; pointe du '
              'haut à ${e.pointeHaute} du plancher du bas.',
        ),
      ],
    );
  }
}

class _Couleurs {
  final Color bois;
  final Color marche;
  final Color trait;
  final Color cote;
  final Color fond;
  const _Couleurs({
    required this.bois,
    required this.marche,
    required this.trait,
    required this.cote,
    required this.fond,
  });
}

enum _Alignement { gauche, centre, droite }

/// Écrit une étiquette. [limite] : taille du dessin, pour que le texte ne sorte
/// jamais de l'image ; [fond] : couleur derrière le texte (le texte reste lisible
/// même s'il croise un trait).
void _texte(
  Canvas canvas,
  String texte,
  Offset position,
  Color couleur, {
  _Alignement alignement = _Alignement.centre,
  double rotation = 0,
  double taille = 11,
  Size? limite,
  Color? fond,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: texte,
      style: TextStyle(
        color: couleur,
        fontSize: taille,
        fontWeight: FontWeight.w600,
        fontFamily: SchemaCoupes.famillePolice,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  var pos = position;
  if (limite != null) {
    // Étendue du texte une fois tourné (horizontal ou vertical seulement).
    final vertical =
        rotation.abs() > math.pi / 4 && rotation.abs() < 3 * math.pi / 4;
    final largeur = vertical ? tp.height : tp.width;
    final hauteur = vertical ? tp.width : tp.height;
    final gauche = switch (alignement) {
      _Alignement.centre => pos.dx - largeur / 2,
      _Alignement.gauche => pos.dx,
      _Alignement.droite => pos.dx - largeur,
    };
    var dxCorr = 0.0;
    if (rotation.abs() < math.pi / 4 || vertical) {
      if (gauche < 2) dxCorr = 2 - gauche;
      if (gauche + largeur > limite.width - 2)
        dxCorr = limite.width - 2 - (gauche + largeur);
      var dyCorr = 0.0;
      if (pos.dy - hauteur / 2 < 2) dyCorr = 2 - (pos.dy - hauteur / 2);
      if (pos.dy + hauteur / 2 > limite.height - 2) {
        dyCorr = limite.height - 2 - (pos.dy + hauteur / 2);
      }
      pos = pos + Offset(dxCorr, dyCorr);
    }
  }
  canvas.save();
  canvas.translate(pos.dx, pos.dy);
  canvas.rotate(rotation);
  final dx = switch (alignement) {
    _Alignement.centre => -tp.width / 2,
    _Alignement.gauche => 0.0,
    _Alignement.droite => -tp.width,
  };
  if (fond != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(dx - 2, -tp.height / 2 - 1, tp.width + 4, tp.height + 2),
        const Radius.circular(3),
      ),
      Paint()..color = fond.withValues(alpha: 0.85),
    );
  }
  tp.paint(canvas, Offset(dx, -tp.height / 2));
  canvas.restore();
}

/// Cote : trait avec deux petits traits d'arrêt.
void _cote(Canvas canvas, Offset a, Offset b, Paint paint, {double arret = 4}) {
  canvas.drawLine(a, b, paint);
  final d = b - a;
  final n = d.distance == 0
      ? const Offset(0, 1)
      : Offset(-d.dy, d.dx) / d.distance;
  canvas.drawLine(a - n * arret, a + n * arret, paint);
  canvas.drawLine(b - n * arret, b + n * arret, paint);
}

// -----------------------------------------------------------------------------
// Gabarit : le triangle de l'équerre
// -----------------------------------------------------------------------------

class _PeintreGabarit extends CustomPainter {
  final ResultatEscalier r;
  final EtiquettesCoupes e;
  final _Couleurs c;
  _PeintreGabarit(this.r, this.e, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.fond);
    void t(
      String texte,
      Offset position,
      Color couleur, {
      _Alignement alignement = _Alignement.centre,
      double rotation = 0,
      double taille = 11,
    }) => _texte(
      canvas,
      texte,
      position,
      couleur,
      alignement: alignement,
      rotation: rotation,
      taille: taille,
      limite: size,
      fond: c.fond,
    );
    const gauche = 40.0, droite = 70.0, haut = 24.0, bas = 36.0;
    final g = r.giron;
    final h = r.contremarche;
    final echelle = math.min(
      (size.width - gauche - droite) / g,
      (size.height - haut - bas) / h,
    );
    final largeur = g * echelle;
    final hauteur = h * echelle;
    final x0 = gauche + (size.width - gauche - droite - largeur) / 2;
    final y1 = haut + (size.height - haut - bas - hauteur) / 2 + hauteur;
    final a = Offset(x0, y1); // pied de la pente
    final b = Offset(x0 + largeur, y1); // angle droit
    final cc = Offset(x0 + largeur, y1 - hauteur); // haut de la contremarche

    final triangle = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(cc.dx, cc.dy)
      ..close();
    canvas.drawPath(triangle, Paint()..color = c.bois);
    canvas.drawPath(
      triangle,
      Paint()
        ..color = c.trait
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Angle droit.
    const q = 9.0;
    canvas.drawPath(
      Path()
        ..moveTo(b.dx - q, b.dy)
        ..lineTo(b.dx - q, b.dy - q)
        ..lineTo(b.dx, b.dy - q),
      Paint()
        ..color = c.trait
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final theta = math.atan2(h, g);
    final arcPaint = Paint()
      ..color = c.cote
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    // Pente, au pied.
    final rayon = math.min(largeur, hauteur) * 0.42 + 12;
    canvas.drawArc(
      Rect.fromCircle(center: a, radius: rayon),
      -theta,
      theta,
      false,
      arcPaint,
    );
    t(
      e.pente,
      a +
          Offset(
            (rayon + 6) * math.cos(theta / 2),
            -(rayon + 6) * math.sin(theta / 2) * 0.6,
          ) +
          const Offset(24, 0),
      c.cote,
      alignement: _Alignement.centre,
    );
    // Angle du haut (90° − pente).
    final rayon2 = math.min(largeur, hauteur) * 0.3 + 8;
    canvas.drawArc(
      Rect.fromCircle(center: cc, radius: rayon2),
      math.pi / 2,
      math.pi / 2 - theta,
      false,
      arcPaint,
    );
    t(
      e.angleHaut,
      cc + Offset(-rayon2 - 4, rayon2 + 6),
      c.cote,
      alignement: _Alignement.droite,
    );

    // Cotes : giron en bas, contremarche à droite, diagonale sur la pente.
    final cote = Paint()
      ..color = c.cote
      ..strokeWidth = 1.2;
    _cote(canvas, a + const Offset(0, 14), b + const Offset(0, 14), cote);
    t('Giron ${e.giron}', Offset((a.dx + b.dx) / 2, a.dy + 26), c.cote);
    _cote(canvas, b + const Offset(14, 0), cc + const Offset(14, 0), cote);
    t(
      'Contremarche',
      Offset(b.dx + 30, (b.dy + cc.dy) / 2 - 8),
      c.cote,
      alignement: _Alignement.gauche,
    );
    t(
      e.contremarche,
      Offset(b.dx + 30, (b.dy + cc.dy) / 2 + 8),
      c.cote,
      alignement: _Alignement.gauche,
    );
    t(
      'Diagonale ${e.diagonale}',
      Offset((a.dx + cc.dx) / 2 - 10, (a.dy + cc.dy) / 2 - 12),
      c.trait,
      rotation: -theta,
    );
  }

  @override
  bool shouldRepaint(_PeintreGabarit old) =>
      !identical(old.r, r) || old.e.pente != e.pente || old.e.giron != e.giron;
}

// -----------------------------------------------------------------------------
// Pied et tête : le profil du limon, agrandi
// -----------------------------------------------------------------------------

/// Passage du repère du limon (pouces, y vers le haut) au dessin (pixels).
class _Fenetre {
  final double xMin, xMax, yMin, yMax;
  final Size taille;
  late final double echelle;
  late final double ox, oy;

  _Fenetre(this.xMin, this.xMax, this.yMin, this.yMax, this.taille) {
    echelle = math.min(
      taille.width / (xMax - xMin),
      taille.height / (yMax - yMin),
    );
    ox = (taille.width - (xMax - xMin) * echelle) / 2;
    oy = taille.height - (taille.height - (yMax - yMin) * echelle) / 2;
  }

  Offset p(double x, double y) =>
      Offset(ox + (x - xMin) * echelle, oy - (y - yMin) * echelle);
}

void _peindreProfil(
  Canvas canvas,
  ResultatEscalier r,
  _Fenetre f,
  _Couleurs c,
) {
  final trait = Paint()
    ..color = c.trait
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  canvas.save();
  canvas.clipRect(Offset.zero & f.taille);
  // Marches voisines (contexte) puis limon.
  final chemin = Path();
  for (var i = 0; i < r.profil.length; i++) {
    final o = f.p(r.profil[i].x, r.profil[i].y);
    i == 0 ? chemin.moveTo(o.dx, o.dy) : chemin.lineTo(o.dx, o.dy);
  }
  chemin.close();
  canvas.drawPath(chemin, Paint()..color = c.bois);
  canvas.drawPath(chemin, trait);
  final s = r.spec;
  for (final t in r.table) {
    final x0 = (t.marche - 1) * r.giron - s.nez;
    final x1 = t.marche * r.giron;
    final rect = Rect.fromPoints(
      f.p(x0, t.hauteurDessus),
      f.p(x1, t.hauteurSiege),
    );
    canvas.drawRect(rect, Paint()..color = c.marche);
    canvas.drawRect(rect, trait);
  }
  canvas.restore();
}

class _PeintrePied extends CustomPainter {
  final ResultatEscalier r;
  final EtiquettesCoupes e;
  final _Couleurs c;
  _PeintrePied(this.r, this.e, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.fond);
    void t(
      String texte,
      Offset position,
      Color couleur, {
      _Alignement alignement = _Alignement.centre,
      double rotation = 0,
      double taille = 11,
    }) => _texte(
      canvas,
      texte,
      position,
      couleur,
      alignement: alignement,
      rotation: rotation,
      taille: taille,
      limite: size,
      fond: c.fond,
    );
    final xBas = r.coupePied;
    final f = _Fenetre(
      -5.5,
      math.max(2 * r.giron, xBas + 4),
      -4.0,
      math.max(2 * r.contremarche, r.hauteurDepart + 3) + 1,
      size,
    );
    // Plancher du bas.
    final sol = Paint()
      ..color = c.trait.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(f.p(f.xMin, 0), f.p(f.xMax, 0), sol);
    t(
      'Plancher du bas',
      f.p(f.xMax, -0.9),
      c.trait,
      alignement: _Alignement.droite,
      taille: 10,
    );
    _peindreProfil(canvas, r, f, c);

    final cote = Paint()
      ..color = c.cote
      ..strokeWidth = 1.2;
    // Coupe d'aplomb du bas : verticale, à gauche.
    final xa = -2.2;
    _cote(canvas, f.p(xa, 0), f.p(xa, r.hauteurDepart), cote);
    t(
      'Aplomb ${e.aplombBas}',
      f.p(xa - 0.9, r.hauteurDepart / 2),
      c.cote,
      rotation: -math.pi / 2,
    );
    // Coupe de niveau : sur le plancher, sous la ligne.
    final yn = -1.6;
    _cote(canvas, f.p(0, yn), f.p(xBas, yn), cote);
    t('Niveau ${e.niveauPied}', f.p(xBas / 2, yn - 1.1), c.cote);
    // Pente : angle entre le plancher et le dessous du limon.
    final theta = math.atan2(r.contremarche, r.giron);
    final centre = f.p(xBas, 0);
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: 26),
      -theta,
      theta,
      false,
      Paint()
        ..color = c.cote
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    t(e.pente, centre + const Offset(58, -4), c.cote);
  }

  @override
  bool shouldRepaint(_PeintrePied old) => !identical(old.r, r);
}

class _PeintreTete extends CustomPainter {
  final ResultatEscalier r;
  final EtiquettesCoupes e;
  final _Couleurs c;
  _PeintreTete(this.r, this.e, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = c.fond);
    void t(
      String texte,
      Offset position,
      Color couleur, {
      _Alignement alignement = _Alignement.centre,
      double rotation = 0,
      double taille = 11,
    }) => _texte(
      canvas,
      texte,
      position,
      couleur,
      alignement: alignement,
      rotation: rotation,
      taille: taille,
      limite: size,
      fond: c.fond,
    );
    final h = r.spec.hauteurTotale;
    final haut = r.hauteurPointeHaute;
    final f = _Fenetre(
      r.course - 2 * r.giron - 2,
      r.course + 15,
      haut - r.coupeTete - 4,
      h + 5,
      size,
    );
    // Plancher du haut (à partir de la face de la poutre).
    final sol = Paint()
      ..color = c.trait.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(f.p(r.course, h), f.p(f.xMax, h), sol);
    t(
      'Plancher du haut',
      f.p(f.xMax, h + 1.3),
      c.trait,
      alignement: _Alignement.droite,
      taille: 10,
    );
    _peindreProfil(canvas, r, f, c);

    final cote = Paint()
      ..color = c.cote
      ..strokeWidth = 1.2;
    // Coupe d'aplomb de la tête : contre la poutre, à droite.
    final xa = r.course + 2.2;
    _cote(canvas, f.p(xa, haut - r.coupeTete), f.p(xa, haut), cote);
    t(
      'Aplomb ${e.aplombTete}',
      f.p(xa + 1.1, haut - r.coupeTete / 2),
      c.cote,
      rotation: -math.pi / 2,
    );
    // Pointe du haut.
    final pointe = f.p(r.course, haut);
    canvas.drawCircle(pointe, 3.5, Paint()..color = c.cote);
    t(
      'Pointe à ${e.pointeHaute}',
      pointe + const Offset(-10, -16),
      c.cote,
      alignement: _Alignement.droite,
    );
  }

  @override
  bool shouldRepaint(_PeintreTete old) => !identical(old.r, r);
}
