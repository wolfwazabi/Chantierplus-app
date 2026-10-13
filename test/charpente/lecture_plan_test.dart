// Lecture d'un plan : la réponse du serveur, les valeurs à confirmer, les corrections, les chemins.
import 'dart:convert';

import 'package:construction_app/charpente/lecture_plan.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:flutter_test/flutter_test.dart';

import '../doubles/faux_plans.dart';

// Mêmes tables que tests/rules/lecture_plans.unit.test.mjs : le serveur et l'application
// acceptent exactement les mêmes chemins.
const _cheminsPermis = [
  'plancher.forme.longueur',
  'plancher.forme.largeur',
  'plancher.forme.cotes.0',
  'plancher.forme.cotes.12',
  'plancher.forme.angles.3',
  'plancher.forme.points.2.0',
  'plancher.forme.points.2.1',
  'plancher.espacement',
  'plancher.section',
  'murs.hauteur',
  'murs.params.espacement',
  'murs.params.section',
  'murs.ouverturesContour.0.0.largeur',
  'murs.ouverturesContour.3.12.hauteur',
  'murs.ouverturesContour.1.2.allege',
  'murs.ouverturesContour.1.2.position',
  'murs.ouverturesContour.1.2.type',
  'murs.libres.0.longueur',
  'murs.libres.5.hauteur',
  'murs.libres.1.ouvertures.0.largeur',
  'murs.libres.1.ouvertures.3.type',
  'plancher.etriers',
  'plancher.poutres.nombre',
  'plancher.poutres.plis',
  'plancher.poutres.section',
  'plancher.poutres.pieux',
  'plancher.poutres.retraitPieux',
];
const _cheminsRefuses = [
  '',
  'plancher',
  'plancher.entremises',
  'plancher.poutres',
  'plancher.poutres.hauteurPatte',
  'plancher.poutres.x',
  'plancher.coteMaison',
  'plancher.forme',
  'plancher.forme.type',
  'plancher.forme.points.0',
  'plancher.forme.points.0.2',
  'plancher.forme.cotes.',
  'plancher.forme.cotes.123',
  'plancher.forme.longueur.x',
  'murs',
  'murs.mode',
  'murs.params',
  'murs.params.linteau',
  'murs.ouverturesContour',
  'murs.ouverturesContour.0',
  'murs.ouverturesContour.0.0',
  'murs.ouverturesContour.0.0.nom',
  'murs.ouverturesContour.0.0.jeuLargeur',
  'murs.ouverturesContour.0.0.largeur.x',
  'murs.ouverturesContour.123.0.largeur',
  'murs.libres',
  'murs.libres.0',
  'murs.libres.0.nom',
  'murs.libres.0.ouvertures',
  'murs.libres.0.ouvertures.0',
  '__proto__',
  'constructor.prototype',
  'plancher.__proto__.x',
  ' plancher.espacement',
  'plancher.espacement ',
  'PLANCHER.ESPACEMENT',
];

const _f2Largeur = 'murs.ouverturesContour.1.0.largeur';
const _f2Allege = 'murs.ouverturesContour.1.0.allege';

void main() {
  group('lecture de la réponse du serveur', () {
    test('le garage : projet, explication, niveau, confiance, hypothèses', () {
      final l = LecturePlan.depuis(lectureGarage());
      expect(l.explication, contains('Garage de 24 pi × 20 pi'));
      expect(l.niveauLu, 'Rez-de-chaussée, page 2');
      expect(l.echelle, '1/4 po = 1 pi');
      expect(l.confiance, ConfianceLecture.moyenne);
      expect(l.hypotheses, [
        'Entraxe des solives de 16 po supposé.',
        'Côté 0 = longueur du bas du plan.',
        // Ajoutée par le serveur : les jeux ne sont jamais donnés par un plan.
        'Jeux autour des portes et fenêtres : 1 po en largeur et 1 1/2 po en hauteur (valeurs courantes), en plus des dimensions du cadre.',
      ]);
      expect(l.projet.nom, 'Garage Tremblay');
      expect(l.projet.plancherActif, isTrue);
      expect(l.projet.mursActifs, isTrue);
    });

    test('portes et fenêtres du projet', () {
      final p = LecturePlan.depuis(lectureGarage()).projet;
      final cote0 = p.murs.ouverturesContour[0]!;
      final cote1 = p.murs.ouverturesContour[1]!;
      expect(cote0.map((o) => o.nom), ['F1', 'P1']);
      expect(cote0[0].largeurCadre, 36);
      expect(cote0[0].hauteurCadre, 48);
      expect(cote0[0].allege, 36);
      // 60 po du coin : le mur 1 s'appuie sur le mur 4 (3 1/2 po), donc 56 1/2 po depuis son début.
      expect(cote0[0].position, 56.5);
      expect(cote0[1].position, 116.5);
      expect(cote0[1].hauteurCadre, 80);
      expect(cote1.single.nom, 'F2');
      expect(cote1.single.largeurCadre, 24);
    });

    test('les valeurs : 2 à confirmer, 5 à vérifier, 8 lues', () {
      final l = LecturePlan.depuis(lectureGarage());
      expect(l.aConfirmer.map((v) => v.chemin).toSet(), {
        _f2Largeur,
        _f2Allege,
      });
      expect(l.aVerifier.map((v) => v.chemin).toSet(), {
        'murs.hauteur',
        'murs.ouverturesContour.0.0.position',
        'murs.ouverturesContour.0.1.position',
        'murs.ouverturesContour.1.0.position',
        'plancher.etriers',
      });
      expect(l.lues, hasLength(8));
      expect(l.lues.every((v) => v.verifiee), isTrue);
      expect(l.lues.first.lecture, '24\'-0"');
      expect(l.restantes, 2);
      expect(l.toutConfirme, isFalse);
    });

    test('la cote mal convertie : valeur du plan et raison du serveur', () {
      final v = LecturePlan.depuis(lectureGarage()).aConfirmer
          .firstWhere((v) => v.chemin == _f2Largeur);
      expect(v.valeurPlan, 36);
      expect(v.lecture, '3\'-0"');
      expect(v.raison, contains('36'));
      expect(v.raison, contains('24'));
      expect(v.verifiee, isFalse);
    });

    test('cartes génériques de la plateforme (Map<Object?, Object?>)', () {
      final l = LecturePlan.depuis(enCartesGeneriques(lectureGarage()));
      expect(l.projet.murs.ouverturesContour[1]!.single.nom, 'F2');
      expect(l.valeurDe(_f2Largeur), 24);
      final modifiee = l.modifier(_f2Largeur, 36);
      expect(
        modifiee.projet.murs.ouverturesContour[1]!.single.largeurCadre,
        36,
      );
    });

    test(
      'réponse sans projet ou avec un projet illisible : FormatException',
      () {
        expect(() => LecturePlan.depuis({}), throwsFormatException);
        expect(
          () => LecturePlan.depuis({'projet': 'x'}),
          throwsFormatException,
        );
        final cassee = lectureGarage();
        (cassee['projet'] as Map)['plancher'] = 'pas un plancher';
        expect(() => LecturePlan.depuis(cassee), throwsFormatException);
        final sansVersion = lectureGarage();
        (sansVersion['projet'] as Map)['v'] = 2;
        expect(() => LecturePlan.depuis(sansVersion), throwsFormatException);
      },
    );

    test(
      'valeurs inutilisables : ignorées (chemin refusé, inexistant, mal formé)',
      () {
        final r = lectureGarage();
        r['valeurs'] = [
          {'chemin': 'plancher.entremises', 'niveau': 'incertain'},
          {
            'chemin': 'murs.ouverturesContour.0.9.largeur',
            'niveau': 'incertain',
          },
          {'chemin': '__proto__.x', 'niveau': 'incertain'},
          {'niveau': 'incertain'},
          {'chemin': 42, 'niveau': 'incertain'},
          'texte',
          null,
          {'chemin': 'plancher.forme.longueur', 'niveau': 'lu'},
        ];
        final l = LecturePlan.depuis(r);
        expect(l.valeurs.map((v) => v.chemin), ['plancher.forme.longueur']);
        for (final mauvais in [null, 'x', 5, <String, dynamic>{}]) {
          r['valeurs'] = mauvais;
          expect(LecturePlan.depuis(r).valeurs, isEmpty);
        }
      },
    );

    test('niveau ou confiance inconnus : le plus prudent', () {
      final r = lectureGarage();
      r['confiance'] = 'parfaite';
      r['valeurs'] = [
        {'chemin': 'plancher.forme.longueur', 'niveau': 'certain'},
        {'chemin': 'plancher.forme.largeur'},
      ];
      final l = LecturePlan.depuis(r);
      expect(l.confiance, ConfianceLecture.moyenne);
      expect(l.valeurs.map((v) => v.niveau), [
        NiveauValeur.incertain,
        NiveauValeur.incertain,
      ]);
      r['confiance'] = 'faible';
      expect(LecturePlan.depuis(r).confiance, ConfianceLecture.faible);
    });

    test('hypothèses et textes : nettoyés', () {
      final r = lectureGarage();
      r['hypotheses'] = ['  ok  ', '', 42, null, '   '];
      r['explication'] = null;
      final l = LecturePlan.depuis(r);
      expect(l.hypotheses, ['ok']);
      expect(l.explication, '');
    });
  });

  group('confirmation', () {
    test('confirmer une valeur incertaine fait baisser le compte', () {
      final l = LecturePlan.depuis(lectureGarage());
      final a = l.confirmer(_f2Largeur);
      expect(a.restantes, 1);
      expect(a.estConfirmee(_f2Largeur), isTrue);
      expect(a.toutConfirme, isFalse);
      final b = a.confirmer(_f2Allege);
      expect(b.restantes, 0);
      expect(b.toutConfirme, isTrue);
      // L'original ne change pas.
      expect(l.restantes, 2);
      expect(l.estConfirmee(_f2Largeur), isFalse);
    });

    test('confirmer deux fois, ou un chemin inconnu : sans effet', () {
      final l = LecturePlan.depuis(lectureGarage()).confirmer(_f2Largeur);
      expect(l.confirmer(_f2Largeur).restantes, 1);
      expect(l.confirmer('plancher.espacement'), same(l));
      expect(l.confirmer('n-importe-quoi'), same(l));
    });

    test('revenir sur une confirmation', () {
      final l = LecturePlan.depuis(lectureGarage())
          .confirmer(_f2Largeur)
          .annulerConfirmation(_f2Largeur);
      expect(l.restantes, 2);
      expect(l.annulerConfirmation(_f2Largeur), same(l));
    });

    test('une valeur « à vérifier » ou « lue » ne bloque jamais', () {
      final l = LecturePlan.depuis(lectureGarage())
          .confirmer(_f2Largeur)
          .confirmer(_f2Allege);
      expect(
        l.toutConfirme,
        isTrue,
      ); // les valeurs déduites restent non confirmées
      expect(l.aVerifier.any((v) => !l.estConfirmee(v.chemin)), isTrue);
    });

    test('sans aucune valeur incertaine : tout est déjà confirmé', () {
      final r = lectureGarage();
      r['valeurs'] = [
        {'chemin': 'plancher.forme.longueur', 'niveau': 'lu'},
      ];
      expect(LecturePlan.depuis(r).toutConfirme, isTrue);
      r['valeurs'] = [];
      expect(LecturePlan.depuis(r).toutConfirme, isTrue);
    });
  });

  group('correction d\'une valeur', () {
    test('la valeur du projet change, l\'original reste intact', () {
      final l = LecturePlan.depuis(lectureGarage());
      final m = l.modifier(_f2Largeur, 36);
      expect(m.valeurDe(_f2Largeur), 36);
      expect(m.projet.murs.ouverturesContour[1]!.single.largeurCadre, 36);
      expect(l.valeurDe(_f2Largeur), 24);
      expect(l.projet.murs.ouverturesContour[1]!.single.largeurCadre, 24);
    });

    test(
      'corriger retire la confirmation : il faut confirmer la valeur finale',
      () {
        final l = LecturePlan.depuis(lectureGarage()).confirmer(_f2Largeur);
        expect(l.estConfirmee(_f2Largeur), isTrue);
        final m = l.modifier(_f2Largeur, 36);
        expect(m.estConfirmee(_f2Largeur), isFalse);
        expect(m.restantes, 2);
        expect(m.confirmer(_f2Largeur).restantes, 1);
      },
    );

    test('les autres confirmations sont gardées', () {
      final l = LecturePlan.depuis(lectureGarage())
          .confirmer(_f2Allege)
          .modifier(_f2Largeur, 36);
      expect(l.estConfirmee(_f2Allege), isTrue);
    });

    test('plancher, hauteur des murs, allège, position, entraxe', () {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'plancher.espacement',
        'niveau': 'deduit',
      });
      var l = LecturePlan.depuis(r);
      l = l.modifier('plancher.forme.longueur', 300);
      l = l.modifier('murs.hauteur', 96);
      l = l.modifier(_f2Allege, 42.5);
      l = l.modifier('murs.ouverturesContour.0.1.position', 130);
      l = l.modifier('plancher.espacement', 12);
      expect(l.projet.plancher.espacement, 12);
      expect(l.projet.murs.hauteur, 96);
      expect(l.projet.murs.ouverturesContour[1]!.single.allege, 42.5);
      expect(l.valeurDe('murs.ouverturesContour.0.1.position'), 130);
      expect(l.projet.murs.ouverturesContour[0]![1].position, 126.5);
    });

    test('un choix : section des solives, type d\'une ouverture', () {
      final r = lectureGarage();
      r['valeurs'] = [
        {'chemin': 'plancher.section', 'niveau': 'incertain'},
        {'chemin': 'murs.ouverturesContour.0.0.type', 'niveau': 'incertain'},
      ];
      var l = LecturePlan.depuis(r);
      expect(l.valeurDe('plancher.section'), '2×10');
      l = l.modifier('plancher.section', '2×8');
      expect(l.projet.plancher.section.nom, '2×8');
      l = l.modifier('murs.ouverturesContour.0.0.type', 'porte');
      expect(l.valeurDe('murs.ouverturesContour.0.0.type'), 'porte');
    });

    test('valeur hors des bornes ou d\'un mauvais genre : refusée, lecture intacte', () {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'plancher.espacement',
        'niveau': 'deduit',
      });
      final l = LecturePlan.depuis(r);
      for (final v in <Object>[
        0,
        0.5,
        -3,
        13000,
        double.nan,
        double.infinity,
        '36',
        true,
      ]) {
        expect(
          () => l.modifier(_f2Largeur, v),
          throwsFormatException,
          reason: '$v',
        );
      }
      expect(() => l.modifier('murs.hauteur', 10), throwsFormatException);
      expect(() => l.modifier('murs.hauteur', 300), throwsFormatException);
      expect(() => l.modifier('plancher.espacement', 3), throwsFormatException);
      expect(l.valeurDe(_f2Largeur), 24);
    });

    test(
      'choix non permis, valeur absente de la liste, chemin inconnu : refusés',
      () {
        final r = lectureGarage();
        r['valeurs'] = [
          {'chemin': 'plancher.section', 'niveau': 'incertain'},
        ];
        final l = LecturePlan.depuis(r);
        expect(
          () => l.modifier('plancher.section', '2×4'),
          throwsFormatException,
        );
        expect(() => l.modifier('plancher.section', 8), throwsFormatException);
        // Un chemin qui n'est pas dans les valeurs de la lecture ne se corrige pas.
        expect(
          () => l.modifier('plancher.espacement', 12),
          throwsFormatException,
        );
        expect(
          () => l.modifier('plancher.etriers', 'aucun'),
          throwsFormatException,
        );
      },
    );
  });

  group('chemins', () {
    test('mêmes chemins permis et refusés que le serveur', () {
      for (final c in _cheminsPermis) {
        expect(genreDuChemin(c), isNotNull, reason: c);
      }
      for (final c in _cheminsRefuses) {
        expect(genreDuChemin(c), isNull, reason: '«$c»');
      }
    });

    test('genres', () {
      expect(genreDuChemin('plancher.forme.longueur'), GenreValeur.longueur);
      expect(genreDuChemin('plancher.forme.angles.0'), GenreValeur.angle);
      expect(genreDuChemin('plancher.espacement'), GenreValeur.nombre);
      expect(genreDuChemin('murs.params.espacement'), GenreValeur.nombre);
      expect(genreDuChemin('plancher.section'), GenreValeur.choix);
      expect(
        genreDuChemin('murs.ouverturesContour.0.0.type'),
        GenreValeur.choix,
      );
      expect(genreDuChemin(_f2Largeur), GenreValeur.longueur);
      expect(
        genreDuChemin('murs.libres.0.ouvertures.1.allege'),
        GenreValeur.longueur,
      );
    });

    test('choix permis', () {
      expect(choixDuChemin('plancher.section'), ['2×6', '2×8', '2×10', '2×12']);
      expect(choixDuChemin('murs.params.section'), ['2×4', '2×6']);
      expect(choixDuChemin('murs.ouverturesContour.0.0.type'), [
        'porte',
        'fenetre',
      ]);
      expect(choixDuChemin('plancher.espacement'), isEmpty);
    });

    test('bornes (celles du filtre du serveur)', () {
      expect(bornesDuChemin('plancher.forme.longueur'), (1.0, pouceMaxSaisie));
      expect(bornesDuChemin('plancher.forme.cotes.2'), (1.0, pouceMaxSaisie));
      expect(bornesDuChemin('plancher.forme.angles.0'), (0.01, 359.99));
      expect(bornesDuChemin('plancher.forme.points.0.1'), (
        -pouceMaxSaisie,
        pouceMaxSaisie,
      ));
      expect(bornesDuChemin('plancher.espacement'), (6.0, 48.0));
      expect(bornesDuChemin('murs.hauteur'), (24.0, 240.0));
      expect(bornesDuChemin('murs.libres.0.hauteur'), (24.0, 240.0));
      expect(bornesDuChemin('murs.libres.0.longueur'), (6.0, 1200.0));
      expect(bornesDuChemin(_f2Largeur), (1.0, pouceMaxSaisie));
      expect(bornesDuChemin('murs.ouverturesContour.0.0.hauteur'), (
        1.0,
        pouceMaxSaisie,
      ));
      expect(bornesDuChemin(_f2Allege), (0.0, pouceMaxSaisie));
      expect(bornesDuChemin('murs.ouverturesContour.0.1.position'), (
        0.0,
        pouceMaxSaisie,
      ));
    });

    test('lireChemin : cartes, listes, bornes', () {
      final j = {
        'a': {
          'b': [
            {'c': 5},
            7,
          ],
        },
      };
      expect(lireChemin(j, 'a.b.0.c'), 5);
      expect(lireChemin(j, 'a.b.1'), 7);
      expect(lireChemin(j, 'a.b.2'), isNull);
      expect(lireChemin(j, 'a.b.-1'), isNull);
      expect(lireChemin(j, 'a.b.x'), isNull);
      expect(lireChemin(j, 'a.z'), isNull);
      expect(lireChemin(j, 'a.b.0.c.d'), isNull);
    });
  });

  group('position des ouvertures : du coin du plan au début du mur', () {
    /// Un L : 6 côtés, dont un coin rentrant (270°) entre les côtés 3 et 4.
    Map<String, dynamic> enL() {
      final r = lectureGarage();
      final p = r['projet'] as Map<String, dynamic>;
      (p['plancher'] as Map)['forme'] = {
        'type': 'points',
        'points': [
          [0, 0],
          [240, 0],
          [240, 120],
          [120, 120],
          [120, 240],
          [0, 240],
        ],
      };
      (p['murs'] as Map)['ouverturesContour'] = {
        for (var i = 0; i < 6; i++)
          '$i': [
            {
              'type': 'fenetre',
              'nom': 'F$i',
              'largeur': 24,
              'hauteur': 36,
              'allege': 36,
              'position': 60,
              'jeuLargeur': 1,
              'jeuHauteur': 1.5,
            },
          ],
      };
      return r;
    }

    test(
      'rectangle : le mur qui s\'appuie commence 3 1/2 po après le coin',
      () {
        final l = LecturePlan.depuis(lectureGarage());
        // Les valeurs du plan restent celles du plan (c'est ce que l'utilisateur confirme).
        expect(l.valeurDe('murs.ouverturesContour.0.0.position'), 60);
        expect(l.valeurDe('murs.ouverturesContour.1.0.position'), 100);
        // Le projet calculé les mesure depuis le début de chaque mur.
        expect(l.projet.murs.ouverturesContour[0]![0].position, 56.5);
        expect(l.projet.murs.ouverturesContour[1]![0].position, 100);
      },
    );

    test(
      'forme en L : chaque position moins le retrait du début de son mur',
      () {
        final l = LecturePlan.depuis(enL());
        final p = l.projet;
        final murs = mursDuContour(
          p.plancher.forme.construire(),
          hauteur: p.murs.hauteur,
          section: p.murs.params.section,
        );
        expect(murs, hasLength(6));
        for (var i = 0; i < 6; i++) {
          expect(
            p.murs.ouverturesContour[i]!.single.position,
            60 - murs[i].retraitDebut,
            reason: 'mur ${i + 1}',
          );
        }
        // Le L couvre les deux sens : murs qui s'appuient (+) et murs prolongés (−).
        expect(murs.any((m) => m.retraitDebut > 0), isTrue);
        expect(murs.any((m) => m.retraitDebut < 0), isTrue);
        expect(murs.any((m) => m.retraitDebut == 0), isTrue);
      },
    );

    test('la section des montants (2×6) change le retrait', () {
      final r = lectureGarage();
      (((r['projet'] as Map)['murs'] as Map)['params'] as Map)['section'] =
          '2×6';
      final l = LecturePlan.depuis(r);
      expect(l.projet.murs.ouverturesContour[0]![0].position, 60 - 5.5);
    });

    test('corriger une position garde la conversion', () {
      final l = LecturePlan.depuis(lectureGarage())
          .modifier('murs.ouverturesContour.0.0.position', 100);
      expect(l.projet.murs.ouverturesContour[0]![0].position, 96.5);
    });

    test('une position plus petite que le retrait du mur reste à 0 (jamais négative)', () {
      final l = LecturePlan.depuis(lectureGarage())
          .modifier('murs.ouverturesContour.0.0.position', 2);
      expect(l.valeurDe('murs.ouverturesContour.0.0.position'), 2);
      expect(l.projet.murs.ouverturesContour[0]![0].position, 0);
      // Le projet reste relisible (un brouillon enregistré ne devient pas illisible).
      expect(
        ProjetCharpente.fromJson(jsonDecode(jsonEncode(l.projet.toJson()))),
        isA<ProjetCharpente>(),
      );
    });

    test('murs libres, ou murs absents : aucune conversion', () {
      final r = lectureGarage();
      ((r['projet'] as Map)['murs'] as Map)['mode'] = 'libres';
      ((r['projet'] as Map)['murs'] as Map)['libres'] = [];
      expect(
        LecturePlan.depuis(r).projet.murs.ouverturesContour[0]![0].position,
        60,
      );
      final r2 = lectureGarage();
      (r2['projet'] as Map)['mursActifs'] = false;
      expect(
        LecturePlan.depuis(r2).projet.murs.ouverturesContour[0]![0].position,
        60,
      );
    });

    test(
      'forme impossible : pas d\'échec, les positions restent celles du plan',
      () {
        final r = lectureGarage();
        (((r['projet'] as Map)['plancher']) as Map)['forme'] = {
          'type': 'points',
          'points': [
            [0, 0],
            [10, 0],
            [20, 0],
          ],
        };
        final l = LecturePlan.depuis(r);
        expect(l.projet.murs.ouverturesContour[0]![0].position, 60);
        expect(calculerProjet(l.projet).erreurPlancher, isNotNull);
      },
    );

    test('ouverture sur un côté qui n\'existe pas : gardée telle quelle', () {
      final r = lectureGarage();
      final o =
          ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
      o['9'] = [
        {
          'type': 'porte',
          'nom': '',
          'largeur': 36,
          'hauteur': 80,
          'allege': 0,
          'position': 50,
          'jeuLargeur': 1,
          'jeuHauteur': 1.5,
        },
      ];
      final l = LecturePlan.depuis(r);
      expect(l.projet.murs.ouverturesContour[9]!.single.position, 50);
    });
  });

  group('avertissements : ce que le calcul ignorerait en silence', () {
    test('le garage : aucun', () {
      expect(LecturePlan.depuis(lectureGarage()).avertissements, isEmpty);
    });

    test('une fenêtre sur un mur qui n\'existe pas est signalée', () {
      final r = lectureGarage();
      final o =
          ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
      o['6'] = [
        {
          'type': 'fenetre',
          'nom': 'F9',
          'largeur': 36,
          'hauteur': 48,
          'allege': 36,
          'position': 60,
          'jeuLargeur': 1,
          'jeuHauteur': 1.5,
        },
      ];
      final a = LecturePlan.depuis(r).avertissements;
      expect(a, hasLength(1));
      expect(a.single, contains('Fenêtre F9'));
      expect(a.single, contains('mur 7'));
      expect(a.single, contains('4 murs'));
      expect(a.single, contains('pas comptée'));
    });

    test('plusieurs ouvertures, plusieurs murs : une phrase chacune', () {
      final r = lectureGarage();
      final o =
          ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
      Map<String, Object> porte(String nom) => {
        'type': 'porte',
        'nom': nom,
        'largeur': 36,
        'hauteur': 80,
        'allege': 0,
        'position': 60,
        'jeuLargeur': 1,
        'jeuHauteur': 1.5,
      };
      o['4'] = [porte('P4'), porte('P5')];
      o['5'] = [porte('P6')];
      expect(LecturePlan.depuis(r).avertissements, hasLength(3));
    });

    test('forme en L (6 murs) : le mur 5 existe, le 7 non', () {
      final r = lectureGarage();
      final p = r['projet'] as Map;
      (p['plancher'] as Map)['forme'] = {
        'type': 'points',
        'points': [
          [0, 0],
          [240, 0],
          [240, 120],
          [120, 120],
          [120, 240],
          [0, 240],
        ],
      };
      final o = (p['murs'] as Map)['ouverturesContour'] as Map;
      final porte = {
        'type': 'porte',
        'nom': 'P',
        'largeur': 36,
        'hauteur': 80,
        'allege': 0,
        'position': 40,
        'jeuLargeur': 1,
        'jeuHauteur': 1.5,
      };
      o['4'] = [porte];
      o['6'] = [porte];
      final a = LecturePlan.depuis(r).avertissements;
      expect(a, hasLength(1));
      expect(a.single, contains('mur 7'));
      expect(a.single, contains('6 murs'));
    });

    test(
      'murs libres, murs absents ou forme impossible : aucun avertissement',
      () {
        final r = lectureGarage();
        (r['projet'] as Map)['mursActifs'] = false;
        expect(LecturePlan.depuis(r).avertissements, isEmpty);
        final r2 = lectureGarage();
        (((r2['projet'] as Map)['plancher']) as Map)['forme'] = {
          'type': 'points',
          'points': [
            [0, 0],
            [10, 0],
            [20, 0],
          ],
        };
        expect(LecturePlan.depuis(r2).avertissements, isEmpty);
      },
    );
  });

  group('porte devenue fenêtre', () {
    LecturePlan avecType() {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'murs.ouverturesContour.0.1.type',
        'niveau': 'incertain',
      });
      return LecturePlan.depuis(r);
    }

    test(
      'l\'allège passe de 0 à 36 po (une fenêtre n\'est pas au plancher)',
      () {
        final l = avecType();
        expect(l.valeurDe('murs.ouverturesContour.0.1.allege'), 0);
        final m = l.modifier('murs.ouverturesContour.0.1.type', 'fenetre');
        expect(m.valeurDe('murs.ouverturesContour.0.1.allege'), 36);
        expect(
          m.projet.murs.ouverturesContour[0]![1].type,
          TypeOuverture.fenetre,
        );
        expect(m.projet.murs.ouverturesContour[0]![1].allege, 36);
      },
    );

    test('une allège déjà donnée est conservée', () {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'murs.ouverturesContour.0.0.type',
        'niveau': 'incertain',
      });
      final l = LecturePlan.depuis(r)
          .modifier('murs.ouverturesContour.0.0.type', 'fenetre');
      expect(l.valeurDe('murs.ouverturesContour.0.0.allege'), 36);
    });

    test('fenêtre devenue porte : le type change, rien d\'autre', () {
      final r = lectureGarage();
      (r['valeurs'] as List).add({
        'chemin': 'murs.ouverturesContour.0.0.type',
        'niveau': 'incertain',
      });
      final l = LecturePlan.depuis(r)
          .modifier('murs.ouverturesContour.0.0.type', 'porte');
      expect(l.projet.murs.ouverturesContour[0]![0].type, TypeOuverture.porte);
    });
  });

  group('structure du plancher : poutres, pieux, étriers', () {
    LecturePlan avecPoutres() {
      final r = lectureGarage();
      (((r['projet'] as Map)['plancher']) as Map)['poutres'] = {
        'nombre': 2,
        'plis': 3,
        'section': '2×8',
        'pieux': 3,
        'retraitPieux': 12,
        'hauteurPatte': 0,
      };
      (r['valeurs'] as List).addAll([
        for (final c in ['nombre', 'plis', 'section', 'pieux', 'retraitPieux'])
          {'chemin': 'plancher.poutres.$c', 'niveau': 'incertain'},
      ]);
      return LecturePlan.depuis(r);
    }

    test('genres, choix et bornes', () {
      expect(genreDuChemin('plancher.poutres.nombre'), GenreValeur.entier);
      expect(genreDuChemin('plancher.poutres.plis'), GenreValeur.entier);
      expect(genreDuChemin('plancher.poutres.pieux'), GenreValeur.entier);
      expect(
        genreDuChemin('plancher.poutres.retraitPieux'),
        GenreValeur.longueur,
      );
      expect(genreDuChemin('plancher.poutres.section'), GenreValeur.choix);
      expect(genreDuChemin('plancher.etriers'), GenreValeur.choix);
      expect(choixDuChemin('plancher.etriers'), [
        'aucun',
        'unBout',
        'deuxBouts',
      ]);
      expect(choixDuChemin('plancher.poutres.section'), [
        '2×6',
        '2×8',
        '2×10',
        '2×12',
      ]);
      expect(bornesDuChemin('plancher.poutres.nombre'), (1.0, 6.0));
      expect(bornesDuChemin('plancher.poutres.plis'), (1.0, 5.0));
      expect(bornesDuChemin('plancher.poutres.pieux'), (2.0, 10.0));
      expect(bornesDuChemin('plancher.poutres.retraitPieux'), (0.0, 120.0));
    });

    test('le garage : étriers à vérifier', () {
      final l = LecturePlan.depuis(lectureGarage());
      expect(l.valeurDe('plancher.etriers'), 'deuxBouts');
      expect(l.aVerifier.map((v) => v.chemin), contains('plancher.etriers'));
    });

    test('corriger un entier : il reste un entier dans le projet', () {
      final l = avecPoutres()
          .modifier('plancher.poutres.pieux', 4.0)
          .modifier('plancher.poutres.nombre', 1)
          .modifier('plancher.poutres.plis', 2);
      expect(l.valeurDe('plancher.poutres.pieux'), 4);
      expect(l.valeurDe('plancher.poutres.pieux'), isA<int>());
      expect(l.projet.plancher.poutres!.pieuxParPoutre, 4);
      expect(l.projet.plancher.poutres!.nombre, 1);
      expect(l.projet.plancher.poutres!.plis, 2);
    });

    test('entier non entier ou hors bornes : refusé', () {
      final l = avecPoutres();
      expect(
        () => l.modifier('plancher.poutres.pieux', 3.5),
        throwsFormatException,
      );
      expect(
        () => l.modifier('plancher.poutres.pieux', 1),
        throwsFormatException,
      );
      expect(
        () => l.modifier('plancher.poutres.nombre', 7),
        throwsFormatException,
      );
      expect(
        () => l.modifier('plancher.poutres.plis', 0),
        throwsFormatException,
      );
      expect(l.valeurDe('plancher.poutres.pieux'), 3);
    });

    test('section des poutres, premier pieu, étriers', () {
      final r = lectureGarage();
      (((r['projet'] as Map)['plancher']) as Map)['poutres'] = {
        'nombre': 2,
        'plis': 3,
        'section': '2×8',
        'pieux': 3,
        'retraitPieux': 12,
        'hauteurPatte': 0,
      };
      (r['valeurs'] as List).addAll([
        {'chemin': 'plancher.poutres.section', 'niveau': 'incertain'},
        {'chemin': 'plancher.poutres.retraitPieux', 'niveau': 'incertain'},
      ]);
      final l = LecturePlan.depuis(r)
          .modifier('plancher.poutres.section', '2×10')
          .modifier('plancher.poutres.retraitPieux', 18)
          .modifier('plancher.etriers', 'unBout');
      expect(l.projet.plancher.poutres!.section.nom, '2×10');
      expect(l.projet.plancher.poutres!.retraitPieux, 18);
      expect(l.projet.plancher.etriers.name, 'unBout');
      expect(
        () => l.modifier('plancher.etriers', 'troisBouts'),
        throwsFormatException,
      );
    });

    test('libellés', () {
      final l = avecPoutres();
      String libelle(String c) => libelleChemin(l.projetJson, c);
      expect(libelle('plancher.etriers'), 'Plancher — étriers de solive');
      expect(
        libelle('plancher.poutres.nombre'),
        'Plancher — nombre de poutres',
      );
      expect(
        libelle('plancher.poutres.plis'),
        'Plancher — plis de chaque poutre',
      );
      expect(
        libelle('plancher.poutres.section'),
        'Plancher — section des poutres',
      );
      expect(libelle('plancher.poutres.pieux'), 'Plancher — pieux par poutre');
      expect(
        libelle('plancher.poutres.retraitPieux'),
        'Plancher — premier pieu (distance du bord)',
      );
    });
  });

  group('nom d\'une ouverture', () {
    test('type et repère, ou type seul', () {
      const f = Ouverture(
        type: TypeOuverture.fenetre,
        nom: ' F1 ',
        largeurCadre: 30,
        hauteurCadre: 40,
        position: 50,
      );
      expect(nomOuverture(f), 'Fenêtre F1');
      const p = Ouverture(
        type: TypeOuverture.porte,
        largeurCadre: 30,
        hauteurCadre: 80,
        position: 50,
      );
      expect(nomOuverture(p), 'Porte');
    });
  });

  group('libellés', () {
    final l = LecturePlan.depuis(lectureGarage());
    String libelle(String c) => libelleChemin(l.projetJson, c);

    test('plancher et murs', () {
      expect(libelle('plancher.forme.longueur'), 'Plancher — longueur');
      expect(libelle('plancher.forme.largeur'), 'Plancher — largeur');
      expect(libelle('plancher.espacement'), 'Plancher — entraxe des solives');
      expect(libelle('plancher.section'), 'Plancher — section des solives');
      expect(libelle('murs.hauteur'), 'Murs — hauteur');
      expect(libelle('murs.params.espacement'), 'Murs — entraxe des montants');
      expect(libelle('murs.params.section'), 'Murs — section des montants');
      expect(libelle('plancher.forme.cotes.2'), 'Plancher — côté 3');
      expect(
        libelle('plancher.forme.angles.0'),
        'Plancher — angle entre les côtés 1 et 2',
      );
      expect(libelle('plancher.forme.points.1.0'), 'Plancher — coin 2 (x)');
      expect(libelle('plancher.forme.points.1.1'), 'Plancher — coin 2 (y)');
    });

    test('portes et fenêtres : mur, repère, champ', () {
      expect(libelle(_f2Largeur), 'Mur 2 — Fenêtre F2 — largeur');
      expect(
        libelle(_f2Allege),
        'Mur 2 — Fenêtre F2 — allège (du plancher au bas du cadre)',
      );
      expect(
        libelle('murs.ouverturesContour.0.1.position'),
        'Mur 1 — Porte P1 — position (du coin extérieur au centre)',
      );
      expect(
        libelle('murs.ouverturesContour.0.1.hauteur'),
        'Mur 1 — Porte P1 — hauteur',
      );
    });

    test('ouverture sans repère : numérotée', () {
      final r = lectureGarage();
      final o =
          ((r['projet'] as Map)['murs'] as Map)['ouverturesContour'] as Map;
      (o['1'] as List)[0]['nom'] = '';
      final sans = LecturePlan.depuis(r);
      expect(
        libelleChemin(sans.projetJson, _f2Largeur),
        'Mur 2 — Fenêtre 1 — largeur',
      );
    });

    test('murs libres', () {
      final r = lectureGarage();
      final murs = (r['projet'] as Map)['murs'] as Map;
      murs['mode'] = 'libres';
      murs['libres'] = [
        {
          'nom': 'Cloison',
          'longueur': 120,
          'hauteur': 96,
          'coinDebut': 0,
          'coinFin': 0,
          'intersections': [],
          'ouvertures': [
            {
              'type': 'porte',
              'nom': '',
              'largeur': 30,
              'hauteur': 80,
              'allege': 0,
              'position': 60,
              'jeuLargeur': 1,
              'jeuHauteur': 1.5,
            },
          ],
        },
      ];
      final libres = LecturePlan.depuis(r);
      expect(
        libelleChemin(libres.projetJson, 'murs.libres.0.longueur'),
        'Cloison — longueur',
      );
      expect(
        libelleChemin(libres.projetJson, 'murs.libres.0.ouvertures.0.largeur'),
        'Cloison — Porte 1 — largeur',
      );
    });
  });
}
