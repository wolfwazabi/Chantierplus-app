// Anciens employés (loi 25 : minimiser, durée limitée, effacement possible).
//
// Quand un admin retire l'accès d'un employé (retirerAccesEmploye), la fiche reste un
// temps limité dans « Anciens employés » pour pouvoir le réactiver (employés
// saisonniers) : le NIP est détruit, seuls le nom, le courriel, le rôle, la date du
// retrait, la date de suppression automatique et un motif en liste fermée sont gardés.
// Le motif n'est JAMAIS du texte libre : un champ libre recevrait des renseignements de
// santé, qui sont sensibles (« absence-prolongee » couvre la maladie sans la nommer).
//
// Ce module ne dépend pas de Firebase (sauf HttpsError) pour être testé facilement.
const {HttpsError} = require("firebase-functions/v2/https");

// Deux saisons. Le client web lit la date réelle dans `supprimeApresLe`.
const RETENTION_ANCIENS_MOIS = 24;

const MOTIFS_RETRAIT = ["non-precise", "saisonnier", "depart-volontaire", "fin-contrat",
  "absence-prolongee", "autre"];

const TAILLE_LOT_PURGE = 100;

/** Motif de départ : liste fermée ; absent → « non-precise » ; autre chose → refusé. */
function lireMotif(valeur) {
  if (valeur === undefined || valeur === null) return "non-precise";
  if (typeof valeur !== "string" || !MOTIFS_RETRAIT.includes(valeur)) {
    throw new HttpsError("invalid-argument", "Motif de départ invalide.");
  }
  return valeur;
}

/**
 * Date de suppression automatique : `mois` mois civils après `depuisMs` (UTC). Le 31
 * janvier + 1 mois donne le dernier jour de février, jamais début mars.
 */
function dateSuppression(depuisMs, mois = RETENTION_ANCIENS_MOIS) {
  const d = new Date(depuisMs);
  const jour = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + mois);
  const dernier = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(jour, dernier));
  return d;
}

/**
 * Supprime les fiches « actif === false » dont l'échéance est passée, avec le même
 * nettoyage que supprimerEmploye (`nettoyer(employeeId)` : sessions, liens, codes).
 * Retourne seulement le nombre de fiches supprimées : aucune donnée personnelle ne
 * doit se retrouver dans les journaux.
 */
async function purgerAnciens({db, Timestamp, nettoyer, maintenant = Date.now()}) {
  let total = 0;
  for (;;) {
    const snap = await db.collection("employees")
        .where("actif", "==", false)
        .where("supprimeApresLe", "<=", Timestamp.fromMillis(maintenant))
        .limit(TAILLE_LOT_PURGE)
        .get();
    if (snap.empty) return total;
    for (const fiche of snap.docs) {
      await fiche.ref.delete();
      await nettoyer(fiche.id);
      total++;
    }
  }
}

module.exports = {
  RETENTION_ANCIENS_MOIS, MOTIFS_RETRAIT, lireMotif, dateSuppression, purgerAnciens,
};
