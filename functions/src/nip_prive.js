// NIP haché : collection `employees_prive/{employeeId}` (serveur seul, aucune lecture ni écriture
// par les clients), au lieu du document `employees` que tout admin de la compagnie peut lire.
// `employees.nipCree` (booléen) indique seulement qu'un NIP existe, pour l'affichage
// (« NIP créé » ou « à créer »).
//
// Transition : l'ancien emplacement (`employees.pinHash`, `employees.pinModifieLe`) reste lu
// tant qu'une fiche n'a pas été migrée ; `migrerNipsPrives` déplace les fiches une à une,
// dans une transaction (copie PUIS retrait de l'ancien champ : personne n'est déconnecté).
// Toute nouvelle écriture de NIP va directement dans le nouvel emplacement.
//
// Ce module ne dépend pas de Firebase (tout est injecté) pour être testé facilement.

const COLLECTION_NIP = "employees_prive";

function refNip(db, employeeId) {
  return db.collection(COLLECTION_NIP).doc(employeeId);
}

const texteNonVide = (v) => (typeof v === "string" && v.length > 0 ? v : null);

/** Le NIP haché d'un employé : le nouvel emplacement d'abord, puis l'ancien (transition). */
function hashEnregistre(fiche, prive) {
  return texteNonVide(prive?.pinHash) ?? texteNonVide(fiche?.pinHash);
}

/** Un NIP existe-t-il ? (le booléen `nipCree` suffit, par prudence). */
function nipExiste(fiche, prive) {
  return hashEnregistre(fiche, prive) !== null || fiche?.nipCree === true;
}

/** Lit le NIP haché d'un employé (une lecture du document privé). */
async function lireHash(db, employeeId, fiche) {
  const prive = await refNip(db, employeeId).get();
  return hashEnregistre(fiche, prive.exists ? prive.data() : null);
}

/** Document privé à écrire pour un NIP (créé ou modifié). */
function donneesNipPrive({FieldValue, companyId, hash}) {
  return {pinHash: hash, pinModifieLe: FieldValue.serverTimestamp(), companyId};
}

/** Champs de la fiche `employees` quand un NIP existe : le booléen, et l'ancien champ retiré. */
function champsNipEcrit(FieldValue) {
  return {nipCree: true, pinHash: FieldValue.delete(), pinModifieLe: FieldValue.delete()};
}

/** Champs de la fiche quand le NIP est détruit (réinitialisation, retrait). */
function champsNipEfface(FieldValue) {
  return {nipCree: false, pinHash: FieldValue.delete(), pinModifieLe: FieldValue.delete()};
}

/**
 * Déplace les NIP restés dans `employees` vers `employees_prive`. Idempotente : peut être
 * relancée sans risque (une fiche déjà migrée est ignorée ; un NIP déjà présent dans le
 * nouvel emplacement n'est jamais écrasé par l'ancien). Retourne le NOMBRE de fiches
 * migrées : aucune donnée personnelle dans les journaux.
 */
async function migrerNipsPrives({db, FieldValue, taille = 100}) {
  let total = 0;
  for (;;) {
    const snap = await db.collection("employees").where("pinHash", ">", "").limit(taille).get();
    if (snap.empty) return total;
    let migrees = 0;
    for (const doc of snap.docs) {
      const fait = await db.runTransaction(async (t) => {
        const [fiche, prive] = await Promise.all([t.get(doc.ref), t.get(refNip(db, doc.id))]);
        if (!fiche.exists) return false;
        const f = fiche.data();
        if (texteNonVide(f.pinHash) === null) return false; // migrée entre-temps
        if (texteNonVide(prive.exists ? prive.data().pinHash : null) === null) {
          t.set(refNip(db, doc.id), {
            pinHash: f.pinHash,
            ...(f.pinModifieLe ? {pinModifieLe: f.pinModifieLe} : {}),
            companyId: f.companyId,
          });
        }
        t.update(doc.ref, champsNipEcrit(FieldValue));
        return true;
      });
      if (fait) migrees++;
    }
    total += migrees;
    // Aucune progression sur toute une page : on s'arrête plutôt que de tourner en rond.
    if (migrees === 0) return total;
  }
}

module.exports = {
  COLLECTION_NIP, refNip, hashEnregistre, nipExiste, lireHash, donneesNipPrive,
  champsNipEcrit, champsNipEfface, migrerNipsPrives,
};
