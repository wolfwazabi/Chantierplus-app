const {initializeApp} = require("firebase-admin/app");
initializeApp();

const {setGlobalOptions} = require("firebase-functions/v2");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {
  db, FieldValue, Timestamp,
  PIN_PEPPER, REGION, ROLES, FORMAT_NIP, FORMAT_NUMERO,
  texte, courriel, nouveauNip, hacherNip, egalConstant, nombreAleatoire,
  empreinte, empreinteIp, verifierAppCheck, exigerAnonyme,
  proprioAppId, contexteEmploye, contexteAdmin, contexteProprioApp,
  limiteur, supprimerSessionsDe, MINUTE, HEURE, JOUR,
} = require("./src/commun");
const {RESEND_API_KEY, envoyerCourriel, courrielConfigure, NOM_APP} = require("./src/courriel");
const {hacherJeton, creerInvitation} = require("./src/invitation");
const {
  reglesPaieDepuis, analyserLundi, echeanceSemaine, lundiCourant, lireJours, calculerFeuille,
} = require("./src/feuille_temps");
const PAGE_CREER_NIP = require("./src/page_creer_nip");

setGlobalOptions({region: REGION, maxInstances: 10});

const SECRETS_NIP = [PIN_PEPPER];
const SECRETS_NIP_COURRIEL = [PIN_PEPPER, RESEND_API_KEY];

const MESSAGE_CONNEXION_INVALIDE = "Numéro de compagnie, courriel ou NIP invalide.";
const MESSAGE_ADMINS_RESERVES = "Seul le super-admin de la compagnie peut nommer, modifier ou retirer un admin.";

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

exports.connexionEmploye = onCall({secrets: SECRETS_NIP}, async (request) => {
  verifierAppCheck(request, "connexionEmploye");
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
  const employe = snap.size === 1 &&
    egalConstant(snap.docs[0].data().pinHash, hacherNip(compagnie.id, pin)) ? snap.docs[0] : null;
  if (!employe) await echouer(limiteCompagnie);

  const data = employe.data();
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
      pinHash: hacherNip(companyRef.id, pinAdmin),
    });
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

// =============================================================================
// Gestion des employés (admins de la compagnie)
// =============================================================================

async function envoyerInvitation(employe, lien, compagnie, nouveau) {
  return envoyerCourriel({
    a: employe.courriel,
    sujet: nouveau ?
      `Bienvenue chez ${compagnie.nomEntreprise} — ${NOM_APP}` :
      `Créez votre nouveau NIP — ${NOM_APP}`,
    lignes: [
      `Bonjour ${employe.nom},`,
      nouveau ?
        `Votre inscription est confirmée : ${compagnie.nomEntreprise} vous a créé un accès à ${NOM_APP}.` :
        `${compagnie.nomEntreprise} a réinitialisé votre NIP. L'ancien ne fonctionne plus.`,
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
  const invitationDemandee = !employeeId || d.reinitialiserNip === true;
  const appelantSuperAdmin = ctx.employe.estProprietaire === true;

  const employes = db.collection("employees");
  const ref = employeeId ? employes.doc(employeeId) : employes.doc();
  const soiMeme = ref.id === ctx.employeeId;

  const enregistre = await db.runTransaction(async (t) => {
    let existant = null;
    if (employeeId) {
      const snap = await t.get(ref);
      if (!snap.exists || snap.data().companyId !== ctx.companyId) {
        throw new HttpsError("not-found", "Employé introuvable.");
      }
      existant = snap.data();
    }
    const memeCourriel = await t.get(employes
        .where("companyId", "==", ctx.companyId).where("courriel", "==", adresse).limit(2));
    if (memeCourriel.docs.some((doc) => doc.id !== ref.id)) {
      throw new HttpsError("already-exists", "Ce courriel est déjà utilisé par un autre employé de votre compagnie.");
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

    const maj = {nom, courriel: adresse, role};
    if (existant) {
      // Réinitialisation : l'ancien NIP cesse de fonctionner immédiatement.
      t.update(ref, invitationDemandee ? {...maj, pinHash: FieldValue.delete()} : maj);
    } else {
      // Pas de NIP tant que l'employé ne l'a pas créé avec son lien.
      t.set(ref, {...maj, companyId: ctx.companyId, estProprietaire: false});
    }
    return {...existant, ...maj};
  });

  if (!invitationDemandee) return {id: ref.id};
  if (employeeId) await supprimerSessionsDe(ref.id, soiMeme ? ctx.uid : null);
  const lien = await creerInvitation(ref.id);
  const envoye = await envoyerInvitation(enregistre, lien, ctx.compagnie, !employeeId);
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
      if (!inv.exists || !emp.exists) return null;
      const i = inv.data();
      if (i.expireLe.toMillis() < Date.now() || !egalConstant(i.jetonHash, hacherJeton(jeton))) return null;
      t.update(empRef, {
        pinHash: hacherNip(emp.data().companyId, nip),
        pinModifieLe: FieldValue.serverTimestamp(),
      });
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
    const cible = snap.data();
    if (cible.estProprietaire === true || employeeId === ctx.idProprioApp) {
      throw new HttpsError("failed-precondition", "Le super-admin de la compagnie ne peut pas être retiré.");
    }
    if (cible.role === "admin" && ctx.employe.estProprietaire !== true) {
      throw new HttpsError("permission-denied", MESSAGE_ADMINS_RESERVES);
    }
    t.delete(ref);
  });
  await supprimerSessionsDe(employeeId);
  await db.collection("reinitialisations_nip").doc(employeeId).delete();
  await db.collection("invitations_nip").doc(employeeId).delete();
  return {ok: true};
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
  // Pas de saisie au-delà de la semaine prochaine.
  const lundiMax = new Date(Date.parse(`${lundiCourant(maintenant)}T00:00:00Z`) + 7 * JOUR)
      .toISOString().slice(0, 10);
  if (lundiDate > lundiMax) {
    throw new HttpsError("failed-precondition", "Cette semaine n'est pas encore ouverte.");
  }

  const limite = limiteur(`feuille_${ctx.employeeId}`, 200, HEURE);
  await limite.verifier();
  await limite.compter();

  // Chantiers : doivent appartenir à la compagnie ; le nom vient du serveur.
  const ids = [...new Set(jours.filter((j) => j.chantierId).map((j) => j.chantierId))];
  const nomsChantiers = new Map();
  if (ids.length > 0) {
    const snaps = await db.getAll(...ids.map((id) => db.collection("chantiers").doc(id)));
    for (const s of snaps) {
      if (!s.exists || s.data().companyId !== ctx.companyId) {
        throw new HttpsError("invalid-argument", "Chantier introuvable.");
      }
      nomsChantiers.set(s.id, s.data().nom);
    }
  }

  const regles = reglesPaieDepuis(ctx.compagnie.reglesPaie);
  const ref = db.collection("feuilles_temps").doc(`${ctx.employeeId}_${lundiDate}`);

  const resultat = await db.runTransaction(async (t) => {
    const existante = (await t.get(ref)).data();
    const calcul = calculerFeuille({
      jours, nomsChantiers, regles, existante,
      maintenantIso: new Date(maintenant).toISOString(),
    });
    t.set(ref, {
      companyId: ctx.companyId,
      estIndividuel: false,
      employeeId: ctx.employeeId,
      employeeNom: ctx.employe.nom,
      lundiDate,
      jours: calcul.jours,
      totalHeures: calcul.totalHeures,
      totalHeuresTravaillees: calcul.totalHeuresTravaillees,
      totalVoyagementPaye: calcul.totalVoyagementPaye,
      // Copie des règles appliquées : un changement futur ne réécrit pas le passé.
      reglesPaie: regles,
      dateModification: FieldValue.serverTimestamp(),
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
  if (!egalConstant(e.pinHash, hacherNip(ctx.companyId, actuel))) {
    throw new HttpsError("permission-denied", "NIP actuel invalide.");
  }

  await db.collection("employees").doc(ctx.employeeId).update({
    pinHash: hacherNip(ctx.companyId, nouveau),
    pinModifieLe: FieldValue.serverTimestamp(),
  });
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
  const ids = [...new Set(employes.docs.map((e) => e.data().companyId))];
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
  if (empSnap.size !== 1) throw invalide();
  const employe = empSnap.docs[0];
  const resetRef = db.collection("reinitialisations_nip").doc(employe.id);

  const valide = await db.runTransaction(async (t) => {
    const snap = await t.get(resetRef);
    if (!snap.exists) return false;
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
    t.update(employe.ref, {
      pinHash: hacherNip(compagnie.id, nouveau),
      pinModifieLe: FieldValue.serverTimestamp(),
    });
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
