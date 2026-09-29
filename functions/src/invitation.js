const crypto = require("node:crypto");
const {defineString} = require("firebase-functions/params");
const {db, Timestamp, JOUR} = require("./commun");

// Adresse de la page de création du NIP (fonction creerNip). Le jeton est
// ajouté après « # » : le navigateur ne l'envoie jamais au serveur, il
// n'apparaît donc dans aucun journal.
const URL_CREATION_NIP = defineString("URL_CREATION_NIP");

const DUREE_INVITATION_MS = 7 * JOUR;

function hacherJeton(jeton) {
  return crypto.createHash("sha256").update(jeton).digest("hex");
}

/**
 * Crée (ou remplace) l'invitation d'un employé et retourne le lien à envoyer.
 * Un seul lien valide à la fois par employé ; usage unique ; 7 jours.
 */
async function creerInvitation(employeeId) {
  const jeton = crypto.randomBytes(32).toString("base64url");
  await db.collection("invitations_nip").doc(employeeId).set({
    jetonHash: hacherJeton(jeton),
    creeLe: Timestamp.now(),
    expireLe: Timestamp.fromMillis(Date.now() + DUREE_INVITATION_MS),
  });
  return `${URL_CREATION_NIP.value()}#e=${encodeURIComponent(employeeId)}&t=${jeton}`;
}

module.exports = {URL_CREATION_NIP, hacherJeton, creerInvitation};
