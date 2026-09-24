// Tests d'intégration des Cloud Functions : émulateurs Auth + Functions +
// Firestore, avec les vraies règles (firestore.rules) appliquées aux lectures
// client. Lancer via : npm run test:functions
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp } from 'firebase/app';
import {
  connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInAnonymously, signInWithEmailAndPassword,
} from 'firebase/auth';
import { connectFunctionsEmulator, getFunctions, httpsCallable } from 'firebase/functions';
import {
  collection, connectFirestoreEmulator, doc, getDoc, getDocs, getFirestore, query, where,
} from 'firebase/firestore';
import { initializeApp as initAdmin } from 'firebase-admin/app';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getFirestore as getAdminDb } from 'firebase-admin/firestore';

const PROJET = 'demo-construction-rules';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

const admin = initAdmin({ projectId: PROJET }, 'admin-tests');
const adminDb = getAdminDb(admin);
const adminAuth = getAdminAuth(admin);

const apps = [];
let compteur = 0;

/** Un « appareil » client isolé (sa propre session Auth). */
function appareil() {
  const app = initializeApp({ projectId: PROJET, apiKey: 'demo-key', appId: 'demo' }, `client-${compteur++}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const fns = getFunctions(app, 'us-central1');
  connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  return { auth, db, appeler: (nom, data) => httpsCallable(fns, nom)(data).then((r) => r.data) };
}

async function employeConnecte(numero, pin) {
  const a = appareil();
  await signInAnonymously(a.auth);
  const profil = await a.appeler('connexionEmploye', { numeroCompagnie: numero, pin });
  return { ...a, profil };
}

async function rejette(promesse, code) {
  await assert.rejects(promesse, (e) => {
    assert.equal(e.code, `functions/${code}`, `code attendu ${code}, reçu ${e.code} (${e.message})`);
    return true;
  });
}

const INSCRIPTION = {
  nomEntreprise: 'Construction Test', nomLegal: 'Construction Test inc.', secteur: 'Entrepreneur général',
  nombreEmployes: 12, telephone: '514-555-0000', nomAdmin: 'Proprio', pinAdmin: '1234',
  emailAdmin: 'Proprio@Exemple.ca',
};

let numero;
let companyId;
let superAdmin;

before(async () => {
  const res = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJET}/databases/(default)/documents`, { method: 'DELETE' });
  assert.ok(res.ok);
  await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${PROJET}/accounts`, { method: 'DELETE' });
});

after(async () => {
  await Promise.all(apps.map((a) => deleteApp(a)));
});

describe('Inscription et approbation', () => {
  test('inscription : refuse un NIP non numérique et un courriel invalide', async () => {
    const a = appareil();
    await signInAnonymously(a.auth);
    await rejette(a.appeler('inscrireCompagnie', { ...INSCRIPTION, pinAdmin: 'abcd' }), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', { ...INSCRIPTION, emailAdmin: 'pas-un-courriel' }), 'invalid-argument');
    await rejette(a.appeler('inscrireCompagnie', { ...INSCRIPTION, nomEntreprise: 'x'.repeat(500) }), 'invalid-argument');
  });

  test('inscription : crée compagnie en attente + propriétaire avec NIP haché', async () => {
    const a = appareil();
    await signInAnonymously(a.auth);
    ({ numero } = await a.appeler('inscrireCompagnie', INSCRIPTION));
    assert.match(numero, /^\d+$/);

    const comp = await adminDb.collection('companies').where('numero', '==', numero).get();
    assert.equal(comp.size, 1);
    companyId = comp.docs[0].id;
    assert.equal(comp.docs[0].data().statut, 'attente');

    const emps = await adminDb.collection('employees').where('companyId', '==', companyId).get();
    assert.equal(emps.size, 1);
    const proprio = emps.docs[0].data();
    assert.equal(proprio.estProprietaire, true);
    assert.equal(proprio.role, 'admin');
    assert.equal(proprio.pin, undefined, 'le NIP ne doit jamais être stocké en clair');
    assert.match(proprio.pinHash, /^[0-9a-f]{64}$/);

    const prive = await adminDb.collection('companies_prive').doc(companyId).get();
    assert.equal(prive.data().emailAdmin, 'proprio@exemple.ca');
  });

  test('connexion refusée tant que la compagnie est en attente', async () => {
    const a = appareil();
    await signInAnonymously(a.auth);
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '1234' }), 'not-found');
  });

  test('super-admin : claim accordé seulement au courriel configuré ET vérifié', async () => {
    // Courriel configuré mais non vérifié → refusé.
    superAdmin = appareil();
    const cred = await createUserWithEmailAndPassword(superAdmin.auth, 'super@exemple.ca', 'motdepasse-solide');
    await rejette(superAdmin.appeler('activerSuperAdmin'), 'permission-denied');

    // Autre compte vérifié → refusé.
    const autre = appareil();
    const credAutre = await createUserWithEmailAndPassword(autre.auth, 'intrus@exemple.ca', 'motdepasse-solide');
    await adminAuth.updateUser(credAutre.user.uid, { emailVerified: true });
    await credAutre.user.getIdToken(true);
    await rejette(autre.appeler('activerSuperAdmin'), 'permission-denied');
    await rejette(autre.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');

    // Compte configuré + vérifié → claim posé.
    await adminAuth.updateUser(cred.user.uid, { emailVerified: true });
    await signInWithEmailAndPassword(superAdmin.auth, 'super@exemple.ca', 'motdepasse-solide');
    assert.deepEqual(await superAdmin.appeler('activerSuperAdmin'), { ok: true });
    const jeton = await superAdmin.auth.currentUser.getIdTokenResult(true);
    assert.equal(jeton.claims.superAdmin, true);
  });

  test('approbation : super-admin OK, une seule fois ; liste des compagnies lisible', async () => {
    await rejette(superAdmin.appeler('approuverCompagnie', { companyId, approuver: 'oui' }), 'invalid-argument');
    assert.deepEqual(await superAdmin.appeler('approuverCompagnie', { companyId, approuver: true }), { ok: true });
    await rejette(superAdmin.appeler('approuverCompagnie', { companyId, approuver: false }), 'failed-precondition');
    const liste = await getDocs(collection(superAdmin.db, 'companies'));
    assert.ok(liste.size >= 1);
  });

  test('un employé ne peut pas approuver de compagnie', async () => {
    const e = await employeConnecte(numero, '1234');
    await rejette(e.appeler('approuverCompagnie', { companyId, approuver: true }), 'permission-denied');
  });
});

describe('Connexion employé', () => {
  test('bon NIP : session créée, profil propriétaire, lecture de sa compagnie', async () => {
    const e = await employeConnecte(numero, '1234');
    assert.equal(e.profil.estProprietaire, true);
    assert.equal(e.profil.role, 'admin');
    assert.equal(e.profil.companyId, companyId);
    const session = await getDoc(doc(e.db, 'sessions', e.auth.currentUser.uid));
    assert.equal(session.data().employeeId, e.profil.id);
    assert.ok((await getDoc(doc(e.db, 'companies', companyId))).exists());
  });

  test('mauvais NIP et numéro inexistant : même erreur générique', async () => {
    const a = appareil();
    await signInAnonymously(a.auth);
    const messages = [];
    for (const essai of [{ numeroCompagnie: numero, pin: '9999' }, { numeroCompagnie: '999999', pin: '1234' }]) {
      await assert.rejects(a.appeler('connexionEmploye', essai), (e) => {
        assert.equal(e.code, 'functions/not-found');
        messages.push(e.message);
        return true;
      });
    }
    assert.equal(messages[0], messages[1], 'les messages ne doivent pas révéler si le numéro existe');
  });

  test('compte courriel : connexion employé refusée', async () => {
    await rejette(superAdmin.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '1234' }), 'failed-precondition');
  });

  test('migration paresseuse : un ancien NIP en clair fonctionne puis est haché', async () => {
    const ref = await adminDb.collection('employees').add({ companyId, nom: 'Ancien', role: 'employe', pin: '4321' });
    const e = await employeConnecte(numero, '4321');
    assert.equal(e.profil.id, ref.id);
    const apres = (await ref.get()).data();
    assert.equal(apres.pin, undefined);
    assert.match(apres.pinHash, /^[0-9a-f]{64}$/);
  });
});

describe('Gestion des employés', () => {
  let proprio;
  let employeId;

  before(async () => { proprio = await employeConnecte(numero, '1234'); });

  test('admin : crée un employé ; NIP en double refusé ; NIP invalide refusé', async () => {
    ({ id: employeId } = await proprio.appeler('enregistrerEmploye', { nom: 'Jean', role: 'employe', pin: '5678' }));
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'Double', role: 'employe', pin: '5678' }), 'already-exists');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'Double', role: 'employe', pin: '4321' }), 'already-exists');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'X', role: 'employe', pin: '12' }), 'invalid-argument');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'X', role: 'patron', pin: '2468' }), 'invalid-argument');
    await rejette(proprio.appeler('enregistrerEmploye', { nom: 'X', role: 'employe' }), 'invalid-argument');
    const cree = (await adminDb.collection('employees').doc(employeId).get()).data();
    assert.equal(cree.estProprietaire, false);
    assert.equal(cree.pin, undefined);
  });

  test('le nouvel employé se connecte ; il ne peut pas gérer les employés', async () => {
    const jean = await employeConnecte(numero, '5678');
    assert.equal(jean.profil.id, employeId);
    await rejette(jean.appeler('enregistrerEmploye', { nom: 'Pirate', role: 'admin', pin: '1111' }), 'permission-denied');
    await rejette(jean.appeler('supprimerEmploye', { employeeId: proprio.profil.id }), 'permission-denied');
    // Les règles l'empêchent de lister les employés.
    await assert.rejects(getDocs(query(collection(jean.db, 'employees'), where('companyId', '==', companyId))));
  });

  test('modification sans NIP : NIP conservé ; le propriétaire reste admin', async () => {
    await proprio.appeler('enregistrerEmploye', { employeeId: employeId, nom: 'Jean Tremblay', role: 'plus' });
    const jean = (await adminDb.collection('employees').doc(employeId).get()).data();
    assert.equal(jean.nom, 'Jean Tremblay');
    assert.equal(jean.role, 'plus');
    await employeConnecte(numero, '5678'); // NIP toujours valide

    await proprio.appeler('enregistrerEmploye', { employeeId: proprio.profil.id, nom: 'Proprio', role: 'employe' });
    const p = (await adminDb.collection('employees').doc(proprio.profil.id).get()).data();
    assert.equal(p.role, 'admin', 'le propriétaire ne peut pas être rétrogradé');
  });

  test('propriétaire : ne peut pas être retiré (ni par un autre admin, ni par lui-même)', async () => {
    const { id: adminId } = await proprio.appeler('enregistrerEmploye', { nom: 'Second admin', role: 'admin', pin: '8642' });
    const second = await employeConnecte(numero, '8642');
    assert.equal(second.profil.id, adminId);
    await rejette(second.appeler('supprimerEmploye', { employeeId: proprio.profil.id }), 'failed-precondition');
    await rejette(proprio.appeler('supprimerEmploye', { employeeId: proprio.profil.id }), 'failed-precondition');
  });

  test('retrait d\'un employé : fiche et sessions supprimées, accès coupé', async () => {
    const jean = await employeConnecte(numero, '5678');
    assert.ok((await getDoc(doc(jean.db, 'companies', companyId))).exists());
    await proprio.appeler('supprimerEmploye', { employeeId: employeId });
    assert.equal((await adminDb.collection('employees').doc(employeId).get()).exists, false);
    const sessions = await adminDb.collection('sessions').where('employeeId', '==', employeId).get();
    assert.equal(sessions.size, 0);
    await assert.rejects(getDoc(doc(jean.db, 'companies', companyId)));
  });

  test('isolation : un admin d\'une autre compagnie ne touche pas à ces employés', async () => {
    const autre = appareil();
    await signInAnonymously(autre.auth);
    const { numero: numeroB } = await autre.appeler('inscrireCompagnie', { ...INSCRIPTION, nomEntreprise: 'Bêta', pinAdmin: '1357' });
    const compB = await adminDb.collection('companies').where('numero', '==', numeroB).get();
    await superAdmin.appeler('approuverCompagnie', { companyId: compB.docs[0].id, approuver: true });
    const adminB = await employeConnecte(numeroB, '1357');

    await rejette(adminB.appeler('enregistrerEmploye', { employeeId: proprio.profil.id, nom: 'Piraté', role: 'employe' }), 'not-found');
    const ciblable = await adminDb.collection('employees').where('companyId', '==', companyId).where('role', '==', 'plus').limit(1).get();
    const cible = ciblable.empty ? proprio.profil.id : ciblable.docs[0].id;
    await rejette(adminB.appeler('supprimerEmploye', { employeeId: cible }), 'not-found');
    await assert.rejects(getDocs(query(collection(adminB.db, 'employees'), where('companyId', '==', companyId))));
    await assert.rejects(getDoc(doc(adminB.db, 'companies', companyId)));
  });
});

describe('Migration et limites', () => {
  test('migrerNips : super-admin seulement ; hache les NIP restants', async () => {
    const ref = await adminDb.collection('employees').add({ companyId, nom: 'Reste', role: 'employe', pin: '7777' });
    const e = await employeConnecte(numero, '1234');
    await rejette(e.appeler('migrerNips'), 'permission-denied');
    const { migres } = await superAdmin.appeler('migrerNips');
    assert.ok(migres >= 1);
    const apres = (await ref.get()).data();
    assert.equal(apres.pin, undefined);
    await employeConnecte(numero, '7777');
  });

  test('force brute : blocage après 10 échecs par IP', async () => {
    await Promise.all((await adminDb.collection('limites_connexion').get()).docs.map((d) => d.ref.delete()));
    const a = appareil();
    await signInAnonymously(a.auth);
    for (let i = 0; i < 10; i++) {
      await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: `00${i}0` }), 'not-found');
    }
    await rejette(a.appeler('connexionEmploye', { numeroCompagnie: numero, pin: '1234' }), 'resource-exhausted');
  });
});
