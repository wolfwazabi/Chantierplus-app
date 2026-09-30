import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/extra_chantier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nombre d\'hommes', () {
    test('entier de 1 à 500', () {
      expect(lireNombreHommes('1'), 1);
      expect(lireNombreHommes(' 12 '), 12);
      expect(lireNombreHommes('500'), 500);
    });
    test('refusé : vide, 0, négatif, décimal, trop grand, texte', () {
      for (final t in ['', '0', '-2', '1.5', '501', 'deux', '2 hommes']) {
        expect(lireNombreHommes(t), isNull, reason: t);
      }
    });
  });

  group('temps en heures', () {
    test('point ou virgule, arrondi au centième', () {
      expect(lireHeures('3.5'), 3.5);
      expect(lireHeures('3,5'), 3.5);
      expect(lireHeures(' 8 '), 8);
      expect(lireHeures('0.333'), 0.33);
      expect(lireHeures('1000'), 1000);
    });
    test('refusé : vide, 0, négatif, trop grand, texte, infini', () {
      for (final t in [
        '',
        '0',
        '0.001',
        '-1',
        '1000.5',
        'abc',
        '3h',
        'Infinity',
        'NaN',
      ]) {
        expect(lireHeures(t), isNull, reason: t);
      }
    });
  });

  group('affichage', () {
    test('nombres sans zéros inutiles', () {
      expect(formatNombre(7), '7');
      expect(formatNombre(3.5), '3.5');
      expect(formatNombre(3.25), '3.25');
      expect(formatNombre(10), '10');
      expect(formatNombre(100), '100');
    });
    test('résumé du temps', () {
      expect(resumeTemps(2, 3.5), '2 hommes × 3.5 h = 7 h-homme');
      expect(resumeTemps(1, 8), '1 homme × 8 h = 8 h-homme');
      expect(resumeTemps(3, 2.25), '3 hommes × 2.25 h = 6.75 h-homme');
    });
    test('dates', () {
      expect(dateIso(DateTime(2026, 10, 1)), '2026-10-01');
      expect(dateAffichee('2026-10-01'), '01/10/2026');
      expect(dateAffichee('pas une date'), 'pas une date');
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
      'nombreHommes': 2,
      'heures': 3.5,
      'dateTravaux': '2026-10-01',
      'ajouteParNom': 'Plus A',
      ...extra,
    };

    test('lecture et heures-homme', () {
      final e = ExtraChantier.fromFirestore('x1', donnees());
      expect(e.id, 'x1');
      expect(e.nombreHommes, 2);
      expect(e.heures, 3.5);
      expect(e.heuresHommes, 7);
      expect(e.photoUrl, isNull);
    });

    test('entier stocké comme nombre, photo et date d\'ajout', () {
      final e = ExtraChantier.fromFirestore(
        'x1',
        donnees({
          'heures': 4,
          'photoUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/p.jpg',
          'cheminPhoto': 'chantiers/A/chA/chantier_extras/p.jpg',
          'dateAjout': Timestamp.fromDate(DateTime(2026, 10, 1, 9)),
        }),
      );
      expect(e.heures, 4.0);
      expect(e.photoUrl, isNotNull);
      expect(e.dateAjout, DateTime(2026, 10, 1, 9));
    });

    test('champs absents : valeurs sûres, sans planter', () {
      final e = ExtraChantier.fromFirestore('x1', {});
      expect(e.heuresHommes, 0);
      expect(e.description, '');
    });
  });
}
