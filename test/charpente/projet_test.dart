import 'dart:convert';
import 'dart:io';

import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/panneaux.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/scene.dart' show Calque;
import 'package:flutter_test/flutter_test.dart';

const _fenetre = Ouverture(
  type: TypeOuverture.fenetre,
  nom: 'Salon',
  largeurCadre: 36,
  hauteurCadre: 48,
  allege: 36,
  position: 100,
  jeuLargeur: 1,
  jeuHauteur: 1.5,
);
const _porte = Ouverture(
  type: TypeOuverture.porte,
  largeurCadre: 36,
  hauteurCadre: 80,
  position: 200,
);

const _porteCloison = Ouverture(
  type: TypeOuverture.porte,
  largeurCadre: 36,
  hauteurCadre: 80,
  position: 110,
);

/// Un projet qui utilise toutes les options.
ProjetCharpente _complet() => ProjetCharpente(
  nom: 'Maison Tremblay',
  plancher: ParametresPlancher(
    forme: FormeCotesAngles(const [240, 180, 100, 160], const [90, 110, 120]),
    espacement: 19.2,
    angleSolivesDeg: 30,
    section: section2x8,
    solivesDoublesAuxCotes: true,
    riveDouble: true,
    etriers: ModeEtriers.unBout,
    rangeesEntremises: 2,
    panneau: panneau4x9,
    decalageMin: 16,
    margePanneauxPourcent: 10,
    longueursPlanches: const [96, 120, 144],
  ),
  mursActifs: true,
  murs: ParametresMursProjet(
    mode: ModeMurs.libres,
    hauteur: 109.125,
    ouverturesContour: const {
      0: [_fenetre, _porte],
      2: [_fenetre],
    },
    libres: const [
      SpecMur(
        nom: 'Cloison',
        longueur: 144,
        hauteur: 97.125,
        ouvertures: [_porteCloison],
        montantsCoinDebut: 1,
        montantsCoinFin: 2,
        intersections: [30, 60],
      ),
    ],
    params: ParametresMurs(
      espacement: 12,
      section: section2x6,
      lissesHautes: 1,
      jacksParCote: 2,
      linteau: section2x10,
      plisLinteau: 3,
      plisAppui: 2,
      precoupes: false,
      panneau: panneauIsobraceR4,
      debordPlancher: 1,
      fourrureEntraxe: 24,
      fourrureEpaisseur: 1,
      fourrureLargeur: 3,
      revetementEpaisseur: 1,
      margeMembranePct: 15,
      margeRevetementPct: 12,
      aireRouleauPi2: 1000,
      margeFeuillesPct: 5,
    ),
  ),
);

void main() {
  group('JSON', () {
    test('projet par défaut : aller-retour', () {
      const p = ProjetCharpente();
      final j = jsonDecode(jsonEncode(p.toJson()));
      final q = ProjetCharpente.fromJson(j);
      expect(jsonEncode(q.toJson()), jsonEncode(p.toJson()));
    });

    test('projet complet : aller-retour exact', () {
      final p = _complet();
      final j = jsonDecode(jsonEncode(p.toJson()));
      final q = ProjetCharpente.fromJson(j);
      expect(jsonEncode(q.toJson()), jsonEncode(p.toJson()));
      expect(q.nom, 'Maison Tremblay');
      expect(q.plancher.angleSolivesDeg, 30);
      expect(q.plancher.panneau.id, '4x9');
      expect(q.murs.params.panneau.id, 'isobrace_r4');
      expect(q.murs.ouverturesContour[0], hasLength(2));
      expect(q.murs.ouverturesContour[0]!.first.nom, 'Salon');
      expect(q.murs.libres.single.intersections, [30, 60]);
      // Même résultat de calcul.
      final a = calculerProjet(p);
      final b = calculerProjet(q);
      expect(b.commande.enTexte(), a.commande.enTexte());
    });

    test('les trois formes se relisent', () {
      for (final f in <FormePlancher>[
        const FormeRectangle(100, 80),
        const FormeCotesAngles([100, 80], [90]),
        const FormePoints([Pt(0, 0), Pt(100, 0), Pt(100, 50), Pt(0, 80)]),
      ]) {
        final g = FormePlancher.fromJson(jsonDecode(jsonEncode(f.toJson())));
        expect(g.runtimeType, f.runtimeType);
        expect(g.construire().aire, closeTo(f.construire().aire, 1e-9));
      }
    });

    test('contenu mal formé : refusé', () {
      final bon = jsonDecode(
        jsonEncode(const ProjetCharpente().toJson()),
      ) as Map<String, dynamic>;
      Map<String, dynamic> copie() =>
          jsonDecode(jsonEncode(bon)) as Map<String, dynamic>;

      expect(() => ProjetCharpente.fromJson(null), throwsFormatException);
      expect(() => ProjetCharpente.fromJson('x'), throwsFormatException);
      expect(() => ProjetCharpente.fromJson({'v': 2}), throwsFormatException);

      var j = copie()..['nom'] = 'x' * 201;
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['plancher'] as Map)['section'] = '4×12';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['plancher'] as Map)['espacement'] = 'seize';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['plancher'] as Map)['espacement'] = double.nan;
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['plancher'] as Map)['panneau'] = 'inconnu';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['plancher'] as Map)['etriers'] = 'partout';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      ((j['plancher'] as Map)['forme'] as Map)['type'] = 'etoile';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['murs'] as Map)['mode'] = 'volant';
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['murs'] as Map)['libres'] = List.generate(41, (_) => {});
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['murs'] as Map)['ouverturesContour'] = {'99': []};
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);

      j = copie();
      (j['murs'] as Map)['ouverturesContour'] = {
        '0': [
          {'type': 'tunnel'},
        ],
      };
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
    });

    test('listes énormes ou nombres hors limites : refusés', () {
      final j = jsonDecode(
        jsonEncode(const ProjetCharpente().toJson()),
      ) as Map<String, dynamic>;
      ((j['plancher'] as Map)['forme'] as Map)
        ..['type'] = 'points'
        ..['points'] = List.generate(25, (i) => [i.toDouble(), 0.0]);
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
      ((j['plancher'] as Map)['forme'] as Map)
        ..['type'] = 'rectangle'
        ..['longueur'] = 1e9
        ..['largeur'] = 100;
      expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
    });
  });

  group('calcul du projet', () {
    test('projet par défaut : plancher 13 pi × 10 pi 6 po', () {
      final r = calculerProjet(const ProjetCharpente());
      expect(r.aDesErreurs, isFalse);
      expect(r.plancher, isNotNull);
      expect(r.murs, isNull);
      expect(r.contour!.aire, closeTo(156 * 126, 1e-9));
      expect(r.scene.estVide, isFalse);
      expect(r.commande.estVide, isFalse);
      expect(
        r.commande.lignes.any((l) => l.article.startsWith('2×10 × ')),
        isTrue,
      );
    });

    test('murs du contour avec ouvertures : un mur par côté', () {
      final p = const ProjetCharpente().copieAvec(
        mursActifs: true,
        murs: const ParametresMursProjet(
          ouverturesContour: {
            0: [_fenetre],
          },
        ),
      );
      final r = calculerProjet(p);
      expect(r.erreurMurs, isNull);
      expect(r.murs!.murs, hasLength(4));
      expect(r.murs!.murs.first.spec.ouvertures, hasLength(1));
      expect(r.murs!.murs.first.spec.cote, 0);
      // Les murs sont posés sur le plancher : une seule scène.
      expect(r.scene.parCalque.keys.length, greaterThanOrEqualTo(7));
      // Et la commande contient plancher + murs.
      final t = r.commande.enTexte();
      expect(t, contains('Sous-plancher'));
      expect(t, contains('Membrane'));
    });

    test('murs libres sans plancher', () {
      final p = const ProjetCharpente().copieAvec(
        plancherActif: false,
        mursActifs: true,
        murs: const ParametresMursProjet(
          mode: ModeMurs.libres,
          libres: [SpecMur(longueur: 192, hauteur: 97.125)],
        ),
      );
      final r = calculerProjet(p);
      expect(r.plancher, isNull);
      expect(r.murs, isNotNull);
      expect(r.contour, isNull);
      expect(r.scene.parCalque[Calque.sousPlancher], isNull);
      expect(
        r.commande.lignes.any((l) => l.article.contains('précoupé')),
        isTrue,
      );
    });

    test('erreur de forme : rapportée, pas lancée', () {
      final p = const ProjetCharpente().copieAvec(
        plancher: const ParametresPlancher(
          forme: FormeCotesAngles([100, 100, 100], [10, 10]),
        ),
        mursActifs: true,
      );
      final r = calculerProjet(p);
      expect(r.erreurPlancher, isNotNull);
      expect(r.plancher, isNull);
      expect(r.erreurMurs, contains('forme de plancher'));
      expect(r.scene.estVide, isTrue);
    });

    test('erreur d\'ouverture : rapportée avec le plancher intact', () {
      final p = const ProjetCharpente().copieAvec(
        mursActifs: true,
        murs: const ParametresMursProjet(
          ouverturesContour: {
            0: [
              Ouverture(
                type: TypeOuverture.fenetre,
                largeurCadre: 36,
                hauteurCadre: 48,
                position: 5,
              ),
            ],
          },
        ),
      );
      final r = calculerProjet(p);
      expect(r.erreurMurs, contains('trop près'));
      expect(r.erreurPlancher, isNull);
      expect(r.plancher, isNotNull);
      expect(r.scene.estVide, isFalse); // le plancher s'affiche quand même
    });

    test('rien d\'actif : scène et commande vides', () {
      final r = calculerProjet(
        const ProjetCharpente(plancherActif: false, mursActifs: false),
      );
      expect(r.scene.estVide, isTrue);
      expect(r.commande.estVide, isTrue);
      expect(r.aDesErreurs, isFalse);
    });

    test('projet complet (toutes options) : calcule sans erreur', () {
      final r = calculerProjet(_complet());
      expect(r.erreurPlancher, isNull);
      expect(r.erreurMurs, isNull);
      expect(r.commande.estVide, isFalse);
      expect(r.scene.solides, isNotEmpty);
      // Le mur libre « Cloison » est dans la scène, avec sa fiche.
      expect(
        r.scene.infos.values.any(
          (i) => i.lignes.any((l) => l == 'Mur : Cloison'),
        ),
        isTrue,
      );
    });

    test('métrique : fiches en mètres', () {
      final r = calculerProjet(const ProjetCharpente(), metrique: true);
      final fiche = r.scene.infos.entries
          .firstWhere((e) => e.key.startsWith('j'))
          .value;
      expect(fiche.lignes.join(), isNot(contains("'")));
    });
  });

  group(
    'conformité avec l’assistant (functions/src/assistant_charpente.js)',
    () {
      test('le projet par défaut de l’application = celui de l’assistant', () {
        final attendu = jsonDecode(
          File('test/charpente/projet_defaut.json').readAsStringSync(),
        );
        final reel = jsonDecode(jsonEncode(const ProjetCharpente().toJson()));
        expect(reel, attendu);
      });

      test(
        'un projet produit par l’assistant est relu et calculé sans erreur',
        () {
          final j = jsonDecode(
            File('test/charpente/projet_assistant.json').readAsStringSync(),
          );
          final p = ProjetCharpente.fromJson(j);
          expect(p.nom, 'Garage Tremblay');
          expect(p.plancher.riveDouble, isTrue);
          expect(p.murs.params.panneau.id, 'isobrace_r4');
          expect(p.murs.ouverturesContour[0]!.single.nom, 'Salon');
          expect(p.murs.ouverturesContour[1]!.single.type, TypeOuverture.porte);
          final r = calculerProjet(p);
          expect(r.erreurPlancher, isNull);
          expect(r.erreurMurs, isNull);
          expect(r.murs!.murs, hasLength(4));
          expect(
            r.commande.lignes.any((l) => l.article.contains('Isobrace')),
            isTrue,
          );
        },
      );
    },
  );
}
