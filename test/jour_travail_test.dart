// Une semaine antérieure garde ses heures et son voyagement payés d'origine : un
// changement des règles de paie ne réécrit jamais le passé. Voir
// functions/src/feuille_temps.js (côté serveur, mêmes règles).
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/correction_feuille.dart';
import 'package:construction_app/models/regles_paie.dart';
import 'package:construction_app/screens/feuille_temps_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _anciennes = ReglesPaie(
  voyagementActif: true,
  voyagementSeuilMinutes: 60,
  voyagementPourcentage: 50,
);
const _nouvelles = ReglesPaie(
  voyagementActif: true,
  voyagementSeuilMinutes: 30,
  voyagementPourcentage: 100,
);

JourTravail _jour({int voyagementMinutes = 120}) => JourTravail('Lundi')
  ..chantier = const Chantier(id: 'c1', companyId: 'A', nom: 'A', adresse: '')
  ..heureDebut = const TimeOfDay(hour: 7, minute: 0)
  ..heureFin = const TimeOfDay(hour: 15, minute: 0)
  ..tempsVoyagement = Duration(minutes: voyagementMinutes);

void main() {
  tearDown(() => AppSession.reglesPaie.value = ReglesPaie.defaut);

  test('semaine courante (non figée) : suit les règles actuelles', () {
    AppSession.reglesPaie.value = _anciennes;
    final j = _jour();
    expect(j.heuresVoyagementPayees, 0.5); // 60 min au-delà du seuil, à 50 %
    AppSession.reglesPaie.value = _nouvelles;
    expect(j.heuresVoyagementPayees, 1.5); // 90 min au-delà de 30, à 100 %
  });

  test('semaine antérieure : garde les valeurs d\'origine malgré de nouvelles règles', () {
    AppSession.reglesPaie.value = _anciennes;
    final j = _jour()..figer(heures: 7.75, voyagementPaye: 0.5);
    AppSession.reglesPaie.value = _nouvelles;
    expect(j.heuresVoyagementPayees, 0.5);
    expect(j.heuresTravaillees, 7.75);
    // Même avec le voyagement désactivé aujourd'hui.
    AppSession.reglesPaie.value = const ReglesPaie(voyagementActif: false);
    expect(j.heuresVoyagementPayees, 0.5);
    // Et si les pauses changent aussi.
    AppSession.reglesPaie.value = const ReglesPaie(dinerPaye: false);
    expect(j.heuresTravaillees, 7.75);
  });

  test(
    'les valeurs d\'origine servent aussi quand la formule a changé depuis',
    () {
      // Ancienne formule : 90 min à partir de 60, à 50 % = 45 min = 0,75 h. La valeur
      // enregistrée (0,75) reste affichée, même si la nouvelle formule donnerait 0,25.
      AppSession.reglesPaie.value = _anciennes;
      final j = _jour(voyagementMinutes: 90)
        ..figer(heures: 7.75, voyagementPaye: 0.75);
      expect(j.heuresVoyagementPayees, 0.75);
    },
  );

  test('journée modifiée : recalculée avec les règles actuelles', () {
    AppSession.reglesPaie.value = _anciennes;
    final j = _jour()..figer(heures: 7.75, voyagementPaye: 0.5);
    AppSession.reglesPaie.value = _nouvelles;
    j.tempsVoyagement = const Duration(minutes: 150);
    expect(j.heuresVoyagementPayees, 2); // 120 min au-delà de 30, à 100 %
    // Retour à la saisie d'origine : les valeurs d'origine reviennent.
    j.tempsVoyagement = const Duration(minutes: 120);
    expect(j.heuresVoyagementPayees, 0.5);
  });

  test('chaque élément de la saisie compte : heures, pauses', () {
    AppSession.reglesPaie.value = _anciennes;
    final j = _jour()..figer(heures: 7.75, voyagementPaye: 0.5);
    // Nouvelles règles : pause de 30 min non payée, dîner non payé.
    AppSession.reglesPaie.value = const ReglesPaie(
      pauseMatinMinutes: 30,
      dinerPaye: false,
    );
    expect(j.heuresTravaillees, 7.75); // valeur d'origine
    j.heureFin = const TimeOfDay(hour: 16, minute: 0);
    expect(j.heuresTravaillees, 8); // 9 h − pause 30 min − dîner 30 min
    j.heureFin = const TimeOfDay(hour: 15, minute: 0);
    expect(j.heuresTravaillees, 7.75); // saisie d'origine rétablie
    j.diner = false;
    expect(j.heuresTravaillees, 7.5); // 8 h − pause 30 min
    j.diner = true;
    j.pauseMatin = false;
    expect(j.heuresTravaillees, 7.5); // 8 h − dîner 30 min
  });

  test('jour « non travaillé » : aucune valeur', () {
    final j = JourTravail('Mardi')..chantier = chantierAucun;
    j.figer(heures: null, voyagementPaye: 0);
    expect(j.heuresTravaillees, isNull);
    expect(j.heuresVoyagementPayees, 0);
  });

  test('férié : 8 h payées, aucune heure travaillée ni voyagement, journée remplie', () {
    final j = _jour()..chantier = chantierFerie;
    expect(j.estFerie, isTrue);
    expect(j.estAucun, isFalse);
    expect(j.heuresTravaillees, isNull);
    expect(j.heuresVoyagementPayees, 0);
    expect(j.heuresFeriees, 8);
    expect(j.estRempli, isTrue);
    expect(_jour().heuresFeriees, 0);
  });

  test("heures en banque : remplie seulement avec un nombre d'heures", () {
    final j = _jour()..chantier = chantierBanque;
    expect(j.estBanque, isTrue);
    expect(j.estFerie, isFalse);
    expect(j.heuresTravaillees, isNull);
    expect(j.heuresVoyagementPayees, 0);
    expect(j.heuresFeriees, 0);
    expect(j.estRempli, isFalse); // pas encore d'heures
    j.heuresBanque = 7.5;
    expect(j.estRempli, isTrue);
    j.vider();
    expect(j.heuresBanque, isNull);
    expect(j.estBanque, isFalse);
  });

  test('heures en banque : lecture du nombre entré', () {
    expect(lireHeuresBanque('8'), 8);
    expect(lireHeuresBanque(' 3,5 '), 3.5);
    expect(lireHeuresBanque('7.25'), 7.25);
    expect(lireHeuresBanque('24'), 24);
    expect(lireHeuresBanque('0'), isNull);
    expect(lireHeuresBanque('-2'), isNull);
    expect(lireHeuresBanque('25'), isNull);
    expect(lireHeuresBanque('abc'), isNull);
    expect(lireHeuresBanque(''), isNull);
    expect(heuresBanqueAffichees(8), '8');
    expect(heuresBanqueAffichees(3.5), '3,5');
  });

  test('vider : la journée supprimée redevient vide (et modifiable)', () {
    final j = _jour()
      ..verrouilleLocalement = true
      ..pauseMatin = false;
    j.vider();
    expect(j.chantier, isNull);
    expect(j.heureDebut, isNull);
    expect(j.heureFin, isNull);
    expect(j.tempsVoyagement, isNull);
    expect(j.pauseMatin, isTrue);
    expect(j.verrouilleLocalement, isFalse);
    expect(j.aDesDonnees, isFalse);
    expect(j.estRempli, isFalse);
  });

  test(
    'supprimer le jeudi : seul le jeudi est effacé, les autres partent vides',
    () {
      expect(joursPourSuppression(5, 3), [
        {'estAucun': false},
        {'estAucun': false},
        {'estAucun': false},
        {'effacer': true},
        {'estAucun': false},
      ]);
    },
  );
}
