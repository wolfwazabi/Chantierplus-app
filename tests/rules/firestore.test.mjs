import assert from 'node:assert/strict';
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

  describe('anciens employés (actif: false)', () => {
    const lire = (uid) => getDocs(query(collection(ctxDe(uid), 'chantiers'), where('companyId', '==', 'A')));
    const fiche = (employeeId, donnees) => env.withSecurityRulesDisabled((c) =>
      updateDoc(doc(c.firestore(), `employees/${employeeId}`), donnees));

    test("un employé retiré (actif: false) n'a plus aucun accès, même avec sa session", async () => {
      await assertSucceeds(lire('uid-adminA'));
      await fiche('adminA', { actif: false });
      await assertFails(lire('uid-adminA'));
      await assertFails(getDoc(doc(ctxDe('uid-adminA'), 'companies/A')));
      await assertFails(addDoc(collection(ctxDe('uid-adminA'), 'chantier_travaux'),
        { companyId: 'A', chantierId: 'chA', texte: 'Coffrage', complete: false, dateAjout: serverTimestamp() }));
      await assertFails(getDoc(doc(ctxDe('uid-adminA'), 'employees/plusA')));
      // Les autres employés de la compagnie ne sont pas touchés.
      await assertSucceeds(lire('uid-superA'));
      await assertSucceeds(getDoc(doc(ctxDe('uid-plusA'), 'employees/plusA')));
    });

    test('réactivé (actif: true) ou sans le champ (employés existants) : accès normal', async () => {
      await fiche('adminA', { actif: true });
      await assertSucceeds(lire('uid-adminA'));
      await assertSucceeds(getDoc(doc(ctxDe('uid-adminA'), 'companies/A')));
      await assertSucceeds(lire('uid-superA'));
    });

    test("contremaître et employé retirés : plus d'accès non plus", async () => {
      await fiche('plusA', { actif: false });
      await fiche('empA', { actif: false });
      await assertFails(getDoc(doc(ctxDe('uid-plusA'), 'companies/A')));
      await assertFails(getDoc(doc(ctxDe('uid-empA'), 'companies/A')));
      await assertFails(getDoc(doc(ctxDe('uid-empA'), 'sessions/uid-adminA')));
    });
  });

  describe("expiration (sessions de l'espace web : expireLe)", () => {
    const sessionAvec = (uid, expireLe, extra = {}) => env.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), `sessions/${uid}`),
        { employeeId: 'adminA', companyId: 'A', canal: 'web', expireLe, ...extra }));
    const heures = (h) => new Date(Date.now() + h * 3600 * 1000);
    const accede = async (uid) => {
      await assertSucceeds(getDocs(query(collection(ctxDe(uid), 'chantiers'), where('companyId', '==', 'A'))));
      await assertSucceeds(getDoc(doc(ctxDe(uid), 'companies/A')));
    };
    const refuse = async (uid) => {
      await assertFails(getDocs(query(collection(ctxDe(uid), 'chantiers'), where('companyId', '==', 'A'))));
      await assertFails(getDoc(doc(ctxDe(uid), 'companies/A')));
      await assertFails(addDoc(collection(ctxDe(uid), 'chantier_travaux'),
        { companyId: 'A', chantierId: 'chA', texte: 'Coffrage', complete: false, dateAjout: serverTimestamp() }));
    };

    test('expireLe dans le futur → accès normal (lecture et écriture)', async () => {
      await sessionAvec('uid-web', heures(11));
      await accede('uid-web');
      await assertSucceeds(addDoc(collection(ctxDe('uid-web'), 'chantier_travaux'),
        { companyId: 'A', chantierId: 'chA', texte: 'Coffrage', complete: false, dateAjout: serverTimestamp() }));
    });

    test('expireLe dépassé → plus aucun accès (lecture, liste, écriture)', async () => {
      await sessionAvec('uid-web', heures(-0.01));
      await refuse('uid-web');
      await sessionAvec('uid-web2', heures(-12));
      await refuse('uid-web2');
    });

    test('expireLe illisible (texte, nombre, null) → refusé, jamais « sans limite »', async () => {
      for (const [uid, v] of [['uid-w1', 'demain'], ['uid-w2', 12], ['uid-w3', null]]) {
        await sessionAvec(uid, v);
        await refuse(uid);
      }
    });

    test("session de l'application (sans expireLe) → reste valide, comme avant", async () => {
      await accede('uid-adminA');
    });

    test("l'expiration coupe aussi le Proprio de l'app et ses accès particuliers", async () => {
      await sessionAvec('uid-webproprio', heures(-1), { employeeId: 'superA' });
      await assertFails(getDocs(collection(ctxDe('uid-webproprio'), 'companies')));
      await sessionAvec('uid-webproprio2', heures(2), { employeeId: 'superA' });
      await assertSucceeds(getDocs(collection(ctxDe('uid-webproprio2'), 'companies')));
    });
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
  // Un contremaître doit demander SA liste (where ajoutePar == lui) ; un admin, tout.
  const generalDe = (uid, companyId = 'A', auteur = null) => query(collection(ctxDe(uid), 'chantier_materiel'),
    where('companyId', '==', companyId), where('chantierId', '==', '_general'),
    ...(auteur ? [where('ajoutePar', '==', auteur)] : []));

  test('contremaître et admin : ajoutent, lisent, complètent, modifient, suppriment', async () => {
    for (const uid of ['uid-plusA', 'uid-adminA']) {
      const ref = await assertSucceeds(addDoc(materiel(uid), general(uid)));
      await assertSucceeds(getDocs(generalDe(uid, 'A', uid === 'uid-plusA' ? 'plusA' : null)));
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

  test("un chantier ordinaire : l'auteur est facultatif (fil Activité), mais jamais au nom d'un autre", async () => {
    const entree = { companyId: 'A', chantierId: 'chA', texte: 'Clous', complete: false, dateAjout: serverTimestamp() };
    await assertSucceeds(addDoc(materiel('uid-plusA'), entree));
    await assertSucceeds(addDoc(materiel('uid-plusA'), { ...entree, ...AUTEURS['uid-plusA'] }));
    await assertFails(addDoc(materiel('uid-plusA'), { ...entree, ...AUTEURS['uid-adminA'] }));
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
describe('Matériel Général : un contremaître ne voit que SA liste', () => {
  const entree = (auteur, nom, over = {}) => ({
    companyId: 'A', chantierId: '_general', texte: 'Demande de ' + nom, complete: false,
    ajoutePar: auteur, ajouteParNom: nom, dateAjout: new Date('2026-10-05'), ...over,
  });
  const semerGeneral = async () => env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, 'chantier_materiel/gPlus'), entree('plusA', 'Plus A'));
    await setDoc(doc(d, 'chantier_materiel/gAdmin'), entree('adminA', 'Admin A'));
    await setDoc(doc(d, 'chantier_materiel/gB'), entree('adminB', 'Admin B', { companyId: 'B' }));
    await setDoc(doc(d, 'chantier_materiel/mChantier'),
      { companyId: 'A', chantierId: 'chA', texte: 'Clous', complete: false, dateAjout: new Date('2026-10-05') });
  });
  beforeEach(semerGeneral);
  const requete = (uid, ...contraintes) => query(collection(ctxDe(uid), 'chantier_materiel'),
    where('companyId', '==', 'A'), where('chantierId', '==', '_general'), ...contraintes);

  test('contremaître : sa propre liste seulement', async () => {
    await assertSucceeds(getDocs(requete('uid-plusA', where('ajoutePar', '==', 'plusA'))));
    await assertSucceeds(getDoc(doc(ctxDe('uid-plusA'), 'chantier_materiel/gPlus')));
  });

  test('contremaître : refusé s\'il demande toute la liste ou celle d\'un autre', async () => {
    await assertFails(getDocs(requete('uid-plusA')));
    await assertFails(getDocs(requete('uid-plusA', where('ajoutePar', '==', 'adminA'))));
    await assertFails(getDoc(doc(ctxDe('uid-plusA'), 'chantier_materiel/gAdmin')));
  });

  test('contremaître : ne modifie ni ne supprime la demande d\'un autre, mais gère la sienne', async () => {
    const d = ctxDe('uid-plusA');
    await assertFails(updateDoc(doc(d, 'chantier_materiel/gAdmin'), { texte: 'Piraté' }));
    await assertFails(updateDoc(doc(d, 'chantier_materiel/gAdmin'),
      { complete: true, dateComplete: serverTimestamp() }));
    await assertFails(deleteDoc(doc(d, 'chantier_materiel/gAdmin')));
    await assertSucceeds(updateDoc(doc(d, 'chantier_materiel/gPlus'),
      { texte: 'Corrigé', dateModif: serverTimestamp(), modifiePar: 'plusA' }));
    await assertSucceeds(deleteDoc(doc(d, 'chantier_materiel/gPlus')));
  });

  test('admin : voit tout le monde, modifie et supprime n\'importe quelle demande', async () => {
    const d = ctxDe('uid-adminA');
    await assertSucceeds(getDocs(requete('uid-adminA')));
    await assertSucceeds(getDoc(doc(d, 'chantier_materiel/gPlus')));
    await assertSucceeds(updateDoc(doc(d, 'chantier_materiel/gPlus'),
      { complete: true, dateComplete: serverTimestamp(), dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertSucceeds(deleteDoc(doc(d, 'chantier_materiel/gPlus')));
  });

  test('autre compagnie : aucune liste Général de A, même pour un admin', async () => {
    await assertFails(getDocs(requete('uid-adminB')));
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'chantier_materiel/gPlus')));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'chantier_materiel/gPlus')));
  });

  test('un chantier ordinaire : le contremaître lit toujours tout (inchangé)', async () => {
    const d = ctxDe('uid-plusA');
    await assertSucceeds(getDocs(query(collection(d, 'chantier_materiel'),
      where('companyId', '==', 'A'), where('chantierId', '==', 'chA'))));
    await assertSucceeds(getDoc(doc(d, 'chantier_materiel/mChantier')));
    await assertSucceeds(updateDoc(doc(d, 'chantier_materiel/mChantier'), { texte: 'Clous 3 po' }));
    await assertSucceeds(deleteDoc(doc(d, 'chantier_materiel/mChantier')));
  });
});

// =============================================================================
describe('Matériel Général : transfert à la Liste d\'achats (la demande reste visible)', () => {
  const entree = (auteur, nom, over = {}) => ({
    companyId: 'A', chantierId: '_general', texte: 'Demande de ' + nom, complete: false,
    ajoutePar: auteur, ajouteParNom: nom, dateAjout: new Date('2026-10-05'), ...over,
  });
  const marque = (over = {}) => ({
    transfere: true, transfereParNom: 'Admin A', dateModif: serverTimestamp(), modifiePar: 'adminA', ...over,
  });
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const d = c.firestore();
      await setDoc(doc(d, 'chantier_materiel/gPlus'), entree('plusA', 'Plus A'));
      await setDoc(doc(d, 'chantier_materiel/gPlusT'), entree('plusA', 'Plus A', { transfere: true, transfereParNom: 'Admin A' }));
      await setDoc(doc(d, 'chantier_materiel/mChantier'),
        { companyId: 'A', chantierId: 'chA', texte: 'Clous', complete: false, dateAjout: new Date('2026-10-05') });
    });
  });
  const admin = () => ctxDe('uid-adminA');
  const plus = () => ctxDe('uid-plusA');

  test('un admin transfère : la demande est marquée (nom + signature)', async () => {
    await assertSucceeds(updateDoc(doc(admin(), 'chantier_materiel/gPlus'), marque()));
  });

  test('refusé : nom d\'un autre, valeur fausse, un seul des deux champs, signature d\'un autre', async () => {
    const r = doc(admin(), 'chantier_materiel/gPlus');
    await assertFails(updateDoc(r, marque({ transfereParNom: 'Quelqu\'un d\'autre' })));
    await assertFails(updateDoc(r, marque({ transfere: false })));
    await assertFails(updateDoc(r, marque({ transfere: 'oui' })));
    await assertFails(updateDoc(r, { transfere: true, dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertFails(updateDoc(r, { transfereParNom: 'Admin A', dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertFails(updateDoc(r, marque({ modifiePar: 'plusA' })));
  });

  test('un contremaître ne peut pas transférer, même sa propre demande', async () => {
    await assertFails(updateDoc(doc(plus(), 'chantier_materiel/gPlus'),
      marque({ transfereParNom: 'Plus A', modifiePar: 'plusA' })));
  });

  test('pas pour un chantier ordinaire (Général seulement)', async () => {
    await assertFails(updateDoc(doc(admin(), 'chantier_materiel/mChantier'), marque()));
  });

  test('la demande transférée reste visible pour son auteur', async () => {
    await assertSucceeds(getDoc(doc(plus(), 'chantier_materiel/gPlusT')));
    await assertSucceeds(getDocs(query(collection(plus(), 'chantier_materiel'),
      where('companyId', '==', 'A'), where('chantierId', '==', '_general'), where('ajoutePar', '==', 'plusA'))));
  });

  test('mais le contremaître ne la modifie, ne la marque faite ni ne la supprime plus', async () => {
    const r = doc(plus(), 'chantier_materiel/gPlusT');
    await assertFails(updateDoc(r, { texte: 'Autre chose', dateModif: serverTimestamp(), modifiePar: 'plusA' }));
    await assertFails(updateDoc(r, { complete: true, dateComplete: serverTimestamp(), dateModif: serverTimestamp(), modifiePar: 'plusA' }));
    await assertFails(deleteDoc(r));
    // Sa demande non transférée reste entièrement à lui.
    await assertSucceeds(updateDoc(doc(plus(), 'chantier_materiel/gPlus'),
      { texte: 'Corrigé', dateModif: serverTimestamp(), modifiePar: 'plusA' }));
    await assertSucceeds(deleteDoc(doc(plus(), 'chantier_materiel/gPlus')));
  });

  test('l\'admin marque la demande transférée faite (achetée), la modifie ou la supprime', async () => {
    const r = doc(admin(), 'chantier_materiel/gPlusT');
    await assertSucceeds(updateDoc(r, {
      complete: true, dateComplete: serverTimestamp(), dateModif: serverTimestamp(), modifiePar: 'adminA',
    }));
    await assertSucceeds(updateDoc(r, { complete: false, dateComplete: deleteField(), dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertSucceeds(deleteDoc(r));
  });

  test('l\'admin retire le transfert (les deux champs ensemble)', async () => {
    const r = doc(admin(), 'chantier_materiel/gPlusT');
    await assertFails(updateDoc(r, { transfere: deleteField(), dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertFails(updateDoc(r, { transfereParNom: deleteField(), dateModif: serverTimestamp(), modifiePar: 'adminA' }));
    await assertSucceeds(updateDoc(r, {
      transfere: deleteField(), transfereParNom: deleteField(), dateModif: serverTimestamp(), modifiePar: 'adminA',
    }));
    // Redevenue ordinaire : son auteur la gère de nouveau.
    await assertSucceeds(updateDoc(doc(plus(), 'chantier_materiel/gPlusT'),
      { texte: 'Repris', dateModif: serverTimestamp(), modifiePar: 'plusA' }));
  });

  test('un contremaître ne peut pas retirer lui-même le transfert', async () => {
    await assertFails(updateDoc(doc(plus(), 'chantier_materiel/gPlusT'), {
      transfere: deleteField(), transfereParNom: deleteField(), dateModif: serverTimestamp(), modifiePar: 'plusA',
    }));
  });

  test('Liste d\'achats : le lien vers la demande d\'origine est accepté, valide seulement', async () => {
    const article = (over = {}) => ({
      companyId: 'A', texte: 'Demande de Plus A', demandeParId: 'plusA', demandeParNom: 'Plus A',
      transfereParId: 'adminA', transfereParNom: 'Admin A', origine: 'general', complete: false,
      dateAjout: serverTimestamp(), ...over,
    });
    const col = collection(admin(), 'liste_achats');
    await assertSucceeds(addDoc(col, article({ origineId: 'gPlus' })));
    await assertSucceeds(addDoc(col, article()));
    await assertFails(addDoc(col, article({ origineId: '' })));
    await assertFails(addDoc(col, article({ origineId: 12 })));
    await assertFails(addDoc(col, article({ origineId: 'x'.repeat(129) })));
  });
});

// =============================================================================
describe('Matériel Général : demandes marquées « non lu » (nonLus)', () => {
  const ref = (uid, id) => doc(ctxDe(uid), `materiel_general_vus/${id}`);

  test('l\'admin garde ses drapeaux dans son document', async () => {
    await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'),
      { companyId: 'A', nonLus: { demande1: true, demande2: true } }, { merge: true }));
    await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'),
      { companyId: 'A', vus: { plusA: serverTimestamp() }, nonLus: { demande1: deleteField() } }, { merge: true }));
    const lu = (await getDoc(ref('uid-adminA', 'adminA'))).data();
    assert.deepEqual(lu.nonLus, { demande2: true });
  });

  test('forme imposée : « nonLus » est une table', async () => {
    await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', nonLus: 'oui' }));
    await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', nonLus: ['a'] }));
  });

  test('pas pour un contremaître, ni dans le document d\'un autre admin', async () => {
    await assertFails(setDoc(ref('uid-plusA', 'plusA'), { companyId: 'A', nonLus: { x: true } }));
    await assertFails(setDoc(ref('uid-adminA', 'superA'), { companyId: 'A', nonLus: { x: true } }));
  });
});

// =============================================================================
describe('Liste d\'achats (admin seulement)', () => {
  const article = (over = {}) => ({
    companyId: 'A', texte: 'Sangles à cliquet', quantite: '4', demandeParId: 'plusA', demandeParNom: 'Plus A',
    transfereParId: 'adminA', transfereParNom: 'Admin A', origine: 'general', complete: false,
    dateAjout: serverTimestamp(), ...over,
  });
  const col = (uid) => collection(ctxDe(uid), 'liste_achats');
  const semerArticle = async (id = 'art1', over = {}) => env.withSecurityRulesDisabled((c) =>
    setDoc(doc(c.firestore(), 'liste_achats', id), { ...article(), dateAjout: new Date('2026-10-05'), ...over }));

  test('admin : crée (avec photo), lit, marque acheté, remet à acheter, supprime', async () => {
    const ref = await assertSucceeds(addDoc(col('uid-adminA'), article({
      photoUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/m.jpg',
    })));
    await assertSucceeds(getDocs(query(col('uid-adminA'), where('companyId', '==', 'A'))));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { complete: true, dateComplete: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { complete: false, dateComplete: deleteField() }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('contremaître et employé : aucun accès', async () => {
    await semerArticle();
    for (const uid of ['uid-plusA', 'uid-empA']) {
      // Signé correctement : seul le rôle l'empêche.
      const moi = uid === 'uid-plusA' ? { transfereParId: 'plusA', transfereParNom: 'Plus A' } : { transfereParId: 'empA', transfereParNom: 'Emp A' };
      await assertFails(addDoc(col(uid), article(moi)));
      await assertFails(getDocs(query(col(uid), where('companyId', '==', 'A'))));
      await assertFails(getDoc(doc(ctxDe(uid), 'liste_achats/art1')));
      await assertFails(updateDoc(doc(ctxDe(uid), 'liste_achats/art1'), { complete: true, dateComplete: serverTimestamp() }));
      await assertFails(deleteDoc(doc(ctxDe(uid), 'liste_achats/art1')));
    }
  });

  test('autre compagnie : refusé (lecture, écriture, suppression)', async () => {
    await semerArticle();
    await assertFails(getDocs(query(col('uid-adminB'), where('companyId', '==', 'A'))));
    await assertFails(getDoc(doc(ctxDe('uid-adminB'), 'liste_achats/art1')));
    await assertFails(addDoc(col('uid-adminB'), article({ companyId: 'A', transfereParId: 'adminB', transfereParNom: 'Admin B' })));
    await assertFails(deleteDoc(doc(ctxDe('uid-adminB'), 'liste_achats/art1')));
  });

  test('création refusée : signature d\'un autre, déjà acheté, date falsifiée, champ inconnu, texte vide, origine inconnue', async () => {
    const c = col('uid-adminA');
    await assertFails(addDoc(c, article({ transfereParId: 'superA' })));
    await assertFails(addDoc(c, article({ transfereParNom: 'Autre' })));
    await assertFails(addDoc(c, article({ complete: true })));
    await assertFails(addDoc(c, article({ dateAjout: new Date('2020-01-01') })));
    await assertFails(addDoc(c, article({ admin: true })));
    await assertFails(addDoc(c, article({ texte: '' })));
    await assertFails(addDoc(c, article({ origine: 'ailleurs' })));
    await assertFails(addDoc(c, article({ photoUrl: 'http://evil.example/x.jpg' })));
    await assertFails(addDoc(c, article({ demandeParId: 12 })));
  });

  test('modification : seulement acheté / pas acheté (pas le texte, pas la compagnie)', async () => {
    await semerArticle();
    const r = doc(ctxDe('uid-adminA'), 'liste_achats/art1');
    await assertFails(updateDoc(r, { texte: 'Autre chose' }));
    await assertFails(updateDoc(r, { companyId: 'B' }));
    await assertFails(updateDoc(r, { complete: true, dateComplete: new Date('2020-01-01') }));
    await assertFails(updateDoc(r, { complete: 'oui' }));
    await assertSucceeds(updateDoc(r, { complete: true, dateComplete: serverTimestamp() }));
  });
});

// =============================================================================
describe('Plusieurs photos par demande (travaux, matériel, Général, Liste d\'achats)', () => {
  const u = (n) => `https://firebasestorage.googleapis.com/v0/b/x/o/photo${n}.jpg`;
  const lot = (n) => Array.from({ length: n }, (_, k) => u(k + 1));
  const avecPhotos = (urls) => ({ photoUrl: urls[0], photoUrls: urls });
  const entree = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', texte: 'Clous', complete: false, dateAjout: serverTimestamp(), ...over,
  });
  const general = (uid, over = {}) => ({
    companyId: 'A', chantierId: '_general', texte: 'Sangles', complete: false, dateAjout: serverTimestamp(),
    ajoutePar: uid === 'uid-plusA' ? 'plusA' : 'adminA', ajouteParNom: uid === 'uid-plusA' ? 'Plus A' : 'Admin A', ...over,
  });
  const col = (uid, nom = 'chantier_materiel') => collection(ctxDe(uid), nom);

  test('1 à 6 photos acceptées (matériel d\'un chantier, travaux et Général)', async () => {
    for (const n of [1, 2, 3, 6]) {
      await assertSucceeds(addDoc(col('uid-plusA'), entree(avecPhotos(lot(n)))));
      await assertSucceeds(addDoc(col('uid-plusA', 'chantier_travaux'), entree(avecPhotos(lot(n)))));
      await assertSucceeds(addDoc(col('uid-plusA'), general('uid-plusA', avecPhotos(lot(n)))));
    }
  });

  test('l\'ancien format (photoUrl seule) reste accepté', async () => {
    await assertSucceeds(addDoc(col('uid-plusA'), entree({ photoUrl: u(1) })));
    await assertSucceeds(addDoc(col('uid-plusA'), general('uid-plusA', { photoUrl: u(1) })));
  });

  test('refusé : 7 photos, liste vide, pas une liste', async () => {
    await assertFails(addDoc(col('uid-plusA'), entree(avecPhotos(lot(7)))));
    await assertFails(addDoc(col('uid-plusA'), entree({ photoUrl: u(1), photoUrls: [] })));
    await assertFails(addDoc(col('uid-plusA'), entree({ photoUrl: u(1), photoUrls: u(1) })));
    await assertFails(addDoc(col('uid-plusA'), entree({ photoUrl: u(1), photoUrls: 'oui' })));
  });

  test('refusé : photoUrls sans photoUrl, ou photoUrl qui n\'est pas la première', async () => {
    await assertFails(addDoc(col('uid-plusA'), entree({ photoUrls: lot(2) })));
    await assertFails(addDoc(col('uid-plusA'), entree({ photoUrl: u(9), photoUrls: lot(2) })));
  });

  test('refusé : un lien qui n\'est pas Firebase Storage, à n\'importe quelle position', async () => {
    for (let k = 0; k < 6; k++) {
      const urls = lot(6);
      urls[k] = 'https://evil.example/x.jpg';
      await assertFails(addDoc(col('uid-plusA'), entree(avecPhotos(urls))), 'position ' + k);
    }
  });

  test('employé : refusé comme avant', async () => {
    await assertFails(addDoc(col('uid-empA'), entree(avecPhotos(lot(2)))));
  });

  test('modification : ajouter, retirer, tout retirer', async () => {
    const ref = await assertSucceeds(addDoc(col('uid-plusA'), entree(avecPhotos(lot(2)))));
    const r = doc(ctxDe('uid-plusA'), ref.path);
    await assertSucceeds(updateDoc(r, avecPhotos(lot(5))));
    await assertSucceeds(updateDoc(r, avecPhotos([u(2), u(4)])));
    await assertSucceeds(updateDoc(r, { photoUrl: deleteField(), photoUrls: deleteField() }));
    await assertFails(updateDoc(r, avecPhotos(lot(7))));
    await assertFails(updateDoc(r, { photoUrls: lot(2) }));
    await assertFails(updateDoc(r, { photoUrl: u(9), photoUrls: lot(3) }));
  });

  test('Général : modification signée avec plusieurs photos', async () => {
    const ref = await assertSucceeds(addDoc(col('uid-plusA'), general('uid-plusA', avecPhotos(lot(2)))));
    await assertSucceeds(updateDoc(doc(ctxDe('uid-plusA'), ref.path), {
      ...avecPhotos(lot(4)), dateModif: serverTimestamp(), modifiePar: 'plusA',
    }));
  });

  test('Liste d\'achats : les photos de la demande suivent (6 au plus, liens valides)', async () => {
    const article = (over = {}) => ({
      companyId: 'A', texte: 'Sangles', demandeParId: 'plusA', demandeParNom: 'Plus A',
      transfereParId: 'adminA', transfereParNom: 'Admin A', origine: 'general', complete: false,
      dateAjout: serverTimestamp(), ...over,
    });
    const c = collection(ctxDe('uid-adminA'), 'liste_achats');
    await assertSucceeds(addDoc(c, article(avecPhotos(lot(3)))));
    await assertSucceeds(addDoc(c, article({ photoUrl: u(1) })));
    await assertFails(addDoc(c, article(avecPhotos(lot(7)))));
    await assertFails(addDoc(c, article({ photoUrl: u(1), photoUrls: [u(1), 'http://evil.example/x.jpg'] })));
    await assertFails(addDoc(c, article({ photoUrls: lot(2) })));
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
describe('Extras : plusieurs photos (6 au plus), avec leurs chemins', () => {
  const lien = (n) => `https://firebasestorage.googleapis.com/v0/b/chantierplus-mtl/o/e${n}.jpg`;
  const chemin = (n) => `chantiers/A/chA/chantier_extras/${n}_e.jpg`;
  const liens = (n) => Array.from({ length: n }, (_, k) => lien(k + 1));
  const chemins = (n) => Array.from({ length: n }, (_, k) => chemin(k + 1));
  const photos = (n) => ({ photoUrl: lien(1), cheminPhoto: chemin(1), photoUrls: liens(n), cheminsPhotos: chemins(n) });
  const extra = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', description: 'Cloison', mainOeuvre: '3 gars — 4 h',
    dateTravaux: '2026-10-01', ajoutePar: 'plusA', ajouteParNom: 'Plus A', dateAjout: serverTimestamp(), ...over,
  });
  const col = (uid = 'uid-plusA') => collection(ctxDe(uid), 'chantier_extras');

  test('1 à 6 photos acceptées (admin et contremaître)', async () => {
    for (const n of [1, 2, 4, 6]) {
      await assertSucceeds(addDoc(col(), extra(photos(n))));
    }
    await assertSucceeds(addDoc(col('uid-adminA'), extra({ ...photos(3), ajoutePar: 'adminA', ajouteParNom: 'Admin A' })));
  });

  test('l\'ancien format (une photo : photoUrl + cheminPhoto) reste accepté, et sans photo aussi', async () => {
    await assertSucceeds(addDoc(col(), extra({ photoUrl: lien(1), cheminPhoto: chemin(1) })));
    await assertSucceeds(addDoc(col(), extra()));
  });

  test('refusé : 7 photos, tailles différentes, listes vides, pas des listes', async () => {
    await assertFails(addDoc(col(), extra(photos(7))));
    await assertFails(addDoc(col(), extra({ ...photos(3), cheminsPhotos: chemins(2) })));
    await assertFails(addDoc(col(), extra({ ...photos(1), photoUrls: [], cheminsPhotos: [] })));
    await assertFails(addDoc(col(), extra({ ...photos(2), photoUrls: 'oui', cheminsPhotos: 'oui' })));
  });

  test('refusé : une liste sans l\'autre, ou première photo qui ne correspond pas', async () => {
    const sansChemins = photos(2); delete sansChemins.cheminsPhotos;
    await assertFails(addDoc(col(), extra(sansChemins)));
    await assertFails(addDoc(col(), extra({ ...photos(2), photoUrl: lien(9) })));
    await assertFails(addDoc(col(), extra({ ...photos(2), cheminPhoto: chemin(9) })));
  });

  test('refusé : la liste de chemins seule, ou plus longue que celle des liens (chemins non vérifiés)', async () => {
    // Chemins seuls : photoUrl + cheminPhoto (ancien format) mais une liste de chemins en plus.
    await assertFails(addDoc(col(), extra({
      photoUrl: lien(1), cheminPhoto: chemin(1), cheminsPhotos: ['chantiers/B/chB/chantier_extras/x.jpg'],
    })));
    await assertFails(addDoc(col(), extra({ photoUrl: lien(1), cheminPhoto: chemin(1), cheminsPhotos: chemins(1) })));
    // Plus de chemins que de liens : le chemin en trop n'est pas vérifié par la règle.
    const longue = [...chemins(2), 'chantiers/B/chB/chantier_extras/x.jpg'];
    await assertFails(addDoc(col(), extra({ ...photos(2), cheminsPhotos: longue })));
    await assertFails(addDoc(col(), extra({ ...photos(2), cheminsPhotos: chemins(3) })));
    // Même chose à la modification.
    const ref = await assertSucceeds(addDoc(col(), extra(photos(2))));
    const r = doc(ctxDe('uid-plusA'), ref.path);
    await assertFails(updateDoc(r, { cheminsPhotos: longue }));
    await assertFails(updateDoc(r, { ...photos(2), cheminsPhotos: longue }));
  });

  test('refusé : un lien qui n\'est pas Firebase Storage, ou un chemin d\'une autre compagnie / d\'un autre dossier', async () => {
    for (let k = 0; k < 6; k++) {
      const u = liens(6); u[k] = 'https://evil.example/x.jpg';
      await assertFails(addDoc(col(), extra({ ...photos(6), photoUrls: u, photoUrl: u[0] })));
      const c = chemins(6); c[k] = 'chantiers/B/chB/chantier_extras/x.jpg';
      await assertFails(addDoc(col(), extra({ ...photos(6), cheminsPhotos: c, cheminPhoto: c[0] })));
      const d = chemins(6); d[k] = 'chantiers/A/chA/photos/x.jpg';
      await assertFails(addDoc(col(), extra({ ...photos(6), cheminsPhotos: d, cheminPhoto: d[0] })));
    }
  });

  test('employé et autre compagnie : refusés comme avant', async () => {
    await assertFails(addDoc(col('uid-empA'), extra(photos(2))));
    await assertFails(addDoc(col('uid-adminB'), extra(photos(2))));
  });

  test('modification : ajouter, retirer, tout retirer', async () => {
    const ref = await assertSucceeds(addDoc(col(), extra(photos(2))));
    const r = doc(ctxDe('uid-plusA'), ref.path);
    await assertSucceeds(updateDoc(r, photos(5)));
    await assertSucceeds(updateDoc(r, { photoUrl: lien(2), cheminPhoto: chemin(2), photoUrls: [lien(2), lien(4)], cheminsPhotos: [chemin(2), chemin(4)] }));
    await assertFails(updateDoc(r, photos(7)));
    await assertFails(updateDoc(r, { photoUrls: liens(2) }));
    await assertSucceeds(updateDoc(r, {
      photoUrl: deleteField(), cheminPhoto: deleteField(), photoUrls: deleteField(), cheminsPhotos: deleteField(),
    }));
  });
});

// =============================================================================
describe("Fil « Activité » de l'admin : qui a fait le geste, et jusqu'où l'admin a tout vu", () => {
  const lienPhoto = 'https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg';
  const photo = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', url: lienPhoto, cheminStorage: 'chantiers/A/chA/photos/a.jpg',
    dateAjout: serverTimestamp(), ...over,
  });
  const entree = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', texte: 'Clous 3 po', complete: false, dateAjout: serverTimestamp(), ...over,
  });
  const document = (over = {}) => ({
    companyId: 'A', chantierId: 'chA', nom: 'Plan.pdf', cheminStorage: 'chantiers/A/chA/documents/2_Plan.pdf',
    url: 'https://firebasestorage.googleapis.com/v0/b/x/o/plan2.pdf', taille: 1000, typeMime: 'application/pdf',
    ajoutePar: 'adminA', dateAjout: serverTimestamp(), ...over,
  });
  const acteurPlus = { ajoutePar: 'plusA', ajouteParNom: 'Plus A' };
  const col = (uid, nom) => collection(ctxDe(uid), nom);

  test('photo : l\'auteur est facultatif, et s\'il est là c\'est l\'employé connecté', async () => {
    await assertSucceeds(addDoc(col('uid-plusA', 'chantier_photos'), photo()));
    await assertSucceeds(addDoc(col('uid-plusA', 'chantier_photos'), photo(acteurPlus)));
    await assertSucceeds(addDoc(col('uid-adminA', 'chantier_photos'), photo({ ajoutePar: 'adminA', ajouteParNom: 'Admin A' })));
    // Au nom d'un autre, avec un autre nom, ou à moitié : refusé.
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ajoutePar: 'adminA', ajouteParNom: 'Plus A' })));
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ajoutePar: 'plusA', ajouteParNom: 'Admin A' })));
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ajoutePar: 'plusA' })));
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ajouteParNom: 'Plus A' })));
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ...acteurPlus, ajoutePar: 123 })));
    // Rien d'autre n'est permis.
    await assertFails(addDoc(col('uid-plusA', 'chantier_photos'), photo({ ...acteurPlus, texte: 'x' })));
    // L'employé et une autre compagnie : toujours refusés.
    await assertFails(addDoc(col('uid-empA', 'chantier_photos'), photo({ ajoutePar: 'empA', ajouteParNom: 'Emp A' })));
    await assertFails(addDoc(col('uid-adminB', 'chantier_photos'), photo({ ajoutePar: 'adminB', ajouteParNom: 'Admin B' })));
  });

  test('matériel et travaux d\'un chantier : même règle', async () => {
    for (const c of ['chantier_materiel', 'chantier_travaux']) {
      await assertSucceeds(addDoc(col('uid-plusA', c), entree()), c);
      await assertSucceeds(addDoc(col('uid-plusA', c), entree(acteurPlus)));
      await assertSucceeds(addDoc(col('uid-plusA', c), entree({ ...acteurPlus, quantite: '12' })));
      await assertFails(addDoc(col('uid-plusA', c), entree({ ajoutePar: 'adminA', ajouteParNom: 'Plus A' })));
      await assertFails(addDoc(col('uid-plusA', c), entree({ ajoutePar: 'plusA', ajouteParNom: 'Faux nom' })));
      await assertFails(addDoc(col('uid-plusA', c), entree({ ajoutePar: 'plusA' })));
      await assertFails(addDoc(col('uid-plusA', c), entree({ ajouteParNom: 'Plus A' })));
      await assertFails(addDoc(col('uid-empA', c), entree({ ajoutePar: 'empA', ajouteParNom: 'Emp A' })));
    }
  });

  test('modifier une demande ne permet pas de changer son auteur', async () => {
    const ref = await assertSucceeds(addDoc(col('uid-plusA', 'chantier_materiel'), entree(acteurPlus)));
    const r = doc(ctxDe('uid-plusA'), ref.path);
    await assertSucceeds(updateDoc(r, { texte: 'Clous 2 po' }));
    await assertFails(updateDoc(r, { ajoutePar: 'adminA' }));
    await assertFails(updateDoc(r, { ajouteParNom: 'Autre' }));
  });

  test('document : le nom de celui qui l\'a déposé est facultatif, et exact', async () => {
    await assertSucceeds(addDoc(col('uid-adminA', 'chantier_documents'), document()));
    await assertSucceeds(addDoc(col('uid-adminA', 'chantier_documents'), document({ ajouteParNom: 'Admin A' })));
    await assertFails(addDoc(col('uid-adminA', 'chantier_documents'), document({ ajouteParNom: 'Quelqu\'un d\'autre' })));
    await assertFails(addDoc(col('uid-plusA', 'chantier_documents'), document({ ajoutePar: 'plusA', ajouteParNom: 'Plus A' })));
  });

  describe('activite_vus : la dernière visite de chaque admin', () => {
    const ref = (uid, id) => doc(ctxDe(uid), `activite_vus/${id}`);
    const passe = () => new Date(Date.now() - 60_000);

    test('un admin écrit et lit SON document', async () => {
      await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: passe() }));
      await assertSucceeds(getDoc(ref('uid-adminA', 'adminA')));
      await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: new Date() }));
      await assertSucceeds(updateDoc(ref('uid-adminA', 'adminA'), { vuJusqua: passe() }));
    });

    test('jamais dans le futur, ni autre chose qu\'une date', async () => {
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: new Date(Date.now() + 24 * 3600 * 1000) }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: '2026-10-12' }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: 12345 }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A' }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { vuJusqua: passe() }));
    });

    test('compagnie, autres champs et document d\'un autre : refusés', async () => {
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'B', vuJusqua: passe() }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: passe(), extra: 1 }));
      await assertFails(setDoc(ref('uid-adminA', 'superA'), { companyId: 'A', vuJusqua: passe() }));
      await assertFails(setDoc(ref('uid-adminB', 'adminA'), { companyId: 'B', vuJusqua: passe() }));
    });

    test('contremaître, employé : aucun accès ; un admin ne lit pas celui d\'un autre', async () => {
      for (const uid of ['uid-plusA', 'uid-empA']) {
        await assertFails(setDoc(ref(uid, uid === 'uid-plusA' ? 'plusA' : 'empA'), { companyId: 'A', vuJusqua: passe() }));
      }
      await env.withSecurityRulesDisabled((c) =>
        setDoc(doc(c.firestore(), 'activite_vus/superA'), { companyId: 'A', vuJusqua: passe() }));
      await assertFails(getDoc(ref('uid-adminA', 'superA')));
      await assertFails(getDoc(ref('uid-plusA', 'superA')));
      await assertSucceeds(getDoc(ref('uid-superA', 'superA')));
    });

    test('pas de liste, pas de suppression', async () => {
      await assertSucceeds(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: passe() }));
      await assertFails(getDocs(collection(ctxDe('uid-adminA'), 'activite_vus')));
      await assertFails(deleteDoc(ref('uid-adminA', 'adminA')));
    });

    test('session expirée ou employé retiré : plus d\'accès', async () => {
      await env.withSecurityRulesDisabled((c) =>
        updateDoc(doc(c.firestore(), 'employees/adminA'), { actif: false }));
      await assertFails(setDoc(ref('uid-adminA', 'adminA'), { companyId: 'A', vuJusqua: passe() }));
    });
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
        'reinitialisations_nip/empA', 'invitations_nip/empA', 'connexions_web/uid-adminA', 'appareils_web/x', 'employees_prive/empA', 'config/securite',
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

// =============================================================================
describe('Notifications des admins : appareils et préférences', () => {
  const appareil = (over = {}) => ({
    companyId: 'A', employeeId: 'adminA', jeton: 'jeton-123', plateforme: 'android',
    majLe: serverTimestamp(), ...over,
  });

  test('l\'admin enregistre le jeton de SON appareil (sous l\'uid de sa session)', async () => {
    const d = ctxDe('uid-adminA');
    await assertSucceeds(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil()));
    await assertSucceeds(getDoc(doc(d, 'appareils_notifications/uid-adminA')));
    await assertSucceeds(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil({ jeton: 'neuf', plateforme: 'ios' })));
    await assertSucceeds(deleteDoc(doc(d, 'appareils_notifications/uid-adminA')));
  });

  test('refusé : un autre uid, un autre employé, une autre compagnie, un champ de trop', async () => {
    const d = ctxDe('uid-adminA');
    await assertFails(setDoc(doc(d, 'appareils_notifications/uid-autre'), appareil()));
    await assertFails(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil({ employeeId: 'empA' })));
    await assertFails(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil({ companyId: 'B' })));
    await assertFails(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil({ role: 'admin' })));
    await assertFails(setDoc(doc(d, 'appareils_notifications/uid-adminA'), appareil({ plateforme: 'web' })));
    await assertFails(getDocs(query(collection(d, 'appareils_notifications'), where('companyId', '==', 'A'))));
  });

  test('employé et contremaître : pas de notifications (admins seulement)', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-empA'), 'appareils_notifications/uid-empA'),
      appareil({ employeeId: 'empA' })));
    await assertFails(setDoc(doc(ctxDe('uid-plusA'), 'appareils_notifications/uid-plusA'),
      appareil({ employeeId: 'plusA' })));
  });

  test('préférences : les siennes seulement, des oui/non par catégorie', async () => {
    const d = ctxDe('uid-adminA');
    await assertSucceeds(getDoc(doc(d, 'preferences_notifications/adminA'))); // absent : lisible
    await assertSucceeds(setDoc(doc(d, 'preferences_notifications/adminA'),
      { companyId: 'A', extras: false, heures: true }));
    await assertSucceeds(getDoc(doc(d, 'preferences_notifications/adminA')));
    await assertFails(setDoc(doc(d, 'preferences_notifications/adminA'), { companyId: 'A', extras: 'non' }));
    await assertFails(setDoc(doc(d, 'preferences_notifications/adminA'), { companyId: 'A', courriel: true }));
    await assertFails(setDoc(doc(d, 'preferences_notifications/empA'), { companyId: 'A', extras: false }));
    await assertFails(getDoc(doc(d, 'preferences_notifications/empA')));
    await assertFails(setDoc(doc(ctxDe('uid-empA'), 'preferences_notifications/empA'),
      { companyId: 'A', extras: false }));
  });

  test('envois de l\'émulateur et regroupement des photos : serveur seulement', async () => {
    const d = ctxDe('uid-adminA');
    await assertFails(getDocs(query(collection(d, 'envois_notifications_emulateur'), where('companyId', '==', 'A'))));
    await assertFails(setDoc(doc(d, 'notifications_regroupees/x'), { companyId: 'A', dernierEnvoi: 0 }));
  });
});

// =============================================================================
// Dernière version de l'app : pastille « Compte » et bouton « Mettre à jour »
// =============================================================================
describe('version_app', () => {
  const version = (build) => ({ build, le: serverTimestamp() });

  test('lue par tous ceux qui sont connectés ; jamais sans compte', async () => {
    await assertSucceeds(getDoc(doc(ctxDe('uid-empA'), 'version_app/ios')));
    await assertSucceeds(getDoc(doc(db(individu(env, 'uid-ind')), 'version_app/ios')));
    await assertFails(getDoc(doc(db(env.unauthenticatedContext()), 'version_app/ios')));
  });

  test('un admin annonce une version plus récente (au plus 10 de plus)', async () => {
    const d = ctxDe('uid-adminA');
    await assertSucceeds(setDoc(doc(d, 'version_app/ios'), version(12)));
    await assertSucceeds(setDoc(doc(d, 'version_app/ios'), version(13)));
    await assertFails(setDoc(doc(d, 'version_app/ios'), version(13))); // pas plus haute
    await assertFails(setDoc(doc(d, 'version_app/ios'), version(11))); // plus ancienne
    await assertFails(setDoc(doc(d, 'version_app/ios'), version(24))); // trop loin
    await assertSucceeds(setDoc(doc(d, 'version_app/ios'), version(23)));
    await assertFails(deleteDoc(doc(d, 'version_app/ios')));
  });

  test('refusé : employé, contremaître, autre plateforme, champ de plus, date fausse', async () => {
    await assertFails(setDoc(doc(ctxDe('uid-empA'), 'version_app/ios'), version(12)));
    await assertFails(setDoc(doc(ctxDe('uid-plusA'), 'version_app/ios'), version(12)));
    await assertFails(setDoc(doc(db(individu(env, 'uid-ind')), 'version_app/ios'), version(12)));
    const d = ctxDe('uid-adminA');
    await assertFails(setDoc(doc(d, 'version_app/web'), version(12)));
    await assertFails(setDoc(doc(d, 'version_app/ios'), { ...version(12), note: 'x' }));
    await assertFails(setDoc(doc(d, 'version_app/ios'), { build: 12, le: new Date(0) }));
    await assertFails(setDoc(doc(d, 'version_app/ios'), version('12')));
    await assertFails(getDocs(collection(d, 'version_app')));
  });
});
