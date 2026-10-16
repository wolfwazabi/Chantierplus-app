// Tests unitaires des devis (sans émulateur) : repérage des montants, carrés noirs au bon endroit,
// copie sans texte, devis numérisé ou trop long caché, préparation d'une fiche.
// Les PDF sont fabriqués ici (aucun devis de client dans le dépôt). Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { pdf, fluxDevis, LIGNES_DEVIS as LIGNES } from './pdf_fabrique.mjs';

const require = createRequire(import.meta.url);
const devis = require('../../functions/src/devis.js');
const pdfjs = await import(pathToFileURL(createRequire(require.resolve('../../functions/index.js'))
  .resolve('pdfjs-dist/legacy/build/pdf.mjs')).href);

// Polices standard de pdf.js : sans elles, le texte de l'original ne se dessine pas.
const POLICES = createRequire(require.resolve('../../functions/index.js'))
  .resolve('pdfjs-dist/package.json').replace(/package\.json$/, 'standard_fonts/');

async function ouvrir(octets) {
  return pdfjs.getDocument({ data: new Uint8Array(octets), isEvalSupported: false, standardFontDataUrl: POLICES }).promise;
}

/** Part des pixels foncés dans un rectangle de la page rendue à l'échelle 2 (points PDF). */
async function partFoncee(octets, page, [x1, y1, x2, y2]) {
  const doc = await ouvrir(octets);
  const p = await doc.getPage(page);
  const vue = p.getViewport({ scale: 2 });
  const { canvas, context } = doc.canvasFactory.create(Math.ceil(vue.width), Math.ceil(vue.height));
  await p.render({ canvasContext: context, viewport: vue }).promise;
  const [a, b, c, d] = vue.convertToViewportRectangle([x1, y1, x2, y2]);
  const x = Math.round(Math.min(a, c)), y = Math.round(Math.min(b, d));
  const l = Math.round(Math.abs(c - a)), h = Math.round(Math.abs(d - b));
  const px = context.getImageData(x, y, l, h).data;
  let fonce = 0;
  for (let i = 0; i < px.length; i += 4) if (px[i] < 128 && px[i + 1] < 128 && px[i + 2] < 128) fonce++;
  await doc.destroy();
  void canvas;
  return fonce / (px.length / 4);
}

/** Couleur moyenne (gris de 0 à 255) d'un rectangle de la page rendue. */
async function grisMoyen(octets, page, [x1, y1, x2, y2]) {
  const doc = await ouvrir(octets);
  const p = await doc.getPage(page);
  const vue = p.getViewport({ scale: 2 });
  const { context } = doc.canvasFactory.create(Math.ceil(vue.width), Math.ceil(vue.height));
  await p.render({ canvasContext: context, viewport: vue }).promise;
  const [a, b, c, d] = vue.convertToViewportRectangle([x1, y1, x2, y2]);
  const px = context.getImageData(Math.round(Math.min(a, c)), Math.round(Math.min(b, d)),
    Math.round(Math.abs(c - a)), Math.round(Math.abs(d - b))).data;
  let s = 0;
  for (let i = 0; i < px.length; i += 4) s += (px[i] + px[i + 1] + px[i + 2]) / 3;
  await doc.destroy();
  return s / (px.length / 4);
}

// --- Tests ----------------------------------------------------------------------------------

describe('Devis : le mot dans le nom du fichier', () => {
  test('majuscules et accents ignorés ; ailleurs, pas un devis', () => {
    for (const n of ['Devis cuisine.pdf', 'DEVIS_2026-112.pdf', 'soumission-devis.xlsx', 'Dévis.pdf']) {
      assert.equal(devis.estDevis(n), true, n);
    }
    for (const n of ['Plan étage.pdf', 'Soumission.pdf', 'facture.pdf', '', null]) {
      assert.equal(devis.estDevis(n), false, String(n));
    }
  });
});

describe('Devis : les montants', () => {
  const trouves = (t) => devis.montantsDans(t).map((m) => m.texte);

  test('avec $ (avant ou après) ou à 2 décimales, milliers français ou anglais', () => {
    assert.deepEqual(trouves('Porte 1 234,56 $ pose'), ['1 234,56 $']);
    assert.deepEqual(trouves('Porte 1 234,56 $'), ['1 234,56 $']);
    assert.deepEqual(trouves('Total $1,234.56'), ['$1,234.56']);
    assert.deepEqual(trouves('450 $ et 45$'), ['450 $', '45$']);
    assert.deepEqual(trouves('450.00 + 12,50'), ['450.00', '12,50']);
    assert.deepEqual(trouves('TPS (5 %) : 88,73'), ['88,73']);
    assert.deepEqual(trouves('-$25.00 crédit'), ['-$25.00']);
  });

  test('pas des montants : quantités, dimensions, dates, téléphone, numéro de devis', () => {
    for (const t of ['Qté 6', '2x4 de 8 pi', '30"', '2026-10-16', '514-555-1234', 'DEVIS 2026-112',
      'Taux 14,975 %', 'Lot 1234']) {
      assert.deepEqual(trouves(t), [], t);
    }
  });

  test('rectangles : un par montant, à sa place ; un montant coupé en deux morceaux', () => {
    const item = (str, x, y, largeur) => ({ str, transform: [12, 0, 0, 12, x, y], width: largeur, height: 12 });
    const r = devis.rectanglesMontants([
      item('Porte 30" moulee', 72, 660, 90),
      item('6', 300, 660, 7),
      item('1 234,56 $', 450, 660, 60),
    ]);
    assert.equal(r.montants, 1);
    assert.equal(r.rects.length, 1);
    const [x1, y1, x2, y2] = r.rects[0];
    assert.ok(x1 <= 450 && x1 > 445 && x2 >= 510 && x2 < 515, `x ${x1}..${x2}`);
    assert.ok(y1 < 660 && y2 > 670, `y ${y1}..${y2}`);

    const coupe = devis.rectanglesMontants([item('Total', 72, 600, 30), item('1 774', 450, 600, 30),
      item(',51 $', 480, 600, 25)]);
    assert.equal(coupe.montants, 1);
    assert.equal(coupe.rects.length, 2);
    assert.ok(coupe.rects.every(([x1]) => x1 > 440), 'le mot Total n\'est pas noirci');
  });
});

describe('Devis : la copie sans montants', () => {
  test('montants effacés en blanc, sans trace ; le reste lisible ; aucun texte dans la copie', async () => {
    const original = pdf({ dessin: fluxDevis });
    const r = await devis.copieSansMontants(original);
    assert.equal(r.pages, 1);
    assert.equal(r.montants, 4);
    // La copie est un vrai PDF, de même taille de page, sans couche de texte.
    const doc = await ouvrir(r.pdf);
    assert.equal(doc.numPages, 1);
    const page = await doc.getPage(1);
    const vue = page.getViewport({ scale: 1 });
    assert.equal(Math.round(vue.width), 612);
    assert.equal(Math.round(vue.height), 792);
    assert.equal((await page.getTextContent()).items.length, 0);
    await doc.destroy();
    // Les montants (bien écrits dans l'original) : plus un pixel d'encre, fond blanc, aucun
    // carré visible ; les descriptions, quantités et le titre : toujours écrits.
    for (const [desc, , , y] of LIGNES) {
      const zone = [450, y - 2, 480, y + 10];
      assert.ok(await partFoncee(original, 1, zone) > 0.05, `montant écrit dans l'original : ${desc}`);
      assert.equal(await partFoncee(r.pdf, 1, zone), 0, `montant effacé : ${desc}`);
      assert.ok(await grisMoyen(r.pdf, 1, zone) > 250, `effacé en blanc : ${desc}`);
      assert.ok(await partFoncee(r.pdf, 1, [72, y, 140, y + 9]) > 0.05, `description ${desc}`);
    }
    // Les quantités restent lisibles, même « 1 » juste avant « 450.00 » (pas des milliers).
    for (const [, qte, , y] of LIGNES) {
      if (qte) assert.ok(await partFoncee(r.pdf, 1, [298, y, 310, y + 9]) > 0.02, `quantité à ${y}`);
    }
    assert.ok(await partFoncee(r.pdf, 1, [72, 700, 200, 709]) > 0.05, 'titre et numéro du devis');
  });

  test('ligne grisée d\'un tableau : le montant est effacé du même gris (pas de tache blanche)', async () => {
    // Bande gris clair (85 %) derrière la ligne de la quincaillerie.
    const grise = () => '0.85 g 66 636 480 16 re f 0 g\n' + fluxDevis();
    const original = pdf({ dessin: grise });
    const r = await devis.copieSansMontants(original);
    const zone = [450, 638, 480, 650];
    assert.ok(await partFoncee(original, 1, zone) > 0.05);
    assert.equal(await partFoncee(r.pdf, 1, zone), 0);
    const gris = await grisMoyen(r.pdf, 1, zone);
    const fond = await grisMoyen(r.pdf, 1, [380, 638, 440, 650]); // la bande, à côté
    assert.ok(Math.abs(gris - fond) < 6, `effacé ${gris} vs bande ${fond}`);
    assert.ok(fond < 230 && fond > 205, `bande grise ${fond}`);
  });

  test('PDF numérisé (sans texte) ou trop long : pas de copie, caché aux contremaîtres', async () => {
    const trait = () => '0 0 0 RG 2 w 72 600 m 500 600 l S\n';
    assert.deepEqual(await devis.copieSansMontants(pdf({ dessin: trait })), { cachee: 'sans_texte' });
    assert.deepEqual(await devis.copieSansMontants(pdf({ pages: devis.MAX_PAGES + 1, dessin: fluxDevis })),
      { cachee: 'trop_long' });
  });

  test('plusieurs pages : une image par page, dans l\'ordre', async () => {
    const r = await devis.copieSansMontants(pdf({ pages: 3, dessin: fluxDevis }));
    assert.equal(r.pages, 3);
    assert.equal(r.montants, 12);
    const doc = await ouvrir(r.pdf);
    assert.equal(doc.numPages, 3);
    await doc.destroy();
  });
});

describe('Devis : préparation d\'une fiche', () => {
  /** Faux Firestore et Storage : ce qui est écrit est noté. */
  function faux(contenu) {
    const ecrits = [];
    const fichiers = new Map([['chantiers/A/chA/documents/111_Devis_cuisine.pdf', contenu]]);
    const operations = [];
    const ref = { update: async (d) => { ecrits.push(d); } };
    const bucket = {
      file: (chemin) => ({
        move: async (vers) => { operations.push(`move ${chemin} → ${vers}`); fichiers.set(vers, fichiers.get(chemin)); fichiers.delete(chemin); },
        setMetadata: async (m) => { operations.push(`jeton ${chemin}`); assert.ok(m.metadata.firebaseStorageDownloadTokens); },
        download: async () => [fichiers.get(chemin)],
        save: async (octets, o) => { operations.push(`save ${chemin} ${o.contentType}`); fichiers.set(chemin, octets); },
      }),
    };
    const FieldValue = { delete: () => 'SUPPRIMÉ' };
    return { ecrits, operations, fichiers, ref, bucket, FieldValue, crypto: { randomUUID: () => 'neuf' } };
  }
  const fiche = (o = {}) => ({
    companyId: 'A', chantierId: 'chA', nom: 'Devis cuisine.pdf', typeMime: 'application/pdf',
    cheminStorage: 'chantiers/A/chA/documents/111_Devis_cuisine.pdf', url: 'https://x', ...o,
  });

  test('un autre document : rien', async () => {
    const f = faux(Buffer.from('x'));
    assert.equal(await devis.preparer({ ...f, data: fiche({ nom: 'Plan.pdf' }), documentId: 'd1' }), null);
    assert.deepEqual(f.ecrits, []);
  });

  test('PDF : lien retiré, jeton révoqué, copie enregistrée', async () => {
    const f = faux(pdf({ dessin: fluxDevis }));
    assert.equal(await devis.preparer({ ...f, data: fiche(), documentId: 'd1' }), 'prete');
    assert.deepEqual(f.ecrits[0], { devis: true, url: 'SUPPRIMÉ', copieContremaitre: { etat: 'en_cours' } });
    assert.deepEqual(f.operations, [
      'jeton chantiers/A/chA/documents/111_Devis_cuisine.pdf',
      'save chantiers/A/chA/devis_sans_montants/d1.pdf application/pdf',
    ]);
    const fin = f.ecrits.at(-1).copieContremaitre;
    assert.equal(fin.etat, 'prete');
    assert.equal(fin.chemin, 'chantiers/A/chA/devis_sans_montants/d1.pdf');
    assert.equal(fin.montants, 4);
    assert.equal(fin.pages, 1);
    assert.ok(fin.taille > 1000);
  });

  test('nom de fichier sans « devis » (ancienne app) : renommé pour les règles', async () => {
    const f = faux(pdf({ dessin: fluxDevis }));
    f.fichiers.set('chantiers/A/chA/documents/111_x.pdf', f.fichiers.get('chantiers/A/chA/documents/111_Devis_cuisine.pdf'));
    await devis.preparer({ ...f, data: fiche({ cheminStorage: 'chantiers/A/chA/documents/111_x.pdf' }), documentId: 'd2' });
    assert.equal(f.operations[0], 'move chantiers/A/chA/documents/111_x.pdf → chantiers/A/chA/documents/devis_111_x.pdf');
    assert.ok(f.ecrits.some((e) => e.cheminStorage === 'chantiers/A/chA/documents/devis_111_x.pdf'));
    assert.equal(f.ecrits.at(-1).copieContremaitre.etat, 'prete');
  });

  test('pas un PDF : caché aux contremaîtres (jeton révoqué quand même)', async () => {
    const f = faux(Buffer.from('x'));
    const d = fiche({ nom: 'Devis.xlsx', typeMime: 'application/vnd.ms-excel',
      cheminStorage: 'chantiers/A/chA/documents/111_Devis_cuisine.pdf' });
    assert.equal(await devis.preparer({ ...f, data: d, documentId: 'd3' }), 'cachee');
    assert.deepEqual(f.ecrits.at(-1), { copieContremaitre: { etat: 'cachee', raison: 'format' } });
    assert.ok(f.operations[0].startsWith('jeton '));
  });

  test('chemin hors du chantier ou fichier illisible : erreur, jamais de copie', async () => {
    const f = faux(Buffer.from('pas un pdf'));
    assert.equal(await devis.preparer({ ...f, data: fiche({ cheminStorage: 'chantiers/B/chB/documents/x_devis.pdf' }), documentId: 'd4' }), 'erreur');
    assert.equal(await devis.preparer({ ...f, data: fiche(), documentId: 'd5' }), 'erreur');
    assert.ok(!f.operations.some((o) => o.startsWith('save')));
    assert.deepEqual(f.ecrits.at(-1), { copieContremaitre: { etat: 'erreur' } });
  });
});
