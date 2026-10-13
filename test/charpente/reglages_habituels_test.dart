import 'dart:convert';

import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/reglages_habituels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Projet de l'entrepreneur : ses habitudes (rives doubles, entremises auto alternées, poutres
/// sur pieux avec pattes de 16 po, murs 2×6 précoupés…) et les mesures d'un chantier.
ProjetCharpente _projet({
  FormePlancher forme = const FormeRectangle(180, 168),
  int? coteMaison = 2,
  double hauteur = 97.125,
  String nom = 'Dupéré',
}) => ProjetCharpente(
  nom: nom,
  plancher: ParametresPlancher(
    forme: forme,
    coteMaison: coteMaison,
    section: section2x8,
    espacement: 16,
    riveDouble: true,
    solivesDoublesAuxCotes: true,
    etriers: ModeEtriers.unBout,
    entremisesAuto: true,
    entremisesEspacement: 96,
    entremisesAlternees: true,
    clousParEtrier: 8,
    poutres: const ParametresPoutres(
      nombre: 2,
      plis: 3,
      pieuxParPoutre: 3,
      hauteurPatte: 16,
    ),
  ),
  mursActifs: true,
  murs: ParametresMursProjet(
    hauteur: hauteur,
    ouverturesContour: const {
      0: [
        Ouverture(
          type: TypeOuverture.fenetre,
          largeurCadre: 36,
          hauteurCadre: 48,
          allege: 36,
          position: 60,
        ),
      ],
    },
    params: const ParametresMurs(section: section2x6, plisLinteau: 3),
  ),
);

String _j(ProjetCharpente p) => jsonEncode(p.toJson());

void main() {
  final habitudes = ReglagesHabituels.vides
      .avecPlancherDe(_projet())
      .avecMursDe(_projet());

  test('aucun réglage : le projet reste tel quel', () {
    final p = _projet();
    expect(ReglagesHabituels.vides.estVide, isTrue);
    expect(_j(ReglagesHabituels.vides.appliquer(p)), _j(p));
    expect(ReglagesHabituels.vides.pourLecturePlan(), isNull);
    expect(ReglagesHabituels.vides.plancherSuivi(p), isFalse);
  });

  test('un nouveau calcul prend les choix, pas les mesures', () {
    final neuf = habitudes.appliquer(const ProjetCharpente());
    final pl = neuf.plancher;
    expect(pl.section, section2x8);
    expect(pl.riveDouble, isTrue);
    expect(pl.solivesDoublesAuxCotes, isTrue);
    expect(pl.etriers, ModeEtriers.unBout);
    expect(pl.entremisesAuto, isTrue);
    expect(pl.entremisesEspacement, 96);
    expect(pl.entremisesAlternees, isTrue);
    expect(pl.clousParEtrier, 8);
    expect(pl.poutres!.hauteurPatte, 16);
    expect(neuf.murs.params.section, section2x6);
    expect(neuf.murs.params.plisLinteau, 3);
    // Les mesures du chantier d'où viennent les réglages ne suivent pas.
    const defaut = ProjetCharpente();
    expect(pl.forme.toJson(), defaut.plancher.forme.toJson());
    expect(pl.coteMaison, isNull);
    expect(neuf.nom, '');
    expect(neuf.murs.hauteur, defaut.murs.hauteur);
    expect(neuf.murs.ouverturesContour, isEmpty);
    expect(neuf.mursActifs, defaut.mursActifs);
  });

  test('appliquer garde la forme, le côté de la maison, la hauteur et les ouvertures', () {
    final autre = _projet(
      forme: const FormeRectangle(144, 120),
      coteMaison: 1,
      hauteur: 84,
      nom: 'Trudel',
    );
    final r = const ProjetCharpente();
    final remis = ReglagesHabituels.vides
        .avecPlancherDe(r)
        .avecMursDe(r)
        .appliquer(autre);
    expect(remis.nom, 'Trudel');
    expect(remis.plancher.forme.toJson(), autre.plancher.forme.toJson());
    expect(remis.plancher.coteMaison, 1);
    expect(remis.murs.hauteur, 84);
    expect(remis.murs.ouverturesContour[0], hasLength(1));
    // Et les choix redeviennent ceux d'un projet par défaut.
    expect(remis.plancher.riveDouble, isFalse);
    expect(remis.plancher.poutres, isNull);
    expect(remis.murs.params.section, section2x4);
  });

  test('plancher seul ou murs seuls', () {
    final base = const ProjetCharpente();
    final plancherSeul = habitudes.appliquer(base, auxMurs: false);
    expect(plancherSeul.plancher.riveDouble, isTrue);
    expect(plancherSeul.murs.params.section, section2x4);
    final mursSeuls = habitudes.appliquer(base, auPlancher: false);
    expect(mursSeuls.plancher.riveDouble, isFalse);
    expect(mursSeuls.murs.params.section, section2x6);

    final r = ReglagesHabituels.vides.avecPlancherDe(_projet());
    expect(r.murs, isNull);
    expect(r.appliquer(base).murs.params.section, section2x4);
  });

  test('suivi : un réglage changé est vu, une mesure changée non', () {
    final p = _projet();
    expect(habitudes.plancherSuivi(p), isTrue);
    expect(habitudes.mursSuivis(p), isTrue);
    // Autre chantier, mêmes habitudes.
    final ailleurs = _projet(forme: const FormeRectangle(120, 96), hauteur: 80);
    expect(habitudes.plancherSuivi(ailleurs), isTrue);
    expect(habitudes.mursSuivis(ailleurs), isTrue);
    // Un réglage du plancher change.
    final change = p.copieAvec(
      plancher: p.plancher.copieAvec(entremisesAlternees: false),
    );
    expect(habitudes.plancherSuivi(change), isFalse);
    expect(habitudes.mursSuivis(change), isTrue);
  });

  test('gardés puis relus (JSON) : identiques', () {
    final texte = jsonEncode(habitudes.toJson());
    final relus = ReglagesHabituels.depuis(jsonDecode(texte));
    expect(jsonEncode(relus.toJson()), texte);
    expect(relus.plancherSuivi(_projet()), isTrue);
    expect(relus.mursSuivis(_projet()), isTrue);
  });

  test('illisibles ou abîmés : écartés, jamais d\'erreur', () {
    for (final j in [
      null,
      'x',
      3,
      <String, dynamic>{},
      {'v': 2},
    ]) {
      expect(ReglagesHabituels.depuis(j).estVide, isTrue, reason: '$j');
    }
    final bon = habitudes.toJson();
    // Une partie abîmée est écartée ; l'autre reste.
    final plancherAbime = jsonDecode(jsonEncode(bon)) as Map<String, dynamic>;
    (plancherAbime['plancher'] as Map)['section'] = '2×99';
    final r1 = ReglagesHabituels.depuis(plancherAbime);
    expect(r1.plancher, isNull);
    expect(r1.murs, isNotNull);
    final mursAbimes = jsonDecode(jsonEncode(bon)) as Map<String, dynamic>;
    (mursAbimes['murs'] as Map)['params'] = 'rien';
    final r2 = ReglagesHabituels.depuis(mursAbimes);
    expect(r2.plancher, isNotNull);
    expect(r2.murs, isNull);
    // Une clé manquante : la partie est incomplète, donc écartée.
    final incomplet = jsonDecode(jsonEncode(bon)) as Map<String, dynamic>;
    (incomplet['plancher'] as Map).remove('coupesSeparees');
    expect(ReglagesHabituels.depuis(incomplet).plancher, isNull);
    // Les mesures glissées dans les réglages ne sont jamais reprises.
    final avecForme = jsonDecode(jsonEncode(bon)) as Map<String, dynamic>;
    (avecForme['plancher'] as Map)['forme'] = {
      'type': 'rectangle',
      'longueur': 999,
      'largeur': 999,
    };
    (avecForme['plancher'] as Map)['coteMaison'] = 3;
    final neuf = ReglagesHabituels.depuis(avecForme)
        .appliquer(const ProjetCharpente());
    expect(
      neuf.plancher.forme.toJson(),
      const ProjetCharpente().plancher.forme.toJson(),
    );
    expect(neuf.plancher.coteMaison, isNull);
  });

  test('pour la lecture d\'un plan : les choix, sans aucune mesure', () {
    final j = habitudes.pourLecturePlan()!;
    final texte = jsonEncode(j);
    expect(
      (j['plancher'] as Map).keys.toSet(),
      ReglagesHabituels.clesPlancher.toSet(),
    );
    expect((j['murs'] as Map).keys, ['params']);
    for (final mesure in [
      '"forme"',
      '"coteMaison"',
      '"hauteur"',
      '"ouverturesContour"',
      'Dupéré',
    ]) {
      expect(texte, isNot(contains(mesure)), reason: mesure);
    }
  });

  test('le calcul d\'un projet issu des réglages fonctionne', () {
    final r = calculerProjet(habitudes.appliquer(const ProjetCharpente()));
    expect(r.erreurPlancher, isNull);
    expect(r.plancher!.poutres, isNotNull);
  });
}
