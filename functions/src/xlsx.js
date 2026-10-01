// Classeur Excel (.xlsx) minimal, sans dépendance : un fichier ZIP de petits
// fichiers XML. Contrairement à un CSV, il s'ouvre pareil en français et en
// anglais : les nombres restent des nombres et les dates des dates (Excel les
// affiche selon la langue de l'utilisateur).
const yazl = require("yazl");

const XML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n";
const NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
const NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const NS_REL = "http://schemas.openxmlformats.org/package/2006/relationships";

// Styles (index dans cellXfs) : 0 normal, 1 en-tête, 2 nombre 0,00, 3 date, 4 texte à la ligne, 5 total (gras).
const STYLE = {normal: 0, entete: 1, nombre: 2, date: 3, texte: 4, total: 5};

/** Texte sûr pour XML 1.0 : retire les caractères de contrôle interdits, échappe les symboles. */
function echapper(valeur) {
  return String(valeur ?? "")
      // eslint-disable-next-line no-control-regex
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, "")
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
}

/** « A », « B »… (26 colonnes au plus : largement assez pour nos tableaux). */
function lettre(i) {
  if (i < 0 || i > 25) throw new Error("trop de colonnes");
  return String.fromCharCode(65 + i);
}

/** Nom d'onglet valide : 31 caractères, sans [ ] : * ? / \ , jamais vide. */
function nomFeuille(nom, utilises = new Set()) {
  let n = String(nom ?? "").replace(/[[\]:*?/\\]/g, " ").replace(/^'+|'+$/g, "").trim().slice(0, 31) || "Feuille";
  let k = 2;
  while (utilises.has(n.toLowerCase())) {
    const suffixe = ` ${k++}`;
    n = `${n.slice(0, 31 - suffixe.length)}${suffixe}`;
  }
  utilises.add(n.toLowerCase());
  return n;
}

/** Numéro de série Excel d'une date « AAAA-MM-JJ » (jours depuis le 30/12/1899), ou null. */
function serieDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ""));
  if (!m) return null;
  const jours = (Date.UTC(+m[1], +m[2] - 1, +m[3]) - Date.UTC(1899, 11, 30)) / 86400000;
  return Number.isInteger(jours) && jours > 0 ? jours : null;
}

function cellule(ref, valeur, type, style) {
  if (valeur === null || valeur === undefined || valeur === "") {
    return style === STYLE.entete ? `<c r="${ref}" s="${style}"/>` : "";
  }
  if (type === "nombre") {
    const n = Number(valeur);
    return Number.isFinite(n) ? `<c r="${ref}" s="${style}"><v>${n}</v></c>` : "";
  }
  if (type === "date") {
    const s = serieDate(valeur);
    return s === null ?
      `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${echapper(valeur)}</t></is></c>` :
      `<c r="${ref}" s="${style}"><v>${s}</v></c>`;
  }
  // Texte : toujours une chaîne (jamais une formule), même s'il commence par « = ».
  return `<c r="${ref}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${echapper(valeur)}</t></is></c>`;
}

/**
 * Onglet : { nom, colonnes: [{titre, cle, type: 'texte'|'nombre'|'date', largeur}], lignes, total? }
 * `total` : { libelle, valeurs: { cle: nombre } } ajoute une ligne en gras.
 */
function xmlFeuille(feuille) {
  const cols = feuille.colonnes;
  const largeurs = cols.map((c, i) =>
    `<col min="${i + 1}" max="${i + 1}" width="${c.largeur ?? 18}" customWidth="1"/>`).join("");
  const rangees = [];
  rangees.push(`<row r="1">${cols.map((c, i) =>
    cellule(`${lettre(i)}1`, c.titre, "texte", STYLE.entete)).join("")}</row>`);
  feuille.lignes.forEach((ligne, r) => {
    const n = r + 2;
    rangees.push(`<row r="${n}">${cols.map((c, i) => {
      const style = c.type === "nombre" ? STYLE.nombre : c.type === "date" ? STYLE.date : STYLE.texte;
      return cellule(`${lettre(i)}${n}`, ligne[c.cle], c.type ?? "texte", style);
    }).join("")}</row>`);
  });
  if (feuille.total) {
    const n = feuille.lignes.length + 2;
    rangees.push(`<row r="${n}">${cols.map((c, i) => {
      if (i === 0) return cellule(`${lettre(i)}${n}`, feuille.total.libelle, "texte", STYLE.total);
      const v = feuille.total.valeurs?.[c.cle];
      return v === undefined ? "" : cellule(`${lettre(i)}${n}`, v, "nombre", STYLE.total);
    }).join("")}</row>`);
  }
  return `${XML}<worksheet xmlns="${NS}"><sheetViews><sheetView workbookViewId="0">` +
    "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>" +
    `<cols>${largeurs}</cols><sheetData>${rangees.join("")}</sheetData></worksheet>`;
}

const STYLES = `${XML}<styleSheet xmlns="${NS}">` +
  "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>" +
  "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill>" +
  "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFEAE2D0\"/><bgColor indexed=\"64\"/></patternFill></fill></fills>" +
  "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>" +
  "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>" +
  "<cellXfs count=\"6\">" +
  "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" +
  "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/>" +
  "<xf numFmtId=\"2\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" +
  "<xf numFmtId=\"14\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" +
  "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyAlignment=\"1\"><alignment vertical=\"top\" wrapText=\"1\"/></xf>" +
  "<xf numFmtId=\"2\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\"/>" +
  "</cellXfs>" +
  "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>";

/** Construit le classeur (Buffer .xlsx). */
function classeur(feuilles) {
  if (!Array.isArray(feuilles) || feuilles.length === 0) throw new Error("au moins une feuille");
  const utilises = new Set();
  const noms = feuilles.map((f) => nomFeuille(f.nom, utilises));
  const zip = new yazl.ZipFile();
  const ajouter = (chemin, contenu) => zip.addBuffer(Buffer.from(contenu, "utf8"), chemin);

  ajouter("[Content_Types].xml", `${XML}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
    "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
    "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" +
    "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" +
    feuilles.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ` +
      "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>").join("") +
    "</Types>");
  ajouter("_rels/.rels", `${XML}<Relationships xmlns="${NS_REL}">` +
    `<Relationship Id="rId1" Type="${NS_R}/officeDocument" Target="xl/workbook.xml"/></Relationships>`);
  ajouter("xl/workbook.xml", `${XML}<workbook xmlns="${NS}" xmlns:r="${NS_R}"><sheets>` +
    noms.map((n, i) => `<sheet name="${echapper(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("") +
    "</sheets></workbook>");
  ajouter("xl/_rels/workbook.xml.rels", `${XML}<Relationships xmlns="${NS_REL}">` +
    feuilles.map((_, i) => `<Relationship Id="rId${i + 1}" Type="${NS_R}/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("") +
    `<Relationship Id="rId${feuilles.length + 1}" Type="${NS_R}/styles" Target="styles.xml"/></Relationships>`);
  ajouter("xl/styles.xml", STYLES);
  feuilles.forEach((f, i) => ajouter(`xl/worksheets/sheet${i + 1}.xml`, xmlFeuille(f)));

  return new Promise((resolve, reject) => {
    const morceaux = [];
    zip.outputStream.on("data", (c) => morceaux.push(c));
    zip.outputStream.on("error", reject);
    zip.outputStream.on("end", () => resolve(Buffer.concat(morceaux)));
    zip.end();
  });
}

module.exports = {classeur, serieDate, nomFeuille, echapper, lettre};
