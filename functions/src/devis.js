"use strict";

/**
 * Devis : copie sans montants pour les contremaîtres (demande de l'entrepreneur, 16 oct. 2026).
 *
 *  - Un document de chantier dont le NOM contient « devis » (majuscules et accents ignorés) est
 *    un devis. L'admin garde l'original ; le contremaître n'y a plus accès (règles Storage, lien
 *    à jeton retiré de la fiche et révoqué).
 *  - Pour un PDF qui a du texte, le serveur fait une copie : chaque page est rendue en image, les
 *    montants (avec $, ou à 2 décimales : 1 234,56 $, $1,234.56, 450.00) y sont noircis. Le texte
 *    n'existe plus dans la copie : rien à copier ni à chercher sous les carrés noirs.
 *  - Un devis qui n'est pas un PDF, ou un PDF numérisé (sans texte), est caché aux contremaîtres.
 *
 * Fiche du document : `devis: true` et `copieContremaitre` = {etat, chemin?, taille?, pages?,
 * montants?, raison?} ; etat ∈ en_cours | prete | cachee | erreur.
 */

const path = require("node:path");

/** Pages au plus dans une copie (un devis de plus est caché aux contremaîtres). */
const MAX_PAGES = 30;
/** Résolution de la copie : 2 × 72 = 144 points par pouce, lisible à l'écran et imprimé. */
const ECHELLE = 2;
const QUALITE_JPEG = 85;
/** Marge autour d'un montant noirci, en points. */
const MARGE = 1.5;

/** Le nom contient « devis » (majuscules et accents ignorés). */
function estDevis(nom) {
  return typeof nom === "string" &&
    nom.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().includes("devis");
}

// Espace des milliers : ordinaire, insécable ou fine insécable.
const SEP = "[ \\u00a0\\u202f]";
const MILLIERS = `\\d{1,3}(?:(?:${SEP}|[.,])\\d{3})+`;
const NOMBRE = `(?:${MILLIERS}|\\d+)(?:[.,]\\d{1,2})?`;
/**
 * Un montant : un nombre avec $ avant ou après (« 450 $ », « $1,234.56 », « 1 234,56$ »), ou un
 * nombre à exactement 2 décimales (« 1 234,56 », « 450.00 »). Jamais au milieu d'un nombre.
 */
const RE_MONTANT = new RegExp(
    `(?<![\\d.,])(?:-?\\$${SEP}?${NOMBRE}|${NOMBRE}${SEP}?\\$(?!${SEP}?\\d)|(?:${MILLIERS}|\\d+)[.,]\\d{2}(?![\\d]))`,
    "g");

/** Les montants d'un texte : [{debut, fin, texte}]. */
function montantsDans(texte) {
  const r = [];
  for (const m of String(texte).matchAll(RE_MONTANT)) {
    r.push({debut: m.index, fin: m.index + m[0].length, texte: m[0]});
  }
  return r;
}

/**
 * Les lignes d'une page à partir des morceaux de texte de pdf.js : morceaux sur la même ligne de
 * base, de gauche à droite, avec une espace là où il y a un petit écart et une tabulation entre
 * deux colonnes (écart de plus de 0,8 fois la hauteur du texte : une quantité n'y devient jamais
 * les milliers du montant voisin). Chaque caractère de la ligne garde son morceau et sa place
 * dans le morceau (null : espace ajoutée).
 */
function lignesDe(items) {
  // Les morceaux d'espaces (pdf.js en ajoute entre deux colonnes) sont ignorés : l'écart réel
  // entre les mots décide de l'espace ou de la tabulation.
  const morceaux = items
      .filter((i) => typeof i.str === "string" && i.str.trim().length > 0 && Array.isArray(i.transform))
      .map((i) => {
        const [a, b, c, d, e, f] = i.transform;
        const hauteur = i.height || Math.hypot(c, d) || 10;
        return {i, x: e, y: f, hauteur, largeur: i.width || 0, a, b, c, d};
      })
      .sort((p, q) => (q.y - p.y) || (p.x - q.x));
  const lignes = [];
  for (const m of morceaux) {
    const l = lignes.find((x) => Math.abs(x.y - m.y) < Math.max(1, m.hauteur * 0.5));
    if (l) l.morceaux.push(m);
    else lignes.push({y: m.y, morceaux: [m]});
  }
  return lignes.map((l) => {
    l.morceaux.sort((p, q) => p.x - q.x);
    let texte = "";
    const carte = [];
    let finPrec = null;
    for (const m of l.morceaux) {
      const ecart = finPrec === null ? 0 : m.x - finPrec;
      if (ecart > m.hauteur * 0.8) {
        texte += "\t";
        carte.push(null);
      } else if (ecart > m.hauteur * 0.15 && !/\s$/.test(texte)) {
        texte += " ";
        carte.push(null);
      }
      for (let k = 0; k < m.i.str.length; k++) {
        texte += m.i.str[k];
        carte.push({m, k});
      }
      finPrec = m.x + m.largeur;
    }
    return {texte, carte};
  });
}

/**
 * Les rectangles à noircir sur une page, en coordonnées du PDF : [[x1, y1, x2, y2]]. Un montant
 * coupé en plusieurs morceaux donne un rectangle par morceau.
 */
function rectanglesMontants(items) {
  const rects = [];
  let montants = 0;
  for (const ligne of lignesDe(items)) {
    for (const t of montantsDans(ligne.texte)) {
      montants++;
      const parMorceau = new Map();
      for (let p = t.debut; p < t.fin; p++) {
        const c = ligne.carte[p];
        if (!c) continue;
        const r = parMorceau.get(c.m) ?? {min: c.k, max: c.k};
        r.min = Math.min(r.min, c.k);
        r.max = Math.max(r.max, c.k);
        parMorceau.set(c.m, r);
      }
      for (const [m, {min, max}] of parMorceau) {
        const n = m.i.str.length;
        // Le long du texte (u) et vers le haut des lettres (v), même tourné.
        const lu = Math.hypot(m.a, m.b) || 1;
        const lv = Math.hypot(m.c, m.d) || 1;
        const u = [m.a / lu, m.b / lu];
        const v = [m.c / lv, m.d / lv];
        const t0 = m.largeur * (min / n) - MARGE;
        const t1 = m.largeur * ((max + 1) / n) + MARGE;
        const s0 = -0.3 * m.hauteur - MARGE;
        const s1 = 1.0 * m.hauteur + MARGE;
        const coins = [[t0, s0], [t1, s0], [t1, s1], [t0, s1]]
            .map(([tt, ss]) => [m.x + u[0] * tt + v[0] * ss, m.y + u[1] * tt + v[1] * ss]);
        const xs = coins.map((p) => p[0]);
        const ys = coins.map((p) => p[1]);
        rects.push([Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]);
      }
    }
  }
  return {rects, montants};
}

let pdfjsPromesse = null;
function pdfjs() {
  if (!pdfjsPromesse) pdfjsPromesse = import("pdfjs-dist/legacy/build/pdf.mjs");
  return pdfjsPromesse;
}

/**
 * Un PDF fait d'images JPEG, une par page : [{jpeg, largeurPx, hauteurPx, largeurPt, hauteurPt}].
 */
function pdfDImages(pages) {
  const morceaux = [];
  const decalages = [];
  let taille = 0;
  const ecrire = (b) => {
    const buf = Buffer.isBuffer(b) ? b : Buffer.from(b, "latin1");
    morceaux.push(buf);
    taille += buf.length;
  };
  const objet = (n, corps) => {
    decalages[n] = taille;
    ecrire(`${n} 0 obj\n`);
    for (const c of [].concat(corps)) ecrire(c);
    ecrire("\nendobj\n");
  };
  ecrire("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n");
  const nPage = (i) => 3 + 3 * i;
  objet(1, "<< /Type /Catalog /Pages 2 0 R >>");
  objet(2, `<< /Type /Pages /Kids [${pages.map((_, i) => `${nPage(i)} 0 R`).join(" ")}] /Count ${pages.length} >>`);
  pages.forEach((p, i) => {
    const n = nPage(i);
    const l = p.largeurPt.toFixed(2);
    const h = p.hauteurPt.toFixed(2);
    objet(n, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${l} ${h}] ` +
      `/Resources << /XObject << /Im0 ${n + 2} 0 R >> >> /Contents ${n + 1} 0 R >>`);
    const contenu = `q ${l} 0 0 ${h} 0 0 cm /Im0 Do Q`;
    objet(n + 1, [`<< /Length ${contenu.length} >>\nstream\n`, contenu, "\nendstream"]);
    objet(n + 2, [
      `<< /Type /XObject /Subtype /Image /Width ${p.largeurPx} /Height ${p.hauteurPx} ` +
        `/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n`,
      p.jpeg, "\nendstream",
    ]);
  });
  const nObjets = 2 + 3 * pages.length;
  const debutXref = taille;
  ecrire(`xref\n0 ${nObjets + 1}\n0000000000 65535 f \n`);
  for (let n = 1; n <= nObjets; n++) ecrire(`${String(decalages[n]).padStart(10, "0")} 00000 n \n`);
  ecrire(`trailer\n<< /Size ${nObjets + 1} /Root 1 0 R >>\nstartxref\n${debutXref}\n%%EOF\n`);
  return Buffer.concat(morceaux);
}

/**
 * La copie sans montants d'un PDF. Retourne {pdf, pages, montants} ; {cachee: raison} si le PDF
 * n'a pas de texte (numérisé) ou trop de pages.
 */
async function copieSansMontants(octets) {
  const {getDocument} = await pdfjs();
  const doc = await getDocument({
    data: new Uint8Array(octets),
    standardFontDataUrl: path.join(path.dirname(require.resolve("pdfjs-dist/package.json")), "standard_fonts") + path.sep,
    isEvalSupported: false,
  }).promise;
  try {
    if (doc.numPages > MAX_PAGES) return {cachee: "trop_long"};
    const pages = [];
    let montants = 0;
    let caracteres = 0;
    for (let p = 1; p <= doc.numPages; p++) {
      const page = await doc.getPage(p);
      const contenu = await page.getTextContent();
      caracteres += contenu.items.reduce((s, i) => s + String(i.str ?? "").replace(/\s/g, "").length, 0);
      const r = rectanglesMontants(contenu.items);
      montants += r.montants;
      const base = page.getViewport({scale: 1});
      const vue = page.getViewport({scale: ECHELLE});
      const {canvas: toile, context} = doc.canvasFactory.create(Math.ceil(vue.width), Math.ceil(vue.height));
      context.fillStyle = "white";
      context.fillRect(0, 0, toile.width, toile.height);
      await page.render({canvasContext: context, viewport: vue}).promise;
      context.fillStyle = "black";
      for (const rect of r.rects) {
        const [x1, y1, x2, y2] = vue.convertToViewportRectangle(rect);
        context.fillRect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
      }
      pages.push({
        jpeg: toile.encodeSync("jpeg", QUALITE_JPEG),
        largeurPx: toile.width, hauteurPx: toile.height,
        largeurPt: base.width, hauteurPt: base.height,
      });
      page.cleanup();
    }
    // Sans texte (PDF numérisé), les montants ne se trouvent pas : la copie n'est pas faite.
    if (caracteres < 20) return {cachee: "sans_texte"};
    return {pdf: pdfDImages(pages), pages: pages.length, montants};
  } finally {
    await doc.destroy();
  }
}

/** Chemin de la copie d'un document. */
function cheminCopie(companyId, chantierId, documentId) {
  return `chantiers/${companyId}/${chantierId}/devis_sans_montants/${documentId}.pdf`;
}

/**
 * Prépare un document « devis » : lien à jeton retiré et révoqué, original rangé sous un nom qui
 * contient « devis » (les règles Storage le réservent aux admins), puis la copie sans montants.
 * Ne fait rien pour un autre document. Retourne l'état de la copie.
 */
async function preparer({db, bucket, FieldValue, ref, data, documentId, crypto, logger}) {
  if (!estDevis(data?.nom)) return null;
  const {companyId, chantierId} = data;
  const dossier = `chantiers/${companyId}/${chantierId}/documents/`;
  if (typeof data.cheminStorage !== "string" || !data.cheminStorage.startsWith(dossier)) {
    await ref.update({devis: true, url: FieldValue.delete(), copieContremaitre: {etat: "erreur"}});
    return "erreur";
  }
  await ref.update({devis: true, url: FieldValue.delete(), copieContremaitre: {etat: "en_cours"}});
  let chemin = data.cheminStorage;
  try {
    let fichier = bucket.file(chemin);
    // Nom de fichier sans « devis » (ancienne version de l'app, nom très long) : il est renommé.
    if (!path.posix.basename(chemin).toLowerCase().includes("devis")) {
      const nouveau = `${dossier}devis_${path.posix.basename(chemin)}`;
      await fichier.move(nouveau);
      chemin = nouveau;
      fichier = bucket.file(chemin);
      await ref.update({cheminStorage: chemin});
    }
    // L'ancien lien à jeton (lisible par les contremaîtres dans la fiche) ne marche plus.
    await fichier.setMetadata({metadata: {firebaseStorageDownloadTokens: crypto.randomUUID()}});

    const pdf = data.typeMime === "application/pdf" || /\.pdf$/i.test(data.nom);
    if (!pdf) {
      await ref.update({copieContremaitre: {etat: "cachee", raison: "format"}});
      return "cachee";
    }
    const [octets] = await fichier.download();
    const r = await copieSansMontants(octets);
    if (r.cachee) {
      await ref.update({copieContremaitre: {etat: "cachee", raison: r.cachee}});
      return "cachee";
    }
    const cheminC = cheminCopie(companyId, chantierId, documentId);
    await bucket.file(cheminC).save(r.pdf, {resumable: false, contentType: "application/pdf"});
    await ref.update({copieContremaitre: {
      etat: "prete", chemin: cheminC, taille: r.pdf.length, pages: r.pages, montants: r.montants,
    }});
    return "prete";
  } catch (e) {
    logger?.error("Copie du devis impossible", {documentId, detail: String(e?.message ?? e)});
    await ref.update({copieContremaitre: {etat: "erreur"}}).catch(() => null);
    return "erreur";
  }
}

module.exports = {
  estDevis, montantsDans, lignesDe, rectanglesMontants, pdfDImages, copieSansMontants, cheminCopie,
  preparer, MAX_PAGES,
};
