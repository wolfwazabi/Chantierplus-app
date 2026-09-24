const crypto = require("node:crypto");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret, defineString} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

setGlobalOptions({region: "us-central1", maxInstances: 10});

// Clé secrète (Secret Manager) servant au hachage HMAC des NIP. Un NIP de 4 à
// 8 chiffres se casse instantanément par force brute s'il est haché sans clé ;
// avec une clé gardée côté serveur, une fuite de la base ne révèle rien.
// ATTENTION : changer cette clé invalide tous les NIP existants.
const PIN_PEPPER = defineSecret("PIN_PEPPER");

// Seul compte courriel autorisé à recevoir le claim superAdmin.
const SUPER_ADMIN_EMAIL = defineString("SUPER_ADMIN_EMAIL");

const ROLES = ["admin", "plus", "employe"];
const FORMAT_NIP = /^\d{4,8}$/;
const FORMAT_NUMERO = /^\d{1,10}$/;
const FORMAT_COURRIEL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$/;

// Limites anti-force brute (fenêtre glissante simple).
const FENETRE_MS = 15 * 60 * 1000;
const MAX_ECHECS_PAR_IP = 10;
const MAX_ECHECS_PAR_COMPAGNIE = 30;
const MAX_INSCRIPTIONS_PAR_IP = 3;
const FENETRE_INSCRIPTION_MS = 24 * 60 * 60 * 1000;

const MESSAGE_CONNEXION_INVALIDE = "Numéro de compagnie ou NIP invalide.";

// =============================================================================
// Utilitaires
// =============================================================================

function exigerAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  return request.auth;
}

function exigerAnonyme(request) {
  const auth = exigerAuth(request);
  if (auth.token.firebase?.sign_in_provider !== "anonymous") {
    throw new HttpsError("failed-precondition", "Déconnectez-vous du compte courriel avant de vous connecter à une compagnie.");
  }
  return auth;
}

function exigerSuperAdmin(request) {
  const auth = exigerAuth(request);
  if (auth.token.superAdmin !== true) {
    throw new HttpsError("permission-denied", "Accès réservé au super-admin.");
  }
  return auth;
}

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

function nipValide(pin) {
  const v = texte(pin, "NIP", {min: 4, max: 8});
  if (!FORMAT_NIP.test(v)) {
    throw new HttpsError("invalid-argument", "Le NIP doit contenir de 4 à 8 chiffres.");
  }
  return v;
}

/** HMAC déterministe (permet la recherche par égalité), lié à la compagnie. */
function hacherNip(companyId, pin) {
  return crypto.createHmac("sha256", PIN_PEPPER.value())
      .update(`${companyId}:${pin}`)
      .digest("hex");
}

function empreinteIp(request) {
  const ip = request.rawRequest?.ip || "inconnue";
  return crypto.createHash("sha256").update(ip).digest("hex").slice(0, 32);
}

/**
 * Compteur d'échecs à fenêtre fixe. `verifier` lance resource-exhausted si la
 * limite est atteinte ; `echec` incrémente. Des requêtes concurrentes peuvent
 * dépasser la limite de quelques unités : acceptable pour ce besoin.
 */
function limiteur(cle, max, fenetreMs) {
  const ref = db.collection("limites_connexion").doc(cle);
  return {
    async verifier() {
      const snap = await ref.get();
      if (!snap.exists) return;
      const {echecs = 0, debut} = snap.data();
      if (debut && Date.now() - debut.toMillis() < fenetreMs && echecs >= max) {
        throw new HttpsError("resource-exhausted", "Trop de tentatives. Réessayez dans quelques minutes.");
      }
    },
    async echec() {
      await db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        const maintenant = Timestamp.now();
        const expire = Timestamp.fromMillis(maintenant.toMillis() + fenetreMs);
        const d = snap.exists ? snap.data() : null;
        if (!d || !d.debut || maintenant.toMillis() - d.debut.toMillis() >= fenetreMs) {
          t.set(ref, {echecs: 1, debut: maintenant, expireLe: expire});
        } else {
          t.update(ref, {echecs: FieldValue.increment(1), expireLe: expire});
        }
      });
    },
    async reinitialiser() {
      await ref.delete();
    },
  };
}

/**
 * Contexte de l'employé appelant, avec les mêmes conditions que les règles
 * Firestore : session écrite par le serveur, employé existant dans la même
 * compagnie, compagnie approuvée.
 */
async function contexteEmploye(request) {
  const auth = exigerAnonyme(request);
  const sessionSnap = await db.collection("sessions").doc(auth.uid).get();
  const session = sessionSnap.exists ? sessionSnap.data() : null;
  if (!session?.employeeId || !session?.companyId) {
    throw new HttpsError("permission-denied", "Session invalide. Reconnectez-vous.");
  }
  const [empSnap, compSnap] = await Promise.all([
    db.collection("employees").doc(session.employeeId).get(),
    db.collection("companies").doc(session.companyId).get(),
  ]);
  if (!empSnap.exists || empSnap.data().companyId !== session.companyId ||
      !compSnap.exists || compSnap.data().statut !== "approuvee") {
    throw new HttpsError("permission-denied", "Session invalide. Reconnectez-vous.");
  }
  return {uid: auth.uid, employeeId: empSnap.id, employe: empSnap.data(), companyId: session.companyId};
}

async function contexteAdmin(request) {
  const ctx = await contexteEmploye(request);
  if (ctx.employe.role !== "admin") {
    throw new HttpsError("permission-denied", "Accès réservé aux administrateurs.");
  }
  return ctx;
}

// =============================================================================
// Connexion employé (numéro de compagnie + NIP)
// =============================================================================

exports.connexionEmploye = onCall({secrets: [PIN_PEPPER]}, async (request) => {
  const auth = exigerAnonyme(request);
  const numero = texte(request.data?.numeroCompagnie, "numéro de compagnie", {max: 10});
  const pin = texte(request.data?.pin, "NIP", {max: 32});

  const limiteIp = limiteur(`ip_${empreinteIp(request)}`, MAX_ECHECS_PAR_IP, FENETRE_MS);
  await limiteIp.verifier();

  // Message unique pour tous les échecs : ne pas révéler si un numéro existe.
  const echouer = async (limiteCompagnie) => {
    await limiteIp.echec();
    if (limiteCompagnie) await limiteCompagnie.echec();
    throw new HttpsError("not-found", MESSAGE_CONNEXION_INVALIDE);
  };

  if (!FORMAT_NUMERO.test(numero)) await echouer();

  const compSnap = await db.collection("companies")
      .where("numero", "==", numero)
      .where("statut", "==", "approuvee")
      .limit(1)
      .get();
  if (compSnap.empty) await echouer();
  const compagnie = compSnap.docs[0];

  const limiteCompagnie = limiteur(`co_${compagnie.id}`, MAX_ECHECS_PAR_COMPAGNIE, FENETRE_MS);
  await limiteCompagnie.verifier();

  const employes = db.collection("employees").where("companyId", "==", compagnie.id);
  let empSnap = await employes.where("pinHash", "==", hacherNip(compagnie.id, pin)).limit(1).get();

  // Migration paresseuse : NIP encore stocké en clair (données antérieures).
  if (empSnap.empty) {
    const ancien = await employes.where("pin", "==", pin).limit(1).get();
    if (!ancien.empty) {
      await ancien.docs[0].ref.update({pinHash: hacherNip(compagnie.id, pin), pin: FieldValue.delete()});
      empSnap = ancien;
    }
  }
  if (empSnap.empty) await echouer(limiteCompagnie);

  const employe = empSnap.docs[0];
  const data = employe.data();

  await db.collection("sessions").doc(auth.uid).set({
    employeeId: employe.id,
    companyId: compagnie.id,
    creeLe: FieldValue.serverTimestamp(),
  });
  await limiteIp.reinitialiser();

  return {
    id: employe.id,
    nom: data.nom || "",
    role: ROLES.includes(data.role) ? data.role : "employe",
    estProprietaire: data.estProprietaire === true,
    companyId: compagnie.id,
    companyNom: compagnie.data().nomEntreprise || "",
  };
});

// =============================================================================
// Inscription d'une compagnie
// =============================================================================

exports.inscrireCompagnie = onCall({secrets: [PIN_PEPPER]}, async (request) => {
  exigerAnonyme(request);
  const d = request.data || {};

  const nomEntreprise = texte(d.nomEntreprise, "nom de l'entreprise", {max: 120});
  const nomLegal = texte(d.nomLegal, "nom légal", {max: 200});
  const secteur = texte(d.secteur, "secteur", {max: 100});
  const telephone = texte(d.telephone, "téléphone", {min: 0, max: 30});
  const nomAdmin = texte(d.nomAdmin, "nom de l'administrateur", {max: 100});
  const pinAdmin = nipValide(d.pinAdmin);
  const emailAdmin = texte(d.emailAdmin, "courriel", {max: 254}).toLowerCase();
  if (!FORMAT_COURRIEL.test(emailAdmin)) {
    throw new HttpsError("invalid-argument", "Courriel invalide.");
  }
  let nombreEmployes = null;
  if (d.nombreEmployes !== undefined && d.nombreEmployes !== null) {
    if (!Number.isInteger(d.nombreEmployes) || d.nombreEmployes < 1 || d.nombreEmployes > 100000) {
      throw new HttpsError("invalid-argument", "Nombre d'employés invalide.");
    }
    nombreEmployes = d.nombreEmployes;
  }

  const limite = limiteur(`insc_${empreinteIp(request)}`, MAX_INSCRIPTIONS_PAR_IP, FENETRE_INSCRIPTION_MS);
  await limite.verifier();

  const compteurRef = db.collection("compteurs").doc("companies");
  const companyRef = db.collection("companies").doc();
  const employeRef = db.collection("employees").doc();

  // Tout ou rien : compteur, compagnie, propriétaire et données privées.
  const numero = await db.runTransaction(async (t) => {
    const compteur = await t.get(compteurRef);
    const nouveau = (compteur.exists ? compteur.data().dernierNumero : 1000) + 1;
    t.set(compteurRef, {dernierNumero: nouveau});
    t.set(companyRef, {
      numero: String(nouveau),
      nomEntreprise,
      nomLegal,
      secteur,
      nombreEmployes,
      telephone,
      statut: "attente",
      dateCreation: FieldValue.serverTimestamp(),
    });
    // Coordonnées de récupération : jamais lisibles par le client.
    t.set(db.collection("companies_prive").doc(companyRef.id), {
      emailAdmin,
      proprietaireId: employeRef.id,
    });
    t.set(employeRef, {
      companyId: companyRef.id,
      nom: nomAdmin,
      role: "admin",
      estProprietaire: true,
      pinHash: hacherNip(companyRef.id, pinAdmin),
    });
    return String(nouveau);
  });

  // Chaque inscription compte dans la limite (anti-pourriel).
  await limite.echec();
  return {numero};
});

// =============================================================================
// Gestion des employés (admin de la compagnie)
// =============================================================================

exports.enregistrerEmploye = onCall({secrets: [PIN_PEPPER]}, async (request) => {
  const ctx = await contexteAdmin(request);
  const d = request.data || {};
  const employeeId = d.employeeId == null ? null : texte(d.employeeId, "employeeId", {max: 128});
  const nom = texte(d.nom, "nom", {max: 100});
  const pinFourni = d.pin !== undefined && d.pin !== null && String(d.pin).trim() !== "";
  const pin = pinFourni ? nipValide(d.pin) : null;
  if (!ROLES.includes(d.role)) {
    throw new HttpsError("invalid-argument", "Rôle invalide.");
  }
  if (!employeeId && !pin) {
    throw new HttpsError("invalid-argument", "Un NIP est requis pour un nouvel employé.");
  }

  const employes = db.collection("employees");
  const ref = employeeId ? employes.doc(employeeId) : employes.doc();

  await db.runTransaction(async (t) => {
    let existant = null;
    if (employeeId) {
      const snap = await t.get(ref);
      if (!snap.exists || snap.data().companyId !== ctx.companyId) {
        throw new HttpsError("not-found", "Employé introuvable.");
      }
      existant = snap.data();
    }

    // Le propriétaire reste toujours admin.
    const role = existant?.estProprietaire === true ? "admin" : d.role;

    const maj = {nom, role};
    if (pin) {
      const pinHash = hacherNip(ctx.companyId, pin);
      const [dejaHache, dejaClair] = await Promise.all([
        t.get(employes.where("companyId", "==", ctx.companyId).where("pinHash", "==", pinHash).limit(2)),
        t.get(employes.where("companyId", "==", ctx.companyId).where("pin", "==", pin).limit(2)),
      ]);
      const conflit = [...dejaHache.docs, ...dejaClair.docs].some((doc) => doc.id !== ref.id);
      if (conflit) {
        throw new HttpsError("already-exists", "Ce NIP est déjà utilisé par un autre employé de votre compagnie.");
      }
      maj.pinHash = pinHash;
    } else if (typeof existant?.pin === "string") {
      maj.pinHash = hacherNip(ctx.companyId, existant.pin);
    }

    if (existant) {
      t.update(ref, {...maj, pin: FieldValue.delete()});
    } else {
      t.set(ref, {...maj, companyId: ctx.companyId, estProprietaire: false});
    }
  });

  return {id: ref.id};
});

exports.supprimerEmploye = onCall(async (request) => {
  const ctx = await contexteAdmin(request);
  const employeeId = texte(request.data?.employeeId, "employeeId", {max: 128});
  if (employeeId === ctx.employeeId) {
    throw new HttpsError("failed-precondition", "Vous ne pouvez pas retirer votre propre compte.");
  }

  const ref = db.collection("employees").doc(employeeId);
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists || snap.data().companyId !== ctx.companyId) {
      throw new HttpsError("not-found", "Employé introuvable.");
    }
    if (snap.data().estProprietaire === true) {
      throw new HttpsError("failed-precondition", "Le propriétaire ne peut pas être retiré.");
    }
    t.delete(ref);
  });

  // Nettoyage des sessions (les règles les invalident déjà, l'employé n'existant plus).
  const sessions = await db.collection("sessions").where("employeeId", "==", employeeId).get();
  const batch = db.batch();
  sessions.docs.forEach((s) => batch.delete(s.ref));
  if (!sessions.empty) await batch.commit();

  return {ok: true};
});

// =============================================================================
// Super-admin
// =============================================================================

/**
 * Pose le claim superAdmin sur le compte courriel configuré (SUPER_ADMIN_EMAIL),
 * une fois son courriel vérifié. Idempotent. Refus générique pour tout autre
 * compte (ne révèle pas quelle adresse est configurée).
 */
exports.activerSuperAdmin = onCall(async (request) => {
  const auth = exigerAuth(request);
  const attendu = SUPER_ADMIN_EMAIL.value().trim().toLowerCase();
  const email = (auth.token.email || "").toLowerCase();
  if (!attendu || auth.token.firebase?.sign_in_provider !== "password" ||
      auth.token.email_verified !== true || email !== attendu) {
    throw new HttpsError("permission-denied", "Non autorisé.");
  }
  if (auth.token.superAdmin !== true) {
    await getAuth().setCustomUserClaims(auth.uid, {superAdmin: true});
  }
  return {ok: true};
});

exports.approuverCompagnie = onCall(async (request) => {
  const auth = exigerSuperAdmin(request);
  const companyId = texte(request.data?.companyId, "companyId", {max: 128});
  if (typeof request.data?.approuver !== "boolean") {
    throw new HttpsError("invalid-argument", "Décision invalide.");
  }
  const approuver = request.data.approuver;

  const ref = db.collection("companies").doc(companyId);
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Compagnie introuvable.");
    }
    if (snap.data().statut !== "attente") {
      throw new HttpsError("failed-precondition", "Cette demande a déjà été traitée.");
    }
    t.update(ref, {
      statut: approuver ? "approuvee" : "refusee",
      dateDecision: FieldValue.serverTimestamp(),
      decidePar: auth.uid,
    });
  });

  return {ok: true};
});

/**
 * Migration unique : remplace tout NIP stocké en clair par son empreinte.
 * Idempotent ; à lancer une fois après le déploiement.
 */
exports.migrerNips = onCall({secrets: [PIN_PEPPER], timeoutSeconds: 540}, async (request) => {
  exigerSuperAdmin(request);
  let migres = 0;
  let curseur = null;
  for (;;) {
    let q = db.collection("employees").orderBy("__name__").limit(300);
    if (curseur) q = q.startAfter(curseur);
    const page = await q.get();
    if (page.empty) break;
    const batch = db.batch();
    let n = 0;
    for (const doc of page.docs) {
      const {pin, companyId} = doc.data();
      if (typeof pin === "string" && typeof companyId === "string") {
        batch.update(doc.ref, {pinHash: hacherNip(companyId, pin.trim()), pin: FieldValue.delete()});
        n++;
      }
    }
    if (n > 0) await batch.commit();
    migres += n;
    curseur = page.docs[page.docs.length - 1];
  }
  return {migres};
});
