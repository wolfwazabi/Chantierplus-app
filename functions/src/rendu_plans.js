"use strict";

/**
 * Plans en grand format : une feuille de permis (24 × 36 po à 1/4 po = 1 pi) ramenée à la
 * taille d'une image ordinaire rend ses cotes illisibles (quelques pixels de haut), et les
 * plans d'architecte n'ont souvent aucune couche de texte (cotes dessinées en traits). Chaque
 * page est donc rendue ici en grand, puis découpée en morceaux qui se chevauchent : le modèle
 * reçoit une vue d'ensemble de la page et ses morceaux, où les cotes se lisent.
 *
 * Les grandes photos sont découpées de la même façon. Un PDF que le serveur ne sait pas lire
 * est envoyé tel quel (comme avant), jamais refusé pour ça.
 */

const path = require("node:path");

/** Côté maximal d'une image envoyée au modèle (au-delà, l'API la réduit). */
const COTE_IMAGE = 1568;
/** Côté long d'une page rendue : les cotes d'un plan au 1/4 po y font une vingtaine de pixels. */
const COTE_PAGE = 4200;
/** Chevauchement des morceaux, pour qu'aucune cote ne soit coupée en deux. */
const CHEVAUCHEMENT = 160;
const MAX_PAGES_DETAILLEES = 6;
const MAX_IMAGES = 60;
const QUALITE_JPEG = 82;
/** Un morceau presque blanc n'apporte rien : on ne l'envoie pas. */
const ENCRE_MIN = 0.004;
/** Une photo dont le côté long dépasse ceci est aussi découpée. */
const COTE_PHOTO_DECOUPEE = 2200;

let pdfjsPromesse = null;
function pdfjs() {
  if (!pdfjsPromesse) pdfjsPromesse = import("pdfjs-dist/legacy/build/pdf.mjs");
  return pdfjsPromesse;
}

function canvas() {
  return require("@napi-rs/canvas");
}

/** Part des pixels « encrés » (pas blancs), mesurée sur un échantillon. */
function partEncre(ctx, x, y, l, h) {
  const donnees = ctx.getImageData(x, y, l, h).data;
  let encre = 0;
  let total = 0;
  // Un pixel sur 7 suffit pour savoir si le morceau contient quelque chose.
  for (let i = 0; i < donnees.length; i += 4 * 7) {
    total++;
    if (donnees[i] < 200 || donnees[i + 1] < 200 || donnees[i + 2] < 200) encre++;
  }
  return total ? encre / total : 0;
}

/** Les morceaux qui couvrent une image de largeur × hauteur (positions en pixels). */
function grille(largeur, hauteur) {
  const pas = COTE_IMAGE - CHEVAUCHEMENT;
  const departs = (taille) => {
    if (taille <= COTE_IMAGE) return [0];
    const n = Math.ceil((taille - CHEVAUCHEMENT) / pas);
    const ecart = (taille - COTE_IMAGE) / (n - 1);
    return Array.from({length: n}, (_, i) => Math.round(i * ecart));
  };
  const morceaux = [];
  const lignes = departs(hauteur);
  const colonnes = departs(largeur);
  lignes.forEach((y, ligne) => colonnes.forEach((x, colonne) => morceaux.push({
    x, y, l: Math.min(COTE_IMAGE, largeur - x), h: Math.min(COTE_IMAGE, hauteur - y),
    ligne: ligne + 1, colonne: colonne + 1, lignes: lignes.length, colonnes: colonnes.length,
  })));
  return morceaux;
}

/**
 * Découpe [source] en JPEG. [creer] fabrique la toile de sortie : elle doit venir de la même
 * bibliothèque que [source] (mélanger deux instances fait planter le processus).
 */
function jpeg(creer, source, x, y, l, h, echelle = 1) {
  const sortie = creer(Math.max(1, Math.round(l * echelle)), Math.max(1, Math.round(h * echelle)));
  const c = sortie.getContext("2d");
  c.fillStyle = "white";
  c.fillRect(0, 0, sortie.width, sortie.height);
  c.drawImage(source, x, y, l, h, 0, 0, sortie.width, sortie.height);
  return sortie.encodeSync("jpeg", QUALITE_JPEG).toString("base64");
}

const blocImage = (donnees) => ({type: "image", source: {type: "base64", media_type: "image/jpeg", data: donnees}});

/** Vue d'ensemble puis morceaux d'une image déjà dessinée sur [toile]. */
function decouper(creer, toile, ctx, etiquette, budget) {
  const blocs = [];
  const long = Math.max(toile.width, toile.height);
  blocs.push({type: "text", text: `${etiquette} — vue d'ensemble`});
  blocs.push(blocImage(jpeg(creer, toile, 0, 0, toile.width, toile.height, Math.min(1, COTE_IMAGE / long))));
  let images = 1;
  for (const m of grille(toile.width, toile.height)) {
    if (images >= budget) break;
    if (partEncre(ctx, m.x, m.y, m.l, m.h) < ENCRE_MIN) continue;
    blocs.push({type: "text", text: `${etiquette} — morceau ligne ${m.ligne}/${m.lignes}, colonne ${m.colonne}/${m.colonnes} (agrandi)`});
    blocs.push(blocImage(jpeg(creer, toile, m.x, m.y, m.l, m.h)));
    images++;
  }
  return {blocs, images};
}

/** Nombre de morceaux de texte dans le PDF (0 : cotes dessinées, illisibles sans agrandir). */
async function texteDuPdf(doc) {
  let n = 0;
  for (let p = 1; p <= Math.min(doc.numPages, 10); p++) {
    const contenu = await (await doc.getPage(p)).getTextContent();
    n += contenu.items.filter((i) => typeof i.str === "string" && i.str.trim()).length;
  }
  return n;
}

/**
 * Prépare le contenu envoyé au modèle pour un fichier : blocs (texte, document, images).
 * `budget` : nombre d'images encore permises dans la requête. Ne lance jamais : en cas de
 * problème, le fichier part tel quel.
 */
async function preparerFichier(f, budget, journal = () => {}) {
  const tel = [{type: f.genre, source: {type: "base64", media_type: f.mime, data: f.donnees}}];
  try {
    if (f.genre === "document") return await preparerPdf(f, budget, tel);
    return await preparerImage(f, budget, tel);
  } catch (e) {
    journal(`Rendu impossible (${f.nom}) : ${e?.message ?? e}`);
    return {blocs: tel, images: 0};
  }
}

async function preparerPdf(f, budget, tel) {
  const {getDocument} = await pdfjs();
  const doc = await getDocument({
    data: new Uint8Array(Buffer.from(f.donnees, "base64")),
    standardFontDataUrl: path.join(path.dirname(require.resolve("pdfjs-dist/package.json")), "standard_fonts") + path.sep,
    isEvalSupported: false,
  }).promise;
  try {
    const blocs = [];
    // Un PDF avec du vrai texte garde aussi sa forme d'origine (le texte aide à lire les cotes).
    if (await texteDuPdf(doc) > 30) blocs.push(...tel);
    let images = 0;
    const pages = Math.min(doc.numPages, MAX_PAGES_DETAILLEES);
    for (let p = 1; p <= pages && images < budget; p++) {
      const page = await doc.getPage(p);
      const base = page.getViewport({scale: 1});
      const echelle = Math.min(6, COTE_PAGE / Math.max(base.width, base.height));
      const vue = page.getViewport({scale: echelle});
      const {canvas: toile, context} = doc.canvasFactory.create(Math.ceil(vue.width), Math.ceil(vue.height));
      context.fillStyle = "white";
      context.fillRect(0, 0, toile.width, toile.height);
      await page.render({canvasContext: context, viewport: vue}).promise;
      const creer = (l, h) => doc.canvasFactory.create(l, h).canvas;
      const r = decouper(creer, toile, context, `Page ${p} sur ${doc.numPages}`, budget - images);
      blocs.push(...r.blocs);
      images += r.images;
      page.cleanup();
    }
    if (doc.numPages > pages) {
      blocs.push({type: "text", text: `Pages ${pages + 1} à ${doc.numPages} non agrandies (trop de pages) : précisez la page utile.`});
      if (!blocs.includes(tel[0])) blocs.push(...tel);
    }
    return {blocs, images};
  } finally {
    await doc.destroy();
  }
}

async function preparerImage(f, budget, tel) {
  const {createCanvas, loadImage} = canvas();
  const img = await loadImage(Buffer.from(f.donnees, "base64"));
  if (Math.max(img.width, img.height) <= COTE_PHOTO_DECOUPEE || budget < 2) return {blocs: tel, images: 1};
  const toile = createCanvas(img.width, img.height);
  const ctx = toile.getContext("2d");
  ctx.drawImage(img, 0, 0);
  return decouper(createCanvas, toile, ctx, "Photo", budget);
}

/**
 * Le contenu de la requête pour tous les fichiers : pour chacun, son nom puis ses blocs.
 * Au plus MAX_IMAGES images au total.
 */
async function contenuDesFichiers(fichiers, journal) {
  const contenu = [];
  let images = 0;
  for (let i = 0; i < fichiers.length; i++) {
    const f = fichiers[i];
    contenu.push({type: "text", text: `Fichier ${i + 1} sur ${fichiers.length} : « ${f.nom} »`});
    const r = await preparerFichier(f, Math.max(0, MAX_IMAGES - images), journal);
    contenu.push(...r.blocs);
    images += r.images;
  }
  return contenu;
}

module.exports = {
  COTE_IMAGE, COTE_PAGE, MAX_IMAGES, MAX_PAGES_DETAILLEES,
  grille, contenuDesFichiers, preparerFichier,
};
