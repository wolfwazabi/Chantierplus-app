import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, deleteField, doc, getDoc, getDocs, orderBy, query,
  serverTimestamp, setDoc, updateDoc, where,
} from 'firebase/firestore';
import { creerEnvironnement, employe, individu, LUNDI, semer, superAdmin } from './helpers.mjs';

let env;
before(async () => { env = await creerEnvironnement(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await semer(env); });

const db = (ctx) => ctx.firestore();

// =============================================================================
describe('Bug semaine_liste_screen : liste des feuilles de temps', () => {
  test('admin A : requête filtrée par companyId + orderBy lundiDate → OK', async () => {
    const q = query(collection(db(employe(env, 'uid-adminA')), 'feuilles_temps'),
      where('companyId', '==', 'A'), orderBy('lundiDate', 'desc'));
    await assertSucceeds(getDocs(q));
  });

  test('admin A : requête SANS filtre companyId (ancien code) → refusée', async () => {
    const q = query(collection(db(employe(env, 'uid-adminA')), 'feuilles_temps'), orderBy('lundiDate', 'desc'));
    await assertFails(getDocs(q));
  });

  test('admin A : requête sur companyId B → refusée', async () => {
    const q = query(collection(db(employe(env, 'uid-adminA')), 'feuilles_temps'), where('companyId', '==', 'B'));
    await assertFails(getDocs(q));
  });

  test('admin A : détail de semaine (companyId + lundiDate) → OK', async () => {
    const q = query(collection(db(employe(env, 'uid-adminA')), 'feuilles_temps'),
      where('companyId', '==', 'A'), where('lundiDate', '==', LUNDI));
    await assertSucceeds(getDocs(q));
  });

  test('admin A : historique employé (companyId + employeeId) → OK', async () => {
    const q = query(collection(db(employe(env, 'uid-adminA')), 'feuilles_temps'),
      where('companyId', '==', 'A'), where('employeeId', '==', 'empA'));
    await assertSucceeds(getDocs(q));
  });

  test('employé (non admin) : liste de la compagnie → refusée', async () => {
    const q = query(collection(db(employe(env, 'uid-empA')), 'feuilles_temps'), where('companyId', '==', 'A'));
    await assertFails(getDocs(q));
  });
});

// =============================================================================
describe('Sessions', () => {
  test('le client ne peut pas créer sa session (usurpation)', async () => {
    await assertFails(setDoc(doc(db(employe(env, 'uid-nouveau')), 'sessions/uid-nouveau'),
      { employeeId: 'adminA', companyId: 'A' }));
  });

  test('le client ne peut pas modifier sa session', async () => {
    await assertFails(updateDoc(doc(db(employe(env, 'uid-empA')), 'sessions/uid-empA'), { employeeId: 'adminA' }));
  });

  test('lecture de sa propre session → OK ; celle d\'un autre → refusée', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(getDoc(doc(db(ctx), 'sessions/uid-empA')));
    await assertFails(getDoc(doc(db(ctx), 'sessions/uid-adminA')));
  });

  test('lister les sessions → refusé', async () => {
    await assertFails(getDocs(collection(db(employe(env, 'uid-adminA')), 'sessions')));
  });

  test('suppression de sa propre session (déconnexion) → OK', async () => {
    await assertSucceeds(deleteDoc(doc(db(employe(env, 'uid-empA')), 'sessions/uid-empA')));
  });

  test('session forgée (employé A déclaré dans compagnie B) → aucun accès à B ni à A', async () => {
    const ctx = employe(env, 'uid-forge');
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'B'))));
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'A'))));
  });

  test('session d\'un employé supprimé → aucun accès', async () => {
    const ctx = employe(env, 'uid-supprime');
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'A'))));
  });

  test('compagnie en attente → aucun accès', async () => {
    const ctx = employe(env, 'uid-adminP');
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'P'))));
    await assertFails(getDoc(doc(db(ctx), 'companies/P')));
  });

  test('compte courriel (particulier) avec une session → ignorée', async () => {
    await env.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), 'sessions/uid-ind'), { employeeId: 'adminA', companyId: 'A' }));
    const ctx = individu(env, 'uid-ind');
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'A'))));
  });

  test('non authentifié → aucun accès', async () => {
    const ctx = env.unauthenticatedContext();
    await assertFails(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'A'))));
  });
});

// =============================================================================
describe('Compagnies', () => {
  test('membre : lit sa compagnie, pas celle d\'une autre', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(getDoc(doc(db(ctx), 'companies/A')));
    await assertFails(getDoc(doc(db(ctx), 'companies/B')));
  });

  test('membre : ne peut pas lister les compagnies', async () => {
    await assertFails(getDocs(collection(db(employe(env, 'uid-adminA')), 'companies')));
  });

  test('super-admin : liste toutes les compagnies', async () => {
    await assertSucceeds(getDocs(query(collection(db(superAdmin(env)), 'companies'), orderBy('dateCreation', 'desc'))));
  });

  test('personne ne modifie une compagnie côté client (ni admin, ni super-admin)', async () => {
    await assertFails(updateDoc(doc(db(employe(env, 'uid-adminA')), 'companies/A'), { statut: 'approuvee' }));
    await assertFails(updateDoc(doc(db(employe(env, 'uid-adminP')), 'companies/P'), { statut: 'approuvee' }));
    await assertFails(updateDoc(doc(db(superAdmin(env)), 'companies/P'), { statut: 'approuvee' }));
  });

  test('un faux claim superAdmin=false ne donne rien', async () => {
    const ctx = env.authenticatedContext('uid-x', { superAdmin: false, firebase: { sign_in_provider: 'password' } });
    await assertFails(getDocs(collection(db(ctx), 'companies')));
  });
});

// =============================================================================
describe('Employés', () => {
  test('employé : lit sa propre fiche, pas celle des autres', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(getDoc(doc(db(ctx), 'employees/empA')));
    await assertFails(getDoc(doc(db(ctx), 'employees/adminA')));
  });

  test('employé : ne peut pas lister les employés', async () => {
    await assertFails(getDocs(query(collection(db(employe(env, 'uid-empA')), 'employees'), where('companyId', '==', 'A'))));
  });

  test('admin A : liste les employés de A, pas ceux de B', async () => {
    const ctx = employe(env, 'uid-adminA');
    await assertSucceeds(getDocs(query(collection(db(ctx), 'employees'), where('companyId', '==', 'A'))));
    await assertFails(getDocs(query(collection(db(ctx), 'employees'), where('companyId', '==', 'B'))));
    await assertFails(getDoc(doc(db(ctx), 'employees/adminB')));
  });

  test('aucune écriture client (création, promotion, suppression du propriétaire)', async () => {
    const ctx = employe(env, 'uid-adminA');
    await assertFails(addDoc(collection(db(ctx), 'employees'), { companyId: 'A', nom: 'X', role: 'admin' }));
    await assertFails(updateDoc(doc(db(employe(env, 'uid-empA')), 'employees/empA'), { role: 'admin' }));
    await assertFails(deleteDoc(doc(db(ctx), 'employees/adminA')));
  });
});

// =============================================================================
describe('Chantiers', () => {
  test('membre : lit les chantiers de sa compagnie seulement', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(getDocs(query(collection(db(ctx), 'chantiers'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(db(ctx), 'chantiers/chB')));
  });

  test('employé : ne peut pas créer de chantier', async () => {
    await assertFails(addDoc(collection(db(employe(env, 'uid-empA')), 'chantiers'),
      { companyId: 'A', nom: 'N', adresse: '' }));
  });

  test('admin A : crée dans A ; refusé dans B ; refusé avec champ en trop', async () => {
    const ctx = employe(env, 'uid-adminA');
    await assertSucceeds(addDoc(collection(db(ctx), 'chantiers'), { companyId: 'A', nom: 'Nouveau', adresse: '2 rue' }));
    await assertFails(addDoc(collection(db(ctx), 'chantiers'), { companyId: 'B', nom: 'Intrus', adresse: '' }));
    await assertFails(addDoc(collection(db(ctx), 'chantiers'), { companyId: 'A', nom: 'N', adresse: '', x: 1 }));
    await assertFails(addDoc(collection(db(ctx), 'chantiers'), { companyId: 'A', nom: '', adresse: '' }));
  });

  test('admin A : modifie le nom ; ne peut pas déplacer vers B ; ne touche pas à B', async () => {
    const ctx = employe(env, 'uid-adminA');
    await assertSucceeds(updateDoc(doc(db(ctx), 'chantiers/chA'), { nom: 'Renommé', adresse: '3 rue' }));
    await assertFails(updateDoc(doc(db(ctx), 'chantiers/chA'), { companyId: 'B' }));
    await assertFails(updateDoc(doc(db(ctx), 'chantiers/chB'), { nom: 'Piraté' }));
    await assertFails(deleteDoc(doc(db(ctx), 'chantiers/chB')));
    await assertSucceeds(deleteDoc(doc(db(ctx), 'chantiers/chA')));
  });
});

// =============================================================================
describe('Photos de chantier', () => {
  const photo = (over = {}) => ({
    companyId: 'A', chantierId: 'chA',
    url: 'https://firebasestorage.googleapis.com/v0/b/x/o/p.jpg',
    cheminStorage: 'chantiers/A/chA/photos/123_p.jpg',
    dateAjout: serverTimestamp(),
    ...over,
  });

  test('membre A : ajoute une photo valide', async () => {
    await assertSucceeds(addDoc(collection(db(employe(env, 'uid-empA')), 'chantier_photos'), photo()));
  });

  test('refusé : chantier d\'une autre compagnie, chemin incohérent, URL externe, date client', async () => {
    const col = collection(db(employe(env, 'uid-empA')), 'chantier_photos');
    await assertFails(addDoc(col, photo({ chantierId: 'chB', cheminStorage: 'chantiers/A/chB/photos/p.jpg' })));
    await assertFails(addDoc(col, photo({ cheminStorage: 'chantiers/B/chB/photos/p.jpg' })));
    await assertFails(addDoc(col, photo({ url: 'https://evil.example.com/p.jpg' })));
    await assertFails(addDoc(col, photo({ dateAjout: new Date('2020-01-01') })));
    await assertFails(addDoc(col, photo({ companyId: 'B', chantierId: 'chB', cheminStorage: 'chantiers/B/chB/photos/p.jpg' })));
  });

  test('lecture/suppression : A oui, B non', async () => {
    await assertSucceeds(getDoc(doc(db(employe(env, 'uid-empA')), 'chantier_photos/pA')));
    await assertFails(getDoc(doc(db(employe(env, 'uid-adminB')), 'chantier_photos/pA')));
    await assertFails(deleteDoc(doc(db(employe(env, 'uid-adminB')), 'chantier_photos/pA')));
    await assertSucceeds(deleteDoc(doc(db(employe(env, 'uid-empA')), 'chantier_photos/pA')));
  });
});

// =============================================================================
describe('Travaux / matériel', () => {
  const entree = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', texte: 'Tâche', complete: false, dateAjout: serverTimestamp(), ...over,
  });

  test('création valide (avec quantité et photo) → OK', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(addDoc(collection(db(ctx), 'chantier_travaux'), entree()));
    await assertSucceeds(addDoc(collection(db(ctx), 'chantier_materiel'), entree({
      quantite: '12 feuilles', photoUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/m.jpg',
    })));
  });

  test('création refusée : déjà complétée, texte vide, chantier de B, champ inconnu', async () => {
    const col = collection(db(employe(env, 'uid-empA')), 'chantier_travaux');
    await assertFails(addDoc(col, entree({ complete: true })));
    await assertFails(addDoc(col, entree({ texte: '' })));
    await assertFails(addDoc(col, entree({ chantierId: 'chB' })));
    await assertFails(addDoc(col, entree({ admin: true })));
  });

  test('compléter / décompléter / éditer → OK', async () => {
    const ref = doc(db(employe(env, 'uid-empA')), 'chantier_travaux/tA');
    await assertSucceeds(updateDoc(ref, { complete: true, dateComplete: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { texte: 'Coffrage fini' }));
    await assertSucceeds(updateDoc(ref, { complete: false, dateComplete: deleteField() }));
  });

  test('modification refusée : changer companyId/chantierId, date falsifiée, autre compagnie', async () => {
    const ref = doc(db(employe(env, 'uid-empA')), 'chantier_travaux/tA');
    await assertFails(updateDoc(ref, { companyId: 'B' }));
    await assertFails(updateDoc(ref, { chantierId: 'chB' }));
    await assertFails(updateDoc(ref, { complete: true, dateComplete: new Date('2020-01-01') }));
    await assertFails(updateDoc(doc(db(employe(env, 'uid-empA')), 'chantier_travaux/tB'), { texte: 'x' }));
    await assertFails(deleteDoc(doc(db(employe(env, 'uid-empA')), 'chantier_travaux/tB')));
  });
});

// =============================================================================
describe('Feuilles de temps — employé', () => {
  const feuille = (over = {}) => ({
    companyId: 'A', estIndividuel: false, employeeId: 'empA', employeeNom: 'Emp A',
    lundiDate: '2026-09-28', jours: [{ nomJour: 'Lundi', heuresTravaillees: 8 }], totalHeures: 8,
    dateModification: serverTimestamp(), ...over,
  });

  test('lit sa feuille (existante ou non) ; pas celle d\'un collègue ni d\'une autre compagnie', async () => {
    const ctx = employe(env, 'uid-empA');
    await assertSucceeds(getDoc(doc(db(ctx), `feuilles_temps/empA_${LUNDI}`)));
    await assertSucceeds(getDoc(doc(db(ctx), 'feuilles_temps/empA_2030-01-07')));
    await assertFails(getDoc(doc(db(ctx), `feuilles_temps/adminA_${LUNDI}`)));
    await assertFails(getDoc(doc(db(ctx), `feuilles_temps/adminB_${LUNDI}`)));
  });

  test('enregistre sa feuille (set merge) → OK', async () => {
    const ref = doc(db(employe(env, 'uid-empA')), 'feuilles_temps/empA_2026-09-28');
    await assertSucceeds(setDoc(ref, feuille(), { merge: true }));
    await assertSucceeds(setDoc(ref, feuille({ totalHeures: 16 }), { merge: true }));
  });

  test('refusé : autre employé, id incohérent, autre compagnie, faux nom, heures absurdes', async () => {
    const d = db(employe(env, 'uid-empA'));
    await assertFails(setDoc(doc(d, 'feuilles_temps/adminA_2026-09-28'), feuille({ employeeId: 'adminA' })));
    await assertFails(setDoc(doc(d, 'feuilles_temps/empA_2026-10-05'), feuille()));
    await assertFails(setDoc(doc(d, 'feuilles_temps/empA_2026-09-28'), feuille({ companyId: 'B' })));
    await assertFails(setDoc(doc(d, 'feuilles_temps/empA_2026-09-28'), feuille({ employeeNom: 'Admin A' })));
    await assertFails(setDoc(doc(d, 'feuilles_temps/empA_2026-09-28'), feuille({ totalHeures: 500 })));
    await assertFails(setDoc(doc(d, 'feuilles_temps/empA_2026-09-28'), feuille({ estIndividuel: true })));
  });

  test('suppression → refusée', async () => {
    await assertFails(deleteDoc(doc(db(employe(env, 'uid-adminA')), `feuilles_temps/empA_${LUNDI}`)));
  });
});

// =============================================================================
describe('Particuliers', () => {
  const feuilleSolo = (over = {}) => ({
    estIndividuel: true, employeeId: 'uid-ind', employeeNom: 'Solo',
    lundiDate: LUNDI, jours: [], totalHeures: 0, dateModification: serverTimestamp(), ...over,
  });

  test('profil : crée/lit le sien avec son propre courriel', async () => {
    const ctx = individu(env, 'uid-ind2');
    await assertSucceeds(setDoc(doc(db(ctx), 'individus/uid-ind2'), { nom: 'Nouveau', email: 'uid-ind2@exemple.ca' }));
    await assertSucceeds(getDoc(doc(db(ctx), 'individus/uid-ind2')));
    await assertFails(setDoc(doc(db(ctx), 'individus/uid-ind2'), { nom: 'N', email: 'autre@exemple.ca' }));
    await assertFails(getDoc(doc(db(ctx), 'individus/uid-ind')));
  });

  test('profil : un compte anonyme ne peut pas créer de profil', async () => {
    await assertFails(setDoc(doc(db(employe(env, 'uid-anon')), 'individus/uid-anon'), { nom: 'N', email: 'x@x.ca' }));
  });

  test('feuille perso : enregistre et relit la sienne', async () => {
    const ref = doc(db(individu(env, 'uid-ind')), `feuilles_temps/uid-ind_${LUNDI}`);
    await assertSucceeds(setDoc(ref, feuilleSolo(), { merge: true }));
    await assertSucceeds(getDoc(ref));
  });

  test('feuille perso : refusé avec companyId, estIndividuel=false ou pour un autre uid', async () => {
    const d = db(individu(env, 'uid-ind'));
    await assertFails(setDoc(doc(d, `feuilles_temps/uid-ind_${LUNDI}`), feuilleSolo({ companyId: 'A' })));
    await assertFails(setDoc(doc(d, `feuilles_temps/uid-ind_${LUNDI}`), feuilleSolo({ estIndividuel: false })));
    await assertFails(setDoc(doc(d, `feuilles_temps/empA_${LUNDI}`), feuilleSolo({ employeeId: 'empA' })));
  });

  test('un compte anonyme sans session ne peut pas se faire passer pour un particulier', async () => {
    const d = db(employe(env, 'uid-anon'));
    await assertFails(setDoc(doc(d, `feuilles_temps/uid-anon_${LUNDI}`), feuilleSolo({ employeeId: 'uid-anon' })));
  });

  test('un particulier ne voit rien des compagnies', async () => {
    const d = db(individu(env, 'uid-ind'));
    await assertFails(getDocs(query(collection(d, 'feuilles_temps'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(d, 'companies/A')));
  });
});

// =============================================================================
describe('Collections serveur uniquement', () => {
  test('compteurs, limites_connexion, companies_prive : aucun accès client', async () => {
    for (const ctx of [employe(env, 'uid-adminA'), superAdmin(env)]) {
      await assertFails(getDoc(doc(db(ctx), 'compteurs/companies')));
      await assertFails(setDoc(doc(db(ctx), 'compteurs/companies'), { dernierNumero: 1 }));
      await assertFails(getDoc(doc(db(ctx), 'limites_connexion/x')));
      await assertFails(getDoc(doc(db(ctx), 'companies_prive/A')));
    }
  });

  test('collection inconnue → refusée', async () => {
    await assertFails(setDoc(doc(db(employe(env, 'uid-adminA')), 'autre/x'), { a: 1 }));
  });
});
