// Une semaine antérieure garde ses heures et son voyagement payés d'origine : un
// changement des règles de paie ne réécrit jamais le passé. Voir
// functions/src/feuille_temps.js (côté serveur, mêmes règles).
import 'package:construction_app/models/chantier.dart';
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

JourTravail _jour({int voyagementMinutes = 120}) =>
    JourTravail('Lundi')
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

  test('les valeurs d\'origine servent aussi quand la formule a changé depuis', () {
    // Ancienne formule : 90 min à partir de 60, à 50 % = 45 min = 0,75 h. La valeur
    // enregistrée (0,75) reste affichée, même si la nouvelle formule donnerait 0,25.
    AppSession.reglesPaie.value = _anciennes;
    final j = _jour(voyagementMinutes: 90)
      ..figer(heures: 7.75, voyagementPaye: 0.75);
    expect(j.heuresVoyagementPayees, 0.75);
  });

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
}
