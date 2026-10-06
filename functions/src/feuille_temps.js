// Feuille de temps : calcul et validation côté serveur.
//
// Les heures payées ne sont JAMAIS reçues du client : il envoie seulement ce
// qu'il a saisi (chantier, heures de début et de fin, pauses prises,
// voyagement), et le serveur recalcule tout avec les règles de paie de la
// compagnie lues dans Firestore. Ce module est pur (aucun accès à la base) pour
// être testé sans émulateur ; l'appel et l'écriture sont dans index.js.
const {HttpsError} = require("firebase-functions/v2/https");

// Fuseau de l'échéance de la semaine (18 h le mardi suivant). Dette connue :
// un fuseau par compagnie serait plus juste pour une clientèle internationale.
const FUSEAU_ECHEANCE = "America/Toronto";

const NOMS_JOURS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"];

const MAX_VOYAGEMENT_MINUTES = 12 * 60;

// Mêmes bornes que firestore.rules (reglesPaieValides) et ReglesPaie (Dart).
const REGLES_DEFAUT = Object.freeze({
  pauseMatinMinutes: 15,
  pauseMatinPayee: false,
  dinerMinutes: 30,
  dinerPaye: true,
  voyagementActif: false,
  voyagementSeuilMinutes: 60,
  voyagementPourcentage: 50,
});
const BORNES = {
  pauseMatinMinutes: 120,
  dinerMinutes: 120,
  voyagementSeuilMinutes: 600,
  voyagementPourcentage: 100,
};

/** Règles de la compagnie ; toute valeur absente ou hors bornes prend le défaut. */
function reglesPaieDepuis(brut) {
  const m = brut && typeof brut === "object" ? brut : {};
  const r = {};
  for (const [cle, defaut] of Object.entries(REGLES_DEFAUT)) {
    const v = m[cle];
    if (typeof defaut === "boolean") {
      r[cle] = typeof v === "boolean" ? v : defaut;
    } else {
      r[cle] = Number.isInteger(v) && v >= 0 && v <= BORNES[cle] ? v : defaut;
    }
  }
  return r;
}

function ajustement(prise, payee, minutes) {
  if (prise && !payee) return -minutes;
  if (!prise && payee) return minutes;
  return 0;
}

/** Minutes payées d'une journée, ou null si les heures sont absentes/incohérentes. */
function minutesTravaillees(regles, {debut, fin, pauseMatin, diner}) {
  if (debut === null || fin === null) return null;
  let total = fin - debut;
  if (total <= 0) return null;
  total += ajustement(pauseMatin, regles.pauseMatinPayee, regles.pauseMatinMinutes);
  total += ajustement(diner, regles.dinerPaye, regles.dinerMinutes);
  return Math.max(total, 0);
}

/**
 * Minutes de voyagement payées : seul le temps AU-DELÀ du seuil est payé, au
 * pourcentage choisi. Seuil de 60 min : 2 h de voyagement = 1 h payée à x % ;
 * seuil de 30 min : 2 h = 1 h 30 payée à x %. Rien jusqu'au seuil.
 */
function minutesVoyagementPayees(regles, minutes) {
  const v = minutes ?? 0;
  const audela = v - regles.voyagementSeuilMinutes;
  if (!regles.voyagementActif || v <= 0 || audela <= 0) return 0;
  return audela * regles.voyagementPourcentage / 100;
}

const arrondir = (x) => Math.round(x * 10000) / 10000;

// -----------------------------------------------------------------------------
// Dates
// -----------------------------------------------------------------------------

function decalageMs(instant, fuseau) {
  const parties = new Intl.DateTimeFormat("en-CA", {
    timeZone: fuseau, hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(new Date(instant));
  const n = (type) => Number(parties.find((p) => p.type === type).value);
  const local = Date.UTC(n("year"), n("month") - 1, n("day"), n("hour"), n("minute"), n("second"));
  return local - Math.floor(instant / 1000) * 1000;
}

/** Instant (ms UTC) où il est jj/mm/aaaa hh:mm dans le fuseau donné. */
function instantLocal(annee, mois, jour, heure, minute, fuseau) {
  const naif = Date.UTC(annee, mois - 1, jour, heure, minute);
  let t = naif;
  for (let i = 0; i < 2; i++) t = naif - decalageMs(t, fuseau);
  return t;
}

const iso = (ms) => new Date(ms).toISOString().slice(0, 10);

/** Valide « AAAA-MM-JJ » : date réelle qui tombe un lundi. Retourne [a, m, j]. */
function analyserLundi(lundiDate) {
  if (typeof lundiDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(lundiDate)) {
    throw new HttpsError("invalid-argument", "Semaine invalide.");
  }
  const [a, m, j] = lundiDate.split("-").map(Number);
  const d = new Date(Date.UTC(a, m - 1, j));
  if (a < 2020 || a > 2100 || iso(d.getTime()) !== lundiDate || d.getUTCDay() !== 1) {
    throw new HttpsError("invalid-argument", "La semaine doit commencer un lundi.");
  }
  return [a, m, j];
}

/** Échéance : mardi suivant la semaine, 18 h dans le fuseau (instant ms). */
function echeanceSemaine(lundiDate, fuseau = FUSEAU_ECHEANCE) {
  const [a, m, j] = analyserLundi(lundiDate);
  const mardi = new Date(Date.UTC(a, m - 1, j + 8));
  return instantLocal(mardi.getUTCFullYear(), mardi.getUTCMonth() + 1, mardi.getUTCDate(), 18, 0, fuseau);
}

/** Lundi de la semaine courante dans le fuseau, en « AAAA-MM-JJ ». */
function lundiCourant(maintenantMs, fuseau = FUSEAU_ECHEANCE) {
  const parties = new Intl.DateTimeFormat("en-CA", {
    timeZone: fuseau, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(maintenantMs));
  const n = (type) => Number(parties.find((p) => p.type === type).value);
  const jour = new Date(Date.UTC(n("year"), n("month") - 1, n("day")));
  const depuisLundi = (jour.getUTCDay() + 6) % 7;
  return iso(jour.getTime() - depuisLundi * 86400000);
}

// -----------------------------------------------------------------------------
// Saisie
// -----------------------------------------------------------------------------

function minuteDuJour(valeur, etiquette) {
  if (valeur === null || valeur === undefined) return null;
  if (!Number.isInteger(valeur) || valeur < 0 || valeur > 1439) {
    throw new HttpsError("invalid-argument", `${etiquette} : heure invalide.`);
  }
  return valeur;
}

function booleen(valeur, etiquette) {
  if (typeof valeur !== "boolean") {
    throw new HttpsError("invalid-argument", `${etiquette} : valeur invalide.`);
  }
  return valeur;
}

/**
 * Lit et valide la saisie brute d'un jour. Aucune valeur calculée n'est
 * acceptée : les champs inconnus (heuresTravaillees, verrouille…) sont ignorés.
 */
function lireJour(entree, index) {
  const nomJour = NOMS_JOURS[index];
  if (!entree || typeof entree !== "object" || Array.isArray(entree)) {
    throw new HttpsError("invalid-argument", `${nomJour} : saisie invalide.`);
  }
  const estAucun = booleen(entree.estAucun ?? false, nomJour);
  if (estAucun) {
    return {nomJour, estAucun: true, chantierId: null, debut: null, fin: null,
      pauseMatin: false, diner: false, voyagement: null, vide: false};
  }
  const chantierId = entree.chantierId ?? null;
  if (chantierId !== null && (typeof chantierId !== "string" || chantierId.length < 1 ||
      chantierId.length > 128 || chantierId.includes("/"))) {
    throw new HttpsError("invalid-argument", `${nomJour} : chantier invalide.`);
  }
  const debut = minuteDuJour(entree.heureDebutMinutes, `${nomJour} (début)`);
  const fin = minuteDuJour(entree.heureFinMinutes, `${nomJour} (fin)`);
  let voyagement = entree.tempsVoyagementMinutes ?? null;
  if (voyagement !== null &&
      (!Number.isInteger(voyagement) || voyagement < 0 || voyagement > MAX_VOYAGEMENT_MINUTES)) {
    throw new HttpsError("invalid-argument", `${nomJour} : voyagement invalide.`);
  }
  if (voyagement === 0) voyagement = null;
  const pauseMatin = booleen(entree.pauseMatin ?? true, nomJour);
  const diner = booleen(entree.diner ?? true, nomJour);

  const vide = chantierId === null && debut === null && fin === null && voyagement === null;
  if (!vide) {
    if (chantierId === null) {
      throw new HttpsError("invalid-argument", `${nomJour} : choisissez un chantier.`);
    }
    if (debut === null || fin === null) {
      throw new HttpsError("invalid-argument", `${nomJour} : heures de début et de fin requises.`);
    }
    if (fin <= debut) {
      throw new HttpsError("invalid-argument", `${nomJour} : l'heure de fin doit suivre l'heure de début.`);
    }
  }
  return {nomJour, estAucun: false, chantierId, debut, fin, pauseMatin, diner, voyagement, vide};
}

/** Lit les jours (1 à 7, dans l'ordre lundi → dimanche). */
function lireJours(jours) {
  if (!Array.isArray(jours) || jours.length < 1 || jours.length > 7) {
    throw new HttpsError("invalid-argument", "La feuille doit contenir de 1 à 7 jours.");
  }
  return jours.map(lireJour);
}

/**
 * Calcule la feuille à enregistrer à partir des jours lus, des noms de chantier
 * (résolus côté serveur), des règles de la compagnie et de la feuille déjà
 * enregistrée (pour dater les modifications après verrouillage).
 *
 * `semaineFigee` : semaine antérieure à la semaine courante. Une journée dont la
 * saisie n'a pas changé garde ses valeurs calculées à l'époque : un changement
 * des règles de paie ne réécrit jamais le passé, même si la feuille est
 * renvoyée en entier. Une journée modifiée est recalculée avec les règles
 * actuelles.
 */
function calculerFeuille({jours, nomsChantiers, archives = new Set(), regles, existante, maintenantIso,
  semaineFigee = false}) {
  let minutesTravail = 0;
  let minutesVoyage = 0;
  let joursRecalcules = 0;
  // Journées conservées telles quelles (valeurs calculées à leur saisie).
  let heuresConservees = 0;
  let voyageConserve = 0;
  const anciens = Array.isArray(existante?.jours) ? existante.jours : [];

  const sortie = jours.map((j, i) => {
    // Une journée envoyée vide n'efface JAMAIS une journée déjà enregistrée :
    // un appareil qui n'a pas pu charger la semaine (réseau, ancienne version)
    // ne doit pas faire disparaître des heures soumises.
    if (j.vide && !j.estAucun && jourEnregistre(anciens[i])) {
      heuresConservees += anciens[i].heuresTravaillees ?? 0;
      voyageConserve += anciens[i].voyagementPayeHeures ?? 0;
      return anciens[i];
    }
    // Semaine passée : une journée inchangée garde ses valeurs d'origine.
    if (semaineFigee && !j.vide && jourEnregistre(anciens[i]) && memeSaisie(anciens[i], j, regles)) {
      heuresConservees += anciens[i].heuresTravaillees ?? 0;
      voyageConserve += anciens[i].voyagementPayeHeures ?? 0;
      return anciens[i];
    }
    // Un chantier archivé ne se choisit plus ; une journée déjà enregistrée
    // avec ce chantier peut encore être renvoyée telle quelle.
    if (!j.estAucun && !j.vide && archives.has(j.chantierId) &&
        anciens[i]?.chantierId !== j.chantierId) {
      throw new HttpsError("invalid-argument", `${j.nomJour} : ce chantier est archivé.`);
    }
    let heures = null;
    let voyPaye = 0;
    let voyagement = null;
    if (!j.estAucun && !j.vide) {
      joursRecalcules++;
      const minutes = minutesTravaillees(regles, j);
      minutesTravail += minutes ?? 0;
      heures = minutes === null ? null : arrondir(minutes / 60);
      if (regles.voyagementActif) {
        voyagement = j.voyagement;
        const payees = minutesVoyagementPayees(regles, voyagement);
        minutesVoyage += payees;
        voyPaye = arrondir(payees / 60);
      }
    }
    const rempli = j.estAucun || !j.vide;
    const ancien = anciens[i];
    const contenu = {
      nomJour: j.nomJour,
      chantierId: j.estAucun || j.vide ? null : j.chantierId,
      chantierNom: j.estAucun ? "Jour non travaillé" : (j.vide ? null : nomsChantiers.get(j.chantierId)),
      estAucun: j.estAucun,
      heureDebutMinutes: j.debut,
      heureFinMinutes: j.fin,
      pauseMatin: j.pauseMatin,
      diner: j.diner,
      heuresTravaillees: heures,
      tempsVoyagementMinutes: voyagement,
      voyagementPayeHeures: voyPaye,
      verrouille: rempli,
    };
    // Trace des corrections d'une journée déjà soumise.
    const stamp = ancien?.verrouille === true && changement(ancien, contenu) ?
      maintenantIso : ancien?.modifieApresVerrouillageLe;
    if (typeof stamp === "string") contenu.modifieApresVerrouillageLe = stamp;
    return contenu;
  });

  // Journées de la feuille enregistrée au-delà de celles reçues : conservées.
  for (let i = jours.length; i < anciens.length; i++) {
    sortie.push(anciens[i]);
    heuresConservees += anciens[i]?.heuresTravaillees ?? 0;
    voyageConserve += anciens[i]?.voyagementPayeHeures ?? 0;
  }

  const travail = minutesTravail / 60 + heuresConservees;
  const voyage = minutesVoyage / 60 + voyageConserve;
  return {
    jours: sortie,
    totalHeuresTravaillees: arrondir(travail),
    totalVoyagementPaye: arrondir(voyage),
    totalHeures: arrondir(travail + voyage),
    joursRecalcules,
  };
}

/**
 * Même saisie qu'à l'enregistrement ? Le voyagement ne compte que si la
 * compagnie le paie encore (sinon le champ n'est plus offert et l'appareil
 * l'envoie vide : ce n'est pas une modification).
 */
function memeSaisie(ancien, j, regles) {
  const egal = (a, b) => (a ?? null) === (b ?? null);
  return (ancien.estAucun === true) === j.estAucun &&
    egal(ancien.chantierId, j.chantierId) &&
    egal(ancien.heureDebutMinutes, j.debut) &&
    egal(ancien.heureFinMinutes, j.fin) &&
    (ancien.pauseMatin ?? true) === j.pauseMatin &&
    (ancien.diner ?? true) === j.diner &&
    (!regles.voyagementActif || egal(ancien.tempsVoyagementMinutes, j.voyagement));
}

/**
 * Recalcule une feuille déjà enregistrée avec de nouvelles règles de paie, à
 * partir de la saisie conservée (heures, pauses, voyagement). Sert à ajuster la
 * SEMAINE COURANTE quand l'employeur change ses règles ; l'appelant ne doit
 * jamais l'utiliser pour une semaine antérieure. Retourne les champs à écrire,
 * ou null si rien ne change.
 */
function recalculerFeuille(feuille, regles, maintenantIso) {
  const jours = Array.isArray(feuille?.jours) ? feuille.jours : [];
  // Aucune journée de travail enregistrée : rien à ajuster.
  if (!jours.some((j) => jourEnregistre(j) && j.estAucun !== true)) return null;
  let travail = 0;
  let voyage = 0;
  const sortie = jours.map((j) => {
    if (!jourEnregistre(j) || j.estAucun === true) return j;
    const minutes = minutesTravaillees(regles, {
      debut: j.heureDebutMinutes ?? null,
      fin: j.heureFinMinutes ?? null,
      pauseMatin: (j.pauseMatin ?? true) === true,
      diner: (j.diner ?? true) === true,
    });
    const heures = minutes === null ? null : arrondir(minutes / 60);
    const voyPaye = regles.voyagementActif ?
      arrondir(minutesVoyagementPayees(regles, j.tempsVoyagementMinutes ?? null) / 60) : 0;
    travail += heures ?? 0;
    voyage += voyPaye;
    return {...j, heuresTravaillees: heures, voyagementPayeHeures: voyPaye};
  });
  // Les journées non enregistrées (ou « non travaillées ») ne comptent pour rien.
  const totalHeuresTravaillees = arrondir(travail);
  const totalVoyagementPaye = arrondir(voyage);
  const totalHeures = arrondir(travail + voyage);
  const inchange = sortie.every((j, i) => j === jours[i] ||
      (j.heuresTravaillees === jours[i].heuresTravaillees &&
        j.voyagementPayeHeures === jours[i].voyagementPayeHeures)) &&
    totalHeuresTravaillees === feuille.totalHeuresTravaillees &&
    totalVoyagementPaye === feuille.totalVoyagementPaye &&
    totalHeures === feuille.totalHeures &&
    JSON.stringify(feuille.reglesPaie ?? null) === JSON.stringify(regles);
  if (inchange) return null;
  return {
    jours: sortie, totalHeures, totalHeuresTravaillees, totalVoyagementPaye,
    reglesPaie: regles, recalculeLe: maintenantIso,
  };
}

/** Journée déjà soumise : non travaillée, ou avec chantier et heures. */
function jourEnregistre(jour) {
  return !!jour && (jour.estAucun === true ||
    (typeof jour.chantierId === "string" && jour.heureDebutMinutes !== null &&
      jour.heureDebutMinutes !== undefined));
}

const CHAMPS_SAISIE = ["chantierId", "estAucun", "heureDebutMinutes", "heureFinMinutes",
  "pauseMatin", "diner", "tempsVoyagementMinutes"];

function changement(ancien, nouveau) {
  return CHAMPS_SAISIE.some((c) => (ancien[c] ?? null) !== (nouveau[c] ?? null));
}

module.exports = {
  FUSEAU_ECHEANCE, NOMS_JOURS, REGLES_DEFAUT,
  reglesPaieDepuis, minutesTravaillees, minutesVoyagementPayees,
  analyserLundi, echeanceSemaine, lundiCourant,
  lireJour, lireJours, calculerFeuille, recalculerFeuille,
};
