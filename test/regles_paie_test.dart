import 'package:construction_app/models/regles_paie.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const r = ReglesPaie.defaut; // pause 15 non payée, dîner 30 payé
  const h7 = 7 * 60, h15 = 15 * 60;

  group('heures d\'une journée (règles par défaut)', () {
    int? jour({bool pause = true, bool diner = true}) => r.minutesTravaillees(
      debutMinutes: h7,
      finMinutes: h15,
      pauseMatinPrise: pause,
      dinerPris: diner,
    );

    test('7 h à 15 h, pause et dîner pris : 8 h − 15 min = 7,75 h', () {
      expect(jour(), 465);
    });

    test('dîner non pris (travaillé) : + 30 min → 8,25 h', () {
      expect(jour(diner: false), 495);
    });

    test('pause non prise : rien à retirer → 8 h', () {
      expect(jour(pause: false), 480);
    });

    test('heures manquantes ou fin avant début → null', () {
      expect(
        r.minutesTravaillees(
          debutMinutes: null,
          finMinutes: h15,
          pauseMatinPrise: true,
          dinerPris: true,
        ),
        isNull,
      );
      expect(
        r.minutesTravaillees(
          debutMinutes: h15,
          finMinutes: h7,
          pauseMatinPrise: true,
          dinerPris: true,
        ),
        isNull,
      );
    });
  });

  group('règles réglées par l\'admin', () {
    test('dîner non payé et pris : − 30 min ; pause payée : rien', () {
      const autre = ReglesPaie(pauseMatinPayee: true, dinerPaye: false);
      expect(
        autre.minutesTravaillees(
          debutMinutes: h7,
          finMinutes: h15,
          pauseMatinPrise: true,
          dinerPris: true,
        ),
        450,
      );
    });

    test('durées modifiées : dîner 60 min non pris et payé → + 60', () {
      const autre = ReglesPaie(dinerMinutes: 60);
      expect(
        autre.minutesTravaillees(
          debutMinutes: h7,
          finMinutes: h15,
          pauseMatinPrise: false,
          dinerPris: false,
        ),
        540,
      );
    });
  });

  group('voyagement', () {
    const actif = ReglesPaie(voyagementActif: true); // seuil 60, 50 %

    test('désactivé (défaut) : jamais payé', () {
      expect(r.minutesVoyagementPayees(120), 0);
    });

    test('jusqu\'au seuil de 60 min : rien', () {
      expect(actif.minutesVoyagementPayees(59), 0);
      expect(actif.minutesVoyagementPayees(60), 0);
      expect(actif.minutesVoyagementPayees(0), 0);
      expect(actif.minutesVoyagementPayees(null), 0);
    });

    test('au-delà du seuil : seulement l\'excédent, à 50 %', () {
      expect(actif.minutesVoyagementPayees(61), 0.5);
      expect(actif.minutesVoyagementPayees(90), 15); // 30 min au-delà, à 50 %
      expect(actif.minutesVoyagementPayees(120), 30);
    });

    test('seuil et pourcentage au choix de l\'employeur', () {
      const x = ReglesPaie(
        voyagementActif: true,
        voyagementSeuilMinutes: 30,
        voyagementPourcentage: 100,
      );
      expect(x.minutesVoyagementPayees(30), 0);
      expect(x.minutesVoyagementPayees(45), 15);
    });

    test('exemples de l\'entrepreneur : 2 h de voyagement', () {
      const aPartirDe60 = ReglesPaie(
        voyagementActif: true,
        voyagementSeuilMinutes: 60,
        voyagementPourcentage: 100,
      );
      const aPartirDe30 = ReglesPaie(
        voyagementActif: true,
        voyagementSeuilMinutes: 30,
        voyagementPourcentage: 100,
      );
      expect(aPartirDe60.minutesVoyagementPayees(120), 60); // 1 h payée
      expect(aPartirDe30.minutesVoyagementPayees(120), 90); // 1 h 30 payée
      // Au pourcentage choisi : 1 h à 50 % = 30 min ; 1 h 30 à 75 % = 67,5 min.
      expect(actif.minutesVoyagementPayees(120), 30);
      const x = ReglesPaie(
        voyagementActif: true,
        voyagementSeuilMinutes: 30,
        voyagementPourcentage: 75,
      );
      expect(x.minutesVoyagementPayees(120), 67.5);
    });

    test('seuil à 0 : tout le voyagement, au pourcentage', () {
      const x = ReglesPaie(voyagementActif: true, voyagementSeuilMinutes: 0);
      expect(x.minutesVoyagementPayees(90), 45);
      expect(x.minutesVoyagementPayees(0), 0);
    });

    test('pourcentage à 0 : rien', () {
      const x = ReglesPaie(voyagementActif: true, voyagementPourcentage: 0);
      expect(x.minutesVoyagementPayees(300), 0);
    });
  });

  group('lecture Firestore', () {
    test('map absente → défaut', () {
      expect(ReglesPaie.depuisMap(null), ReglesPaie.defaut);
    });

    test('aller-retour sans perte', () {
      const x = ReglesPaie(
        pauseMatinPayee: true,
        dinerMinutes: 45,
        voyagementActif: true,
        voyagementSeuilMinutes: 30,
        voyagementPourcentage: 75,
      );
      expect(ReglesPaie.depuisMap(x.versMap()), x);
    });

    test('valeurs invalides → défaut champ par champ', () {
      final x = ReglesPaie.depuisMap({
        'dinerMinutes': -5,
        'voyagementPourcentage': 500,
        'dinerPaye': 'oui',
        'voyagementActif': true,
      });
      expect(x.dinerMinutes, 30);
      expect(x.voyagementPourcentage, 50);
      expect(x.dinerPaye, true);
      expect(x.voyagementActif, true);
    });
  });
}
