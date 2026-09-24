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
  });
});

const IMAGE = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const JPEG = { contentType: 'image/jpeg' };
const st = (ctx) => ctx.storage();

describe('Storage — photos de chantier', () => {
  test('membre A : téléverse dans son chantier (photos, travaux, matériel)', async () => {
    const s = st(employe(env, 'uid-empA'));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/photos/1.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/chantier_travaux/2.jpg'), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(ref(s, 'chantiers/A/chA/chantier_materiel/3.jpg'), IMAGE, JPEG));
  });

  test('membre A : refusé dans la compagnie B ou sur un chantier de B', async () => {
    const s = st(employe(env, 'uid-empA'));
    await assertFails(uploadBytes(ref(s, 'chantiers/B/chB/photos/x.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chB/photos/x.jpg'), IMAGE, JPEG));
  });

  test('refusé : type de dossier inconnu, fichier non-image, fichier trop gros', async () => {
    const s = st(employe(env, 'uid-empA'));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/autre/x.jpg'), IMAGE, JPEG));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/photos/x.html'), IMAGE, { contentType: 'text/html' }));
    await assertFails(uploadBytes(ref(s, 'chantiers/A/chA/photos/gros.jpg'), new Uint8Array(10 * 1024 * 1024 + 1), JPEG));
  });

  test('refusé : écrasement d\'un fichier existant', async () => {
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-empA')), 'chantiers/A/chA/photos/existante.jpg'), IMAGE, JPEG));
  });

  test('lecture : A lit A, pas B', async () => {
    const s = st(employe(env, 'uid-empA'));
    await assertSucceeds(getBytes(ref(s, 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(getBytes(ref(s, 'chantiers/B/chB/photos/secrete.jpg')));
  });

  test('suppression : B ne supprime pas les fichiers de A', async () => {
    await assertFails(deleteObject(ref(st(employe(env, 'uid-adminB')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertSucceeds(deleteObject(ref(st(employe(env, 'uid-empA')), 'chantiers/A/chA/photos/existante.jpg')));
  });

  test('sessions invalides (forgée, employé supprimé, compagnie en attente) → refusé', async () => {
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-forge')), 'chantiers/B/chB/photos/f.jpg'), IMAGE, JPEG));
    await assertFails(getBytes(ref(st(employe(env, 'uid-supprime')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminP')), 'chantiers/P/chP/photos/p.jpg'), IMAGE, JPEG));
  });

  test('non authentifié ou particulier → refusé ; hors de chantiers/ → refusé', async () => {
    await assertFails(getBytes(ref(st(env.unauthenticatedContext()), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(getBytes(ref(st(individu(env, 'uid-ind')), 'chantiers/A/chA/photos/existante.jpg')));
    await assertFails(uploadBytes(ref(st(employe(env, 'uid-adminA')), 'autre/x.jpg'), IMAGE, JPEG));
  });
});
