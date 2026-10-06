import 'dart:math' as math;

import 'geometrie.dart';
import 'mur.dart';
import 'plancher.dart';
import 'solides.dart';
import 'unites.dart';

export 'solides.dart' show Scene, Solide, Calque, Matiere, InfoPiece, Cote, P3;

/// Construit la scène 3D d'un projet : plancher (solives, rives, entremises,
/// sous-plancher) et murs (ossature, feuilles, membrane, fourrures, revêtement),
/// avec une fiche par pièce (dimensions, coupes) et des cotes.
///
/// Repère : x, y dans le plan du bâtiment (le contour du plancher est celui de
/// la forme), z vers le haut ; z = 0 : dessus du sous-plancher.

const double _epMembrane = 0.06;
const double _epPanneauMurDefaut = 0.4375; // OSB de 7/16 po
const double _epSousPlancherDefaut = 0.75; // 3/4 po

class _Constructeur {
  final bool metrique;
  final List<Solide> solides = [];
  final Map<String, InfoPiece> infos = {};
  final List<Cote> cotes = [];
  int _id = 0;

  _Constructeur(this.metrique);

  int get id => _id++;

  String l(double po) => formatLongueur(po, metrique: metrique);

  void ajouter(Solide? s) {
    if (s != null) {
      solides.add(s);
    }
  }

  void info(String groupe, String titre, List<String> lignes) {
    infos[groupe] = InfoPiece(titre, lignes);
  }

  Scene fin() {
    var min = const P3(double.infinity, double.infinity, double.infinity);
    var max = const P3(-double.infinity, -double.infinity, -double.infinity);
    for (final s in solides) {
      for (final p in s.coque) {
        min = P3(math.min(min.x, p.x), math.min(min.y, p.y), min.z);
        max = P3(math.max(max.x, p.x), math.max(max.y, p.y), max.z);
      }
      min = P3(min.x, min.y, math.min(min.z, s.z0));
      max = P3(max.x, max.y, math.max(max.z, s.z1));
    }
    if (solides.isEmpty) {
      return Scene.vide;
    }
    return Scene(
      solides: solides,
      infos: infos,
      cotes: cotes,
      min: min,
      max: max,
    );
  }
}

bool _horizontale(Pt p, Pt q) {
  final d = q - p;
  final longueur = d.longueur;
  return longueur > 0 && d.y.abs() / longueur < math.sin(0.05 * math.pi / 180);
}

double _cotDemi(double angleDeg) => 1 / math.tan(angleDeg * math.pi / 360);

// =============================================================================
// Plancher
// =============================================================================

void _ajouterPlancher(
  _Constructeur c,
  ResultatPlancher r,
  SectionBois section,
) {
  final spec = r.spec;
  final tSub = spec.panneau.epaisseur ?? _epSousPlancherDefaut;
  final zHaut = -tSub;
  final zBas = zHaut - section.profondeur;
  final f = r.formePivotee;
  final t = spec.epaisseurSolive;
  Pt versForme(Pt p) => r.versForme(p);

  // --- Solives ---------------------------------------------------------------
  var numero = 0;
  for (final s in r.solives) {
    numero++;
    final boucle =
        s.contour ??
        [
          Pt(s.u0 - t / 2 * s.penteDebut, s.v - t / 2),
          Pt(s.u1 - t / 2 * s.penteFin, s.v - t / 2),
          Pt(s.u1 + t / 2 * s.penteFin, s.v + t / 2),
          Pt(s.u0 + t / 2 * s.penteDebut, s.v + t / 2),
        ];
    final groupe = 'j$numero';
    c.ajouter(
      extrusionHorizontale(
        id: c.id,
        groupe: groupe,
        calque: Calque.solives,
        matiere: Matiere.bois,
        boucles: [boucle.map(versForme).toList()],
        z0: zBas,
        z1: zHaut,
      ),
    );
    final coupes = <String>[
      if (s.biseauDebutDeg > 0.5)
        'Coupe d\'angle au début : ${formatAngle(s.biseauDebutDeg)}',
      if (s.biseauFinDeg > 0.5)
        'Coupe d\'angle à la fin : ${formatAngle(s.biseauFinDeg)}',
    ];
    c.info(
      groupe,
      s.bordure
          ? (s.doublon ? 'Solive de bordure (doublée)' : 'Solive de bordure')
          : 'Solive',
      [
        'Section : ${section.nom}',
        'Longueur à couper : ${c.l(s.longueurCoupe)} (pointe longue)',
        if (!s.bordure) 'Entraxe : ${c.l(spec.espacement)}',
        ...coupes,
      ],
    );
  }

  // --- Solives de rive -------------------------------------------------------
  final e = spec.epaisseurRive;
  for (var k = 0; k < r.rives.length; k++) {
    final rive = r.rives[k];
    final i = rive.cote;
    final v = f.sommet(i), w = f.sommet(i + 1);
    final dir = (w - v).unitaire;
    final n = f.normaleInterieure(i);
    final ply = rive.doublon ? 1 : 0;
    final a = ply * e, b = (ply + 1) * e;
    final s0 = rive.depart, s1 = s0 + rive.longueur;
    final mitreDebut = rive.morceau == 0 && !_horizontale(f.sommet(i - 1), v);
    final mitreFin =
        rive.morceau == rive.morceaux - 1 && !_horizontale(w, f.sommet(i + 2));
    double recul(bool mitre, double angle, double profondeur) =>
        mitre ? profondeur * _cotDemi(angle) : 0;
    Pt pt(double s, double profondeur) => v + dir * s + n * profondeur;
    var boucle = [
      pt(s0 + recul(mitreDebut, rive.angleDebutDeg, a), a),
      pt(s1 - recul(mitreFin, rive.angleFinDeg, a), a),
      pt(s1 - recul(mitreFin, rive.angleFinDeg, b), b),
      pt(s0 + recul(mitreDebut, rive.angleDebutDeg, b), b),
    ];
    // Bout contre un côté parallèle aux solives : la rive ne dépasse pas la
    // face extérieure de ce côté (coin aigu).
    List<Pt> contre(List<Pt> poly, Pt coin, int arete) {
      final n2 = f.normaleInterieure(arete);
      return coupeDemiPlan(poly, -n2.x, -n2.y, -n2.dot(coin));
    }

    if (rive.morceau == 0 && !mitreDebut && rive.angleDebutDeg < 179.5) {
      boucle = contre(boucle, v, i - 1);
    }
    if (rive.morceau == rive.morceaux - 1 &&
        !mitreFin &&
        rive.angleFinDeg < 179.5) {
      boucle = contre(boucle, w, i + 1);
    }
    final groupe = 'r$k';
    c.ajouter(
      extrusionHorizontale(
        id: c.id,
        groupe: groupe,
        calque: Calque.solives,
        matiere: Matiere.rive,
        boucles: [boucle.map(versForme).toList()],
        z0: zBas,
        z1: zHaut,
      ),
    );
    c.info(groupe, rive.doublon ? 'Solive de rive (doublée)' : 'Solive de rive', [
      'Section : ${section.nom}',
      'Longueur à couper : ${c.l(rive.longueur)} (pointe longue)',
      if (rive.morceaux > 1)
        'Morceau ${rive.morceau + 1} de ${rive.morceaux} (à épisser sur une solive)',
      if (mitreDebut)
        'Coupe d\'angle au début : ${formatAngle(rive.angleDebutDeg / 2)} (coin de ${formatAngle(rive.angleDebutDeg)})',
      if (mitreFin)
        'Coupe d\'angle à la fin : ${formatAngle(rive.angleFinDeg / 2)} (coin de ${formatAngle(rive.angleFinDeg)})',
    ]);
  }

  // --- Entremises ------------------------------------------------------------
  for (var k = 0; k < r.entremisesPoses.length; k++) {
    final p = r.entremisesPoses[k];
    final boucle = [
      Pt(p.u - t / 2, p.v0),
      Pt(p.u + t / 2, p.v0),
      Pt(p.u + t / 2, p.v1),
      Pt(p.u - t / 2, p.v1),
    ];
    final groupe = 'e$k';
    c.ajouter(
      extrusionHorizontale(
        id: c.id,
        groupe: groupe,
        calque: Calque.solives,
        matiere: Matiere.bois,
        boucles: [boucle.map(versForme).toList()],
        z0: zBas,
        z1: zHaut,
      ),
    );
    c.info(groupe, 'Entremise', [
      'Section : ${section.nom}',
      'Longueur à couper : ${c.l(p.longueur)}',
    ]);
  }

  // --- Sous-plancher ---------------------------------------------------------
  final pn = r.panneaux;
  final b = f.boite;
  for (var k = 0; k < pn.poses.length; k++) {
    final p = pn.poses[k];
    final contour = polygoneDansRectangle(f.sommets, p.u0, p.u1, p.v0, p.v1);
    if (contour.length < 3 || aireSignee(contour).abs() < 1e-6) {
      continue;
    }
    final groupe = 'fs$k';
    final coque = [
      Pt(p.u0, p.v0),
      Pt(p.u1, p.v0),
      Pt(p.u1, p.v1),
      Pt(p.u0, p.v1),
    ].map(versForme).toList();
    c.ajouter(
      extrusionHorizontale(
        id: c.id,
        groupe: groupe,
        calque: Calque.sousPlancher,
        matiere: Matiere.sousPlancher,
        boucles: [contour.map(versForme).toList()],
        z0: zHaut,
        z1: 0,
        coque: coque,
      ),
    );
    final entiere =
        (p.longueur - pn.format.longueur).abs() < 0.01 &&
        (p.largeur - pn.format.largeur).abs() < 0.01;
    final irreguliere =
        (aireSignee(contour).abs() - p.longueur * p.largeur).abs() > 0.5;
    c.info(groupe, 'Feuille de sous-plancher n° ${p.feuille + 1}', [
      'Format : ${pn.format.nom}',
      'Pièce : ${c.l(p.longueur)} (en travers des solives) × ${c.l(p.largeur)}',
      entiere
          ? 'Feuille entière, sans coupe'
          : 'À couper dans la feuille n° ${p.feuille + 1}',
      if (irreguliere)
        'Pièce de forme irrégulière : à tracer selon le contour du plancher',
      'Rangée ${p.rangee + 1}',
      'Position : à ${c.l(p.u0 - b.xMin)} de la rive de départ, à ${c.l(p.v0 - b.yMin)} du bord',
      'Joints sur le centre des solives',
    ]);
  }

  // --- Cotes -----------------------------------------------------------------
  final contour = spec.forme;
  for (var i = 0; i < contour.nombre; i++) {
    final v = contour.sommet(i), w = contour.sommet(i + 1);
    final dir = (w - v).unitaire;
    final dehors = Pt(dir.y, -dir.x) * 10;
    c.cotes.add(
      Cote(
        P3(v.x + dehors.x, v.y + dehors.y, 0),
        P3(w.x + dehors.x, w.y + dehors.y, 0),
        c.l(contour.longueurCote(i)),
        Calque.solives,
      ),
    );
  }
}

// =============================================================================
// Murs
// =============================================================================

void _ajouterMurs(_Constructeur c, ResultatMurs r, Polygone? contour) {
  final p = r.parametres;
  final ts = p.panneau.epaisseur ?? _epPanneauMurDefaut;
  var curseur = 0.0;

  for (var w = 0; w < r.murs.length; w++) {
    final m = r.murs[w];
    final spec = m.spec;
    final d = p.section.profondeur;
    final longueur = spec.longueur;
    final h = spec.hauteur;

    // Placement : sur le contour, ou en rangée si le mur est isolé.
    Pt origine, u;
    final cote = spec.cote;
    if (contour != null && cote != null && cote < contour.nombre) {
      final v = contour.sommet(cote), s = contour.sommet(cote + 1);
      u = (s - v).unitaire;
      origine = v + u * spec.retraitDebut;
    } else {
      u = const Pt(1, 0);
      origine = Pt(curseur, 0);
      curseur += longueur + 48;
    }

    double? cot(double? angle, bool couches) {
      if (angle == null) {
        return null;
      }
      final droit = (angle - 90).abs() < 0.5;
      final rentrant = (angle - 270).abs() < 0.5;
      if (droit || (rentrant && !couches)) {
        return null;
      }
      return _cotDemi(angle);
    }

    RepereMur repere(bool couches) => RepereMur(
      origine: origine,
      u: u,
      d: d,
      xSommetDebut: -spec.retraitDebut,
      cotDebut: cot(spec.angleDebut, couches),
      xSommetFin: longueur + spec.retraitFin,
      cotFin: cot(spec.angleFin, couches),
    );
    final repOssature = repere(false);
    final repCouches = repere(true);

    final xDebut = -spec.retraitDebut;
    final xFin = longueur + spec.retraitFin;
    final zBas = -p.debordPlancher;
    final baies = <Rect4>[
      for (final o in spec.ouvertures)
        (o.baieG, o.baieD, o.baieBas, o.baieHaut),
    ];

    // --- Ossature ------------------------------------------------------------
    for (var i = 0; i < m.membres.length; i++) {
      final b = m.membres[i];
      final groupe = 'w${w}m$i';
      c.ajouter(
        plaqueMurOuNull(
          id: c.id,
          groupe: groupe,
          calque: Calque.ossature,
          matiere: b.type == TypeMembre.linteau
              ? Matiere.linteau
              : Matiere.bois,
          repere: repOssature,
          boucles: [
            [Pt(b.x0, b.z0), Pt(b.x1, b.z0), Pt(b.x1, b.z1), Pt(b.x0, b.z1)],
          ],
          y0: b.y0,
          y1: b.y1,
        ),
      );
      final precoupe =
          p.precoupes &&
          (b.type == TypeMembre.montant ||
              b.type == TypeMembre.montantCoin ||
              b.type == TypeMembre.roi) &&
          montantsPrecoupes.any(
            (x) => (x - b.longueurCoupe).abs() < 1 / 16 + 1e-9,
          );
      c.info(groupe, libelleMembre(b.type), [
        'Section : ${b.type == TypeMembre.linteau ? p.linteau.nom : b.section}',
        'Longueur à couper : ${c.l(b.longueurCoupe)}${precoupe ? ' (montant précoupé)' : ''}',
        'Position : de ${c.l(b.x0)} à ${c.l(b.x1)} du début du mur',
        if (b.type != TypeMembre.lisseBasse &&
            b.type != TypeMembre.lisseHaute &&
            b.type != TypeMembre.appui &&
            b.type != TypeMembre.linteau)
          'Hauteur : de ${c.l(b.z0)} à ${c.l(b.z1)}',
        'Mur : ${spec.nom}',
      ]);
    }

    // --- Feuilles ------------------------------------------------------------
    for (var k = 0; k < m.panneaux.length; k++) {
      final pa = m.panneaux[k];
      final groupe = 'w${w}p$k';
      c.ajouter(
        plaqueMurOuNull(
          id: c.id,
          groupe: groupe,
          calque: Calque.panneaux,
          matiere: p.panneau.estIsolant ? Matiere.isolant : Matiere.osb,
          repere: repCouches,
          boucles: contourRectangleMoinsTrous(
            pa.x0,
            pa.x1,
            pa.z0,
            pa.z1,
            pa.decoupes,
          ),
          y0: d,
          y1: d + ts,
        ),
      );
      c.info(groupe, 'Feuille murale n° ${pa.feuille + 1}', [
        'Format : ${p.panneau.nom}',
        'Pièce : ${c.l(pa.largeur)} de large × ${c.l(pa.hauteur)} de haut',
        (pa.largeur - p.panneau.largeur).abs() < 0.01 &&
                (pa.hauteur - p.panneau.longueur).abs() < 0.01
            ? 'Feuille entière'
            : 'À couper dans la feuille n° ${pa.feuille + 1}',
        'Position : à ${c.l(pa.x0 - xDebut)} du coin de départ, du bas à ${c.l(pa.z0 - zBas)}',
        for (final (x0, x1, z0, z1) in pa.decoupes)
          'Découpe d\'ouverture : ${c.l(x1 - x0)} × ${c.l(z1 - z0)}, à ${c.l(x0 - pa.x0)} du bord gauche, à ${c.l(z0 - pa.z0)} du bas',
        'Joints sur le centre des montants',
        'Mur : ${spec.nom}',
      ]);
    }

    // --- Membrane ------------------------------------------------------------
    final yMembrane = d + ts;
    c.ajouter(
      plaqueMurOuNull(
        id: c.id,
        groupe: 'w${w}mem',
        calque: Calque.membrane,
        matiere: Matiere.membrane,
        repere: repCouches,
        boucles: contourRectangleMoinsTrous(xDebut, xFin, zBas, h, baies),
        y0: yMembrane,
        y1: yMembrane + _epMembrane,
      ),
    );
    c.info('w${w}mem', 'Membrane (pare-air / pare-vapeur)', [
      'Mur : ${spec.nom}',
      'Aire nette : ${(m.aireNettePo2 / 144).toStringAsFixed(1).replaceFirst('.', ',')} pi²',
      'Chevauchement à prévoir aux joints, selon les directives du fabricant',
    ]);

    // --- Fourrures -----------------------------------------------------------
    final yFourrure = yMembrane + _epMembrane;
    for (var k = 0; k < m.fourrures.length; k++) {
      final fo = m.fourrures[k];
      final groupe = 'w${w}f$k';
      c.ajouter(
        plaqueMurOuNull(
          id: c.id,
          groupe: groupe,
          calque: Calque.fourrures,
          matiere: Matiere.fourrure,
          repere: repCouches,
          boucles: [
            [
              Pt(fo.x0, fo.z0),
              Pt(fo.x1, fo.z0),
              Pt(fo.x1, fo.z1),
              Pt(fo.x0, fo.z1),
            ],
          ],
          y0: yFourrure,
          y1: yFourrure + p.fourrureEpaisseur,
        ),
      );
      c.info(
        groupe,
        fo.verticale ? 'Fourrure verticale' : 'Fourrure horizontale',
        [
          'Section : ${c.l(p.fourrureEpaisseur)} × ${c.l(p.fourrureLargeur)}',
          'Longueur : ${c.l(fo.longueur)}',
          'Mur : ${spec.nom}',
        ],
      );
    }

    // --- Revêtement ----------------------------------------------------------
    final yRevetement = yFourrure + p.fourrureEpaisseur;
    c.ajouter(
      plaqueMurOuNull(
        id: c.id,
        groupe: 'w${w}rev',
        calque: Calque.revetement,
        matiere: Matiere.revetement,
        repere: repCouches,
        boucles: contourRectangleMoinsTrous(xDebut, xFin, zBas, h, baies),
        y0: yRevetement,
        y1: yRevetement + p.revetementEpaisseur,
      ),
    );
    c.info('w${w}rev', 'Revêtement extérieur', [
      'Mur : ${spec.nom}',
      'Aire nette : ${(m.aireNettePo2 / 144).toStringAsFixed(1).replaceFirst('.', ',')} pi²',
      'Épaisseur : ${c.l(p.revetementEpaisseur)}',
    ]);

    // --- Cotes ---------------------------------------------------------------
    P3 sur(double x, double z) => repOssature.point(x, d, z);
    c.cotes.add(
      Cote(sur(0, h + 6), sur(longueur, h + 6), c.l(longueur), Calque.ossature),
    );
    c.cotes.add(Cote(sur(0, 0), sur(0, h), c.l(h), Calque.ossature));
    for (final o in spec.ouvertures) {
      final nom = o.libelle;
      c.cotes.add(
        Cote(
          sur(o.baieG, o.baieBas - 4),
          sur(o.baieD, o.baieBas - 4),
          '$nom : baie ${c.l(o.largeurBaie)} × ${c.l(o.hauteurBaie)}',
          Calque.ossature,
        ),
      );
    }
  }
}

// =============================================================================
// Scène complète
// =============================================================================

/// [contour] : contour sur lequel poser les murs d'un bâtiment (par défaut,
/// celui du plancher) ; sans contour, les murs sont alignés côte à côte.
Scene construireScene({
  ResultatPlancher? plancher,
  SectionBois sectionPlancher = section2x10,
  ResultatMurs? murs,
  Polygone? contour,
  bool metrique = false,
}) {
  final c = _Constructeur(metrique);
  if (plancher != null) {
    _ajouterPlancher(c, plancher, sectionPlancher);
  }
  if (murs != null) {
    _ajouterMurs(c, murs, contour ?? plancher?.spec.forme);
  }
  return c.fin();
}
