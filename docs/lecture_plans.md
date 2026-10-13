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

## Pages agrandies (plans grand format)

Les plans de permis (feuilles 24 × 36 po à 1/4 po = 1 pi) n'ont souvent aucune couche de texte : les cotes
sont dessinées en traits, et à la taille d'une image ordinaire elles font quelques pixels. Le serveur
(`functions/src/rendu_plans.js`) rend donc chaque page en grand (environ 4200 px), puis l'envoie au modèle en
vue d'ensemble et en morceaux agrandis qui se chevauchent (les morceaux blancs sont omis ; 6 pages et 60 images
au plus). Un PDF avec une vraie couche de texte est joint aussi tel quel. Un PDF que le serveur ne sait pas lire
part tel quel, comme avant. Les grandes photos (plus de 2200 px) sont découpées de la même façon.

## Garde-fous (pourquoi on peut s'y fier… à condition de confirmer)

- **Le modèle ne calcule pas le bois.** Il remplit les mêmes paramètres que l'assistant
  texte ; tout ce qui revient est filtré (liste blanche de champs, bornes, valeurs permises)
  avant d'atteindre l'application.
- **Les cotes sont revérifiées par le serveur.** Pour chaque cote relevée, le modèle recopie
  le texte imprimé (« 12'-6" », « 3050 mm ») ; le serveur le convertit lui-même (pieds-pouces,
  mm, cm, m) et compare : un écart de plus de 1/4 po marque la valeur « incertaine » et propose
  la valeur du plan (« Utiliser cette valeur »). Les conversions fausses d'un modèle sont ainsi
  attrapées.
- **Le garde-fou ne repose pas sur le modèle.** Chaque longueur qui décide du calcul (cotes du
  plancher, hauteur des murs, largeur, hauteur, allège et position de chaque porte et fenêtre,
  murs libres) doit avoir sa fiche : sans fiche, elle est marquée « incertaine » (à confirmer) ;
  donnée comme « lue » sans cote imprimée que le serveur ait pu comparer, elle passe au moins à
  « à vérifier ». Une position se calcule à partir d'autres cotes : elle est toujours « à vérifier »
  au mieux. Une dimension oubliée n'est jamais remplacée en silence par une valeur par défaut.
- **Les défauts sont dits.** Section et entraxe des solives et des montants non donnés par le plan :
  fiches « à vérifier » corrigeables ; les jeux autour des portes et fenêtres (1 po et 1 1/2 po)
  sont annoncés dans les hypothèses ; des coins donnés dans le sens horaire aussi.
- **Structure du plancher.** Poutres (nombre, plis, section), pieux par poutre, premier pieu et étriers ont
  leur fiche, comme les cotes : à confirmer si le modèle ne les a pas relevés, à vérifier sinon.
- **Ce qui ne passe pas dans les murs.** Chaque porte et fenêtre est vérifiée : trop près d'un coin,
  chevauchement, et surtout le linteau sous la lisse haute (allège + cadre + jeu + linteau ≤ hauteur du mur −
  lisses). La revue liste TOUS les problèmes avec le calcul (« … = 8' 8", lisse à 7' 9" : il manque 11" ») ;
  le serveur marque ces hauteurs « à confirmer » et le modèle doit dire comment le plan le règle (poutre qui
  sert de linteau, imposte dans le pignon, mur plus haut).
- **Rien ne disparaît sans bruit.** Une porte ou fenêtre placée sur un mur qui n'existe pas dans la
  forme du plancher est signalée en rouge (elle ne serait pas comptée).
- **Position des portes et fenêtres.** Sur un plan elle se mesure du coin extérieur ; dans
  l'application, du début du mur (raccourci de 3 1/2 po là où il s'appuie sur le mur voisin).
  L'application fait cette conversion elle-même, avec la même géométrie que le calcul des murs.
- Les fichiers sont vérifiés d'après leur **contenu réel** (PDF, JPEG, PNG, WebP), pas leur nom.
- **Confidentialité** : le plan est envoyé à l'API d'IA pour la lecture ; Chantier+ ne le
  conserve pas. L'écran le dit avant l'envoi.
- Limites : 6 lectures par heure et par employé, 30 par jour et par compagnie (réservation
  atomique : des appels simultanés ne la dépassent pas). Une photo de plus de 5 Mo est refusée
  (limite de l'API) ; un PDF peut aller jusqu'à 8 Mo.

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

## Limites connues

- « Conversion vérifiée » signifie que le serveur a retrouvé, en convertissant la cote imprimée, la
  valeur du modèle ; pas que le plan a été lu correctement : c'est ce que la confirmation à la main
  couvre.
- L'attribution d'une porte ou fenêtre à un mur (le numéro du côté) dépend de l'orientation que le
  modèle choisit ; il doit dire quel mur est le côté 0 (hypothèses). Comparer avec l'aperçu 3D.
- Une porte changée en fenêtre dans la revue prend une allège de 36 po ; on la corrige alors dans la
  fiche de l'ouverture au prochain calcul (Murs).
- Le corps d'une requête peut atteindre environ 16 Mo : à confirmer en déploiement.

## Essai avec de vrais plans (13 oct. 2026)

Quatre plans de permis (solariums et véranda sur pieux vissés) et un contrat de fenêtres ont été lus à la main
puis passés dans le vrai filtre du serveur et le vrai calcul (sans l'API). Constats :
- Les plans contiennent tout le plancher : dimensions, solives, poutres, pieux, côté de la maison. Une lecture
  correcte, avec les réglages habituels de l'entrepreneur (bordures et rive avant doublées, entremises
  alternées, hauteur de patte), redonne ses commandes réelles (voir `exemples_reels_plancher.md`).
- Ces réglages habituels ne sont pas sur les plans : sans eux, la lecture commande moins de solives.
- Trois des quatre projets ont des murs en panneaux préfabriqués : pas d'ossature à calculer. Le quatrième
  (murs 2x6) a des vitrages jusqu'à la sablière et dans le pignon : le calcul des murs le signale.
- Un solarium de 12 × 10 pi commandait cinq 2x8 de 20 pi pour ses solives de 10 pi : corrigé (des planches à
  la mesure des pièces quand ça ne coûte pas plus de bois).

## Ce qui n'a PAS été testé

La lecture par le vrai modèle sur de vrais plans : les tests simulent l'API. Premier essai à
faire avec un plan réel, en comparant chaque valeur affichée au plan.
