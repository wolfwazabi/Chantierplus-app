import 'dart:math' as math;

import 'composite.dart';
import 'escalier.dart';
import 'escalier_composite.dart';
import 'geometrie.dart';
import 'solides.dart';
import 'unites.dart';

/// Vue 3D d'un escalier. En composite, comme la photo de référence de Philip : les limons, les
/// fascias des contremarches vissées sur les limons et les 2x12 à plat aux côtés des marches ; la
/// marche du haut est posée en cadre (nez, deux côtés en onglet, planches du centre) et les
/// autres sont laissées ouvertes pour qu'on voie la structure. En bois : les limons, les marches
/// et les contremarches fermées. Seul, un bout du plancher du haut (rive et dessus) situe
/// l'escalier ; jumelé à un plancher ([placerEscalier]), c'est le vrai plancher.
///
/// Repère : x en travers de l'escalier (0 : face extérieure du limon de gauche, en montant),
/// y dans le sens de la montée (0 : face de la coupe de départ des limons), z vers le haut
/// (0 : plancher fini du bas). Les limons sont tranchés marche par marche : chaque tranche est
/// convexe, ce que demande l'ordre d'affichage de la vue 3D.

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
  /// [profil], en (y, z). [internes] : arêtes du profil (i : du point i au suivant) partagées avec
  /// la tranche voisine de la même pièce — ni trait ni chant : la pièce paraît pleine.
  void plaqueX(
    String groupe,
    Matiere matiere,
    double x0,
    double x1,
    List<Pt> profil, {
    Set<int> internes = const {},
  }) {
    final aire = aireSignee(profil);
    if (aire.abs() < 1e-6) {
      return;
    }
    final m = profil.length;
    // Contour retourné : l'arête i devient l'arête m − 2 − i.
    Set<int> retourne(Set<int> s) => {for (final i in s) (m - 2 - i) % m};
    final p = aire > 0 ? profil : profil.reversed.toList();
    final cachees = aire > 0 ? internes : retourne(internes);
    final faces = <Face>[
      Face(
        [
          [for (final q in p) P3(x1, q.x, q.y)],
        ],
        const P3(1, 0, 0),
        aretesSansTrait: cachees,
      ),
      Face(
        [
          [for (final q in p.reversed) P3(x0, q.x, q.y)],
        ],
        const P3(-1, 0, 0),
        aretesSansTrait: retourne(cachees),
      ),
    ];
    for (var i = 0; i < p.length; i++) {
      // Chant intérieur, caché par la tranche voisine.
      if (cachees.contains(i)) continue;
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

/// [jumele] : l'escalier descend d'un plancher du projet (pas de bout de plancher dessiné ; en
/// composite, la plus haute contremarche est la fascia du plancher).
Scene sceneEscalier(
  ResultatEscalier r, {
  required bool metrique,
  bool jumele = false,
}) {
  final s = r.spec;
  final produit = s.composite;
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
      // Joints avec les tranches voisines : à droite toute la coupe (la tranche suivante est plus
      // haute), à gauche sous le siège de la marche d'avant (au-dessus, c'est la vraie coupe
      // d'aplomb).
      final profil = <Pt>[];
      final internes = <int>{};
      void point(Pt q, {bool jointVersSuivant = false}) {
        if (jointVersSuivant) internes.add(profil.length);
        profil.add(q);
      }

      point(Pt(y0, dessous(y0)));
      if (finDessous.x > y0 && finDessous.x < y1) point(Pt(finDessous.x, 0));
      point(Pt(y1, dessous(y1)), jointVersSuivant: k < n - 1);
      point(Pt(y1, dessus));
      point(Pt(y0, dessus));
      if (k > 1) point(Pt(y0, (k - 1) * h - t), jointVersSuivant: true);
      if (dessus - math.max(dessous(y0), dessous(y1)) > 0.05) {
        p.plaqueX(
          groupe,
          Matiere.bois,
          x0,
          x0 + ep,
          profil,
          internes: internes,
        );
      }
    }
  }

  if (produit != null) {
    _composite(p, r, produit, jumele: jumele);
  } else {
    _bois(p, r, jumele: jumele);
  }

  // Plancher du haut, seul : la rive où les limons s'accrochent, et le dessus qui dépasse la
  // dernière contremarche comme un nez.
  final course = r.course;
  final hauteur = s.hauteurTotale;
  if (!jumele) {
    final devant = produit != null
        ? _epFascia
        : (s.contremarchesFermees ? s.epaisseurContremarche : 0.0);
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
      produit != null ? Matiere.composite : Matiere.sousPlancher,
      0,
      largeur,
      course - devant - s.nez,
      course + _profondeurPlancherHaut,
      hauteur - t,
      hauteur,
    );
  }

  // Cotes : hauteur totale, course et largeur.
  final cotes = [
    Cote(
      P3(largeur + 4, -_epFascia, 0),
      P3(largeur + 4, -_epFascia, hauteur),
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
      P3(0, -_epFascia - 4, 0),
      P3(largeur, -_epFascia - 4, 0),
      'Largeur ${l(largeur)}',
      Calque.escalier,
    ),
  ];
  return _scene(p.solides, p.infos, cotes);
}

/// Composite : fascias, 2x12 à plat aux côtés, la marche du haut en cadre.
void _composite(
  _Pieces p,
  ResultatEscalier r,
  ProduitComposite produit, {
  required bool jumele,
}) {
  final s = r.spec;
  final c = calculerComposite(r);
  String l(double po) => p.l(po);
  final n = r.nombreContremarches;
  final g = r.giron;
  final h = r.contremarche;
  final t = s.epaisseurMarcheEffective;
  final largeur = s.largeur;
  final ep = s.section.epaisseur;
  final e = r.espacementReel;

  // Contremarches : la fascia vissée directement sur la coupe d'aplomb des limons, du siège de la
  // marche du dessous au siège de la marche du dessus (la hauteur de la contremarche). Jumelé à un
  // plancher, la plus haute est la fascia du plancher.
  for (var k = 1; k <= (jumele ? n - 1 : n); k++) {
    final yCoupe = (k - 1) * g;
    final z0 = math.max(0.0, (k - 1) * h - t);
    final z1 = k * h - t;
    final fascia = 'fascia$k';
    p.infos[fascia] = InfoPiece('Fascia de la contremarche $k', [
      'Pièce : ${l(largeur)} × ${l(z1 - z0)}',
      '${produit.marque}, vissée sur les limons',
    ]);
    p.boite(
      fascia,
      Matiere.fascia,
      0,
      largeur,
      yCoupe - _epFascia,
      yCoupe,
      z0,
      z1,
    );
  }

  // 2x12 à plat aux côtés : entre le limon de côté et le suivant, le dessus à égalité du siège,
  // pleine largeur (11 1/4) depuis le devant du siège ; il passe sous la fascia du dessus, mais
  // s'arrête à la rive du plancher du haut.
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
        'Le dessus à égalité du siège du limon',
      ]);
      p.boite(
        groupe,
        Matiere.bloc,
        x0,
        x1,
        (k - 1) * g,
        math.min((k - 1) * g + 11.25, r.course),
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
    final avant = (k - 1) * g - _epFascia - s.nez;
    // Jumelé : jusqu'à la fascia du plancher, qui fait la contremarche du haut.
    final fond = jumele ? k * g : k * g - _epFascia;
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
}

/// Bois : une marche sur chaque siège (giron + nez), les contremarches si elles sont fermées.
void _bois(_Pieces p, ResultatEscalier r, {required bool jumele}) {
  final s = r.spec;
  String l(double po) => p.l(po);
  final n = r.nombreContremarches;
  final g = r.giron;
  final h = r.contremarche;
  final t = s.epaisseurMarche;
  final largeur = s.largeur;
  final ec = s.contremarchesFermees ? s.epaisseurContremarche : 0.0;
  for (var k = 1; k < n; k++) {
    final groupe = 'marche$k';
    p.infos[groupe] = InfoPiece('Marche $k', [
      'Longueur à couper : ${l(largeur)}',
      'Profondeur : ${l(r.profondeurMarche)} (giron ${l(g)} + nez ${l(s.nez)})',
      'Épaisseur : ${l(t)}',
    ]);
    p.boite(
      groupe,
      Matiere.rive,
      0,
      largeur,
      (k - 1) * g - ec - s.nez,
      k * g - ec,
      k * h - t,
      k * h,
    );
  }
  if (!s.contremarchesFermees) return;
  for (var k = 1; k <= (jumele ? n - 1 : n); k++) {
    final groupe = 'contremarche$k';
    final z0 = math.max(0.0, (k - 1) * h - t), z1 = k * h - t;
    p.infos[groupe] = InfoPiece('Contremarche $k', [
      'Pièce : ${l(largeur)} × ${l(z1 - z0)}',
      'Épaisseur : ${l(ec)}',
    ]);
    p.boite(
      groupe,
      Matiere.bois,
      0,
      largeur,
      (k - 1) * g - ec,
      (k - 1) * g,
      z0,
      z1,
    );
  }
}

Scene _scene(
  List<Solide> solides,
  Map<String, InfoPiece> infos,
  List<Cote> cotes,
) {
  if (solides.isEmpty) return Scene.vide;
  var min = const P3(double.infinity, double.infinity, double.infinity);
  var max = const P3(-double.infinity, -double.infinity, -double.infinity);
  for (final so in solides) {
    for (final q in so.coque) {
      min = P3(math.min(min.x, q.x), math.min(min.y, q.y), min.z);
      max = P3(math.max(max.x, q.x), math.max(max.y, q.y), max.z);
    }
    min = P3(min.x, min.y, math.min(min.z, so.z0));
    max = P3(max.x, max.y, math.max(max.z, so.z1));
  }
  return Scene(
    solides: solides,
    infos: infos,
    cotes: cotes,
    min: min,
    max: max,
  );
}

/// L'escalier [s] (dans son repère) placé dans le repère d'un plancher : (x, y) = (0, 0) tombe sur
/// [origine], x suit [u] (en travers) et y suit [w] (le sens de la montée), z est décalé de
/// [dz]. Les pièces prennent le préfixe « escalier. ».
Scene placerEscalier(
  Scene s, {
  required Pt origine,
  required Pt u,
  required Pt w,
  required double dz,
}) {
  Pt plan(Pt q) => origine + u * q.x + w * q.y;
  P3 point(P3 q) {
    final pp = plan(Pt(q.x, q.y));
    return P3(pp.x, pp.y, q.z + dz);
  }

  P3 direction(P3 v) {
    final d = u * v.x + w * v.y;
    return P3(d.x, d.y, v.z);
  }

  return _scene(
    [
      for (final so in s.solides)
        Solide(
          id: so.id,
          groupe: 'escalier.${so.groupe}',
          calque: so.calque,
          matiere: so.matiere,
          coque: [for (final q in so.coque) plan(q)],
          z0: so.z0 + dz,
          z1: so.z1 + dz,
          faces: [
            for (final f in so.faces)
              Face(
                [
                  for (final b in f.boucles) [for (final q in b) point(q)],
                ],
                direction(f.normale),
                laterale: f.laterale,
                aretesSansTrait: f.aretesSansTrait,
              ),
          ],
        ),
    ],
    {for (final e in s.infos.entries) 'escalier.${e.key}': e.value},
    [for (final c in s.cotes) Cote(point(c.a), point(c.b), c.texte, c.calque)],
  );
}
