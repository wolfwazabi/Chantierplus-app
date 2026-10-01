// Tests du classeur Excel (.xlsx) généré côté serveur. Le fichier est relu avec
// une bibliothèque indépendante (exceljs) pour vérifier qu'il est bien formé.
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import ExcelJS from 'exceljs';

const require = createRequire(import.meta.url);
const x = require('../../functions/src/xlsx.js');

const lire = async (buffer) => {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  return wb;
};

const heures = {
  nom: 'Heures',
  colonnes: [
    { titre: 'Date', cle: 'date', type: 'date', largeur: 14 },
    { titre: 'Employé', cle: 'nom' },
    { titre: 'Heures travaillées', cle: 'h', type: 'nombre' },
  ],
  lignes: [
    { date: '2026-10-05', nom: 'Marie Tremblay', h: 7.75 },
    { date: '2026-10-06', nom: 'Luc', h: 8 },
  ],
  total: { libelle: 'Total', valeurs: { h: 15.75 } },
};

describe('Classeur Excel', () => {
  test('fichier bien formé : onglets, en-têtes, valeurs', async () => {
    const wb = await lire(await x.classeur([heures, { nom: 'Extras', colonnes: [{ titre: 'Description', cle: 'd' }], lignes: [{ d: 'Cloison' }] }]));
    assert.deepEqual(wb.worksheets.map((w) => w.name), ['Heures', 'Extras']);
    const ws = wb.getWorksheet('Heures');
    assert.deepEqual(ws.getRow(1).values.slice(1), ['Date', 'Employé', 'Heures travaillées']);
    assert.equal(ws.getRow(3).getCell(2).value, 'Luc');
    assert.equal(wb.getWorksheet('Extras').getCell('A2').value, 'Cloison');
  });

  test('les nombres sont de vrais nombres (pas du texte) : même résultat en français et en anglais', async () => {
    const ws = (await lire(await x.classeur([heures]))).getWorksheet('Heures');
    assert.equal(typeof ws.getCell('C2').value, 'number');
    assert.equal(ws.getCell('C2').value, 7.75);
    assert.equal(ws.getCell('C3').value, 8);
    // Ligne de total, en gras.
    assert.equal(ws.getCell('A4').value, 'Total');
    assert.equal(ws.getCell('C4').value, 15.75);
    assert.equal(ws.getCell('C4').font.bold, true);
  });

  test('les dates sont de vraies dates (Excel les affiche selon la langue)', async () => {
    const ws = (await lire(await x.classeur([heures]))).getWorksheet('Heures');
    const d = ws.getCell('A2').value;
    assert.ok(d instanceof Date, 'cellule de type date');
    assert.equal(d.toISOString().slice(0, 10), '2026-10-05');
    assert.equal(x.serieDate('1900-03-01'), 61);
    assert.equal(x.serieDate('2026-10-05'), 46300);
    assert.equal(x.serieDate('pas une date'), null);
  });

  test('un texte qui commence par = + - @ reste du texte : aucune formule', async () => {
    const wb = await lire(await x.classeur([{
      nom: 'T', colonnes: [{ titre: 'Texte', cle: 't' }],
      lignes: ['=SOMME(A1:A9)', '+1+1', '-2+3', '@HYPERLINK("http://x")', '=cmd|\'/c calc\'!A0'].map((t) => ({ t })),
    }]));
    const ws = wb.getWorksheet('T');
    for (let r = 2; r <= 6; r++) {
      const c = ws.getCell(`A${r}`);
      assert.equal(typeof c.value, 'string', `ligne ${r}`);
      assert.notEqual(c.type, ExcelJS.ValueType.Formula);
    }
    assert.equal(ws.getCell('A2').value, '=SOMME(A1:A9)');
  });

  test('caractères spéciaux : accents, guillemets, & < >, retours à la ligne, emoji', async () => {
    const texte = 'Cloison "A" & <B>\nligne 2 — é à ç 🙂';
    const ws = (await lire(await x.classeur([{ nom: 'S', colonnes: [{ titre: 'T', cle: 't' }], lignes: [{ t: texte }] }]))).getWorksheet('S');
    assert.equal(ws.getCell('A2').value, texte);
  });

  test('caractères de contrôle interdits en XML : retirés, le fichier reste valide', async () => {
    const ws = (await lire(await x.classeur([{ nom: 'S', colonnes: [{ titre: 'T', cle: 't' }], lignes: [{ t: 'a\u0000b\u0008c\u001Fd￾e' }] }]))).getWorksheet('S');
    assert.equal(ws.getCell('A2').value, 'abcde');
  });

  test('valeurs vides ou invalides : cellules vides, pas d\'erreur', async () => {
    const ws = (await lire(await x.classeur([{
      nom: 'V', colonnes: [{ titre: 'N', cle: 'n', type: 'nombre' }, { titre: 'D', cle: 'd', type: 'date' }, { titre: 'T', cle: 't' }],
      lignes: [{ n: null, d: null, t: null }, { n: NaN, d: 'bientôt', t: '' }, { n: Infinity }],
    }]))).getWorksheet('V');
    assert.equal(ws.getCell('A2').value, null);
    assert.equal(ws.getCell('A3').value, null);
    assert.equal(ws.getCell('B3').value, 'bientôt');
    assert.equal(ws.getCell('A4').value, null);
  });

  test('noms d\'onglets : caractères interdits, longueur, doublons, vide', async () => {
    const wb = await lire(await x.classeur([
      { nom: 'Matériel / [test]: *?', colonnes: [{ titre: 'A', cle: 'a' }], lignes: [] },
      { nom: 'x'.repeat(50), colonnes: [{ titre: 'A', cle: 'a' }], lignes: [] },
      { nom: 'x'.repeat(50), colonnes: [{ titre: 'A', cle: 'a' }], lignes: [] },
      { nom: '', colonnes: [{ titre: 'A', cle: 'a' }], lignes: [] },
    ]));
    const noms = wb.worksheets.map((w) => w.name);
    assert.ok(noms.every((n) => n.length > 0 && n.length <= 31), noms.join('|'));
    assert.equal(new Set(noms.map((n) => n.toLowerCase())).size, 4, 'noms uniques');
    assert.ok(!/[[\]:*?/\\]/.test(noms[0]));
  });

  test('onglet sans ligne : en-têtes seulement ; aucun onglet : refusé', async () => {
    const ws = (await lire(await x.classeur([{ nom: 'Vide', colonnes: [{ titre: 'A', cle: 'a' }, { titre: 'B', cle: 'b' }], lignes: [] }]))).getWorksheet('Vide');
    assert.equal(ws.rowCount, 1);
    await assert.rejects(async () => x.classeur([]));
  });

  test('beaucoup de lignes', async () => {
    const lignes = Array.from({ length: 5000 }, (_, i) => ({ date: '2026-10-05', nom: `E${i}`, h: i / 4 }));
    const ws = (await lire(await x.classeur([{ ...heures, lignes, total: undefined }]))).getWorksheet('Heures');
    assert.equal(ws.rowCount, 5001);
    assert.equal(ws.getCell('C5001').value, 4999 / 4);
  });
});
