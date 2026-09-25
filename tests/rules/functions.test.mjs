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
  collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, query, where,
} from 'firebase/firestore';
import { initializeApp as initAdmin } from 'firebase-admin/app';
import { getFirestore as getAdminDb } from 'firebase-admin/firestore';

const PROJET = 'demo-construction-rules';
const REGION = 'northamerica-northeast1';
const PEPPER_EMULATEUR = 'cle-de-test-emulateur-seulement'; // functions/.secret.local
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const adminDb = getAdminDb(initAdmin({ projectId: PROJET }, 'admin-tests'));
const hacher = (companyId, pin) => createHmac('sha256', PEPPER_EMULATEUR).update(`${companyId}:${pin}`).digest('hex');

const apps = [];
let compteur = 0;

/** Un « appareil » client isolé (sa propre session Auth anonyme). */
async function appareil() {
  const app = initializeApp({ projectId: PROJET, apiKey: 'demo-key', appId: 'demo' }, `client-${compteur++}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const fns = getFunctions(app, REGION);
  connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  await signInAnonymously(auth);
  return { auth, db, appeler: (nom, data) => httpsCallable(fns, nom)(data).then((r) => r.data) };
}

async function connecter(numero, courriel, pin) {
  const a = await appareil();
  const profil = await a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel, pin });
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

async function nipRecu(courriel, sujet = 'accès') {
  const msg = await dernierCourriel(courriel, sujet);
  assert.ok(msg, `courriel « ${sujet} » attendu pour ${courriel}`);
  return extraire(msg.texte, 'NIP');
}

const viderLimites = async () =>
  Promise.all((await adminDb.collection('limites_connexion').get()).docs.map((d) => d.ref.delete()));

const inscription = (over = {}) => ({
  nomEntreprise: 'Construction Test', nomLegal: 'Construction Test inc.', secteur: 'Entrepreneur général',
  nombreEmployes: 12, telephone: '514-555-0000', nomAdmin: 'Proprio Compagnie', pinAdmin: '123456',
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
describe('Proprio de l\'app, inscription et approbation', () => {
  test('mise en place : compagnie du Proprio (approuvée, config/proprio_app posé à la console)', async () => {
    const a = await appareil();
    ({ numero: numeroS } = await a.appeler('inscrireCompagnie',
      inscription({ nomEntreprise: 'Boréal', nomAdmin: 'Le Proprio', emailAdmin: 'proprio-app@exemple.ca', pinAdmin: '246810' })));
    const comp = (await adminDb.collection('companies').where('numero', '==', numeroS).get()).docs[0];
    await comp.ref.update({ statut: 'approuvee' });
    const fiche = (await adminDb.collection('employees').where('companyId', '==', comp.id).get()).docs[0];
    await adminDb.collection('config').doc('proprio_app').set({ employeeId: fiche.id });
  });

  test('inscription : validations (NIP de 6 à 8 chiffres, courriel, longueur)', async () => {
    const a = await appareil();
    await rejette(a.appeler('inscrireCompagnie', inscription({ pinAdmin: '1234' })), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', inscription({ pinAdmin: 'abcdef' })), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', inscription({ emailAdmin: 'pas-un-courriel' })), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', inscription({ nomEntreprise: 'x'.repeat(500) })), 'invalid-argument');
  });

  test('inscription : compagnie en attente, super-admin avec NIP haché, courriel reçu', async () => {
    const a = await appareil();
    ({ numero } = await a.appeler('inscrireCompagnie', inscription()));
    const comp = (await adminDb.collection('companies').where('numero', '==', numero).get()).docs[0];
    companyId = comp.id;
    assert.equal(comp.data().statut, 'attente');

    const emps = await adminDb.collection('employees').where('companyId', '==', companyId).get();
    assert.equal(emps.size, 1);
    const p = emps.docs[0].data();
    proprioId = emps.docs[0].id;
    assert.equal(p.estProprietaire, true);
    assert.equal(p.role, 'admin');
    assert.equal(p.courriel, 'proprio@exemple.ca');
    assert.equal(p.pin, undefined, 'le NIP ne doit jamais être stocké en clair');
    assert.equal(p.pinHash, hacher(companyId, '123456'));
    assert.ok(await dernierCourriel('proprio@exemple.ca', numero), 'courriel de confirmation attendu');
  });

  test('connexion refusée tant que la compagnie est en attente', async () => {
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye',
      { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '123456' }), 'not-found');
  });

  test('un champ superAdmin/proprioApp sur une autre fiche ne donne aucun pouvoir de Proprio', async () => {
    const comp = (await adminDb.collection('companies').where('numero', '==', numeroS).get()).docs[0];
    await adminDb.collection('employees').add({
      companyId: comp.id, nom: 'Usurpateur', role: 'admin', courriel: 'usurpateur@exemple.ca',
      superAdmin: true, proprioApp: true, pinHash: hacher(comp.id, '112233'),
    });
    const u = await connecter(numeroS, 'usurpateur@exemple.ca', '112233');
    assert.equal(u.profil.estProprioApp, false);
    await rejette(u.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');
    await assert.rejects(getDocs(collection(u.db, 'companies')));
  });

  test('Proprio : approuve une seule fois ; le super-admin de la compagnie est avisé', async () => {
    const s = await connecter(numeroS, 'proprio-app@exemple.ca', '246810');
    assert.equal(s.profil.estProprioApp, true);
    assert.ok((await getDocs(collection(s.db, 'companies'))).size >= 2);
    await rejette(s.appeler('approuverCompagnie', { companyId, approuver: 'oui' }), 'invalid-argument');
    assert.deepEqual(await s.appeler('approuverCompagnie', { companyId, approuver: true }), { ok: true });
    await rejette(s.appeler('approuverCompagnie', { companyId, approuver: false }), 'failed-precondition');
    assert.ok(await dernierCourriel('proprio@exemple.ca', 'approuvée'));
  });

  test('un super-admin de compagnie n\'est pas le Proprio de l\'app', async () => {
    const p = await connecter(numero, 'proprio@exemple.ca', '123456');
    assert.equal(p.profil.estProprioApp, false);
    await rejette(p.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');
  });
});

// =============================================================================
describe('Connexion employé', () => {
  test('courriel + NIP : session créée, profil super-admin', async () => {
    const e = await connecter(numero, 'PROPRIO@exemple.ca', '123456');
    assert.equal(e.profil.estProprietaire, true);
    assert.equal(e.profil.role, 'admin');
    assert.equal(e.profil.courriel, 'proprio@exemple.ca');
    const session = await getDoc(doc(e.db, 'sessions', e.auth.currentUser.uid));
    assert.equal(session.data().employeeId, e.profil.id);
  });

  test('courriel obligatoire : le NIP seul est refusé', async () => {
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '123456' }), 'invalid-argument');
  });

  test('erreurs : même message générique (numéro, courriel ou NIP faux)', async () => {
    const a = await appareil();
    const messages = [];
    for (const essai of [
      { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '999999' },
      { numeroCompagnie: numero, courriel: 'inconnu@exemple.ca', pin: '123456' },
      { numeroCompagnie: '999999', courriel: 'proprio@exemple.ca', pin: '123456' },
      { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '1234' },
    ]) {
      await assert.rejects(a.appeler('connexionEmploye', essai), (e) => {
        assert.equal(e.code, 'functions/not-found');
        messages.push(e.message);
        return true;
      });
    }
    assert.equal(new Set(messages).size, 1, 'les messages ne doivent pas révéler ce qui existe');
  });
});

// =============================================================================
describe('Création d\'employés : NIP aléatoire envoyé par courriel', () => {
  let superAdmin;
  before(async () => { superAdmin = await connecter(numero, 'proprio@exemple.ca', '123456'); });

  test('création : nom + courriel + rôle → NIP de 6 chiffres envoyé à l\'employé', async () => {
    const r = await superAdmin.appeler('enregistrerEmploye', { nom: 'Jean Tremblay', courriel: 'Jean@Exemple.ca', role: 'employe' });
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

  test('refus : courriel en double, courriel manquant, rôle invalide, employé non admin', async () => {
    await rejette(superAdmin.appeler('enregistrerEmploye', { nom: 'Double', courriel: 'jean@exemple.ca', role: 'employe' }), 'already-exists');
    await rejette(superAdmin.appeler('enregistrerEmploye', { nom: 'Sans', role: 'employe' }), 'invalid-argument');
    await rejette(superAdmin.appeler('enregistrerEmploye', { nom: 'X', courriel: 'x@exemple.ca', role: 'patron' }), 'invalid-argument');
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    await rejette(jean.appeler('enregistrerEmploye', { nom: 'Pirate', courriel: 'p@exemple.ca', role: 'employe' }), 'permission-denied');
    await rejette(jean.appeler('supprimerEmploye', { employeeId: proprioId }), 'permission-denied');
    await assert.rejects(getDocs(query(collection(jean.db, 'employees'), where('companyId', '==', companyId))));
  });

  test('modification : NIP conservé ; le super-admin reste admin', async () => {
    await superAdmin.appeler('enregistrerEmploye', { employeeId: jeanId, nom: 'Jean Tremblay', courriel: 'jean@exemple.ca', role: 'plus' });
    assert.equal((await adminDb.collection('employees').doc(jeanId).get()).data().role, 'plus');
    await connecter(numero, 'jean@exemple.ca', nipJean);
    await superAdmin.appeler('enregistrerEmploye', { employeeId: proprioId, nom: 'Proprio Compagnie', courriel: 'proprio@exemple.ca', role: 'admin' });
    assert.equal((await adminDb.collection('employees').doc(proprioId).get()).data().role, 'admin');
  });

  test('nouveau NIP envoyé par l\'admin : l\'ancien ne fonctionne plus, sessions coupées', async () => {
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    await superAdmin.appeler('enregistrerEmploye',
      { employeeId: jeanId, nom: 'Jean Tremblay', courriel: 'jean@exemple.ca', role: 'plus', envoyerNouveauNip: true });
    const nouveau = await nipRecu('jean@exemple.ca', 'nouveau NIP');
    assert.notEqual(nouveau, nipJean);
    const a = await appareil();
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, courriel: 'jean@exemple.ca', pin: nipJean }), 'not-found');
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)), 'ancienne session coupée');
    nipJean = nouveau;
    await connecter(numero, 'jean@exemple.ca', nipJean);
  });
});

// =============================================================================
describe('Admins : seul le super-admin de la compagnie les gère', () => {
  let superAdmin; let admin; let adminId; let admin2Id; let employeId;

  before(async () => {
    superAdmin = await connecter(numero, 'proprio@exemple.ca', '123456');
  });

  test('le super-admin nomme des admins', async () => {
    ({ id: adminId } = await superAdmin.appeler('enregistrerEmploye', { nom: 'Bureau Un', courriel: 'bureau1@exemple.ca', role: 'admin' }));
    ({ id: admin2Id } = await superAdmin.appeler('enregistrerEmploye', { nom: 'Bureau Deux', courriel: 'bureau2@exemple.ca', role: 'admin' }));
    admin = await connecter(numero, 'bureau1@exemple.ca', await nipRecu('bureau1@exemple.ca'));
    assert.equal(admin.profil.role, 'admin');
    assert.equal(admin.profil.estProprietaire, false);
  });

  test('un admin gère les employés et contremaîtres', async () => {
    ({ id: employeId } = await admin.appeler('enregistrerEmploye', { nom: 'Paul', courriel: 'paul@exemple.ca', role: 'employe' }));
    await admin.appeler('enregistrerEmploye', { employeeId: employeId, nom: 'Paul Roy', courriel: 'paul@exemple.ca', role: 'plus' });
    assert.equal((await adminDb.collection('employees').doc(employeId).get()).data().role, 'plus');
  });

  test('un admin ne peut pas nommer un admin (création ou promotion)', async () => {
    await rejette(admin.appeler('enregistrerEmploye', { nom: 'Intrus', courriel: 'intrus@exemple.ca', role: 'admin' }), 'permission-denied');
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: employeId, nom: 'Paul Roy', courriel: 'paul@exemple.ca', role: 'admin' }), 'permission-denied');
    assert.equal((await adminDb.collection('employees').doc(employeId).get()).data().role, 'plus');
  });

  test('un admin ne peut ni modifier, ni rétrograder, ni retirer un autre admin', async () => {
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: admin2Id, nom: 'Renommé', courriel: 'bureau2@exemple.ca', role: 'admin' }), 'permission-denied');
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: admin2Id, nom: 'Bureau Deux', courriel: 'bureau2@exemple.ca', role: 'employe' }), 'permission-denied');
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: admin2Id, nom: 'Bureau Deux', courriel: 'bureau2@exemple.ca', role: 'admin', envoyerNouveauNip: true }), 'permission-denied');
    await rejette(admin.appeler('supprimerEmploye', { employeeId: admin2Id }), 'permission-denied');
    assert.ok((await adminDb.collection('employees').doc(admin2Id).get()).exists);
  });

  test('un admin modifie sa propre fiche, mais pas son rôle', async () => {
    await admin.appeler('enregistrerEmploye', { employeeId: adminId, nom: 'Bureau Un (Marie)', courriel: 'bureau1@exemple.ca', role: 'admin' });
    assert.equal((await adminDb.collection('employees').doc(adminId).get()).data().nom, 'Bureau Un (Marie)');
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: adminId, nom: 'Bureau Un', courriel: 'bureau1@exemple.ca', role: 'employe' }), 'permission-denied');
  });

  test('un admin ne peut pas toucher au super-admin', async () => {
    await rejette(admin.appeler('enregistrerEmploye',
      { employeeId: proprioId, nom: 'Piraté', courriel: 'proprio@exemple.ca', role: 'admin' }), 'permission-denied');
    await rejette(admin.appeler('supprimerEmploye', { employeeId: proprioId }), 'failed-precondition');
  });

  test('un admin retire un employé', async () => {
    assert.deepEqual(await admin.appeler('supprimerEmploye', { employeeId: employeId }), { ok: true });
  });

  test('le super-admin rétrograde et retire des admins ; il ne peut pas se retirer', async () => {
    await superAdmin.appeler('enregistrerEmploye', { employeeId: admin2Id, nom: 'Bureau Deux', courriel: 'bureau2@exemple.ca', role: 'plus' });
    assert.equal((await adminDb.collection('employees').doc(admin2Id).get()).data().role, 'plus');
    assert.deepEqual(await superAdmin.appeler('supprimerEmploye', { employeeId: adminId }), { ok: true });
    await assert.rejects(getDoc(doc(admin.db, 'companies', companyId)), 'admin retiré : accès coupé');
    await rejette(superAdmin.appeler('supprimerEmploye', { employeeId: proprioId }), 'failed-precondition');
  });
});

// =============================================================================
describe('NIP : changement par l\'employé et récupération', () => {
  test('changerNip : NIP actuel exigé, 6 chiffres minimum, autres appareils déconnectés', async () => {
    const autreAppareil = await connecter(numero, 'jean@exemple.ca', nipJean);
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    await rejette(jean.appeler('changerNip', { nipActuel: '000000', nouveauNip: '135790' }), 'permission-denied');
    await rejette(jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '1357' }), 'invalid-argument');
    assert.deepEqual(await jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '135790' }), { ok: true });
    nipJean = '135790';
    assert.ok((await getDoc(doc(jean.db, 'companies', companyId))).exists(), 'appareil courant conservé');
    await assert.rejects(getDoc(doc(autreAppareil.db, 'companies', companyId)), 'autre appareil déconnecté');
    assert.ok(await dernierCourriel('jean@exemple.ca', 'modifié'));
    await connecter(numero, 'jean@exemple.ca', '135790');
  });

  test('changerNip : un NIP identique à celui d\'un collègue est accepté (aucune fuite)', async () => {
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    assert.deepEqual(await jean.appeler('changerNip', { nipActuel: nipJean, nouveauNip: '123456' }), { ok: true });
    nipJean = '123456';
    const j = await connecter(numero, 'jean@exemple.ca', '123456');
    assert.equal(j.profil.id, jeanId);
    const p = await connecter(numero, 'proprio@exemple.ca', '123456');
    assert.equal(p.profil.id, proprioId);
  });

  test('NIP oublié : code par courriel, usage unique, sessions coupées', async () => {
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    const a = await appareil();
    assert.deepEqual(await a.appeler('demanderReinitialisationNip', { numeroCompagnie: numero, email: 'jean@exemple.ca' }), { ok: true });
    const code = extraire((await dernierCourriel('jean@exemple.ca', 'réinitialisation')).texte, 'Votre code de réinitialisation');
    assert.match(code, /^\d{6}$/);
    const essai = (c, pin = '864209') =>
      a.appeler('validerReinitialisationNip', { numeroCompagnie: numero, email: 'jean@exemple.ca', code: c, nouveauPin: pin });
    await rejette(essai(code === '000000' ? '000001' : '000000'), 'permission-denied');
    await rejette(essai(code, '12'), 'invalid-argument');
    assert.deepEqual(await essai(code), { ok: true });
    await rejette(essai(code), 'permission-denied');
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)), 'sessions coupées');
    nipJean = '864209';
    await connecter(numero, 'jean@exemple.ca', nipJean);
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
describe('Retrait et isolation', () => {
  test('retrait d\'un employé : fiche et sessions supprimées, accès coupé', async () => {
    const superAdmin = await connecter(numero, 'proprio@exemple.ca', '123456');
    const jean = await connecter(numero, 'jean@exemple.ca', nipJean);
    await superAdmin.appeler('supprimerEmploye', { employeeId: jeanId });
    assert.equal((await adminDb.collection('employees').doc(jeanId).get()).exists, false);
    assert.equal((await adminDb.collection('sessions').where('employeeId', '==', jeanId).get()).size, 0);
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)));
  });

  test('isolation : le super-admin d\'une autre compagnie ne touche pas à ces employés', async () => {
    const a = await appareil();
    const { numero: numeroB } = await a.appeler('inscrireCompagnie',
      inscription({ nomEntreprise: 'Bêta', emailAdmin: 'b@exemple.ca', pinAdmin: '135791' }));
    const compB = (await adminDb.collection('companies').where('numero', '==', numeroB).get()).docs[0];
    await compB.ref.update({ statut: 'approuvee' });
    const adminB = await connecter(numeroB, 'b@exemple.ca', '135791');

    await rejette(adminB.appeler('enregistrerEmploye',
      { employeeId: proprioId, nom: 'Piraté', courriel: 'p@exemple.ca', role: 'employe' }), 'not-found');
    await rejette(adminB.appeler('supprimerEmploye', { employeeId: proprioId }), 'not-found');
    await assert.rejects(getDocs(query(collection(adminB.db, 'employees'), where('companyId', '==', companyId))));
    await assert.rejects(getDoc(doc(adminB.db, 'companies', companyId)));
  });
});

// =============================================================================
describe('Limites anti-force brute', () => {
  test('connexion : blocage après 10 échecs par IP', async () => {
    const a = await appareil();
    for (let i = 0; i < 10; i++) {
      await rejette(a.appeler('connexionEmploye',
        { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: `90000${i}` }), 'not-found');
    }
    await rejette(a.appeler('connexionEmploye',
      { numeroCompagnie: numero, courriel: 'proprio@exemple.ca', pin: '123456' }), 'resource-exhausted');
  });

  test('changerNip : 5 tentatives par jour au maximum', async () => {
    const e = await connecter(numero, 'proprio@exemple.ca', '123456');
    for (let i = 0; i < 5; i++) {
      await rejette(e.appeler('changerNip', { nipActuel: '000000', nouveauNip: '654321' }), 'permission-denied');
    }
    await rejette(e.appeler('changerNip', { nipActuel: '123456', nouveauNip: '654321' }), 'resource-exhausted');
  });
});
