// Suppression définitive d'un chantier archivé (demande de l'entrepreneur, 16 oct. 2026).
//
// Réservée aux admins de la compagnie, seulement pour un chantier ARCHIVÉ, avec son nom tapé en
// confirmation. Irréversible : photos, documents (et copies sans montants), extras, travaux à
// compléter, matériel, commandes et leurs fichiers disparaissent. Les HEURES restent : chaque
// journée des feuilles de temps garde le nom du chantier (chantierNom), la paie ne change pas.
// Un petit journal (nom, adresse, date, auteur, décompte) est gardé, lisible par le serveur seul.
//
// Peut être rappelée si elle s'interrompt : la fiche du chantier n'est effacée qu'en dernier.
const {HttpsError} = require("firebase-functions/v2/https");
const {idValide, supprimerRequete, supprimerFichiers} = require("./suppression_compagnie");

// Collections dont chaque document porte companyId et chantierId.
const COLLECTIONS_DU_CHANTIER = [
  "chantier_photos", "chantier_travaux", "chantier_materiel", "chantier_extras",
  "chantier_commandes", "chantier_documents",
];

/** Le nom tapé et celui du chantier : espaces, majuscules et accents ignorés. */
function memeNom(a, b) {
  const n = (s) => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/\s+/g, " ").trim().toLowerCase();
  return n(a) !== "" && n(a) === n(b);
}

async function supprimerChantier({db, bucket, FieldValue, ctx, chantierId, confirmationNom}) {
  if (!idValide(chantierId) || chantierId === "_general") {
    throw new HttpsError("invalid-argument", "Chantier invalide.");
  }
  const ref = db.collection("chantiers").doc(chantierId);
  const snap = await ref.get();
  if (!snap.exists || snap.data().companyId !== ctx.companyId) {
    throw new HttpsError("not-found", "Chantier introuvable.");
  }
  const c = snap.data();
  if (c.archive !== true) {
    throw new HttpsError("failed-precondition", "Archivez d'abord le chantier : seul un chantier archivé se supprime.");
  }
  if (!memeNom(confirmationNom, c.nom)) {
    throw new HttpsError("invalid-argument", "Le nom tapé ne correspond pas au nom du chantier.");
  }
  const companyId = ctx.companyId;

  // Fichiers d'abord : une fiche restante permet de reprendre, un fichier orphelin non.
  const compteurs = {fichiers: await supprimerFichiers(bucket, `chantiers/${companyId}/${chantierId}/`)};
  const [exportsZip] = await bucket.getFiles({prefix: `exports/${companyId}/`});
  await Promise.all(exportsZip.filter((f) => f.name.endsWith(`_${chantierId}.zip`))
      .map((f) => f.delete({ignoreNotFound: true})));

  for (const col of COLLECTIONS_DU_CHANTIER) {
    compteurs[col] = await supprimerRequete(db, db.collection(col)
        .where("companyId", "==", companyId).where("chantierId", "==", chantierId));
  }
  // Regroupement des notifications de photos de ce chantier.
  const regroupees = await db.collection("notifications_regroupees").where("companyId", "==", companyId).get();
  await Promise.all(regroupees.docs.filter((d) => d.id.startsWith(`${companyId}_${chantierId}_`))
      .map((d) => d.ref.delete()));

  await db.collection("journal_chantiers_supprimes").add({
    companyId, chantierId, nom: c.nom ?? "", adresse: c.adresse ?? "",
    supprimeLe: FieldValue.serverTimestamp(), parEmployeeId: ctx.employeeId, compteurs,
  });
  await ref.delete();
  return compteurs;
}

module.exports = {supprimerChantier, memeNom, COLLECTIONS_DU_CHANTIER};
