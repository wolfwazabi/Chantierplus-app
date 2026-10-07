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

  test('compagnie en cours de suppression → plus aucun accès, même pour ses admins', async () => {
    await assertSucceeds(getDocs(query(collection(ctxDe('uid-adminA'), 'chantiers'), where('companyId', '==', 'A'))));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(db(ctx), 'companies/A'), { statut: 'suppression' });
    });
    for (const uid of ['uid-adminA', 'uid-superA', 'uid-plusA', 'uid-empA']) {
      await assertFails(getDocs(query(collection(ctxDe(uid), 'chantiers'), where('companyId', '==', 'A'))));
      await assertFails(getDoc(doc(ctxDe(uid), 'companies/A')));
    }
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
  });

  test('un chantier ne se supprime jamais (tous rôles) : il s\'archive', async () => {
    for (const uid of ['uid-adminA', 'uid-superA', 'uid-plusA', 'uid-empA', 'uid-adminB']) {
      await assertFails(deleteDoc(doc(ctxDe(uid), 'chantiers/chA')));
    }
  });

  test('archiver et restaurer : admin de la compagnie seulement, booléen seulement', async () => {
    const ref = (uid) => doc(ctxDe(uid), 'chantiers/chA');
    await assertSucceeds(updateDoc(ref('uid-adminA'), { archive: true }));
    await assertSucceeds(updateDoc(ref('uid-superA'), { archive: false }));
    await assertFails(updateDoc(ref('uid-plusA'), { archive: true }));
    await assertFails(updateDoc(ref('uid-empA'), { archive: true }));
    await assertFails(updateDoc(ref('uid-adminB'), { archive: true }));
    await assertFails(updateDoc(ref('uid-adminA'), { archive: 'oui' }));
    await assertFails(updateDoc(ref('uid-adminA'), { archive: true, companyId: 'B' }));
    await assertFails(updateDoc(ref('uid-adminA'), { archive: true, autre: 1 }));
  });

  test('un chantier archivé reste lisible (ses photos et documents restent accessibles)', async () => {
    await assertSucceeds(updateDoc(doc(ctxDe('uid-adminA'), 'chantiers/chA'), { archive: true }));
    await assertSucceeds(getDoc(doc(ctxDe('uid-empA'), 'chantiers/chA')));
    await assertSucceeds(getDoc(doc(ctxDe('uid-adminA'), 'chantiers/chA')));
  });

  test('un chantier ne se crée pas déjà archivé ni avec un champ inconnu', async () => {
    await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'chantiers'),
      { companyId: 'A', nom: 'X', adresse: '', archive: true }));
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
describe('Matériel « Général » (remorque, sans chantier) : matériel seulement', () => {
  // Chaque entrée porte son auteur : ids et noms de la graine (plusA, adminA).
  const AUTEURS = {
    'uid-plusA': { ajoutePar: 'plusA', ajouteParNom: 'Plus A' },
    'uid-adminA': { ajoutePar: 'adminA', ajouteParNom: 'Admin A' },
    'uid-adminB': { ajoutePar: 'adminB', ajouteParNom: 'Admin B' },
  };
  const general = (uid, over = {}) => ({
    companyId: 'A', chantierId: '_general', texte: 'Sangles à cliquet', quantite: '4',
    complete: false, dateAjout: serverTimestamp(), ...AUTEURS[uid], ...over,
  });
  const materiel = (uid) => collection(ctxDe(uid), 'chantier_materiel');
  const generalDe = (uid, companyId = 'A') => query(collection(ctxDe(uid), 'chantier_materiel'),
    where('companyId', '==', companyId), where('chantierId', '==', '_general'));

  test('contremaître et admin : ajoutent, lisent, complètent, modifient, suppriment', async () => {
    for (const uid of ['uid-plusA', 'uid-adminA']) {
      const ref = await assertSucceeds(addDoc(materiel(uid), general(uid)));
      await assertSucceeds(getDocs(generalDe(uid)));
      await assertSucceeds(updateDoc(ref, { complete: true, dateComplete: serverTimestamp() }));
      await assertSucceeds(updateDoc(ref, { texte: 'Sangles 2 po', quantite: '6' }));
      await assertSucceeds(updateDoc(ref, { complete: false, dateComplete: deleteField() }));
      await assertSucceeds(deleteDoc(ref));
    }
  });

  test('avec photo : même chose qu\'un chantier', async () => {
    await assertSucceeds(addDoc(materiel('uid-plusA'), general('uid-plusA', {
      photoUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/m.jpg',
    })));
  });

  test('l\'auteur est obligatoire et ne peut pas être celui d\'un autre', async () => {
    const col = materiel('uid-plusA');
    const sans = general('uid-plusA'); delete sans.ajoutePar; delete sans.ajouteParNom;
    await assertFails(addDoc(col, sans));
    await assertFails(addDoc(col, general('uid-plusA', { ajoutePar: 'adminA', ajouteParNom: 'Admin A' })));
    await assertFails(addDoc(col, general('uid-plusA', { ajouteParNom: 'Quelqu\'un d\'autre' })));
    await assertFails(addDoc(col, general('uid-plusA', { ajoutePar: 'plusA', ajouteParNom: 'Admin A' })));
    // Bon nom, mauvais identifiant : pas moyen de passer pour quelqu'un d'autre.
    await assertFails(addDoc(col, general('uid-plusA', { ajoutePar: 'adminA', ajouteParNom: 'Plus A' })));
    await assertFails(addDoc(col, general('uid-plusA', { ajoutePar: '', ajouteParNom: 'Plus A' })));
  });

  test('employé : refusé (comme pour un chantier)', async () => {
    await assertFails(addDoc(materiel('uid-empA'),
      general('uid-plusA', { ajoutePar: 'empA', ajouteParNom: 'Emp A' })));
    await assertFails(getDocs(generalDe('uid-empA')));
  });

  test('chaque compagnie a son Général : pas de lecture ni d\'écriture croisée', async () => {
    await assertSucceeds(addDoc(materiel('uid-plusA'), general('uid-plusA')));
    await assertSucceeds(addDoc(materiel('uid-adminB'), general('uid-adminB', { companyId: 'B' })));
    await assertFails(addDoc(materiel('uid-plusA'), general('uid-plusA', { companyId: 'B' })));
    await assertFails(getDocs(generalDe('uid-plusA', 'B')));
    await assertFails(getDocs(generalDe('uid-adminB', 'A')));
  });

  test('toujours les mêmes contrôles : texte vide, déjà complété, champ inconnu, date falsifiée', async () => {
    const col = materiel('uid-plusA');
    await assertFails(addDoc(col, general('uid-plusA', { texte: '' })));
    await assertFails(addDoc(col, general('uid-plusA', { complete: true })));
    await assertFails(addDoc(col, general('uid-plusA', { admin: true })));
    await assertFails(addDoc(col, general('uid-plusA', { dateAjout: new Date('2020-01-01') })));
  });

  test('un autre identifiant inventé reste refusé (seul « _general » est permis)', async () => {
    for (const id of ['general', '_General', '_autre', '', 'chB']) {
      await assertFails(addDoc(materiel('uid-plusA'), general('uid-plusA', { chantierId: id })));
    }
  });

  test('pas un chantier : refusé pour travaux, extras et photos', async () => {
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'chantier_travaux'), general('uid-plusA')));
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'chantier_extras'), {
      companyId: 'A', chantierId: '_general', description: 'x', mainOeuvre: '1 gars',
      dateTravaux: '2026-10-01', ajoutePar: 'plusA', ajouteParNom: 'Plus A', dateAjout: serverTimestamp(),
    }));
    await assertFails(addDoc(collection(ctxDe('uid-plusA'), 'chantier_photos'), {
      companyId: 'A', chantierId: '_general',
      url: 'https://firebasestorage.googleapis.com/v0/b/x/o/p.jpg',
      cheminStorage: 'chantiers/A/_general/photos/p.jpg', dateAjout: serverTimestamp(),
    }));
  });

  test('un chantier ordinaire ne prend pas les champs « auteur » (inchangé)', async () => {
    const entree = { companyId: 'A', chantierId: 'chA', texte: 'Clous', complete: false, dateAjout: serverTimestamp() };
    await assertSucceeds(addDoc(materiel('uid-plusA'), entree));
    await assertFails(addDoc(materiel('uid-plusA'), { ...entree, ...AUTEURS['uid-plusA'] }));
  });

  describe('qui a changé quoi, et quand (dateModif, modifiePar)', () => {
    const creer = async () => addDoc(materiel('uid-plusA'), general('uid-plusA'));

    test('chaque personne signe sa modification avec l\'heure du serveur', async () => {
      const ref = await assertSucceeds(creer());
      // L'admin marque « obtenu » (acheté) la demande du contremaître.
      const refAdmin = doc(ctxDe('uid-adminA'), ref.path);
      await assertSucceeds(updateDoc(refAdmin, {
        complete: true, dateComplete: serverTimestamp(), dateModif: serverTimestamp(), modifiePar: 'adminA',
      }));
      // Le contremaître modifie ensuite : modifiePar change, dateModif aussi.
      await assertSucceeds(updateDoc(doc(ctxDe('uid-plusA'), ref.path), {
        texte: 'Sangles 2 po', dateModif: serverTimestamp(), modifiePar: 'plusA',
      }));
    });

    test('refusé : signer au nom d\'un autre, fausse date, modifiePar seul', async () => {
      const ref = await assertSucceeds(creer());
      const r = doc(ctxDe('uid-plusA'), ref.path);
      await assertFails(updateDoc(r, { texte: 'x', dateModif: serverTimestamp(), modifiePar: 'adminA' }));
      await assertFails(updateDoc(r, { texte: 'x', dateModif: new Date('2020-01-01'), modifiePar: 'plusA' }));
      await assertFails(updateDoc(r, { texte: 'x', modifiePar: 'plusA' }));
      await assertFails(updateDoc(r, { texte: 'x', dateModif: serverTimestamp() }));
    });

    test('refusé : changer l\'auteur ou le chantier d\'une entrée existante', async () => {
      const ref = await assertSucceeds(creer());
      const r = doc(ctxDe('uid-adminA'), ref.path);
      await assertFails(updateDoc(r, { ajoutePar: 'adminA', ajouteParNom: 'Admin A' }));
      await assertFails(updateDoc(r, { chantierId: 'chA' }));
    });

    test('refusé ailleurs : un chantier ordinaire ou un travail ne porte pas dateModif', async () => {
      const r = doc(ctxDe('uid-plusA'), 'chantier_travaux/tA');
      await assertFails(updateDoc(r, { texte: 'x', dateModif: serverTimestamp(), modifiePar: 'plusA' }));
    });
  });

  test('« _general » ne peut pas devenir un vrai chantier (il paraîtrait dans les heures)', async () => {
    const admin = ctxDe('uid-adminA');
    await assertFails(setDoc(doc(admin, 'chantiers/_general'),
      { companyId: 'A', nom: 'Général', adresse: '' }));
    // Un chantier ordinaire se crée toujours.
    await assertSucceeds(setDoc(doc(admin, 'chantiers/nouveauA'),
      { companyId: 'A', nom: 'Chalet', adresse: '' }));
  });
});

// =============================================================================
describe('Matériel Général : ce que chaque admin a déjà vu (pastille)', () => {
  const vus = (over = {}) => ({ companyId: 'A', vus: { plusA: serverTimestamp() }, ...over });
  const ref = (uid, id) => doc(ctxDe(uid), `materiel_general_vus/${id}`);

  test('un admin lit et écrit SON document (même s\'il n\'existe pas encore)', async () => {
    await assertSucceeds(getDoc(ref('uid-adminA', 'adminA')));
    await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'), vus(), { merge: true }));
    await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'),
      { companyId: 'A', vus: { adminA: serverTimestamp() } }, { merge: true }));
    await assertSucceeds(getDoc(ref('uid-adminA', 'adminA')));
  });

  test('pas celui d\'un autre admin, ni d\'une autre compagnie', async () => {
    await assertFails(getDoc(ref('uid-adminA', 'superA')));
    await assertFails(setDoc(ref('uid-adminA', 'superA'), vus()));
    await assertFails(setDoc(ref('uid-adminA', 'adminA'), vus({ companyId: 'B' })));
    await assertFails(setDoc(ref('uid-adminB', 'adminA'), vus({ companyId: 'B' })));
  });

  test('contremaître et employé : aucun accès (c\'est une vue d\'admin)', async () => {
    await assertFails(getDoc(ref('uid-plusA', 'plusA')));
    await assertFails(setDoc(ref('uid-plusA', 'plusA'), vus()));
    await assertFails(getDoc(ref('uid-empA', 'empA')));
    await assertFails(setDoc(ref('uid-empA', 'empA'), vus()));
  });

  test('forme imposée : champs connus, « vus » est une table, jamais supprimé', async () => {
    await assertFails(setDoc(ref('uid-adminA', 'adminA'), vus({ extra: 1 })));
    await assertFails(setDoc(ref('uid-adminA', 'adminA'), vus({ vus: 'oui' })));
    await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'), vus()));
    await assertFails(deleteDoc(ref('uid-adminA', 'adminA')));
  });
});

// =============================================================================
describe('Extras (saisie : admin et contremaître ; suppression : admin)', () => {
  const extra = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', description: 'Ajout d\'une cloison',
    mainOeuvre: '3 gars, 1 compagnon, 1 apprenti — 4 h', dateTravaux: '2026-10-01',
    ajoutePar: 'plusA', ajouteParNom: 'Plus A', dateAjout: serverTimestamp(), ...over,
  });
  const PHOTO = {
    photoUrl: 'https://firebasestorage.googleapis.com/v0/b/chantierplus-mtl/o/e.jpg',
    cheminPhoto: 'chantiers/A/chA/chantier_extras/123_e.jpg',
  };
  const col = (uid) => collection(ctxDe(uid), 'chantier_extras');
  const seme = async (id = 'ex1') => env.withSecurityRulesDisabled((c) =>
    setDoc(doc(c.firestore(), 'chantier_extras', id), { ...extra(), dateAjout: new Date() }));

  test('contremaître et admin créent un extra ; employé et autre compagnie refusés', async () => {
    await assertSucceeds(addDoc(col('uid-plusA'), extra()));
    await assertSucceeds(addDoc(col('uid-adminA'), extra({ ajoutePar: 'adminA', ajouteParNom: 'Admin A' })));
    await assertFails(addDoc(col('uid-empA'), extra({ ajoutePar: 'empA', ajouteParNom: 'Emp A' })));
    await assertFails(addDoc(col('uid-adminB'), extra()));
  });

  test('photo facultative : acceptée avec son chemin, refusée sinon', async () => {
    await assertSucceeds(addDoc(col('uid-plusA'), extra(PHOTO)));
    await assertFails(addDoc(col('uid-plusA'), extra({ photoUrl: PHOTO.photoUrl })));
    await assertFails(addDoc(col('uid-plusA'), extra({ cheminPhoto: PHOTO.cheminPhoto })));
    await assertFails(addDoc(col('uid-plusA'), extra({ ...PHOTO, photoUrl: 'https://exemple.com/x.jpg' })));
    await assertFails(addDoc(col('uid-plusA'), extra({ ...PHOTO, cheminPhoto: 'chantiers/B/chB/chantier_extras/x.jpg' })));
    await assertFails(addDoc(col('uid-plusA'), extra({ ...PHOTO, cheminPhoto: 'chantiers/A/chA/photos/x.jpg' })));
    await assertFails(addDoc(col('uid-plusA'), extra({ ...PHOTO, cheminPhoto: 'chantiers/A/chA/chantier_extras/../x.jpg/y' })));
  });

  test('main-d\'œuvre en texte libre ; valeurs invalides refusées (vide, trop long, date, description, champs inconnus)', async () => {
    const c = col('uid-plusA');
    await assertSucceeds(addDoc(c, extra({ mainOeuvre: '1 gars' })));
    await assertSucceeds(addDoc(c, extra({ mainOeuvre: 'x'.repeat(300) })));
    for (const mauvais of [
      { mainOeuvre: '' }, { mainOeuvre: 'x'.repeat(301) }, { mainOeuvre: 3 }, { mainOeuvre: null },
      { nombreHommes: 2 }, { heures: 3.5 },
      { dateTravaux: '2026-1-5' }, { dateTravaux: 20261001 },
      { description: '' }, { description: 'x'.repeat(2001) },
      { bonus: 1 }, { chantierId: 'chB' }, { companyId: 'B' },
    ]) {
      await assertFails(addDoc(c, extra(mauvais)));
    }
  });

  test('l\'auteur est celui de la session : pas de faux nom ni de faux identifiant', async () => {
    await assertFails(addDoc(col('uid-plusA'), extra({ ajoutePar: 'adminA' })));
    await assertFails(addDoc(col('uid-plusA'), extra({ ajouteParNom: 'Quelqu\'un d\'autre' })));
    await assertFails(addDoc(col('uid-plusA'), extra({ dateAjout: new Date('2020-01-01') })));
  });

  test('lecture : admin et contremaître de la compagnie seulement', async () => {
    await seme();
    await assertSucceeds(getDoc(doc(ctxDe('uid-plusA'), 'chantier_extras/ex1')));
    await assertSucceeds(getDoc(doc(ctxDe('uid-adminA'), 'chantier_extras/ex1')));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'chantier_extras/ex1')));
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'chantier_extras/ex1')));
    await assertFails(getDocs(query(collection(ctxDe('uid-empA'), 'chantier_extras'), where('companyId', '==', 'A'))));
    await assertFails(getDocs(query(collection(ctxDe('uid-adminB'), 'chantier_extras'), where('companyId', '==', 'A'))));
  });

  test('modification : contenu seulement, jamais l\'auteur, le chantier ou la compagnie', async () => {
    await seme();
    const ref = (uid) => doc(ctxDe(uid), 'chantier_extras/ex1');
    await assertSucceeds(updateDoc(ref('uid-plusA'), { description: 'Corrigé', mainOeuvre: '4 gars, 5 h' }));
    await assertSucceeds(updateDoc(ref('uid-adminA'), { ...PHOTO }));
    await assertSucceeds(updateDoc(ref('uid-adminA'), { photoUrl: deleteField(), cheminPhoto: deleteField() }));
    await assertFails(updateDoc(ref('uid-plusA'), { ajoutePar: 'adminA' }));
    await assertFails(updateDoc(ref('uid-plusA'), { chantierId: 'chB' }));
    await assertFails(updateDoc(ref('uid-plusA'), { companyId: 'B' }));
    await assertFails(updateDoc(ref('uid-plusA'), { mainOeuvre: '' }));
    await assertFails(updateDoc(ref('uid-plusA'), { nombreHommes: 3 }));
    await assertFails(updateDoc(ref('uid-plusA'), { photoUrl: PHOTO.photoUrl }));
    await assertFails(updateDoc(ref('uid-empA'), { description: 'Piraté' }));
    await assertFails(updateDoc(ref('uid-adminB'), { description: 'Piraté' }));
  });

  test('suppression : admin seulement', async () => {
    await seme();
    const ref = (uid) => doc(ctxDe(uid), 'chantier_extras/ex1');
    await assertFails(deleteDoc(ref('uid-plusA')));
    await assertFails(deleteDoc(ref('uid-empA')));
    await assertFails(deleteDoc(ref('uid-adminB')));
    await assertSucceeds(deleteDoc(ref('uid-adminA')));
  });
});

// =============================================================================
describe('Commandes de matériaux (création et suivi : admin et contremaître)', () => {
  const ligne = { categorie: 'bois', article: "2×10 × 12'", quantite: 12, unite: '', usage: 'Plancher', manuelle: false };
  const commande = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', nom: 'Plancher Tremblay',
    lignes: [ligne], projet: '{"v":1}', statut: 'brouillon',
    ajoutePar: 'plusA', ajouteParNom: 'Plus A', dateAjout: serverTimestamp(), ...over,
  });
  const col = (uid) => collection(ctxDe(uid), 'chantier_commandes');
  const seme = async (id = 'cmd1', over = {}) => env.withSecurityRulesDisabled((c) =>
    setDoc(doc(c.firestore(), 'chantier_commandes', id), { ...commande(), dateAjout: new Date(), ...over }));

  test('contremaître et admin enregistrent une commande ; employé et autre compagnie refusés', async () => {
    await assertSucceeds(addDoc(col('uid-plusA'), commande()));
    await assertSucceeds(addDoc(col('uid-adminA'), commande({ ajoutePar: 'adminA', ajouteParNom: 'Admin A' })));
    await assertFails(addDoc(col('uid-empA'), commande({ ajoutePar: 'empA', ajouteParNom: 'Emp A' })));
    await assertFails(addDoc(col('uid-adminB'), commande()));
  });

  test('valeurs invalides refusées (statut, lignes, nom, projet, champs inconnus, chantier d’une autre compagnie)', async () => {
    const c = col('uid-plusA');
    const { projet: _omis, ...sansProjet } = commande();
    await assertSucceeds(addDoc(c, sansProjet));
    await assertSucceeds(addDoc(c, commande({ lignes: Array.from({ length: 300 }, () => ligne) })));
    await assertSucceeds(addDoc(c, commande({ projet: 'x'.repeat(150000) })));
    for (const mauvais of [
      { statut: 'commandee' }, { statut: 'recue' }, { statut: 'autre' },
      { lignes: [] }, { lignes: 'beaucoup' }, { lignes: Array.from({ length: 301 }, () => ligne) },
      { nom: '' }, { nom: 'x'.repeat(201) }, { nom: 3 },
      { projet: 'x'.repeat(150001) }, { projet: { v: 1 } },
      { notes: 'x'.repeat(2001) }, { fournisseur: 'x'.repeat(201) },
      { total: 100 }, { dateCommande: new Date() },
      { chantierId: 'chB' }, { companyId: 'B' },
    ]) {
      await assertFails(addDoc(c, commande(mauvais)));
    }
  });

  test('l’auteur est celui de la session', async () => {
    await assertFails(addDoc(col('uid-plusA'), commande({ ajoutePar: 'adminA' })));
    await assertFails(addDoc(col('uid-plusA'), commande({ ajouteParNom: "Quelqu'un d'autre" })));
    await assertFails(addDoc(col('uid-plusA'), commande({ dateAjout: new Date('2020-01-01') })));
  });

  test('lecture : admin et contremaître de la compagnie seulement', async () => {
    await seme();
    await assertSucceeds(getDoc(doc(ctxDe('uid-plusA'), 'chantier_commandes/cmd1')));
    await assertSucceeds(getDoc(doc(ctxDe('uid-adminA'), 'chantier_commandes/cmd1')));
    await assertFails(getDoc(doc(ctxDe('uid-empA'), 'chantier_commandes/cmd1')));
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'chantier_commandes/cmd1')));
    await assertSucceeds(getDocs(query(collection(ctxDe('uid-plusA'), 'chantier_commandes'),
      where('companyId', '==', 'A'), where('chantierId', '==', 'chA'))));
    await assertFails(getDocs(query(collection(ctxDe('uid-empA'), 'chantier_commandes'), where('companyId', '==', 'A'))));
    await assertFails(getDocs(query(collection(ctxDe('uid-adminB'), 'chantier_commandes'), where('companyId', '==', 'A'))));
  });

  test('suivi : statut, notes, fournisseur, nom et date de commande ; jamais les lignes ni l’auteur', async () => {
    await seme();
    const ref = (uid) => doc(ctxDe(uid), 'chantier_commandes/cmd1');
    await assertSucceeds(updateDoc(ref('uid-plusA'), { statut: 'commandee', dateCommande: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref('uid-adminA'), { statut: 'recue', notes: 'Livré mardi', fournisseur: 'BMR Laval' }));
    await assertSucceeds(updateDoc(ref('uid-plusA'), { nom: 'Plancher Tremblay (v2)' }));
    await assertFails(updateDoc(ref('uid-plusA'), { lignes: [] }));
    await assertFails(updateDoc(ref('uid-plusA'), { lignes: [{ ...ligne, quantite: 99 }] }));
    await assertFails(updateDoc(ref('uid-plusA'), { projet: '{}' }));
    await assertFails(updateDoc(ref('uid-plusA'), { ajoutePar: 'adminA' }));
    await assertFails(updateDoc(ref('uid-plusA'), { chantierId: 'chB' }));
    await assertFails(updateDoc(ref('uid-plusA'), { companyId: 'B' }));
    await assertFails(updateDoc(ref('uid-plusA'), { statut: 'perdue' }));
    await assertFails(updateDoc(ref('uid-plusA'), { dateCommande: new Date('2020-01-01') }));
    await assertFails(updateDoc(ref('uid-plusA'), { notes: 'x'.repeat(2001) }));
    await assertFails(updateDoc(ref('uid-empA'), { statut: 'commandee' }));
    await assertFails(updateDoc(ref('uid-adminB'), { statut: 'commandee' }));
  });

  test('suppression : admin toujours ; contremaître seulement un brouillon', async () => {
    await seme('brouillon1', { statut: 'brouillon' });
    await seme('commandee1', { statut: 'commandee' });
    const ref = (uid, id) => doc(ctxDe(uid), 'chantier_commandes/' + id);
    await assertFails(deleteDoc(ref('uid-empA', 'brouillon1')));
    await assertFails(deleteDoc(ref('uid-adminB', 'brouillon1')));
    await assertFails(deleteDoc(ref('uid-plusA', 'commandee1')));
    await assertSucceeds(deleteDoc(ref('uid-plusA', 'brouillon1')));
    await assertSucceeds(deleteDoc(ref('uid-adminA', 'commandee1')));
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
        'reinitialisations_nip/empA', 'invitations_nip/empA', 'config/securite',
        'journal_suppressions/A']) {
        await assertFails(getDoc(doc(d, chemin)));
        await assertFails(setDoc(doc(d, chemin), { a: 1 }));
      }
    }
  });

  test('collection inconnue → refusée', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-adminA'), 'autre/x'), { a: 1 }));
  });
});
