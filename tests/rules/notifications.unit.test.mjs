// Tests unitaires des messages de notification (sans émulateur).
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const n = require('../../functions/src/notifications.js');
const ft = require('../../functions/src/feuille_temps.js');

describe('Messages des entrées sur un chantier', () => {
  test('extra, travail, matériel, photos, document', () => {
    const par = { ajouteParNom: 'Paul' };
    assert.deepEqual(n.messageEntree('extras', 'Chalet Nord', { description: 'Porte', ...par }),
      { titre: 'Extra — Chalet Nord', corps: 'Porte (Paul)' });
    assert.deepEqual(n.messageEntree('travaux', 'Chalet Nord', { texte: 'Soffite', ...par }),
      { titre: 'Travail à compléter — Chalet Nord', corps: 'Soffite (Paul)' });
    assert.deepEqual(n.messageEntree('materiel', 'Général', { texte: 'Vis', quantite: '2 boîtes', ...par }),
      { titre: 'Matériel manquant — Général', corps: 'Vis × 2 boîtes (Paul)' });
    assert.deepEqual(n.messageEntree('photos', 'Chalet Nord', par),
      { titre: 'Photos — Chalet Nord', corps: 'Paul a ajouté des photos.' });
    assert.deepEqual(n.messageEntree('documents', 'Chalet Nord', { nom: 'Plan.pdf', ...par }),
      { titre: 'Document — Chalet Nord', corps: 'Plan.pdf (Paul)' });
  });

  test('un texte trop long est coupé ; sans auteur, pas de parenthèses', () => {
    const m = n.messageEntree('travaux', 'X', { texte: 'a'.repeat(300) });
    assert.equal(m.corps.length, 140);
    assert.ok(m.corps.endsWith('…'));
    assert.equal(n.messageEntree('extras', 'X', { description: 'Porte' }).corps, 'Porte');
  });
});

describe('Message d\'un envoi d\'heures', () => {
  const jours = (liste) => ft.lireJours(liste);
  const jour = { chantierId: 'c', heureDebutMinutes: 420, heureFinMinutes: 900 };

  test('les journées envoyées, puis le total de la semaine', () => {
    const m = n.messageHeures('Émile', jours([jour, { estAucun: false }, jour]), 15.5);
    assert.equal(m.titre, 'Heures — Émile');
    assert.equal(m.corps, 'Lundi, mercredi — total de la semaine : 15,5 h');
  });

  test('férié, non travaillé, journée supprimée', () => {
    const m = n.messageHeures('Émile', jours([{ estFerie: true }, { estAucun: true }, { effacer: true }]), 8);
    assert.equal(m.corps, 'Lundi férié, mardi non travaillé, mercredi supprimé — total de la semaine : 8 h');
  });

  test('rien de nouveau (tout envoyé vide) : seulement le total', () => {
    assert.equal(n.messageHeures('Émile', jours([{ estAucun: false }]), 0).corps,
      'Total de la semaine : 0 h');
  });
});

describe('Catégories', () => {
  test('les six catégories choisies par l\'entrepreneur', () => {
    assert.deepEqual(n.CATEGORIES, ['extras', 'travaux', 'materiel', 'heures', 'photos', 'documents']);
  });

  test('une catégorie inconnue ne part pas', async () => {
    assert.equal(await n.notifier(null, null, { companyId: 'c', categorie: 'inconnue' }), 0);
  });
});
