import 'dart:math' as math;

import 'package:construction_app/charpente/composite.dart';
import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/escalier_composite.dart';
import 'package:construction_app/charpente/escalier_scene.dart';
import 'package:construction_app/charpente/solides.dart';
import 'package:construction_app/charpente/vue3d_core.dart';
import 'package:flutter_test/flutter_test.dart';

ResultatEscalier _escalier({
  String? produit = 'trex_enhance',
  double largeur = 36,
}) => calculerEscalier(
  SpecEscalier(
    hauteurTotale: 108,
    largeur: largeur,
    nez: 0.75,
    composite: produit == null ? null : produitComposite(produit),
  ),
);

int _compte(Scene s, String prefixe) => {
  for (final so in s.solides)
    if (so.groupe.startsWith(prefixe)) so.groupe,
}.length;

/// Boîte englobante d'un solide : x, y de l'empreinte, z0 à z1.
(double, double, double, double, double, double) _boite(Solide s) => (
  s.coque.map((p) => p.x).reduce(math.min),
  s.coque.map((p) => p.x).reduce(math.max),
  s.coque.map((p) => p.y).reduce(math.min),
  s.coque.map((p) => p.y).reduce(math.max),
  s.z0,
  s.z1,
);

void main() {
  test('escalier en bois : pas de vue 3D', () {
    expect(
      sceneEscalier(_escalier(produit: null), metrique: false).estVide,
      isTrue,
    );
  });

  test('comme la photo : limons, backing et fascia à chaque contremarche, 2x12 aux côtés, '
      'la marche du haut en cadre', () {
    final r = _escalier();
    final c = calculerComposite(r);
    final s = sceneEscalier(r, metrique: false);
    expect(r.nombreContremarches, 15);
    expect(r.nombreLimons, 5);
    // Un limon tranché marche par marche (14 tranches chacun).
    expect(_compte(s, 'limon'), 5);
    expect(s.solides.where((so) => so.groupe == 'limon0'), hasLength(14));
    // Un backing et une fascia par contremarche.
    expect(_compte(s, 'backing'), 15);
    expect(_compte(s, 'fascia'), 15);
    // 2x12 à plat : 2 par marche (le milieu ouvert).
    expect(_compte(s, 'bloc'), 14 * 2);
    // La marche du haut : nez, 2 côtés en onglet, les planches du centre.
    expect(s.solides.where((so) => so.groupe == 'nez'), hasLength(1));
    expect(s.solides.where((so) => so.groupe == 'cotes'), hasLength(2));
    expect(
      s.solides.where((so) => so.groupe == 'centre'),
      hasLength(c.rangsCentre),
    );
    // Couleurs : bois (limons, backing), fascias, 2x12, composite.
    expect(
      {for (final so in s.solides) so.matiere},
      containsAll([
        Matiere.bois,
        Matiere.fascia,
        Matiere.bloc,
        Matiere.composite,
      ]),
    );
    // Une fiche par pièce.
    for (final so in s.solides) {
      expect(s.infos[so.groupe], isNotNull, reason: so.groupe);
    }
    expect(s.infos['bloc1.0']!.lignes, contains('Longueur à couper : 7 1/8"'));
    expect(s.cotes, hasLength(3));
  });

  test('aux bonnes places : le 2x12 entre le limon de côté et le suivant, à égalité du siège', () {
    final r = _escalier();
    final s = sceneEscalier(r, metrique: false);
    final bloc = s.solides.firstWhere((so) => so.groupe == 'bloc1.0');
    final (x0, x1, y0, y1, z0, z1) = _boite(bloc);
    expect(x0, closeTo(1.5, 1e-9)); // contre le limon de gauche
    expect(x1, closeTo(r.espacementReel, 1e-9)); // contre le 2e limon
    expect(y0, closeTo(0, 1e-9)); // devant du siège 1
    expect(y1, closeTo(r.giron - 1.5, 1e-9)); // contre le backing du dessus
    expect(z1, closeTo(r.contremarche - 0.94, 1e-9)); // siège 1
    expect(z1 - z0, closeTo(1.5, 1e-9));
    final droite = _boite(s.solides.firstWhere((so) => so.groupe == 'bloc1.1'));
    expect(droite.$1, closeTo(36 - r.espacementReel, 1e-9));
    expect(droite.$2, closeTo(36 - 1.5, 1e-9));
    // Le dessus de la marche du haut est à sa hauteur finie.
    final nez = s.solides.firstWhere((so) => so.groupe == 'nez');
    expect(nez.z1, closeTo(14 * r.contremarche, 1e-9));
    expect(s.max.z, closeTo(108, 1e-9));
  });

  test('aucune pièce n\'en traverse une autre', () {
    final s = sceneEscalier(_escalier(), metrique: false);
    final boites = [for (final so in s.solides) _boite(so)];
    for (var i = 0; i < s.solides.length; i++) {
      for (var j = i + 1; j < s.solides.length; j++) {
        final a = boites[i], b = boites[j];
        final groupes = {s.solides[i].groupe, s.solides[j].groupe};
        // Le nez et les côtés se touchent en onglet : leurs boîtes se croisent, pas les pièces.
        if (groupes.containsAll(['nez', 'cotes']) ||
            (groupes.length == 1 && groupes.single == 'cotes')) {
          continue;
        }
        final recouvre =
            math.min(a.$2, b.$2) - math.max(a.$1, b.$1) > 1e-6 &&
            math.min(a.$4, b.$4) - math.max(a.$3, b.$3) > 1e-6 &&
            math.min(a.$6, b.$6) - math.max(a.$5, b.$5) > 1e-6;
        expect(
          recouvre,
          isFalse,
          reason: '${s.solides[i].groupe} et ${s.solides[j].groupe}',
        );
      }
    }
  });

  test('l\'ordre d\'affichage se calcule pour la vue de départ', () {
    final s = sceneEscalier(_escalier(), metrique: false);
    final ordre = ordreAffichage(s.solides, Camera.pourScene(s, 400, 240));
    expect(ordre.toSet(), hasLength(s.solides.length));
  });

  test('2 limons seulement : un 2x12 par marche, entre les deux', () {
    final r = _escalier(produit: 'fiberon_good_life', largeur: 12);
    final s = sceneEscalier(r, metrique: false);
    expect(_compte(s, 'bloc'), 14);
    final (x0, x1, _, _, _, _) = _boite(
      s.solides.firstWhere((so) => so.groupe == 'bloc1.0'),
    );
    expect(x0, closeTo(1.5, 1e-9));
    expect(x1, closeTo(12 - 1.5, 1e-9));
  });
}
