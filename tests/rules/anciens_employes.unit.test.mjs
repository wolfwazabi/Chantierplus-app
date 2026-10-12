// Anciens employés (loi 25) : motif en liste fermée et date de suppression automatique.
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import archivage from '../../functions/src/anciens_employes.js';

const { MOTIFS_RETRAIT, RETENTION_ANCIENS_MOIS, dateSuppression, lireMotif } = archivage;
const iso = (d) => d.toISOString().slice(0, 10);

describe('Motif du départ', () => {
  test('la liste fermée : exactement ces six valeurs, rien de libre', () => {
    assert.deepEqual(MOTIFS_RETRAIT,
      ['non-precise', 'saisonnier', 'depart-volontaire', 'fin-contrat', 'absence-prolongee', 'autre']);
  });

  test('chaque motif de la liste est accepté tel quel', () => {
    for (const m of MOTIFS_RETRAIT) assert.equal(lireMotif(m), m);
  });

  test('absent (undefined ou null) : « non-precise »', () => {
    assert.equal(lireMotif(undefined), 'non-precise');
    assert.equal(lireMotif(null), 'non-precise');
  });

  test('tout le reste est refusé : texte libre, casse, espaces, types', () => {
    for (const mauvais of ['', ' ', 'maladie', 'Saisonnier', 'SAISONNIER', ' saisonnier', 'saisonnier ', 'autre chose',
      'burn-out', 0, 1, true, false, [], ['autre'], {}, { motif: 'autre' }]) {
      assert.throws(() => lireMotif(mauvais), (e) => {
        assert.equal(e.code, 'invalid-argument');
        assert.equal(e.message, 'Motif de départ invalide.');
        return true;
      }, JSON.stringify(mauvais));
    }
  });
});

describe('Date de suppression automatique', () => {
  test('deux saisons : 24 mois', () => {
    assert.equal(RETENTION_ANCIENS_MOIS, 24);
  });

  test('24 mois civils plus tard, même jour et même heure', () => {
    const depuis = Date.UTC(2026, 9, 12, 14, 30, 15);
    const fin = dateSuppression(depuis);
    assert.equal(fin.toISOString(), '2028-10-12T14:30:15.000Z');
  });

  test('fin de mois : jamais un débordement vers le mois suivant', () => {
    assert.equal(iso(dateSuppression(Date.UTC(2026, 0, 31))), '2028-01-31');
    assert.equal(iso(dateSuppression(Date.UTC(2025, 1, 28))), '2027-02-28');
    // 29 février d'une année bissextile + 24 mois = février d'une année ordinaire.
    assert.equal(iso(dateSuppression(Date.UTC(2024, 1, 29))), '2026-02-28');
    // Et l'inverse : le 28 février 2026 + 24 mois (2028 est bissextile) reste le 28.
    assert.equal(iso(dateSuppression(Date.UTC(2026, 1, 28))), '2028-02-28');
    assert.equal(iso(dateSuppression(Date.UTC(2026, 7, 31), 6)), '2027-02-28');
    assert.equal(iso(dateSuppression(Date.UTC(2026, 4, 31), 1)), '2026-06-30');
  });

  test('passage d\'année et durée personnalisée', () => {
    assert.equal(iso(dateSuppression(Date.UTC(2026, 11, 15), 1)), '2027-01-15');
    assert.equal(iso(dateSuppression(Date.UTC(2026, 11, 31), 12)), '2027-12-31');
    assert.equal(iso(dateSuppression(Date.UTC(2026, 0, 1), 0)), '2026-01-01');
  });

  test('toujours dans le futur, et jamais avant 23 mois', () => {
    const maintenant = Date.UTC(2026, 9, 12);
    const fin = dateSuppression(maintenant).getTime();
    assert.ok(fin > maintenant + 23 * 28 * 24 * 3600 * 1000);
    assert.ok(fin < maintenant + 25 * 31 * 24 * 3600 * 1000);
  });
});
