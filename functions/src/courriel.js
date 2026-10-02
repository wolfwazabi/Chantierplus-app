const {defineSecret, defineString} = require("firebase-functions/params");
const {logger} = require("firebase-functions");

// Clé API Resend (Secret Manager). Valeur « non-configure » tant que le compte
// Resend n'est pas prêt : les envois échouent alors proprement (resultat false).
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

// Adresse d'expédition vérifiée chez Resend, ex. « Boréal <noreply@boreal.ca> ».
const COURRIEL_EXPEDITEUR = defineString("COURRIEL_EXPEDITEUR", {default: ""});

// Adresse où aboutissent les réponses des destinataires (une vraie boîte, lue
// par une personne) ; vide : pas d'en-tête « Répondre à ».
const COURRIEL_REPONSE = defineString("COURRIEL_REPONSE", {default: ""});

const NOM_APP = "Chantier+";

// Bas de courriel : dit pourquoi le message est reçu (les filtres antipourriel
// et les destinataires s'y fient) et où répondre.
const MOTIF_RECEPTION =
  "Vous recevez ce message parce que votre adresse courriel est associée à un compte " +
  "Chantier+ (inscription, ajout à une équipe ou demande de votre part). " +
  "Si ce n'est pas le cas, ignorez-le : aucune action n'est requise. " +
  "Une question ? Répondez simplement à ce courriel.";

function courrielConfigure() {
  const cle = RESEND_API_KEY.value();
  return Boolean(cle && cle.startsWith("re_") && COURRIEL_EXPEDITEUR.value());
}

function echapper(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
  })[c]);
}

/**
 * Envoie un courriel via l'API Resend. Ne lance jamais : retourne true si
 * l'envoi est accepté, false sinon (non configuré, erreur réseau ou API).
 * `lignes` : paragraphes en texte brut (échappés pour la version HTML).
 */
async function envoyerCourriel({a, sujet, lignes}) {
  if (!courrielConfigure()) {
    logger.warn("Courriel non envoyé : Resend non configuré", {sujet});
    return false;
  }
  const texteBrut = [...lignes, "", `— ${NOM_APP}`, MOTIF_RECEPTION].join("\n\n");
  const html = [
    "<div style=\"font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#222\">",
    ...lignes.map((l) => `<p>${echapper(l).replace(/\n/g, "<br>")}</p>`),
    `<p style="color:#777;font-size:13px">— ${NOM_APP}</p>`,
    `<p style="color:#999;font-size:12px">${echapper(MOTIF_RECEPTION)}</p>`,
    "</div>",
  ].join("");

  // Émulateur seulement (variable posée par Firebase, jamais en production) :
  // le courriel est conservé dans Firestore pour les tests, rien n'est envoyé.
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    const {getFirestore, FieldValue} = require("firebase-admin/firestore");
    await getFirestore().collection("_courriels_emulateur").add({
      a, sujet, texte: texteBrut, envoyeLe: FieldValue.serverTimestamp(),
    });
    return true;
  }

  try {
    const reponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: COURRIEL_EXPEDITEUR.value(),
        to: [a],
        subject: sujet,
        text: texteBrut,
        html,
        ...(COURRIEL_REPONSE.value() ? {reply_to: COURRIEL_REPONSE.value()} : {}),
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!reponse.ok) {
      logger.error("Resend a refusé l'envoi", {statut: reponse.status, sujet});
      return false;
    }
    return true;
  } catch (e) {
    logger.error("Échec d'envoi Resend", {erreur: e.message, sujet});
    return false;
  }
}

module.exports = {RESEND_API_KEY, COURRIEL_EXPEDITEUR, COURRIEL_REPONSE, MOTIF_RECEPTION, envoyerCourriel, courrielConfigure, NOM_APP};
