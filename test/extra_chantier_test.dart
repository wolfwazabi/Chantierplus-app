import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/extra_chantier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dates', () {
    test('format ISO et affichage', () {
      expect(dateIso(DateTime(2026, 10, 1)), '2026-10-01');
      expect(dateAffichee('2026-10-01'), '01/10/2026');
      expect(dateAffichee('pas une date'), 'pas une date');
    });
    test('lecture d\'une date ISO', () {
      expect(lireDateIso('2026-10-01'), DateTime(2026, 10, 1));
      expect(lireDateIso('2026-02-30'), isNull);
      expect(lireDateIso('2026-1-5'), isNull);
    });
  });

  group('modèle', () {
    Map<String, dynamic> donnees([Map<String, dynamic> extra = const {}]) => {
      'companyId': 'A',
      'chantierId': 'chA',
      'description': 'Cloison',
      'mainOeuvre': '3 gars, 1 compagnon, 1 apprenti — 4 h',
      'dateTravaux': '2026-10-01',
      'ajouteParNom': 'Plus A',
      ...extra,
    };

    test('la main-d\'œuvre est un texte libre, conservé tel quel', () {
      final e = ExtraChantier.fromFirestore('x1', donnees());
      expect(e.id, 'x1');
      expect(e.mainOeuvre, '3 gars, 1 compagnon, 1 apprenti — 4 h');
      expect(e.photoUrl, isNull);
    });

    test('photo et date d\'ajout', () {
      final e = ExtraChantier.fromFirestore(
        'x1',
        donnees({
          'photoUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/p.jpg',
          'cheminPhoto': 'chantiers/A/chA/chantier_extras/p.jpg',
          'dateAjout': Timestamp.fromDate(DateTime(2026, 10, 1, 9)),
        }),
      );
      expect(e.photoUrl, isNotNull);
      expect(e.cheminPhoto, isNotNull);
      expect(e.dateAjout, DateTime(2026, 10, 1, 9));
    });

    test('champs absents : valeurs sûres, sans planter', () {
      final e = ExtraChantier.fromFirestore('x1', {});
      expect(e.mainOeuvre, '');
      expect(e.description, '');
    });
  });

  test('longueurs maximales identiques aux règles Firestore', () {
    expect(maxDescription, 2000);
    expect(maxMainOeuvre, 300);
  });
}
