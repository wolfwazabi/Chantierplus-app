import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
import { creerEnvironnement, employe, individu, semer } from './helpers.mjs';

let env;
before(async () => { env = await creerEnvironnement({ storage: true }); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await semer(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), 'chantiers/A/chA/photos/existante.jpg'), IMAGE, JPEG);
    await uploadBytes(ref(ctx.storage(), 'chantiers/B/chB/photos/secrete.jpg'), IMAGE, JPEG);
    await uploadBytes(ref(ctx.storage(), 'chantiers/A/chA/documents/plan.pdf'), IMAGE, PDF);
  });
});

const IMAGE = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const JPEG = { contentType: 'image/jpeg' };
const PDF = { contentType: 'application/pdf' };
const XLSX = { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' };
const DOCX = { contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };
const BINAIRE = { contentType: 'application/octet-stream' };
const st = (ctx) => ctx.storage();

describe('Storage — documents de chantier', () => {
  test('admin : dépose PDF, Excel, Word, images et plans', async () => {
    const s = st(employe(env, 'uid-adminA'));
    for (const [nom, meta] of [['a.pdf', PDF], ['b.xlsx', XLSX], ['c.docx', DOCX], ['d.JPG', JPEG],
      ['e.png', { contentType: 'image/png' }], ['f.dwg', BINAIRE], ['g.csv', { contentType: 'text/csv' }]]) {
      await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/documents/' + nom), IMAGE, meta));
    }
  });

  test('refusé : HTML, SVG, JavaScript, exécutable, extension inconnue, > 50 Mo, écrasement', async () => {
    const s = st(employe(env, 'uid-adminA'));
    const refuser = (nom, meta, donnees = IMAGE) =>
      assertFails(uploadBytes(ref(s, 'chantiers/A/chA/documents/' + nom), donnees, meta));
    await refuser('page.html', { contentType: 'text/html' });
    await refuser('page.pdf', { contentType: 'text/html' });
    await refuser('image.svg', { contentType: 'image/svg+xml' });
    await refuser('script.js', { contentType: 'text/javascript' });
    await refuser('virus.exe', { contentType: 'application/x-msdownload' });
    await refuser('virus.exe', BINAIRE);
    await refuser('sans_extension', PDF);
    await refuser('gros.pdf', PDF, new Uint8Array(50 * 1024 * 1024 + 1));
    await refuser('plan.pdf', PDF);
  });

  test('contremaître : lit, mais ne dépose ni ne supprime', async () => {
    const s = st(employe(env, 'uid-plusA'));
    await assertSucceeds(getBytes(ref(s, 'chantiers/A/chA/documents/plan.pdf')));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/documents/x.pdf'), IMAGE, PDF));
    await assertFails(deleteObject(ref(s, 'chantiers/A/chA/documents/plan.pdf')));
  });

  test('employé et autre compagnie : aucun accès', async () => {
    await assertFails(getBytes(ref(st(employe(env, 'uid-empA')), 'chantiers/A/chA/documents/plan.pdf')));
    await assertFails(getBytes(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/documents/plan.pdf')));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/documents/x.pdf'), IMAGE, PDF));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminA')), 'chantiers/B/chB/documents/x.pdf'), IMAGE, PDF));
    await assertFails(deleteObject(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/documents/plan.pdf')));
  });

  test('admin : supprime', async () => {
    await assertSucceeds(deleteObject(ref(st(employe(env, 'uid-adminA')), 'chantiers/A/chA/documents/plan.pdf')));
  });
});

describe('Storage — exports de dossiers de chantier', () => {
  // Les ZIP d'export sont créés par la fonction exporterChantier (compte de service) et
  // téléchargés par lien à jeton : aucun client ne peut les lire, les écrire ni les supprimer.
  test('exports/ : refusé à tous les rôles, de toutes les compagnies', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), 'exports/A/2026-10-30_chA.zip'), IMAGE, { contentType: 'application/zip' });
    });
    for (const uid of ['uid-adminA', 'uid-superA', 'uid-plusA', 'uid-empA', 'uid-adminB']) {
      const s = st(employe(env, uid));
      await assertFails(getBytes(ref(s, 'exports/A/2026-10-30_chA.zip')));
      await assertFails(uploadBytes(ref(s, 'exports/A/autre.zip'), IMAGE, { contentType: 'application/zip' }));
      await assertFails(deleteObject(ref(s, 'exports/A/2026-10-30_chA.zip')));
    }
  });
});

describe('Storage — photos de chantier', () => {
  test('contremaître A : téléverse dans son chantier (photos, travaux, matériel)', async () => {
    const s = st(employe(env, 'uid-plusA'));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/photos/1.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/chantier_travaux/2.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/chantier_materiel/3.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/chantier_extras/4.jpg'), IMAGE, JPEG));
  });

  test("matériel Général (_general) : photo permise au contremaître et à l'admin, pas à l'employé ni à l'autre compagnie", async () => {
    await assertSucceeds(uploadBytes(ref(st(employe(env, 'uid-plusA')), 'chantiers/A/_general/chantier_materiel/g1.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(st(employe(env, 'uid-adminA')), 'chantiers/A/_general/chantier_materiel/g2.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-empA')), 'chantiers/A/_general/chantier_materiel/g3.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/_general/chantier_materiel/g4.jpg'), IMAGE, JPEG));
    // Lecture par un gestionnaire de la compagnie.
    await assertSucceeds(getBytes(ref(st(employe(env, 'uid-plusA')), 'chantiers/A/_general/chantier_materiel/g1.jpg')));
    await assertFails(getBytes(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/_general/chantier_materiel/g1.jpg')));
  });

  test('photos d\'extras : employé et autre compagnie refusés, pas de non-image', async () => {
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-empA')), 'chantiers/A/chA/chantier_extras/x.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/chantier_extras/x.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-plusA')), 'chantiers/A/chA/chantier_extras/x.html'), IMAGE, { contentType: 'text/html' }));
  });

  test('contremaître A : refusé dans la compagnie B (dépôt, lecture, suppression)', async () => {
    const s = st(employe(env, 'uid-plusA'));
    await assertFails(uploadBytes(ref(s, 'chantiers/B/chB/photos/x.jpg'), IMAGE, JPEG));
    await assertFails(getBytes(ref(s, 'chantiers/B/chB/photos/secrete.jpg')));
    await assertFails(deleteObject(ref(s, 'chantiers/B/chB/photos/secrete.jpg')));
  });

  test('refusé : type de dossier inconnu, fichier non-image, fichier trop gros', async () => {
    const s = st(employe(env, 'uid-plusA'));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/autre/x.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/photos/x.html'), IMAGE, { contentType: 'text/html' }));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/photos/gros.jpg'), new Uint8Array(10 * 1024 * 1024 + 1), JPEG));
  });

  test('refusé : écrasement d\'un fichier existant', async () => {
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-plusA')), 'chantiers/A/chA/photos/existante.jpg'), IMAGE, JPEG));
  });

  test('lecture : A lit A, pas B', async () => {
    const s = st(employe(env, 'uid-plusA'));
    await assertSucceeds(getBytes(ref(s, 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(getBytes(ref(s, 'chantiers/B/chB/photos/secrete.jpg')));
  });

  test('suppression : B ne supprime pas les fichiers de A', async () => {
    await assertFails(deleteObject(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertSucceeds(deleteObject(ref(st(employe(env, 'uid-plusA')), 'chantiers/A/chA/photos/existante.jpg')));
  });

  test('employé : ni lecture, ni téléversement, ni suppression', async () => {
    const s = st(employe(env, 'uid-empA'));
    await assertFails(getBytes(ref(s, 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/photos/e.jpg'), IMAGE, JPEG));
    await assertFails(deleteObject(ref(s, 'chantiers/A/chA/photos/existante.jpg')));
  });

  // Le statut de la compagnie n'est pas relu ici (limite de 2 documents, voir
  // storage_limite.unit.test.mjs) : seule une compagnie approuvée ouvre une session.
  test('sessions invalides (forgée, employé supprimé, aucune session) → refusé', async () => {
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-forge')), 'chantiers/B/chB/photos/f.jpg'), IMAGE, JPEG));
    await assertFails(getBytes(ref(st(employe(env, 'uid-supprime')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-sans-session')), 'chantiers/A/chA/photos/s.jpg'), IMAGE, JPEG));
  });

  test('non authentifié ou particulier → refusé ; hors de chantiers/ → refusé', async () => {
    await assertFails(getBytes(ref(st(env.unauthenticatedContext()), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(getBytes(ref(st(individu(env, 'uid-ind')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminA')), 'autre/x.jpg'), IMAGE, JPEG));
  });
});
