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

  test('le client ne peut pas modifier sa session, même à l\'identique', async () => {
    const ref = doc(ctxDe('uid-empA'), 'sessions/uid-empA');
    await assertFails(updateDoc(ref, { employeeId: 'adminA' }));
    await assertFails(setDoc(ref, { employeeId: 'empA', companyId: 'B' }));
    await assertFails(setDoc(ref, { employeeId: 'empA', companyId: 'A' }));
    await assertFails(updateDoc(ref, { proprioApp: true }));
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

  test('Proprio : liste et lit toutes les compagnies', async () => {
    const d = ctxDe('uid-superA');
    await assertSucceeds(getDocs(query(collection(d, 'companies'), orderBy('dateCreation', 'desc'))));
    await assertSucceeds(getDoc(doc(d, 'companies/P')));
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

  test('personne ne modifie le statut ou le numéro d\'une compagnie côté client', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-adminP'), 'companies/P'), { statut: 'approuvee' }));
    await assertFails(updateDoc(doc(ctxDe('uid-superA'), 'companies/P'), { statut: 'approuvee' }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'), { statut: 'refusee' }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'), { numero: '9999' }));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminA'), 'companies/A')));
    await assertFails(setDoc(doc(ctxDe('uid-adminA'), 'companies/Z'), { couleurTheme: '#C62828' }));
  });
});

// =============================================================================
describe('Couleur de l\'application (par compagnie)', () => {
  test('admin et super-admin de la compagnie : changent la couleur', async () => {
    await assertSucceeds(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'), { couleurTheme: '#C62828' }));
    await assertSucceeds(updateDoc(doc(ctxDe('uid-superA'), 'companies/A'), { couleurTheme: '#1565C0' }));
  });

  test('contremaître et employé : refusé', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-plusA'), 'companies/A'), { couleurTheme: '#C62828' }));
    await assertFails(updateDoc(doc(ctxDe('uid-empA'), 'companies/A'), { couleurTheme: '#C62828' }));
  });

  test('autre compagnie, compagnie en attente, particulier : refusé', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-adminB'), 'companies/A'), { couleurTheme: '#C62828' }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminP'), 'companies/P'), { couleurTheme: '#C62828' }));
    await assertFails(updateDoc(doc(db(individu(env, 'uid-ind')), 'companies/A'), { couleurTheme: '#C62828' }));
  });

  test('format strict « #RRGGBB » en majuscules', async () => {
    const ref = doc(ctxDe('uid-adminA'), 'companies/A');
    for (const mauvais of ['#c62828', 'C62828', '#FFF', '#C628289', 'rouge', 123, '#GGGGGG', "#C62828'; x"]) {
      await assertFails(updateDoc(ref, { couleurTheme: mauvais }));
    }
  });

  test('la couleur seulement : pas en même temps qu\'un autre champ', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'),
      { couleurTheme: '#C62828', statut: 'refusee' }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'),
      { couleurTheme: '#C62828', nomEntreprise: 'Piratée' }));
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

  test('aucune écriture client, même par un admin (tout passe par les Cloud Functions)', async () => {
    const d = ctxDe('uid-adminA');
    const fiche = { companyId: 'A', nom: 'N', courriel: 'n@a.ca', role: 'employe', estProprietaire: false };
    await assertFails(addDoc(collection(d, 'employees'), fiche));
    await assertFails(addDoc(collection(d, 'employees'), { ...fiche, pin: '123456' }));
    await assertFails(setDoc(doc(d, 'employees/nouveau'), fiche));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { nom: 'Renommé' }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { role: 'admin' }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { superAdmin: true }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { estProprietaire: true }));
    await assertFails(updateDoc(doc(d, 'employees/empA'), { pinHash: 'autre' }));
    await assertFails(updateDoc(doc(ctxDe('uid-empA'), 'employees/empA'), { role: 'admin' }));
    await assertFails(deleteDoc(doc(d, 'employees/empA')));
    await assertFails(deleteDoc(doc(d, 'employees/adminA')));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'employees/empA')));
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
describe('Documents de chantier (dépôt : admin ; consultation : admin et contremaître)', () => {
  const document = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', nom: 'Devis toiture.xlsx',
    cheminStorage: 'chantiers/A/chA/documents/171_Devis_toiture.xlsx',
    url: 'https://firebasestorage.googleapis.com/v0/b/x/o/devis.xlsx',
    taille: 20480, typeMime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ajoutePar: 'adminA', dateAjout: serverTimestamp(), ...over,
  });
  const lister = (uid, cid = 'A') => getDocs(query(collection(ctxDe(uid), 'chantier_documents'),
    where('companyId', '==', cid), where('chantierId', '==', cid === 'A' ? 'chA' : 'chB')));

  test('admin et Proprio (admin de sa compagnie) : déposent et suppriment', async () => {
    await assertSucceeds(addDoc(collection(ctxDe('uid-adminA'), 'chantier_documents'), document()));
    await assertSucceeds(addDoc(collection(ctxDe('uid-superA'), 'chantier_documents'),
      document({ ajoutePar: 'superA' })));
    await assertSucceeds(deleteDoc(doc(ctxDe('uid-adminA'), 'chantier_documents/dA')));
  });

  test('contremaître : consulte, mais ne dépose ni ne supprime', async () => {
    await assertSucceeds(lister('uid-plusA'));
    await assertSucceeds(getDoc(doc(ctxDe('uid-plusA'), 'chantier_documents/dA')));
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'chantier_documents'), document({ ajoutePar: 'plusA' })));
    await assertFails(deleteDoc(doc(ctxDe('uid-plusA'), 'chantier_documents/dA')));
  });

  test('employé : aucun accès', async () => {
    await assertFails(lister('uid-empA'));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'chantier_documents/dA')));
  });

  test('autre compagnie : ni lecture, ni dépôt, ni suppression', async () => {
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'chantier_documents/dA')));
    await assertFails(lister('uid-adminB', 'A'));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'chantier_documents/dA')));
    await assertFails(addDoc(collection(ctxDe('uid-adminB'), 'chantier_documents'), document({ ajoutePar: 'adminB' })));
  });

  test("refusé : chemin incohérent, chantier d'une autre compagnie, taille, auteur ou date falsifiés, champ inconnu", async () => {
    const col = collection(ctxDe('uid-adminA'), 'chantier_documents');
    await assertFails(addDoc(col, document({ cheminStorage: 'chantiers/A/chA/photos/x.pdf' })));
    await assertFails(addDoc(col, document({ cheminStorage: 'chantiers/B/chB/documents/x.pdf' })));
    await assertFails(addDoc(col, document({ chantierId: 'chB', cheminStorage: 'chantiers/A/chB/documents/x.pdf' })));
    await assertFails(addDoc(col, document({ taille: 60 * 1024 * 1024 })));
    await assertFails(addDoc(col, document({ taille: 0 })));
    await assertFails(addDoc(col, document({ ajoutePar: 'empA' })));
    await assertFails(addDoc(col, document({ dateAjout: new Date('2020-01-01') })));
    await assertFails(addDoc(col, document({ url: 'https://evil.example.com/x.pdf' })));
    await assertFails(addDoc(col, document({ public: true })));
    await assertFails(updateDoc(doc(ctxDe('uid-adminA'), 'chantier_documents/dA'), { nom: 'Renommé.pdf' }));
  });
});

// =============================================================================
describe('Règles de paie (pauses, voyagement) par compagnie', () => {
  const regles = (over = {}) => ({
    pauseMatinMinutes: 15, pauseMatinPayee: false, dinerMinutes: 30, dinerPaye: true,
    voyagementActif: true, voyagementSeuilMinutes: 60, voyagementPourcentage: 50, ...over,
  });

  test('admin et super-admin : modifient les règles de paie', async () => {
    await assertSucceeds(updateDoc(doc(ctxDe('uid-adminA'), 'companies/A'), { reglesPaie: regles() }));
    await assertSucceeds(updateDoc(doc(ctxDe('uid-superA'), 'companies/A'),
      { reglesPaie: regles({ voyagementActif: false }), couleurTheme: '#1565C0' }));
  });

  test('contremaître, employé, autre compagnie : refusé', async () => {
    await assertFails(updateDoc(doc(ctxDe('uid-plusA'), 'companies/A'), { reglesPaie: regles() }));
    await assertFails(updateDoc(doc(ctxDe('uid-empA'), 'companies/A'), { reglesPaie: regles() }));
    await assertFails(updateDoc(doc(ctxDe('uid-adminB'), 'companies/A'), { reglesPaie: regles() }));
  });

  test('valeurs hors bornes, champ manquant ou inconnu : refusé', async () => {
    const ref = doc(ctxDe('uid-adminA'), 'companies/A');
    for (const mauvais of [
      regles({ voyagementPourcentage: 150 }), regles({ voyagementPourcentage: -1 }),
      regles({ voyagementSeuilMinutes: 601 }), regles({ dinerMinutes: 121 }),
      regles({ pauseMatinMinutes: 7.5 }), regles({ dinerPaye: 'oui' }),
      regles({ bonus: 1 }), (({ dinerPaye, ...r }) => r)(regles()), 'pas-un-map',
    ]) {
      await assertFails(updateDoc(ref, { reglesPaie: mauvais }));
    }
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

  // Les feuilles de compagnie s'écrivent uniquement par la Cloud Function
  // enregistrerFeuilleTemps (calcul des heures côté serveur, testée dans
  // functions.test.mjs). Aucun rôle ne peut les écrire depuis l'app.
  test('AUCUN rôle n\'écrit une feuille de compagnie directement (heures truquées impossibles)', async () => {
    const cas = [
      ['uid-empA', 'empA', 'Emp A'], ['uid-plusA', 'plusA', 'Plus A'],
      ['uid-adminA', 'adminA', 'Admin A'], ['uid-superA', 'superA', 'Super A'],
    ];
    for (const [uid, employeeId, employeeNom] of cas) {
      const d = ctxDe(uid);
      for (const lundiDate of [LUNDI, LUNDI_PROCHAIN, LUNDI_PASSE]) {
        const ref = doc(d, `feuilles_temps/${employeeId}_${lundiDate}`);
        const f = feuille(lundiDate, { employeeId, employeeNom });
        await assertFails(setDoc(ref, f));
        await assertFails(setDoc(ref, f, { merge: true }));
        await assertFails(updateDoc(ref, { totalHeures: 1 }));
      }
    }
  });

  test('un employé ne peut pas gonfler les heures d\'une feuille existante', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), `feuilles_temps/empA_${LUNDI}`), feuille(LUNDI, { dateModification: new Date() }));
    });
    const ref = doc(ctxDe('uid-empA'), `feuilles_temps/empA_${LUNDI}`);
    await assertFails(updateDoc(ref, { totalHeures: 160, totalHeuresTravaillees: 160 }));
    await assertFails(setDoc(ref, feuille(LUNDI, { totalHeures: 100 }), { merge: true }));
    await assertSucceeds(getDoc(ref)); // lecture de sa propre feuille : permise
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

  test('profil : crée/lit le sien avec exactement le courriel du jeton', async () => {
    const d = db(individu(env, 'uid-ind2'));
    await assertSucceeds(setDoc(doc(d, 'individus/uid-ind2'), { nom: 'Nouveau', email: 'uid-ind2@exemple.ca' }));
    await assertFails(setDoc(doc(d, 'individus/uid-ind2'), { nom: 'Nouveau', email: 'UID-Ind2@Exemple.ca' }));
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
        'reinitialisations_nip/empA', 'invitations_nip/empA', 'config/securite']) {
        await assertFails(getDoc(doc(d, chemin)));
        await assertFails(setDoc(doc(d, chemin), { a: 1 }));
      }
    }
  });

  test('collection inconnue → refusée', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-adminA'), 'autre/x'), { a: 1 }));
  });
});
