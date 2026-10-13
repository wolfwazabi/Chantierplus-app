// La mesure en bref d'une pièce (pastille de la vue 3D) : pour chaque sorte de pièce de la scène.
import 'package:construction_app/charpente/mur.dart';
import 'package:construction_app/charpente/projet.dart';
import 'package:construction_app/charpente/scene.dart';
import 'package:flutter_test/flutter_test.dart';

Scene _scene({bool metrique = false}) => calculerProjet(
  const ProjetCharpente(
    mursActifs: true,
    murs: ParametresMursProjet(
      ouverturesContour: {
        0: [
          Ouverture(
            type: TypeOuverture.fenetre,
            nom: 'F1',
            largeurCadre: 36,
            hauteurCadre: 48,
            position: 60,
          ),
        ],
      },
    ),
  ),
  metrique: metrique,
).scene;

void main() {
  group('texte bref d\'une pièce', () {
    test(
      'solive : section et longueur, sans la précision entre parenthèses',
      () {
        const i = InfoPiece('Solive', [
          'Section : 2×10',
          "Longueur à couper : 12' (pointe longue)",
          'Entraxe : 16"',
        ]);
        expect(i.court, "2×10 · 12'");
      },
    );

    test('montant précoupé : la précision est laissée à la fiche', () {
      const i = InfoPiece('Montant', [
        'Section : 2×4',
        'Longueur à couper : 92 5/8" (montant précoupé)',
        'Position : de 16" à 17 1/2" du début du mur',
      ]);
      expect(i.court, '2×4 · 92 5/8"');
    });

    test('feuille de sous-plancher : dimensions de la pièce', () {
      const i = InfoPiece('Feuille de sous-plancher n° 3', [
        'Format : 4×8',
        "Pièce : 8' (en travers des solives) × 4'",
        'Feuille entière, sans coupe',
      ]);
      expect(i.court, "8' × 4'");
    });

    test('feuille murale : largeur × hauteur', () {
      const i = InfoPiece('Feuille murale n° 2', [
        'Format : 4×9',
        "Pièce : 4' de large × 9' de haut",
        'Feuille entière',
      ]);
      expect(i.court, "4' × 9'");
    });

    test('fourrure : sa longueur seulement', () {
      const i = InfoPiece('Fourrure verticale', [
        'Section : 3/4" × 2 1/2"',
        "Longueur : 8'",
        'Mur : Mur 1',
      ]);
      expect(i.court, "8'");
    });

    test('membrane et revêtement : l\'aire', () {
      const i = InfoPiece('Membrane (pare-air / pare-vapeur)', [
        'Mur : Mur 1',
        'Aire nette : 112,5 pi²',
        'Chevauchement à prévoir aux joints, selon les directives du fabricant',
      ]);
      expect(i.court, '112,5 pi²');
    });

    test('rien de mesurable : le titre', () {
      expect(const InfoPiece('Pièce', ['Mur : Mur 1']).court, 'Pièce');
      expect(const InfoPiece('Pièce', []).court, 'Pièce');
    });

    test('section sans longueur : le titre (pas de demi-mesure)', () {
      expect(const InfoPiece('Montant', ['Section : 2×4']).court, 'Montant');
    });
  });

  group('toutes les pièces d\'une vraie scène', () {
    for (final metrique in [false, true]) {
      test(
        'plancher + murs + fenêtre (${metrique ? 'métrique' : 'impérial'})',
        () {
          final scene = _scene(metrique: metrique);
          expect(scene.infos, isNotEmpty);
          final titres = <String>{};
          for (final i in scene.infos.values) {
            titres.add(i.titre);
            expect(i.court, isNotEmpty, reason: i.titre);
            expect(
              i.court.length,
              lessThanOrEqualTo(32),
              reason: '${i.titre} : « ${i.court} »',
            );
            expect(i.court, isNot(contains('(')), reason: i.titre);
            expect(i.court, isNot(contains('n°')), reason: i.titre);
          }
          // Chaque sorte de pièce de la scène est couverte.
          expect(
            titres,
            containsAll([
              'Solive',
              'Montant',
              'Linteau',
              'Membrane (pare-air / pare-vapeur)',
            ]),
          );
        },
      );
    }

    test('les pièces de bois montrent leur section et leur longueur', () {
      final scene = _scene();
      for (final i in scene.infos.values.where(
        (i) => i.lignes.any((l) => l.startsWith('Longueur à couper : ')),
      )) {
        expect(i.court, contains(' · '), reason: i.titre);
        expect(i.court, matches(RegExp(r'^\d×\d+ · ')), reason: i.titre);
      }
    });

    test('les feuilles montrent largeur × hauteur', () {
      final scene = _scene();
      final feuilles = scene.infos.values.where(
        (i) => i.titre.startsWith('Feuille'),
      );
      expect(feuilles, isNotEmpty);
      for (final i in feuilles) {
        expect(i.court, contains(' × '), reason: i.titre);
        expect(i.court, isNot(contains('de large')));
      }
    });

    test('en mètres : la mesure bref est en mètres', () {
      final scene = _scene(metrique: true);
      final solive = scene.infos.values.firstWhere((i) => i.titre == 'Solive');
      expect(solive.court, isNot(contains("'")));
      expect(solive.court, anyOf(contains(' m'), contains('mm')));
    });
  });
}
