// Pose du linteau d'une porte ou d'une fenêtre (CNB, partie 9 : 9.23.11.3 et 9.23.12) : sous les
// lisses (courant), sous une lisse simple (+1 1/2 po), à la place des lisses (+3 po, plaques de
// liaison) ou sans linteau (poutre conçue par un ingénieur). Cas d'un solarium dont le vitrage
// monte jusqu'à la sablière.
import 'dart:convert';

import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/plancher.dart' show SpecInvalide;
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mur de 8 pi (96 po) et 12 pi de long, 2 lisses hautes, linteau 2×8 (7 1/4 po) : la lisse
/// haute est à 93 po, la lisse du dessus à 94 1/2 po.
const double _h = 96;
const double _longueur = 144;

/// Fenêtre de 36 po de large au centre, allège 14 po, jeu de 1 1/2 po : la baie monte de
/// 14 − 3/4 + cadre + 1 1/2 ; le dessus du linteau est 7 1/4 po plus haut.
Ouverture _fenetre(
  double cadre, {
  PoseLinteau pose = PoseLinteau.sousLesLisses,
}) => Ouverture(
  type: TypeOuverture.fenetre,
  nom: 'F1',
  largeurCadre: 36,
  hauteurCadre: cadre,
  allege: 14,
  position: 72,
  pose: pose,
);

/// Cadre de 72 1/2 po : dessus du linteau à 94 1/2 po (passe sous une lisse simple).
const double _cadreLisseSimple = 72.5;

/// Cadre de 74 po : dessus du linteau à 96 po (passe seulement à la place des lisses).
const double _cadreSabliere = 74;

SpecMur _mur(Ouverture o, {double h = _h}) =>
    SpecMur(nom: 'Mur 1', longueur: _longueur, hauteur: h, ouvertures: [o]);

ResultatMur _calcul(Ouverture o, {ParametresMurs p = const ParametresMurs()}) =>
    calculerMurs([_mur(o)], p).murs.single;

List<Membre> _de(ResultatMur r, TypeMembre t) =>
    r.membres.where((m) => m.type == t).toList();

/// Deux pièces de bois ne se chevauchent jamais (boîtes en x, y, z).
void _sansChevauchement(ResultatMur r) {
  final m = r.membres;
  for (var i = 0; i < m.length; i++) {
    for (var j = i + 1; j < m.length; j++) {
      final a = m[i], b = m[j];
      final chevauche =
          a.x0 < b.x1 - 1e-6 &&
          b.x0 < a.x1 - 1e-6 &&
          a.y0 < b.y1 - 1e-6 &&
          b.y0 < a.y1 - 1e-6 &&
          a.z0 < b.z1 - 1e-6 &&
          b.z0 < a.z1 - 1e-6;
      expect(
        chevauche,
        isFalse,
        reason:
            '${libelleMembre(a.type)} (${a.x0}–${a.x1}, ${a.z0}–${a.z1}) et '
            '${libelleMembre(b.type)} (${b.x0}–${b.x1}, ${b.z0}–${b.z1})',
      );
    }
  }
}

void main() {
  const p = ParametresMurs();

  group('vérification de la hauteur selon la pose', () {
    test('pose courante : ne passe pas ; la pose qui passe est proposée', () {
      final m1 = problemesOuvertures(
        _mur(_fenetre(_cadreLisseSimple)),
        p,
      ).single;
      expect(m1, contains('le linteau 2×8 ne passe pas sous la lisse haute'));
      expect(m1, contains('il manque ${formatImperial(1.5)}'));
      expect(
        m1,
        contains('Avec la pose « Sous une lisse simple », elle passe'),
      );

      final m2 = problemesOuvertures(_mur(_fenetre(_cadreSabliere)), p).single;
      expect(m2, contains('il manque ${formatImperial(3)}'));
      expect(
        m2,
        contains('Avec la pose « À la place des lisses », elle passe'),
      );

      // Trop haute pour toutes les poses : rien n'est proposé.
      final m3 = problemesOuvertures(_mur(_fenetre(80)), p).single;
      expect(m3, isNot(contains('Avec la pose')));
      expect(m3, contains('sans linteau'));
    });

    test('sous une lisse simple : passe à 94 1/2 po, pas plus haut', () {
      expect(
        problemesOuvertures(
          _mur(_fenetre(_cadreLisseSimple, pose: PoseLinteau.sousLisseSimple)),
          p,
        ),
        isEmpty,
      );
      final m = problemesOuvertures(
        _mur(_fenetre(_cadreSabliere, pose: PoseLinteau.sousLisseSimple)),
        p,
      ).single;
      expect(m, contains('ne passe pas sous la lisse simple'));
      expect(m, contains('la lisse du dessus est à ${formatImperial(94.5)}'));
      expect(m, contains('Avec la pose « À la place des lisses », elle passe'));
    });

    test('à la place des lisses : passe jusqu\'au dessus du mur', () {
      expect(
        problemesOuvertures(
          _mur(_fenetre(_cadreSabliere, pose: PoseLinteau.aLaPlaceDesLisses)),
          p,
        ),
        isEmpty,
      );
      final m = problemesOuvertures(
        _mur(_fenetre(75, pose: PoseLinteau.aLaPlaceDesLisses)),
        p,
      ).single;
      expect(m, contains('ne passe pas dans la hauteur du mur'));
      expect(m, contains('le dessus du mur est à ${formatImperial(96)}'));
      expect(m, contains('il manque ${formatImperial(1)}'));
    });

    test('sans linteau : la baie monte jusqu\'au dessous des lisses', () {
      // Cadre de 78 1/4 po : baie de 13 1/4 à 93 po (allège 14 − 3/4 + cadre + 1 1/2).
      expect(
        problemesOuvertures(
          _mur(_fenetre(78.25, pose: PoseLinteau.porteeParPoutre)),
          p,
        ),
        isEmpty,
      );
      final m = problemesOuvertures(
        _mur(_fenetre(79.25, pose: PoseLinteau.porteeParPoutre)),
        p,
      ).single;
      expect(m, contains('la baie dépasse le dessous des lisses hautes'));
      expect(m, contains('il manque ${formatImperial(1)}'));
    });

    test('une seule lisse haute : « sous une lisse simple » ne gagne rien', () {
      const une = ParametresMurs(lissesHautes: 1);
      // Lisse à 94 1/2 po : un dessus de linteau à 96 po ne passe pas…
      final o = _fenetre(_cadreSabliere, pose: PoseLinteau.sousLisseSimple);
      expect(problemesOuvertures(_mur(o), une), hasLength(1));
      // … sauf à la place de la lisse.
      expect(
        problemesOuvertures(
          _mur(o.avecPose(PoseLinteau.aLaPlaceDesLisses)),
          une,
        ),
        isEmpty,
      );
      expect(hauteursLinteau(o, une, _h), (96, 94.5));
    });

    test(
      'le calcul refuse une ouverture qui ne passe pas (message complet)',
      () {
        expect(
          () => _calcul(_fenetre(_cadreSabliere)),
          throwsA(
            isA<SpecInvalide>().having(
              (e) => e.message,
              'message',
              contains('À la place des lisses'),
            ),
          ),
        );
      },
    );
  });

  group('ossature', () {
    test(
      'pose courante : rien ne change (lisses entières, courts montants)',
      () {
        final r = _calcul(_fenetre(48));
        expect(_de(r, TypeMembre.lisseHaute), hasLength(2));
        expect(
          _de(
            r,
            TypeMembre.lisseHaute,
          ).every((m) => m.longueurCoupe == _longueur),
          isTrue,
        );
        expect(_de(r, TypeMembre.linteau), hasLength(2));
        expect(r.plaquesLiaison, 0);
        _sansChevauchement(r);
      },
    );

    test(
      'sous une lisse simple : la lisse du dessous est coupée sur le linteau',
      () {
        final r = _calcul(
          _fenetre(_cadreLisseSimple, pose: PoseLinteau.sousLisseSimple),
        );
        final linteau = _de(r, TypeMembre.linteau).first;
        expect(linteau.z1, closeTo(94.5, 1e-9));
        final lisses = _de(r, TypeMembre.lisseHaute);
        final dessous = lisses.where((m) => m.z0 == 93).toList();
        final dessus = lisses.where((m) => m.z0 == 94.5).toList();
        expect(dessus.single.longueurCoupe, _longueur);
        expect(dessous, hasLength(2));
        // La lisse coupée laisse exactement la place du linteau (baie + jacks).
        final longueurLinteau = linteau.x1 - linteau.x0;
        expect(
          dessous.fold(0.0, (a, m) => a + m.longueurCoupe),
          closeTo(_longueur - longueurLinteau, 1e-9),
        );
        expect(_de(r, TypeMembre.courtHaut), isEmpty);
        expect(r.plaquesLiaison, 0);
        expect(
          r.avertissements.join(),
          contains('passe sans joint au-dessus du linteau'),
        );
        _sansChevauchement(r);
      },
    );

    test('à la place des lisses : les deux lisses coupées, deux plaques de liaison', () {
      final r = _calcul(
        _fenetre(_cadreSabliere, pose: PoseLinteau.aLaPlaceDesLisses),
      );
      expect(_de(r, TypeMembre.linteau).first.z1, closeTo(96, 1e-9));
      final lisses = _de(r, TypeMembre.lisseHaute);
      expect(lisses, hasLength(4));
      expect(r.plaquesLiaison, 2);
      expect(
        r.avertissements.join(),
        contains('plaque d\'acier galvanisé de 3 × 6 po'),
      );
      _sansChevauchement(r);
    });

    test(
      'à la place des lisses, linteau un peu plus bas : cale pour l\'affleurer',
      () {
        // Dessus du linteau à 95 po : il traverse les deux lisses, 1 po sous le dessus du mur.
        final r = _calcul(_fenetre(73, pose: PoseLinteau.aLaPlaceDesLisses));
        expect(_de(r, TypeMembre.lisseHaute), hasLength(4));
        expect(r.plaquesLiaison, 2);
        expect(
          r.avertissements.join(),
          contains('${formatImperial(1)} sous le dessus du mur'),
        );
        _sansChevauchement(r);
      },
    );

    test('pose remontée choisie alors que la pose courante suffit : lisses entières', () {
      final r = _calcul(_fenetre(48, pose: PoseLinteau.aLaPlaceDesLisses));
      expect(_de(r, TypeMembre.lisseHaute), hasLength(2));
      expect(r.plaquesLiaison, 0);
      expect(_de(r, TypeMembre.courtHaut), isNotEmpty);
      _sansChevauchement(r);
    });

    test('sans linteau : pas de linteau, une traverse, des courts montants, l\'ingénieur', () {
      final r = _calcul(_fenetre(72, pose: PoseLinteau.porteeParPoutre));
      expect(_de(r, TypeMembre.linteau), isEmpty);
      final traverse = _de(r, TypeMembre.traverse).single;
      // Baie de 13 1/4 à 86 3/4 po ; traverse à plat de 1 1/2 po au-dessus.
      expect(traverse.z0, closeTo(86.75, 1e-9));
      expect(traverse.z1, closeTo(88.25, 1e-9));
      for (final c in _de(r, TypeMembre.courtHaut)) {
        expect(c.z0, closeTo(88.25, 1e-9));
        expect(c.z1, closeTo(93, 1e-9));
      }
      expect(_de(r, TypeMembre.lisseHaute), hasLength(2));
      expect(r.avertissements.join(), contains('ingénieur'));
      _sansChevauchement(r);
    });

    test(
      'sans linteau, baie jusqu\'aux lisses : ni traverse ni courts montants',
      () {
        final r = _calcul(_fenetre(78.25, pose: PoseLinteau.porteeParPoutre));
        expect(_de(r, TypeMembre.traverse), isEmpty);
        expect(_de(r, TypeMembre.courtHaut), isEmpty);
        _sansChevauchement(r);
      },
    );
  });

  group('commande et projet', () {
    ProjetCharpente projet(PoseLinteau pose) => ProjetCharpente(
      plancherActif: false,
      mursActifs: true,
      murs: ParametresMursProjet(
        mode: ModeMurs.libres,
        libres: [_mur(_fenetre(_cadreSabliere, pose: pose))],
      ),
    );

    test('plaques de liaison dans la quincaillerie de la commande', () {
      final texte = calculerProjet(projet(PoseLinteau.aLaPlaceDesLisses))
          .commande
          .enTexte();
      expect(
        texte,
        contains('2 × Plaque de liaison en acier galvanisé 3 × 6 po (0,91 mm)'),
      );
    });

    test(
      'la pose est gardée dans le projet ; un ancien projet = pose courante',
      () {
        for (final pose in PoseLinteau.values) {
          final j = jsonDecode(jsonEncode(projet(pose).toJson()));
          final relu = ProjetCharpente.fromJson(j)
              .murs
              .libres
              .single
              .ouvertures
              .single;
          expect(relu.pose, pose);
          final o = (j['murs']['libres'][0]['ouvertures'][0] as Map);
          expect(o.containsKey('pose'), pose != PoseLinteau.sousLesLisses);
        }
        final j = jsonDecode(
          jsonEncode(projet(PoseLinteau.sousLesLisses).toJson()),
        );
        expect(
          ProjetCharpente.fromJson(j).murs.libres.single.ouvertures.single.pose,
          PoseLinteau.sousLesLisses,
        );
        (j['murs']['libres'][0]['ouvertures'][0] as Map)['pose'] = 'inventee';
        expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
      },
    );

    test('la position (avecPosition) garde la pose', () {
      final o = _fenetre(72, pose: PoseLinteau.porteeParPoutre);
      expect(o.avecPosition(10).pose, PoseLinteau.porteeParPoutre);
      expect(o.avecPose(PoseLinteau.sousLisseSimple).position, 72);
    });
  });
}
