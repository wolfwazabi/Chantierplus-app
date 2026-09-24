import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

const racine = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const PROJET = 'demo-construction-rules';
export const BUCKET = 'demo-construction-rules.appspot.com';
export const LUNDI = '2026-09-21';

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

export const superAdmin = (env) =>
  env.authenticatedContext('uid-super', {
    email: 'super@exemple.ca',
    email_verified: true,
    superAdmin: true,
    firebase: { sign_in_provider: 'password' },
  });

// ------------------------------------------------------------ Jeu de données
//
// Compagnie A (approuvée) : adminA (admin), empA (employé)
// Compagnie B (approuvée) : adminB (admin)
// Compagnie P (en attente) : adminP
// Sessions : une par employé, + une session forgée (employé A / compagnie B)
//            + une session d'employé supprimé.

export async function semer(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const d = (chemin, data) => setDoc(doc(db, chemin), data);

    await d('companies/A', { numero: '1001', nomEntreprise: 'Alpha', statut: 'approuvee' });
    await d('companies/B', { numero: '1002', nomEntreprise: 'Bêta', statut: 'approuvee' });
    await d('companies/P', { numero: '1003', nomEntreprise: 'Pending', statut: 'attente' });

    await d('employees/adminA', { companyId: 'A', nom: 'Admin A', role: 'admin', estProprietaire: true, pinHash: 'h1' });
    await d('employees/empA', { companyId: 'A', nom: 'Emp A', role: 'employe', estProprietaire: false, pinHash: 'h2' });
    await d('employees/adminB', { companyId: 'B', nom: 'Admin B', role: 'admin', estProprietaire: true, pinHash: 'h3' });
    await d('employees/adminP', { companyId: 'P', nom: 'Admin P', role: 'admin', estProprietaire: true, pinHash: 'h4' });

    await d('sessions/uid-adminA', { employeeId: 'adminA', companyId: 'A' });
    await d('sessions/uid-empA', { employeeId: 'empA', companyId: 'A' });
    await d('sessions/uid-adminB', { employeeId: 'adminB', companyId: 'B' });
    await d('sessions/uid-adminP', { employeeId: 'adminP', companyId: 'P' });
    await d('sessions/uid-forge', { employeeId: 'empA', companyId: 'B' });
    await d('sessions/uid-supprime', { employeeId: 'fantome', companyId: 'A' });

    await d('chantiers/chA', { companyId: 'A', nom: 'Chantier A', adresse: '1 rue A' });
    await d('chantiers/chB', { companyId: 'B', nom: 'Chantier B', adresse: '1 rue B' });

    await d(`feuilles_temps/empA_${LUNDI}`, {
      companyId: 'A', estIndividuel: false, employeeId: 'empA', employeeNom: 'Emp A',
      lundiDate: LUNDI, jours: [], totalHeures: 0,
    });
    await d(`feuilles_temps/adminB_${LUNDI}`, {
      companyId: 'B', estIndividuel: false, employeeId: 'adminB', employeeNom: 'Admin B',
      lundiDate: LUNDI, jours: [], totalHeures: 0,
    });

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
