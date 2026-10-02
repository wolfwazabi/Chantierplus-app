// Garde-fou : les règles Storage lisent au plus DEUX documents Firestore.
//
// Firebase refuse tout accès Storage dont l'évaluation lit plus de deux documents
// Firestore distincts (firestore.get / firestore.exists). L'émulateur Storage
// n'applique pas cette limite : les tests de règles passent, puis tous les
// téléversements sont refusés en production. Ce test analyse donc le texte de
// storage.rules ; il ne remplace pas un essai réel après déploiement.
// Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const LIMITE = 2;

// Documents distincts lus par les appels firestore.get / firestore.exists. Un même
// chemin, appelé plusieurs fois, ne compte qu'une fois (Firebase le met en cache).
function documentsLus(regles) {
  const sansCommentaires = regles.replace(/\/\/.*$/gm, '');
  const appels = sansCommentaires.matchAll(/firestore\s*\.\s*(?:get|exists)\s*\(\s*(\/databases\/[^)]*\)[^)]*\)[^)]*?)\s*\)/g);
  const chemins = new Set();
  for (const [, chemin] of appels) chemins.add(chemin.replace(/\s+/g, ''));
  return [...chemins];
}

describe('Storage : limite de documents Firestore lus par les règles', () => {
  const regles = readFileSync(fileURLToPath(new URL('../../storage.rules', import.meta.url)), 'utf8');

  test('storage.rules lit au plus 2 documents Firestore distincts', () => {
    const lus = documentsLus(regles);
    assert.ok(lus.length > 0, 'aucun appel firestore.get/exists trouvé : l analyse ne reconnaît plus le fichier');
    assert.ok(lus.length <= LIMITE,
      `storage.rules lit ${lus.length} documents (${lus.join(' ; ')}) : au-delà de ${LIMITE}, ` +
      'Firebase refuse tous les accès en production (l émulateur, lui, ne le voit pas).');
  });

  test('seule la base (default) est lue', () => {
    for (const chemin of documentsLus(regles)) {
      assert.match(chemin, /^\/databases\/\(default\)\/documents\//);
    }
  });

  test('l analyse repère un troisième document, et ignore commentaires et doublons', () => {
    const trois = `
      // firestore.get(/databases/(default)/documents/ignore/$(x))
      function f() {
        return firestore.exists(/databases/(default)/documents/a/$(request.auth.uid))
          && firestore.get(/databases/(default)/documents/a/$(request.auth.uid)).data.x == 1
          && firestore.get(/databases/(default)/documents/b/$(s.id)).data.y == 2
          && firestore.get(/databases/(default)/documents/c/$(companyId)).data.z == 3;
      }`;
    assert.deepEqual(documentsLus(trois), [
      '/databases/(default)/documents/a/$(request.auth.uid)',
      '/databases/(default)/documents/b/$(s.id)',
      '/databases/(default)/documents/c/$(companyId)',
    ]);
  });
});
