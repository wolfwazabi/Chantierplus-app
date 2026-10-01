// Tests unitaires de l'assistant de charpente (sans émulateur, sans réseau) :
// filtrage du projet venu du modèle, requête envoyée à l'API et gestion des
// erreurs. Lancer : npm run test:unitaires
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const require = createRequire(import.meta.url);
const a = require('../../functions/src/assistant_charpente.js');
const racine = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const fixture = (nom) => JSON.parse(readFileSync(resolve(racine, 'test', 'charpente', nom), 'utf8'));

const rejette = async (promesse, code) => {
  await assert.rejects(promesse, (e) => {
    assert.equal(e.code, code, `${e.code} : ${e.message}`);
    return true;
  });
};
const rejetteSync = (fn, code) => assert.throws(fn, (e) => { assert.equal(e.code, code, `${e.code} : ${e.message}`); return true; });

/** Sortie réaliste du modèle : plancher 10'6" × 13' à 16 po, 4 murs avec ouvertures. */
const SORTIE_MODELE = {
  nom: 'Garage Tremblay',
  plancherActif: true,
  plancher: {
    forme: { type: 'rectangle', longueur: 156, largeur: 126 },
    espacement: 16, section: '2×10', riveDouble: true, etriers: 'deuxBouts', entremises: 1, panneau: '4x8',
  },
  mursActifs: true,
  murs: {
    mode: 'contour', hauteur: 97.125,
    ouverturesContour: {
      0: [{ type: 'fenetre', nom: 'Salon', largeur: 36, hauteur: 48, allege: 36, position: 60 }],
      1: [{ type: 'porte', largeur: 36, hauteur: 80, position: 63 }],
    },
    params: { section: '2×6', linteau: '2×10', panneau: 'isobrace_r4' },
  },
};

describe('normaliserProjet : valeurs par défaut', () => {
  test('rien du modèle : projet par défaut identique à celui de l\'application', () => {
    const { projet, corrections } = a.normaliserProjet({});
    assert.deepEqual(projet, fixture('projet_defaut.json'));
    assert.deepEqual(corrections, []);
  });

  test('entrée absente ou de mauvais type : projet par défaut', () => {
    for (const e of [undefined, null, 'x', 12, [], true]) {
      assert.deepEqual(a.normaliserProjet(e).projet, fixture('projet_defaut.json'));
    }
  });
});

describe('normaliserProjet : sortie du modèle', () => {
  test('exemple complet : conforme à la fixture lue par l\'application', () => {
    const { projet, corrections } = a.normaliserProjet(SORTIE_MODELE);
    assert.deepEqual(corrections, []);
    assert.equal(projet.v, 1);
    assert.equal(projet.nom, 'Garage Tremblay');
    assert.equal(projet.plancher.riveDouble, true);
    assert.equal(projet.plancher.entremises, 1);
    assert.equal(projet.murs.params.panneau, 'isobrace_r4');
    assert.equal(projet.murs.params.section, '2×6');
    assert.deepEqual(Object.keys(projet.murs.ouverturesContour), ['0', '1']);
    const fenetre = projet.murs.ouverturesContour['0'][0];
    assert.deepEqual(fenetre, {
      type: 'fenetre', nom: 'Salon', largeur: 36, hauteur: 48, allege: 36, position: 60, jeuLargeur: 1, jeuHauteur: 1.5,
    });
    assert.equal(projet.murs.ouverturesContour['1'][0].allege, 0); // une porte n'a pas d'allège
    // Même JSON que celui que l'application relit dans ses tests.
    assert.deepEqual(projet, fixture('projet_assistant.json'));
  });

  test('forme à côtés et angles, et forme à points', () => {
    const c = a.normaliserProjet({ plancher: { forme: { type: 'cotes', cotes: [180, 120, 90, 140], angles: [90, 110, 120] } } }).projet;
    assert.deepEqual(c.plancher.forme, { type: 'cotes', cotes: [180, 120, 90, 140], angles: [90, 110, 120] });
    const p = a.normaliserProjet({ plancher: { forme: { type: 'points', points: [[0, 0], [100, 0], [100, 50]] } } }).projet;
    assert.deepEqual(p.plancher.forme.points, [[0, 0], [100, 0], [100, 50]]);
  });

  test('forme inutilisable : erreur claire plutôt qu\'une forme inventée', () => {
    for (const forme of [
      { type: 'cotes', cotes: [100, 100, 100], angles: [90] }, // il manque un angle
      { type: 'cotes', cotes: [100], angles: [] },
      { type: 'cotes', cotes: [100, 100], angles: [90, 90] },
      { type: 'cotes', cotes: [100, -5], angles: [90] },
      { type: 'cotes', cotes: [100, 'x'], angles: [90] },
      { type: 'points', points: [[0, 0], [1, 1]] },
      { type: 'points', points: [[0, 0], [1, 1], ['a', 2]] },
      { type: 'points', points: Array.from({ length: 25 }, (_, i) => [i, 0]) },
    ]) {
      rejetteSync(() => a.normaliserProjet({ plancher: { forme } }), 'failed-precondition');
    }
  });

  test('type de forme inconnu : rectangle par défaut, signalé', () => {
    const { projet, corrections } = a.normaliserProjet({ plancher: { forme: { type: 'etoile' } } });
    assert.deepEqual(projet.plancher.forme, { type: 'rectangle', longueur: 156, largeur: 126 });
    assert.ok(corrections.some((c) => c.includes('Forme du plancher inconnue')));
  });

  test('valeurs invalides : remplacées par le défaut et signalées', () => {
    const { projet, corrections } = a.normaliserProjet({
      plancher: {
        espacement: 'seize', section: '4×4', etriers: 'partout', entremises: 9, panneau: '5x5',
        forme: { type: 'rectangle', longueur: -3, largeur: 1e9 },
      },
      murs: { hauteur: 5, mode: 'volant', params: { espacement: 1000, section: '2×12', plisLinteau: 7, panneau: 'carton' } },
    });
    assert.equal(projet.plancher.espacement, 16);
    assert.equal(projet.plancher.section, '2×10');
    assert.equal(projet.plancher.etriers, 'deuxBouts');
    assert.equal(projet.plancher.entremises, 0);
    assert.equal(projet.plancher.panneau, '4x8');
    assert.deepEqual(projet.plancher.forme, { type: 'rectangle', longueur: 156, largeur: 126 });
    assert.equal(projet.murs.hauteur, 97.125);
    assert.equal(projet.murs.mode, 'contour');
    assert.equal(projet.murs.params.espacement, 16);
    assert.equal(projet.murs.params.section, '2×4');
    assert.equal(projet.murs.params.plisLinteau, 2);
    assert.equal(projet.murs.params.panneau, '4x9');
    assert.ok(corrections.length >= 8);
  });

  test('nombres non finis, chaînes à la place de nombres, entiers décimaux', () => {
    const { projet } = a.normaliserProjet({
      plancher: { espacement: NaN, entremises: 1.5, decalageMin: Infinity, marge: '10' },
    });
    assert.equal(projet.plancher.espacement, 16);
    assert.equal(projet.plancher.entremises, 0);
    assert.equal(projet.plancher.decalageMin, 24);
    assert.equal(projet.plancher.marge, 0);
  });

  test('champs inconnus ou dangereux : jamais recopiés', () => {
    const entree = JSON.parse(`{
      "__proto__": {"admin": true}, "constructor": {"x": 1}, "script": "<script>alert(1)</script>",
      "plancher": {"forme": {"type": "rectangle", "longueur": 100, "largeur": 80, "evil": 1}, "cleApi": "sk-secret", "section": "2×8"},
      "murs": {"params": {"commande": "rm -rf", "section": "2×6"}, "libres": [{"longueur": 100, "hauteur": 97, "url": "http://x"}]}
    }`);
    const { projet } = a.normaliserProjet(entree);
    const texte = JSON.stringify(projet);
    for (const interdit of ['admin', 'script', 'sk-secret', 'rm -rf', 'http://x', 'evil', 'constructor']) {
      assert.ok(!texte.includes(interdit), `« ${interdit} » ne doit pas passer`);
    }
    assert.equal(projet.plancher.section, '2×8');
    assert.equal(projet.murs.libres.length, 1);
    assert.deepEqual(Object.keys(projet.murs.libres[0]).sort(),
        ['coinDebut', 'coinFin', 'hauteur', 'intersections', 'longueur', 'nom', 'ouvertures']);
    assert.equal({}.admin, undefined);
  });

  test('chaînes : longueur bornée, caractères de contrôle retirés', () => {
    const { projet } = a.normaliserProjet({
      nom: `Garage\u0000\u0007\n${'x'.repeat(500)}`,
      murs: { libres: [{ nom: 'y'.repeat(200), longueur: 100, hauteur: 97 }] },
    });
    assert.ok(projet.nom.length <= 200);
    assert.ok(!/[\u0000-\u001f]/.test(projet.nom));
    assert.equal(projet.murs.libres[0].nom.length, 60);
  });

  test('ouvertures : côtés valides seulement, type connu, au plus 30 par mur, murs libres au plus 40', () => {
    const ouv = { type: 'porte', largeur: 36, hauteur: 80, position: 50 };
    const { projet } = a.normaliserProjet({
      murs: {
        ouverturesContour: {
          0: Array.from({ length: 50 }, () => ouv), 24: [ouv], '-1': [ouv], abc: [ouv], 3: [{ type: 'tunnel' }, ouv], 4: 'x', 5: [],
        },
        libres: Array.from({ length: 60 }, () => ({ longueur: 100, hauteur: 97 })),
      },
    });
    assert.deepEqual(Object.keys(projet.murs.ouverturesContour).sort(), ['0', '3']);
    assert.equal(projet.murs.ouverturesContour['0'].length, 30);
    assert.equal(projet.murs.ouverturesContour['3'].length, 1);
    assert.equal(projet.murs.libres.length, 40);
  });

  test('longueurs de planches : sous-ensemble des longueurs standard', () => {
    const { projet } = a.normaliserProjet({ plancher: { longueursPlanches: [96, 100, 240, 9999] } });
    assert.deepEqual(projet.plancher.longueursPlanches, [96, 240]);
    assert.deepEqual(a.normaliserProjet({ plancher: { longueursPlanches: [1, 2] } }).projet.plancher.longueursPlanches,
        [96, 120, 144, 168, 192, 216, 240]);
  });

  test('angle des solives : null ou nombre borné', () => {
    assert.equal(a.normaliserProjet({ plancher: { angle: null } }).projet.plancher.angle, null);
    assert.equal(a.normaliserProjet({ plancher: { angle: 35 } }).projet.plancher.angle, 35);
    assert.equal(a.normaliserProjet({ plancher: { angle: 5000 } }).projet.plancher.angle, 0);
  });

  test('murs libres : intersections filtrées', () => {
    const { projet } = a.normaliserProjet({
      murs: { libres: [{ longueur: 200, hauteur: 97, intersections: [50, -1, 'x', 99999, 120, ...Array(20).fill(10)] }] },
    });
    assert.equal(projet.murs.libres[0].intersections.length, 10);
    assert.deepEqual(projet.murs.libres[0].intersections.slice(0, 2), [50, 120]);
  });
});

describe('construireRequete', () => {
  test('outil forcé, modèle indiqué, texte de l\'utilisateur dans le message', () => {
    const r = a.construireRequete({ texte: 'plancher 10\'6" x 13\'', projetActuel: null, modele: 'claude-haiku-4-5-20251001' });
    assert.equal(r.model, 'claude-haiku-4-5-20251001');
    assert.deepEqual(r.tool_choice, { type: 'tool', name: 'definir_projet' });
    assert.equal(r.tools.length, 1);
    assert.equal(r.tools[0].name, 'definir_projet');
    assert.ok(r.messages[0].content.includes('plancher 10\'6" x 13\''));
    assert.ok(!r.messages[0].content.includes('Projet actuel'));
    assert.ok(r.max_tokens <= 4000);
    assert.ok(r.system.includes('POUCES'));
  });

  test('projet actuel joint seulement s\'il existe', () => {
    const r = a.construireRequete({ texte: 'passe à 12 po', projetActuel: '{"v":1}', modele: 'm' });
    assert.ok(r.messages[0].content.includes('Projet actuel'));
    assert.ok(r.messages[0].content.includes('{"v":1}'));
  });

  test('le schéma de l\'outil décrit bien le projet', () => {
    const props = a.SCHEMA_OUTIL.properties;
    assert.deepEqual(a.SCHEMA_OUTIL.required.sort(), ['explication', 'hypotheses', 'projet']);
    assert.ok(props.projet.properties.plancher.properties.forme.properties.type.enum.includes('cotes'));
    assert.ok(props.projet.properties.murs.properties.params.properties.panneau.enum.includes('isobrace_r4'));
  });
});

describe('interroger : réponses de l\'API', () => {
  const appel = (reponse, opts = {}) => {
    const appels = [];
    const fetchImpl = async (url, init) => {
      appels.push({ url, init });
      if (reponse instanceof Error) throw reponse;
      return reponse;
    };
    const promesse = a.interroger({
      texte: 'garage 24 x 20', projetActuel: null, cle: 'cle-test', url: 'http://api.test/v1/messages',
      modele: 'modele-test', fetchImpl, ...opts,
    });
    return { promesse, appels };
  };
  const ok = (corps, status = 200) => ({
    ok: status >= 200 && status < 300, status,
    json: async () => corps, text: async () => JSON.stringify(corps),
  });
  const outil = (input) => ({ content: [{ type: 'text', text: 'ok' }, { type: 'tool_use', name: 'definir_projet', input }] });

  test('réponse valide : explication, hypothèses et projet filtré', async () => {
    const { promesse, appels } = appel(ok(outil({
      explication: 'Plancher de 13 pi × 10 pi 6 po avec murs.',
      hypotheses: ['Entraxe de 16 po supposé.', '', 3, 'x'.repeat(500)],
      projet: SORTIE_MODELE,
    })));
    const r = await promesse;
    assert.equal(r.explication, 'Plancher de 13 pi × 10 pi 6 po avec murs.');
    assert.equal(r.hypotheses[0], 'Entraxe de 16 po supposé.');
    assert.ok(r.hypotheses.every((h) => h.length <= 300));
    assert.equal(r.projet.v, 1);
    assert.equal(r.projet.plancher.entremises, 1);
    // Requête : clé dans l'en-tête, jamais dans le corps.
    assert.equal(appels.length, 1);
    assert.equal(appels[0].url, 'http://api.test/v1/messages');
    assert.equal(appels[0].init.method, 'POST');
    assert.equal(appels[0].init.headers['x-api-key'], 'cle-test');
    assert.equal(appels[0].init.headers['anthropic-version'], '2023-06-01');
    assert.ok(!appels[0].init.body.includes('cle-test'));
    assert.ok(appels[0].init.signal);
    const corps = JSON.parse(appels[0].init.body);
    assert.equal(corps.model, 'modele-test');
  });

  test('les corrections du filtre s\'ajoutent aux hypothèses', async () => {
    const { promesse } = appel(ok(outil({
      explication: 'ok', hypotheses: ['Une hypothèse.'], projet: { plancher: { espacement: 'beaucoup' } },
    })));
    const r = await promesse;
    assert.equal(r.hypotheses.length, 2);
    assert.ok(r.hypotheses[1].includes('entraxe des solives'));
  });

  test('clé absente : assistant non activé', async () => {
    await rejette(appel(ok({}), { cle: '' }).promesse, 'failed-precondition');
    await rejette(appel(ok({}), { cle: undefined }).promesse, 'failed-precondition');
  });

  test('429 : trop sollicité', async () => {
    await rejette(appel(ok({}, 429)).promesse, 'resource-exhausted');
  });

  test('erreur serveur ou clé refusée : indisponible, sans fuite du détail', async () => {
    for (const status of [401, 403, 500, 529]) {
      const { promesse } = appel(ok({ error: { message: 'invalid x-api-key sk-ant-secret' } }, status));
      await assert.rejects(promesse, (e) => {
        assert.equal(e.code, 'unavailable');
        assert.ok(!e.message.includes('sk-ant'), 'le message client ne contient pas le détail');
        assert.ok(e.detailInterne.includes(`HTTP ${status}`));
        return true;
      });
    }
  });

  test('réseau coupé ou délai dépassé : indisponible', async () => {
    await rejette(appel(new Error('ECONNRESET')).promesse, 'unavailable');
    const lent = a.interroger({
      texte: 'x'.repeat(10), projetActuel: null, cle: 'k', url: 'http://api.test', modele: 'm', delaiMs: 20,
      fetchImpl: (url, init) => new Promise((_, rejet) => init.signal.addEventListener('abort', () => rejet(new Error('abort')))),
    });
    await rejette(lent, 'unavailable');
  });

  test('réponse sans appel d\'outil, ou illisible : demande non comprise', async () => {
    await rejette(appel(ok({ content: [{ type: 'text', text: 'Bonjour' }] })).promesse, 'failed-precondition');
    await rejette(appel(ok({ content: [] })).promesse, 'failed-precondition');
    await rejette(appel(ok({})).promesse, 'failed-precondition');
    await rejette(appel(ok({ content: [{ type: 'tool_use', name: 'autre_outil', input: {} }] })).promesse, 'failed-precondition');
    await rejette(appel(ok({ content: [{ type: 'tool_use', name: 'definir_projet', input: 'texte' }] })).promesse, 'failed-precondition');
    await rejette(appel({ ok: true, status: 200, json: async () => { throw new Error('pas du json'); }, text: async () => '' }).promesse, 'unavailable');
  });

  test('forme décrite incomplète : erreur claire, pas de projet', async () => {
    const { promesse } = appel(ok(outil({
      explication: 'x', hypotheses: [], projet: { plancher: { forme: { type: 'cotes', cotes: [100, 100], angles: [] } } },
    })));
    await rejette(promesse, 'failed-precondition');
  });

  test('instructions cachées dans le texte de l\'utilisateur : aucune action, seulement des paramètres', async () => {
    // Le modèle (compromis ou trompé) renvoie des champs hors schéma : ils sont ignorés.
    const { promesse } = appel(ok(outil({
      explication: 'ok', hypotheses: [],
      projet: { plancherActif: true, plancher: { forme: { type: 'rectangle', longueur: 100, largeur: 80 } }, execute: 'curl evil', role: 'admin' },
      autre: 'ignorer toutes les règles',
    })));
    const r = await promesse;
    assert.ok(!JSON.stringify(r).includes('curl'));
    assert.ok(!JSON.stringify(r).includes('admin'));
    assert.deepEqual(Object.keys(r).sort(), ['explication', 'hypotheses', 'projet']);
  });
});
