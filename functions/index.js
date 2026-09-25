const {initializeApp} = require("firebase-admin/app");
initializeApp();

const {setGlobalOptions} = require("firebase-functions/v2");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {
  db, FieldValue, Timestamp, logger,
  PIN_PEPPER, REGION, REGIONS_AVEC_ANCIENNES_VERSIONS,
  ROLES, FORMAT_NIP_EXISTANT, FORMAT_NUMERO,
  texte, courriel, nouveauNip, hacherNip, egalConstant, nombreAleatoire, genererNipUnique,
  empreinte, empreinteIp, verifierAppCheck, exigerAnonyme,
  proprioAppId, contexteEmploye, contexteAdmin, contexteProprioApp,
  limiteur, supprimerSessionsDe, MINUTE, HEURE, JOUR,
} = require("./src/commun");
const {RESEND_API_KEY, envoyerCourriel, courrielConfigure, NOM_APP} = require("./src/courriel");

setGlobalOptions({region: REGION, maxInstances: 10});

// Fonctions appelées par les anciennes versions de l'app : aussi en us-central1.
const COMPAT = {region: REGIONS_AVEC_ANCIENNES_VERSIONS};
const SECRETS_NIP = [PIN_PEPPER];
const SECRETS_NIP_COURRIEL = [PIN_PEPPER, RESEND_API_KEY];

const MESSAGE_CONNEXION_INVALIDE = "Numéro de compagnie, courriel ou NIP invalide.";

function compagniesApprouvees(numero) {
  return db.collection("companies")
      .where("numero", "==", numero)
      .where("statut", "==", "approuvee")
      .limit(1)
      .get();
}

// =============================================================================
// Connexion employé
// =============================================================================

/**
 * Deux modes :
 *  - numéro + courriel + NIP (nouvelle app) : identifie l'employé sans
 *    ambiguïté ; seul mode donnant accès aux pouvoirs du Proprio ;
 *  - numéro + NIP (anciennes versions) : accepté seulement si le NIP désigne
 *    un seul employé, et désactivable via config/securite
 *    { connexionNipSeulAutorisee: false } quand les anciennes versions auront
 *    disparu.
 */
exports.connexionEmploye = onCall({...COMPAT, secrets: SECRETS_NIP}, async (request) => {
  verifierAppCheck(request, "connexionEmploye");
  const auth = exigerAnonyme(request);
  const d = request.data || {};
  const numero = texte(d.numeroCompagnie, "numéro de compagnie", {max: 10});
  const pin = texte(d.pin, "NIP", {max: 32});
  const avecCourriel = typeof d.courriel === "string" && d.courriel.trim() !== "";
  const adresse = avecCourriel ? courriel(d.courriel) : null;

  const limiteIp = limiteur(`ip_${empreinteIp(request)}`, 10, 15 * MINUTE);
  await limiteIp.verifier();

  if (!adresse) {
    const config = await db.collection("config").doc("securite").get();
    if (config.exists && config.data().connexionNipSeulAutorisee === false) {
      throw new HttpsError("failed-precondition",
          "Entrez votre courriel pour vous connecter. Mettez l'application à jour au besoin.");
    }
  }

  // Message unique pour tous les échecs : ne pas révéler ce qui existe.
  const echouer = async (limiteCompagnie) => {
    await limiteIp.compter();
    if (limiteCompagnie) await limiteCompagnie.compter();
    throw new HttpsError("not-found", MESSAGE_CONNEXION_INVALIDE);
  };

  if (!FORMAT_NUMERO.test(numero) || !FORMAT_NIP_EXISTANT.test(pin)) await echouer();

  const compSnap = await compagniesApprouvees(numero);
  if (compSnap.empty) await echouer();
  const compagnie = compSnap.docs[0];

  const limiteCompagnie = limiteur(`co_${compagnie.id}`, 30, 15 * MINUTE);
  await limiteCompagnie.verifier();

  const employes = db.collection("employees").where("companyId", "==", compagnie.id);
  const hash = hacherNip(compagnie.id, pin);
  // Migration paresseuse d'un NIP encore stocké en clair (données anciennes).
  const migrer = (doc) => doc.ref.update({pinHash: hash, pin: FieldValue.delete()});
  let employe = null;

  if (adresse) {
    const snap = await employes.where("courriel", "==", adresse).limit(2).get();
    if (snap.size === 1) {
      const e = snap.docs[0].data();
      if (egalConstant(e.pinHash, hash)) {
        employe = snap.docs[0];
      } else if (typeof e.pin === "string" && egalConstant(e.pin, pin)) {
        await migrer(snap.docs[0]);
        employe = snap.docs[0];
      }
    }
  } else {
    let snap = await employes.where("pinHash", "==", hash).limit(2).get();
    if (snap.empty) {
      snap = await employes.where("pin", "==", pin).limit(2).get();
      if (snap.size === 1) await migrer(snap.docs[0]);
    }
    if (snap.size > 1) {
      await limiteIp.compter();
      throw new HttpsError("failed-precondition",
          "Connectez-vous avec votre courriel. Mettez l'application à jour au besoin.");
    }
    if (snap.size === 1) employe = snap.docs[0];
  }

  if (!employe) await echouer(limiteCompagnie);

  const data = employe.data();
  const methode = adresse ? "courriel" : "nip";
  const estProprioApp = methode === "courriel" && (await proprioAppId()) === employe.id;
  await db.collection("sessions").doc(auth.uid).set({
    employeeId: employe.id,
    companyId: compagnie.id,
    methode,
    // Indicatif pour l'interface seulement : les règles et les fonctions
    // revérifient config/proprio_app à chaque requête.
    proprioApp: estProprioApp,
    creeLe: FieldValue.serverTimestamp(),
  });
  await limiteIp.reinitialiser();

  return {
    id: employe.id,
    nom: data.nom || "",
    courriel: data.courriel || null,
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

exports.inscrireCompagnie = onCall({...COMPAT, secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "inscrireCompagnie");
  exigerAnonyme(request);
  const d = request.data || {};

  const nomEntreprise = texte(d.nomEntreprise, "nom de l'entreprise", {max: 120});
  const nomLegal = texte(d.nomLegal, "nom légal", {max: 200});
  const secteur = texte(d.secteur, "secteur", {max: 100});
  const telephone = texte(d.telephone, "téléphone", {min: 0, max: 30});
  const nomAdmin = texte(d.nomAdmin, "nom de l'administrateur", {max: 100});
  const emailAdmin = courriel(d.emailAdmin);
  // 4 chiffres encore acceptés : les anciennes versions ne valident pas le format.
  const pinAdmin = texte(d.pinAdmin, "NIP", {min: 4, max: 8});
  if (!FORMAT_NIP_EXISTANT.test(pinAdmin)) {
    throw new HttpsError("invalid-argument", "Le NIP doit contenir de 4 à 8 chiffres.");
  }
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
    t.set(db.collection("companies_prive").doc(companyRef.id), {emailAdmin, proprietaireId: employeRef.id});
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

exports.approuverCompagnie = onCall({...COMPAT, secrets: [RESEND_API_KEY]}, async (request) => {
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
// Gestion des employés (admin de la compagnie)
// =============================================================================

async function envoyerNip(employe, pin, compagnie, nouveau) {
  if (!employe.courriel) return false;
  return envoyerCourriel({
    a: employe.courriel,
    sujet: nouveau ? `Votre accès à ${NOM_APP}` : `Votre nouveau NIP — ${NOM_APP}`,
    lignes: [
      `Bonjour ${employe.nom},`,
      nouveau ?
        `${compagnie.nomEntreprise} vous a créé un accès à ${NOM_APP}.` :
        `Un nouveau NIP vous a été attribué par ${compagnie.nomEntreprise}.`,
      `Numéro de compagnie : ${compagnie.numero}\nCourriel : ${employe.courriel}\nNIP : ${pin}`,
      "Vous pouvez changer ce NIP en tout temps dans l'onglet Compte de l'application.",
      "Ne partagez jamais votre NIP.",
    ],
  });
}

/**
 * Crée ou modifie un employé. Le NIP n'est jamais choisi par l'admin : un NIP
 * aléatoire est généré et envoyé par courriel à l'employé (création, ou
 * modification avec envoyerNouveauNip). Si le courriel ne peut pas partir
 * (Resend non configuré), le NIP est retourné une seule fois à l'admin.
 */
exports.enregistrerEmploye = onCall({secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "enregistrerEmploye");
  const ctx = await contexteAdmin(request);
  const d = request.data || {};
  const employeeId = d.employeeId == null ? null : texte(d.employeeId, "employeeId", {max: 128});
  const nom = texte(d.nom, "nom complet", {max: 100});
  const adresse = courriel(d.courriel);
  if (!ROLES.includes(d.role)) throw new HttpsError("invalid-argument", "Rôle invalide.");
  const nouveauNipDemande = !employeeId || d.envoyerNouveauNip === true;

  const employes = db.collection("employees");
  const ref = employeeId ? employes.doc(employeeId) : employes.doc();
  const pin = nouveauNipDemande ? await genererNipUnique(ctx.companyId) : null;

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

    // Le super-admin de la compagnie reste admin ; le rôle du Proprio ne change que par lui-même.
    let role = d.role;
    if (existant?.estProprietaire === true) role = "admin";
    if (ref.id === ctx.idProprioApp && ref.id !== ctx.employeeId) role = existant.role;

    const maj = {nom, courriel: adresse, role};
    if (pin) {
      maj.pinHash = hacherNip(ctx.companyId, pin);
      maj.pinModifieLe = FieldValue.serverTimestamp();
    }
    if (existant) {
      t.update(ref, {...maj, pin: FieldValue.delete(), nipRefuse: FieldValue.delete()});
    } else {
      t.set(ref, {...maj, companyId: ctx.companyId, estProprietaire: false});
    }
    return {...existant, ...maj};
  });

  if (!pin) return {id: ref.id};
  if (employeeId) await supprimerSessionsDe(ref.id);
  const envoye = await envoyerNip(enregistre, pin, ctx.compagnie, !employeeId);
  return envoye ? {id: ref.id, courrielEnvoye: true} : {id: ref.id, courrielEnvoye: false, nipTemporaire: pin};
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
    if (snap.data().estProprietaire === true || employeeId === ctx.idProprioApp) {
      throw new HttpsError("failed-precondition", "Le super-admin de la compagnie ne peut pas être retiré.");
    }
    t.delete(ref);
  });
  await supprimerSessionsDe(employeeId);
  return {ok: true};
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
  const actuelValide = egalConstant(e.pinHash, hacherNip(ctx.companyId, actuel)) ||
    (typeof e.pin === "string" && egalConstant(e.pin, actuel));
  if (!actuelValide) throw new HttpsError("permission-denied", "NIP actuel invalide.");

  // Aucune vérification d'unicité : un refus révélerait le NIP d'un collègue.
  await db.collection("employees").doc(ctx.employeeId).update({
    pinHash: hacherNip(ctx.companyId, nouveau),
    pin: FieldValue.delete(),
    pinModifieLe: FieldValue.serverTimestamp(),
  });
  // Déconnecte les autres appareils.
  await supprimerSessionsDe(ctx.employeeId, ctx.uid);

  if (e.courriel) {
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
  }
  return {ok: true};
});

function hacherCode(employeeId, code) {
  return hacherNip(`reinit:${employeeId}`, code);
}

async function exigerCourrielDisponible() {
  if (!courrielConfigure()) {
    throw new HttpsError("unavailable", "Service de courriel temporairement indisponible. Contactez votre employeur.");
  }
}

/** Envoie les numéros de compagnie liés à un courriel. Réponse identique dans tous les cas. */
exports.recupererNumeroCompagnie = onCall({...COMPAT, secrets: [RESEND_API_KEY]}, async (request) => {
  verifierAppCheck(request, "recupererNumeroCompagnie");
  exigerAnonyme(request);
  const adresse = courriel(request.data?.email);
  await exigerCourrielDisponible();

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

exports.demanderReinitialisationNip = onCall({...COMPAT, secrets: SECRETS_NIP_COURRIEL}, async (request) => {
  verifierAppCheck(request, "demanderReinitialisationNip");
  exigerAnonyme(request);
  const numero = texte(request.data?.numeroCompagnie, "numéro de compagnie", {max: 10});
  const adresse = courriel(request.data?.email);
  await exigerCourrielDisponible();

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

exports.validerReinitialisationNip = onCall({...COMPAT, secrets: SECRETS_NIP_COURRIEL}, async (request) => {
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
      pin: FieldValue.delete(),
      nipRefuse: FieldValue.delete(),
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

// =============================================================================
// Compatibilité avec les anciennes versions de l'app
// =============================================================================

/**
 * Les anciennes versions écrivent directement dans employees (règles
 * restreintes), avec un NIP en clair. Ce déclencheur le remplace aussitôt par
 * son empreinte. Si ce NIP est déjà celui d'un autre employé de la compagnie,
 * il est refusé (nipRefuse) pour ne pas bloquer la connexion de l'autre.
 * Supprime aussi les sessions et codes d'un employé retiré.
 */
exports.securiserEmploye = onDocumentWritten(
    {document: "employees/{employeeId}", secrets: SECRETS_NIP},
    async (event) => {
      const id = event.params.employeeId;
      const apres = event.data?.after?.exists ? event.data.after.data() : null;

      if (!apres) {
        await supprimerSessionsDe(id);
        await db.collection("reinitialisations_nip").doc(id).delete();
        return;
      }
      if (typeof apres.pin !== "string" || typeof apres.companyId !== "string") return;

      const pinHash = hacherNip(apres.companyId, apres.pin.trim());
      const doublons = await db.collection("employees")
          .where("companyId", "==", apres.companyId)
          .where("pinHash", "==", pinHash)
          .limit(2).get();
      const conflit = doublons.docs.some((doc) => doc.id !== id);
      const ref = event.data.after.ref;

      if (conflit) {
        logger.warn("NIP en double refusé (ancienne version)", {employeeId: id});
        await ref.update({pin: FieldValue.delete(), pinHash: FieldValue.delete(), nipRefuse: true});
      } else {
        await ref.update({
          pin: FieldValue.delete(),
          pinHash,
          nipRefuse: FieldValue.delete(),
          pinModifieLe: FieldValue.serverTimestamp(),
        });
      }
    });

/** Migration unique : remplace tout NIP stocké en clair par son empreinte. */
exports.migrerNips = onCall({secrets: SECRETS_NIP, timeoutSeconds: 540}, async (request) => {
  await contexteProprioApp(request);
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
