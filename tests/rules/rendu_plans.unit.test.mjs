// Tests unitaires du rendu des plans (sans réseau) : pages de PDF agrandies et découpées en
// morceaux lisibles, grandes photos découpées, limites, et repli sur le fichier tel quel.
// Les PDF sont fabriqués ici (aucun plan de client dans le dépôt). Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const rendu = require('../../functions/src/rendu_plans.js');
const lp = require('../../functions/src/lecture_plans.js');
const { createCanvas, loadImage } = createRequire(require.resolve('../../functions/index.js'))('@napi-rs/canvas');

// --- Fabrication de PDF minimaux -------------------------------------------------------------

/**
 * Un PDF valide de [pages] pages de largeur × hauteur points. [dessin] (page → texte du flux de
 * contenu) : traits, texte… La police F1 (Helvetica) est disponible.
 */
function pdf({ pages = 1, largeur = 1296, hauteur = 1728, dessin = () => '' }) {
  const objets = [];
  const ajouter = (corps) => { objets.push(corps); return objets.length; };
  const catalogue = ajouter(null);
  const arbre = ajouter(null);
  const police = ajouter('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  const kids = [];
  for (let p = 0; p < pages; p++) {
    const flux = dessin(p);
    const contenu = ajouter(`<< /Length ${Buffer.byteLength(flux, 'latin1')} >>\nstream\n${flux}\nendstream`);
    kids.push(ajouter(`<< /Type /Page /Parent ${arbre} 0 R /MediaBox [0 0 ${largeur} ${hauteur}] ` +
      `/Resources << /Font << /F1 ${police} 0 R >> >> /Contents ${contenu} 0 R >>`));
  }
  objets[catalogue - 1] = `<< /Type /Catalog /Pages ${arbre} 0 R >>`;
  objets[arbre - 1] = `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(' ')}] /Count ${pages} >>`;
  let texte = '%PDF-1.4\n';
  const positions = [];
  objets.forEach((corps, i) => {
    positions.push(Buffer.byteLength(texte, 'latin1'));
    texte += `${i + 1} 0 obj\n${corps}\nendobj\n`;
  });
  const xref = Buffer.byteLength(texte, 'latin1');
  texte += `xref\n0 ${objets.length + 1}\n0000000000 65535 f \n`;
  for (const pos of positions) texte += `${String(pos).padStart(10, '0')} 00000 n \n`;
  texte += `trailer\n<< /Size ${objets.length + 1} /Root ${catalogue} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(texte, 'latin1');
}

/** Un quadrillage serré sur toute la page : chaque morceau contient de l'encre. */
const quadrillage = (l = 1296, h = 1728) => {
  let s = '0 0 0 RG 1.5 w\n';
  for (let x = 20; x < l; x += 60) s += `${x} 0 m ${x} ${h} l S\n`;
  for (let y = 20; y < h; y += 60) s += `0 ${y} m ${l} ${y} l S\n`;
  return s;
};

/** Du vrai texte (une cote par ligne) : le PDF a une couche de texte. */
const cotes = (n = 40) => {
  let s = 'BT /F1 14 Tf\n';
  for (let i = 0; i < n; i++) s += `1 0 0 1 60 ${60 + i * 30} Tm (Cote ${i}: 12'-6") Tj\n`;
  return s + 'ET\n';
};

const fichierPdf = (octets, nom = 'plan.pdf') => lp.validerFichiers([{ nom, donnees: octets.toString('base64') }])[0];

async function taille(bloc) {
  const img = await loadImage(Buffer.from(bloc.source.data, 'base64'));
  return [img.width, img.height];
}

const images = (blocs) => blocs.filter((b) => b.type === 'image');
const textes = (blocs) => blocs.filter((b) => b.type === 'text').map((b) => b.text);

// =================================================================================================
describe('grille des morceaux', () => {
  test('petite image : un seul morceau, l\'image entière', () => {
    assert.deepEqual(rendu.grille(1000, 800).map(({ x, y, l, h }) => [x, y, l, h]), [[0, 0, 1000, 800]]);
  });

  test('page de 3150 × 4200 : 3 × 3 morceaux de 1568 px au plus, qui couvrent tout et se chevauchent', () => {
    const g = rendu.grille(3150, 4200);
    assert.equal(g.length, 9);
    assert.ok(g.every((m) => m.l <= rendu.COTE_IMAGE && m.h <= rendu.COTE_IMAGE));
    assert.ok(g.every((m) => m.lignes === 3 && m.colonnes === 3));
    // Chaque pixel (échantillonné) est couvert.
    for (let x = 0; x < 3150; x += 37) {
      for (let y = 0; y < 4200; y += 41) {
        assert.ok(g.some((m) => x >= m.x && x < m.x + m.l && y >= m.y && y < m.y + m.h), `${x},${y}`);
      }
    }
    // Deux morceaux voisins se chevauchent d'au moins 160 px (une cote n'est jamais coupée en deux).
    const xs = [...new Set(g.map((m) => m.x))].sort((a, b) => a - b);
    for (let i = 1; i < xs.length; i++) assert.ok(xs[i - 1] + rendu.COTE_IMAGE - xs[i] >= 160);
  });
});

// =================================================================================================
describe('PDF : pages agrandies et découpées', () => {
  test('feuille de plan (18 × 24 po) dessinée partout : vue d\'ensemble et 9 morceaux par page', async () => {
    const f = fichierPdf(pdf({ pages: 2, dessin: () => quadrillage() }));
    const r = await rendu.preparerFichier(f, 60);
    const t = textes(r.blocs);
    assert.equal(images(r.blocs).length, 20);
    assert.equal(r.images, 20);
    assert.ok(t.includes('Page 1 sur 2 — vue d\'ensemble'));
    assert.ok(t.includes('Page 2 sur 2 — morceau ligne 3/3, colonne 3/3 (agrandi)'));
    // Le PDF sans texte n'est pas joint tel quel (ses images seraient illisibles).
    assert.equal(r.blocs.filter((b) => b.type === 'document').length, 0);
    for (const b of images(r.blocs)) {
      assert.equal(b.source.media_type, 'image/jpeg');
      const [l, h] = await taille(b);
      assert.ok(l <= rendu.COTE_IMAGE && h <= rendu.COTE_IMAGE, `${l}×${h}`);
    }
  });

  test('les morceaux sont agrandis : la page entière fait environ 4200 px de haut', async () => {
    const f = fichierPdf(pdf({ dessin: () => quadrillage() }));
    const r = await rendu.preparerFichier(f, 60);
    const morceaux = images(r.blocs).slice(1);
    const hauteurs = await Promise.all(morceaux.map(taille));
    assert.ok(hauteurs.every(([, h]) => h > 1300), 'chaque morceau garde la pleine résolution');
    const [l, h] = await taille(images(r.blocs)[0]);
    assert.ok(Math.max(l, h) <= rendu.COTE_IMAGE, 'la vue d\'ensemble est réduite');
  });

  test('page blanche : seulement la vue d\'ensemble (les morceaux vides ne sont pas envoyés)', async () => {
    const r = await rendu.preparerFichier(fichierPdf(pdf({ dessin: () => '' })), 60);
    assert.equal(images(r.blocs).length, 1);
  });

  test('un dessin dans un coin : seulement les morceaux qui le contiennent', async () => {
    const coin = '0 0 0 RG 3 w\n' + Array.from({ length: 20 }, (_, i) => `${40 + i * 10} 40 m ${40 + i * 10} 300 l S`).join('\n');
    const r = await rendu.preparerFichier(fichierPdf(pdf({ dessin: () => coin })), 60);
    const n = images(r.blocs).length;
    assert.ok(n >= 2 && n <= 3, `${n} images`);
  });

  test('PDF avec une vraie couche de texte : joint aussi tel quel', async () => {
    const r = await rendu.preparerFichier(fichierPdf(pdf({ dessin: () => quadrillage() + cotes() })), 60);
    assert.equal(r.blocs.filter((b) => b.type === 'document').length, 1);
    assert.ok(images(r.blocs).length > 1);
  });

  test('plus de 6 pages : les 6 premières agrandies, le reste signalé et joint tel quel', async () => {
    const r = await rendu.preparerFichier(fichierPdf(pdf({ pages: 8, largeur: 612, hauteur: 792, dessin: () => quadrillage(612, 792) })), 60);
    const t = textes(r.blocs);
    assert.ok(t.some((x) => x.startsWith('Page 6 sur 8')));
    assert.ok(!t.some((x) => x.startsWith('Page 7 sur 8')));
    assert.ok(t.some((x) => x.includes('Pages 7 à 8 non agrandies')));
    assert.equal(r.blocs.filter((b) => b.type === 'document').length, 1);
  });

  test('budget d\'images : jamais plus que permis', async () => {
    const f = fichierPdf(pdf({ pages: 3, dessin: () => quadrillage() }));
    const r = await rendu.preparerFichier(f, 7);
    assert.ok(images(r.blocs).length <= 7, `${images(r.blocs).length}`);
    assert.equal(r.images, images(r.blocs).length);
  });

  test('plusieurs fichiers : au plus 60 images en tout, chaque fichier précédé de son nom', async () => {
    const lourd = pdf({ pages: 6, dessin: () => quadrillage() });
    const fichiers = lp.validerFichiers([1, 2].map((i) => ({ nom: `plan${i}.pdf`, donnees: lourd.toString('base64') })));
    const contenu = await rendu.contenuDesFichiers(fichiers);
    assert.ok(images(contenu).length <= rendu.MAX_IMAGES);
    assert.equal(contenu[0].text, 'Fichier 1 sur 2 : « plan1.pdf »');
    assert.ok(textes(contenu).includes('Fichier 2 sur 2 : « plan2.pdf »'));
  });

  test('PDF illisible pour le serveur : envoyé tel quel, jamais refusé, et noté au journal', async () => {
    const f = fichierPdf(Buffer.concat([Buffer.from('%PDF-1.7\n'), Buffer.alloc(300, 0x20)]));
    const journal = [];
    const r = await rendu.preparerFichier(f, 60, (m) => journal.push(m));
    assert.deepEqual(r.blocs, [{ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: f.donnees } }]);
    assert.equal(journal.length, 1);
    assert.ok(journal[0].includes('plan.pdf'));
  });
});

// =================================================================================================
describe('photos', () => {
  const photo = (l, h) => {
    const c = createCanvas(l, h);
    const x = c.getContext('2d');
    x.fillStyle = 'white';
    x.fillRect(0, 0, l, h);
    x.strokeStyle = 'black';
    for (let i = 0; i < l; i += 40) { x.beginPath(); x.moveTo(i, 0); x.lineTo(i, h); x.stroke(); }
    return c.encodeSync('jpeg', 85);
  };

  test('photo ordinaire : envoyée telle quelle', async () => {
    const f = lp.validerFichiers([{ nom: 'p.jpg', donnees: photo(1600, 1200).toString('base64') }])[0];
    const r = await rendu.preparerFichier(f, 60);
    assert.equal(r.blocs.length, 1);
    assert.equal(r.blocs[0].source.data, f.donnees);
  });

  test('grande photo (4000 × 3000) : vue d\'ensemble et morceaux', async () => {
    const f = lp.validerFichiers([{ nom: 'grande.jpg', donnees: photo(4000, 3000).toString('base64') }])[0];
    const r = await rendu.preparerFichier(f, 60);
    assert.ok(images(r.blocs).length > 2);
    assert.ok(textes(r.blocs)[0].startsWith('Photo — vue d\'ensemble'));
  });
});

// =================================================================================================
describe('requête au modèle', () => {
  test('lirePlan envoie les pages préparées, pas le PDF brut', async () => {
    const f = fichierPdf(pdf({ dessin: () => quadrillage() }));
    let corps;
    const reponse = { content: [{ type: 'tool_use', name: 'lire_plan', input: {
      lisible: true, explication: 'x', hypotheses: [],
      projet: { plancherActif: true, plancher: { forme: { type: 'rectangle', longueur: 144, largeur: 120 } }, mursActifs: false },
      valeurs: [],
    } }] };
    await lp.lirePlan({
      fichiers: [f], precisions: '', cle: 'cle', url: 'http://x', modele: 'm',
      fetchImpl: async (u, opts) => { corps = JSON.parse(opts.body); return { status: 200, ok: true, json: async () => reponse }; },
    });
    const contenu = corps.messages[0].content;
    assert.equal(contenu[0].text, 'Fichier 1 sur 1 : « plan.pdf »');
    assert.equal(contenu.filter((b) => b.type === 'document').length, 0);
    assert.equal(contenu.filter((b) => b.type === 'image').length, 10);
    assert.ok(contenu.at(-1).text.startsWith('Lis ce plan'));
    assert.ok(lp.PROMPT_PLAN.includes('morceaux agrandis'));
  });

  test('sans clé : refusé avant tout rendu', async () => {
    let prepare = false;
    await assert.rejects(lp.lirePlan({
      fichiers: [], precisions: '', cle: '', url: 'http://x', modele: 'm',
      preparer: async () => { prepare = true; return []; },
    }), (e) => e.code === 'failed-precondition');
    assert.equal(prepare, false);
  });
});
