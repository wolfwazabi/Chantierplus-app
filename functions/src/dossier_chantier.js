// Dossier de chantier : résumé des heures et documents d'export.
//
// Module pur (aucun accès à la base ni au stockage) pour être testé sans
// émulateur. La lecture des données et la création du ZIP sont dans index.js.

const ISO = /^\d{4}-\d{2}-\d{2}$/;

const arrondir2 = (x) => Math.round(x * 100) / 100;
const nombre = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/** Date « AAAA-MM-JJ » du jour d'indice `n` (0 = lundi) de la semaine. */
function ajouterJours(lundiIso, n) {
  const [a, m, j] = lundiIso.split("-").map(Number);
  return new Date(Date.UTC(a, m - 1, j + n)).toISOString().slice(0, 10);
}

/**
 * Une ligne par journée travaillée sur le chantier, d'après les feuilles de
 * temps de la compagnie (valeurs déjà calculées par le serveur à la saisie).
 */
function detailHeures(feuilles, chantierId) {
  const lignes = [];
  for (const f of feuilles) {
    if (!f || !ISO.test(f.lundiDate ?? "") || !Array.isArray(f.jours)) continue;
    f.jours.forEach((j, i) => {
      if (!j || j.estAucun === true || j.chantierId !== chantierId) return;
      lignes.push({
        date: ajouterJours(f.lundiDate, i),
        employeeId: String(f.employeeId ?? ""),
        employeNom: String(f.employeeNom ?? ""),
        heures: nombre(j.heuresTravaillees),
        voyagementPaye: nombre(j.voyagementPayeHeures),
      });
    });
  }
  lignes.sort((a, b) => a.date.localeCompare(b.date) ||
      a.employeNom.localeCompare(b.employeNom, "fr"));
  return lignes;
}

/** Totaux, par employé et période, à partir du détail. */
function resumerHeures(lignes) {
  const parEmploye = new Map();
  let heures = 0;
  let voyage = 0;
  for (const l of lignes) {
    heures += l.heures;
    voyage += l.voyagementPaye;
    const e = parEmploye.get(l.employeeId) ??
      {employeeId: l.employeeId, nom: l.employeNom, heures: 0, voyagementPaye: 0, jours: 0};
    e.heures += l.heures;
    e.voyagementPaye += l.voyagementPaye;
    e.jours += 1;
    parEmploye.set(l.employeeId, e);
  }
  const employes = [...parEmploye.values()]
      .map((e) => ({...e, heures: arrondir2(e.heures), voyagementPaye: arrondir2(e.voyagementPaye)}))
      .sort((a, b) => b.heures - a.heures || a.nom.localeCompare(b.nom, "fr"));
  return {
    totalHeures: arrondir2(heures),
    totalVoyagementPaye: arrondir2(voyage),
    joursTravailles: new Set(lignes.map((l) => l.date)).size,
    journeesHomme: lignes.length,
    premierJour: lignes.length ? lignes[0].date : null,
    dernierJour: lignes.length ? lignes[lignes.length - 1].date : null,
    parEmploye: employes,
  };
}

// -----------------------------------------------------------------------------
// Chemins de fichiers
// -----------------------------------------------------------------------------

/**
 * Chemin Storage d'une photo de matériel, tiré de son URL de téléchargement
 * (« …/o/chemin%2Fencode?alt=media&token=… »), ou null.
 */
function cheminDepuisUrl(url) {
  if (typeof url !== "string") return null;
  const m = url.match(/\/o\/([^?#]+)/);
  if (!m) return null;
  try {
    return decodeURIComponent(m[1]);
  } catch (_) {
    return null;
  }
}

/**
 * Un chemin n'est lu que s'il est dans le dossier de CE chantier de CETTE
 * compagnie : une fiche forgée ne doit jamais faire exporter le fichier d'une
 * autre compagnie. Refuse aussi « .. » et les chemins vides.
 */
function cheminDuChantier(chemin, companyId, chantierId) {
  if (typeof chemin !== "string" || chemin.length > 600) return false;
  if (chemin.includes("..") || chemin.includes("\\") || chemin.includes("//")) return false;
  return chemin.startsWith(`chantiers/${companyId}/${chantierId}/`);
}

/** Nom de fichier sûr pour le ZIP. */
function nomSur(texte, defaut = "fichier") {
  const s = String(texte ?? "")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^A-Za-z0-9._ -]+/g, "_")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 80);
  return s.length > 0 && s !== "." && s !== ".." ? s : defaut;
}

function extension(chemin) {
  const m = String(chemin).toLowerCase().match(/[.]([a-z0-9]{1,5})$/);
  return m ? m[1] : "jpg";
}

// -----------------------------------------------------------------------------
// CSV (pour Excel en français : séparateur « ; », virgule décimale)
// -----------------------------------------------------------------------------

/**
 * Une cellule. Un texte qui commence par = + - @ (ou tabulation) serait lu
 * comme une formule par Excel : on le préfixe d'une apostrophe.
 */
function cellule(valeur) {
  if (valeur === null || valeur === undefined) return "";
  if (typeof valeur === "number") {
    return Number.isFinite(valeur) ? String(valeur).replace(".", ",") : "";
  }
  let s = String(valeur);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[";\r\n]/.test(s)) s = `"${s.replace(/"/g, "\"\"")}"`;
  return s;
}

/** CSV avec BOM UTF-8 (accents corrects dans Excel). */
function csv(colonnes, lignes) {
  const rangees = [colonnes.map((c) => cellule(c.titre)).join(";")];
  for (const l of lignes) rangees.push(colonnes.map((c) => cellule(l[c.cle])).join(";"));
  return `﻿${rangees.join("\r\n")}\r\n`;
}

// -----------------------------------------------------------------------------
// Résumé imprimable (HTML)
// -----------------------------------------------------------------------------

function esc(v) {
  return String(v ?? "")
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

const fr = (n) => String(n).replace(".", ",");

function dateFr(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : String(iso ?? "");
}

/**
 * Résumé du dossier, lisible et imprimable dans n'importe quel navigateur.
 * `d` : {compagnie, chantier:{nom, adresse, archive}, dateExport (ISO),
 *        heures (résumé), detail (lignes), extras, materiel, photos (nombres
 *        de fichiers), ignores}
 */
function htmlResume(d) {
  const h = d.heures;
  const lignesEmployes = h.parEmploye.map((e) => `<tr><td>${esc(e.nom)}</td>` +
    `<td class="n">${fr(e.jours)}</td><td class="n">${fr(e.heures)}</td>` +
    `<td class="n">${fr(e.voyagementPaye)}</td></tr>`).join("");
  const lignesExtras = d.extras.map((e) => `<tr><td>${esc(dateFr(e.dateTravaux))}</td>` +
    `<td>${esc(e.description)}</td><td>${esc(e.mainOeuvre)}</td><td>${esc(e.ajouteParNom)}</td>` +
    `<td>${e.fichierPhoto ? `<a href="${esc(e.fichierPhoto)}">photo</a>` : ""}</td></tr>`).join("");
  const lignesMateriel = d.materiel.map((m) => `<tr><td>${esc(m.texte)}</td>` +
    `<td>${esc(m.quantite)}</td><td>${m.complete ? "Obtenu" : "À obtenir"}</td>` +
    `<td>${esc(dateFr(m.dateAjout))}</td>` +
    `<td>${m.fichierPhoto ? `<a href="${esc(m.fichierPhoto)}">photo</a>` : ""}</td></tr>`).join("");
  const avertissement = d.ignores.length === 0 ? "" :
    `<p class="avert">Fichiers non inclus dans l'export (${d.ignores.length}) : ` +
    `${esc(d.ignores.slice(0, 20).join(", "))}${d.ignores.length > 20 ? "…" : ""}</p>`;

  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dossier — ${esc(d.chantier.nom)}</title>
<style>
body{font:14px/1.45 system-ui,Segoe UI,sans-serif;color:#1e1e1a;max-width:900px;margin:24px auto;padding:0 16px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px;border-bottom:2px solid #2f4a34;padding-bottom:4px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #c9c2b0;padding:5px 8px;text-align:left;vertical-align:top}
th{background:#eae2d0}td.n,th.n{text-align:right}.meta{color:#555}.tot{font-weight:700}
.avert{background:#fff3cd;padding:8px;border:1px solid #e0c36a}
@media print{body{margin:0}a{color:inherit;text-decoration:none}}
</style></head><body>
<h1>${esc(d.chantier.nom)}${d.chantier.archive ? " (archivé)" : ""}</h1>
<p class="meta">${esc(d.chantier.adresse)}<br>${esc(d.compagnie)} — export du ${esc(dateFr(d.dateExport))}</p>
${avertissement}
<h2>Résumé des heures</h2>
<p>Période : ${h.premierJour ? `${esc(dateFr(h.premierJour))} au ${esc(dateFr(h.dernierJour))}` : "aucune heure saisie"}
 — ${fr(h.joursTravailles)} jour(s) de travail, ${fr(h.journeesHomme)} journée(s)-homme.</p>
<table><tr><th>Employé</th><th class="n">Jours</th><th class="n">Heures travaillées</th><th class="n">Voyagement payé (h)</th></tr>
${lignesEmployes}
<tr class="tot"><td>Total</td><td class="n">${fr(h.journeesHomme)}</td><td class="n">${fr(h.totalHeures)}</td><td class="n">${fr(h.totalVoyagementPaye)}</td></tr></table>
<p class="meta">Le détail jour par jour est dans heures.csv.</p>
<h2>Extras (${d.extras.length})</h2>
${d.extras.length ? `<table><tr><th>Date</th><th>Description</th><th>Main-d'œuvre et temps</th><th>Saisi par</th><th>Photo</th></tr>${lignesExtras}</table>` : "<p>Aucun extra.</p>"}
<h2>Matériel (${d.materiel.length})</h2>
${d.materiel.length ? `<table><tr><th>Matériel</th><th>Quantité</th><th>État</th><th>Ajouté le</th><th>Photo</th></tr>${lignesMateriel}</table>` : "<p>Aucun matériel.</p>"}
<h2>Photos du chantier (${d.photos})</h2>
<p>${d.photos ? "Les photos sont dans le dossier « photos »." : "Aucune photo."}</p>
</body></html>`;
}

module.exports = {
  detailHeures, resumerHeures, cheminDepuisUrl, cheminDuChantier, nomSur, extension,
  cellule, csv, esc, htmlResume, dateFr, ajouterJours,
};
