// Tests unitaires des courriels envoyés par Resend (sans réseau : fetch simulé).
// Lancer : npm run test:unitaires
import { afterEach, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ENV = ['RESEND_API_KEY', 'COURRIEL_EXPEDITEUR', 'COURRIEL_REPONSE', 'FUNCTIONS_EMULATOR'];
const avant = {};
const fetchOrigine = globalThis.fetch;
let appels;

beforeEach(() => {
  for (const k of ENV) { avant[k] = process.env[k]; }
  process.env.RESEND_API_KEY = 're_cle_de_test';
  process.env.COURRIEL_EXPEDITEUR = 'Chantier+ <noreply@send.exemple.app>';
  process.env.COURRIEL_REPONSE = 'contact@exemple.app';
  delete process.env.FUNCTIONS_EMULATOR; // vrai envoi (simulé), pas la capture de l'émulateur
  appels = [];
  globalThis.fetch = async (url, init) => {
    appels.push({ url, init, corps: JSON.parse(init.body) });
    return { ok: true, status: 200 };
  };
});
afterEach(() => {
  for (const k of ENV) { if (avant[k] === undefined) delete process.env[k]; else process.env[k] = avant[k]; }
  globalThis.fetch = fetchOrigine;
});

const courriel = () => require('../../functions/src/courriel.js');
const lignes = ['Bonjour Jean,', 'Votre inscription est confirmée.'];

describe('Courriels (Resend)', () => {
  test('envoi : expéditeur, destinataire, sujet, texte et HTML', async () => {
    const ok = await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'Bienvenue', lignes });
    assert.equal(ok, true);
    assert.equal(appels.length, 1);
    assert.equal(appels[0].url, 'https://api.resend.com/emails');
    assert.equal(appels[0].init.headers.Authorization, 'Bearer re_cle_de_test');
    const c = appels[0].corps;
    assert.equal(c.from, 'Chantier+ <noreply@send.exemple.app>');
    assert.deepEqual(c.to, ['jean@exemple.ca']);
    assert.equal(c.subject, 'Bienvenue');
    assert.ok(c.text.includes('Votre inscription est confirmée.'));
    assert.ok(c.html.includes('Votre inscription est confirmée.'));
  });

  test('adresse de réponse : en-tête reply_to quand elle est configurée', async () => {
    await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes });
    assert.equal(appels[0].corps.reply_to, 'contact@exemple.app');
  });

  test('sans adresse de réponse : pas d\'en-tête reply_to', async () => {
    process.env.COURRIEL_REPONSE = '';
    await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes });
    assert.equal('reply_to' in appels[0].corps, false);
  });

  test('bas de courriel : dit pourquoi le message est reçu, en texte et en HTML', async () => {
    await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes });
    const { text, html } = appels[0].corps;
    assert.ok(text.includes('Vous recevez ce message parce que'));
    assert.ok(text.includes('Répondez simplement à ce courriel'));
    assert.ok(html.includes('Vous recevez ce message parce que'));
    // Le motif vient après le contenu et la signature.
    assert.ok(text.indexOf('Vous recevez') > text.indexOf('— Chantier+'));
  });

  test('HTML : le contenu variable est échappé (pas d\'injection)', async () => {
    await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes: ['<script>alert(1)</script> & "x"'] });
    const { html, text } = appels[0].corps;
    assert.ok(!html.includes('<script>'));
    assert.ok(html.includes('&lt;script&gt;'));
    assert.ok(text.includes('<script>'), 'le texte brut reste tel quel');
  });

  test('refus de Resend ou réseau coupé : retourne false, ne lance jamais', async () => {
    globalThis.fetch = async () => ({ ok: false, status: 422 });
    assert.equal(await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes }), false);
    globalThis.fetch = async () => { throw new Error('ECONNRESET'); };
    assert.equal(await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes }), false);
  });

  test('non configuré (clé absente ou expéditeur vide) : rien n\'est envoyé', async () => {
    process.env.RESEND_API_KEY = '';
    assert.equal(await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes }), false);
    process.env.RESEND_API_KEY = 're_cle_de_test';
    process.env.COURRIEL_EXPEDITEUR = '';
    assert.equal(await courriel().envoyerCourriel({ a: 'jean@exemple.ca', sujet: 'S', lignes }), false);
    assert.equal(appels.length, 0);
  });
});
