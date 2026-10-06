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

  test('jusqu\'au seuil : rien ; au-delà : seulement l\'excédent, au pourcentage', () => {
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 59 })], avec()).totalVoyagementPaye, 0);
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 60 })], avec()).totalVoyagementPaye, 0);
    // 90 min, seuil 60 : 30 min payées à 50 % = 15 min.
    const r = calcul([jour({ tempsVoyagementMinutes: 90 })], avec());
    assert.equal(r.jours[0].voyagementPayeHeures, 0.25);
    assert.equal(r.totalHeures, 7.75 + 0.25);
  });

  test('exemples de l\'entrepreneur : 2 h de voyagement', () => {
    // À partir de 60 min : 1 h payée au pourcentage choisi.
    const a = calcul([jour({ tempsVoyagementMinutes: 120 })], avec({ voyagementPourcentage: 100 }));
    assert.equal(a.jours[0].voyagementPayeHeures, 1);
    const a50 = calcul([jour({ tempsVoyagementMinutes: 120 })], avec({ voyagementPourcentage: 50 }));
    assert.equal(a50.jours[0].voyagementPayeHeures, 0.5);
    // À partir de 30 min : 1 h 30 payée au pourcentage choisi.
    const b = calcul([jour({ tempsVoyagementMinutes: 120 })], avec({ voyagementSeuilMinutes: 30, voyagementPourcentage: 100 }));
    assert.equal(b.jours[0].voyagementPayeHeures, 1.5);
    const b50 = calcul([jour({ tempsVoyagementMinutes: 120 })], avec({ voyagementSeuilMinutes: 30, voyagementPourcentage: 50 }));
    assert.equal(b50.jours[0].voyagementPayeHeures, 0.75);
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementPourcentage: 100 }), 120), 60);
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementSeuilMinutes: 30, voyagementPourcentage: 100 }), 120), 90);
  });

  test('seuil à 0 : tout le voyagement est payé au pourcentage', () => {
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementSeuilMinutes: 0, voyagementPourcentage: 50 }), 120), 60);
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementSeuilMinutes: 0 }), 0), 0);
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementSeuilMinutes: 0 }), null), 0);
  });

  test('pourcentage à 0 : rien de payé ; désactivé : rien de payé', () => {
    assert.equal(ft.minutesVoyagementPayees(avec({ voyagementPourcentage: 0 }), 300), 0);
    assert.equal(ft.minutesVoyagementPayees(ft.reglesPaieDepuis({ voyagementActif: false }), 300), 0);
  });

  test('le seuil s\'applique par jour', () => {
    const r = calcul([jour({ tempsVoyagementMinutes: 40 }), jour({ tempsVoyagementMinutes: 40 })], avec());
    assert.equal(r.totalVoyagementPaye, 0);
  });

  test('seuil et pourcentage configurables', () => {
    const regles = avec({ voyagementSeuilMinutes: 30, voyagementPourcentage: 100 });
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 30 })], regles).totalVoyagementPaye, 0);
    assert.equal(calcul([jour({ tempsVoyagementMinutes: 90 })], regles).totalVoyagementPaye, 1);
  });

  test('le voyagement de la semaine : chaque jour à part, puis additionné', () => {
    // Lundi 2 h et mardi 45 min, seuil 60 min à 100 % : 60 min + 0.
    const r = calcul([jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 45 })],
      avec({ voyagementPourcentage: 100 }));
    assert.equal(r.totalVoyagementPaye, 1);
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
    assert.equal(r.totalVoyagementPaye, 0.25);
    assert.equal(r.totalHeures, 7.75 + 0.25 + 7.75);
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

describe('Chantiers archivés', () => {
  const archives = new Set(['ch2']);
  const avecArchives = (jours, existante) => ft.calculerFeuille({
    jours: ft.lireJours(jours), nomsChantiers: NOMS, archives, regles: defaut, existante,
    maintenantIso: '2026-01-06T12:00:00.000Z',
  });

  test('un chantier archivé ne peut pas être choisi pour une journée', () => {
    rejette(() => avecArchives([jour({ chantierId: 'ch2' })]));
  });

  test('une journée déjà enregistrée avec ce chantier peut être renvoyée telle quelle', () => {
    const avant = calcul([jour({ chantierId: 'ch2' })]);
    const r = avecArchives([jour({ chantierId: 'ch2' })], { jours: avant.jours });
    assert.equal(r.jours[0].chantierNom, 'Chantier 2');
    assert.equal(r.totalHeures, 7.75);
  });

  test('changer une journée vers un chantier archivé reste refusé', () => {
    const avant = calcul([jour({ chantierId: 'ch1' })]);
    rejette(() => avecArchives([jour({ chantierId: 'ch2' })], { jours: avant.jours }));
  });

  test('les chantiers actifs ne sont pas touchés', () => {
    assert.equal(avecArchives([jour({ chantierId: 'ch1' })]).totalHeures, 7.75);
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

// Changement des règles de paie : la semaine courante s'ajuste, jamais les semaines passées.
describe('Semaines précédentes : jamais modifiées par un changement de règles', () => {
  const anciennes = ft.reglesPaieDepuis({ voyagementActif: true, voyagementSeuilMinutes: 60, voyagementPourcentage: 50 });
  const nouvelles = ft.reglesPaieDepuis({ voyagementActif: true, voyagementSeuilMinutes: 30, voyagementPourcentage: 100 });
  const avecFigee = (jours, regles, existante, semaineFigee) => ft.calculerFeuille({
    jours: ft.lireJours(jours), nomsChantiers: NOMS, regles, existante, semaineFigee,
    maintenantIso: '2026-01-06T12:00:00.000Z',
  });
  const semainePassee = () => avecFigee(
    [jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 90 })], anciennes, undefined, true);

  test('les valeurs de départ (anciennes règles)', () => {
    const r = semainePassee();
    assert.equal(r.jours[0].voyagementPayeHeures, 0.5); // 60 min à 50 %
    assert.equal(r.jours[1].voyagementPayeHeures, 0.25); // 30 min à 50 %
  });

  test('semaine passée renvoyée telle quelle avec de nouvelles règles : rien ne change', () => {
    const avant = semainePassee();
    const r = avecFigee([jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 90 })],
      nouvelles, { jours: avant.jours }, true);
    assert.deepEqual(r.jours, avant.jours);
    assert.equal(r.totalVoyagementPaye, avant.totalVoyagementPaye);
    assert.equal(r.totalHeures, avant.totalHeures);
    assert.equal(r.joursRecalcules, 0);
  });

  test('semaine passée : seule la journée modifiée est recalculée, les autres gardent leurs valeurs', () => {
    const avant = semainePassee();
    const r = avecFigee([jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 150 })],
      nouvelles, { jours: avant.jours }, true);
    assert.deepEqual(r.jours[0], avant.jours[0]); // inchangée : 0.5 h d'origine
    assert.equal(r.jours[0].voyagementPayeHeures, 0.5);
    assert.equal(r.jours[1].voyagementPayeHeures, 2); // modifiée : 120 min à 100 %
    assert.equal(r.joursRecalcules, 1);
    assert.equal(r.totalVoyagementPaye, 2.5);
  });

  test('semaine passée, voyagement plus payé aujourd\'hui : les journées inchangées gardent le leur', () => {
    const avant = semainePassee();
    const sans = ft.reglesPaieDepuis({ voyagementActif: false });
    // L'appareil n'offre plus le champ : il envoie le voyagement vide.
    const r = avecFigee([jour(), jour()], sans, { jours: avant.jours }, true);
    assert.deepEqual(r.jours, avant.jours);
    assert.equal(r.totalVoyagementPaye, avant.totalVoyagementPaye);
  });

  test('semaine courante (non figée) : tout est recalculé avec les nouvelles règles', () => {
    const avant = semainePassee();
    const r = avecFigee([jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 90 })],
      nouvelles, { jours: avant.jours }, false);
    assert.equal(r.jours[0].voyagementPayeHeures, 1.5);
    assert.equal(r.jours[1].voyagementPayeHeures, 1);
  });

  test('journée « non travaillée » d\'une semaine passée : conservée', () => {
    const avant = avecFigee([jour({ estAucun: true })], anciennes, undefined, true);
    const r = avecFigee([jour({ estAucun: true })], nouvelles, { jours: avant.jours }, true);
    assert.deepEqual(r.jours, avant.jours);
  });
});

describe('recalculerFeuille : semaine courante après un changement de règles', () => {
  const anciennes = ft.reglesPaieDepuis({ voyagementActif: true, voyagementSeuilMinutes: 60, voyagementPourcentage: 50 });
  const feuilleStockee = (regles = anciennes) => {
    const c = calcul([
      jour({ tempsVoyagementMinutes: 120 }), jour({ tempsVoyagementMinutes: 90, diner: false }),
      jour({ estAucun: true }), { estAucun: false },
    ], regles);
    return {
      jours: c.jours, totalHeures: c.totalHeures, totalHeuresTravaillees: c.totalHeuresTravaillees,
      totalVoyagementPaye: c.totalVoyagementPaye, reglesPaie: regles, companyId: 'A', lundiDate: '2026-01-05',
    };
  };
  const maj = (f, regles) => ft.recalculerFeuille(f, regles, '2026-01-07T09:00:00.000Z');

  test('mêmes règles : rien à écrire', () => {
    assert.equal(maj(feuilleStockee(), anciennes), null);
  });

  test('seuil 60 → 30 min, 100 % : heures de voyagement et totaux ajustés', () => {
    const f = feuilleStockee();
    const nouvelles = ft.reglesPaieDepuis({ voyagementActif: true, voyagementSeuilMinutes: 30, voyagementPourcentage: 100 });
    const r = maj(f, nouvelles);
    assert.equal(r.jours[0].voyagementPayeHeures, 1.5); // 120 − 30 = 90 min à 100 %
    assert.equal(r.jours[1].voyagementPayeHeures, 1); // 90 − 30 = 60 min
    assert.equal(r.totalVoyagementPaye, 2.5);
    assert.equal(r.totalHeuresTravaillees, f.totalHeuresTravaillees);
    assert.equal(r.totalHeures, f.totalHeuresTravaillees + 2.5);
    assert.deepEqual(r.reglesPaie, nouvelles);
    assert.equal(r.recalculeLe, '2026-01-07T09:00:00.000Z');
  });

  test('la saisie et les journées non travaillées ou vides restent intactes', () => {
    const f = feuilleStockee();
    const r = maj(f, ft.reglesPaieDepuis({ voyagementActif: true, voyagementPourcentage: 100 }));
    for (const [i, j] of r.jours.entries()) {
      for (const cle of ['nomJour', 'chantierId', 'chantierNom', 'estAucun', 'heureDebutMinutes', 'heureFinMinutes',
        'pauseMatin', 'diner', 'tempsVoyagementMinutes', 'verrouille']) {
        assert.deepEqual(j[cle], f.jours[i][cle], `jour ${i} ${cle}`);
      }
    }
    assert.equal(r.jours[2].estAucun, true);
    assert.equal(r.jours[3].heuresTravaillees, null);
  });

  test('voyagement désactivé : voyagement payé à 0, la saisie est gardée', () => {
    const f = feuilleStockee();
    const r = maj(f, ft.reglesPaieDepuis({ voyagementActif: false }));
    assert.equal(r.totalVoyagementPaye, 0);
    assert.equal(r.jours[0].voyagementPayeHeures, 0);
    assert.equal(r.jours[0].tempsVoyagementMinutes, 120);
    assert.equal(r.totalHeures, r.totalHeuresTravaillees);
  });

  test('règles de pause : les heures payées sont recalculées aussi', () => {
    const f = feuilleStockee();
    const r = maj(f, ft.reglesPaieDepuis({ voyagementActif: true, dinerPaye: false }));
    assert.equal(r.jours[0].heuresTravaillees, 7.25); // 8 h − pause 15 − dîner 30 (non payé)
  });

  test('aucune journée enregistrée ou feuille absente : rien', () => {
    assert.equal(maj({ jours: [], totalHeures: 0, totalHeuresTravaillees: 0, totalVoyagementPaye: 0, reglesPaie: anciennes }, anciennes), null);
    assert.equal(maj(undefined, anciennes), null);
    assert.equal(maj({}, anciennes), null);
  });

  test('ne modifie jamais la feuille reçue', () => {
    const f = feuilleStockee();
    const copie = JSON.parse(JSON.stringify(f));
    maj(f, ft.reglesPaieDepuis({ voyagementActif: true, voyagementPourcentage: 100 }));
    assert.deepEqual(JSON.parse(JSON.stringify(f)), copie);
  });
});
