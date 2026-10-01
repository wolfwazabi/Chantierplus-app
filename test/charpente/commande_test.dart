import 'package:construction_app/charpente/commande.dart';
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/panneaux.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:flutter_test/flutter_test.dart';

ResultatPlancher _plancher({
  ModeEtriers etriers = ModeEtriers.deuxBouts,
  FormatPanneau panneau = panneau4x8,
}) => calculerPlancher(
  SpecPlancher(
    forme: Polygone.rectangle(156, 126), // 13' x 10'6"
    etriers: etriers,
    panneau: panneau,
  ),
);

ResultatMurs _murs([ParametresMurs p = const ParametresMurs()]) =>
    calculerMurs([const SpecMur(longueur: 192, hauteur: 97.125)], p);

LigneCommande? _ligne(Commande c, String article) {
  final l = c.lignes.where((e) => e.article == article).toList();
  return l.isEmpty ? null : l.single;
}

void main() {
  group('commande d\'un mur', () {
    test('mur de 16 pi : liste complète', () {
      final c = construireCommande(murs: _murs());
      expect(_ligne(c, '2×4 précoupé 92 5/8 po')!.quantite, 13);
      expect(_ligne(c, "2×4 × 16'")!.quantite, 3); // 1 lisse basse + 2 hautes
      final feuilles = c.lignes.where(
        (l) => l.categorie == CategorieCommande.panneaux,
      );
      expect(feuilles.single.article, '4 × 9 pi');
      expect(feuilles.single.quantite, 4);
      expect(_ligne(c, "Fourrure 3/4 po × 2 1/2 po × 10'")!.quantite, 13);
      final membrane = c.lignes.firstWhere(
        (l) => l.article.startsWith('Membrane'),
      );
      expect(membrane.quantite, 1);
      expect(membrane.unite, '');
      final revetement = c.lignes.firstWhere(
        (l) => l.article.startsWith('Revêtement'),
      );
      expect(revetement.unite, 'pi²');
      expect(revetement.quantite, 143); // 129,5 × 1,1 = 142,45 → 143
    });

    test('catégories dans l\'ordre, avertissement de linteaux', () {
      final c = construireCommande(murs: _murs());
      final cats = c.lignes.map((l) => l.categorie.index).toList();
      expect([...cats]..sort(), cats);
      expect(c.avertissements.any((a) => a.startsWith('Murs : ')), isTrue);
    });

    test('Isobrace comme revêtement des murs', () {
      final c = construireCommande(
        murs: _murs(const ParametresMurs(panneau: panneauIsobraceR4)),
      );
      expect(_ligne(c, 'OSB isolant R-4 (Isobrace) 4 × 9 pi')!.quantite, 4);
    });

    test('linteaux : section propre', () {
      final r = calculerMurs([
        const SpecMur(
          longueur: 192,
          hauteur: 97.125,
          ouvertures: [
            Ouverture(
              type: TypeOuverture.fenetre,
              largeurCadre: 36,
              hauteurCadre: 48,
              position: 96,
            ),
          ],
        ),
      ], const ParametresMurs());
      final c = construireCommande(murs: r);
      expect(_ligne(c, "2×8 × 8'")!.quantite, 1);
      expect(_ligne(c, "2×8 × 8'")!.usage, 'Murs (linteaux)');
    });
  });

  group('commande d\'un plancher', () {
    test('bois, étriers et sous-plancher correspondent au calcul', () {
      final r = _plancher();
      final c = construireCommande(plancher: r, sectionPlancher: section2x10);
      final bois = c.lignes.where((l) => l.categorie == CategorieCommande.bois);
      final total = bois.fold(0.0, (a, l) => a + l.quantite);
      expect(total, r.bois.planches.length);
      for (final l in bois) {
        expect(l.article, startsWith('2×10 × '));
        expect(l.usage, 'Plancher');
      }
      expect(_ligne(c, 'Étrier de solive pour 2×10')!.quantite, r.etriers);
      expect(r.etriers, greaterThan(0));
      expect(
        _ligne(c, 'Sous-plancher 4 × 8 pi')!.quantite,
        r.panneaux.feuillesACommander,
      );
      expect(
        c.avertissements.every((a) => a.startsWith('Plancher : ')),
        isTrue,
      );
    });

    test('sans étriers : pas de ligne de quincaillerie', () {
      final c = construireCommande(
        plancher: _plancher(etriers: ModeEtriers.aucun),
      );
      expect(
        c.lignes.where((l) => l.categorie == CategorieCommande.quincaillerie),
        isEmpty,
      );
    });

    test('feuilles 4 × 9 et Isobrace pour le plancher', () {
      final c = construireCommande(plancher: _plancher(panneau: panneau4x9));
      expect(
        c.lignes.any((l) => l.article == 'Sous-plancher 4 × 9 pi'),
        isTrue,
      );
    });
  });

  group('plancher + murs', () {
    test('même section : les lignes de bois sont fusionnées', () {
      final c = construireCommande(
        plancher: _plancher(),
        sectionPlancher: section2x4,
        murs: _murs(),
      );
      // Aucun article en double.
      final cles = c.lignes
          .map((l) => '${l.categorie.name}|${l.article}|${l.unite}')
          .toList();
      expect(cles.toSet().length, cles.length);
      // Une lisse de 16' des murs et les rives/solives de 16' du plancher, s'il
      // y en a, sont sur la même ligne.
      final seize = _ligne(c, "2×4 × 16'")!;
      expect(seize.usage, contains('Murs'));
      final r = _plancher();
      final dePlancher = r.bois.parLongueur[192] ?? 0;
      expect(seize.quantite, dePlancher + 3);
      if (dePlancher > 0) {
        expect(seize.usage, 'Plancher, Murs');
      }
    });

    test('avertissements des deux calculs, préfixés', () {
      final c = construireCommande(plancher: _plancher(), murs: _murs());
      expect(c.avertissements.any((a) => a.startsWith('Plancher : ')), isTrue);
      expect(c.avertissements.any((a) => a.startsWith('Murs : ')), isTrue);
    });

    test('rien à commander : liste vide', () {
      final c = construireCommande();
      expect(c.estVide, isTrue);
      expect(c.piecesDeBois, 0);
    });
  });

  group('texte et JSON', () {
    test('texte pour le fournisseur', () {
      final c = construireCommande(murs: _murs());
      final t = c.enTexte(titre: 'Maison Tremblay');
      expect(t, startsWith('Maison Tremblay'));
      expect(t, contains("BOIS D'ŒUVRE"));
      expect(t, contains('13 × 2×4 précoupé 92 5/8 po'));
      expect(t, contains("3 × 2×4 × 16'"));
      expect(t, contains('1 × Membrane (rouleau de 900 pi²)'));
      expect(t.endsWith('\n'), isFalse);
    });

    test('JSON : aller-retour', () {
      final c = construireCommande(plancher: _plancher(), murs: _murs());
      final relu = [
        for (final l in c.lignes) LigneCommande.fromJson(l.toJson()),
      ];
      expect(relu.length, c.lignes.length);
      for (var i = 0; i < relu.length; i++) {
        expect(relu[i].article, c.lignes[i].article);
        expect(relu[i].quantite, c.lignes[i].quantite);
        expect(relu[i].unite, c.lignes[i].unite);
        expect(relu[i].usage, c.lignes[i].usage);
        expect(relu[i].categorie, c.lignes[i].categorie);
      }
    });

    test('JSON : lignes invalides refusées', () {
      for (final j in <Object?>[
        null,
        'x',
        {'categorie': 'bois', 'article': '', 'quantite': 1},
        {'categorie': 'bois', 'article': 'a', 'quantite': 0},
        {'categorie': 'bois', 'article': 'a', 'quantite': -2},
        {'categorie': 'bois', 'article': 'a', 'quantite': 'beaucoup'},
        {'categorie': 'autre', 'article': 'a', 'quantite': 1},
        {'categorie': 'bois', 'article': 'a' * 201, 'quantite': 1},
        {'categorie': 'bois', 'article': 'a', 'quantite': double.nan},
        {'categorie': 'bois', 'article': 'a', 'quantite': 1e9},
      ]) {
        expect(() => LigneCommande.fromJson(j), throwsFormatException);
      }
    });

    test(
      'fusion : quantités additionnées, usages réunis, manuelles à part',
      () {
        final l = fusionnerLignes(const [
          LigneCommande(
            categorie: CategorieCommande.bois,
            article: "2×4 × 8'",
            quantite: 3,
            usage: 'Plancher',
          ),
          LigneCommande(
            categorie: CategorieCommande.quincaillerie,
            article: 'Clous',
            quantite: 1,
            manuelle: true,
          ),
          LigneCommande(
            categorie: CategorieCommande.bois,
            article: "2×4 × 8'",
            quantite: 2,
            usage: 'Murs',
          ),
          LigneCommande(
            categorie: CategorieCommande.bois,
            article: "2×4 × 8'",
            quantite: 1,
            usage: 'Murs',
            manuelle: true,
          ),
        ]);
        expect(l, hasLength(3));
        expect(l[0].quantite, 5);
        expect(l[0].usage, 'Plancher, Murs');
        expect(l[1].manuelle, isTrue); // bois manuel, avant la quincaillerie
        expect(l[2].article, 'Clous');
      },
    );
  });
}
