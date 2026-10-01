import 'package:construction_app/charpente/unites.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lecture impériale', () {
    final cas = <String, double>{
      '10\'6"': 126,
      '10\' 6"': 126,
      '10\'6': 126,
      '10\' 6 1/2"': 126.5,
      '10\'6-1/2"': 126.5,
      '10-6': 126,
      '10 6': 126,
      '10 6 1/2': 126.5,
      '126"': 126,
      '126.5"': 126.5,
      '10.5\'': 126,
      '13\'': 156,
      '13': 156,
      '13.5': 162,
      '6 1/2"': 6.5,
      '1/2"': 0.5,
      '3/4"': 0.75,
      '0"': 0,
      '10 pi 6 po': 126,
      '10 ft 6 in': 126,
      '10pi6po': 126,
      '10’6”': 126,
      '10’6’’': 126,
      '10′ 6″': 126,
      '10\'6½"': 126.5,
      '  10\' 6"  ': 126,
      '1000\'': 12000,
    };
    cas.forEach((texte, attendu) {
      test('« $texte » = $attendu po', () {
        expect(lireLongueurImperiale(texte), closeTo(attendu, 1e-9));
      });
    });

    test('refusé : vide, texte, négatif, symboles mal placés, trop grand', () {
      for (final t in [
        '',
        '   ',
        'abc',
        '-5',
        '10\'6\'',
        '10"6',
        '\'',
        '\'6"',
        '1/0"',
        '10\'6"x',
        '10 6 7 8',
        '13 1/2', // ambigu : pieds ou pouces ?
        '1/2',
        '1001\'',
        '1e3',
        '10\'\'\'',
      ]) {
        expect(
          () => lireLongueurImperiale(t),
          throwsA(isA<MesureInvalide>()),
          reason: t,
        );
      }
    });

    test('le message d\'erreur est lisible', () {
      try {
        lireLongueurImperiale('13 1/2');
        fail('doit échouer');
      } on MesureInvalide catch (e) {
        expect(e.message, contains('unités'));
      }
    });
  });

  group('lecture métrique', () {
    test('mètres par défaut, mm, cm, espaces et virgule', () {
      expect(lireLongueurMetrique('3.2'), closeTo(3200 / 25.4, 1e-9));
      expect(lireLongueurMetrique('3,2 m'), closeTo(3200 / 25.4, 1e-9));
      expect(lireLongueurMetrique('3200 mm'), closeTo(3200 / 25.4, 1e-9));
      expect(lireLongueurMetrique('3 200 mm'), closeTo(3200 / 25.4, 1e-9));
      expect(lireLongueurMetrique('320 cm'), closeTo(3200 / 25.4, 1e-9));
      expect(lireLongueurMetrique('38 mm'), closeTo(1.496, 1e-3));
    });
    test('refusé', () {
      for (final t in ['', 'abc', '-3', '3 pieds', '3..2', '5000 m']) {
        expect(
          () => lireLongueurMetrique(t),
          throwsA(isA<MesureInvalide>()),
          reason: t,
        );
      }
    });
    test('selon le mode', () {
      expect(lireLongueur('10\'6"', metrique: false), 126);
      expect(lireLongueur('3.2', metrique: true), closeTo(125.984, 1e-3));
    });
  });

  group('angle', () {
    test('valeurs valides', () {
      expect(lireAngle('90'), 90);
      expect(lireAngle('35°'), 35);
      expect(lireAngle('35,5'), 35.5);
    });
    test('refusé : 0, 360, négatif, texte', () {
      for (final t in ['0', '360', '-10', '400', 'abc', '']) {
        expect(() => lireAngle(t), throwsA(isA<MesureInvalide>()), reason: t);
      }
    });
  });

  group('affichage', () {
    test('impérial', () {
      expect(formatImperial(126), '10\' 6"');
      expect(formatImperial(126.5), '10\' 6 1/2"');
      expect(formatImperial(120), '10\'');
      expect(formatImperial(156), '13\'');
      expect(formatImperial(6.5), '6 1/2"');
      expect(formatImperial(0.5), '1/2"');
      expect(formatImperial(0), '0"');
      expect(formatImperial(1.5), '1 1/2"');
      expect(formatImperial(92.625), '7\' 8 5/8"');
      expect(formatImperial(97.125), '8\' 1 1/8"');
      expect(formatImperial(12), '1\'');
      expect(formatImperial(13.0625), '1\' 1 1/16"');
    });
    test('arrondi au 1/16 et report sur les pieds', () {
      expect(formatImperial(11.99), '1\'');
      expect(formatImperial(5.0001), '5"');
      expect(formatImperial(0.03), '0"');
      expect(formatImperial(0.04), '1/16"');
    });
    test('métrique', () {
      expect(formatMetrique(3200 / 25.4), '3,2 m');
      expect(formatMetrique(1), '25 mm');
      expect(formatMetrique(1000 / 25.4), '1 m');
      expect(formatMetrique(38 / 25.4), '38 mm');
    });
    test('planches commerciales', () {
      expect(formatPlanche(144, metrique: false), '12\'');
      expect(formatPlanche(3.6576 * 39.3701, metrique: true), '3,66 m');
    });
    test('nombres et angles', () {
      expect(formatNombre(7.5), '7,5');
      expect(formatNombre(8), '8');
      expect(formatNombre(0.125, decimales: 3), '0,125');
      expect(formatAngle(35), '35°');
      expect(formatAngle(35.25), '35,3°');
    });
    test('lecture puis affichage : aller-retour', () {
      for (final po in [126.0, 126.5, 97.125, 5.0625, 156.0, 0.0625]) {
        expect(
          lireLongueurImperiale(formatImperial(po)),
          closeTo(po, 1e-9),
          reason: '$po',
        );
      }
    });
  });
}
