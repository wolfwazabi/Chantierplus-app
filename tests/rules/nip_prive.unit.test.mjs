// NIP haché dans l'espace privé : lecture sur les deux emplacements (transition) et champs écrits.
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import nipPrive from '../../functions/src/nip_prive.js';

const { hashEnregistre, nipExiste, champsNipEcrit, champsNipEfface, donneesNipPrive, migrerNipsPrives, COLLECTION_NIP } = nipPrive;

const SUPPRIMER = Symbol('delete');
const HORODATAGE = Symbol('horodatage');
const FieldValue = { delete: () => SUPPRIMER, serverTimestamp: () => HORODATAGE };

describe('Où est le NIP haché ?', () => {
  test('le nouvel emplacement d\'abord, puis l\'ancien champ de la fiche', () => {
    assert.equal(hashEnregistre({ pinHash: 'ancien' }, { pinHash: 'prive' }), 'prive');
    assert.equal(hashEnregistre({ pinHash: 'ancien' }, null), 'ancien');
    assert.equal(hashEnregistre({}, { pinHash: 'prive' }), 'prive');
    assert.equal(hashEnregistre(undefined, undefined), null);
  });

  test('un champ vide ou illisible n\'est pas un NIP', () => {
    for (const mauvais of ['', null, undefined, 0, 12, true, {}, []]) {
      assert.equal(hashEnregistre({ pinHash: mauvais }, { pinHash: mauvais }), null, JSON.stringify(mauvais));
    }
    // Un privé vide laisse la place à l'ancien champ valide.
    assert.equal(hashEnregistre({ pinHash: 'ancien' }, { pinHash: '' }), 'ancien');
  });

  test('un NIP existe : un hachage quelque part, ou le booléen nipCree seul (par prudence)', () => {
    assert.equal(nipExiste({ pinHash: 'a' }, null), true);
    assert.equal(nipExiste({}, { pinHash: 'p' }), true);
    assert.equal(nipExiste({ nipCree: true }, null), true);
    assert.equal(nipExiste({ nipCree: false }, null), false);
    assert.equal(nipExiste({}, null), false);
    assert.equal(nipExiste({ nipCree: 'true' }, { pinHash: '' }), false);
  });
});

describe('Champs écrits', () => {
  test('NIP écrit : nipCree vrai, ancien hachage et ancienne date retirés de la fiche', () => {
    assert.deepEqual(champsNipEcrit(FieldValue), { nipCree: true, pinHash: SUPPRIMER, pinModifieLe: SUPPRIMER });
  });

  test('NIP détruit : nipCree faux, rien ne reste sur la fiche', () => {
    assert.deepEqual(champsNipEfface(FieldValue), { nipCree: false, pinHash: SUPPRIMER, pinModifieLe: SUPPRIMER });
  });

  test('document privé : hachage, date du serveur et compagnie (pour la suppression de compagnie)', () => {
    assert.deepEqual(donneesNipPrive({ FieldValue, companyId: 'C', hash: 'h' }),
      { pinHash: 'h', pinModifieLe: HORODATAGE, companyId: 'C' });
  });

  test('la collection s\'appelle employees_prive', () => {
    assert.equal(COLLECTION_NIP, 'employees_prive');
  });
});

describe('Migration : jamais de boucle sans fin', () => {
  test('si aucune fiche d\'une page n\'est migrable, la migration s\'arrête', async () => {
    let pages = 0;
    const db = {
      collection: () => ({
        where: () => ({ limit: () => ({ get: async () => { pages++; return { empty: false, docs: [{ id: 'x', ref: {} }] }; } }) }),
        doc: (id) => ({ id }),
      }),
      runTransaction: async (fn) => fn({
        get: async () => ({ exists: true, data: () => ({ pinHash: '' }) }),
        set() { throw new Error('rien à écrire'); },
        update() { throw new Error('rien à écrire'); },
      }),
    };
    assert.equal(await migrerNipsPrives({ db, FieldValue }), 0);
    assert.equal(pages, 1, 'une seule page lue');
  });

  test('une fiche supprimée entre-temps est ignorée', async () => {
    const db = {
      collection: () => ({
        where: () => ({ limit: () => ({ get: async () => ({ empty: false, docs: [{ id: 'x', ref: {} }] }) }) }),
        doc: (id) => ({ id }),
      }),
      runTransaction: async (fn) => fn({ get: async () => ({ exists: false, data: () => undefined }) }),
    };
    assert.equal(await migrerNipsPrives({ db, FieldValue }), 0);
  });
});
