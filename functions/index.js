const {initializeApp} = require("firebase-admin/app");
initializeApp();

const {setGlobalOptions} = require("firebase-functions/v2");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  db, FieldValue, Timestamp,
  PIN_PEPPER, REGION, ROLES, ROLES_GESTION, FORMAT_NIP, FORMAT_NUMERO,
  texte, courriel, nouveauNip, hacherNip, egalConstant, nombreAleatoire,
  empreinte, empreinteIp, verifierAppCheck, exigerAnonyme,
  proprioAppId, contexteEmploye, contexteAdmin, contexteProprioApp,
  limiteur, supprimerSessionsDe, revoquerAppareilsWeb, MINUTE, HEURE, JOUR,
} = require("./src/commun");
const {RESEND_API_KEY, envoyerCourriel, courrielConfigure, NOM_APP} = require("./src/courriel");
const {hacherJeton, creerInvitation} = require("./src/invitation");
const {
  reglesPaieDepuis, analyserLundi, echeanceSemaine, lundiCourant, lireJours, calculerFeuille, recalculerFeuille,
} = require("./src/feuille_temps");
const {getStorage} = require("firebase-admin/storage");
const {logger} = require("firebase-functions");
const crypto = require("node:crypto");
const yazl = require("yazl");
const dossier = require("./src/dossier_chantier");
const xlsx = require("./src/xlsx");
const PAGE_CREER_NIP = require("./src/page_creer_nip");
const assistantCharpente = require("./src/assistant_charpente");
const lecturePlans = require("./src/lecture_plans");
const suppression = require("./src/suppression_compagnie");
const archivage = require("./src/anciens_employes");
const nipPrive = require("./src/nip_prive");

setGlobalOptions({region: REGION, maxInstances: 10});

const SECRETS_NIP = [PIN_PEPPER];
const SECRETS_NIP_COURRIEL = [PIN_PEPPER, RESEND_API_KEY];

const MESSAGE_CONNEXION_INVALIDE = "Numéro de compagnie, courriel ou NIP invalide.";
const MESSAGE_ADMINS_RESERVES = "Seul le super-admin de la compagnie peut nommer, modifier ou retirer un admin.";
const MESSAGE_ANCIEN_EMPLOYE = "Cette personne figure dans « Anciens employés » : réactivez-la ou supprimez sa fiche.";

// Identifiant de document Firestore reçu d'un client : jamais de « / » (un chemin forgé).
const FORMAT_ID = /^[A-Za-z0-9_-]{1,128}$/;

function compagniesApprouvees(numero) {
  return db.collection("companies")
      .where("numero", "==", numero)
      .where("statut", "==", "approuvee")
      .limit(1)
      .get();
}

// =============================================================================
// Connexion employé : numéro de compagnie + courriel + NIP
// =============================================================================

/**
 * Numéro de compagnie + courriel + NIP : retrouve l'employé, ou échoue avec le
 * message unique MESSAGE_CONNEXION_INVALIDE (limiteurs par adresse IP et par
 * compagnie). Commun à connexionEmploye (application) et connexionWeb (espace
 * web). Ne crée aucune session.
 */
async function identifierParNip(request) {
  const auth = exigerAnonyme(request);
  const d = request.data || {};
  const numero = texte(d.numeroCompagnie, "numéro de compagnie", {max: 10});
  const adresse = courriel(d.courriel);
  const pin = texte(d.pin, "NIP", {max: 32});

  const limiteIp = limiteur(`ip_${empreinteIp(request)}`, 10, 15 * MINUTE);
  await limiteIp.verifier();

  // Message unique pour tous les échecs : ne pas révéler ce qui existe.
  const echouer = async (limiteCompagnie) => {
    await limiteIp.compter();
    if (limiteCompagnie) await limiteCompagnie.compter();
    throw new HttpsError("not-found", MESSAGE_CONNEXION_INVALIDE);
  };

  if (!FORMAT_NUMERO.test(numero) || !FORMAT_NIP.test(pin)) await echouer();

  const compSnap = await compagniesApprouvees(numero);
  if (compSnap.empty) await echouer();
  const compagnie = compSnap.docs[0];

  const limiteCompagnie = limiteur(`co_${compagnie.id}`, 30, 15 * MINUTE);
  await limiteCompagnie.verifier();

  const snap = await db.collection("employees")
      .where("companyId", "==", compagnie.id)
      .where("courriel", "==", adresse)
      .limit(2)
      .get();
  // Un ancien employé (actif === false) n'a plus de NIP : même échec générique.
  const candidat = snap.size === 1 && snap.docs[0].data().actif !== false ? snap.docs[0] : null;
  const hashNip = candidat ? await nipPrive.lireHash(db, candidat.id, candidat.data()) : null;
  const employe = candidat && egalConstant(hashNip, hacherNip(compagnie.id, pin)) ? candidat : null;
  if (!employe) await echouer(limiteCompagnie);

  return {auth, employe, compagnie, limiteIp};
}

/** Réponse de connexion : identique pour l'application et l'espace web. */
function profilConnexion(employe, compagnie, estProprioApp) {
  const data = employe.data();
  return {
    id: employe.id,
    nom: data.nom || "",
    courriel: data.courriel,
    role: ROLES.includes(data.role) ? data.role : "employe",
    estProprietaire: data.estProprietaire === true,
    estProprioApp,
    companyId: compagnie.id,
    companyNom: compagnie.data().nomEntreprise || "",
  };
}

exports.connexionEmploye = onCall({secrets: SECRETS_NIP}, async (request) => {
  verifierAppCheck(request, "connexionEmploye");
  const {auth, employe, compagnie, limiteIp} = await identifierParNip(request);

  const estProprioApp = (await proprioAppId()) === employe.id;
  await db.collection("sessions").doc(auth.uid).set({
    employeeId: employe.id,
    companyId: compagnie.id,
    // Indicatif pour l'interface seulement : les règles et les fonctions
    // revérifient config/proprio_app à chaque requête.
    proprioApp: estProprioApp,
    creeLe: FieldValue.serverTimestamp(),
  });
  await limiteIp.reinitialiser();

  return profilConnexion(employe, compagnie, estProprioApp);
});

// =============================================================================
// Connexion de l'espace web : NIP, puis code à usage unique reçu par courriel
// =============================================================================

const MESSAGE_WEB_RESERVE = "Cet espace est réservé aux super-admins, admins et contremaîtres.";
const DUREE_CODE_WEB_MS = 10 * MINUTE;
const DUREE_SESSION_WEB_MS = 12 * HEURE;
const ESSAIS_CODE_WEB = 5;
const FORMAT_CODE_WEB = /^\d{6}$/;

// Appareil de confiance : après un code valide, et seulement si l'utilisateur coche la
// case (décochée par défaut), un jeton aléatoire remplace le code par courriel pendant
// 30 jours. Le NIP reste TOUJOURS exigé. Seul le hachage du jeton est conservé, avec
// des dates : ni adresse IP ni agent utilisateur (loi 25).
const DUREE_APPAREIL_MS = 30 * JOUR;
const MAX_APPAREILS_PAR_EMPLOYE = 5;
const FORMAT_JETON_APPAREIL = /^[A-Za-z0-9_-]{43}$/; // 32 octets en base64url

function hacherJetonAppareil(jeton) {
  return hacherNip("appareil_web", jeton);
}

/** Un jeton est valable s'il existe, n'est pas expiré et appartient à CET employé et CETTE compagnie. */
async function appareilValide(jeton, employe, compagnie) {
  if (typeof jeton !== "string" || !FORMAT_JETON_APPAREIL.test(jeton)) return false;
  const hash = hacherJetonAppareil(jeton);
  const ref = db.collection("appareils_web").doc(hash);
  const snap = await ref.get();
  if (!snap.exists) return false;
  const a = snap.data();
  const fin = a.expireLe && typeof a.expireLe.toMillis === "function" ? a.expireLe.toMillis() : 0;
  if (fin <= Date.now()) {
    await ref.delete();
    return false;
  }
  return egalConstant(a.jetonHash, hash) && a.employeeId === employe.id && a.companyId === compagnie.id;
}

/** Crée un appareil de confiance et retourne son jeton (une seule fois) ; au plus 5 par employé. */
async function creerAppareilWeb(employe, compagnieId) {
  const jeton = crypto.randomBytes(32).toString("base64url");
  const hash = hacherJetonAppareil(jeton);
  await db.collection("appareils_web").doc(hash).set({
    employeeId: employe.id,
    companyId: compagnieId,
    jetonHash: hash,
    creeLe: FieldValue.serverTimestamp(),
    expireLe: Timestamp.fromMillis(Date.now() + DUREE_APPAREIL_MS),
  });
  // Plafond : au-delà de 5, le plus ancien est supprimé.
  const tous = await db.collection("appareils_web").where("employeeId", "==", employe.id).get();
  const depuis = (d) => (d.data().creeLe?.toMillis?.() ?? 0);
  const plusAnciens = tous.docs.filter((d) => d.id !== hash).sort((a, b) => depuis(a) - depuis(b))
      .slice(0, Math.max(0, tous.size - MAX_APPAREILS_PAR_EMPLOYE));
  await Promise.all(plusAnciens.map((d) => d.ref.delete()));
  return {jeton, expireDans: DUREE_APPAREIL_MS / 1000};
}

async function ecrireSessionWeb(uid, employeeId, companyId, estProprioApp) {
  await db.collection("sessions").doc(uid).set({
    employeeId,
    companyId,
    proprioApp: estProprioApp,
    creeLe: FieldValue.serverTimestamp(),
    canal: "web",
    // Les règles Firestore et Storage et contexteEmploye refusent la session
    // une fois cette date passée.
    expireLe: Timestamp.fromMillis(Date.now() + DUREE_SESSION_WEB_MS),
  });
}

/** « philippe@gmail.com » → « p***@gmail.com ». */
function masquerCourriel(adresse) {
  const [local, domaine] = adresse.split("@");
  return `${local.slice(0, 1)}***@${domaine}`;
}

/**
 * Première étape : numéro de compagnie + courriel + NIP, avec les mêmes
 * vérifications et limites que connexionEmploye. Les employés sont refusés ici,
 * côté serveur, sans session ni code. Pour un admin ou un contremaître, un code à
 * 6 chiffres (10 minutes) est envoyé par courriel ; aucune session n'est créée
 * avant validerConnexionWeb.
 *
 * Appareil de confiance : si `jetonAppareil` (reçu d'une connexion précédente où
 * l'utilisateur avait coché la case) est valable pour CET employé, la session s'ouvre
 * sans code : {etape: "connecte", ...profil}. Le NIP, lui, vient d'être vérifié comme
 * toujours. Jeton absent, inconnu, expiré ou d'un autre employé : flux normal avec
 * code, sans dire pourquoi, avec `jetonRefuse: true` si un jeton avait été envoyé
 * (le client efface alors le sien). Ce chemin ne consomme pas la limite d'envoi de codes.
 */
exports.connexionWeb = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "connexionWeb");
  const {auth, employe, compagnie, limiteIp} = await identifierParNip(request);
  const data = employe.data();
  if (!ROLES_GESTION.includes(data.role)) {
    throw new HttpsError("permission-denied", MESSAGE_WEB_RESERVE);
  }

  const jetonAppareil = request.data?.jetonAppareil;
  const jetonFourni = jetonAppareil !== undefined && jetonAppareil !== null && jetonAppareil !== "";
  // Rôle de gestion, fiche active et compagnie approuvée viennent d'être vérifiés par
  // identifierParNip et ci-dessus : les mêmes conditions que validerConnexionWeb.
  if (jetonFourni && await appareilValide(jetonAppareil, employe, compagnie)) {
    const estProprioApp = (await proprioAppId()) === employe.id;
    await ecrireSessionWeb(auth.uid, employe.id, compagnie.id, estProprioApp);
    await db.collection("connexions_web").doc(auth.uid).delete(); // un code resté en attente
    await limiteIp.reinitialiser();
    return {etape: "connecte", ...profilConnexion(employe, compagnie, estProprioApp)};
  }

  exigerCourrielDisponible();

  const limiteEnvoi = limiteur(`connweb_${employe.id}`, 5, HEURE);
  await limiteEnvoi.verifier();
  await limiteEnvoi.compter();

  const code = nombreAleatoire(6);
  const ref = db.collection("connexions_web").doc(auth.uid);
  // Une nouvelle demande remplace la précédente (l'ancien code cesse de valoir).
  await ref.set({
    employeeId: employe.id,
    companyId: compagnie.id,
    codeHash: hacherCode(employe.id, code),
    expireLe: Timestamp.fromMillis(Date.now() + DUREE_CODE_WEB_MS),
    essais: 0,
    creeLe: FieldValue.serverTimestamp(),
  });
  const envoye = await envoyerCourriel({
    a: data.courriel,
    sujet: `Code de connexion — ${NOM_APP}`,
    lignes: [
      `Bonjour ${data.nom || ""},`,
      `Votre code de connexion : ${code}`,
      "Ce code expire dans 10 minutes. Si vous n'avez pas essayé de vous connecter à l'espace web, " +
        "ignorez ce message et avertissez votre employeur.",
    ],
  });
  if (!envoye) {
    await ref.delete();
    throw new HttpsError("unavailable", "Le code n'a pas pu être envoyé. Réessayez dans un instant.");
  }
  await limiteIp.reinitialiser();

  return {
    etape: "code",
    expireDans: DUREE_CODE_WEB_MS / 1000,
    courrielMasque: masquerCourriel(data.courriel),
    ...(jetonFourni ? {jetonRefuse: true} : {}),
  };
});

/**
 * Seconde étape : le code reçu par courriel. 5 essais ratés → le code est
 * supprimé et il faut recommencer la première étape. Le code ne sert qu'une
 * fois. Succès : session de 12 h (canal « web ») et même réponse que
 * connexionEmploye. Avec `faireConfiance: true` (case cochée par l'utilisateur), la
 * réponse contient en plus `appareil: {jeton, expireDans}`, UNE SEULE FOIS : le jeton
 * dispense du code pendant 30 jours sur cet appareil (le NIP reste exigé).
 */
exports.validerConnexionWeb = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "validerConnexionWeb");
  const auth = exigerAnonyme(request);
  const code = texte(request.data?.code, "code", {max: 10});
  if (!FORMAT_CODE_WEB.test(code)) {
    throw new HttpsError("invalid-argument", "Le code contient 6 chiffres.");
  }

  const ref = db.collection("connexions_web").doc(auth.uid);
  const verdict = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) return {etat: "expire"};
    const c = snap.data();
    if (!c.expireLe || typeof c.expireLe.toMillis !== "function" || c.expireLe.toMillis() <= Date.now()) {
      t.delete(ref);
      return {etat: "expire"};
    }
    if (egalConstant(c.codeHash, hacherCode(c.employeeId, code))) {
      t.delete(ref);
      return {etat: "ok", employeeId: c.employeeId, companyId: c.companyId};
    }
    const essais = (Number.isInteger(c.essais) ? c.essais : 0) + 1;
    if (essais >= ESSAIS_CODE_WEB) {
      t.delete(ref);
      return {etat: "epuise"};
    }
    t.update(ref, {essais});
    return {etat: "mauvais"};
  });
  // details.raison : le client web distingue ces cas sans lire le texte du message
  // (« code-invalide » = on peut réessayer ; tout le reste = retour à la première étape).
  if (verdict.etat === "expire") {
    throw new HttpsError("failed-precondition", "Code expiré. Recommencez.", {raison: "code-expire"});
  }
  if (verdict.etat === "epuise") {
    throw new HttpsError("resource-exhausted", "Trop d'essais. Recommencez la connexion.",
        {raison: "essais-epuises"});
  }
  if (verdict.etat === "mauvais") {
    throw new HttpsError("permission-denied", "Code invalide.", {raison: "code-invalide"});
  }

  // Entre les deux étapes, l'employé a pu être retiré ou changer de rôle.
  const [empSnap, compSnap, idProprio] = await Promise.all([
    db.collection("employees").doc(verdict.employeeId).get(),
    db.collection("companies").doc(verdict.companyId).get(),
    proprioAppId(),
  ]);
  if (!empSnap.exists || empSnap.data().companyId !== verdict.companyId ||
      empSnap.data().actif === false ||
      !compSnap.exists || compSnap.data().statut !== "approuvee") {
    throw new HttpsError("permission-denied", "Session invalide. Reconnectez-vous.",
        {raison: "session-invalide"});
  }
  if (!ROLES_GESTION.includes(empSnap.data().role)) {
    throw new HttpsError("permission-denied", MESSAGE_WEB_RESERVE, {raison: "role-refuse"});
  }

  const estProprioApp = idProprio === empSnap.id;
  await ecrireSessionWeb(auth.uid, empSnap.id, verdict.companyId, estProprioApp);

  const profil = profilConnexion(empSnap, compSnap, estProprioApp);
  if (request.data?.faireConfiance !== true) return profil;

  const appareil = await creerAppareilWeb(empSnap, verdict.companyId);
  await envoyerCourriel({
    a: empSnap.data().courriel,
    sujet: `Appareil de confiance — ${NOM_APP}`,
    lignes: [
      `Bonjour ${empSnap.data().nom || ""},`,
      "Vous avez choisi de faire confiance à un appareil pendant 30 jours : sur cet appareil, " +
        "le code de connexion par courriel ne vous sera pas demandé pendant cette période " +
        "(votre NIP reste toujours exigé).",
      "Si ce n'était pas vous, changez votre NIP : tous les appareils de confiance seront alors retirés.",
    ],
  });
  return {...profil, appareil};
});

/**
 * « Ne plus faire confiance à cet appareil » : retire l'appareil dont le jeton est fourni.
 * Utilisateur anonyme, sans session ; répond toujours {ok: true} (aucun oracle) ; limité
 * par adresse IP. Posséder le jeton suffit pour le révoquer.
 */
exports.revoquerAppareilWeb = onCall({secrets: SECRETS_NIP}, async (request) => {
  verifierAppCheck(request, "revoquerAppareilWeb");
  exigerAnonyme(request);
  const limite = limiteur(`revoc_ip_${empreinteIp(request)}`, 20, HEURE);
  await limite.verifier();
  await limite.compter();
  const jeton = request.data?.jeton;
  if (typeof jeton === "string" && FORMAT_JETON_APPAREIL.test(jeton)) {
    await db.collection("appareils_web").doc(hacherJetonAppareil(jeton)).delete();
  }
  return {ok: true};
});

// =============================================================================
// Inscription et approbation des compagnies
// =============================================================================

exports.inscrireCompagnie = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "inscrireCompagnie");
  exigerAnonyme(request);
  const d = request.data || {};

  const nomEntreprise = texte(d.nomEntreprise, "nom de l'entreprise", {max: 120});
  const nomLegal = texte(d.nomLegal, "nom légal", {max: 200});
  const secteur = texte(d.secteur, "secteur", {max: 100});
  const telephone = texte(d.telephone, "téléphone", {min: 0, max: 30});
  const nomAdmin = texte(d.nomAdmin, "nom du super-admin", {max: 100});
  const emailAdmin = courriel(d.emailAdmin);
  const pinAdmin = nouveauNip(d.pinAdmin);
  let nombreEmployes = null;
  if (d.nombreEmployes !== undefined && d.nombreEmployes !== null) {
    if (!Number.isInteger(d.nombreEmployes) || d.nombreEmployes < 1 || d.nombreEmployes > 100000) {
      throw new HttpsError("invalid-argument", "Nombre d'employés invalide.");
    }
    nombreEmployes = d.nombreEmployes;
  }

  const limite = limiteur(`insc_${empreinteIp(request)}`, 3, JOUR);
  await limite.verifier();

  const compteurRef = db.collection("compteurs").doc("companies");
  const companyRef = db.collection("companies").doc();
  const employeRef = db.collection("employees").doc();

  // Tout ou rien : compteur, compagnie, super-admin et données privées.
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
    t.set(db.collection("companies_prive").doc(companyRef.id), {emailAdmin, proprietaireId: employeRef.id});
    // Le propriétaire de la compagnie en est le super-admin.
    t.set(employeRef, {
      companyId: companyRef.id,
      nom: nomAdmin,
      courriel: emailAdmin,
      role: "admin",
      estProprietaire: true,
      nipCree: true,
    });
    t.set(nipPrive.refNip(db, employeRef.id), nipPrive.donneesNipPrive({
      FieldValue, companyId: companyRef.id, hash: hacherNip(companyRef.id, pinAdmin),
    }));
    return String(nouveau);
  });

  await limite.compter();
  await envoyerCourriel({
    a: emailAdmin,
    sujet: `Demande d'inscription reçue — compagnie n° ${numero}`,
    lignes: [
      `Bonjour ${nomAdmin},`,
      `Nous avons bien reçu la demande d'inscription de ${nomEntreprise} à ${NOM_APP}.`,
      `Votre numéro de compagnie : ${numero}`,
      "Vous recevrez un courriel dès que votre compagnie sera approuvée.",
    ],
  });
  return {numero};
});

exports.approuverCompagnie = onCall({secrets: [RESEND_API_KEY]}, async (request) => {
  verifierAppCheck(request, "approuverCompagnie");
  const ctx = await contexteProprioApp(request);
  const companyId = texte(request.data?.companyId, "companyId", {max: 128});
  if (typeof request.data?.approuver !== "boolean") {
    throw new HttpsError("invalid-argument", "Décision invalide.");
  }
  const approuver = request.data.approuver;

  const ref = db.collection("companies").doc(companyId);
  const compagnie = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Compagnie introuvable.");
    if (snap.data().statut !== "attente") {
      throw new HttpsError("failed-precondition", "Cette demande a déjà été traitée.");
    }
    t.update(ref, {
      statut: approuver ? "approuvee" : "refusee",
      dateDecision: FieldValue.serverTimestamp(),
      decidePar: ctx.employeeId,
    });
    return snap.data();
  });

  const prive = await db.collection("companies_prive").doc(companyId).get();
  if (prive.exists && prive.data().emailAdmin) {
    await envoyerCourriel({
      a: prive.data().emailAdmin,
      sujet: approuver ? `Votre compagnie est approuvée — n° ${compagnie.numero}` : "Demande d'inscription refusée",
      lignes: approuver ? [
        `Bonne nouvelle : ${compagnie.nomEntreprise} est maintenant active sur ${NOM_APP}.`,
        `Connectez-vous avec le numéro de compagnie ${compagnie.numero}, votre courriel et votre NIP.`,
      ] : [
        `La demande d'inscription de ${compagnie.nomEntreprise} n'a pas été approuvée.`,
        "Répondez à ce courriel pour toute question.",
      ],
    });
  }
  return {ok: true};
});

/**
 * Supprime définitivement une compagnie et tout ce qu'elle contient (employés,
 * admins, contremaîtres, chantiers, photos, documents, feuilles de temps,
 * commandes, fichiers). Réservé au Proprio de l'application, qui doit envoyer le
 * numéro exact de la compagnie ; la sienne est protégée. Peut être rappelée si
 * elle s'interrompt : elle reprend où elle s'était arrêtée.
 */
exports.supprimerCompagnie = onCall({timeoutSeconds: 540, memory: "512MiB"}, async (request) => {
  verifierAppCheck(request, "supprimerCompagnie");
  const ctx = await contexteProprioApp(request);
  const companyId = texte(request.data?.companyId, "companyId", {max: 128});
  const numeroConfirme = texte(request.data?.confirmationNumero, "numéro de confirmation", {max: 10});

  const compagnie = await suppression.verrouiller({db, FieldValue, companyId, numeroConfirme, ctx});
  const bucket = getStorage().bucket(BUCKET_STOCKAGE);
  const supprime = await suppression.effacerDonnees({db, bucket, FieldValue, compagnie, ctx});
  logger.warn("Compagnie supprimée", {
    companyId, numero: compagnie.numero, par: ctx.employeeId, supprime,
  });
  return {ok: true, supprime};
});

// =============================================================================
// Gestion des employés (admins de la compagnie)
// =============================================================================

// mode : « nouveau » (création de la fiche), « reinit » (NIP réinitialisé par l'admin),
// « rappel » (même invitation renvoyée à qui n'a pas encore créé son NIP) ou « retour »
// (ancien employé réactivé : nouveau NIP).
const TEXTES_INVITATION = {
  retour: (c) => ({
    sujet: `Bon retour chez ${c.nomEntreprise} — ${NOM_APP}`,
    intro: `Bon retour ! ${c.nomEntreprise} a réactivé votre accès à ${NOM_APP}. ` +
      "Votre ancien NIP n'a pas été conservé : créez-en un nouveau.",
  }),
  nouveau: (c) => ({
    sujet: `Bienvenue chez ${c.nomEntreprise} — ${NOM_APP}`,
    intro: `Votre inscription est confirmée : ${c.nomEntreprise} vous a créé un accès à ${NOM_APP}.`,
  }),
  reinit: (c) => ({
    sujet: `Créez votre nouveau NIP — ${NOM_APP}`,
    intro: `${c.nomEntreprise} a réinitialisé votre NIP. L'ancien ne fonctionne plus.`,
  }),
  rappel: (c) => ({
    sujet: `Rappel : créez votre NIP — ${NOM_APP}`,
    intro: `Voici de nouveau votre invitation à ${NOM_APP} de la part de ${c.nomEntreprise}.`,
  }),
};

async function envoyerInvitation(employe, lien, compagnie, mode) {
  const {sujet, intro} = TEXTES_INVITATION[mode](compagnie);
  return envoyerCourriel({
    a: employe.courriel,
    sujet,
    lignes: [
      `Bonjour ${employe.nom},`,
      intro,
      `Numéro de compagnie : ${compagnie.numero}\nCourriel : ${employe.courriel}`,
      `Créez votre NIP en ouvrant ce lien (valide 7 jours, une seule fois) :\n${lien}`,
      "Vous pourrez ensuite vous connecter avec votre numéro de compagnie, votre courriel et votre NIP.",
      "Si vous n'attendiez pas ce courriel, ignorez-le.",
    ],
  });
}

/**
 * Crée ou modifie un employé. Le NIP n'est jamais choisi par l'admin :
 * l'employé reçoit par courriel son numéro de compagnie et un lien à usage
 * unique pour créer lui-même son NIP (création, ou modification avec
 * reinitialiserNip : l'ancien NIP est alors désactivé). Si le courriel ne
 * peut pas partir, le lien est retourné une seule fois à l'admin.
 *
 * Mode renvoiInvitation (avec employeeId) : renvoie l'invitation à un employé
 * qui n'a pas encore créé son NIP, sans rien désactiver (pinHash et sessions
 * intacts). Refusé si le NIP existe déjà ; 3 envois par heure et par employé.
 *
 * Seul le super-admin de la compagnie (estProprietaire) peut nommer un admin,
 * modifier un admin ou changer le rôle d'un admin. Un admin peut modifier sa
 * propre fiche (nom, courriel), mais pas son rôle.
 */
exports.enregistrerEmploye = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "enregistrerEmploye");
  const ctx = await contexteAdmin(request);
  const d = request.data || {};
  const employeeId = d.employeeId == null ? null : texte(d.employeeId, "employeeId", {max: 128});
  const nom = texte(d.nom, "nom complet", {max: 100});
  const adresse = courriel(d.courriel);
  if (!ROLES.includes(d.role)) throw new HttpsError("invalid-argument", "Rôle invalide.");
  const renvoi = d.renvoiInvitation === true;
  if (renvoi && (!employeeId || d.reinitialiserNip === true)) {
    throw new HttpsError("invalid-argument", "Le renvoi d'invitation concerne un employé existant, sans réinitialisation.");
  }
  const invitationDemandee = !employeeId || d.reinitialiserNip === true || renvoi;
  const appelantSuperAdmin = ctx.employe.estProprietaire === true;

  const employes = db.collection("employees");
  const ref = employeeId ? employes.doc(employeeId) : employes.doc();
  const soiMeme = ref.id === ctx.employeeId;
  const limiteRenvoi = renvoi ? limiteur(`renvoi_${ref.id}`, 3, HEURE) : null;
  if (limiteRenvoi) await limiteRenvoi.verifier();

  let roleAvant = null;
  const enregistre = await db.runTransaction(async (t) => {
    let existant = null;
    if (employeeId) {
      const snap = await t.get(ref);
      if (!snap.exists || snap.data().companyId !== ctx.companyId) {
        throw new HttpsError("not-found", "Employé introuvable.");
      }
      existant = snap.data();
      roleAvant = existant.role;
      // Un ancien employé ne se modifie pas : on le réactive ou on supprime sa fiche.
      if (existant.actif === false) throw new HttpsError("failed-precondition", MESSAGE_ANCIEN_EMPLOYE);
    }
    const memeCourriel = await t.get(employes
        .where("companyId", "==", ctx.companyId).where("courriel", "==", adresse).limit(2));
    const doublon = memeCourriel.docs.find((doc) => doc.id !== ref.id);
    if (doublon) {
      throw new HttpsError("already-exists", doublon.data().actif === false ?
        MESSAGE_ANCIEN_EMPLOYE : "Ce courriel est déjà utilisé par un autre employé de votre compagnie.");
    }

    // Le super-admin de la compagnie reste admin.
    const role = existant?.estProprietaire === true ? "admin" : d.role;
    if (soiMeme && role !== existant.role) {
      throw new HttpsError("permission-denied", "Vous ne pouvez pas changer votre propre rôle.");
    }
    const toucheUnAdmin = role === "admin" || existant?.role === "admin";
    if (toucheUnAdmin && !soiMeme && !appelantSuperAdmin) {
      throw new HttpsError("permission-denied", MESSAGE_ADMINS_RESERVES);
    }

    // Renvoi : seul le serveur peut garantir, au moment de l'écriture, que le NIP
    // n'a pas été créé entre-temps (il serait effacé par une réinitialisation).
    if (renvoi) {
      const prive = await t.get(nipPrive.refNip(db, ref.id));
      if (nipPrive.nipExiste(existant, prive.exists ? prive.data() : null)) {
        throw new HttpsError("failed-precondition", "Cet employé a déjà créé son NIP.");
      }
    }

    const maj = {nom, courriel: adresse, role};
    if (existant) {
      // Réinitialisation : l'ancien NIP cesse de fonctionner immédiatement.
      if (invitationDemandee && !renvoi) {
        t.update(ref, {...maj, ...nipPrive.champsNipEfface(FieldValue)});
        t.delete(nipPrive.refNip(db, ref.id));
      } else {
        t.update(ref, maj);
      }
    } else {
      // Pas de NIP tant que l'employé ne l'a pas créé avec son lien.
      t.set(ref, {...maj, companyId: ctx.companyId, estProprietaire: false, nipCree: false});
    }
    return {...existant, ...maj};
  });

  // Passé au rôle « employé » : plus d'espace web, donc plus d'appareils de confiance.
  if (ROLES_GESTION.includes(roleAvant) && !ROLES_GESTION.includes(enregistre.role)) {
    await revoquerAppareilsWeb(ref.id);
  }
  if (!invitationDemandee) return {id: ref.id};
  if (limiteRenvoi) await limiteRenvoi.compter();
  // Réinitialisation : les sessions de l'employé sont coupées. Un simple renvoi
  // ne touche à rien (l'employé n'a pas encore de NIP ni de session).
  if (employeeId && !renvoi) await supprimerSessionsDe(ref.id, soiMeme ? ctx.uid : null);
  const lien = await creerInvitation(ref.id);
  const envoye = await envoyerInvitation(enregistre, lien, ctx.compagnie,
    !employeeId ? "nouveau" : (renvoi ? "rappel" : "reinit"));
  return envoye ?
    {id: ref.id, courrielEnvoye: true} :
    {id: ref.id, courrielEnvoye: false, lienInvitation: lien};
});

/**
 * Page de création du NIP (lien d'invitation reçu par courriel).
 * GET : la page ; POST {employeeId, jeton, nip} : crée le NIP.
 * Jeton à usage unique, 7 jours, comparé par empreinte ; tentatives limitées.
 */
exports.creerNip = onRequest({secrets: SECRETS_NIP_COURRIEL}, async (req, res) => {
  res.set({
    "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; " +
      "style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; " +
      "form-action 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
  });
  if (req.method === "GET") {
    res.status(200).type("html").send(PAGE_CREER_NIP);
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({erreur: "Méthode non permise."});
    return;
  }

  const lienInvalide = "Ce lien est invalide ou expiré. Demandez un nouveau lien à votre employeur.";
  const limite = limiteur(`lien_ip_${empreinteIp({rawRequest: req})}`, 10, HEURE);
  try {
    await limite.verifier();
  } catch (_) {
    res.status(429).json({erreur: "Trop de tentatives. Réessayez plus tard."});
    return;
  }

  const {employeeId, jeton, nip} = req.body || {};
  if (typeof nip !== "string" || !FORMAT_NIP.test(nip)) {
    res.status(400).json({erreur: "Le NIP doit contenir de 6 à 8 chiffres."});
    return;
  }
  // Identifiant Firestore simple : aucune barre oblique (pas de chemin forgé).
  if (typeof employeeId !== "string" || !/^[A-Za-z0-9]{1,128}$/.test(employeeId) ||
      typeof jeton !== "string" || jeton.length < 20 || jeton.length > 100) {
    await limite.compter();
    res.status(400).json({erreur: lienInvalide});
    return;
  }

  const invRef = db.collection("invitations_nip").doc(employeeId);
  const empRef = db.collection("employees").doc(employeeId);
  let employe = null;
  try {
    employe = await db.runTransaction(async (t) => {
      const [inv, emp] = await Promise.all([t.get(invRef), t.get(empRef)]);
      if (!inv.exists || !emp.exists || emp.data().actif === false) return null;
      const i = inv.data();
      if (i.expireLe.toMillis() < Date.now() || !egalConstant(i.jetonHash, hacherJeton(jeton))) return null;
      t.update(empRef, nipPrive.champsNipEcrit(FieldValue));
      t.set(nipPrive.refNip(db, employeeId), nipPrive.donneesNipPrive({
        FieldValue, companyId: emp.data().companyId, hash: hacherNip(emp.data().companyId, nip),
      }));
      t.delete(invRef); // usage unique
      return emp.data();
    });
  } catch (e) {
    res.status(500).json({erreur: "Une erreur est survenue. Réessayez."});
    return;
  }
  if (!employe) {
    await limite.compter();
    res.status(400).json({erreur: lienInvalide});
    return;
  }

  await supprimerSessionsDe(employeeId);
  const compagnie = (await db.collection("companies").doc(employe.companyId).get()).data() || {};
  await envoyerCourriel({
    a: employe.courriel,
    sujet: `Votre NIP a été créé — ${NOM_APP}`,
    lignes: [
      `Bonjour ${employe.nom},`,
      "Votre NIP vient d'être créé. Vous pouvez maintenant vous connecter à l'application.",
      "Si vous n'êtes pas à l'origine de ce changement, avertissez votre employeur.",
    ],
  });
  res.status(200).json({ok: true, numero: compagnie.numero || "", courriel: employe.courriel});
});

/** Identifiant d'employé reçu d'un client : jamais de « / » (un chemin forgé). */
function idEmploye(valeur) {
  if (typeof valeur !== "string" || !FORMAT_ID.test(valeur)) {
    throw new HttpsError("invalid-argument", "Employé invalide.");
  }
  return valeur;
}

/** Coupe tous les accès d'un employé : sessions, codes de connexion, liens et codes de NIP. */
async function nettoyerAccesEmploye(employeeId, saufUid = null) {
  await supprimerSessionsDe(employeeId, saufUid);
  await db.collection("reinitialisations_nip").doc(employeeId).delete();
  await db.collection("invitations_nip").doc(employeeId).delete();
  await nipPrive.refNip(db, employeeId).delete();
}

/** Mêmes protections pour retirer, quel que soit le mode : jamais le super-admin ni le Proprio. */
function exigerCibleRetirable(ctx, employeeId, cible) {
  if (cible.estProprietaire === true || employeeId === ctx.idProprioApp) {
    throw new HttpsError("failed-precondition", "Le super-admin de la compagnie ne peut pas être retiré.");
  }
  if (cible.role === "admin" && ctx.employe.estProprietaire !== true) {
    throw new HttpsError("permission-denied", MESSAGE_ADMINS_RESERVES);
  }
}

/** Suppression définitive de la fiche, tout de suite (droit à l'effacement). */
exports.supprimerEmploye = onCall(async (request) => {
  verifierAppCheck(request, "supprimerEmploye");
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
    exigerCibleRetirable(ctx, employeeId, snap.data());
    t.delete(ref);
    t.delete(nipPrive.refNip(db, employeeId));
  });
  await nettoyerAccesEmploye(employeeId);
  return {ok: true};
});

/**
 * Retire l'accès d'un employé : plus aucune connexion, NIP détruit, sessions coupées.
 * Seuls le nom, le courriel, le rôle, la date du retrait, la date de suppression
 * automatique (24 mois) et un motif en liste fermée sont conservés, pour pouvoir le
 * réactiver (saisonnier). `supprimerEmploye` efface la fiche tout de suite.
 */
exports.retirerAccesEmploye = onCall(async (request) => {
  verifierAppCheck(request, "retirerAccesEmploye");
  const ctx = await contexteAdmin(request);
  const employeeId = idEmploye(request.data?.employeeId);
  const motif = archivage.lireMotif(request.data?.motif);
  if (employeeId === ctx.employeeId) {
    throw new HttpsError("failed-precondition", "Vous ne pouvez pas retirer votre propre compte.");
  }

  const ref = db.collection("employees").doc(employeeId);
  const supprimeApresLe = archivage.dateSuppression(Date.now());
  await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists || snap.data().companyId !== ctx.companyId) {
      throw new HttpsError("not-found", "Employé introuvable.");
    }
    exigerCibleRetirable(ctx, employeeId, snap.data());
    if (snap.data().actif === false) {
      throw new HttpsError("failed-precondition", "Cette personne figure déjà dans « Anciens employés ».");
    }
    t.update(ref, {
      actif: false,
      retireLe: FieldValue.serverTimestamp(),
      supprimeApresLe: Timestamp.fromDate(supprimeApresLe),
      motifRetrait: motif,
      // Le NIP est détruit : une réactivation passe toujours par un nouveau NIP.
      ...nipPrive.champsNipEfface(FieldValue),
    });
    t.delete(nipPrive.refNip(db, employeeId));
  });
  await nettoyerAccesEmploye(employeeId);
  return {ok: true, supprimeApresLe: supprimeApresLe.toISOString()};
});

/**
 * Réactive un ancien employé. L'ancien NIP n'existe plus : un lien à usage unique
 * (7 jours) lui permet d'en créer un nouveau. Même retour que enregistrerEmploye.
 */
exports.reactiverEmploye = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "reactiverEmploye");
  const ctx = await contexteAdmin(request);
  const employeeId = idEmploye(request.data?.employeeId);

  const limite = limiteur(`reactiver_${employeeId}`, 3, HEURE);
  await limite.verifier();

  const ref = db.collection("employees").doc(employeeId);
  const employe = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists || snap.data().companyId !== ctx.companyId) {
      throw new HttpsError("not-found", "Employé introuvable.");
    }
    const cible = snap.data();
    if (cible.role === "admin" && ctx.employe.estProprietaire !== true) {
      throw new HttpsError("permission-denied", MESSAGE_ADMINS_RESERVES);
    }
    if (cible.actif !== false) {
      throw new HttpsError("failed-precondition", "Cette personne ne figure pas dans « Anciens employés ».");
    }
    t.update(ref, {
      actif: true,
      retireLe: FieldValue.delete(),
      supprimeApresLe: FieldValue.delete(),
      motifRetrait: FieldValue.delete(),
      // Par précaution : jamais d'ancien NIP.
      ...nipPrive.champsNipEfface(FieldValue),
    });
    t.delete(nipPrive.refNip(db, employeeId));
    return cible;
  });
  await limite.compter();
  const lien = await creerInvitation(employeeId);
  const envoye = await envoyerInvitation(employe, lien, ctx.compagnie, "retour");
  return envoye ?
    {id: employeeId, courrielEnvoye: true} :
    {id: employeeId, courrielEnvoye: false, lienInvitation: lien};
});

/**
 * Déplace chaque nuit les NIP restés dans `employees` vers `employees_prive` (migration :
 * sans effet une fois tout déplacé, à retirer ensuite). Journalise seulement un nombre.
 */
exports.migrerNipsPrives = onSchedule(
    {schedule: "every day 04:00", timeZone: "America/Toronto", timeoutSeconds: 300},
    async () => {
      const nombre = await nipPrive.migrerNipsPrives({db, FieldValue});
      logger.info("NIP déplacés vers l'espace privé", {nombre});
    });

/** Chaque nuit : supprime les anciens employés dont les 24 mois sont écoulés. */
exports.purgerAnciensEmployes = onSchedule(
    {schedule: "every day 03:30", timeZone: "America/Toronto", timeoutSeconds: 300},
    async () => {
      const nombre = await archivage.purgerAnciens({
        db, Timestamp, nettoyer: (employeeId) => nettoyerAccesEmploye(employeeId),
      });
      // Seulement un compte : aucune donnée personnelle dans les journaux.
      logger.info("Anciens employés purgés", {nombre});
    });

// =============================================================================
// Feuille de temps : calculée et enregistrée par le serveur
// =============================================================================

// Le client envoie seulement sa saisie ; les heures payées, le voyagement payé
// et les totaux sont recalculés ici avec les règles de la compagnie. Les règles
// Firestore interdisent toute écriture directe d'une feuille de compagnie.
exports.enregistrerFeuilleTemps = onCall(async (request) => {
  verifierAppCheck(request, "enregistrerFeuilleTemps");
  const ctx = await contexteEmploye(request);
  const lundiDate = request.data?.lundiDate;
  analyserLundi(lundiDate);
  const jours = lireJours(request.data?.jours);

  const maintenant = Date.now();
  // Contremaîtres et employés : semaine échue = verrouillée (les admins
  // peuvent encore corriger).
  if (ctx.employe.role !== "admin" && maintenant >= echeanceSemaine(lundiDate)) {
    throw new HttpsError("permission-denied",
        "Cette semaine est verrouillée. Contactez votre superviseur pour toute correction.");
  }
  exigerSemaineOuverte(lundiDate, maintenant);

  const limite = limiteur(`feuille_${ctx.employeeId}`, 200, HEURE);
  await limite.verifier();
  await limite.compter();

  return calculerEtEnregistrerFeuille({
    ctx, cible: {id: ctx.employeeId, nom: ctx.employe.nom}, lundiDate, jours, maintenant,
    acteur: {id: ctx.employeeId, nom: ctx.employe.nom, role: ctx.employe.role},
  });
});

/** Pas de saisie au-delà de la semaine prochaine. */
function exigerSemaineOuverte(lundiDate, maintenant) {
  const lundiMax = new Date(Date.parse(`${lundiCourant(maintenant)}T00:00:00Z`) + 7 * JOUR)
      .toISOString().slice(0, 10);
  if (lundiDate > lundiMax) {
    throw new HttpsError("failed-precondition", "Cette semaine n'est pas encore ouverte.");
  }
}

/**
 * Corps commun à enregistrerFeuilleTemps et corrigerFeuilleTemps : valide les
 * chantiers (de la compagnie, noms lus ici), calcule heures et voyagement payés
 * avec les règles de paie, puis écrit la feuille de `cible` dans une transaction.
 * Aucune valeur de paie ne vient du client.
 *
 * `reglesDeLaSemaine` : pour une semaine passée déjà enregistrée, les règles
 * copiées dans la feuille (et non celles d'aujourd'hui) servent aux journées
 * modifiées, et elles restent la copie conservée.
 *
 * `acteur` : qui enregistre (l'employé lui-même, ou l'admin qui corrige). La feuille
 * garde la date de sa création et le dernier acteur : le fil « Activité » de l'admin
 * s'en sert (« Heures entrées par … », « Changements apportés aux heures par … »).
 * Chaque journée déjà soumise puis modifiée s'ajoute à l'historique `corrections`
 * (identifiant et rôle de l'auteur, avant/après) : voir calculerFeuille.
 */
async function calculerEtEnregistrerFeuille({
  ctx, cible, lundiDate, jours, maintenant, reglesDeLaSemaine = false, acteur,
}) {
  // Chantiers : doivent appartenir à la compagnie ; le nom vient du serveur.
  const ids = [...new Set(jours.filter((j) => j.chantierId).map((j) => j.chantierId))];
  const nomsChantiers = new Map();
  const archives = new Set();
  if (ids.length > 0) {
    const snaps = await db.getAll(...ids.map((id) => db.collection("chantiers").doc(id)));
    for (const s of snaps) {
      if (!s.exists || s.data().companyId !== ctx.companyId) {
        throw new HttpsError("invalid-argument", "Chantier introuvable.");
      }
      nomsChantiers.set(s.id, s.data().nom);
      if (s.data().archive === true) archives.add(s.id);
    }
  }

  const reglesActuelles = reglesPaieDepuis(ctx.compagnie.reglesPaie);
  const ref = db.collection("feuilles_temps").doc(`${cible.id}_${lundiDate}`);

  // Semaine antérieure à la semaine courante : les journées inchangées gardent
  // leurs valeurs d'origine (un changement de règles ne réécrit pas le passé).
  const semaineFigee = lundiDate < lundiCourant(maintenant);
  const resultat = await db.runTransaction(async (t) => {
    const existante = (await t.get(ref)).data();
    const reglesConservees = reglesDeLaSemaine && semaineFigee && existante?.reglesPaie ?
      existante.reglesPaie : null;
    const regles = reglesConservees ? reglesPaieDepuis(reglesConservees) : reglesActuelles;
    const calcul = calculerFeuille({
      jours, nomsChantiers, archives, regles, existante, semaineFigee,
      maintenantIso: new Date(maintenant).toISOString(),
      acteur: {id: acteur.id, role: acteur.role},
    });
    t.set(ref, {
      companyId: ctx.companyId,
      estIndividuel: false,
      employeeId: cible.id,
      employeeNom: cible.nom,
      lundiDate,
      jours: calcul.jours,
      // Historique des corrections (journées déjà soumises puis modifiées), écrit par le serveur.
      ...(calcul.corrections ? {corrections: calcul.corrections} : {}),
      totalHeures: calcul.totalHeures,
      totalHeuresTravaillees: calcul.totalHeuresTravaillees,
      totalVoyagementPaye: calcul.totalVoyagementPaye,
      // Copie des règles appliquées : un changement futur ne réécrit pas le passé.
      // Semaine passée sans journée recalculée : les règles d'origine restent.
      reglesPaie: reglesConservees ||
        (semaineFigee && calcul.joursRecalcules === 0 && existante?.reglesPaie ?
          existante.reglesPaie : regles),
      dateModification: FieldValue.serverTimestamp(),
      // Première écriture : la date de création ne change plus ensuite.
      creeLe: existante?.creeLe ?? FieldValue.serverTimestamp(),
      modifieParId: acteur.id,
      modifieParNom: acteur.nom || "",
    });
    return calcul;
  });

  return {
    totalHeures: resultat.totalHeures,
    totalHeuresTravaillees: resultat.totalHeuresTravaillees,
    totalVoyagementPaye: resultat.totalVoyagementPaye,
    jours: resultat.jours.map((j) => ({
      heuresTravaillees: j.heuresTravaillees,
      voyagementPayeHeures: j.voyagementPayeHeures,
    })),
  };
}

/**
 * Un admin corrige la saisie d'un employé de sa compagnie (espace web), y
 * compris pour une semaine verrouillée. Même calcul serveur que
 * enregistrerFeuilleTemps. Une semaine passée garde les règles de paie copiées
 * dans sa feuille : une correction ne réécrit pas le passé avec les règles
 * d'aujourd'hui.
 */
exports.corrigerFeuilleTemps = onCall(async (request) => {
  verifierAppCheck(request, "corrigerFeuilleTemps");
  const ctx = await contexteAdmin(request);
  const employeeId = request.data?.employeeId;
  if (typeof employeeId !== "string" || !FORMAT_ID.test(employeeId)) {
    throw new HttpsError("invalid-argument", "Employé invalide.");
  }
  const lundiDate = request.data?.lundiDate;
  analyserLundi(lundiDate);
  const jours = lireJours(request.data?.jours);

  const maintenant = Date.now();
  exigerSemaineOuverte(lundiDate, maintenant);

  const limite = limiteur(`corrfeuille_${ctx.employeeId}`, 200, HEURE);
  await limite.verifier();
  await limite.compter();

  const snap = await db.collection("employees").doc(employeeId).get();
  if (!snap.exists || snap.data().companyId !== ctx.companyId) {
    throw new HttpsError("not-found", "Employé introuvable.");
  }

  return calculerEtEnregistrerFeuille({
    ctx, cible: {id: snap.id, nom: snap.data().nom || ""}, lundiDate, jours, maintenant,
    reglesDeLaSemaine: true,
    acteur: {id: ctx.employeeId, nom: ctx.employe.nom, role: ctx.employe.role},
  });
});

/**
 * Applique les règles de paie actuelles aux feuilles de la SEMAINE COURANTE de la
 * compagnie (heures payées, voyagement payé, totaux), à partir de la saisie
 * conservée. Appelée après chaque changement des règles. Les semaines
 * précédentes ne sont jamais touchées : leurs heures restent celles d'origine.
 */
exports.recalculerSemaineCourante = onCall(async (request) => {
  verifierAppCheck(request, "recalculerSemaineCourante");
  const ctx = await contexteAdmin(request);
  const limite = limiteur(`recalcul_${ctx.employeeId}`, 30, HEURE);
  await limite.verifier();
  await limite.compter();

  const maintenant = Date.now();
  const lundi = lundiCourant(maintenant);
  const regles = reglesPaieDepuis(ctx.compagnie.reglesPaie);
  const snap = await db.collection("feuilles_temps")
      .where("companyId", "==", ctx.companyId).where("lundiDate", "==", lundi).get();

  let modifiees = 0;
  for (const d of snap.docs) {
    if (d.data().estIndividuel === true) continue;
    // Chaque feuille dans sa transaction : une sauvegarde de l'employé en même
    // temps n'est pas écrasée par une lecture périmée.
    const changee = await db.runTransaction(async (t) => {
      const f = (await t.get(d.ref)).data();
      if (!f || f.estIndividuel === true || f.companyId !== ctx.companyId || f.lundiDate !== lundi) return false;
      const maj = recalculerFeuille(f, regles, new Date(maintenant).toISOString());
      if (!maj) return false;
      t.update(d.ref, maj);
      return true;
    });
    if (changee) modifiees++;
  }
  return {semaine: lundi, feuilles: snap.size, modifiees};
});

// =============================================================================
// Dossier de chantier : résumé et export (admin seulement)
// =============================================================================

// Bucket des photos et documents (Montréal).
const BUCKET_STOCKAGE = "chantierplus-mtl";

// Garde-fous de l'export : un dossier énorme n'épuise ni la mémoire ni le temps.
const EXPORT_MAX_FICHIERS = 3000;
const EXPORT_MAX_OCTETS = 1.5 * 1024 * 1024 * 1024;
const EXPORT_CONSERVATION_MS = 6 * HEURE;

const dateDe = (ts) => (ts && typeof ts.toDate === "function" ? ts.toDate().toISOString().slice(0, 10) : "");

/** Lit tout ce qui appartient au chantier ; refuse un chantier d'une autre compagnie. */
async function chargerDossier(ctx, chantierId) {
  const chSnap = await db.collection("chantiers").doc(chantierId).get();
  if (!chSnap.exists || chSnap.data().companyId !== ctx.companyId) {
    throw new HttpsError("not-found", "Chantier introuvable.");
  }
  const duChantier = (col) => db.collection(col)
      .where("companyId", "==", ctx.companyId).where("chantierId", "==", chantierId).get();
  const [feuilles, extras, materiel, photos, travaux, documents] = await Promise.all([
    db.collection("feuilles_temps").where("companyId", "==", ctx.companyId).get(),
    duChantier("chantier_extras"), duChantier("chantier_materiel"), duChantier("chantier_photos"),
    duChantier("chantier_travaux"), duChantier("chantier_documents"),
  ]);
  const trier = (docs, champ) => docs.map((d) => ({id: d.id, ...d.data()}))
      .sort((a, b) => String(a[champ] ?? "").localeCompare(String(b[champ] ?? "")) ||
        (a.dateAjout?.toMillis?.() ?? 0) - (b.dateAjout?.toMillis?.() ?? 0));
  const detail = dossier.detailHeures(feuilles.docs.map((d) => d.data()), chantierId);
  const c = chSnap.data();
  return {
    chantier: {id: chantierId, nom: c.nom ?? "", adresse: c.adresse ?? "", archive: c.archive === true},
    detail,
    heures: dossier.resumerHeures(detail),
    extras: trier(extras.docs, "dateTravaux"),
    materiel: trier(materiel.docs, "dateAjout"),
    travaux: trier(travaux.docs, "dateAjout"),
    documents: documents.docs.map((x) => ({id: x.id, ...x.data()}))
        .sort((a, b) => (a.dateAjout?.toMillis?.() ?? 0) - (b.dateAjout?.toMillis?.() ?? 0)),
    photos: photos.docs.map((d) => ({id: d.id, ...d.data()}))
        .sort((a, b) => (a.dateAjout?.toMillis?.() ?? 0) - (b.dateAjout?.toMillis?.() ?? 0)),
  };
}

exports.resumeChantier = onCall(async (request) => {
  verifierAppCheck(request, "resumeChantier");
  const ctx = await contexteAdmin(request);
  const chantierId = texte(request.data?.chantierId, "chantierId", {max: 128});
  const d = await chargerDossier(ctx, chantierId);
  return {
    chantier: d.chantier,
    heures: d.heures,
    nombres: {
      extras: d.extras.length, materiel: d.materiel.length, photos: d.photos.length,
      travaux: d.travaux.length, documents: d.documents.length,
    },
  };
});

exports.exporterChantier = onCall({memory: "1GiB", timeoutSeconds: 540}, async (request) => {
  verifierAppCheck(request, "exporterChantier");
  const ctx = await contexteAdmin(request);
  const chantierId = texte(request.data?.chantierId, "chantierId", {max: 128});

  const limite = limiteur(`export_${ctx.employeeId}`, 10, HEURE);
  await limite.verifier();
  await limite.compter();

  const d = await chargerDossier(ctx, chantierId);
  const bucket = getStorage().bucket(BUCKET_STOCKAGE);

  // Les exports plus vieux que 6 h sont supprimés (copies de données clients).
  try {
    const [anciens] = await bucket.getFiles({prefix: `exports/${ctx.companyId}/`});
    await Promise.all(anciens.filter((f) =>
      Date.now() - Date.parse(f.metadata?.timeCreated ?? 0) > EXPORT_CONSERVATION_MS)
        .map((f) => f.delete().catch(() => null)));
  } catch (_) { /* le nettoyage ne bloque pas l'export */ }

  const maintenant = new Date();
  const racine = dossier.nomSur(`Chantier - ${d.chantier.nom}`, "Chantier");
  const horodatage = maintenant.toISOString().replace(/[:.]/g, "-");
  const cheminZip = `exports/${ctx.companyId}/${horodatage}_${chantierId}.zip`;
  const jeton = crypto.randomUUID();
  const nomTelechargement = `${racine}.zip`;

  const zip = new yazl.ZipFile();
  const fichierZip = bucket.file(cheminZip);
  const sortie = fichierZip.createWriteStream({
    resumable: false,
    metadata: {
      contentType: "application/zip",
      cacheControl: "no-store",
      contentDisposition: `attachment; filename="${dossier.nomSur(racine, "dossier")}.zip"`,
      metadata: {firebaseStorageDownloadTokens: jeton},
    },
  });
  const termine = new Promise((resolve, reject) => {
    sortie.on("finish", resolve);
    sortie.on("error", reject);
    zip.outputStream.on("error", reject);
  });
  zip.outputStream.pipe(sortie);

  const ignores = [];
  let octets = 0;
  let nbFichiers = 0;

  /** Copie un fichier Storage dans le ZIP ; retourne son nom dans le ZIP, ou null. */
  const ajouter = async (cheminStorage, dansZip) => {
    if (!dossier.cheminDuChantier(cheminStorage, ctx.companyId, chantierId)) {
      ignores.push(`${dansZip} (chemin refusé)`);
      return null;
    }
    const fichier = bucket.file(cheminStorage);
    let taille;
    try {
      const [meta] = await fichier.getMetadata();
      taille = Number(meta.size);
    } catch (_) {
      ignores.push(`${dansZip} (introuvable)`);
      return null;
    }
    if (nbFichiers >= EXPORT_MAX_FICHIERS || octets + taille > EXPORT_MAX_OCTETS) {
      ignores.push(`${dansZip} (limite de taille de l'export)`);
      return null;
    }
    nbFichiers += 1;
    octets += taille;
    await new Promise((resolve, reject) => {
      const flux = fichier.createReadStream();
      flux.on("end", resolve);
      flux.on("error", reject);
      // Images déjà compressées : stockées telles quelles.
      zip.addReadStream(flux, `${racine}/${dansZip}`, {compress: false, mtime: maintenant});
    });
    return dansZip;
  };
  const numero = (i) => String(i + 1).padStart(3, "0");

  try {
    // Documents du chantier (plans, devis…) : en premier, ce sont les plus utiles.
    const nomsPris = new Set();
    const documents = [];
    for (const doc of d.documents) {
      const nomZip = `documents/${dossier.nomFichierDocument(doc.nom, nomsPris)}`;
      documents.push({...doc, fichier: await ajouter(doc.cheminStorage, nomZip)});
    }
    // Photos du chantier.
    let nbPhotos = 0;
    for (let i = 0; i < d.photos.length; i++) {
      const chemin = d.photos[i].cheminStorage;
      const nom = `photos/photo_${numero(i)}.${dossier.extension(chemin)}`;
      if (await ajouter(chemin, nom)) nbPhotos += 1;
    }
    // Photos des extras, du matériel et des travaux à compléter.
    // Chaque demande peut avoir jusqu'à 6 photos : la première garde le nom d'avant
    // (extra_001.jpg), les suivantes prennent _2, _3… (extra_001_2.jpg) : seules les
    // photos réellement incluses sont numérotées, sans trou.
    const suffixe = (j) => (j === 0 ? "" : `_${j + 1}`);
    const extras = [];
    for (let i = 0; i < d.extras.length; i++) {
      const e = d.extras[i];
      const fichiers = [];
      const photos = dossier.photosExtraDe(e);
      for (let j = 0; j < photos.length; j++) {
        const nom = `extras/extra_${numero(i)}${suffixe(fichiers.length)}.${dossier.extension(photos[j].chemin)}`;
        const inclus = await ajouter(photos[j].chemin, nom);
        if (inclus) fichiers.push(inclus);
      }
      extras.push({...e, fichiersPhotos: fichiers, fichierPhoto: fichiers.length > 0 ? fichiers.join("; ") : null});
    }
    const avecPhotoUrl = async (liste, dossierZip, prefixe) => {
      const sortie = [];
      for (let i = 0; i < liste.length; i++) {
        const fichiers = [];
        const urls = dossier.photosDe(liste[i]);
        for (let j = 0; j < urls.length; j++) {
          const chemin = dossier.cheminDepuisUrl(urls[j]);
          if (!chemin) continue;
          const nom = `${dossierZip}/${prefixe}_${numero(i)}${suffixe(fichiers.length)}.${dossier.extension(chemin)}`;
          const inclus = await ajouter(chemin, nom);
          if (inclus) fichiers.push(inclus);
        }
        sortie.push({...liste[i], fichiersPhotos: fichiers, fichierPhoto: fichiers.length > 0 ? fichiers.join("; ") : null});
      }
      return sortie;
    };
    const materiel = await avecPhotoUrl(d.materiel, "materiel", "materiel");
    const travaux = await avecPhotoUrl(d.travaux, "travaux", "travail");

    // Résumé imprimable et classeur Excel (s'ouvre pareil en français et en anglais).
    const html = dossier.htmlResume({
      compagnie: ctx.compagnie.nomEntreprise ?? "",
      chantier: d.chantier,
      dateExport: maintenant.toISOString(),
      heures: d.heures,
      extras: extras.map((e) => ({
        dateTravaux: e.dateTravaux ?? "", description: e.description ?? "", mainOeuvre: e.mainOeuvre ?? "",
        ajouteParNom: e.ajouteParNom ?? "", fichierPhoto: e.fichierPhoto, fichiersPhotos: e.fichiersPhotos,
      })),
      materiel: materiel.map((m) => ({
        texte: m.texte ?? "", quantite: m.quantite ?? "", complete: m.complete === true,
        dateAjout: dateDe(m.dateAjout), fichierPhoto: m.fichierPhoto, fichiersPhotos: m.fichiersPhotos,
      })),
      travaux: travaux.map((t) => ({
        texte: t.texte ?? "", complete: t.complete === true, dateAjout: dateDe(t.dateAjout),
        dateComplete: dateDe(t.dateComplete), fichierPhoto: t.fichierPhoto, fichiersPhotos: t.fichiersPhotos,
      })),
      documents: documents.map((x) => ({
        nom: x.nom ?? "", taille: x.taille, dateAjout: dateDe(x.dateAjout), fichier: x.fichier,
      })),
      photos: nbPhotos,
      ignores,
    });
    const classeur = await xlsx.classeur([
      {
        nom: "Heures",
        colonnes: [
          {titre: "Date", cle: "date", type: "date", largeur: 14}, {titre: "Employé", cle: "employeNom", largeur: 28},
          {titre: "Heures travaillées", cle: "heures", type: "nombre", largeur: 20},
          {titre: "Voyagement payé (h)", cle: "voyagementPaye", type: "nombre", largeur: 22},
        ],
        lignes: d.detail,
        total: {libelle: "Total", valeurs: {heures: d.heures.totalHeures, voyagementPaye: d.heures.totalVoyagementPaye}},
      },
      {
        nom: "Par employé",
        colonnes: [
          {titre: "Employé", cle: "nom", largeur: 28}, {titre: "Jours", cle: "jours", type: "nombre", largeur: 10},
          {titre: "Heures travaillées", cle: "heures", type: "nombre", largeur: 20},
          {titre: "Voyagement payé (h)", cle: "voyagementPaye", type: "nombre", largeur: 22},
        ],
        lignes: d.heures.parEmploye,
        total: {
          libelle: "Total",
          valeurs: {jours: d.heures.journeesHomme, heures: d.heures.totalHeures, voyagementPaye: d.heures.totalVoyagementPaye},
        },
      },
      {
        nom: "Extras",
        colonnes: [
          {titre: "Date des travaux", cle: "dateTravaux", type: "date", largeur: 16},
          {titre: "Description", cle: "description", largeur: 50}, {titre: "Main-d'œuvre et temps", cle: "mainOeuvre", largeur: 36},
          {titre: "Saisi par", cle: "ajouteParNom", largeur: 24}, {titre: "Photo", cle: "fichierPhoto", largeur: 28},
        ],
        lignes: extras,
      },
      {
        nom: "Matériel",
        colonnes: [
          {titre: "Matériel", cle: "texte", largeur: 40}, {titre: "Quantité", cle: "quantite", largeur: 20},
          {titre: "État", cle: "etat", largeur: 12}, {titre: "Ajouté le", cle: "ajoute", type: "date", largeur: 14},
          {titre: "Obtenu le", cle: "obtenu", type: "date", largeur: 14}, {titre: "Photo", cle: "fichierPhoto", largeur: 28},
        ],
        lignes: materiel.map((m) => ({
          ...m, etat: m.complete === true ? "Obtenu" : "À obtenir", ajoute: dateDe(m.dateAjout), obtenu: dateDe(m.dateComplete),
        })),
      },
      {
        nom: "Travaux à compléter",
        colonnes: [
          {titre: "Travail", cle: "texte", largeur: 50}, {titre: "État", cle: "etat", largeur: 14},
          {titre: "Ajouté le", cle: "ajoute", type: "date", largeur: 14}, {titre: "Complété le", cle: "complete", type: "date", largeur: 14},
          {titre: "Photo", cle: "fichierPhoto", largeur: 28},
        ],
        lignes: travaux.map((t) => ({
          ...t, etat: t.complete === true ? "Complété" : "À compléter", ajoute: dateDe(t.dateAjout), complete: dateDe(t.dateComplete),
        })),
      },
      {
        nom: "Documents",
        colonnes: [
          {titre: "Document", cle: "nom", largeur: 44}, {titre: "Taille", cle: "tailleTexte", largeur: 12},
          {titre: "Type", cle: "typeMime", largeur: 28}, {titre: "Ajouté le", cle: "ajoute", type: "date", largeur: 14},
          {titre: "Dans l'export", cle: "inclus", largeur: 14}, {titre: "Fichier dans le ZIP", cle: "fichier", largeur: 40},
        ],
        lignes: documents.map((x) => ({
          ...x, tailleTexte: dossier.tailleLisible(x.taille), ajoute: dateDe(x.dateAjout), inclus: x.fichier ? "Inclus" : "Non inclus",
        })),
      },
    ]);
    const texteBrut = (nom, contenu) => zip.addBuffer(Buffer.from(contenu, "utf8"), `${racine}/${nom}`, {mtime: maintenant});
    texteBrut("Resume.html", html);
    zip.addBuffer(classeur, `${racine}/Dossier.xlsx`, {mtime: maintenant});
    if (ignores.length > 0) texteBrut("fichiers_non_inclus.txt", `${ignores.join("\r\n")}\r\n`);
    zip.end();
    await termine;
  } catch (e) {
    await fichierZip.delete().catch(() => null);
    logger.error("Export du dossier échoué", {chantierId, erreur: String(e?.message ?? e)});
    throw new HttpsError("internal", "L'export a échoué. Réessayez.");
  }

  const [meta] = await fichierZip.getMetadata();
  return {
    url: `https://firebasestorage.googleapis.com/v0/b/${BUCKET_STOCKAGE}/o/${encodeURIComponent(cheminZip)}?alt=media&token=${jeton}`,
    nom: nomTelechargement,
    taille: Number(meta.size),
    fichiers: nbFichiers,
    ignores,
  };
});

// =============================================================================
// NIP : changement par l'employé et récupération par courriel
// =============================================================================

exports.changerNip = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "changerNip");
  const ctx = await contexteEmploye(request);
  const actuel = texte(request.data?.nipActuel, "NIP actuel", {max: 32});
  const nouveau = nouveauNip(request.data?.nouveauNip, "nouveau NIP");

  const limite = limiteur(`nip_${ctx.employeeId}`, 5, JOUR);
  await limite.verifier();
  await limite.compter();

  const e = ctx.employe;
  const hashActuel = await nipPrive.lireHash(db, ctx.employeeId, e);
  if (!egalConstant(hashActuel, hacherNip(ctx.companyId, actuel))) {
    throw new HttpsError("permission-denied", "NIP actuel invalide.");
  }

  const lot = db.batch();
  lot.set(nipPrive.refNip(db, ctx.employeeId), nipPrive.donneesNipPrive({
    FieldValue, companyId: ctx.companyId, hash: hacherNip(ctx.companyId, nouveau),
  }));
  lot.update(db.collection("employees").doc(ctx.employeeId), nipPrive.champsNipEcrit(FieldValue));
  await lot.commit();
  // Déconnecte les autres appareils.
  await supprimerSessionsDe(ctx.employeeId, ctx.uid);

  await envoyerCourriel({
    a: e.courriel,
    sujet: `Votre NIP a été modifié — ${NOM_APP}`,
    lignes: [
      `Bonjour ${e.nom},`,
      "Le NIP de votre compte vient d'être modifié.",
      "Si vous n'êtes pas à l'origine de ce changement, utilisez « NIP oublié ? » " +
        "dans l'application et avertissez votre employeur.",
    ],
  });
  return {ok: true};
});

function hacherCode(employeeId, code) {
  return hacherNip(`reinit:${employeeId}`, code);
}

function exigerCourrielDisponible() {
  if (!courrielConfigure()) {
    throw new HttpsError("unavailable", "Service de courriel temporairement indisponible. Contactez votre employeur.");
  }
}

/** Envoie les numéros de compagnie liés à un courriel. Réponse identique dans tous les cas. */
exports.recupererNumeroCompagnie = onCall({secrets: [RESEND_API_KEY]}, async (request) => {
  verifierAppCheck(request, "recupererNumeroCompagnie");
  exigerAnonyme(request);
  const adresse = courriel(request.data?.email);
  exigerCourrielDisponible();

  const limiteIp = limiteur(`rec_ip_${empreinteIp(request)}`, 5, HEURE);
  const limiteAdresse = limiteur(`rec_${empreinte(adresse)}`, 3, HEURE);
  await limiteIp.verifier();
  await limiteAdresse.verifier();
  await limiteIp.compter();
  await limiteAdresse.compter();

  const employes = await db.collection("employees").where("courriel", "==", adresse).limit(20).get();
  const ids = [...new Set(employes.docs.filter((e) => e.data().actif !== false).map((e) => e.data().companyId))];
  const compagnies = (await Promise.all(ids.map((id) => db.collection("companies").doc(id).get())))
      .filter((c) => c.exists && c.data().statut !== "refusee");

  if (compagnies.length > 0) {
    await envoyerCourriel({
      a: adresse,
      sujet: `Votre numéro de compagnie — ${NOM_APP}`,
      lignes: [
        "Voici le ou les numéros de compagnie associés à votre courriel :",
        compagnies.map((c) => `${c.data().nomEntreprise} : ${c.data().numero}`).join("\n"),
        "Si vous n'avez pas fait cette demande, ignorez ce message.",
      ],
    });
  }
  return {ok: true};
});

exports.demanderReinitialisationNip = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "demanderReinitialisationNip");
  exigerAnonyme(request);
  const numero = texte(request.data?.numeroCompagnie, "numéro de compagnie", {max: 10});
  const adresse = courriel(request.data?.email);
  exigerCourrielDisponible();

  const limiteIp = limiteur(`reinit_ip_${empreinteIp(request)}`, 5, HEURE);
  const limiteAdresse = limiteur(`reinit_${empreinte(`${numero}:${adresse}`)}`, 3, HEURE);
  await limiteIp.verifier();
  await limiteAdresse.verifier();
  await limiteIp.compter();
  await limiteAdresse.compter();

  if (!FORMAT_NUMERO.test(numero)) return {ok: true};
  const compSnap = await compagniesApprouvees(numero);
  if (compSnap.empty) return {ok: true};
  const compagnie = compSnap.docs[0];
  const empSnap = await db.collection("employees")
      .where("companyId", "==", compagnie.id).where("courriel", "==", adresse).limit(2).get();
  if (empSnap.size !== 1) return {ok: true};
  const employe = empSnap.docs[0];
  // Un ancien employé ne peut pas se redonner accès par « NIP oublié ».
  if (employe.data().actif === false) return {ok: true};

  const code = nombreAleatoire(6);
  await db.collection("reinitialisations_nip").doc(employe.id).set({
    codeHash: hacherCode(employe.id, code),
    essais: 0,
    expireLe: Timestamp.fromMillis(Date.now() + 15 * MINUTE),
  });
  await envoyerCourriel({
    a: adresse,
    sujet: `Code de réinitialisation du NIP — ${NOM_APP}`,
    lignes: [
      `Bonjour ${employe.data().nom},`,
      `Votre code de réinitialisation : ${code}`,
      "Ce code expire dans 15 minutes. Si vous n'avez pas fait cette demande, ignorez ce message.",
    ],
  });
  return {ok: true};
});

exports.validerReinitialisationNip = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "validerReinitialisationNip");
  exigerAnonyme(request);
  const numero = texte(request.data?.numeroCompagnie, "numéro de compagnie", {max: 10});
  const adresse = courriel(request.data?.email);
  const code = texte(request.data?.code, "code", {max: 10});
  const nouveau = nouveauNip(request.data?.nouveauPin, "nouveau NIP");
  const invalide = () => new HttpsError("permission-denied", "Code invalide ou expiré.");

  const limiteIp = limiteur(`valid_ip_${empreinteIp(request)}`, 10, HEURE);
  await limiteIp.verifier();
  await limiteIp.compter();

  if (!FORMAT_NUMERO.test(numero)) throw invalide();
  const compSnap = await compagniesApprouvees(numero);
  if (compSnap.empty) throw invalide();
  const compagnie = compSnap.docs[0];
  const empSnap = await db.collection("employees")
      .where("companyId", "==", compagnie.id).where("courriel", "==", adresse).limit(2).get();
  if (empSnap.size !== 1 || empSnap.docs[0].data().actif === false) throw invalide();
  const employe = empSnap.docs[0];
  const resetRef = db.collection("reinitialisations_nip").doc(employe.id);

  const valide = await db.runTransaction(async (t) => {
    const [snap, fiche] = await Promise.all([t.get(resetRef), t.get(employe.ref)]);
    // Retiré entre la demande et la validation : le NIP ne ressuscite pas.
    if (!snap.exists || !fiche.exists || fiche.data().actif === false) return false;
    const r = snap.data();
    if (r.expireLe.toMillis() < Date.now() || r.essais >= 5) {
      t.delete(resetRef);
      return false;
    }
    if (!egalConstant(r.codeHash, hacherCode(employe.id, code))) {
      t.update(resetRef, {essais: FieldValue.increment(1)});
      return false;
    }
    t.delete(resetRef);
    t.update(employe.ref, nipPrive.champsNipEcrit(FieldValue));
    t.set(nipPrive.refNip(db, employe.id), nipPrive.donneesNipPrive({
      FieldValue, companyId: compagnie.id, hash: hacherNip(compagnie.id, nouveau),
    }));
    return true;
  });
  if (!valide) throw invalide();

  await supprimerSessionsDe(employe.id);
  await envoyerCourriel({
    a: adresse,
    sujet: `Votre NIP a été réinitialisé — ${NOM_APP}`,
    lignes: [
      `Bonjour ${employe.data().nom},`,
      "Votre NIP vient d'être réinitialisé. Vos autres appareils ont été déconnectés.",
      "Si vous n'êtes pas à l'origine de ce changement, avertissez votre employeur.",
    ],
  });
  return {ok: true};
});

// =============================================================================
// Assistant de charpente : une description en français devient un projet validé
// =============================================================================

// Le modèle ne fait que convertir du texte en paramètres ; l'application calcule
// elle-même le bois. Accès : admin et contremaître. Clé d'API dans Secret Manager
// (ANTHROPIC_API_KEY), jamais côté client.
exports.assistantCharpente = onCall(
    {secrets: [assistantCharpente.ANTHROPIC_API_KEY], timeoutSeconds: 90, memory: "256MiB"},
    async (request) => {
      verifierAppCheck(request, "assistantCharpente");
      const ctx = await contexteEmploye(request);
      if (!["admin", "plus"].includes(ctx.employe.role)) {
        throw new HttpsError("permission-denied", "Accès réservé aux admins et aux contremaîtres.");
      }
      const description = texte(request.data?.texte, "texte", {min: 5, max: assistantCharpente.MAX_TEXTE});

      // Projet actuel facultatif (pour modifier plutôt que recommencer) : relu et
      // filtré, jamais transmis tel quel.
      let projetActuel = null;
      const brut = request.data?.projetActuel;
      if (brut !== undefined && brut !== null) {
        if (typeof brut !== "string" || brut.length > assistantCharpente.MAX_PROJET_ACTUEL) {
          throw new HttpsError("invalid-argument", "Projet actuel invalide.");
        }
        try {
          projetActuel = JSON.stringify(assistantCharpente.normaliserProjet(JSON.parse(brut)).projet);
        } catch (e) {
          projetActuel = null;
        }
      }

      // Limites : par employé (20 par heure) et par compagnie (200 par jour).
      const parHeure = limiteur(`assistant_h_${ctx.employeeId}`, 20, HEURE);
      const parJour = limiteur(`assistant_j_${ctx.companyId}`, 200, JOUR);
      await parHeure.verifier();
      await parJour.verifier();
      await parHeure.compter();
      await parJour.compter();

      try {
        const resultat = await assistantCharpente.interroger({
          texte: description,
          projetActuel,
          cle: assistantCharpente.ANTHROPIC_API_KEY.value(),
          url: assistantCharpente.URL_API_ANTHROPIC.value(),
          modele: assistantCharpente.MODELE_ASSISTANT.value(),
        });
        logger.info("Assistant charpente", {companyId: ctx.companyId, longueur: description.length});
        return resultat;
      } catch (e) {
        if (e.detailInterne) logger.error("Assistant charpente : échec de l'API", {detail: e.detailInterne});
        throw e;
      }
    },
);

// =============================================================================
// Lecture de plans : un PDF ou des photos de plans deviennent un projet à confirmer
// =============================================================================

// Comme l'assistant, le modèle lit et convertit : l'application calcule le bois. Il signale aussi
// les valeurs qu'il juge incertaines ; le serveur y ajoute celles dont la cote imprimée ne
// correspond pas à la valeur lue ou qui manquent. L'utilisateur confirme à la main avant
// d'appliquer. Les plans ne sont pas conservés : ils servent à cet appel seulement.
// Accès : admin et contremaître. Même clé d'API (ANTHROPIC_API_KEY) que l'assistant.
exports.lirePlanCharpente = onCall(
    // Mémoire : les pages des plans sont rendues en grand (environ 4200 px) avant l'envoi.
    {secrets: [assistantCharpente.ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: "2GiB"},
    async (request) => {
      verifierAppCheck(request, "lirePlanCharpente");
      const ctx = await contexteEmploye(request);
      if (!["admin", "plus"].includes(ctx.employe.role)) {
        throw new HttpsError("permission-denied", "Accès réservé aux admins et aux contremaîtres.");
      }
      const fichiers = lecturePlans.validerFichiers(request.data?.fichiers);
      const precisions = texte(request.data?.precisions, "precisions", {min: 0, max: lecturePlans.MAX_PRECISIONS});
      // Réglages habituels de l'entrepreneur (là où le plan ne dit rien) : filtrés comme un projet.
      const reglages = lecturePlans.validerReglages(request.data?.reglages);

      // Limites (une lecture coûte plus cher qu'une description) : par employé (6 par heure) et par
      // compagnie (30 par jour).
      const parHeure = limiteur(`plan_h_${ctx.employeeId}`, 6, HEURE);
      const parJour = limiteur(`plan_j_${ctx.companyId}`, 30, JOUR);
      // Refus rapide, puis réservation atomique : des appels simultanés ne dépassent pas la limite.
      await parHeure.verifier();
      await parJour.verifier();
      await parHeure.reserver();
      await parJour.reserver();

      try {
        const resultat = await lecturePlans.lirePlan({
          fichiers,
          precisions,
          cle: assistantCharpente.ANTHROPIC_API_KEY.value(),
          url: assistantCharpente.URL_API_ANTHROPIC.value(),
          modele: lecturePlans.MODELE_PLANS.value(),
          journal: (message) => logger.warn("Lecture de plan : rendu", {message}),
          reglages,
        });
        logger.info("Lecture de plan", {
          companyId: ctx.companyId,
          fichiers: fichiers.length,
          octets: fichiers.reduce((a, f) => a + f.octets, 0),
          aConfirmer: resultat.valeurs.filter((v) => v.niveau === "incertain").length,
        });
        return resultat;
      } catch (e) {
        if (e.detailInterne) logger.error("Lecture de plan : échec de l'API", {detail: e.detailInterne});
        throw e;
      }
    },
);
