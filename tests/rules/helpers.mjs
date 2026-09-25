import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const racine = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const PROJET = 'demo-construction-rules';

/** Lundi (AAAA-MM-JJ, UTC) de la semaine courante décalée de `semaines`. */
export function lundi(semaines = 0) {
  const d = new Date();
  d.setUTCHours(0, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7) + 7 * semaines);
  return d.toISOString().slice(0, 10);
}

export const LUNDI = lundi(0);           // semaine courante : ouverte
export const LUNDI_PASSE = lundi(-2);    // échéance dépassée : verrouillée
export const LUNDI_PROCHAIN = lundi(1);  // semaine future : ouverte

export async function creerEnvironnement({ storage = false } = {}) {
  return initializeTestEnvironment({
    projectId: PROJET,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync(resolve(racine, 'firestore.rules'), 'utf8'),
    },
    ...(storage && {
      storage: {
        host: '127.0.0.1',
        port: 9199,
        rules: readFileSync(resolve(racine, 'storage.rules'), 'utf8'),
      },
    }),
  });
}

// ---------------------------------------------------------------- Contextes

export const employe = (env, uid) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } });

export const individu = (env, uid, email = `${uid}@exemple.ca`) =>
  env.authenticatedContext(uid, { email, email_verified: true, firebase: { sign_in_provider: 'password' } });

// ------------------------------------------------------------ Jeu de données
//
// Compagnie A (approuvée) : adminA (admin, propriétaire), plusA (contremaître),
//                           empA (employé), superA (admin, LE super-admin
//                           désigné par config/super_admin), usurpateur (porte
//                           un champ superAdmin: true, qui ne doit rien donner)
// Compagnie B (approuvée) : adminB (admin)
// Compagnie P (en attente) : adminP
// Sessions : une par employé ; superA en a deux (courriel / NIP seul) ;
//            + une session forgée et une d'employé supprimé.

export async function semer(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const d = (chemin, data) => setDoc(doc(db, chemin), data);

    await d('companies/A', { numero: '1001', nomEntreprise: 'Alpha', statut: 'approuvee' });
    await d('companies/B', { numero: '1002', nomEntreprise: 'Bêta', statut: 'approuvee' });
    await d('companies/P', { numero: '1003', nomEntreprise: 'Pending', statut: 'attente' });

    const emp = (companyId, nom, role, extra = {}) =>
      ({ companyId, nom, role, estProprietaire: false, pinHash: 'h', courriel: `${nom}@a.ca`, ...extra });
    await d('employees/adminA', emp('A', 'Admin A', 'admin', { estProprietaire: true }));
    await d('employees/plusA', emp('A', 'Plus A', 'plus'));
    await d('employees/empA', emp('A', 'Emp A', 'employe'));
    await d('employees/superA', emp('A', 'Super A', 'admin'));
    await d('employees/usurpateur', emp('A', 'Usurpateur', 'admin', { superAdmin: true }));
    await d('config/super_admin', { employeeId: 'superA' });
    await d('employees/adminB', emp('B', 'Admin B', 'admin', { estProprietaire: true }));
    await d('employees/adminP', emp('P', 'Admin P', 'admin', { estProprietaire: true }));

    const session = (employeeId, companyId, methode = 'courriel') => ({ employeeId, companyId, methode });
    await d('sessions/uid-adminA', session('adminA', 'A'));
    await d('sessions/uid-plusA', session('plusA', 'A'));
    await d('sessions/uid-empA', session('empA', 'A', 'nip'));
    await d('sessions/uid-superA', session('superA', 'A'));
    await d('sessions/uid-superA-nip', session('superA', 'A', 'nip'));
    await d('sessions/uid-usurpateur', { ...session('usurpateur', 'A'), superAdmin: true });
    await d('sessions/uid-adminB', session('adminB', 'B'));
    await d('sessions/uid-adminP', session('adminP', 'P'));
    await d('sessions/uid-forge', session('empA', 'B'));
    await d('sessions/uid-supprime', session('fantome', 'A'));

    await d('chantiers/chA', { companyId: 'A', nom: 'Chantier A', adresse: '1 rue A' });
    await d('chantiers/chB', { companyId: 'B', nom: 'Chantier B', adresse: '1 rue B' });

    const feuille = (employeeId, companyId, employeeNom, lundiDate) => ({
      companyId, estIndividuel: false, employeeId, employeeNom, lundiDate, jours: [], totalHeures: 0,
    });
    await d(`feuilles_temps/empA_${LUNDI}`, feuille('empA', 'A', 'Emp A', LUNDI));
    await d(`feuilles_temps/empA_${LUNDI_PASSE}`, feuille('empA', 'A', 'Emp A', LUNDI_PASSE));
    await d(`feuilles_temps/adminB_${LUNDI}`, feuille('adminB', 'B', 'Admin B', LUNDI));

    await d('chantier_travaux/tA', { companyId: 'A', chantierId: 'chA', texte: 'Coffrage', complete: false });
    await d('chantier_travaux/tB', { companyId: 'B', chantierId: 'chB', texte: 'Toiture', complete: false });
    await d('chantier_photos/pA', {
      companyId: 'A', chantierId: 'chA',
      url: 'https://firebasestorage.googleapis.com/v0/b/x/o/a.jpg', cheminStorage: 'chantiers/A/chA/photos/a.jpg',
    });

    await d('individus/uid-ind', { nom: 'Solo', email: 'uid-ind@exemple.ca' });
    await d('compteurs/companies', { dernierNumero: 1003 });
  });
}
