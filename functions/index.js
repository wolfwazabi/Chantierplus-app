const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// TODO avant un vrai lancement public : déplacer ce PIN vers Secret Manager
// plutôt que de le garder en dur dans le code.
const SUPER_ADMIN_PIN = "9137-BOREAL";

exports.connexionEmploye = onCall(async (request) => {
  const numeroCompagnie = (request.data.numeroCompagnie || "").trim();
  const pin = (request.data.pin || "").trim();
  const uid = request.auth ? request.auth.uid : null;

  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion anonyme requise.");
  }
  if (!numeroCompagnie || !pin) {
    throw new HttpsError("invalid-argument", "Numéro de compagnie et NIP requis.");
  }

  const compagnieSnap = await db
      .collection("companies")
      .where("numero", "==", numeroCompagnie)
      .where("statut", "==", "approuvee")
      .limit(1)
      .get();

  if (compagnieSnap.empty) {
    throw new HttpsError("not-found", "Numéro de compagnie invalide ou en attente d'approbation.");
  }
  const compagnieDoc = compagnieSnap.docs[0];

  const empSnap = await db
      .collection("employees")
      .where("companyId", "==", compagnieDoc.id)
      .where("pin", "==", pin)
      .limit(1)
      .get();

  if (empSnap.empty) {
    throw new HttpsError("not-found", "NIP invalide.");
  }
  const empDoc = empSnap.docs[0];
  const empData = empDoc.data();

  await db.collection("sessions").doc(uid).set({
    employeeId: empDoc.id,
    companyId: compagnieDoc.id,
  });

  return {
    id: empDoc.id,
    nom: empData.nom || "",
    role: empData.role || "employe",
    companyId: compagnieDoc.id,
    companyNom: compagnieDoc.data().nomEntreprise || "",
  };
});

exports.inscrireCompagnie = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion anonyme requise.");
  }

  const d = request.data;
  const nomEntreprise = (d.nomEntreprise || "").trim();
  const nomLegal = (d.nomLegal || "").trim();
  const secteur = (d.secteur || "").trim();
  const nombreEmployes = d.nombreEmployes || null;
  const telephone = (d.telephone || "").trim();
  const nomAdmin = (d.nomAdmin || "").trim();
  const pinAdmin = (d.pinAdmin || "").trim();

  if (!nomEntreprise || !nomLegal || !secteur || !nomAdmin || !pinAdmin) {
    throw new HttpsError("invalid-argument", "Veuillez remplir tous les champs requis.");
  }

  const compteurRef = db.collection("compteurs").doc("companies");
  const numero = await db.runTransaction(async (t) => {
    const compteurDoc = await t.get(compteurRef);
    const dernier = compteurDoc.exists ? compteurDoc.data().dernierNumero : 1000;
    const nouveau = dernier + 1;
    t.set(compteurRef, {dernierNumero: nouveau});
    return nouveau;
  });

  const companyRef = await db.collection("companies").add({
    numero: String(numero),
    nomEntreprise,
    nomLegal,
    secteur,
    nombreEmployes,
    telephone,
    statut: "attente",
    dateCreation: FieldValue.serverTimestamp(),
  });

  await db.collection("employees").add({
    companyId: companyRef.id,
    nom: nomAdmin,
    pin: pinAdmin,
    role: "admin",
  });

  return {numero: String(numero)};
});

exports.connexionSuperAdmin = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion anonyme requise.");
  }
  const pin = (request.data.pin || "").trim();
  if (pin !== SUPER_ADMIN_PIN) {
    throw new HttpsError("not-found", "PIN invalide.");
  }
  await db.collection("sessions").doc(uid).set({role: "superadmin"});
  return {ok: true};
});

exports.approuverCompagnie = onCall(async (request) => {
  const uid = request.auth ? request.auth.uid : null;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion anonyme requise.");
  }
  const sessionDoc = await db.collection("sessions").doc(uid).get();
  if (!sessionDoc.exists || sessionDoc.data().role !== "superadmin") {
    throw new HttpsError("permission-denied", "Accès réservé au Super Admin.");
  }

  const companyId = request.data.companyId;
  const approuver = request.data.approuver === true;
  if (!companyId) {
    throw new HttpsError("invalid-argument", "companyId requis.");
  }

  await db.collection("companies").doc(companyId).update({
    statut: approuver ? "approuvee" : "refusee",
  });

  return {ok: true};
});