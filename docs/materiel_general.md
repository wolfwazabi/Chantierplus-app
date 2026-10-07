# Matériel « Général » (remorque, sans chantier)

Liste de matériel pour tout ce dont un contremaître ou un admin a besoin pour sa remorque,
sans que ce soit pour un chantier précis.

## Où le trouver

- **Chantiers** (barre du bas) : « Général » est le **premier choix** de la liste de chantiers
  (et de la recherche « … »), toujours devant les chantiers, même alphabétiquement. Il ne
  contient que la liste de matériel (pas de photos, travaux, extras, documents ni calcul).
- **Admin → Chantiers** : la tuile « Général » est épinglée **en tête de la liste** (jamais
  archivée). Elle ouvre le matériel **séparé par contremaître et admin**.
- **Jamais dans les heures** : « Général » n'est pas un chantier. Il n'existe pas dans la
  collection `chantiers`, la feuille de temps ne le propose pas et le serveur le refuse
  (« Chantier introuvable »).

## Séparé par personne

Chaque demande porte son auteur (`ajoutePar`, `ajouteParNom` : l'employé connecté, imposé par
les règles Firestore).

- Côté contremaître / admin (Chantiers → Général) : puces **Mes ajouts** (par défaut),
  **Tous**, puis une puce par autre personne qui a ajouté du matériel. En « Tous », chaque
  demande indique « Par … ».
- Côté Admin (Admin → Chantiers → Général) : un groupe par personne (ordre alphabétique), avec
  « N à acheter • M obtenus ». Ouvrir un groupe montre ses demandes ; l'admin peut marquer une
  demande obtenue (achetée), la remettre comme manquante ou la supprimer.

## Pastille « changement non vu »

Une pastille rouge avec un nombre apparaît sur le groupe d'une personne, sur la tuile
« Général » et sur la tuile « Chantiers » de l'écran Admin.

- Un **changement** = une nouvelle demande ou une modification (texte, quantité, photo,
  obtenue / manquante) faite par **quelqu'un d'autre** que vous, après votre dernière visite
  de ce groupe. Vos propres gestes n'allument jamais votre pastille.
- **Ouvrir le groupe** = l'avoir vu : sa pastille s'éteint (les autres restent). Tant que la
  page reste ouverte, les demandes nouvelles ont un point rouge « Nouveau ».
- Chaque admin a sa propre visite : la collection `materiel_general_vus`, un document par admin
  `{ companyId, vus: { idAuteur: horodatage } }`, lisible et modifiable par lui seul.
- Les modifications sont signées : `dateModif` et `modifiePar` (heure du serveur et employé
  connecté, imposés par les règles).
- Une demande **supprimée** disparaît de la liste sans pastille.

## Données et sécurité

| Élément | Règle |
|---|---|
| `chantier_materiel` avec `chantierId == '_general'` | admin et contremaître ; auteur obligatoire et vérifié ; seulement le matériel (refusé pour travaux, extras, photos, documents) |
| `chantiers/_general` | jamais créable comme vrai chantier |
| `materiel_general_vus/{idAdmin}` | lecture et écriture par cet admin seulement |
| Photos | `chantiers/<compagnie>/_general/chantier_materiel/` (mêmes règles Storage que les autres photos de matériel) |
| Suppression d'une compagnie | efface aussi `materiel_general_vus` et le dossier `_general` du Storage |

## Déploiement

- **Règles Firestore à déployer AVANT le nouveau build** : sans elles, ajouter du matériel
  dans Général est refusé, et la pastille ne peut pas enregistrer ce qui a été vu.
- Fonction `supprimerCompagnie` à redéployer (elle efface la nouvelle collection).

## Tests

`flutter test test/materiel_general_test.dart test/materiel_general_ecrans_test.dart` ;
règles : `cd tests/rules && npm run test:regles` ; serveur : `npm run test:functions`.
