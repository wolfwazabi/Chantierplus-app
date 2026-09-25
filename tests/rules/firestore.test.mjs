import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, deleteField, doc, getDoc, getDocs, orderBy, query,
  serverTimestamp, setDoc, updateDoc, where,
} from 'firebase/firestore';
import {
  creerEnvironnement, employe, individu, LUNDI, LUNDI_PASSE, LUNDI_PROCHAIN, semer,
} from './helpers.mjs';

let env;
before(async () => { env = await creerEnvironnement(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await semer(env); });

const db = (ctx) => ctx.firestore();
const ctxDe = (uid) => db(employe(env, uid));

// =============================================================================
describe('Bug semaine_liste_screen : liste des feuilles de temps', () => {
  test('admin A : requête filtrée par companyId + orderBy lundiDate → OK', async () => {
    const q = query(collection(ctxDe('uid-adminA'), 'feuilles_temps'),
      where('companyId', '==', 'A'), orderBy('lundiDate', 'desc'));
    await assertSucceeds(getDocs(q));
  });

  test('admin A : requête SANS filtre companyId (ancien code) → refusée', async () => {
    await assertFails(getDocs(query(collection(ctxDe('uid-adminA'), 'feuilles_temps'), orderBy('lundiDate', 'desc'))));
  });

  test('admin A : requête sur companyId B → refusée', async () => {
    await assertFails(getDocs(query(collection(ctxDe('uid-adminA'), 'feuilles_temps'), where('companyId', '==', 'B'))));
  });

  test('admin A : détail de semaine et historique employé → OK', async () => {
    const col = collection(ctxDe('uid-adminA'), 'feuilles_temps');
    await assertSucceeds(getDocs(query(col, where('companyId', '==', 'A'), where('lundiDate', '==', LUNDI))));
    await assertSucceeds(getDocs(query(col, where('companyId', '==', 'A'), where('employeeId', '==', 'empA'))));
  });

  test('employé et contremaître : liste de la compagnie → refusée', async () => {
    for (const uid of ['uid-empA', 'uid-plusA']) {
      await assertFails(getDocs(query(collection(ctxDe(uid), 'feuilles_temps'), where('companyId', '==', 'A'))));
    }
  });
});

// =============================================================================
describe('Sessions', () => {
  test('le client ne peut pas créer sa session (usurpation)', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-nouveau'), 'sessions/uid-nouveau'), { employeeId: 'adminA', companyId: 'A' }));
  });

  test('le client ne peut pas changer d\'identité ni se donner la méthode courriel', async () => {
    const ref = doc(ctxDe('uid-empA'), 'sessions/uid-empA');
    await assertFails(updateDoc(ref, { employeeId: 'adminA' }));
    await assertFails(setDoc(ref, { employeeId: 'empA', companyId: 'B' }));
    await assertFails(setDoc(ref, { employeeId: 'empA', companyId: 'A', methode: 'courriel' }));
  });

  test('[anciennes versions] réécriture identique de la session → OK', async () => {
    await assertSucceeds(setDoc(doc(ctxDe('uid-empA'), 'sessions/uid-empA'), { employeeId: 'empA', companyId: 'A' }));
  });

  test('lecture de sa propre session → OK ; celle d\'un autre ou la liste → refusée', async () => {
    await assertSucceeds(getDoc(doc(ctxDe('uid-empA'), 'sessions/uid-empA')));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'sessions/uid-adminA')));
    await assertFails(getDocs(collection(ctxDe('uid-adminA'), 'sessions')));
  });

  test('suppression de sa propre session (déconnexion) → OK', async () => {
    await assertSucceeds(deleteDoc(doc(ctxDe('uid-empA'), 'sessions/uid-empA')));
  });

  test('sessions invalides (forgée, employé supprimé, compagnie en attente) → aucun accès', async () => {
    for (const [uid, cid] of [['uid-forge', 'B'], ['uid-forge', 'A'], ['uid-supprime', 'A'], ['uid-adminP', 'P']]) {
      await assertFails(getDocs(query(collection(ctxDe(uid), 'chantiers'), where('companyId', '==', cid))));
    }
    await assertFails(getDoc(doc(ctxDe('uid-adminP'), 'companies/P')));
  });

  test('compte courriel (particulier) avec une session → ignorée', async () => {
    await env.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), 'sessions/uid-ind'), { employeeId: 'adminA', companyId: 'A' }));
    const d = db(individu(env, 'uid-ind'));
    await assertFails(getDocs(query(collection(d, 'chantiers'), where('companyId', '==', 'A'))));
  });

  test('non authentifié → aucun accès', async () => {
    const d = db(env.unauthenticatedContext());
    await assertFails(getDocs(query(collection(d, 'chantiers'), where('companyId', '==', 'A'))));
  });
});

// =============================================================================
describe('Compagnies et Proprio', () => {
  test('membre : lit sa compagnie, pas celle d\'une autre ; ne liste pas', async () => {
    await assertSucceeds(getDoc(doc(ctxDe('uid-empA'), 'companies/A')));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'companies/B')));
    await assertFails(getDocs(collection(ctxDe('uid-adminA'), 'companies')));
  });

  test('Proprio connecté par courriel : liste et lit toutes les compagnies', async () => {
    const d = ctxDe('uid-superA');
    await assertSucceeds(getDocs(query(collection(d, 'companies'), orderBy('dateCreation', 'desc'))));
    await assertSucceeds(getDoc(doc(d, 'companies/P')));
  });

  test('Proprio connecté par NIP seul : aucun pouvoir Proprio', async () => {
    await assertFails(getDocs(collection(ctxDe('uid-superA-nip'), 'companies')));
    await assertFails(getDoc(doc(ctxDe('uid-superA-nip'), 'companies/B')));
  });

  test('un seul Proprio : le champ superAdmin sur une fiche ou une session ne donne rien', async () => {
    await assertFails(getDocs(collection(ctxDe('uid-usurpateur'), 'companies')));
    await assertFails(getDoc(doc(ctxDe('uid-usurpateur'), 'companies/B')));
  });

  test('config/proprio_app : ni lisible ni modifiable depuis l\'app, même par le Proprio', async () => {
    for (const uid of ['uid-superA', 'uid-adminA', 'uid-usurpateur']) {
      await assertFails(getDoc(doc(ctxDe(uid), 'config/proprio_app')));
      await assertFails(setDoc(doc(ctxDe(uid), 'config/proprio_app'), { employeeId: 'usurpateur' }));
    }
  });

  test('Proprio : ne voit pas les données internes des autres compagnies', async () => {
    const d = ctxDe('uid-superA');
    await assertFails(getDocs(query(collection(d, 'chantiers'), where('companyId', '==', 'B'))));
    await assertFails(getDocs(query(collection(d, 'employees'), where('companyId', '==', 'B'))));
    await assertFails(getDocs(query(collection(d, 'feuilles_temps'), where('companyId', '==', 'B'))));
  });

  test('personne ne modifie une compagnie côté client', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-adminP'), 'companies/P'), { statut: 'approuvee' }));
    await assertFails(updateDoc(doc(ctxDe('uid-superA'), 'companies/P'), { statut: 'approuvee' }));
  });
});

// =============================================================================
describe('Employés', () => {
  test('employé : lit sa propre fiche, pas celle des autres, ne liste pas', async () => {
    await assertSucceeds(getDoc(doc(ctxDe('uid-empA'), 'employees/empA')));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'employees/adminA')));
    await assertFails(getDocs(query(collection(ctxDe('uid-empA'), 'employees'), where('companyId', '==', 'A'))));
  });

  test('admin A : liste les employés de A, pas ceux de B', async () => {
    const d = ctxDe('uid-adminA');
    await assertSucceeds(getDocs(query(collection(d, 'employees'), where('companyId', '==', 'A'))));
    await assertFails(getDocs(query(collection(d, 'employees'), where('companyId', '==', 'B'))));
    await assertFails(getDoc(doc(d, 'employees/adminB')));
  });

  test('[anciennes versions] admin : crée un employé avec NIP en clair → OK', async () => {
    await assertSucceeds(addDoc(collection(ctxDe('uid-adminA'), 'employees'),
      { companyId: 'A', nom: 'Nouveau', pin: '4321', role: 'employe', estProprietaire: false }));
  });

  test('[anciennes versions] création refusée : non-admin, autre compagnie, propriétaire, Proprio, courriel, NIP invalide', async () => {
    const ok = { companyId: 'A', nom: 'N', pin: '4321', role: 'employe', estProprietaire: false };
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'employees'), ok));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, companyId: 'B' }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, estProprietaire: true }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, superAdmin: true }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'employees/empA'), { superAdmin: true }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, courriel: 'x@x.ca' }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, pin: '12' }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, pinHash: 'h' }));
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'employees'), { ...ok, role: 'patron' }));
  });

  test('[anciennes versions] admin : modifie nom/NIP/rôle → OK', async () => {
    await assertSucceeds(updateDoc(doc(ctxDe('uid-adminA'), 'employees/empA'), { nom: 'Emp A2', pin: '5555', role: 'plus' }));
  });

  test('[anciennes versions] modification refusée : propriétaire rétrogradé, Proprio, champs protégés', async () => {
    const d = ctxDe('uid-adminA');
    await assertFails(updateDoc(doc(d, 'employees/adminA'), { nom: 'Admin A', pin: '1111', role: 'employe' }));
    await assertFails(updateDoc(doc(d, 'employees/superA'), { nom: 'Super A', pin: '1111', role: 'employe' }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { superAdmin: true }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { estProprietaire: true }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { companyId: 'B' }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { courriel: 'pirate@x.ca' }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { pinHash: 'autre' }));
    await assertFails(updateDoc(doc(ctxDe('uid-empA'), 'employees/empA'), { role: 'admin' }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminB'), 'employees/empA'), { nom: 'Piraté' }));
  });

  test('[anciennes versions] suppression : employé OK ; propriétaire, Proprio, soi-même, autre compagnie refusés', async () => {
    const d = ctxDe('uid-adminA');
    await assertFails(deleteDoc(doc(d, 'employees/adminA')));
    await assertFails(deleteDoc(doc(d, 'employees/superA')));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'employees/empA')));
    await assertFails(deleteDoc(doc(ctxDe('uid-plusA'), 'employees/empA')));
    await assertSucceeds(deleteDoc(doc(d, 'employees/empA')));
  });

  test('un admin non propriétaire ne peut pas se supprimer lui-même', async () => {
    await assertFails(deleteDoc(doc(ctxDe('uid-superA'), 'employees/superA')));
  });
});

// =============================================================================
describe('Chantiers', () => {
  test('tous les membres lisent les chantiers de leur compagnie (feuille de temps)', async () => {
    await assertSucceeds(getDocs(query(collection(ctxDe('uid-empA'), 'chantiers'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'chantiers/chB')));
  });

  test('seul l\'admin crée, modifie, supprime', async () => {
    const nouveau = { companyId: 'A', nom: 'Nouveau', adresse: '2 rue' };
    await assertFails(addDoc(collection(ctxDe('uid-empA'), 'chantiers'), nouveau));
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'chantiers'), nouveau));
    const d = ctxDe('uid-adminA');
    await assertSucceeds(addDoc(collection(d, 'chantiers'), nouveau));
    await assertFails(addDoc(collection(d, 'chantiers'), { ...nouveau, companyId: 'B' }));
    await assertFails(addDoc(collection(d, 'chantiers'), { ...nouveau, x: 1 }));
    await assertFails(addDoc(collection(d, 'chantiers'), { ...nouveau, nom: '' }));
    await assertSucceeds(updateDoc(doc(d, 'chantiers/chA'), { nom: 'Renommé', adresse: '3 rue' }));
    await assertFails(updateDoc(doc(d, 'chantiers/chA'), { companyId: 'B' }));
    await assertFails(updateDoc(doc(d, 'chantiers/chB'), { nom: 'Piraté' }));
    await assertFails(deleteDoc(doc(d, 'chantiers/chB')));
    await assertSucceeds(deleteDoc(doc(d, 'chantiers/chA')));
  });
});

// =============================================================================
describe('Photos (admin et contremaître seulement)', () => {
  const photo = (over = {}) => ({
    companyId: 'A', chantierId: 'chA',
    url: 'https://firebasestorage.googleapis.com/v0/b/x/o/p.jpg',
    cheminStorage: 'chantiers/A/chA/photos/123_p.jpg',
    dateAjout: serverTimestamp(),
    ...over,
  });

  test('contremaître et admin : lisent, ajoutent et suppriment', async () => {
    for (const uid of ['uid-plusA', 'uid-adminA']) {
      await assertSucceeds(getDocs(query(collection(ctxDe(uid), 'chantier_photos'),
        where('companyId', '==', 'A'), where('chantierId', '==', 'chA'))));
      await assertSucceeds(addDoc(collection(ctxDe(uid), 'chantier_photos'), photo()));
    }
    await assertSucceeds(deleteDoc(doc(ctxDe('uid-plusA'), 'chantier_photos/pA')));
  });

  test('employé : ne voit ni ne gère les photos', async () => {
    const d = ctxDe('uid-empA');
    await assertFails(getDocs(query(collection(d, 'chantier_photos'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(d, 'chantier_photos/pA')));
    await assertFails(addDoc(collection(d, 'chantier_photos'), photo()));
    await assertFails(deleteDoc(doc(d, 'chantier_photos/pA')));
  });

  test('refusé : chantier d\'une autre compagnie, chemin incohérent, URL externe, date client', async () => {
    const col = collection(ctxDe('uid-plusA'), 'chantier_photos');
    await assertFails(addDoc(col, photo({ chantierId: 'chB', cheminStorage: 'chantiers/A/chB/photos/p.jpg' })));
    await assertFails(addDoc(col, photo({ cheminStorage: 'chantiers/B/chB/photos/p.jpg' })));
    await assertFails(addDoc(col, photo({ url: 'https://evil.example.com/p.jpg' })));
    await assertFails(addDoc(col, photo({ dateAjout: new Date('2020-01-01') })));
    await assertFails(addDoc(col, photo({ companyId: 'B', chantierId: 'chB', cheminStorage: 'chantiers/B/chB/photos/p.jpg' })));
  });

  test('autre compagnie : ni lecture ni suppression', async () => {
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'chantier_photos/pA')));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'chantier_photos/pA')));
  });
});

// =============================================================================
describe('Travaux / matériel (admin et contremaître seulement)', () => {
  const entree = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', texte: 'Tâche', complete: false, dateAjout: serverTimestamp(), ...over,
  });

  test('contremaître : crée (avec quantité et photo), complète, édite, supprime', async () => {
    const d = ctxDe('uid-plusA');
    await assertSucceeds(addDoc(collection(d, 'chantier_travaux'), entree()));
    await assertSucceeds(addDoc(collection(d, 'chantier_materiel'), entree({
      quantite: '12 feuilles', photoUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/m.jpg',
    })));
    const ref = doc(d, 'chantier_travaux/tA');
    await assertSucceeds(updateDoc(ref, { complete: true, dateComplete: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { texte: 'Coffrage fini' }));
    await assertSucceeds(updateDoc(ref, { complete: false, dateComplete: deleteField() }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('employé : ni lecture, ni création, ni modification', async () => {
    const d = ctxDe('uid-empA');
    await assertFails(getDocs(query(collection(d, 'chantier_travaux'), where('companyId', '==', 'A'))));
    await assertFails(getDocs(query(collection(d, 'chantier_materiel'), where('companyId', '==', 'A'))));
    await assertFails(addDoc(collection(d, 'chantier_travaux'), entree()));
    await assertFails(updateDoc(doc(d, 'chantier_travaux/tA'), { complete: true, dateComplete: serverTimestamp() }));
    await assertFails(deleteDoc(doc(d, 'chantier_travaux/tA')));
  });

  test('création refusée : déjà complétée, texte vide, chantier de B, champ inconnu', async () => {
    const col = collection(ctxDe('uid-plusA'), 'chantier_travaux');
    await assertFails(addDoc(col, entree({ complete: true })));
    await assertFails(addDoc(col, entree({ texte: '' })));
    await assertFails(addDoc(col, entree({ chantierId: 'chB' })));
    await assertFails(addDoc(col, entree({ admin: true })));
  });

  test('modification refusée : changer companyId/chantierId, date falsifiée, autre compagnie', async () => {
    const ref = doc(ctxDe('uid-plusA'), 'chantier_travaux/tA');
    await assertFails(updateDoc(ref, { companyId: 'B' }));
    await assertFails(updateDoc(ref, { chantierId: 'chB' }));
    await assertFails(updateDoc(ref, { complete: true, dateComplete: new Date('2020-01-01') }));
    await assertFails(updateDoc(doc(ctxDe('uid-plusA'), 'chantier_travaux/tB'), { texte: 'x' }));
    await assertFails(deleteDoc(doc(ctxDe('uid-plusA'), 'chantier_travaux/tB')));
  });
});

// =============================================================================
describe('Feuilles de temps — employé', () => {
  const feuille = (lundiDate, over = {}) => ({
    companyId: 'A', estIndividuel: false, employeeId: 'empA', employeeNom: 'Emp A',
    lundiDate, jours: [{ nomJour: 'Lundi', heuresTravaillees: 8 }], totalHeures: 8,
    dateModification: serverTimestamp(), ...over,
  });

  test('lit sa feuille (existante ou non) ; pas celle d\'un collègue ni d\'une autre compagnie', async () => {
    const d = ctxDe('uid-empA');
    await assertSucceeds(getDoc(doc(d, `feuilles_temps/empA_${LUNDI}`)));
    await assertSucceeds(getDoc(doc(d, 'feuilles_temps/empA_2030-01-07')));
    await assertFails(getDoc(doc(d, `feuilles_temps/adminA_${LUNDI}`)));
    await assertFails(getDoc(doc(d, `feuilles_temps/adminB_${LUNDI}`)));
  });

  test('enregistre sa feuille de la semaine courante et suivante (set merge) → OK', async () => {
    const d = ctxDe('uid-empA');
    await assertSucceeds(setDoc(doc(d, `feuilles_temps/empA_${LUNDI}`), feuille(LUNDI), { merge: true }));
    await assertSucceeds(setDoc(doc(d, `feuilles_temps/empA_${LUNDI_PROCHAIN}`), feuille(LUNDI_PROCHAIN), { merge: true }));
  });

  test('refusé : autre employé, id incohérent, autre compagnie, faux nom, heures absurdes', async () => {
    const d = ctxDe('uid-empA');
    const id = `feuilles_temps/empA_${LUNDI}`;
    await assertFails(setDoc(doc(d, `feuilles_temps/adminA_${LUNDI}`), feuille(LUNDI, { employeeId: 'adminA' })));
    await assertFails(setDoc(doc(d, `feuilles_temps/empA_${LUNDI_PROCHAIN}`), feuille(LUNDI)));
    await assertFails(setDoc(doc(d, id), feuille(LUNDI, { companyId: 'B' })));
    await assertFails(setDoc(doc(d, id), feuille(LUNDI, { employeeNom: 'Admin A' })));
    await assertFails(setDoc(doc(d, id), feuille(LUNDI, { totalHeures: 500 })));
    await assertFails(setDoc(doc(d, id), feuille(LUNDI, { estIndividuel: true })));
  });

  test('verrouillage : employé et contremaître ne modifient plus une semaine échue', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-empA'), `feuilles_temps/empA_${LUNDI_PASSE}`),
      feuille(LUNDI_PASSE), { merge: true }));
    await assertFails(setDoc(doc(ctxDe('uid-plusA'), `feuilles_temps/plusA_${LUNDI_PASSE}`),
      feuille(LUNDI_PASSE, { employeeId: 'plusA', employeeNom: 'Plus A' })));
  });

  test('verrouillage : l\'admin peut encore corriger sa semaine échue', async () => {
    await assertSucceeds(setDoc(doc(ctxDe('uid-adminA'), `feuilles_temps/adminA_${LUNDI_PASSE}`),
      feuille(LUNDI_PASSE, { employeeId: 'adminA', employeeNom: 'Admin A' })));
  });

  test('suppression → refusée', async () => {
    await assertFails(deleteDoc(doc(ctxDe('uid-adminA'), `feuilles_temps/empA_${LUNDI}`)));
  });
});

// =============================================================================
describe('Particuliers', () => {
  const feuilleSolo = (over = {}) => ({
    estIndividuel: true, employeeId: 'uid-ind', employeeNom: 'Solo',
    lundiDate: LUNDI_PASSE, jours: [], totalHeures: 0, dateModification: serverTimestamp(), ...over,
  });

  test('profil : crée/lit le sien avec son propre courriel (casse ignorée)', async () => {
    const d = db(individu(env, 'uid-ind2'));
    await assertSucceeds(setDoc(doc(d, 'individus/uid-ind2'), { nom: 'Nouveau', email: 'uid-ind2@exemple.ca' }));
    await assertSucceeds(setDoc(doc(d, 'individus/uid-ind2'), { nom: 'Nouveau', email: 'UID-Ind2@Exemple.ca' }));
    await assertSucceeds(getDoc(doc(d, 'individus/uid-ind2')));
    await assertFails(setDoc(doc(d, 'individus/uid-ind2'), { nom: 'N', email: 'autre@exemple.ca' }));
    await assertFails(getDoc(doc(d, 'individus/uid-ind')));
  });

  test('profil : un compte anonyme ne peut pas créer de profil', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-anon'), 'individus/uid-anon'), { nom: 'N', email: 'x@x.ca' }));
  });

  test('feuille perso : enregistre (même semaine passée : pas de verrouillage) et relit', async () => {
    const ref = doc(db(individu(env, 'uid-ind')), `feuilles_temps/uid-ind_${LUNDI_PASSE}`);
    await assertSucceeds(setDoc(ref, feuilleSolo(), { merge: true }));
    await assertSucceeds(getDoc(ref));
  });

  test('feuille perso : refusé avec companyId, estIndividuel=false ou pour un autre uid', async () => {
    const d = db(individu(env, 'uid-ind'));
    await assertFails(setDoc(doc(d, `feuilles_temps/uid-ind_${LUNDI_PASSE}`), feuilleSolo({ companyId: 'A' })));
    await assertFails(setDoc(doc(d, `feuilles_temps/uid-ind_${LUNDI_PASSE}`), feuilleSolo({ estIndividuel: false })));
    await assertFails(setDoc(doc(d, `feuilles_temps/empA_${LUNDI}`), feuilleSolo({ employeeId: 'empA', lundiDate: LUNDI })));
  });

  test('un compte anonyme sans session ne peut pas se faire passer pour un particulier', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-anon'), `feuilles_temps/uid-anon_${LUNDI}`),
      feuilleSolo({ employeeId: 'uid-anon', lundiDate: LUNDI })));
  });

  test('un particulier ne voit rien des compagnies', async () => {
    const d = db(individu(env, 'uid-ind'));
    await assertFails(getDocs(query(collection(d, 'feuilles_temps'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(d, 'companies/A')));
  });
});

// =============================================================================
describe('Collections serveur uniquement', () => {
  test('compteurs, limites, données privées, codes, config : aucun accès client', async () => {
    for (const uid of ['uid-adminA', 'uid-superA']) {
      const d = ctxDe(uid);
      for (const chemin of ['compteurs/companies', 'limites_connexion/x', 'companies_prive/A',
        'reinitialisations_nip/empA', 'config/securite']) {
        await assertFails(getDoc(doc(d, chemin)));
        await assertFails(setDoc(doc(d, chemin), { a: 1 }));
      }
    }
  });

  test('collection inconnue → refusée', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-adminA'), 'autre/x'), { a: 1 }));
  });
});
