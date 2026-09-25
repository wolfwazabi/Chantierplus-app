// Tests d'intégration des Cloud Functions : émulateurs Auth + Functions +
// Firestore, avec les vraies règles (firestore.rules) appliquées aux lectures
// client. Dans l'émulateur, les courriels sont conservés dans la collection
// _courriels_emulateur au lieu d'être envoyés. Lancer via : npm run test:functions
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInAnonymously } from 'firebase/auth';
import { connectFunctionsEmulator, getFunctions, httpsCallable } from 'firebase/functions';
import {
  addDoc, collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, query, updateDoc, where,
} from 'firebase/firestore';
import { initializeApp as initAdmin } from 'firebase-admin/app';
import { getFirestore as getAdminDb } from 'firebase-admin/firestore';

const PROJET = 'demo-construction-rules';
const MONTREAL = 'northamerica-northeast1';
const ANCIENNE_REGION = 'us-central1';
const PEPPER_EMULATEUR = 'cle-de-test-emulateur-seulement'; // functions/.secret.local
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const adminDb = getAdminDb(initAdmin({ projectId: PROJET }, 'admin-tests'));
const hacher = (companyId, pin) => createHmac('sha256', PEPPER_EMULATEUR).update(`${companyId}:${pin}`).digest('hex');

const apps = [];
let compteur = 0;

/** Un « appareil » client isolé (sa propre session Auth). */
async function appareil(region = MONTREAL) {
  const app = initializeApp({ projectId: PROJET, apiKey: 'demo-key', appId: 'demo' }, `client-${compteur++}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const fns = getFunctions(app, region);
  connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  return { auth, db, appeler: (nom, data) => httpsCallable(fns, nom)(data).then((r) => r.data) };
}

async function connecter(numero, pin, courriel, region = MONTREAL) {
  const a = await appareil(region);
  const profil = await a.appeler('connexionEmploye', { numeroCompagnie: numero, pin, ...(courriel && { courriel }) });
  return { ...a, profil };
}

async function rejette(promesse, code) {
  await assert.rejects(promesse, (e) => {
    assert.equal(e.code, `functions/${code}`, `code attendu ${code}, reçu ${e.code} (${e.message})`);
    return true;
  });
}

/** Dernier courriel capturé pour une adresse (et un sujet), en attendant au besoin. */
async function dernierCourriel(a, sujetContient = '') {
  for (let i = 0; i < 30; i++) {
    const snap = await adminDb.collection('_courriels_emulateur').where('a', '==', a).get();
    const msgs = snap.docs.map((d) => d.data())
      .filter((m) => m.sujet.includes(sujetContient))
      .sort((x, y) => (y.envoyeLe?.toMillis() ?? 0) - (x.envoyeLe?.toMillis() ?? 0));
    if (msgs.length) return msgs[0];
    await new Promise((r) => setTimeout(r, 200));
  }
  return null;
}

const extraire = (texte, etiquette) => texte.match(new RegExp(`${etiquette} : (\\d+)`))?.[1];

async function attendre(condition) {
  for (let i = 0; i < 50; i++) {
    if (await condition()) return;
    await new Promise((r) => setTimeout(r, 200));
  }
  assert.fail('condition jamais atteinte');
}

const viderLimites = async () =>
  Promise.all((await adminDb.collection('limites_connexion').get()).docs.map((d) => d.ref.delete()));

const inscription = (over = {}) => ({
  nomEntreprise: 'Construction Test', nomLegal: 'Construction Test inc.', secteur: 'Entrepreneur général',
  nombreEmployes: 12, telephone: '514-555-0000', nomAdmin: 'Proprio', pinAdmin: '1234',
  emailAdmin: 'Proprio@Exemple.ca', ...over,
});

// État partagé entre les tests (exécutés dans l'ordre).
let numeroS; let numero; let companyId; let proprioId;
let nipJean; let jeanId;

before(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJET}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${PROJET}/accounts`, { method: 'DELETE' });
});
beforeEach(viderLimites);
after(async () => { await Promise.all(apps.map((a) => deleteApp(a))); });

// =============================================================================
describe('Super-admin, inscription et approbation', () => {
  test('mise en place : compagnie du super-admin (approuvée, config/super_admin posé à la console)', async () => {
    const a = await appareil();
    ({ numero: numeroS } = await a.appeler('inscrireCompagnie',
      inscription({ nomEntreprise: 'Boréal', nomAdmin: 'Super', emailAdmin: 'super@exemple.ca', pinAdmin: '246810' })));
    const comp = (await adminDb.collection('companies').where('numero', '==', numeroS).get()).docs[0];
    await comp.ref.update({ statut: 'approuvee' });
    const proprio = (await adminDb.collection('employees').where('companyId', '==', comp.id).get()).docs[0];
    await adminDb.collection('config').doc('super_admin').set({ employeeId: proprio.id });
  });

  test('inscription : validations (NIP, courriel, longueur)', async () => {
    const a = await appareil();
    await rejette(a.appeler('inscrireCompagnie', inscription({ pinAdmin: 'abcd' })), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', inscription({ emailAdmin: 'pas-un-courriel' })), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', inscription({ nomEntreprise: 'x'.repeat(500) })), 'invalid-argument');
  });

  test('inscription (ancienne région) : compagnie en attente, propriétaire haché, courriel reçu', async () => {
    const a = await appareil(ANCIENNE_REGION);
    ({ numero } = await a.appeler('inscrireCompagnie', inscription()));
    const comp = (await adminDb.collection('companies').where('numero', '==', numero).get()).docs[0];
    companyId = comp.id;
    assert.equal(comp.data().statut, 'attente');

    const emps = await adminDb.collection('employees').where('companyId', '==', companyId).get();
    assert.equal(emps.size, 1);
    const p = emps.docs[0].data();
    proprioId = emps.docs[0].id;
    assert.equal(p.estProprietaire, true);
    assert.equal(p.courriel, 'proprio@exemple.ca');
    assert.equal(p.pin, undefined, 'le NIP ne doit jamais être stocké en clair');
    assert.equal(p.pinHash, hacher(companyId, '1234'));

    const msg = await dernierCourriel('proprio@exemple.ca', numero);
    assert.ok(msg, 'courriel de confirmation attendu');
  });

  test('connexion refusée tant que la compagnie est en attente', async () => {
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '1234' }), 'not-found');
  });

  test('super-admin par NIP seul : pas de pouvoirs ; un admin ordinaire non plus', async () => {
    const parNip = await connecter(numeroS, '246810');
    assert.equal(parNip.profil.estSuperAdmin, false);
    await rejette(parNip.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');
    await assert.rejects(getDocs(collection(parNip.db, 'companies')));
  });

  test('un champ superAdmin sur une autre fiche ne donne aucun pouvoir', async () => {
    const comp = (await adminDb.collection('companies').where('numero', '==', numeroS).get()).docs[0];
    await adminDb.collection('employees').add({
      companyId: comp.id, nom: 'Usurpateur', role: 'admin', courriel: 'usurpateur@exemple.ca',
      superAdmin: true, pinHash: hacher(comp.id, '112233'),
    });
    const u = await connecter(numeroS, '112233', 'usurpateur@exemple.ca');
    assert.equal(u.profil.estSuperAdmin, false);
    await rejette(u.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');
    await assert.rejects(getDocs(collection(u.db, 'companies')));
  });

  test('super-admin par courriel : approuve une seule fois ; le propriétaire est avisé', async () => {
    const s = await connecter(numeroS, '246810', 'super@exemple.ca');
    assert.equal(s.profil.estSuperAdmin, true);
    assert.ok((await getDocs(collection(s.db, 'companies'))).size >= 2);
    await rejette(s.appeler('approuverCompagnie', { companyId, approuver: 'oui' }), 'invalid-argument');
    assert.deepEqual(await s.appeler('approuverCompagnie', { companyId, approuver: true }), { ok: true });
    await rejette(s.appeler('approuverCompagnie', { companyId, approuver: false }), 'failed-precondition');
    assert.ok(await dernierCourriel('proprio@exemple.ca', 'approuvée'));
  });
});

// =============================================================================
describe('Connexion employé', () => {
  test('courriel + NIP : session « courriel », profil propriétaire', async () => {
    const e = await connecter(numero, '1234', 'PROPRIO@exemple.ca');
    assert.equal(e.profil.estProprietaire, true);
    assert.equal(e.profil.role, 'admin');
    assert.equal(e.profil.courriel, 'proprio@exemple.ca');
    const session = await getDoc(doc(e.db, 'sessions', e.auth.currentUser.uid));
    assert.equal(session.data().methode, 'courriel');
  });

  test('[anciennes versions] NIP seul en us-central1 : OK si le NIP est unique', async () => {
    const e = await connecter(numero, '1234', null, ANCIENNE_REGION);
    assert.equal(e.profil.id, proprioId);
  });

  test('erreurs : même message générique (numéro, courriel ou NIP faux)', async () => {
    const a = await appareil();
    const messages = [];
    for (const essai of [
      { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '9999' },
      { numeroCompagnie: numero, courriel: 'inconnu@exemple.ca', pin: '1234' },
      { numeroCompagnie: '999999', courriel: 'proprio@exemple.ca', pin: '1234' },
      { numeroCompagnie: numero, pin: '9999' },
    ]) {
      await assert.rejects(a.appeler('connexionEmploye', essai), (e) => {
        assert.equal(e.code, 'functions/not-found');
        messages.push(e.message);
        return true;
      });
    }
    assert.equal(new Set(messages).size, 1, 'les messages ne doivent pas révéler ce qui existe');
  });

  test('migration paresseuse : un ancien NIP en clair fonctionne puis est haché', async () => {
    const ref = await adminDb.collection('employees').add({ companyId, nom: 'Ancien', role: 'employe', pin: '4321' });
    const e = await connecter(numero, '4321');
    assert.equal(e.profil.id, ref.id);
    const apres = (await ref.get()).data();
    assert.equal(apres.pin, undefined);
    assert.equal(apres.pinHash, hacher(companyId, '4321'));
  });

  test('NIP seul ambigu (partagé par 2 employés) : courriel exigé', async () => {
    const h = hacher(companyId, '777777');
    await adminDb.collection('employees').add({ companyId, nom: 'Jumeau 1', role: 'employe', courriel: 'j1@exemple.ca', pinHash: h });
    await adminDb.collection('employees').add({ companyId, nom: 'Jumeau 2', role: 'employe', courriel: 'j2@exemple.ca', pinHash: h });
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '777777' }), 'failed-precondition');
    const j2 = await connecter(numero, '777777', 'j2@exemple.ca');
    assert.equal(j2.profil.nom, 'Jumeau 2');
  });

  test('config/securite : la connexion par NIP seul peut être désactivée', async () => {
    await adminDb.collection('config').doc('securite').set({ connexionNipSeulAutorisee: false });
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '1234' }), 'failed-precondition');
    await connecter(numero, '1234', 'proprio@exemple.ca');
    await adminDb.collection('config').doc('securite').delete();
  });
});

// =============================================================================
describe('Création d\'employés : NIP aléatoire envoyé par courriel', () => {
  let proprio;
  before(async () => { proprio = await connecter(numero, '1234', 'proprio@exemple.ca'); });

  test('création : nom + courriel + rôle → NIP de 6 chiffres envoyé à l\'employé', async () => {
    const r = await proprio.appeler('enregistrerEmploye', { nom: 'Jean Tremblay', courriel: 'Jean@Exemple.ca', role: 'employe' });
    jeanId = r.id;
    assert.equal(r.courrielEnvoye, true);
    assert.equal(r.nipTemporaire, undefined, 'le NIP ne doit pas être retourné à l\'admin');
    const msg = await dernierCourriel('jean@exemple.ca', 'accès');
    nipJean = extraire(msg.texte, 'NIP');
    assert.match(nipJean, /^\d{6}$/);
    assert.ok(msg.texte.includes(numero));
    const fiche = (await adminDb.collection('employees').doc(jeanId).get()).data();
    assert.equal(fiche.pinHash, hacher(companyId, nipJean));
    assert.equal(fiche.estProprietaire, false);
  });

  test('refus : courriel en double, courriel manquant, rôle invalide, non-admin', async () => {
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'Double', courriel: 'jean@exemple.ca', role: 'employe' }), 'already-exists');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'Sans', role: 'employe' }), 'invalid-argument');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'X', courriel: 'x@exemple.ca', role: 'patron' }), 'invalid-argument');
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    await rejette(jean.appeler('enregistrerEmploye', { nom: 'Pirate', courriel: 'p@exemple.ca', role: 'admin' }), 'permission-denied');
    await rejette(jean.appeler('supprimerEmploye', { employeeId: proprioId }), 'permission-denied');
    await assert.rejects(getDocs(query(collection(jean.db, 'employees'), where('companyId', '==', companyId))));
  });

  test('modification : NIP conservé ; le propriétaire reste admin', async () => {
    await proprio.appeler('enregistrerEmploye', { employeeId: jeanId, nom: 'Jean Tremblay', courriel: 'jean@exemple.ca', role: 'plus' });
    assert.equal((await adminDb.collection('employees').doc(jeanId).get()).data().role, 'plus');
    await connecter(numero, nipJean, 'jean@exemple.ca');
    await proprio.appeler('enregistrerEmploye', { employeeId: proprioId, nom: 'Proprio', courriel: 'proprio@exemple.ca', role: 'employe' });
    assert.equal((await adminDb.collection('employees').doc(proprioId).get()).data().role, 'admin');
  });

  test('nouveau NIP envoyé par l\'admin : l\'ancien ne fonctionne plus, sessions coupées', async () => {
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    await proprio.appeler('enregistrerEmploye',
      { employeeId: jeanId, nom: 'Jean Tremblay', courriel: 'jean@exemple.ca', role: 'plus', envoyerNouveauNip: true });
    const msg = await dernierCourriel('jean@exemple.ca', 'nouveau NIP');
    const nouveau = extraire(msg.texte, 'NIP');
    assert.notEqual(nouveau, nipJean);
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel: 'jean@exemple.ca', pin: nipJean }), 'not-found');
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)), 'ancienne session coupée');
    nipJean = nouveau;
    await connecter(numero, nipJean, 'jean@exemple.ca');
  });
});

// =============================================================================
describe('NIP : changement par l\'employé et récupération', () => {
  test('changerNip : NIP actuel exigé, 6 chiffres minimum, autres appareils déconnectés', async () => {
    const autreAppareil = await connecter(numero, nipJean, 'jean@exemple.ca');
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    await rejette(jean.appeler('changerNip', { nipActuel: '000000', nouveauNip: '135790' }), 'permission-denied');
    await rejette(jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '1357' }), 'invalid-argument');
    assert.deepEqual(await jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '135790' }), { ok: true });
    nipJean = '135790';
    assert.ok((await getDoc(doc(jean.db, 'companies', companyId))).exists(), 'appareil courant conservé');
    await assert.rejects(getDoc(doc(autreAppareil.db, 'companies', companyId)), 'autre appareil déconnecté');
    assert.ok(await dernierCourriel('jean@exemple.ca', 'modifié'));
    await connecter(numero, '135790', 'jean@exemple.ca');
  });

  test('changerNip : un NIP déjà pris par un collègue est accepté (aucune fuite)', async () => {
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    assert.deepEqual(await jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '777777' }), { ok: true });
    nipJean = '777777';
    await connecter(numero, nipJean, 'jean@exemple.ca');
  });

  test('NIP oublié : code par courriel, 5 essais, nouveau NIP, sessions coupées', async () => {
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    const a = await appareil(ANCIENNE_REGION);
    assert.deepEqual(await a.appeler('demanderReinitialisationNip', { numeroCompagnie: numero, email: 'jean@exemple.ca' }), { ok: true });
    const code = extraire((await dernierCourriel('jean@exemple.ca', 'réinitialisation')).texte, 'Votre code de réinitialisation');
    assert.match(code, /^\d{6}$/);
    const essai = (c, pin = '864209') =>
      a.appeler('validerReinitialisationNip', { numeroCompagnie: numero, email: 'jean@exemple.ca', code: c, nouveauPin: pin });
    await rejette(essai('000000'), 'permission-denied');
    await rejette(essai(code, '12'), 'invalid-argument');
    assert.deepEqual(await essai(code), { ok: true });
    await rejette(essai(code), 'permission-denied'); // code à usage unique
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)), 'sessions coupées');
    nipJean = '864209';
    await connecter(numero, nipJean, 'jean@exemple.ca');
  });

  test('NIP oublié : code bloqué après 5 mauvais essais', async () => {
    const a = await appareil();
    await a.appeler('demanderReinitialisationNip', { numeroCompagnie: numero, email: 'jean@exemple.ca' });
    const code = extraire((await dernierCourriel('jean@exemple.ca', 'réinitialisation')).texte, 'Votre code de réinitialisation');
    const essai = (c) => a.appeler('validerReinitialisationNip',
      { numeroCompagnie: numero, email: 'jean@exemple.ca', code: c, nouveauPin: '999111' });
    for (let i = 0; i < 5; i++) await rejette(essai(code === '000000' ? '000001' : '000000'), 'permission-denied');
    await rejette(essai(code), 'permission-denied');
  });

  test('courriel inconnu : même réponse, aucun courriel envoyé', async () => {
    const a = await appareil();
    assert.deepEqual(await a.appeler('demanderReinitialisationNip', { numeroCompagnie: numero, email: 'fantome@exemple.ca' }), { ok: true });
    assert.deepEqual(await a.appeler('recupererNumeroCompagnie', { email: 'fantome@exemple.ca' }), { ok: true });
    const snap = await adminDb.collection('_courriels_emulateur').where('a', '==', 'fantome@exemple.ca').get();
    assert.equal(snap.size, 0);
  });

  test('numéro de compagnie oublié : envoyé au courriel de l\'employé', async () => {
    const a = await appareil();
    assert.deepEqual(await a.appeler('recupererNumeroCompagnie', { email: 'Jean@exemple.ca' }), { ok: true });
    const msg = await dernierCourriel('jean@exemple.ca', 'numéro de compagnie');
    assert.ok(msg.texte.includes(numero));
  });
});

// =============================================================================
describe('Retrait, protections et isolation', () => {
  let proprio;
  before(async () => { proprio = await connecter(numero, '1234', 'proprio@exemple.ca'); });

  test('propriétaire et super-admin : ne peuvent pas être retirés', async () => {
    const { id: adminId, nipTemporaire } = await proprio.appeler('enregistrerEmploye',
      { nom: 'Second admin', courriel: 'admin2@exemple.ca', role: 'admin' });
    assert.equal(nipTemporaire, undefined);
    const nip = extraire((await dernierCourriel('admin2@exemple.ca', 'accès')).texte, 'NIP');
    const second = await connecter(numero, nip, 'admin2@exemple.ca');
    assert.equal(second.profil.id, adminId);
    await rejette(second.appeler('supprimerEmploye', { employeeId: proprioId }), 'failed-precondition');
    await rejette(proprio.appeler('supprimerEmploye', { employeeId: proprioId }), 'failed-precondition');
  });

  test('retrait d\'un employé : fiche et sessions supprimées, accès coupé', async () => {
    const jean = await connecter(numero, nipJean, 'jean@exemple.ca');
    await proprio.appeler('supprimerEmploye', { employeeId: jeanId });
    assert.equal((await adminDb.collection('employees').doc(jeanId).get()).exists, false);
    assert.equal((await adminDb.collection('sessions').where('employeeId', '==', jeanId).get()).size, 0);
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)));
  });

  test('isolation : l\'admin d\'une autre compagnie ne touche pas à ces employés', async () => {
    const a = await appareil();
    const { numero: numeroB } = await a.appeler('inscrireCompagnie',
      inscription({ nomEntreprise: 'Bêta', emailAdmin: 'b@exemple.ca', pinAdmin: '135791' }));
    const compB = (await adminDb.collection('companies').where('numero', '==', numeroB).get()).docs[0];
    await compB.ref.update({ statut: 'approuvee' });
    const adminB = await connecter(numeroB, '135791', 'b@exemple.ca');

    await rejette(adminB.appeler('enregistrerEmploye',
      { employeeId: proprioId, nom: 'Piraté', courriel: 'p@exemple.ca', role: 'employe' }), 'not-found');
    await assert.rejects(getDocs(query(collection(adminB.db, 'employees'), where('companyId', '==', companyId))));
    await assert.rejects(getDoc(doc(adminB.db, 'companies', companyId)));
  });
});

// =============================================================================
describe('Compatibilité : anciennes versions de l\'app', () => {
  let proprio;
  before(async () => { proprio = await connecter(numero, '1234', null, ANCIENNE_REGION); });

  test('l\'ancien écran employés écrit un NIP en clair : haché aussitôt par le serveur', async () => {
    const ref = await addDoc(collection(proprio.db, 'employees'),
      { companyId, nom: 'Ancien écran', pin: '5678', role: 'employe', estProprietaire: false });
    await attendre(async () => (await adminDb.collection('employees').doc(ref.id).get()).data().pin === undefined);
    assert.equal((await adminDb.collection('employees').doc(ref.id).get()).data().pinHash, hacher(companyId, '5678'));
    const e = await connecter(numero, '5678', null, ANCIENNE_REGION);
    assert.equal(e.profil.id, ref.id);
  });

  test('NIP en double saisi par l\'ancien écran : refusé sans bloquer le collègue', async () => {
    const ref = await addDoc(collection(proprio.db, 'employees'),
      { companyId, nom: 'Doublon', pin: '5678', role: 'employe', estProprietaire: false });
    await attendre(async () => (await adminDb.collection('employees').doc(ref.id).get()).data().nipRefuse === true);
    const fiche = (await adminDb.collection('employees').doc(ref.id).get()).data();
    assert.equal(fiche.pin, undefined);
    assert.equal(fiche.pinHash, undefined);
    const e = await connecter(numero, '5678', null, ANCIENNE_REGION);
    assert.equal(e.profil.nom, 'Ancien écran');
  });

  test('l\'ancien écran modifie un employé (nom, NIP, rôle) → OK et haché', async () => {
    const emp = (await adminDb.collection('employees').where('nom', '==', 'Ancien écran').get()).docs[0];
    await updateDoc(doc(proprio.db, 'employees', emp.id), { nom: 'Ancien écran', pin: '2468', role: 'plus' });
    await attendre(async () => (await emp.ref.get()).data().pinHash === hacher(companyId, '2468'));
    assert.equal((await emp.ref.get()).data().pin, undefined);
  });
});

// =============================================================================
describe('Migration et limites', () => {
  test('migrerNips : super-admin (courriel) seulement', async () => {
    const ref = await adminDb.collection('employees').add({ companyId, nom: 'Reste', role: 'employe', pin: '3690' });
    const p = await connecter(numero, '1234', 'proprio@exemple.ca');
    await rejette(p.appeler('migrerNips'), 'permission-denied');
    const s = await connecter(numeroS, '246810', 'super@exemple.ca');
    // Le déclencheur peut avoir haché ce NIP avant la migration : seul l'état final compte.
    assert.equal(typeof (await s.appeler('migrerNips')).migres, 'number');
    await attendre(async () => (await ref.get()).data().pin === undefined);
    assert.equal((await ref.get()).data().pinHash, hacher(companyId, '3690'));
  });

  test('force brute : blocage après 10 échecs par IP', async () => {
    const a = await appareil();
    for (let i = 0; i < 10; i++) {
      await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: `90${i}0` }), 'not-found');
    }
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '1234' }), 'resource-exhausted');
  });

  test('changerNip : 5 tentatives par jour au maximum', async () => {
    const e = await connecter(numero, '1234', 'proprio@exemple.ca');
    for (let i = 0; i < 5; i++) {
      await rejette(e.appeler('changerNip', { nipActuel: '000000', nouveauNip: '123456' }), 'permission-denied');
    }
    await rejette(e.appeler('changerNip', { nipActuel: '1234', nouveauNip: '123456' }), 'resource-exhausted');
  });
});
