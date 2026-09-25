const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const {defineBoolean, defineSecret} = require("firebase-functions/params");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {logger} = require("firebase-functions");

const db = getFirestore();

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

// Clé HMAC des NIP (Secret Manager). Un NIP de 4 à 8 chiffres haché sans clé
// se retrouve instantanément par force brute ; avec cette clé gardée côté
// serveur, une fuite de la base ne révèle rien.
// ATTENTION : changer cette clé invalide tous les NIP existants.
const PIN_PEPPER = defineSecret("PIN_PEPPER");

// App Check : en mode « surveillance » tant que d'anciennes versions de l'app
// (sans App Check) sont en circulation. Passer à true pour l'imposer.
const APP_CHECK_OBLIGATOIRE = defineBoolean("APP_CHECK_OBLIGATOIRE", {default: false});

// Régions : Montréal pour tout ; us-central1 seulement pour les fonctions
// appelées par les anciennes versions de l'app (à retirer ensuite).
const REGION = "northamerica-northeast1";
const REGIONS_AVEC_ANCIENNES_VERSIONS = [REGION, "us-central1"];

const ROLES = ["admin", "plus", "employe"];
const ROLES_GESTION = ["admin", "plus"];

// NIP : 4 chiffres acceptés pour les NIP existants ; 6 minimum pour tout
// nouveau NIP choisi ou généré.
const FORMAT_NIP_EXISTANT = /^\d{4,8}$/;
const FORMAT_NIP_NOUVEAU = /^\d{6,8}$/;
const FORMAT_NUMERO = /^\d{1,10}$/;
const FORMAT_COURRIEL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$/;

// -----------------------------------------------------------------------------
// Validation
// -----------------------------------------------------------------------------

/** Valide une chaîne (après trim) ; lance invalid-argument sinon. */
function texte(valeur, champ, {min = 1, max = 200} = {}) {
  if (valeur === undefined || valeur === null) valeur = "";
  if (typeof valeur !== "string") {
    throw new HttpsError("invalid-argument", `Champ invalide : ${champ}.`);
  }
  const v = valeur.trim();
  if (v.length < min || v.length > max) {
    throw new HttpsError("invalid-argument",
        min > 0 && v.length === 0 ? `Champ requis : ${champ}.` : `Longueur invalide : ${champ} (max ${max}).`);
  }
  return v;
}

function courriel(valeur, champ = "courriel") {
  const v = texte(valeur, champ, {max: 254}).toLowerCase();
  if (!FORMAT_COURRIEL.test(v)) {
    throw new HttpsError("invalid-argument", "Courriel invalide.");
  }
  return v;
}

function nouveauNip(valeur, champ = "NIP") {
  const v = texte(valeur, champ, {min: 6, max: 8});
  if (!FORMAT_NIP_NOUVEAU.test(v)) {
    throw new HttpsError("invalid-argument", "Le NIP doit contenir de 6 à 8 chiffres.");
  }
  return v;
}

// -----------------------------------------------------------------------------
// NIP
// -----------------------------------------------------------------------------

/** HMAC déterministe (permet la recherche par égalité), lié à la compagnie. */
function hacherNip(companyId, pin) {
  return crypto.createHmac("sha256", PIN_PEPPER.value())
      .update(`${companyId}:${pin}`)
      .digest("hex");
}

function egalConstant(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

function nombreAleatoire(chiffres) {
  const max = 10 ** chiffres;
  return String(crypto.randomInt(0, max)).padStart(chiffres, "0");
}

/**
 * NIP aléatoire de 6 chiffres, évitant ceux déjà présents dans la compagnie
 * (pour ne pas rendre ambiguë la connexion « NIP seul » des anciennes
 * versions). Personne n'est informé des valeurs écartées : aucune fuite.
 */
async function genererNipUnique(companyId) {
  for (let essai = 0; essai < 20; essai++) {
    const pin = nombreAleatoire(6);
    const pris = await db.collection("employees")
        .where("companyId", "==", companyId)
        .where("pinHash", "==", hacherNip(companyId, pin))
        .limit(1).get();
    if (pris.empty) return pin;
  }
  throw new HttpsError("internal", "Impossible de générer un NIP. Réessayez.");
}

// -----------------------------------------------------------------------------
// Appelant
// -----------------------------------------------------------------------------

function empreinte(valeur) {
  return crypto.createHash("sha256").update(String(valeur)).digest("hex").slice(0, 32);
}

function empreinteIp(request) {
  return empreinte(request.rawRequest?.ip || "inconnue");
}

/** Vérifie App Check (imposé seulement si APP_CHECK_OBLIGATOIRE). */
function verifierAppCheck(request, nomFonction) {
  if (request.app) return;
  if (APP_CHECK_OBLIGATOIRE.value()) {
    throw new HttpsError("failed-precondition", "Application non vérifiée. Mettez l'application à jour.");
  }
  logger.info("Appel sans jeton App Check", {fonction: nomFonction});
}

function exigerAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  return request.auth;
}

function exigerAnonyme(request) {
  const auth = exigerAuth(request);
  if (auth.token.firebase?.sign_in_provider !== "anonymous") {
    throw new HttpsError("failed-precondition",
        "Déconnectez-vous du compte courriel avant de vous connecter à une compagnie.");
  }
  return auth;
}

/**
 * Contexte de l'employé appelant, avec les mêmes conditions que les règles
 * Firestore : session écrite par le serveur, employé existant dans la même
 * compagnie, compagnie approuvée.
 */
/**
 * Identifiant de la fiche employé du super-admin (un seul pour toute l'app),
 * défini à la main dans config/super_admin { employeeId } via la console.
 * Aucune fonction ni aucune règle ne permet de le modifier depuis l'app.
 */
async function superAdminId() {
  const snap = await db.collection("config").doc("super_admin").get();
  const id = snap.exists ? snap.data().employeeId : null;
  return typeof id === "string" && id.length > 0 ? id : null;
}

async function contexteEmploye(request) {
  const auth = exigerAnonyme(request);
  const sessionSnap = await db.collection("sessions").doc(auth.uid).get();
  const session = sessionSnap.exists ? sessionSnap.data() : null;
  if (!session?.employeeId || !session?.companyId) {
    throw new HttpsError("permission-denied", "Session invalide. Reconnectez-vous.");
  }
  const [empSnap, compSnap, idSuperAdmin] = await Promise.all([
    db.collection("employees").doc(session.employeeId).get(),
    db.collection("companies").doc(session.companyId).get(),
    superAdminId(),
  ]);
  if (!empSnap.exists || empSnap.data().companyId !== session.companyId ||
      !compSnap.exists || compSnap.data().statut !== "approuvee") {
    throw new HttpsError("permission-denied", "Session invalide. Reconnectez-vous.");
  }
  const employe = empSnap.data();
  return {
    uid: auth.uid,
    employeeId: empSnap.id,
    employe,
    companyId: session.companyId,
    compagnie: compSnap.data(),
    // Pouvoirs super-admin : seulement avec une session ouverte par courriel.
    estSuperAdmin: idSuperAdmin === empSnap.id && session.methode === "courriel",
    idSuperAdmin,
  };
}

async function contexteAdmin(request) {
  const ctx = await contexteEmploye(request);
  if (ctx.employe.role !== "admin") {
    throw new HttpsError("permission-denied", "Accès réservé aux administrateurs.");
  }
  return ctx;
}

async function contexteSuperAdmin(request) {
  const ctx = await contexteEmploye(request);
  if (!ctx.estSuperAdmin) {
    throw new HttpsError("permission-denied", "Accès réservé au super-admin.");
  }
  return ctx;
}

// -----------------------------------------------------------------------------
// Limites (anti-force brute / anti-pourriel)
// -----------------------------------------------------------------------------

/**
 * Compteur à fenêtre fixe dans limites_connexion/{cle}. `verifier` lance
 * resource-exhausted si la limite est atteinte ; `compter` incrémente. Des
 * requêtes concurrentes peuvent dépasser la limite de quelques unités.
 * Le champ expireLe sert à la politique TTL de Firestore.
 */
function limiteur(cle, max, fenetreMs) {
  const ref = db.collection("limites_connexion").doc(cle);
  return {
    async verifier() {
      const snap = await ref.get();
      if (!snap.exists) return;
      const {compte = 0, debut} = snap.data();
      if (debut && Date.now() - debut.toMillis() < fenetreMs && compte >= max) {
        throw new HttpsError("resource-exhausted", "Trop de tentatives. Réessayez plus tard.");
      }
    },
    async compter() {
      await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const maintenant = Timestamp.now();
        const expireLe = Timestamp.fromMillis(maintenant.toMillis() + fenetreMs);
        const d = snap.exists ? snap.data() : null;
        if (!d || !d.debut || maintenant.toMillis() - d.debut.toMillis() >= fenetreMs) {
          t.set(ref, {compte: 1, debut: maintenant, expireLe});
        } else {
          t.update(ref, {compte: FieldValue.increment(1), expireLe});
        }
      });
    },
    async reinitialiser() {
      await ref.delete();
    },
  };
}

const MINUTE = 60 * 1000;
const HEURE = 60 * MINUTE;
const JOUR = 24 * HEURE;

async function supprimerSessionsDe(employeeId, saufUid = null) {
  const sessions = await db.collection("sessions").where("employeeId", "==", employeeId).get();
  const batch = db.batch();
  let n = 0;
  sessions.docs.forEach((s) => {
    if (s.id !== saufUid) {
      batch.delete(s.ref);
      n++;
    }
  });
  if (n > 0) await batch.commit();
}

module.exports = {
  db, FieldValue, Timestamp, logger,
  PIN_PEPPER, APP_CHECK_OBLIGATOIRE, REGION, REGIONS_AVEC_ANCIENNES_VERSIONS,
  ROLES, ROLES_GESTION, FORMAT_NIP_EXISTANT, FORMAT_NUMERO,
  texte, courriel, nouveauNip, hacherNip, egalConstant, nombreAleatoire, genererNipUnique,
  empreinte, empreinteIp, verifierAppCheck, exigerAuth, exigerAnonyme,
  superAdminId, contexteEmploye, contexteAdmin, contexteSuperAdmin,
  limiteur, supprimerSessionsDe, MINUTE, HEURE, JOUR,
};
