import 'dart:math' as math;

import 'escalier.dart';
import 'escalier_composite.dart';
import 'geometrie.dart';
import 'solides.dart';
import 'unites.dart';

/// Vue 3D d'un escalier en composite, comme la photo de référence de Philip : les limons, le
/// backing 2x derrière chaque contremarche, les 2x12 à plat aux côtés des marches et les fascias.
/// La marche du haut est posée en cadre (nez, deux côtés en onglet, planches du centre) ; les
/// autres sont laissées ouvertes pour qu'on voie la structure. Un bout du plancher du haut
/// (rive et dessus) situe l'escalier.
///
/// Repère : x en travers de l'escalier (0 : face extérieure du limon de gauche, en montant),
/// y dans le sens de la montée (0 : face de la coupe de départ des limons), z vers le haut
/// (0 : plancher fini du bas). Les limons sont tranchés marche par marche : chaque tranche est
/// convexe, ce que demande l'ordre d'affichage de la vue 3D.
///
/// Escalier en bois (sans composite) : scène vide.

/// Épaisseur de la fascia, pour le dessin seulement (elle n'entre pas dans le calcul).
const double _epFascia = 0.75;

/// Rive et dessus du plancher du haut, pour situer l'escalier.
const double _hauteurRive = 9.25;
const double _profondeurPlancherHaut = 30;

class _Pieces {
  final bool metrique;
  final List<Solide> solides = [];
  final Map<String, InfoPiece> infos = {};
  int _id = 0;
  _Pieces(this.metrique);

  String l(double po) => formatLongueur(po, metrique: metrique);

  /// Prisme vertical sur un polygone en plan (anti-horaire).
  void prisme(
    String groupe,
    Matiere matiere,
    List<Pt> plan,
    double z0,
    double z1,
  ) {
    if (z1 - z0 < 1e-6 || aireSignee(plan).abs() < 1e-6) {
      return;
    }
    solides.add(
      extrusionHorizontale(
        id: _id++,
        groupe: groupe,
        calque: Calque.escalier,
        matiere: matiere,
        boucles: [aireSignee(plan) > 0 ? plan : plan.reversed.toList()],
        z0: z0,
        z1: z1,
      ),
    );
  }

  void boite(
    String groupe,
    Matiere matiere,
    double x0,
    double x1,
    double y0,
    double y1,
    double z0,
    double z1,
  ) {
    if (x1 - x0 < 1e-6 || y1 - y0 < 1e-6) {
      return;
    }
    prisme(
      groupe,
      matiere,
      [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)],
      z0,
      z1,
    );
  }

  /// Plaque verticale de [x0] à [x1] (épaisseur en travers de l'escalier) sur le contour
  /// [profil], en (y, z).
  void plaqueX(
    String groupe,
    Matiere matiere,
    double x0,
    double x1,
    List<Pt> profil,
  ) {
    final aire = aireSignee(profil);
    if (aire.abs() < 1e-6) {
      return;
    }
    final p = aire > 0 ? profil : profil.reversed.toList();
    final faces = <Face>[
      Face([
        [for (final q in p) P3(x1, q.x, q.y)],
      ], const P3(1, 0, 0)),
      Face([
        [for (final q in p.reversed) P3(x0, q.x, q.y)],
      ], const P3(-1, 0, 0)),
    ];
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      final d = b - a;
      final lg = d.longueur;
      if (lg < 1e-9) {
        continue;
      }
      faces.add(
        Face(
          [
            [
              P3(x0, a.x, a.y),
              P3(x1, a.x, a.y),
              P3(x1, b.x, b.y),
              P3(x0, b.x, b.y),
            ],
          ],
          // Contour anti-horaire en (y, z) : la normale sortante est (dz, −dy).
          P3(0, d.y / lg, -d.x / lg),
          laterale: true,
        ),
      );
    }
    final ys = [for (final q in p) q.x];
    final zs = [for (final q in p) q.y];
    final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
    solides.add(
      Solide(
        id: _id++,
        groupe: groupe,
        calque: Calque.escalier,
        matiere: matiere,
        coque: [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)],
        z0: zs.reduce(math.min),
        z1: zs.reduce(math.max),
        faces: faces,
      ),
    );
  }
}

Scene sceneEscalier(ResultatEscalier r, {required bool metrique}) {
  final s = r.spec;
  final produit = s.composite;
  if (produit == null) {
    return Scene.vide;
  }
  final c = calculerComposite(r);
  final p = _Pieces(metrique);
  String l(double po) => p.l(po);

  final n = r.nombreContremarches;
  final g = r.giron;
  final h = r.contremarche;
  final t = s.epaisseurMarcheEffective;
  final largeur = s.largeur;
  final ep = s.section.epaisseur;
  final e = r.espacementReel;

  // Dessous des limons : à plat sur le plancher, puis parallèle à la pente (du bout du dessous à
  // la coupe de tête).
  final finDessous = r.profil.last;
  final basTete = r.profil[r.profil.length - 2];
  final pente = (basTete.y - finDessous.y) / (basTete.x - finDessous.x);
  double dessous(double y) =>
      y <= finDessous.x ? 0 : (y - finDessous.x) * pente;

  // Limons, une tranche par marche : du devant du siège k (coupe d'aplomb) à la coupe suivante.
  for (var i = 0; i < r.nombreLimons; i++) {
    final x0 = i * e;
    final groupe = 'limon$i';
    p.infos[groupe] = InfoPiece('Limon ${i + 1} de ${r.nombreLimons}', [
      'Section : ${s.section.nom}',
      'Longueur à couper : ${l(r.longueurLimon)}',
      'Planche : ${formatPlanche(r.longueurCommerciale, metrique: metrique)}',
      'Entraxe : ${l(e)}',
    ]);
    for (var k = 1; k < n; k++) {
      final y0 = (k - 1) * g, y1 = k * g;
      final dessus = k * h - t;
      final profil = <Pt>[
        Pt(y0, dessous(y0)),
        if (finDessous.x > y0 && finDessous.x < y1) Pt(finDessous.x, 0),
        Pt(y1, dessous(y1)),
        Pt(y1, dessus),
        Pt(y0, dessus),
      ];
      if (dessus - math.max(dessous(y0), dessous(y1)) > 0.05) {
        p.plaqueX(groupe, Matiere.bois, x0, x0 + ep, profil);
      }
    }
  }

  // Contremarches : backing 2x vissé sur la coupe d'aplomb des limons, la fascia devant ; du siège
  // de la marche du dessous au siège de la marche du dessus (la hauteur de la contremarche).
  for (var k = 1; k <= n; k++) {
    final yCoupe = (k - 1) * g;
    final z0 = math.max(0.0, (k - 1) * h - t);
    final z1 = k * h - t;
    final backing = 'backing$k';
    p.infos[backing] = InfoPiece('Backing de la contremarche $k', [
      'Section : ${c.sectionBacking}',
      'Longueur à couper : ${l(largeur)}',
      'Refendu à ${l(z1 - z0)} de haut, vissé sur la coupe d\'aplomb des limons',
    ]);
    p.boite(
      backing,
      Matiere.bois,
      0,
      largeur,
      yCoupe - epaisseurBacking,
      yCoupe,
      z0,
      z1,
    );
    final fascia = 'fascia$k';
    p.infos[fascia] = InfoPiece('Fascia de la contremarche $k', [
      'Pièce : ${l(largeur)} × ${l(z1 - z0)}',
      '${produit.marque}, vissée dans le backing',
    ]);
    p.boite(
      fascia,
      Matiere.fascia,
      0,
      largeur,
      yCoupe - epaisseurBacking - _epFascia,
      yCoupe - epaisseurBacking,
      z0,
      z1,
    );
  }

  // 2x12 à plat aux côtés : entre le limon de côté et le suivant, le dessus à égalité du siège,
  // du devant du siège au backing de la contremarche du dessus.
  final travees = c.blocsParMarche == 2
      ? [(ep, e), (largeur - e, largeur - ep)]
      : [(ep, largeur - ep)];
  for (var k = 1; k < n; k++) {
    final dessus = k * h - t;
    for (final (j, (x0, x1)) in travees.indexed) {
      final groupe = 'bloc$k.$j';
      p.infos[groupe] = InfoPiece('2x12 à plat', [
        'Section : 2x12',
        'Longueur à couper : ${l(c.longueurBloc)}',
        'Refendu à ${l(c.profondeurBloc)} de profond, le dessus à égalité du siège',
      ]);
      p.boite(
        groupe,
        Matiere.bloc,
        x0,
        x1,
        (k - 1) * g,
        k * g - epaisseurBacking,
        dessus - 1.5,
        dessus,
      );
    }
  }

  // La marche du haut, posée en cadre : du fond (contre la fascia du dessus) au nez, qui dépasse
  // la fascia de la contremarche.
  if (n >= 2) {
    final k = n - 1;
    final b = produit.largeur;
    final avant = (k - 1) * g - epaisseurBacking - _epFascia - s.nez;
    final fond = k * g - epaisseurBacking - _epFascia;
    final z0 = k * h - t, z1 = k * h;
    p.infos['nez'] = InfoPiece('Nez de marche', [
      'Longueur à couper : ${l(largeur)}',
      '${produit.nom}, en onglet aux deux bouts',
    ]);
    p.prisme(
      'nez',
      Matiere.composite,
      [
        Pt(0, avant),
        Pt(largeur, avant),
        Pt(largeur - b, avant + b),
        Pt(b, avant + b),
      ],
      z0,
      z1,
    );
    p.infos['cotes'] = InfoPiece('Côté de marche', [
      'Longueur à couper : ${l(r.profondeurMarche)}',
      'En onglet contre le nez',
    ]);
    p.prisme(
      'cotes',
      Matiere.composite,
      [Pt(0, avant), Pt(b, avant + b), Pt(b, fond), Pt(0, fond)],
      z0,
      z1,
    );
    p.prisme(
      'cotes',
      Matiere.composite,
      [
        Pt(largeur, avant),
        Pt(largeur, fond),
        Pt(largeur - b, fond),
        Pt(largeur - b, avant + b),
      ],
      z0,
      z1,
    );
    p.infos['centre'] = InfoPiece('Planche du centre', [
      'Longueur à couper : ${l(c.longueurCentre)}',
      'Écart de ${l(produit.ecartBout)} au bout contre les côtés',
    ]);
    for (var j = 0; j < c.rangsCentre; j++) {
      final y0 = avant + b + produit.ecart + j * (b + produit.ecart);
      p.boite(
        'centre',
        Matiere.composite,
        b + produit.ecartBout,
        largeur - b - produit.ecartBout,
        y0,
        math.min(y0 + b, fond),
        z0,
        z1,
      );
    }
  }

  // Plancher du haut : la rive où les limons s'accrochent, et le dessus qui dépasse la fascia de
  // la dernière contremarche comme un nez.
  final course = r.course;
  final hauteur = s.hauteurTotale;
  p.infos['plancher'] = InfoPiece('Plancher du haut', [
    'Hauteur : ${l(hauteur)} au-dessus du plancher du bas',
  ]);
  p.boite(
    'plancher',
    Matiere.rive,
    0,
    largeur,
    course,
    course + 1.5,
    hauteur - t - _hauteurRive,
    hauteur - t,
  );
  p.boite(
    'plancher',
    Matiere.composite,
    0,
    largeur,
    course - epaisseurBacking - _epFascia - s.nez,
    course + _profondeurPlancherHaut,
    hauteur - t,
    hauteur,
  );

  // Cotes : hauteur totale, course et largeur.
  final cotes = [
    Cote(
      P3(largeur + 4, -epaisseurBacking - _epFascia, 0),
      P3(largeur + 4, -epaisseurBacking - _epFascia, hauteur),
      'Hauteur ${l(hauteur)}',
      Calque.escalier,
    ),
    Cote(
      P3(largeur + 4, 0, -2),
      P3(largeur + 4, course, -2),
      'Course ${l(course)}',
      Calque.escalier,
    ),
    Cote(
      P3(0, -epaisseurBacking - _epFascia - 4, 0),
      P3(largeur, -epaisseurBacking - _epFascia - 4, 0),
      'Largeur ${l(largeur)}',
      Calque.escalier,
    ),
  ];

  var min = const P3(double.infinity, double.infinity, double.infinity);
  var max = const P3(-double.infinity, -double.infinity, -double.infinity);
  for (final so in p.solides) {
    for (final q in so.coque) {
      min = P3(math.min(min.x, q.x), math.min(min.y, q.y), min.z);
      max = P3(math.max(max.x, q.x), math.max(max.y, q.y), max.z);
    }
    min = P3(min.x, min.y, math.min(min.z, so.z0));
    max = P3(max.x, max.y, math.max(max.z, so.z1));
  }
  return Scene(
    solides: p.solides,
    infos: p.infos,
    cotes: cotes,
    min: min,
    max: max,
  );
}
