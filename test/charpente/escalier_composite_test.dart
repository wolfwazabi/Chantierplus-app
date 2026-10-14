// Marches en composite : marches en cadre, contremarches en fascia avec un 2x de backing,
// attaches cachées au centre, vis apparentes (nez et côtés) avec bouchons, limons à l'entraxe du
// fabricant, écarts du fabricant (côte à côte et au bout contre le cadre).
import 'package:construction_app/charpente/composite.dart';
import 'package:construction_app/charpente/empaquetage.dart';
import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_composite.dart';
import 'package:construction_app/charpente/escalier_texte.dart';
import 'package:flutter_test/flutter_test.dart';

/// 9 pi, 36 po de large, giron 10 1/4, nez 1 po : 15 contremarches de 7,2 po, 14 marches de
/// 11 1/4 po de profondeur.
SpecEscalier _spec({
  double hauteur = 108,
  double largeur = 36,
  double entraxe = 16,
  ProduitComposite? composite = produitCompositeGenerique,
}) => SpecEscalier(
  hauteurTotale: hauteur,
  largeur: largeur,
  nez: 1,
  espacementMax: entraxe,
  composite: composite,
);

List<double> _longueurs(ResultatDecoupe d) => [
  for (final p in d.planches)
    for (final x in p.pieces) x.longueur,
]..sort();

void main() {
  final r = calculerEscalier(_spec());

  group('escalier', () {
    test(
      'la marche a l\'épaisseur de la planche : siège du limon à R − 1 po',
      () {
        expect(r.nombreContremarches, 15);
        expect(r.contremarche, closeTo(7.2, 1e-9));
        expect(r.hauteurDepart, closeTo(7.2 - 1, 1e-9));
        final bois = calculerEscalier(_spec(composite: null));
        expect(bois.hauteurDepart, closeTo(7.2 - 1.5, 1e-9));
      },
    );

    test('limons à 12 po au plus (16 en bois)', () {
      final large = calculerEscalier(_spec(largeur: 48));
      expect(large.nombreLimons, 5); // 46,5 / 12 → 4 espaces
      expect(
        calculerEscalier(_spec(largeur: 48, composite: null)).nombreLimons,
        4,
      );
      // Un entraxe plus serré choisi par l'utilisateur est gardé.
      expect(calculerEscalier(_spec(largeur: 48, entraxe: 10)).nombreLimons, 6);
    });

    test(
      'contremarches fermées par la fascia : pas d\'avertissement « ouvertes »',
      () {
        expect(r.verifications.any((v) => v.id == 'ouvertes'), isFalse);
      },
    );
  });

  group('composite', () {
    final c = calculerComposite(r);

    test('marches en cadre : nez, 2 côtés, 1 planche au centre avec l\'écart au bout', () {
      expect(
        c.rangsCentre,
        1,
      ); // 11 1/4 − 5 1/2 = 5 3/4 : une planche (1/4 po de reste)
      // Centre : 36 − 2 × 5 1/2 − 2 × 1/8 (écart au bout contre chaque côté).
      expect(c.longueurCentre, closeTo(24.75, 1e-9));
      final pieces = _longueurs(c.planches);
      expect(pieces.where((x) => x == 36), hasLength(14)); // nez
      expect(pieces.where((x) => x == 11.25), hasLength(28)); // côtés
      expect(pieces.where((x) => x == 24.75), hasLength(14)); // centre
      expect(c.planches.horsLimites, isEmpty);
      expect(
        c.planches.planches.every(
          (p) => produitCompositeGenerique.longueurs.contains(p.stock),
        ),
        isTrue,
      );
    });

    test('marche plus profonde : un rang de plus au centre', () {
      final profonde = calculerEscalier(
        SpecEscalier(
          hauteurTotale: 108,
          giron: 11,
          nez: 1,
          composite: produitCompositeGenerique,
        ),
      );
      // 12 po de profondeur : 12 − 5 1/2 = 6 1/2 → 2 rangs.
      expect(calculerComposite(profonde).rangsCentre, 2);
    });

    test('fascias de 7 1/4 en 12 pi (3 par planche) ; backing 2x8', () {
      expect(c.hauteurFascia, 7.25);
      expect(c.fascias.parLongueur, {144.0: 5});
      expect(_longueurs(c.backing), List.filled(15, 36.0));
      expect(c.sectionBacking, '2x8');
    });

    test('contremarche de 7 1/2 po : fascia de 11 1/4, backing 2x10', () {
      // 112 1/2 po en 15 contremarches imposées : 7 1/2 po chacune.
      final haut = calculerComposite(
        calculerEscalier(
          const SpecEscalier(
            hauteurTotale: 112.5,
            nombreContremarches: 15,
            nez: 1,
            composite: produitCompositeGenerique,
          ),
        ),
      );
      expect(haut.hauteurFascia, 11.25);
      expect(haut.hauteurFascia, 11.25);
      expect(haut.sectionBacking, '2x10');
    });

    test(
      'plus large qu\'une fascia de 12 pi : deux morceaux par contremarche',
      () {
        final large = calculerComposite(calculerEscalier(_spec(largeur: 160)));
        expect(_longueurs(large.fascias), List.filled(30, 80.0));
      },
    );

    test('vis apparentes et bouchons, attaches cachées, vis de fascia', () {
      // 4 limons. Par marche : nez 2 × 4 = 8 vis, côtés 2 × 2 = 4 → 12 ; 14 marches.
      expect(c.visApparentes, 168);
      expect(c.boitesBouchons, 2); // boîtes de 100
      // Centre : 2 joints (devant, au fond) × 2 limons intérieurs × 14 marches.
      expect(c.attaches, 56);
      expect(c.boitesAttaches, 1); // boîte de 90
      // Fascias : 2 vis par limon × 4 × 15.
      expect(c.visFascia, 120);
    });

    test('trop étroit pour un cadre : message clair', () {
      expect(
        () => calculerComposite(calculerEscalier(_spec(largeur: 11))),
        throwsA(isA<EscalierInvalide>()),
      );
    });
  });

  group('liste de matériaux', () {
    final lignes = materielEscalier(r, metrique: false);
    String texte() => lignes
        .map((l) => '${l.quantite} × ${l.article} — ${l.detail}')
        .join('\n');

    test('les articles du composite remplacent « Marches de … de long »', () {
      final t = texte();
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
      expect(t, contains('1 × Boîte d\'attaches cachées'));
      expect(t, contains('2 × Boîtes de vis et bouchons de la couleur (100)'));
      expect(t, contains('168 vis apparentes cachées par un bouchon'));
      expect(t, contains('120 × Vis de fascia de la couleur'));
    });

    test('en bois : comme avant', () {
      final bois = materielEscalier(
        calculerEscalier(_spec(composite: null)),
        metrique: false,
      );
      expect(bois.map((l) => l.article).join(), contains('Marches de'));
      expect(bois.map((l) => l.article).join(), isNot(contains('Fascia')));
    });
  });
}
