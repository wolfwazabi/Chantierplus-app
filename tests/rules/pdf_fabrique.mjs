// PDF minimaux fabriqués pour les tests (aucun document de client dans le dépôt).

/**
 * Un PDF valide de [pages] pages de largeur × hauteur points. [dessin] (page → texte du flux de
 * contenu) : traits, texte… La police F1 (Helvetica) est disponible.
 */
export function pdf({ pages = 1, largeur = 612, hauteur = 792, dessin = () => '' }) {
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

/** Les lignes du devis de test : description, quantité, montant, hauteur de la ligne. */
export const LIGNES_DEVIS = [
  ['Porte 30" moulee', '6', '1 234,56 $', 660],
  ['Quincaillerie', '6', '$89.95', 640],
  ["Main-d'oeuvre", '1', '450.00', 620],
  ['Total', '', '1 774,51 $', 600],
];

/** Un devis d'une page (police de 12 pt) : 4 montants. */
export const fluxDevis = () => {
  let s = 'BT /F1 12 Tf\n1 0 0 1 72 700 Tm (DEVIS 2026-112) Tj\n';
  for (const [desc, qte, montant, y] of LIGNES_DEVIS) {
    s += `1 0 0 1 72 ${y} Tm (${desc}) Tj\n`;
    if (qte) s += `1 0 0 1 300 ${y} Tm (${qte}) Tj\n`;
    s += `1 0 0 1 450 ${y} Tm (${montant}) Tj\n`;
  }
  return s + '1 0 0 1 72 560 Tm (Telephone 514-555-1234, le 2026-10-16) Tj\nET\n';
};
