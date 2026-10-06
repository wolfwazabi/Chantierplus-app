// Suppression définitive d'une compagnie et de tout ce qui lui appartient.
//
// Réservée au Proprio de l'application (voir la fonction supprimerCompagnie).
// Irréversible : employés, admins, contremaîtres, chantiers, photos, documents,
// feuilles de temps, commandes, fichiers du Storage et sessions disparaissent.
// Seul un petit journal (numéro, nom, date, décompte) est conservé.
//
// La suppression est reprise telle quelle si elle s'interrompt (délai dépassé,
// panne) : la compagnie reste en statut « suppression », donc inaccessible, et
// la fiche de la compagnie n'est effacée qu'en tout dernier.
const {HttpsError} = require("firebase-functions/v2/https");

// Un identifiant Firestore ne contient jamais « / » : on refuse tout le reste
// avant de bâtir un chemin de fichiers (chantiers/<id>/) à effacer.
const FORMAT_ID = /^[A-Za-z0-9_-]{1,128}$/;

// Collections dont chaque document porte le champ companyId, les chantiers en dernier.
const COLLECTIONS_PAR_COMPAGNIE = [
  "chantier_photos", "chantier_travaux", "chantier_materiel", "chantier_extras",
  "chantier_commandes", "chantier_documents", "feuilles_temps", "chantiers",
];

// Compteurs anti-abus (limites_connexion) liés à un employé ou à une compagnie.
const LIMITES_PAR_EMPLOYE = ["feuille", "export", "nip", "assistant_h"];
const LIMITES_PAR_COMPAGNIE = ["co", "assistant_j"];

const LOT_DOCUMENTS = 300;
const LOT_EMPLOYES = 50; // 50 × 7 documents < 500 écritures par lot
const LOT_FICHIERS = 25;
const MAX_ECRITURES = 450;

function idValide(id) {
  return typeof id === "string" && FORMAT_ID.test(id);
}

async function supprimerRefs(db, refs) {
  for (let i = 0; i < refs.length; i += MAX_ECRITURES) {
    const lot = db.batch();
    refs.slice(i, i + MAX_ECRITURES).forEach((ref) => lot.delete(ref));
    await lot.commit();
  }
}

/** Supprime, page par page, tous les documents qu'une requête retourne. */
async function supprimerRequete(db, requete) {
  let total = 0;
  for (;;) {
    const snap = await requete.limit(LOT_DOCUMENTS).get();
    if (snap.empty) return total;
    await supprimerRefs(db, snap.docs.map((d) => d.ref));
    total += snap.size;
  }
}

async function supprimerFichiers(bucket, prefixe) {
  const [fichiers] = await bucket.getFiles({prefix: prefixe});
  for (let i = 0; i < fichiers.length; i += LOT_FICHIERS) {
    await Promise.all(fichiers.slice(i, i + LOT_FICHIERS).map((f) => f.delete({ignoreNotFound: true})));
  }
  return fichiers.length;
}

async function supprimerSessionsCompagnie(db, companyId) {
  return supprimerRequete(db, db.collection("sessions").where("companyId", "==", companyId));
}

/**
 * Étape 1 : vérifie la demande et verrouille la compagnie (statut « suppression » :
 * connexions et accès Firestore refusés immédiatement). Lance une HttpsError si la
 * demande est refusée ; rien n'est alors modifié.
 *
 * - `numeroConfirme` doit être exactement le numéro de la compagnie (double
 *   vérification : le client le fait saisir, le serveur le revérifie) ;
 * - la compagnie qui contient la fiche du Proprio est intouchable.
 */
async function verrouiller({db, FieldValue, companyId, numeroConfirme, ctx}) {
  if (!idValide(companyId)) throw new HttpsError("invalid-argument", "Compagnie invalide.");
  const ref = db.collection("companies").doc(companyId);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compagnie introuvable.");
    const compagnie = snap.data();
    if (typeof compagnie.numero !== "string" || compagnie.numero !== numeroConfirme) {
      throw new HttpsError("invalid-argument", "Le numéro saisi ne correspond pas à cette compagnie.");
    }
    const ficheProprio = ctx.idProprioApp ?
      await t.get(db.collection("employees").doc(ctx.idProprioApp)) : null;
    if (ctx.companyId === companyId || ficheProprio?.data()?.companyId === companyId) {
      throw new HttpsError("failed-precondition",
          "La compagnie du Proprio de l'application ne peut pas être supprimée.");
    }
    const reprise = compagnie.statut === "suppression";
    t.update(ref, reprise ?
      {suppressionReprise: FieldValue.serverTimestamp()} :
      {
        statut: "suppression",
        statutAvant: compagnie.statut ?? null,
        suppressionDebut: FieldValue.serverTimestamp(),
        suppressionPar: ctx.employeeId,
      });
    return {id: snap.id, ...compagnie, statutAvant: reprise ? compagnie.statutAvant ?? null : compagnie.statut ?? null};
  });
}

/**
 * Étape 2 : efface les données. Chaque phase peut être rejouée sans effet de
 * bord. La fiche de la compagnie est supprimée en dernier ; un journal sans
 * donnée personnelle (numéro, nom, décompte) reste dans journal_suppressions.
 */
async function effacerDonnees({db, bucket, FieldValue, compagnie, ctx}) {
  const companyId = compagnie.id;
  const compteurs = {};

  // 1. Plus aucun accès : sessions d'abord (les règles Storage ne lisent que la session).
  compteurs.sessions = await supprimerSessionsCompagnie(db, companyId);

  // 2. Fichiers.
  compteurs.fichiers = await supprimerFichiers(bucket, `chantiers/${companyId}/`) +
    await supprimerFichiers(bucket, `exports/${companyId}/`);

  // 3. Données de chantier.
  for (const nom of COLLECTIONS_PAR_COMPAGNIE) {
    compteurs[nom] = await supprimerRequete(db, db.collection(nom).where("companyId", "==", companyId));
  }

  // 4. Employés (super-admin, admins, contremaîtres, employés) et ce qui s'y rattache.
  compteurs.employes = 0;
  const employes = db.collection("employees").where("companyId", "==", companyId);
  for (;;) {
    const snap = await employes.limit(LOT_EMPLOYES).get();
    if (snap.empty) break;
    const refs = [];
    for (const e of snap.docs) {
      refs.push(e.ref,
          db.collection("reinitialisations_nip").doc(e.id),
          db.collection("invitations_nip").doc(e.id),
          ...LIMITES_PAR_EMPLOYE.map((p) => db.collection("limites_connexion").doc(`${p}_${e.id}`)));
    }
    await supprimerRefs(db, refs);
    compteurs.employes += snap.size;
  }

  // 5. Compteurs de la compagnie et données privées.
  await supprimerRefs(db, [
    ...LIMITES_PAR_COMPAGNIE.map((p) => db.collection("limites_connexion").doc(`${p}_${companyId}`)),
    db.collection("companies_prive").doc(companyId),
  ]);

  // 6. Une connexion ouverte pendant la suppression : on balaie une dernière fois.
  compteurs.sessions += await supprimerSessionsCompagnie(db, companyId);

  // 7. Journal (id = compagnie : rejouer la suppression ne le duplique pas), puis la fiche.
  await db.collection("journal_suppressions").doc(companyId).set({
    numero: compagnie.numero,
    nomEntreprise: compagnie.nomEntreprise ?? "",
    statutAvant: compagnie.statutAvant ?? null,
    supprimeLe: FieldValue.serverTimestamp(),
    parEmployeeId: ctx.employeeId,
    compteurs,
  });
  await db.collection("companies").doc(companyId).delete();
  return compteurs;
}

module.exports = {
  verrouiller, effacerDonnees, idValide, supprimerRefs,
  COLLECTIONS_PAR_COMPAGNIE, LIMITES_PAR_EMPLOYE, LIMITES_PAR_COMPAGNIE,
};
