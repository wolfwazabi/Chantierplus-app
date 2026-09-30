// Tests unitaires du calcul de la feuille de temps côté serveur (sans émulateur).
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ft = require('../../functions/src/feuille_temps.js');

const H = (h, m = 0) => h * 60 + m;
const defaut = ft.reglesPaieDepuis(undefined);
const NOMS = new Map([['ch1', 'Chantier 1'], ['ch2', 'Chantier 2']]);

const jour = (over = {}) => ({
  estAucun: false, chantierId: 'ch1', heureDebutMinutes: H(7), heureFinMinutes: H(15),
  pauseMatin: true, diner: true, tempsVoyagementMinutes: null, ...over,
});
const calcul = (jours, regles = defaut, existante = undefined) => ft.calculerFeuille({
  jours: ft.lireJours(jours), nomsChantiers: NOMS, regles, existante, maintenantIso: '2026-01-06T12:00:00.000Z',
});
const rejette = (fn, code = 'invalid-argument') =>
  assert.throws(fn, (e) => { assert.equal(e.code, code, e.message); return true; });

describe('Règles de paie lues de la compagnie', () => {
  test('absentes ou invalides : valeurs par défaut', () => {
    assert.deepEqual(ft.reglesPaieDepuis(undefined), ft.REGLES_DEFAUT);
    assert.deepEqual(ft.reglesPaieDepuis({ dinerMinutes: 999, voyagementPourcentage: -3, dinerPaye: 'oui', pauseMatinMinutes: 7.5 }), ft.REGLES_DEFAUT);
    assert.equal(ft.reglesPaieDepuis({ dinerMinutes: 45 }).dinerMinutes, 45);
  });
});

describe('Heures payées d\'une journée', () => {
  test('7 h à 15 h, pause (non payée) et dîner (payé) pris = 7 h 45', () => {
    const r = calcul([jour()]);
    assert.equal(r.jours[0].heuresTravaillees, 7.75);
    assert.equal(r.totalHeuresTravaillees, 7.75);
    assert.equal(r.totalHeures, 7.75);
  });

  test('dîner non pris : +30 min ; pause non prise : rien à retirer', () => {
    assert.equal(calcul([jour({ diner: false })]).totalHeures, 8.25);
    assert.equal(calcul([jour({ pauseMatin: false })]).totalHeures, 8);
    assert.equal(calcul([jour({ pauseMatin: false, diner: false })]).totalHeures, 8.5);
  });

  test('pauses configurées : dîner non payé, pause payée', () => {
    const r = ft.reglesPaieDepuis({ dinerPaye: false, dinerMinutes: 45, pauseMatinPayee: true });
    // 8 h − 45 min (dîner non payé pris) ; pause payée prise : aucun ajustement.
    assert.equal(calcul([jour()], r).totalHeures, 7.25);
  });

  test('jour non travaillé : 0 h, « Jour non travaillé » ; jour vide : ignoré', () => {
    const r = calcul([jour({ estAucun: true }), { estAucun: false }, jour()]);
    assert.equal(r.totalHeures, 7.75);
    assert.equal(r.jours[0].chantierNom, 'Jour non travaillé');
    assert.equal(r.jours[0].heuresTravaillees, null);
    assert.equal(r.jours[0].verrouille, true);
    assert.equal(r.jours[1].verrouille, false);
    assert.equal(r.jours[1].heuresTravaillees, null);
    assert.equal(r.jours[2].nomJour, 'Mercredi');
  });

  test('le nom du chantier vient du serveur', () => {
    assert.equal(calcul([jour({ chantierNom: 'Faux nom' })]).jours[0].chantierNom, 'Chantier 1');
  });

  test('les valeurs calculées envoyées par le client sont ignorées', () => {
    const r = calcul([jour({ heuresTravaillees: 99, voyagementPayeHeures: 50, verrouille: false, totalHeures: 500 })]);
    assert.equal(r.jours[0].heuresTravaillees, 7.75);
    assert.equal(r.jours[0].voyagementPayeHeures, 0);
    assert.equal(r.totalHeures, 7.75);
  });
});

describe('Voyagement payé', () => {
  const avec = (over) => ft.reglesPaieDepuis({ voyagementActif: true, ...over });

  test('désactivé : ignoré et non conservé', () => {
    const r = calcul([jour({ tempsVoyagementMinutes: 120 })]);
    assert.equal(r.totalVoyagementPaye, 0);
    assert.equal(r.jours[0].tempsVoyagementMinutes, null);
  });

  test('sous le seuil : rien ; au seuil : pourcentage de tout', () => {
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 59 })], avec()).totalVoyagementPaye, 0);
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 60 })], avec()).totalVoyagementPaye, 0.5);
    const r = calcul([jour({ tempsVoyagementMinutes: 90 })], avec());
    assert.equal(r.jours[0].voyagementPayeHeures, 0.75);
    assert.equal(r.totalHeures, 7.75 + 0.75);
  });

  test('le seuil s\'applique par jour', () => {
    const r = calcul([jour({ tempsVoyagementMinutes: 40 }), jour({ tempsVoyagementMinutes: 40 })], avec());
    assert.equal(r.totalVoyagementPaye, 0);
  });

  test('seuil et pourcentage configurables', () => {
    const r = calcul([jour({ tempsVoyagementMinutes: 30 })], avec({ voyagementSeuilMinutes: 30, voyagementPourcentage: 100 }));
    assert.equal(r.totalVoyagementPaye, 0.5);
  });
});

describe('Validation de la saisie', () => {
  test('heures incohérentes ou hors plage : refusées', () => {
    rejette(() => ft.lireJours([jour({ heureFinMinutes: H(7) })]));
    rejette(() => ft.lireJours([jour({ heureFinMinutes: H(6) })]));
    rejette(() => ft.lireJours([jour({ heureFinMinutes: 1440 })]));
    rejette(() => ft.lireJours([jour({ heureDebutMinutes: -1 })]));
    rejette(() => ft.lireJours([jour({ heureDebutMinutes: 420.5 })]));
    rejette(() => ft.lireJours([jour({ heureDebutMinutes: '420' })]));
  });

  test('journée incomplète : refusée', () => {
    rejette(() => ft.lireJours([jour({ heureFinMinutes: null })]));
    rejette(() => ft.lireJours([jour({ chantierId: null })]));
    rejette(() => ft.lireJours([jour({ chantierId: 'a/b' })]));
  });

  test('voyagement invalide ou > 12 h, booléens invalides : refusés', () => {
    rejette(() => ft.lireJours([jour({ tempsVoyagementMinutes: -5 })]));
    rejette(() => ft.lireJours([jour({ tempsVoyagementMinutes: 721 })]));
    rejette(() => ft.lireJours([jour({ diner: 'oui' })]));
    ft.lireJours([jour({ tempsVoyagementMinutes: 720 })]);
  });

  test('nombre de jours : 1 à 7', () => {
    rejette(() => ft.lireJours([]));
    rejette(() => ft.lireJours(Array(8).fill(jour())));
    rejette(() => ft.lireJours('lundi'));
    rejette(() => ft.lireJours([null]));
    ft.lireJours(Array(7).fill(jour()));
  });

  test('semaine : date réelle qui tombe un lundi', () => {
    ft.analyserLundi('2026-01-05');
    rejette(() => ft.analyserLundi('2026-01-06'));
    rejette(() => ft.analyserLundi('2026-02-30'));
    rejette(() => ft.analyserLundi('26-01-05'));
    rejette(() => ft.analyserLundi(20260105));
    rejette(() => ft.analyserLundi('1999-01-04'));
  });
});

describe('Trace des corrections après soumission', () => {
  const existante = (over = {}) => ({
    jours: [{ ...calcul([jour()]).jours[0], ...over }],
  });

  test('journée soumise puis modifiée : date de la modification consignée', () => {
    const r = calcul([jour({ heureFinMinutes: H(16) })], defaut, existante());
    assert.equal(r.jours[0].modifieApresVerrouillageLe, '2026-01-06T12:00:00.000Z');
  });

  test('journée inchangée : aucune trace ; ancienne trace conservée', () => {
    assert.equal(calcul([jour()], defaut, existante()).jours[0].modifieApresVerrouillageLe, undefined);
    const r = calcul([jour()], defaut, existante({ modifieApresVerrouillageLe: '2026-01-01T00:00:00.000Z' }));
    assert.equal(r.jours[0].modifieApresVerrouillageLe, '2026-01-01T00:00:00.000Z');
  });
});

describe('Une journée vide n\'efface jamais une journée enregistrée', () => {
  const enregistree = () => calcul([jour(), jour({ heureFinMinutes: H(16) })]);

  test('lundi et mardi déjà soumis, envoi avec seulement le mercredi : tout est conservé', () => {
    const avant = enregistree();
    const r = calcul([{ estAucun: false }, { estAucun: false }, jour()], defaut, { jours: avant.jours });
    assert.equal(r.jours.length, 3);
    assert.deepEqual(r.jours[0], avant.jours[0]);
    assert.deepEqual(r.jours[1], avant.jours[1]);
    assert.equal(r.jours[2].heuresTravaillees, 7.75);
    assert.equal(r.totalHeures, 7.75 + 8.75 + 7.75);
    assert.equal(r.totalHeuresTravaillees, 7.75 + 8.75 + 7.75);
  });

  test('journée « non travaillée » conservée aussi', () => {
    const avant = calcul([jour({ estAucun: true })]);
    const r = calcul([{ estAucun: false }], defaut, { jours: avant.jours });
    assert.equal(r.jours[0].estAucun, true);
    assert.equal(r.jours[0].chantierNom, 'Jour non travaillé');
  });

  test('le voyagement payé d\'une journée conservée reste dans les totaux', () => {
    const regles = ft.reglesPaieDepuis({ voyagementActif: true });
    const avant = calcul([jour({ tempsVoyagementMinutes: 90 })], regles);
    const r = calcul([{ estAucun: false }, jour()], regles, { jours: avant.jours });
    assert.equal(r.totalVoyagementPaye, 0.75);
    assert.equal(r.totalHeures, 7.75 + 0.75 + 7.75);
  });

  test('journées enregistrées au-delà de celles reçues : conservées', () => {
    const avant = calcul(Array(5).fill(jour()));
    const r = calcul([jour()], defaut, { jours: avant.jours });
    assert.equal(r.jours.length, 5);
    assert.equal(r.totalHeures, 7.75 * 5);
  });

  test('une journée modifiée (pas vide) remplace bien l\'ancienne', () => {
    const avant = enregistree();
    const r = calcul([jour({ heureFinMinutes: H(14) })], defaut, { jours: avant.jours });
    assert.equal(r.jours[0].heuresTravaillees, 6.75);
    assert.equal(r.totalHeures, 6.75 + 8.75);
  });
});

describe('Échéance (mardi suivant, 18 h à Montréal)', () => {
  const utc = (iso) => Date.parse(iso);

  test('hiver (heure normale, UTC−5) : 23 h UTC', () => {
    assert.equal(ft.echeanceSemaine('2026-01-05'), utc('2026-01-13T23:00:00Z'));
  });

  test('été (heure avancée, UTC−4) : 22 h UTC', () => {
    assert.equal(ft.echeanceSemaine('2026-07-06'), utc('2026-07-14T22:00:00Z'));
  });

  test('semaines de changement d\'heure', () => {
    assert.equal(ft.echeanceSemaine('2026-03-02'), utc('2026-03-10T22:00:00Z')); // début heure avancée le 8 mars
    assert.equal(ft.echeanceSemaine('2026-10-26'), utc('2026-11-03T23:00:00Z')); // fin le 1er novembre
  });

  test('lundi courant selon le fuseau (et non l\'UTC)', () => {
    // Lundi 2026-01-05 à 01 h UTC = dimanche soir à Montréal → semaine du 29 décembre.
    assert.equal(ft.lundiCourant(utc('2026-01-05T01:00:00Z')), '2025-12-29');
    assert.equal(ft.lundiCourant(utc('2026-01-05T06:00:00Z')), '2026-01-05');
    assert.equal(ft.lundiCourant(utc('2026-01-11T12:00:00Z')), '2026-01-05');
  });
});
