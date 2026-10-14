// Marches en composite : marches en cadre, contremarches en fascia avec un 2x de backing,
// limons à l'entraxe du fabricant, écarts du fabricant (côte à côte et au bout contre le cadre),
// fixation selon le guide : attaches cachées au centre seulement si le fabricant les permet sur
// les marches (Trex), sinon tout vissé en surface (avec bouchons, ou vis de la couleur).
import 'package:construction_app/charpente/composite.dart';
import 'package:construction_app/charpente/empaquetage.dart';
import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_composite.dart';
import 'package:construction_app/charpente/escalier_texte.dart';
import 'package:flutter_test/flutter_test.dart';

/// 9 pi, 36 po de large, giron 10 1/4, nez 3/4 : 15 contremarches de 7,2 po, 14 marches de
/// 11 po de profondeur.
SpecEscalier _spec({
  double hauteur = 108,
  double largeur = 36,
  double entraxe = 16,
  double nez = 0.75,
  ProduitComposite? composite = produitCompositeGenerique,
}) => SpecEscalier(
  hauteurTotale: hauteur,
  largeur: largeur,
  nez: nez,
  espacementMax: entraxe,
  composite: composite,
);

List<double> _longueurs(ResultatDecoupe d) => [
  for (final p in d.planches)
    for (final x in p.pieces) x.longueur,
]..sort();

ProduitComposite _produit(String id) =>
    produitsComposite.singleWhere((p) => p.id == id);

void main() {
  final r = calculerEscalier(_spec());

  test('catalogue : identifiants uniques, valeurs plausibles, sources', () {
    final ids = produitsComposite.map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(produitsComposite.first, produitCompositeGenerique);
    for (final p in produitsComposite) {
      expect(p.largeur, inInclusiveRange(5, 6), reason: p.id);
      expect(p.epaisseur, inInclusiveRange(0.75, 1.05), reason: p.id);
      expect(p.ecart, inInclusiveRange(1 / 8, 3 / 8), reason: p.id);
      expect(p.ecartBout, inInclusiveRange(0, 1 / 4), reason: p.id);
      expect(p.entraxeMaxLimons, inInclusiveRange(7, 12), reason: p.id);
      expect(p.debordNezMax, inInclusiveRange(0.5, 1), reason: p.id);
      expect(p.longueurs, isNotEmpty, reason: p.id);
      expect(p.hauteursFascia, isNotEmpty, reason: p.id);
      expect(p.source, isNotEmpty, reason: p.id);
    }
    expect(produitComposite('inconnu'), produitCompositeGenerique);
    expect(produitComposite('trex_select').nom, 'Trex Select');
  });

  group('escalier', () {
    test('la marche a l\'épaisseur de la planche : siège du limon à R − t', () {
      expect(r.nombreContremarches, 15);
      expect(r.contremarche, closeTo(7.2, 1e-9));
      expect(r.hauteurDepart, closeTo(7.2 - 1, 1e-9));
      final trex = calculerEscalier(_spec(composite: _produit('trex_select')));
      expect(trex.hauteurDepart, closeTo(7.2 - 0.82, 1e-9));
      final bois = calculerEscalier(_spec(composite: null));
      expect(bois.hauteurDepart, closeTo(7.2 - 1.5, 1e-9));
    });

    test('limons à l\'entraxe du fabricant (16 po en bois)', () {
      int limons(ProduitComposite? p, {double entraxe = 16}) =>
          calculerEscalier(_spec(largeur: 48, composite: p, entraxe: entraxe))
              .nombreLimons;
      // 46,5 po entre les limons de rive.
      expect(limons(null), 4); // 16 po
      expect(limons(produitCompositeGenerique), 7); // 9 po
      expect(limons(_produit('fiberon_good_life')), 5); // 12 po
      expect(limons(_produit('timbertech_pro')), 6); // 10 po
      expect(limons(_produit('timbertech_terrain')), 7); // 8 po
      expect(limons(_produit('trex_select')), 7); // 200 mm
      // Un entraxe plus serré choisi par l'utilisateur est gardé.
      expect(limons(produitCompositeGenerique, entraxe: 6), 9);
    });

    test(
      'contremarches fermées par la fascia : pas d\'avertissement « ouvertes »',
      () {
        expect(r.verifications.any((v) => v.id == 'ouvertes'), isFalse);
      },
    );

    test('nez plus long que le fabricant le permet : averti', () {
      expect(r.verifications.any((v) => v.id == 'nez_composite'), isFalse);
      final long = calculerEscalier(_spec(nez: 1));
      final v = long.verifications.singleWhere((v) => v.id == 'nez_composite');
      expect(v.niveau, Niveau.avertissement);
      expect(v.message, contains('au plus 3/4"'));
      final azek = calculerEscalier(
        _spec(composite: _produit('timbertech_azek')),
      );
      expect(
        azek.verifications.any((v) => v.id == 'nez_composite'),
        isTrue,
        reason: 'PVC : 1/2 po au plus',
      );
    });
  });

  group('marches en cadre', () {
    final c = calculerComposite(r);

    test(
      'nez, 2 côtés, 1 planche au centre ; écart au bout contre le cadre',
      () {
        expect(c.rangsCentre, 1); // 11 − 5 1/2 = 5 1/2 : une planche
        // Centre : 36 − 2 × 5 1/2 − 2 × 1/8 (écart au bout contre chaque côté).
        expect(c.longueurCentre, closeTo(24.75, 1e-9));
        final pieces = _longueurs(c.planches);
        expect(pieces.where((x) => x == 36), hasLength(14)); // nez
        expect(pieces.where((x) => x == 11), hasLength(28)); // côtés
        expect(pieces.where((x) => x == 24.75), hasLength(14)); // centre
        expect(c.planches.horsLimites, isEmpty);
      },
    );

    test(
      'la largeur de planche et les écarts du produit changent le centre',
      () {
        final tt = calculerComposite(
          calculerEscalier(_spec(composite: _produit('timbertech_pro'))),
        );
        expect(tt.longueurCentre, closeTo(36 - 2 * 5.36 - 2 / 8, 1e-9));
        // PVC : bouts serrés, pas d'écart.
        final azek = calculerComposite(
          calculerEscalier(_spec(composite: _produit('timbertech_azek'))),
        );
        expect(azek.longueurCentre, closeTo(36 - 11, 1e-9));
      },
    );

    test('marche plus profonde : un rang de plus au centre', () {
      final profonde = calculerEscalier(
        const SpecEscalier(
          hauteurTotale: 108,
          giron: 11,
          nez: 0.75,
          composite: produitCompositeGenerique,
        ),
      );
      // 11 3/4 po : 11 3/4 − 5 1/2 = 6 1/4 → 2 rangs.
      expect(calculerComposite(profonde).rangsCentre, 2);
    });

    test('planches à bord carré dans les longueurs vendues du produit', () {
      final trex = calculerComposite(
        calculerEscalier(_spec(composite: _produit('trex_enhance'))),
      );
      // Bord carré Trex : 16 et 20 pi seulement.
      expect(
        trex.planches.planches.every((p) => p.stock == 192 || p.stock == 240),
        isTrue,
      );
    });
  });

  group('contremarches', () {
    final c = calculerComposite(r);

    test('fascias de 7 1/4 en 12 pi (3 par planche) ; backing 2x8', () {
      expect(c.hauteurFascia, 7.25);
      expect(c.fascias.parLongueur, {144.0: 5});
      expect(_longueurs(c.backing), List.filled(15, 36.0));
      expect(c.sectionBacking, '2x8');
    });

    test('contremarche de 7 1/2 po : fascia plus haute, backing 2x10', () {
      ResultatEscalier haute(ProduitComposite p) => calculerEscalier(
        SpecEscalier(
          hauteurTotale: 112.5,
          nombreContremarches: 15,
          nez: 0.75,
          composite: p,
        ),
      );
      final g = calculerComposite(haute(produitCompositeGenerique));
      expect(g.hauteurFascia, 11.25);
      expect(g.sectionBacking, '2x10');
      expect(
        calculerComposite(haute(_produit('trex_enhance'))).hauteurFascia,
        11.375,
      );
    });

    test(
      'plus large qu\'une fascia de 12 pi : deux morceaux par contremarche',
      () {
        final large = calculerComposite(calculerEscalier(_spec(largeur: 160)));
        expect(_longueurs(large.fascias), List.filled(30, 80.0));
      },
    );
  });

  group('fixation', () {
    test('attaches interdites sur les marches : tout vissé, avec bouchons', () {
      final c = calculerComposite(r); // générique : 5 limons
      // Par marche : nez 2 × 5 = 10, côtés 2 × 2 = 4, centre 1 × 2 × 3 = 6 → 20 ; 14 marches.
      expect(c.visApparentes, 280);
      expect(c.attaches, 0);
      // Fascias : 2 vis par limon × 5 × 15.
      expect(c.visFascia, 150);
    });

    test('Trex : attaches Hideaway au centre, nez et côtés vissés', () {
      final c = calculerComposite(
        calculerEscalier(_spec(composite: _produit('trex_enhance'))),
      ); // 9 po : 5 limons
      expect(c.visApparentes, 14 * (10 + 4));
      // 2 joints (devant, au fond) × 3 limons intérieurs × 14 marches.
      expect(c.attaches, 84);
      expect(c.boitesAttaches, 1); // boîte de 90
    });
  });

  group('2x12 à plat aux côtés des marches', () {
    ResultatEscalier avec({
      required bool blocs,
      String produit = 'trex_enhance',
      double largeur = 36,
    }) => calculerEscalier(
      SpecEscalier(
        hauteurTotale: 108,
        largeur: largeur,
        nez: 0.75,
        composite: _produit(produit),
        blocs2x12: blocs,
      ),
    );

    test('un morceau de chaque côté de chaque marche, entre le limon de côté et le suivant', () {
      final r = avec(blocs: true);
      // 5 limons aux 9 po au plus : entraxe réel 34 1/2 / 4 = 8 5/8 ; libre : 7 1/8.
      expect(r.nombreLimons, 5);
      final c = calculerComposite(r);
      expect(c.longueurBloc, closeTo(8.625 - 1.5, 1e-9));
      expect(c.blocsParMarche, 2);
      // Le milieu reste ouvert : 2 morceaux par marche, pas 4.
      expect(_longueurs(c.blocs!), List.filled(14 * 2, 7.125));
      expect(c.blocs!.horsLimites, isEmpty);
    });

    test('2 limons seulement : un morceau par marche', () {
      // Fiberon aux 12 po, escalier de 12 po : 2 limons à 10 1/2 ; libre : 9.
      final r = avec(blocs: true, produit: 'fiberon_good_life', largeur: 12);
      expect(r.nombreLimons, 2);
      final c = calculerComposite(r);
      expect(c.blocsParMarche, 1);
      expect(_longueurs(c.blocs!), List.filled(14, 9.0));
    });

    test(
      'la marche garde l\'épaisseur de la planche (pas de contreplaqué)',
      () {
        expect(
          avec(blocs: true).hauteurDepart,
          closeTo(avec(blocs: false).hauteurDepart, 1e-9),
        );
        expect(avec(blocs: true).hauteurDepart, closeTo(7.2 - 0.94, 1e-9));
      },
    );

    test('dans la liste de matériaux ; sans : rien', () {
      final lignes = materielEscalier(avec(blocs: true), metrique: false);
      final t = lignes
          .map((l) => '${l.quantite} × ${l.article} — ${l.detail}')
          .join('\n');
      expect(t, contains('2x12 traité ×'));
      expect(t, contains('(à plat aux côtés des marches)'));
      expect(
        t,
        contains(
          '28 morceaux de 7 1/8", un de chaque côté de chaque marche, '
          'entre le limon de côté et le suivant, sous la planche de côté',
        ),
      );
      expect(t, isNot(contains('ontreplaqué')));
      expect(calculerComposite(avec(blocs: false)).blocs, isNull);
      expect(
        materielEscalier(
          avec(blocs: false),
          metrique: false,
        ).map((l) => l.article).join(),
        isNot(contains('2x12 traité')),
      );
    });
  });

  group('liste de matériaux', () {
    String texte(ProduitComposite? p) => materielEscalier(
      calculerEscalier(_spec(composite: p)),
      metrique: false,
    ).map((l) => '${l.quantite} × ${l.article} — ${l.detail}').join('\n');

    test('générique : planches, fascias, backing, vis et bouchons ; pas d\'attaches', () {
      final t = texte(produitCompositeGenerique);
      expect(t, isNot(contains('Marches de')));
      expect(t, contains('Planches Composite courant ×'));
      expect(
        t,
        contains(
          'écart de 3/16" entre planches côte à côte, 1/8" au bout contre le cadre',
        ),
      );
      expect(t, contains('5 × Fascias Composite courant 7 1/4" × 12\''));
      expect(t, contains('2x8 traité ×'));
      expect(t, isNot(contains('attaches cachées Hideaway')));
      expect(
        t,
        contains('280 × Vis et bouchons (vis et bouchons de la couleur)'),
      );
      expect(t, contains('(attaches cachées interdites sur les marches)'));
      expect(t, contains('150 × Vis de fascia de la couleur'));
    });

    test('Trex : la boîte d\'attaches Hideaway et les bouchons du nez et des côtés', () {
      final t = texte(_produit('trex_enhance'));
      expect(
        t,
        contains('1 × Boîte d\'attaches cachées Hideaway Universal (90)'),
      );
      expect(t, contains('196 × Vis et bouchons'));
      expect(t, contains('Planches Trex Enhance ×'));
    });

    test('TimberTech Terrain : vis TOPLoc de la couleur, sans bouchon', () {
      final t = texte(_produit('timbertech_terrain'));
      expect(t, contains('× Vis (vis TOPLoc de la couleur'));
      expect(t, isNot(contains('bouchon')));
    });

    test('en bois : comme avant', () {
      final t = texte(null);
      expect(t, contains('Marches de'));
      expect(t, isNot(contains('Fascia')));
    });
  });
}
