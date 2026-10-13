// Portes et fenêtres qui n'entrent pas dans la charpente : tous les problèmes, avec le détail des
// hauteurs (cas d'un solarium dont le vitrage monte jusqu'à la sablière).
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/plancher.dart' show SpecInvalide;
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mur de 8 pi (96 po), 2 lisses hautes, linteau 2×8 par défaut : la lisse haute est à 93 po.
const double _h = 96;

Ouverture _fenetre(
  double position, {
  String nom = '',
  double largeur = 36,
  double hauteur = 48,
  double allege = 36,
}) => Ouverture(
  type: TypeOuverture.fenetre,
  nom: nom,
  largeurCadre: largeur,
  hauteurCadre: hauteur,
  allege: allege,
  position: position,
);

Ouverture _porte(
  double position, {
  String nom = '',
  double largeur = 36,
  double hauteur = 80,
}) => Ouverture(
  type: TypeOuverture.porte,
  nom: nom,
  largeurCadre: largeur,
  hauteurCadre: hauteur,
  position: position,
);

SpecMur _mur(List<Ouverture> ouvertures, {double longueur = 192}) => SpecMur(
  nom: 'Mur 2',
  longueur: longueur,
  hauteur: _h,
  ouvertures: ouvertures,
);

void main() {
  group('désignation', () {
    test('type et repère', () {
      expect(_fenetre(50, nom: 'Poste 3').designation, 'Fenêtre Poste 3');
      expect(_porte(50).designation, 'Porte');
      expect(_porte(50, nom: ' P1 ').designation, 'Porte P1');
    });
  });

  group('une ouverture trop haute pour le linteau', () {
    test(
      'fenêtre de 82 po à 14 po du plancher : le détail et ce qu\'il manque',
      () {
        final p = problemesOuvertures(
          _mur([
            _fenetre(96, nom: 'Poste 3', largeur: 66, hauteur: 82, allege: 14),
          ]),
          const ParametresMurs(),
        );
        expect(p, hasLength(1));
        final m = p.single;
        expect(
          m,
          startsWith(
            'Mur 2 : Fenêtre Poste 3 : le linteau 2×8 ne passe pas sous la lisse haute.',
          ),
        );
        // 14 + 82 + 3/4 + 7 1/4 = 104 po ; lisse à 93 po ; il manque 11 po.
        expect(m, contains('allège ${formatImperial(14)}'));
        expect(m, contains('cadre ${formatImperial(82)}'));
        expect(m, contains('jeu du haut ${formatImperial(0.75)}'));
        expect(
          m,
          contains('linteau ${formatImperial(7.25)} = ${formatImperial(104)}'),
        );
        expect(m, contains('la lisse haute est à ${formatImperial(93)}'));
        expect(m, contains('mur de ${formatImperial(96)} moins 2 lisses'));
        expect(m, contains('il manque ${formatImperial(11)}'));
        expect(m, contains('une poutre qui sert de linteau'));
      },
    );

    test('porte-patio avec imposte (99 1/8 po) : il manque 14 7/8 po', () {
      final m = problemesOuvertures(
        _mur([_porte(96, nom: 'Poste 8 + 9', largeur: 70.75, hauteur: 99.125)]),
        const ParametresMurs(),
      ).single;
      expect(
        m,
        contains(
          'cadre ${formatImperial(99.125)} + jeu ${formatImperial(1.5)}',
        ),
      );
      expect(m, contains('= ${formatImperial(107.875)}'));
      expect(m, contains('il manque ${formatImperial(14.875)}'));
    });

    test('une lisse haute : la lisse est plus haut, le message le dit', () {
      final m = problemesOuvertures(
        _mur([_fenetre(96, largeur: 66, hauteur: 82, allege: 14)]),
        const ParametresMurs(lissesHautes: 1),
      ).single;
      expect(m, contains('moins 1 lisse)'));
      expect(m, contains('il manque ${formatImperial(9.5)}'));
    });

    test('une fenêtre qui entre : aucun problème', () {
      expect(
        problemesOuvertures(_mur([_fenetre(96)]), const ParametresMurs()),
        isEmpty,
      );
    });

    test('le calcul refuse avec le premier problème, mot pour mot', () {
      final spec = _mur([_fenetre(96, largeur: 66, hauteur: 82, allege: 14)]);
      final premier = problemesOuvertures(spec, const ParametresMurs()).first;
      expect(
        () => calculerMurs([spec], const ParametresMurs()),
        throwsA(
          isA<SpecInvalide>().having((e) => e.message, 'message', premier),
        ),
      );
    });
  });

  group('tous les problèmes, pas seulement le premier', () {
    test('trois ouvertures, quatre problèmes, dans l\'ordre du mur', () {
      final p = problemesOuvertures(
        _mur([
          _fenetre(20, nom: 'A'), // trop près du début
          _fenetre(
            96,
            nom: 'B',
            largeur: 66,
            hauteur: 82,
            allege: 14,
          ), // linteau
          _porte(
            120,
            nom: 'C',
          ), // chevauche B, et trop haute ? non : 80 + 1 1/2 + 7 1/4 < 93
        ]),
        const ParametresMurs(),
      );
      expect(p, hasLength(3));
      expect(p[0], contains('Fenêtre A trop près du début du mur'));
      expect(p[1], contains('Fenêtre B : le linteau'));
      expect(p[2], contains('Porte C chevauche une autre ouverture'));
    });

    test('une ouverture peut avoir plusieurs problèmes à la fois', () {
      final p = problemesOuvertures(
        _mur([
          _fenetre(30, nom: 'D', largeur: 60, hauteur: 82, allege: 14),
        ], longueur: 96),
        const ParametresMurs(),
      );
      expect(p.where((m) => m.contains('Fenêtre D')), hasLength(2));
      expect(p.any((m) => m.contains('trop près du début')), isTrue);
      expect(p.any((m) => m.contains('le linteau')), isTrue);
    });

    test('dimensions invalides : signalées, sans autre vérification de cette ouverture', () {
      final p = problemesOuvertures(
        _mur([
          const Ouverture(
            type: TypeOuverture.fenetre,
            largeurCadre: 0,
            hauteurCadre: 48,
            position: 96,
          ),
        ]),
        const ParametresMurs(),
      );
      expect(p.single, contains('dimensions invalides'));
    });
  });

  group('projet entier', () {
    ProjetCharpente projet({
      required Map<int, List<Ouverture>> ouvertures,
      bool mursActifs = true,
      FormePlancher forme = const FormeRectangle(156, 144),
    }) => ProjetCharpente(
      plancher: ParametresPlancher(forme: forme),
      mursActifs: mursActifs,
      murs: ParametresMursProjet(hauteur: 96, ouverturesContour: ouvertures),
    );

    test('mur par mur, avec le nom de chaque mur', () {
      final p = problemesDesOuvertures(
        projet(
          ouvertures: {
            1: [_porte(72, nom: 'P1', largeur: 70.75, hauteur: 99.125)],
            3: [_fenetre(72, nom: 'F3', largeur: 66, hauteur: 82, allege: 14)],
          },
        ),
      );
      expect(p, hasLength(2));
      expect(p[0], startsWith('Mur 2 : Porte P1'));
      expect(p[1], startsWith('Mur 4 : Fenêtre F3'));
      // Le calcul, lui, s'arrête au premier.
      final r = calculerProjet(
        projet(
          ouvertures: {
            1: [_porte(72, nom: 'P1', largeur: 70.75, hauteur: 99.125)],
            3: [_fenetre(72, nom: 'F3', largeur: 66, hauteur: 82, allege: 14)],
          },
        ),
      );
      expect(r.erreurMurs, p.first);
    });

    test('tout entre, murs absents ou forme impossible : rien', () {
      expect(
        problemesDesOuvertures(
          projet(
            ouvertures: {
              0: [_fenetre(78)],
            },
          ),
        ),
        isEmpty,
      );
      expect(
        problemesDesOuvertures(
          projet(
            ouvertures: {
              0: [_fenetre(78, hauteur: 90)],
            },
            mursActifs: false,
          ),
        ),
        isEmpty,
      );
      expect(
        problemesDesOuvertures(
          projet(
            ouvertures: {
              0: [_fenetre(78, hauteur: 90)],
            },
            forme: const FormePoints([Pt(0, 0), Pt(10, 0), Pt(20, 0)]),
          ),
        ),
        isEmpty,
      );
    });
  });
}
