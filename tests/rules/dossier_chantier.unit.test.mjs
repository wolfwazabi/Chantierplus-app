// Tests unitaires du résumé et de l'export d'un dossier de chantier (sans émulateur).
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const d = require('../../functions/src/dossier_chantier.js');

const jour = (chantierId, heures, voyage = 0, over = {}) => ({
  chantierId, estAucun: false, heuresTravaillees: heures, voyagementPayeHeures: voyage, ...over,
});
// 2026-10-05 est un lundi.
const feuille = (employeeId, employeeNom, lundiDate, jours) => ({ employeeId, employeeNom, lundiDate, jours });

const FEUILLES = [
  feuille('e1', 'Marie', '2026-10-05', [jour('chA', 7.75), jour('chA', 8, 0.75), jour('chB', 7.75), { estAucun: true }, jour('chA', 4)]),
  feuille('e2', 'Luc', '2026-10-05', [jour('chA', 7.75), jour('chB', 7.75)]),
  feuille('e1', 'Marie', '2026-10-12', [jour('chA', 7.75)]),
];

describe('Heures d\'un chantier', () => {
  test('seulement les journées du chantier, avec la bonne date', () => {
    const l = d.detailHeures(FEUILLES, 'chA');
    assert.deepEqual(l.map((x) => [x.date, x.employeNom, x.heures]), [
      ['2026-10-05', 'Luc', 7.75], ['2026-10-05', 'Marie', 7.75],
      ['2026-10-06', 'Marie', 8], ['2026-10-09', 'Marie', 4], ['2026-10-12', 'Marie', 7.75],
    ]);
  });

  test('totaux, par employé, période et jours', () => {
    const r = d.resumerHeures(d.detailHeures(FEUILLES, 'chA'));
    assert.equal(r.totalHeures, 35.25);
    assert.equal(r.totalVoyagementPaye, 0.75);
    assert.equal(r.journeesHomme, 5);
    assert.equal(r.joursTravailles, 4);
    assert.equal(r.premierJour, '2026-10-05');
    assert.equal(r.dernierJour, '2026-10-12');
    assert.deepEqual(r.parEmploye.map((e) => [e.nom, e.heures, e.voyagementPaye, e.jours]), [
      ['Marie', 27.5, 0.75, 4], ['Luc', 7.75, 0, 1],
    ]);
  });

  test('chantier sans heures : totaux à zéro, pas de période', () => {
    const r = d.resumerHeures(d.detailHeures(FEUILLES, 'chZ'));
    assert.equal(r.totalHeures, 0);
    assert.equal(r.premierJour, null);
    assert.deepEqual(r.parEmploye, []);
  });

  test('données abîmées ignorées sans planter', () => {
    const l = d.detailHeures([null, { lundiDate: 'n/importe/quoi', jours: [] }, { lundiDate: '2026-10-05', jours: 'x' },
      feuille('e1', 'M', '2026-10-05', [null, jour('chA', 'beaucoup'), jour('chA', 3)])], 'chA');
    assert.equal(l.length, 2);
    assert.equal(l[0].heures, 0);
    assert.equal(l[1].heures, 3);
  });

  test('une journée « non travaillée » n\'est jamais comptée', () => {
    const l = d.detailHeures([feuille('e1', 'M', '2026-10-05', [jour('chA', 8, 0, { estAucun: true })])], 'chA');
    assert.equal(l.length, 0);
  });
});

describe('Chemins de fichiers', () => {
  test('chemin tiré d\'une URL de téléchargement', () => {
    assert.equal(d.cheminDepuisUrl('https://firebasestorage.googleapis.com/v0/b/b/o/chantiers%2FA%2FchA%2Fchantier_materiel%2F1_x.jpg?alt=media&token=t'),
      'chantiers/A/chA/chantier_materiel/1_x.jpg');
    assert.equal(d.cheminDepuisUrl('https://exemple.com/pas-storage'), null);
    assert.equal(d.cheminDepuisUrl(null), null);
    assert.equal(d.cheminDepuisUrl('https://x/o/%E0%A4%A'), null);
  });

  test('un fichier n\'est lu que dans le dossier de CE chantier de CETTE compagnie', () => {
    const ok = (c) => d.cheminDuChantier(c, 'A', 'chA');
    assert.ok(ok('chantiers/A/chA/photos/1.jpg'));
    assert.ok(ok('chantiers/A/chA/chantier_extras/2.jpg'));
    for (const mauvais of [
      'chantiers/B/chB/photos/1.jpg', 'chantiers/A/chB/photos/1.jpg', 'chantiers/A/chA/../chB/photos/1.jpg',
      'chantiers/A/chA//photos/1.jpg', 'chantiers\\A\\chA\\photos\\1.jpg', 'exports/A/x.zip', '', null, 5,
      'chantiers/A/chAA/photos/1.jpg', 'chantiers/AA/chA/photos/1.jpg', 'x'.repeat(601),
    ]) {
      assert.equal(ok(mauvais), false, String(mauvais));
    }
  });

  test('noms de fichiers sûrs pour le ZIP', () => {
    assert.equal(d.nomSur('Rénovation / Salle de bain : #2'), 'Renovation _ Salle de bain _ _2');
    assert.equal(d.nomSur('../../etc/passwd'), '.._.._etc_passwd');
    for (const piege of ['../x', 'a/../b', 'C:\\Windows\\x', '/etc/passwd']) {
      const n = d.nomSur(piege);
      assert.ok(!n.includes('/') && !n.includes('\\'), piege);
    }
    assert.equal(d.nomSur('..'), 'fichier');
    assert.equal(d.nomSur(''), 'fichier');
    assert.ok(d.nomSur('x'.repeat(500)).length <= 80);
    assert.equal(d.extension('chantiers/A/chA/photos/12_p.JPEG'), 'jpeg');
    assert.equal(d.extension('sans_extension'), 'jpg');
  });
});

describe('Noms des documents dans le ZIP', () => {
  const noms = (liste) => { const deja = new Set(); return liste.map((n) => d.nomFichierDocument(n, deja)); };

  test('le nom d\'origine est conservé, accents compris', () => {
    assert.deepEqual(noms(['Devis rénovation.pdf', 'Plan_étage 2.dwg']), ['Devis rénovation.pdf', 'Plan_étage 2.dwg']);
  });

  test('doublons : « (2) », « (3) », sans écraser (insensible à la casse)', () => {
    assert.deepEqual(noms(['plan.pdf', 'Plan.PDF', 'plan.pdf', 'sans_extension', 'sans_extension']),
      ['plan.pdf', 'Plan (2).PDF', 'plan (3).pdf', 'sans_extension', 'sans_extension (2)']);
  });

  test('aucun séparateur de dossier ni caractère interdit : pas de sortie du dossier du ZIP', () => {
    for (const piege of ['../../etc/passwd', '..\\..\\Windows\\x.dll', '/absolu.pdf', 'C:\\x.pdf', 'a/b/c.pdf', 'x:y*z?.pdf', '<script>.pdf', '..', '...', '.cache']) {
      const n = noms([piege])[0];
      assert.ok(!/[\\/:*?"<>|]/.test(n), piege + ' → ' + n);
      assert.ok(!n.startsWith('.'), piege + ' → ' + n);
      assert.ok(n.length > 0);
    }
    assert.equal(noms(['..'])[0], 'document');
  });

  test('noms réservés de Windows, vides, très longs, contrôles', () => {
    assert.equal(noms(['CON.txt'])[0], '_CON.txt');
    assert.equal(noms(['nul'])[0], '_nul');
    assert.equal(noms([''])[0], 'document');
    assert.equal(noms([null])[0], 'document');
    assert.ok(noms(['x'.repeat(400) + '.pdf'])[0].length <= 150);
    assert.equal(noms(['a\u0000b\u001Fc.pdf'])[0], 'a_b_c.pdf');
  });

  test('taille lisible', () => {
    assert.equal(d.tailleLisible(500), '500 o');
    assert.equal(d.tailleLisible(850 * 1024), '850 Ko');
    assert.equal(d.tailleLisible(12.4 * 1024 * 1024), '12,4 Mo');
    assert.equal(d.tailleLisible(undefined), '');
    assert.equal(d.tailleLisible(-1), '');
  });
});

describe('Résumé HTML', () => {
  const base = () => ({
    compagnie: 'Alpha inc.', chantier: { nom: 'Chalet <b>Nord</b>', adresse: '1 rue "A"', archive: true },
    dateExport: '2026-10-30T12:00:00Z',
    heures: d.resumerHeures(d.detailHeures(FEUILLES, 'chA')),
    extras: [{ dateTravaux: '2026-10-08', description: 'Cloison <script>alert(1)</script>', mainOeuvre: '3 gars, 4 h', ajouteParNom: 'Plus A', fichierPhoto: 'extras/001.jpg' }],
    materiel: [{ texte: 'Vis 3"', quantite: '2 boîtes', complete: false, dateAjout: '2026-10-07', fichierPhoto: null }],
    travaux: [{ texte: 'Peinture <i>plafond</i>', complete: true, dateAjout: '2026-10-02', dateComplete: '2026-10-09', fichierPhoto: 'travaux/travail_001.jpg' },
      { texte: 'Calfeutrage', complete: false, dateAjout: '2026-10-03', dateComplete: '', fichierPhoto: null }],
    documents: [{ nom: 'Devis rénovation.pdf', taille: 850 * 1024, dateAjout: '2026-10-01', fichier: 'documents/Devis rénovation.pdf' },
      { nom: 'Gros plan.dwg', taille: 60 * 1024 * 1024, dateAjout: '2026-10-02', fichier: null }],
    photos: 12, ignores: [],
  });

  test('contenu : totaux, extras, matériel, photos, archivé', () => {
    const h = d.htmlResume(base());
    for (const attendu of ['35,25', '0,75', '(archivé)', 'Marie', 'Luc', '08/10/2026', '3 gars, 4 h',
      'À obtenir', 'Photos du chantier (12)', 'href="extras/001.jpg"', 'lang="fr"',
      'Travaux à compléter (2)', 'Complété le 09/10/2026', 'À compléter', 'href="travaux/travail_001.jpg"',
      'Documents (2)', 'Devis rénovation.pdf', '850 Ko', 'Inclus', 'Non inclus', 'Dossier.xlsx']) {
      assert.ok(h.includes(attendu), attendu);
    }
  });

  test('tout texte saisi est échappé (aucun HTML ni script ne passe)', () => {
    const h = d.htmlResume(base());
    assert.ok(!h.includes('<script>'));
    assert.ok(!h.includes('<b>Nord</b>'));
    assert.ok(h.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
    assert.ok(h.includes('Chalet &lt;b&gt;Nord&lt;/b&gt;'));
    assert.ok(h.includes('Vis 3&quot;'));
  });

  test('fichiers ignorés signalés ; chantier sans rien', () => {
    const b = base();
    b.ignores = ['photos/gros.jpg'];
    assert.ok(d.htmlResume(b).includes('Fichiers non inclus'));
    const vide = { ...b, ignores: [], extras: [], materiel: [], photos: 0, chantier: { nom: 'X', adresse: '', archive: false },
      heures: d.resumerHeures([]) };
    const h = d.htmlResume(vide);
    assert.ok(h.includes('aucune heure saisie'));
    assert.ok(h.includes('Aucun extra.'));
    assert.ok(h.includes('Aucun matériel.'));
    assert.ok(!h.includes('(archivé)'));
  });

  test('liens vers les fichiers : chemin encodé, relatif, jamais d\'autre schéma', () => {
    const h = d.htmlResume(base());
    assert.ok(h.includes('href="documents/Devis%20r%C3%A9novation.pdf"'));
    const b = base();
    b.documents = [{ nom: 'x', taille: 1, dateAjout: '', fichier: 'javascript:alert(1)' }];
    const h2 = d.htmlResume(b);
    assert.ok(!/href="javascript:/.test(h2), 'le schéma javascript: ne doit pas rester dans un href');
    b.documents = [{ nom: '"><script>x</script>', taille: 1, dateAjout: '', fichier: 'documents/a"b.pdf' }];
    const h3 = d.htmlResume(b);
    assert.ok(!h3.includes('<script>x</script>'));
    assert.ok(h3.includes('documents/a%22b.pdf'));
  });

  test('travaux et documents échappés ; sections vides', () => {
    const h = d.htmlResume(base());
    assert.ok(h.includes('Peinture &lt;i&gt;plafond&lt;/i&gt;'));
    const vide = { ...base(), ignores: [], extras: [], materiel: [], travaux: [], documents: [], photos: 0,
      chantier: { nom: 'X', adresse: '', archive: false }, heures: d.resumerHeures([]) };
    const hv = d.htmlResume(vide);
    assert.ok(hv.includes('Aucun travail à compléter.'));
    assert.ok(hv.includes('Aucun document.'));
    // Anciens appels sans travaux ni documents : toujours valides.
    const { travaux, documents, ...ancien } = vide;
    assert.ok(d.htmlResume(ancien).includes('Documents (0)'));
  });
});
