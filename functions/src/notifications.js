// Notifications sur le téléphone des admins (Firebase Cloud Messaging), demandées par
// l'entrepreneur (16 oct. 2026) : quand quelque chose est entré sur un chantier (extra, travail
// à compléter, matériel, photos, document) ou quand un employé envoie ses heures.
//
//  - Seulement les admins actifs de la compagnie, jamais l'auteur lui-même.
//  - Chaque admin choisit ses catégories : preferences_notifications/{employeeId}
//    ({extras, travaux, materiel, heures, photos, documents} ; absent = oui).
//  - Chaque appareil connecté enregistre son jeton : appareils_notifications/{uid de la
//    session}. Un appareil dont la session n'existe plus (déconnecté) ou dont le jeton est
//    refusé par FCM est retiré.
//  - Photos : un envoi de plusieurs photos ne donne qu'une notification (une par auteur et par
//    chantier toutes les 10 minutes).
//  - En émulateur, rien ne part chez Google : l'envoi est écrit dans
//    envois_notifications_emulateur (les tests le lisent).

const CATEGORIES = ["extras", "travaux", "materiel", "heures", "photos", "documents"];

/** Photos d'un même auteur sur un même chantier : une notification par 10 minutes. */
const REGROUPEMENT_PHOTOS_MS = 10 * 60 * 1000;

const LONGUEUR_MAX = 140;

/** Codes FCM d'un jeton à oublier (appareil désinstallé, jeton périmé). */
const JETONS_PERIMES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

function couper(s, max = LONGUEUR_MAX) {
  const t = String(s ?? "").replace(/\s+/g, " ").trim();
  return t.length <= max ? t : `${t.slice(0, max - 1)}…`;
}

const nombre = (x) => (Math.round(x * 100) / 100).toString().replace(".", ",");

/**
 * Le message d'une entrée sur un chantier : {titre, corps}. `entree` : les champs du document
 * (texte, description, quantite, nom, ajouteParNom).
 */
function messageEntree(categorie, chantierNom, entree) {
  const auteur = couper(entree.ajouteParNom || "", 60);
  const par = auteur ? ` (${auteur})` : "";
  const chantier = couper(chantierNom || "Chantier", 60);
  switch (categorie) {
    case "extras":
      return {titre: `Extra — ${chantier}`, corps: couper(`${entree.description || ""}${par}`)};
    case "travaux":
      return {titre: `Travail à compléter — ${chantier}`, corps: couper(`${entree.texte || ""}${par}`)};
    case "materiel": {
      const q = entree.quantite ? ` × ${entree.quantite}` : "";
      return {titre: `Matériel manquant — ${chantier}`, corps: couper(`${entree.texte || ""}${q}${par}`)};
    }
    case "photos":
      return {titre: `Photos — ${chantier}`, corps: `${auteur || "Quelqu'un"} a ajouté des photos.`};
    case "documents":
      return {titre: `Document — ${chantier}`, corps: couper(`${entree.nom || ""}${par}`)};
    default:
      throw new Error(`catégorie inconnue : ${categorie}`);
  }
}

/**
 * Le message d'un envoi d'heures : les journées envoyées (dans l'ordre), et le total de la
 * semaine. `jours` : la saisie lue (lireJours) ; seules les journées remplies, fériées, non
 * travaillées ou supprimées comptent (une journée vide n'a rien changé).
 */
function messageHeures(employeNom, jours, totalHeures) {
  const noms = [];
  for (const j of jours) {
    const nom = j.nomJour.toLowerCase();
    if (j.effacer) noms.push(`${nom} supprimé`);
    else if (j.estFerie) noms.push(`${nom} férié`);
    else if (j.estBanque) noms.push(`${nom} banque (${nombre(j.heuresBanque)} h)`);
    else if (j.estAucun) noms.push(`${nom} non travaillé`);
    else if (!j.vide) noms.push(nom);
  }
  const liste = noms.length ? `${noms.join(", ")} — ` : "";
  const texte = `${liste}total de la semaine : ${nombre(totalHeures ?? 0)} h`;
  return {
    titre: `Heures — ${couper(employeNom || "Employé", 60)}`,
    corps: couper(texte.charAt(0).toUpperCase() + texte.slice(1)),
  };
}

/**
 * Les appareils à prévenir : ceux des admins actifs de la compagnie (sauf l'auteur) qui veulent
 * cette catégorie, dont la session est encore ouverte. Retourne [{uid, jeton}].
 */
async function destinataires(db, companyId, categorie, auteurId) {
  const admins = await db.collection("employees")
      .where("companyId", "==", companyId).where("role", "==", "admin").get();
  const ids = admins.docs
      .filter((d) => d.data().actif !== false && d.id !== auteurId)
      .map((d) => d.id);
  if (ids.length === 0) return [];
  const prefs = await db.getAll(...ids.map((id) => db.collection("preferences_notifications").doc(id)));
  const veulent = new Set(ids.filter((_, i) =>
    !prefs[i].exists || prefs[i].data().companyId !== companyId || prefs[i].data()[categorie] !== false));
  if (veulent.size === 0) return [];

  const appareils = (await db.collection("appareils_notifications")
      .where("companyId", "==", companyId).get()).docs
      .filter((d) => veulent.has(d.data().employeeId) && typeof d.data().jeton === "string");
  if (appareils.length === 0) return [];
  // Session encore ouverte, au même employé : un téléphone déconnecté ne reçoit plus rien.
  const sessions = await db.getAll(...appareils.map((d) => db.collection("sessions").doc(d.id)));
  const valides = [];
  const fermes = [];
  appareils.forEach((d, i) => {
    const s = sessions[i];
    if (s.exists && s.data().employeeId === d.data().employeeId && s.data().companyId === companyId) {
      valides.push({uid: d.id, jeton: d.data().jeton});
    } else {
      fermes.push(d.ref);
    }
  });
  await Promise.all(fermes.map((ref) => ref.delete()));
  return valides;
}

/**
 * Envoie la notification aux admins concernés. Ne lance jamais : une notification manquée ne
 * doit pas faire échouer ce qui l'a déclenchée (l'enregistrement des heures, par exemple).
 * Retourne le nombre d'appareils visés.
 */
async function notifier(db, messaging, {companyId, categorie, auteurId, titre, corps, donnees = {}, logger}) {
  try {
    if (!CATEGORIES.includes(categorie) || typeof companyId !== "string") return 0;
    const cibles = await destinataires(db, companyId, categorie, auteurId ?? null);
    if (cibles.length === 0) return 0;
    const data = {categorie, ...Object.fromEntries(
        Object.entries(donnees).filter(([, v]) => typeof v === "string"))};
    if (process.env.FUNCTIONS_EMULATOR === "true") {
      await db.collection("envois_notifications_emulateur").add({
        companyId, categorie, titre, corps, data, jetons: cibles.map((c) => c.jeton), le: Date.now(),
      });
      return cibles.length;
    }
    const reponse = await messaging.sendEachForMulticast({
      tokens: cibles.map((c) => c.jeton),
      notification: {title: titre, body: corps},
      data,
      android: {priority: "high", notification: {sound: "default"}},
      apns: {payload: {aps: {sound: "default"}}},
    });
    // Jetons refusés : l'appareil est oublié (désinstallé, jeton périmé).
    await Promise.all(reponse.responses.map((r, i) =>
      (!r.success && JETONS_PERIMES.has(r.error?.code)) ?
        db.collection("appareils_notifications").doc(cibles[i].uid).delete() : null));
    return cibles.length;
  } catch (e) {
    logger?.error("Notification non envoyée", {categorie, companyId, detail: String(e?.message ?? e)});
    return 0;
  }
}

/**
 * Photos : vrai si cette photo doit prévenir (la première d'un envoi), faux si une notification
 * pour le même auteur et le même chantier est partie il y a moins de 10 minutes.
 */
async function premierePhotoDuLot(db, {companyId, chantierId, auteurId, maintenant}) {
  const ref = db.collection("notifications_regroupees")
      .doc(`${companyId}_${chantierId}_${auteurId || "inconnu"}_photos`.replace(/\//g, "_"));
  return db.runTransaction(async (t) => {
    const d = (await t.get(ref)).data();
    if (d && maintenant - d.dernierEnvoi < REGROUPEMENT_PHOTOS_MS) return false;
    t.set(ref, {companyId, dernierEnvoi: maintenant});
    return true;
  });
}

module.exports = {
  CATEGORIES, REGROUPEMENT_PHOTOS_MS,
  messageEntree, messageHeures, destinataires, notifier, premierePhotoDuLot,
};
