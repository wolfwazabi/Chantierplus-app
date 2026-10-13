# Calcul à partir d'un plan (PDF ou photos)

Dans **Chantier → Calcul → Charpente**, l'icône « téléverser » (à côté de l'assistant IA)
ouvre **Calculer à partir d'un plan**. On joint le plan, l'assistant le lit, on vérifie ce
qu'il a lu, puis l'application calcule les matériaux comme si on avait tout saisi à la main.

Accès : admin et contremaître (comme l'assistant IA). Les employés n'y ont pas accès.

## Déroulement

1. **Joindre** : un PDF ou une image du téléphone, des photos de la galerie, ou une photo
   prise sur place (jusqu'à 5 fichiers, 8 Mo chacun, 12 Mo au total ; PDF, JPEG, PNG, WebP).
   On peut préciser (« seulement le garage », « le rez-de-chaussée est à la page 2 »).
2. **Lecture** (20 secondes à 2 minutes) : le plan est envoyé au serveur, qui interroge
   le modèle. Le modèle ne calcule rien : il relève la forme du plancher, la hauteur des
   murs et **chaque porte et fenêtre** (type, repère, largeur, hauteur, allège, position,
   mur), et signale ce dont il n'est pas sûr.
3. **Vérification** (écran « Plan lu ») :
   - **À confirmer** : les valeurs incertaines (illisibles, floues, absentes du plan et
     supposées, ou dont la cote imprimée ne correspond pas à la valeur lue). Chacune
     montre ce qui a été lu, la raison du doute, la cote telle qu'imprimée sur le plan et
     un champ pour corriger. **Rien ne s'applique tant que chacune n'est pas confirmée à
     la main.** Corriger une valeur retire sa confirmation : on confirme la valeur finale.
   - **À vérifier** : les valeurs déduites (somme de cotes, échelle, tableau). Non bloquant.
   - **Hypothèses** de l'assistant, **ce qui a été lu** (plancher, chaque mur, chaque porte
     et fenêtre), et les **cotes lues** avec la mention « vérifié » quand le serveur a
     converti lui-même la cote imprimée et obtenu la même valeur.
   - **Aperçu 3D** (toucher pour l'agrandir) pour comparer au plan, et **matériaux
     calculés**, mis à jour à chaque correction.
4. **Appliquer** : le projet remplace le calcul en cours (avec confirmation s'il y en a
   un ; les lignes ajoutées à la main sont conservées) et l'application ouvre la commande.

## Ce qui est calculé, et ce qui ne l'est pas

Plancher et murs (portes et fenêtres comprises), comme le reste du module (voir
`calcul_charpente.md`). **Pas de toiture, de fondations ni d'escalier** à partir du plan :
l'assistant l'indique s'il en voit. Le dimensionnement structural n'est pas vérifié.

## Garde-fous (pourquoi on peut s'y fier… à condition de confirmer)

- **Le modèle ne calcule pas le bois.** Il remplit les mêmes paramètres que l'assistant
  texte ; tout ce qui revient est filtré (liste blanche de champs, bornes, valeurs permises)
  avant d'atteindre l'application.
- **Les cotes sont revérifiées par le serveur.** Pour chaque cote relevée, le modèle recopie
  le texte imprimé (« 12'-6" », « 3050 mm ») ; le serveur le convertit lui-même (pieds-pouces,
  mm, cm, m) et compare : un écart de plus de 1/4 po marque la valeur « incertaine » et propose
  la valeur du plan (« Utiliser cette valeur »). Les conversions fausses d'un modèle sont ainsi
  attrapées.
- **Les oublis deviennent des confirmations.** Une dimension de porte ou de fenêtre, la
  position, la hauteur des murs ou une cote du plancher que le modèle n'a pas donnée n'est
  jamais remplacée en silence par une valeur par défaut : elle est marquée « incertaine ».
- **Position des portes et fenêtres.** Sur un plan elle se mesure du coin extérieur ; dans
  l'application, du début du mur (raccourci de 3 1/2 po là où il s'appuie sur le mur voisin).
  L'application fait cette conversion elle-même, avec la même géométrie que le calcul des murs.
- Les fichiers sont vérifiés d'après leur **contenu réel** (PDF, JPEG, PNG, WebP), pas leur nom.
- **Confidentialité** : le plan est envoyé à l'API d'IA pour la lecture ; Chantier+ ne le
  conserve pas. L'écran le dit avant l'envoi.
- Limites : 6 lectures par heure et par employé, 30 par jour et par compagnie.

## Côté serveur

`functions/src/lecture_plans.js`, fonction `lirePlanCharpente` (`functions/index.js`) :
délai de 240 s, 1 Gio de mémoire, même secret `ANTHROPIC_API_KEY` que l'assistant
(voir `calcul_charpente.md`). Le modèle se règle par le paramètre `MODELE_PLANS`
(`functions/.env.boreal-8cd7c`, `claude-sonnet-5-5` par défaut) ; un modèle plus précis coûte
plus cher par plan. Si le modèle refuse le réglage `temperature`, une seconde tentative est
faite sans lui. Les erreurs de l'API (clé refusée, crédit épuisé, PDF protégé ou trop de pages)
deviennent des messages clairs ; le détail reste dans les journaux.

Déploiement : `firebase deploy --only functions:lirePlanCharpente` (la fonction est nouvelle ;
la suppression d'une compagnie nettoie aussi ses compteurs `plan_h_` et `plan_j_`).

## Tests

- Serveur : `tests/rules/lecture_plans.unit.test.mjs` (fichiers, conversion des cotes, filtrage
  et chemins, valeurs manquantes, erreurs de l'API) et le bloc « Lecture de plans » de
  `functions.test.mjs` (rôles, limites, clé jamais dans le corps, sortie filtrée).
- Contrat serveur ↔ application : `test/charpente/lecture_plan_garage.json` est la sortie réelle
  du serveur ; les tests Dart la relisent. Pour la régénérer après un changement voulu :
  `REGENERER_FIXTURE=1 npm run test:unitaires` (dans `tests/rules`).
- Application : `test/charpente/lecture_plan_test.dart` (modèle, confirmation, positions),
  `test/lire_plan_screen_test.dart` (écran), `test/charpente/ecran_charpente_test.dart`.

## Ce qui n'a PAS été testé

La lecture par le vrai modèle sur de vrais plans : les tests simulent l'API. Premier essai à
faire avec un plan réel, en comparant chaque valeur affichée au plan.
