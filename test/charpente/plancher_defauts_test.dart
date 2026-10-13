// Plancher de 14 × 12 pi avec une rangée d'entremises : les réglages par défaut suivent la façon
// de commander de l'entrepreneur (pas d'étrier sur les solives de bordure, qui sont à l'extérieur
// du plancher ; entremises dans leurs propres planches, jamais dans les bouts de planches des
// rives). Voir docs/exemples_reels_plancher.md.
import 'dart:convert';

import 'package:construction_app/charpente/mur.dart' show section2x8;
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:flutter_test/flutter_test.dart';

ProjetCharpente _projet({
  ModeEtriers etriers = ModeEtriers.deuxBouts,
  bool? etriersBordures,
  bool? coupesSeparees,
  bool bordureDouble = true,
  int rangees = 1,
}) => ProjetCharpente(
  plancher: ParametresPlancher(
    forme: const FormeRectangle(168, 144), // 14 pi × 12 pi
    section: section2x8,
    solivesDoublesAuxCotes: bordureDouble,
    etriers: etriers,
    rangeesEntremises: rangees,
    etriersBordures:
        etriersBordures ?? const ParametresPlancher().etriersBordures,
    coupesSeparees: coupesSeparees ?? const ParametresPlancher().coupesSeparees,
  ),
);

Map<String, double> _bois(ProjetCharpente p) {
  final texte = calculerProjet(p).commande.enTexte();
  final m = <String, double>{};
  for (final l in texte.split('\n')) {
    final r = RegExp(r"^(\d+) × (.+)$").firstMatch(l);
    if (r != null) m[r[2]!] = double.parse(r[1]!);
  }
  return m;
}

void main() {
  test('les nouveaux projets partent avec les réglages de l\'entrepreneur', () {
    const p = ParametresPlancher();
    expect(p.etriersBordures, isFalse);
    expect(p.coupesSeparees, isTrue);
  });

  group('14 × 12 pi, une rangée d\'entremises', () {
    final resultat = calculerProjet(_projet()).plancher!;

    test('14 morceaux de solive dont 4 de bordure (2 doubles)', () {
      expect(resultat.nombreSolives, 14);
      expect(resultat.solives.where((s) => s.bordure), hasLength(4));
      expect(resultat.solives.where((s) => !s.bordure), hasLength(10));
    });

    test('étriers : seulement les 10 solives intérieures (2 bouts : 20)', () {
      expect(resultat.etriers, 20);
      expect(_bois(_projet())['Étrier de solive pour 2×8'], 20);
    });

    test('un bout : 10 étriers', () {
      expect(
        calculerProjet(_projet(etriers: ModeEtriers.unBout)).plancher!.etriers,
        10,
      );
    });

    test('sans solives de bordure doublées : les 2 solives de bordure n\'ont pas d\'étrier non plus', () {
      final r = calculerProjet(_projet(bordureDouble: false)).plancher!;
      expect(r.nombreSolives, 12);
      expect(r.solives.where((s) => s.bordure), hasLength(2));
      expect(r.etriers, 20);
    });

    test('entremises : 11 blocs dans UNE planche de 14 pi, rien dans les planches des rives', () {
      final blocs = resultat.bois.planches
          .where((pl) => pl.pieces.any((x) => x.etiquette == 'entremise'))
          .toList();
      expect(blocs, hasLength(1));
      expect(blocs.single.stock, 168);
      expect(
        blocs.single.pieces.every((x) => x.etiquette == 'entremise'),
        isTrue,
      );
      expect(blocs.single.pieces, hasLength(11));
      for (final pl in resultat.bois.planches.where(
        (pl) => pl.pieces.any((x) => x.etiquette == 'solive de rive'),
      )) {
        expect(
          pl.stock,
          168,
          reason: 'les rives de 14 pi restent dans des planches de 14 pi',
        );
        expect(pl.pieces, hasLength(1));
      }
    });

    test('la commande : 14 solives de 12 pi, 3 planches de 14 pi, aucune planche de 20 pi', () {
      final b = _bois(_projet());
      expect(b["2×8 × 12'"], 14);
      expect(b["2×8 × 14'"], 3, reason: '2 rives + 1 planche d\'entremises');
      expect(b.keys.where((k) => k.contains("20'")), isEmpty);
    });
  });

  group('anciens réglages (toujours possibles)', () {
    test('étriers sur toutes les solives, bordures comprises : 28', () {
      final r = calculerProjet(_projet(etriersBordures: true)).plancher!;
      expect(r.etriers, 28);
    });

    test('coupes groupées : les blocs prennent le reste des planches des rives (2 planches de 20 pi)', () {
      final b = _bois(_projet(coupesSeparees: false));
      expect(b["2×8 × 20'"], 2);
    });
  });

  test('aucune rangée : aucune entremise, mêmes étriers', () {
    final r = calculerProjet(_projet(rangees: 0)).plancher!;
    expect(r.entremises, isEmpty);
    expect(r.etriers, 20);
  });

  test(
    'le projet enregistré garde ces réglages d\'un enregistrement à l\'autre',
    () {
      final j = jsonDecode(jsonEncode(_projet().toJson())) as Map;
      expect((j['plancher'] as Map)['etriersBordures'], isFalse);
      expect((j['plancher'] as Map)['coupesSeparees'], isTrue);
      final relu = ProjetCharpente.fromJson(j).plancher;
      expect(relu.etriersBordures, isFalse);
      expect(relu.coupesSeparees, isTrue);
    },
  );
}
