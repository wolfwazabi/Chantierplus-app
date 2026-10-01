import 'dart:math' as math;

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/panneaux.dart';
import 'package:construction_app/charpente/plancher.dart' show SpecInvalide;
import 'package:flutter_test/flutter_test.dart';

/// 8 pi + 1 1/8 po : 3 lisses (1 basse, 2 hautes) + un montant précoupé de
/// 92 5/8 po.
const double _h = 97.125;

const _fenetre = Ouverture(
  type: TypeOuverture.fenetre,
  largeurCadre: 36,
  hauteurCadre: 48,
  allege: 36,
  position: 96,
);

const _porte = Ouverture(
  type: TypeOuverture.porte,
  largeurCadre: 32,
  hauteurCadre: 80,
  position: 48,
);

ResultatMurs _calc(
  List<SpecMur> specs, {
  ParametresMurs params = const ParametresMurs(),
}) => calculerMurs(specs, params);

ResultatMur _mur(
  SpecMur spec, {
  ParametresMurs params = const ParametresMurs(),
}) => _calc([spec], params: params).murs.single;

List<Membre> _de(ResultatMur r, TypeMembre t) =>
    r.membres.where((m) => m.type == t).toList();

Matcher _proche(double v) => closeTo(v, 1e-6);

const _verticaux = {
  TypeMembre.montant,
  TypeMembre.montantCoin,
  TypeMembre.roi,
  TypeMembre.jack,
  TypeMembre.courtHaut,
  TypeMembre.courtBas,
};

void main() {
  group('mur sans ouverture', () {
    test('16 pi à 16 po c/c : 13 montants précoupés et 3 lisses', () {
      final r = _mur(const SpecMur(longueur: 192, hauteur: _h));
      final m = _de(r, TypeMembre.montant);
      expect(m, hasLength(13));
      for (final x in m) {
        expect(x.longueurCoupe, _proche(92.625));
        expect(x.z0, _proche(1.5));
        expect(x.z1, _proche(94.125));
      }
      // Premier et dernier montants collés aux bouts, les autres centrés sur 16 po.
      final xs = m.map((e) => (e.x0 + e.x1) / 2).toList()..sort();
      expect(xs.first, _proche(0.75));
      expect(xs.last, _proche(191.25));
      for (var i = 1; i < 12; i++) {
        expect(xs[i], _proche(16.0 * i));
      }
      expect(_de(r, TypeMembre.lisseBasse), hasLength(1));
      expect(_de(r, TypeMembre.lisseHaute), hasLength(2));
      expect(r.compter(TypeMembre.roi), 0);
    });

    test('nombre de montants = longueur / entraxe + 1 (mur courant)', () {
      for (final (l, s, n) in [
        (96.0, 16.0, 7),
        (96.0, 24.0, 5),
        (96.0, 12.0, 9),
        (100.0, 16.0, 8),
        (240.0, 19.2, 14),
      ]) {
        final r = _mur(
          SpecMur(longueur: l, hauteur: _h),
          params: ParametresMurs(espacement: s),
        );
        expect(r.compter(TypeMembre.montant), n, reason: '$l po à $s c/c');
      }
    });

    test('lisses et montants précoupés dans la commande', () {
      final r = _calc([const SpecMur(longueur: 192, hauteur: _h)]);
      expect(r.precoupes, {92.625: 13});
      expect(r.boisOssature.parLongueur, {192.0: 3});
      expect(r.boisOssature.pertePourcent, closeTo(0, 1e-9));
      expect(r.boisLinteaux.planches, isEmpty);
    });

    test('sans précoupés : les montants sont coupés dans des planches', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h),
      ], params: const ParametresMurs(precoupes: false));
      expect(r.precoupes, isEmpty);
      expect(r.boisOssature.parLongueur, {96.0: 13, 192.0: 3});
    });

    test('une seule lisse haute : montant de 94 1/8 po, pas précoupé', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h),
      ], params: const ParametresMurs(lissesHautes: 1));
      expect(r.murs.single.compter(TypeMembre.lisseHaute), 1);
      expect(
        _de(r.murs.single, TypeMembre.montant).first.longueurCoupe,
        _proche(94.125),
      );
      expect(r.precoupes, isEmpty);
      expect(r.boisOssature.parLongueur, {96.0: 13, 192.0: 2});
    });

    test('mur de 9 pi : montant précoupé de 104 5/8 po', () {
      final r = _calc([const SpecMur(longueur: 192, hauteur: 109.125)]);
      expect(r.precoupes, {104.625: 13});
    });

    test('lisse plus longue que la plus longue planche : épissée', () {
      final r = _calc([const SpecMur(longueur: 360, hauteur: _h)]);
      expect(r.avertissements.any((a) => a.contains('épissée')), isTrue);
      // 3 lisses de 30 pi chacune en 2 morceaux de 15 pi : 6 planches de 16 pi
      // (la plus longue étant 20 pi : 240 po).
      final total = r.boisOssature.planches
          .where((p) => p.stock >= 168)
          .fold(0.0, (a, p) => a + p.utilise);
      expect(total, greaterThanOrEqualTo(3 * 360 - 1e-6));
    });

    test('aire, membrane, revêtement et fourrures', () {
      final r = _calc([const SpecMur(longueur: 192, hauteur: _h)]);
      expect(r.murs.single.aireNettePo2 / 144, closeTo(129.5, 1e-9));
      expect(r.aireMembranePi2, closeTo(129.5 * 1.1, 1e-9));
      expect(r.aireRevetementPi2, closeTo(129.5 * 1.1, 1e-9));
      expect(r.rouleauxMembrane, 1);
      // 13 fourrures de 97 1/8 po : un seul morceau par planche de 10 pi.
      expect(r.fourrures.parLongueur, {120.0: 13});
    });

    test('plusieurs murs : le nombre de rouleaux suit l\'aire totale', () {
      // 40 murs de 40 pi : l'aire totale + 10 % se divise en rouleaux de 900 pi².
      final specs = [
        for (var i = 0; i < 40; i++) const SpecMur(longueur: 480, hauteur: _h),
      ];
      final r = _calc(specs);
      final aire = 40 * 480 * _h / 144;
      expect(r.aireMembranePi2, closeTo(aire * 1.1, 1e-6));
      expect(r.rouleauxMembrane, (aire * 1.1 / 900).ceil());
    });
  });

  group('feuilles (OSB / Isobrace)', () {
    test(
      '16 pi avec des feuilles de 4 × 9 : 4 feuilles, joints sur les montants',
      () {
        final r = _calc([const SpecMur(longueur: 192, hauteur: _h)]);
        final p = r.murs.single.panneaux;
        expect(p, hasLength(4));
        expect(r.feuillesUtilisees, 4);
        expect(r.feuillesACommander, 4);
        expect(p.map((e) => (e.x0, e.x1)).toList(), [
          (0.0, 48.0),
          (48.0, 96.0),
          (96.0, 144.0),
          (144.0, 192.0),
        ]);
        for (final e in p) {
          expect(e.z0, _proche(0));
          expect(e.z1, _proche(_h));
          expect(e.decoupes, isEmpty);
        }
      },
    );

    test('marge d\'achat sur les feuilles', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h),
      ], params: const ParametresMurs(margeFeuillesPct: 10));
      expect(r.feuillesUtilisees, 4);
      expect(r.feuillesACommander, 5); // 4 × 1,1 = 4,4 → 5
    });

    test('feuilles de 4 × 8 : le mur de 97 1/8 po est en deux rangées + entremises', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h),
      ], params: const ParametresMurs(panneau: panneau4x8));
      final p = r.murs.single.panneaux;
      expect(p, hasLength(8));
      final joints = p.map((e) => e.z0).where((z) => z > 0).toSet();
      expect(
        joints.single,
        _proche(91.125),
      ); // plus de 6 po pour la rangée du haut
      expect(
        r.avertissements.any((a) => a.contains('joint horizontal')),
        isTrue,
      );
      // Entremise entre chaque paire de montants consécutifs : 12 intervalles.
      expect(r.murs.single.compter(TypeMembre.entremise), 12);
      // 4 grandes pièces (une feuille chacune) + 4 bandes de 6 po sur une 5e.
      expect(r.feuillesUtilisees, 5);
    });

    test('Isobrace R-4 : même format 4 × 9', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h),
      ], params: const ParametresMurs(panneau: panneauIsobraceR4));
      expect(r.feuillesUtilisees, 4);
    });

    test('dernière colonne : jamais moins de 12 po', () {
      // 192,5 po : 4 × 48 laisserait 0,5 po.
      final r = _mur(const SpecMur(longueur: 192.5, hauteur: _h));
      final largeurs = r.panneaux.map((e) => e.largeur).toList();
      expect(
        largeurs.every((l) => l >= 12 - 1e-6),
        isTrue,
        reason: '$largeurs',
      );
      expect(largeurs.fold(0.0, (a, b) => a + b), _proche(192.5));
    });
  });

  group('fenêtre', () {
    test('baie, rois, jacks, linteau, appui et courts montants', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      );
      // Baie : 36 + 1 po de large ; 48 + 1 1/2 po de haut, bas à 36 − 3/4 po.
      expect(_fenetre.largeurBaie, _proche(37));
      expect(_fenetre.hauteurBaie, _proche(49.5));
      expect(_fenetre.baieBas, _proche(35.25));
      expect(_fenetre.baieHaut, _proche(84.75));

      final rois = _de(r, TypeMembre.roi);
      expect(rois, hasLength(2));
      expect(rois.map((e) => e.x0).toList()..sort(), [
        closeTo(74.5, 1e-6),
        closeTo(116, 1e-6),
      ]);
      for (final k in rois) {
        expect(k.longueurCoupe, _proche(92.625));
      }

      final jacks = _de(r, TypeMembre.jack);
      expect(jacks, hasLength(2));
      for (final j in jacks) {
        expect(j.longueurCoupe, _proche(83.25)); // 84,75 − 1,5
        expect(j.z1, _proche(84.75));
      }

      // Linteau 2×8, 2 plis, baie 37 + 2 jacks de 1 1/2 po = 40 po.
      final linteaux = _de(r, TypeMembre.linteau);
      expect(linteaux, hasLength(2));
      for (final l in linteaux) {
        expect(l.longueurCoupe, _proche(40));
        expect(l.z0, _proche(84.75));
        expect(l.z1, _proche(92));
      }
      expect(linteaux[0].y0, _proche(0));
      expect(linteaux[1].y1, _proche(3.5));

      // Appui : sous la baie, 37 po.
      final appui = _de(r, TypeMembre.appui);
      expect(appui, hasLength(1));
      expect(appui.single.longueurCoupe, _proche(37));
      expect(appui.single.z0, _proche(33.75));
      expect(appui.single.z1, _proche(35.25));

      // Courts montants : 3 au-dessus (2 1/8 po), 3 sous l'appui (32 1/4 po),
      // sur les montants à 80, 96 et 112 po.
      final hauts = _de(r, TypeMembre.courtHaut);
      final bas = _de(r, TypeMembre.courtBas);
      expect(hauts, hasLength(3));
      expect(bas, hasLength(3));
      for (final c in hauts) {
        expect(c.longueurCoupe, _proche(2.125));
      }
      for (final c in bas) {
        expect(c.longueurCoupe, _proche(32.25));
      }
      expect(hauts.map((e) => (e.x0 + e.x1) / 2).toList()..sort(), [
        closeTo(80, 1e-6),
        closeTo(96, 1e-6),
        closeTo(112, 1e-6),
      ]);

      // Montants courants : 13 − 3 (dans la baie) = 10.
      expect(_de(r, TypeMembre.montant), hasLength(10));
      // La lisse basse n'est pas coupée sous une fenêtre.
      expect(_de(r, TypeMembre.lisseBasse), hasLength(1));
    });

    test('aire nette : on retire la baie', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      );
      expect(r.aireBrutePo2, _proche(192 * _h));
      expect(r.aireNettePo2, _proche(192 * _h - 37 * 49.5));
    });

    test('commande : linteaux, montants de rive et de linteau', () {
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      ]);
      expect(r.boisLinteaux.parLongueur, {96.0: 1}); // 2 × 40 po dans une 8 pi
      // 10 montants + 2 rois précoupés ; les jacks et courts montants sont dans le bois.
      expect(r.precoupes, {92.625: 12});
      expect(r.feuillesUtilisees, 4);
      // La baie est découpée dans les feuilles 2 et 3.
      final p = r.murs.single.panneaux;
      expect(p, hasLength(4));
      final (a0, a1, a2, a3) = p[1].decoupes.single;
      expect(
        [a0, a1, a2, a3],
        [
          closeTo(77.5, 1e-6),
          closeTo(96, 1e-6),
          closeTo(35.25, 1e-6),
          closeTo(84.75, 1e-6),
        ],
      );
      final (b0, b1, b2, b3) = p[2].decoupes.single;
      expect(
        [b0, b1, b2, b3],
        [
          closeTo(96, 1e-6),
          closeTo(114.5, 1e-6),
          closeTo(35.25, 1e-6),
          closeTo(84.75, 1e-6),
        ],
      );
    });

    test('jeux hors de la plage GCR : avertissement', () {
      final r = _calc([
        const SpecMur(
          longueur: 192,
          hauteur: _h,
          ouvertures: [
            Ouverture(
              type: TypeOuverture.fenetre,
              nom: 'Salon',
              largeurCadre: 36,
              hauteurCadre: 48,
              position: 96,
              jeuLargeur: 2.5,
              jeuHauteur: 0.5,
            ),
          ],
        ),
      ]);
      final g = r.avertissements.where((a) => a.startsWith('Salon')).toList();
      expect(g, hasLength(2));
      expect(g.any((a) => a.contains('largeur')), isTrue);
      expect(g.any((a) => a.contains('hauteur')), isTrue);
    });

    test('jeux de la plage GCR : aucun avertissement de jeu', () {
      for (final (jl, jh) in [(0.52, 1.0), (1.5, 1.75), (1.0, 1.5)]) {
        final r = _calc([
          SpecMur(
            longueur: 192,
            hauteur: _h,
            ouvertures: [
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 96,
                jeuLargeur: jl,
                jeuHauteur: jh,
              ),
            ],
          ),
        ]);
        expect(
          r.avertissements.any((a) => a.contains('GCR')),
          isFalse,
          reason: '$jl / $jh',
        );
      }
    });

    test('2 jacks par côté et linteau à 3 plis (mur 2×6)', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
        params: const ParametresMurs(
          section: section2x6,
          jacksParCote: 2,
          plisLinteau: 3,
        ),
      );
      expect(_de(r, TypeMembre.jack), hasLength(4));
      final l = _de(r, TypeMembre.linteau);
      expect(l, hasLength(3));
      expect(l.first.longueurCoupe, _proche(37 + 6)); // baie + 4 jacks
      // Les plis tiennent dans l'épaisseur du mur (5 1/2 po) sans se superposer.
      for (var i = 0; i < 3; i++) {
        expect(l[i].y1 - l[i].y0, _proche(1.5));
        expect(l[i].y1, lessThanOrEqualTo(5.5 + 1e-9));
        if (i > 0) {
          expect(l[i].y0, greaterThanOrEqualTo(l[i - 1].y1 - 1e-9));
        }
      }
    });

    test('3 plis ne tiennent pas dans un mur 2×4 : refusé', () {
      expect(
        () => _mur(
          const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
          params: const ParametresMurs(plisLinteau: 3),
        ),
        throwsA(isA<SpecInvalide>()),
      );
    });
  });

  group('porte', () {
    test('lisse basse coupée dans la baie, courts montants au-dessus', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_porte]),
      );
      // Baie : 33 × 81 1/2 po, de 31 1/2 à 64 1/2 po.
      expect(_porte.baieG, _proche(31.5));
      expect(_porte.baieD, _proche(64.5));
      expect(_porte.baieHaut, _proche(81.5));
      final basses = _de(r, TypeMembre.lisseBasse);
      expect(basses, hasLength(2));
      expect(basses.map((e) => e.longueurCoupe).toList()..sort(), [
        closeTo(31.5, 1e-6),
        closeTo(127.5, 1e-6),
      ]);
      // Linteau : dessus à 81,5 + 7,25 = 88,75 po ; 5 3/8 po sous la lisse haute.
      final hauts = _de(r, TypeMembre.courtHaut);
      expect(hauts, hasLength(1)); // montant à 48 po
      expect(hauts.single.longueurCoupe, _proche(5.375));
      expect(_de(r, TypeMembre.appui), isEmpty);
      expect(_de(r, TypeMembre.courtBas), isEmpty);
      // Les montants à 32 et 64 po chevauchent les jacks : retirés.
      expect(_de(r, TypeMembre.montant), hasLength(13 - 3));
    });

    test('grande porte de garage : feuilles pleines dessus / pièces au-dessus', () {
      const garage = Ouverture(
        type: TypeOuverture.porte,
        nom: 'Garage',
        largeurCadre: 96,
        hauteurCadre: 84,
        position: 96,
      );
      final r = _calc([
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [garage]),
      ]);
      final p = r.murs.single.panneaux;
      // 2 colonnes pleines au centre (une pièce de 11 5/8 po au-dessus de la
      // baie chacune), 2 colonnes d'extrémité découpées.
      expect(p, hasLength(4));
      final dessus = p.where((e) => e.hauteur < 20).toList();
      expect(dessus, hasLength(2));
      for (final e in dessus) {
        expect(e.hauteur, _proche(_h - 85.5));
        expect(e.largeur, _proche(48));
      }
      // 2 feuilles pour les colonnes d'extrémité + 1 pour les 2 pièces du haut.
      expect(r.feuillesUtilisees, 3);
    });
  });

  group('intersections en T', () {
    test('2 montants d\'appui, montant courant chevauché retiré', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, intersections: [46]),
      );
      final coins = _de(r, TypeMembre.montantCoin);
      expect(coins, hasLength(2));
      expect(coins.map((e) => (e.x0 + e.x1) / 2).toList()..sort(), [
        closeTo(43.5, 1e-6),
        closeTo(48.5, 1e-6),
      ]);
      // Le montant à 48 po chevauche le montant d'appui à 48,5 : retiré.
      expect(_de(r, TypeMembre.montant), hasLength(12));
    });

    test('montant courant dans l\'empreinte de la cloison : conservé', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, intersections: [96]),
      );
      expect(_de(r, TypeMembre.montantCoin), hasLength(2));
      expect(_de(r, TypeMembre.montant), hasLength(13));
    });

    test('trop près d\'un coin ou d\'une ouverture : refusé', () {
      expect(
        () => _calc([
          const SpecMur(
            longueur: 192,
            hauteur: _h,
            montantsCoinDebut: 1,
            intersections: [6],
          ),
        ]),
        throwsA(isA<SpecInvalide>()),
      );
      expect(
        () => _calc([
          const SpecMur(
            longueur: 192,
            hauteur: _h,
            ouvertures: [_fenetre],
            intersections: [74],
          ),
        ]),
        throwsA(isA<SpecInvalide>()),
      );
      expect(
        () => _calc([
          const SpecMur(longueur: 192, hauteur: _h, intersections: [50, 51]),
        ]),
        throwsA(isA<SpecInvalide>()),
      );
    });
  });

  group('validation', () {
    SpecInvalide? echec(
      List<SpecMur> s, [
      ParametresMurs p = const ParametresMurs(),
    ]) {
      try {
        calculerMurs(s, p);
      } on SpecInvalide catch (e) {
        return e;
      }
      return null;
    }

    test('ouvertures trop proches du bout ou entre elles', () {
      expect(
        echec([
          const SpecMur(
            longueur: 192,
            hauteur: _h,
            ouvertures: [
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 20,
              ),
            ],
          ),
        ])?.message,
        contains('trop près du début'),
      );
      expect(
        echec([
          const SpecMur(
            longueur: 192,
            hauteur: _h,
            ouvertures: [
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 175,
              ),
            ],
          ),
        ])?.message,
        contains('trop près de la fin'),
      );
      expect(
        echec([
          const SpecMur(
            longueur: 192,
            hauteur: _h,
            ouvertures: [
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 60,
              ),
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 100,
              ),
            ],
          ),
        ])?.message,
        contains('chevauche'),
      );
    });

    test(
      'linteau trop haut, allège sous le plancher, dimensions invalides',
      () {
        expect(
          echec([
            const SpecMur(
              longueur: 192,
              hauteur: _h,
              ouvertures: [
                Ouverture(
                  type: TypeOuverture.fenetre,
                  largeurCadre: 36,
                  hauteurCadre: 48,
                  allege: 40,
                  position: 96,
                ),
              ],
            ),
          ], const ParametresMurs(linteau: section2x12))?.message,
          contains('linteau'),
        );
        expect(
          echec([
            const SpecMur(
              longueur: 192,
              hauteur: _h,
              ouvertures: [
                Ouverture(
                  type: TypeOuverture.fenetre,
                  largeurCadre: 36,
                  hauteurCadre: 48,
                  allege: 0.2,
                  position: 96,
                ),
              ],
            ),
          ]),
          isNotNull,
        );
        expect(
          echec([
            const SpecMur(
              longueur: 192,
              hauteur: _h,
              ouvertures: [
                Ouverture(
                  type: TypeOuverture.porte,
                  largeurCadre: 0,
                  hauteurCadre: 80,
                  position: 96,
                ),
              ],
            ),
          ]),
          isNotNull,
        );
      },
    );

    test('mur : longueur, hauteur, aucun mur', () {
      expect(echec([const SpecMur(longueur: 3, hauteur: _h)]), isNotNull);
      expect(echec([const SpecMur(longueur: 192, hauteur: 12)]), isNotNull);
      expect(echec([const SpecMur(longueur: 192, hauteur: 300)]), isNotNull);
      expect(echec(const []), isNotNull);
      expect(
        echec([
          for (var i = 0; i < 41; i++) const SpecMur(longueur: 96, hauteur: _h),
        ]),
        isNotNull,
      );
    });

    test('paramètres hors limites', () {
      const un = [SpecMur(longueur: 192, hauteur: _h)];
      for (final p in [
        const ParametresMurs(espacement: 3),
        const ParametresMurs(espacement: 60),
        const ParametresMurs(lissesHautes: 3),
        const ParametresMurs(jacksParCote: 0),
        const ParametresMurs(plisLinteau: 5),
        const ParametresMurs(plisAppui: 3),
        const ParametresMurs(longueursPlanches: []),
        const ParametresMurs(debordPlancher: 30),
        const ParametresMurs(fourrureEntraxe: 2),
        const ParametresMurs(margeMembranePct: 80),
        const ParametresMurs(aireRouleauPi2: 0),
      ]) {
        expect(echec(un, p), isNotNull);
      }
    });

    test('avertissement permanent : linteaux non dimensionnés', () {
      final r = _calc([const SpecMur(longueur: 192, hauteur: _h)]);
      expect(r.avertissements.any((a) => a.contains('linteaux')), isTrue);
    });
  });

  group('fourrures', () {
    test('mur plein : 13 verticales de la hauteur du mur', () {
      final r = _mur(const SpecMur(longueur: 192, hauteur: _h));
      expect(r.fourrures, hasLength(13));
      for (final f in r.fourrures) {
        expect(f.verticale, isTrue);
        expect(f.longueur, _proche(_h));
        expect(f.x1 - f.x0, _proche(2.5));
      }
      final xs = r.fourrures.map((f) => (f.x0 + f.x1) / 2).toList()..sort();
      expect(xs.first, _proche(1.25));
      expect(xs.last, _proche(190.75));
      expect(xs[1], _proche(16));
    });

    test('fenêtre : cadre de fourrures, les verticales s\'arrêtent contre lui', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
      );
      final h = r.fourrures.where((f) => !f.verticale).toList();
      expect(h, hasLength(2)); // dessus et dessous
      for (final f in h) {
        expect(f.longueur, _proche(37 + 5)); // baie + 2 × 2 1/2 po
      }
      // Côtés du cadre : de la baie, 49 1/2 po.
      final cotes = r.fourrures
          .where((f) => f.verticale && (f.longueur - 49.5).abs() < 1e-6)
          .toList();
      expect(cotes, hasLength(2));
      // Les 3 verticales courantes à 80, 96 et 112 po sont coupées en deux :
      // 32 3/4 po sous le cadre et 9 7/8 po au-dessus.
      final bas = r.fourrures.where(
        (f) => f.verticale && (f.longueur - 32.75).abs() < 1e-6,
      );
      final haut = r.fourrures.where(
        (f) => f.verticale && (f.longueur - 9.875).abs() < 1e-6,
      );
      expect(bas, hasLength(3));
      expect(haut, hasLength(3));
      expect(r.fourrures, hasLength(10 + 3 + 3 + 2 + 2));
      // Rien ne se superpose : deux fourrures n'occupent jamais la même place.
      for (var i = 0; i < r.fourrures.length; i++) {
        for (var j = i + 1; j < r.fourrures.length; j++) {
          final a = r.fourrures[i], b = r.fourrures[j];
          final x = math.min(a.x1, b.x1) - math.max(a.x0, b.x0);
          final z = math.min(a.z1, b.z1) - math.max(a.z0, b.z0);
          expect(x > 1e-6 && z > 1e-6, isFalse, reason: '$i / $j');
        }
      }
    });

    test('porte : pas de fourrure sous la baie ni de traverse du bas', () {
      final r = _mur(
        const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_porte]),
      );
      expect(r.fourrures.where((f) => !f.verticale), hasLength(1));
      for (final f in r.fourrures.where((f) => f.verticale)) {
        final dansLaBaie = f.x0 > _porte.baieG && f.x1 < _porte.baieD;
        expect(dansLaBaie && f.z0 < _porte.baieHaut, isFalse);
      }
    });

    test(
      'commande de fourrures : les petits morceaux partagent les planches',
      () {
        final r = _calc([
          const SpecMur(longueur: 192, hauteur: _h, ouvertures: [_fenetre]),
        ]);
        final total = r.fourrures.planches.fold(0.0, (a, p) => a + p.utilise);
        final pieces = r.murs.single.fourrures.fold(
          0.0,
          (a, f) => a + f.longueur,
        );
        expect(total, _proche(pieces));
      },
    );
  });

  group('murs d\'un contour', () {
    test('couches extérieures : de sommet à sommet', () {
      final m = mursDuContour(Polygone.rectangle(288, 240), hauteur: _h);
      final r = _calc(m);
      final abutte = r.murs[0]; // 281 po d'ossature, retraits de 3 1/2 po
      expect(abutte.spec.retraitDebut, 3.5);
      expect(abutte.spec.retraitFin, 3.5);
      final x0 = abutte.panneaux.map((e) => e.x0).reduce(math.min);
      final x1 = abutte.panneaux.map((e) => e.x1).reduce(math.max);
      expect(x0, _proche(-3.5));
      expect(x1, _proche(284.5));
      expect(abutte.aireBrutePo2, _proche(288 * _h));
      // Le mur qui passe : de 0 à sa longueur.
      final passe = r.murs[1];
      expect(passe.spec.retraitDebut, 0);
      expect(passe.panneaux.map((e) => e.x0).reduce(math.min), _proche(0));
      // Aire totale = périmètre × hauteur.
      final aire = r.murs.fold(0.0, (a, e) => a + e.aireBrutePo2);
      expect(aire, _proche(2 * (288 + 240) * _h));
    });

    test('onglet : les montants de bout reculent contre la coupe d\'angle', () {
      final t = mursDuContour(
        Polygone(const [Pt(0, 0), Pt(144, 0), Pt(48, 96)]),
        hauteur: _h,
      );
      final r = _mur(t[0]);
      final montants = _de(r, TypeMembre.montant)
        ..sort((a, b) => a.x0.compareTo(b.x0));
      // 63,43° au début : 3,5 × cot(31,72°) = 5,663 po ; 45° à la fin : 8,450 po.
      expect(montants.first.x0, closeTo(5.6631, 1e-3));
      expect(montants.last.x1, closeTo(144 - 8.4497, 1e-3));
      // Les lisses vont d'un sommet à l'autre (pointe longue).
      for (final l in _de(r, TypeMembre.lisseHaute)) {
        expect(l.longueurCoupe, _proche(144));
      }
    });

    test('côtés, retraits et angles transmis aux murs', () {
      final m = mursDuContour(Polygone.rectangle(288, 240), hauteur: _h);
      expect(m.map((e) => e.cote).toList(), [0, 1, 2, 3]);
      expect(m.map((e) => (e.retraitDebut, e.retraitFin)).toList(), [
        (3.5, 3.5),
        (0.0, 0.0),
        (3.5, 3.5),
        (0.0, 0.0),
      ]);
      expect(m.every((e) => e.angleDebut == 90 && e.angleFin == 90), isTrue);
      final t = mursDuContour(
        Polygone(const [Pt(0, 0), Pt(144, 0), Pt(48, 96)]),
        hauteur: _h,
      );
      expect(t[0].angleDebut, closeTo(63.4349, 1e-3));
      expect(t[0].angleFin, closeTo(45, 1e-9));
      expect(t[2].angleFin, closeTo(63.4349, 1e-3));
    });

    test('rectangle 24 × 20 pi : deux murs passent, deux s\'appuient', () {
      final m = mursDuContour(Polygone.rectangle(288, 240), hauteur: _h);
      expect(m.map((e) => e.longueur).toList(), [281, 240, 281, 240]);
      expect(m.map((e) => (e.montantsCoinDebut, e.montantsCoinFin)).toList(), [
        (1, 1),
        (0, 0),
        (1, 1),
        (0, 0),
      ]);
      // Le périmètre en bois : les longueurs de lisse + 2 × 3 1/2 po par coin.
      final somme = m.fold(0.0, (a, e) => a + e.longueur);
      expect(somme, 1042); // 2 × 281 + 2 × 240
    });

    test('forme en L : coin rentrant prolongé', () {
      final l = Polygone(const [
        Pt(0, 0),
        Pt(240, 0),
        Pt(240, 120),
        Pt(120, 120),
        Pt(120, 240),
        Pt(0, 240),
      ]);
      final m = mursDuContour(l, hauteur: _h);
      expect(m.map((e) => e.longueur).toList(), [
        233,
        120,
        116.5,
        123.5,
        113,
        240,
      ]);
      expect(m.map((e) => (e.montantsCoinDebut, e.montantsCoinFin)).toList(), [
        (1, 1),
        (0, 0),
        (1, 1),
        (0, 0),
        (1, 1),
        (0, 0),
      ]);
    });

    test('triangle : les trois murs vont jusqu\'aux sommets', () {
      final t = Polygone(const [Pt(0, 0), Pt(144, 0), Pt(48, 96)]);
      final m = mursDuContour(t, hauteur: _h);
      expect(m.map((e) => e.longueur).toList(), [
        closeTo(144, 1e-9),
        closeTo(math.sqrt(96 * 96 + 96 * 96), 1e-9),
        closeTo(math.sqrt(48 * 48 + 96 * 96), 1e-9),
      ]);
      for (final e in m) {
        expect(e.montantsCoinDebut, 1);
        expect(e.montantsCoinFin, 1);
      }
    });

    test('un contour complet se calcule', () {
      final m = mursDuContour(Polygone.rectangle(288, 240), hauteur: _h);
      final r = _calc(m);
      expect(r.murs, hasLength(4));
      // Montants : 288 → 281 po : 1 + 17 (16..272) + fin ; chaque mur compte
      // aussi ses montants de coin (type coin, précoupés eux aussi).
      expect(r.precoupes.keys.single, 92.625);
      expect(
        r.feuillesUtilisees,
        greaterThanOrEqualTo(
          (r.murs.fold(0.0, (a, e) => a + e.aireNettePo2) / (108 * 48)).ceil(),
        ),
      );
    });
  });

  group('propriétés sur des murs au hasard', () {
    test(
      'joints sur des appuis, pas de montants superposés, tout dans le mur',
      () {
        final rnd = math.Random(11);
        var essais = 0, valides = 0;
        while (valides < 150 && essais < 3000) {
          essais++;
          final longueur = 72 + rnd.nextInt(360) + (rnd.nextBool() ? 0.5 : 0.0);
          final espacement = [12.0, 16.0, 19.2, 24.0][rnd.nextInt(4)];
          final ouvertures = <Ouverture>[];
          for (var i = rnd.nextInt(4); i > 0; i--) {
            final porte = rnd.nextInt(3) == 0;
            ouvertures.add(
              Ouverture(
                type: porte ? TypeOuverture.porte : TypeOuverture.fenetre,
                largeurCadre: 24 + rnd.nextInt(60).toDouble(),
                hauteurCadre: porte ? 78 : 24 + rnd.nextInt(30).toDouble(),
                allege: porte ? 0 : 30 + rnd.nextInt(12).toDouble(),
                position: 24 + rnd.nextDouble() * (longueur - 48),
              ),
            );
          }
          final intersections = [
            for (var i = rnd.nextInt(3); i > 0; i--)
              12 + rnd.nextDouble() * (longueur - 24),
          ];
          final spec = SpecMur(
            longueur: longueur,
            hauteur: [97.125, 109.125, 100.0][rnd.nextInt(3)],
            ouvertures: ouvertures,
            intersections: intersections,
            montantsCoinDebut: rnd.nextInt(3),
            montantsCoinFin: rnd.nextInt(3),
          );
          final params = ParametresMurs(
            espacement: espacement,
            panneau: [panneau4x8, panneau4x9, panneau4x10][rnd.nextInt(3)],
          );
          ResultatMur r;
          try {
            r = _mur(spec, params: params);
          } on SpecInvalide {
            continue; // ouvertures qui se touchent, etc. : refusé proprement
          }
          valides++;

          // Tout dans le mur.
          for (final m in r.membres) {
            expect(m.x0, greaterThanOrEqualTo(-1e-6));
            expect(m.x1, lessThanOrEqualTo(longueur + 1e-6));
            expect(m.z0, greaterThanOrEqualTo(-1e-6));
            expect(m.z1, lessThanOrEqualTo(spec.hauteur + 1e-6));
            expect(m.longueurCoupe, greaterThan(0));
          }

          // Aucune superposition entre pièces verticales.
          final v = r.membres
              .where((m) => _verticaux.contains(m.type))
              .toList();
          for (var i = 0; i < v.length; i++) {
            for (var j = i + 1; j < v.length; j++) {
              final x = math.min(v[i].x1, v[j].x1) - math.max(v[i].x0, v[j].x0);
              final z = math.min(v[i].z1, v[j].z1) - math.max(v[i].z0, v[j].z0);
              expect(
                x > 1e-6 && z > 1e-6,
                isFalse,
                reason:
                    'superposition ${v[i].type} / ${v[j].type} (essai $essais)',
              );
            }
          }

          // Feuilles : colonnes contiguës, ≤ largeur du panneau, joints sur appuis.
          final colonnes = <(double, double)>{
            for (final p in r.panneaux) (p.x0, p.x1),
          }.toList()..sort((a, b) => a.$1.compareTo(b.$1));
          expect(colonnes.first.$1, _proche(0));
          expect(colonnes.last.$2, _proche(longueur));
          for (var i = 0; i < colonnes.length; i++) {
            expect(
              colonnes[i].$2 - colonnes[i].$1,
              lessThanOrEqualTo(48 + 1e-6),
            );
            if (i > 0) {
              expect(colonnes[i].$1, _proche(colonnes[i - 1].$2));
            }
          }
          for (var i = 1; i < colonnes.length; i++) {
            final x = colonnes[i].$1;
            final surMembre = v.any(
              (m) => ((m.x0 + m.x1) / 2 - x).abs() < 1e-6,
            );
            final dansBaie = ouvertures.any((o) => x > o.baieG && x < o.baieD);
            expect(
              surMembre || dansBaie,
              isTrue,
              reason: 'joint à $x sans appui (essai $essais, ${spec.longueur})',
            );
          }
        }
        expect(valides, 150);
      },
    );
  });
}
