import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../charpente/escalier.dart';
import '../../charpente/unites.dart';

/// Schéma de côté du limon : contour, marches, plancher du haut et du bas, avec
/// la hauteur totale, la course, la 1re contremarche, le 1er giron et la pente.
class SchemaLimon extends StatelessWidget {
  final ResultatEscalier resultat;
  final bool metrique;
  const SchemaLimon({super.key, required this.resultat, required this.metrique});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1.35,
      child: CustomPaint(
        key: const ValueKey('schema_limon'),
        painter: _PeintreLimon(
          resultat: resultat,
          metrique: metrique,
          bois: const Color(0xFFD9B27C),
          marche: const Color(0xFF9C6B3A),
          trait: scheme.onSurface,
          cote: scheme.primary,
          fond: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _PeintreLimon extends CustomPainter {
  final ResultatEscalier resultat;
  final bool metrique;
  final Color bois;
  final Color marche;
  final Color trait;
  final Color cote;
  final Color fond;

  _PeintreLimon({
    required this.resultat,
    required this.metrique,
    required this.bois,
    required this.marche,
    required this.trait,
    required this.cote,
    required this.fond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = resultat;
    final s = r.spec;
    canvas.drawRect(Offset.zero & size, Paint()..color = fond);

    // Monde (pouces) : x vers le haut de l'escalier, y vers le haut.
    const margeG = 64.0;
    const margeD = 16.0;
    const margeH = 18.0;
    const margeB = 44.0;
    final xMin = -s.nez - 1;
    final xMax = r.course + math.max(10.0, r.giron);
    const yMin = -1.0;
    final yMax = s.hauteurTotale + 4;
    final echelle = math.min(
      (size.width - margeG - margeD) / (xMax - xMin),
      (size.height - margeH - margeB) / (yMax - yMin),
    );
    Offset p(double x, double y) => Offset(
      margeG + (x - xMin) * echelle,
      size.height - margeB - (y - yMin) * echelle,
    );

    final traitFin = Paint()
      ..color = trait
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Planchers.
    final sol = Paint()
      ..color = trait.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(p(xMin, 0), p(r.course * 0.35, 0), sol);
    canvas.drawLine(p(r.course, s.hauteurTotale), p(xMax, s.hauteurTotale), sol);

    // Limon.
    final chemin = Path()..moveTo(p(r.profil.first.x, r.profil.first.y).dx, p(r.profil.first.x, r.profil.first.y).dy);
    for (final q in r.profil.skip(1)) {
      final o = p(q.x, q.y);
      chemin.lineTo(o.dx, o.dy);
    }
    chemin.close();
    canvas.drawPath(chemin, Paint()..color = bois);
    canvas.drawPath(chemin, traitFin);

    // Marches : siège k de (k − 1) × G à k × G, dessus à k × R, nez en avant.
    for (final t in r.table) {
      final x0 = (t.marche - 1) * r.giron - s.nez;
      final x1 = t.marche * r.giron;
      final rect = Rect.fromPoints(p(x0, t.hauteurDessus), p(x1, t.hauteurSiege));
      canvas.drawRect(rect, Paint()..color = marche);
      canvas.drawRect(rect, traitFin);
    }

    // Cotes.
    final cotePaint = Paint()
      ..color = cote
      ..strokeWidth = 1.2;
    String l(double po) => formatLongueur(po, metrique: metrique);

    // Hauteur totale, à gauche.
    final xh = xMin + 0.0;
    canvas.drawLine(p(xh - 1.5, 0), p(xh - 1.5, s.hauteurTotale), cotePaint);
    canvas.drawLine(p(xh - 2.5, 0), p(xh, 0), cotePaint);
    canvas.drawLine(p(xh - 2.5, s.hauteurTotale), p(xh, s.hauteurTotale), cotePaint);
    _texte(
      canvas,
      l(s.hauteurTotale),
      p(xh - 1.5, s.hauteurTotale / 2) + const Offset(-6, 0),
      cote,
      alignement: _Alignement.droite,
      rotation: -math.pi / 2,
    );

    // Course, en bas.
    final yc = -1.0;
    canvas.drawLine(p(0, yc), p(r.course, yc), cotePaint);
    canvas.drawLine(p(0, yc - 0.5), p(0, yc + 0.5), cotePaint);
    canvas.drawLine(p(r.course, yc - 0.5), p(r.course, yc + 0.5), cotePaint);
    _texte(
      canvas,
      'Course ${l(r.course)}',
      p(r.course / 2, yc) + const Offset(0, 8),
      cote,
      alignement: _Alignement.centre,
    );

    // Légende dans le coin vide, en haut à gauche (au-dessus du limon).
    final legende = [
      '${r.nombreContremarches} contremarches de ${l(r.contremarche)}',
      '${r.nombreMarches} marches, giron ${l(r.giron)}',
      'Pente ${formatAngle(r.angle)}',
    ];
    for (var i = 0; i < legende.length; i++) {
      _texte(
        canvas,
        legende[i],
        Offset(margeG + 10, margeH + 8 + i * 15),
        trait,
        alignement: _Alignement.gauche,
      );
    }
  }

  void _texte(
    Canvas canvas,
    String texte,
    Offset position,
    Color couleur, {
    _Alignement alignement = _Alignement.centre,
    double rotation = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texte,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    final dx = switch (alignement) {
      _Alignement.centre => -tp.width / 2,
      _Alignement.gauche => 0.0,
      _Alignement.droite => -tp.width,
    };
    tp.paint(canvas, Offset(dx, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeintreLimon old) =>
      !identical(old.resultat, resultat) || old.metrique != metrique;
}

enum _Alignement { gauche, centre, droite }
