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
  mainPlancherReel();
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

// Réglages ajoutés pour les planchers sur pieux vissés (rives par côté, étriers,
// entremises automatiques, coupes séparées, poutres, clous). Un projet enregistré
// avant leur ajout doit se relire et se calculer comme avant.
void mainPlancherReel() {
  const poutres = ParametresPoutres(
    nombre: 2,
    plis: 3,
    pieuxParPoutre: 3,
    hauteurPatte: 16,
  );
  const plancherReel = ParametresPlancher(
    forme: FormeRectangle(180, 168),
    section: section2x8,
    solivesDoublesAuxCotes: true,
    riveDouble: true,
    coteMaison: 2,
    etriers: ModeEtriers.unBout,
    etriersBordures: false,
    entremisesAuto: true,
    entremisesEspacement: 108,
    entremisesAlternees: true,
    coupesSeparees: true,
    poutres: poutres,
    clousParEtrier: 12,
    clousParBoite: 100,
    margeClous: 10,
  );

  group('réglages du plancher sur pieux vissés', () {
    test('aller-retour JSON : tout est conservé', () {
      final lu = ProjetCharpente.fromJson(
        jsonDecode(
          jsonEncode(const ProjetCharpente(plancher: plancherReel).toJson()),
        ),
      );
      final p = lu.plancher;
      expect(p.coteMaison, 2);
      expect(p.etriersBordures, isFalse);
      expect(p.entremisesAuto, isTrue);
      expect(p.entremisesEspacement, 108);
      expect(p.entremisesAlternees, isTrue);
      expect(p.coupesSeparees, isTrue);
      expect(p.clousParEtrier, 12);
      expect(p.clousParBoite, 100);
      expect(p.margeClous, 10);
      expect(p.poutres!.nombre, 2);
      expect(p.poutres!.plis, 3);
      expect(p.poutres!.section.nom, '2×8');
      expect(p.poutres!.pieuxParPoutre, 3);
      expect(p.poutres!.hauteurPatte, 16);
      expect(lu.toJson(), const ProjetCharpente(plancher: plancherReel).toJson());
    });

    test('sans poutres : null dans le JSON et à la relecture', () {
      final j = const ProjetCharpente().toJson();
      expect((j['plancher'] as Map)['poutres'], isNull);
      expect((j['plancher'] as Map)['coteMaison'], isNull);
      expect(ProjetCharpente.fromJson(jsonDecode(jsonEncode(j))).plancher.poutres, isNull);
    });

    test('un projet enregistré avant ces réglages se relit avec les valeurs d\'avant', () {
      final j = jsonDecode(jsonEncode(const ProjetCharpente().toJson())) as Map;
      for (final cle in [
        'coteMaison',
        'etriersBordures',
        'entremisesAuto',
        'entremisesEspacement',
        'entremisesAlternees',
        'coupesSeparees',
        'poutres',
        'clousParEtrier',
        'clousParBoite',
        'margeClous',
      ]) {
        (j['plancher'] as Map).remove(cle);
      }
      final p = ProjetCharpente.fromJson(j).plancher;
      expect(p.coteMaison, isNull);
      expect(p.etriersBordures, isTrue);
      expect(p.entremisesAuto, isFalse);
      expect(p.coupesSeparees, isFalse);
      expect(p.poutres, isNull);
      expect(p.clousParEtrier, 10);
      expect(p.clousParBoite, 120);
    });

    test('même calcul avec ou sans les nouveaux champs (ancien projet)', () {
      final ancien = const ProjetCharpente(
        plancher: ParametresPlancher(
          forme: FormeRectangle(180, 168),
          riveDouble: true,
          rangeesEntremises: 1,
        ),
      );
      final j = jsonDecode(jsonEncode(ancien.toJson())) as Map;
      (j['plancher'] as Map)
        ..remove('coteMaison')
        ..remove('poutres')
        ..remove('coupesSeparees');
      final a = calculerProjet(ancien).commande.enTexte();
      final b = calculerProjet(ProjetCharpente.fromJson(j)).commande.enTexte();
      expect(b, a);
    });

    test('valeurs invalides refusées', () {
      Map base() =>
          jsonDecode(jsonEncode(const ProjetCharpente(plancher: plancherReel).toJson()))
              as Map;
      void refuse(void Function(Map plancher) change) {
        final j = base();
        change(j['plancher'] as Map);
        expect(() => ProjetCharpente.fromJson(j), throwsFormatException);
      }

      refuse((p) => p['coteMaison'] = -1);
      refuse((p) => p['coteMaison'] = 'haut');
      refuse((p) => p['etriersBordures'] = 'oui');
      refuse((p) => p['entremisesEspacement'] = 5);
      refuse((p) => p['clousParEtrier'] = 0);
      refuse((p) => p['clousParBoite'] = 'x');
      refuse((p) => p['margeClous'] = 500);
      refuse((p) => (p['poutres'] as Map)['nombre'] = 99);
      refuse((p) => (p['poutres'] as Map)['plis'] = 0);
      refuse((p) => (p['poutres'] as Map)['pieux'] = 1);
      refuse((p) => (p['poutres'] as Map)['section'] = '2×99');
      refuse((p) => (p['poutres'] as Map)['hauteurPatte'] = -2);
      refuse((p) => p['poutres'] = 'beaucoup');
    });

    test('calcul du projet : poutres, pattes, clous et rives dans la commande', () {
      final r = calculerProjet(const ProjetCharpente(plancher: plancherReel));
      expect(r.erreurPlancher, isNull);
      final lignes = {for (final l in r.commande.lignes) l.article: l.quantite};
      expect(lignes["2×8 × 16' traité"], 6);
      expect(lignes["6×6 × 8' traité"], 1);
      expect(lignes['Étrier de solive pour 2×8'], 11);
      // 11 étriers × 12 clous + 10 % = 145,2 clous : 2 boîtes de 100.
      expect(
        lignes.entries.firstWhere((e) => e.key.startsWith('Clous d')).value,
        2,
      );
      expect(r.plancher!.rives, hasLength(3));
    });

    test('un côté de maison hors du contour est refusé au calcul, sans exception', () {
      final r = calculerProjet(
        const ProjetCharpente(
          plancher: ParametresPlancher(forme: FormeRectangle(180, 168), coteMaison: 9),
        ),
      );
      expect(r.plancher, isNull);
      expect(r.erreurPlancher, contains('Côté de la maison'));
    });
  });
}
