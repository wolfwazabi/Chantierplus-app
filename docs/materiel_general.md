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

## Chaque contremaître ne voit que SA liste

Un **contremaître** ne voit, ne modifie et ne supprime que **ses propres** demandes dans
Général : les listes des autres lui sont fermées, par l'application **et** par les règles du
serveur (sa requête doit nommer son identifiant, sinon elle est refusée). Un **admin** voit
toutes les listes.

## Séparé par personne

Chaque demande porte son auteur (`ajoutePar`, `ajouteParNom` : l'employé connecté, imposé par
les règles Firestore).

- Côté admin (Chantiers → Général) : puces **Mes ajouts** (par défaut),
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

## Appui long (admin, Admin → Chantiers → Général)

- **Sur une demande** : « Marquer comme non lu » (la pastille de la personne se rallume jusqu'à
  ce qu'on rouvre son groupe) ou « Transférer à la Liste d'achats ». Les mêmes actions sont dans
  le menu ⋮ de la demande.
- **Sur une personne** : « Marquer comme non lu » marque toutes ses demandes à acheter.
- Les drapeaux « non lu » sont personnels (document `materiel_general_vus`, champ `nonLus`) et
  tombent à l'ouverture du groupe.

## Admin → Liste d'achats

Reçoit les demandes transférées : l'article garde le texte, la quantité, les photos, **qui l'a
demandé** (équipe) et qui l'a transféré. Le transfert crée l'article **et** marque la demande
d'origine (`transfere`, `transfereParNom`) d'un seul geste, tout ou rien.

**La demande reste visible pour le contremaître jusqu'à ce qu'elle soit achetée.** Dans sa liste,
elle porte la mention « Dans la Liste d'achats (transféré par X) » ; il ne peut plus la modifier
ni la supprimer (elle n'est plus « à acheter » pour lui). Quand l'admin marque l'article acheté
dans la Liste d'achats, la demande d'origine est marquée **obtenue** et passe dans l'historique du
contremaître ; si l'admin remet l'article à acheter, elle revient ; si l'admin retire l'article de
la Liste, la mention disparaît et le contremaître retrouve sa demande (la mise à jour de la
demande d'origine se fait au mieux : l'article reste la référence).

La page sépare les articles **à acheter par équipe** (ordre alphabétique, plus récent d'abord) ;
chaque article se marque acheté (il passe dans « Achetés », replié), se remet à acheter ou se
retire. Collection `liste_achats`, admin seulement.

## Plusieurs photos

Une demande (matériel ou travaux, Général comprise) accepte **jusqu'à 6 photos** : `photoUrl` (la
première, pour l'export et les anciennes versions) et `photoUrls` (toutes). Les anciennes demandes
à une seule photo se lisent comme avant. Dans l'application : « Ajouter » choisit plusieurs photos
d'un coup (ou une à la fois avec l'appareil), chaque vignette se retire avant l'envoi, et la
modification garde, retire ou ajoute des photos. Les fichiers retirés ou orphelins (envoi
interrompu) sont supprimés du Storage. Même fonctionnement pour les extras (`photoUrl` +
`cheminPhoto` pour la première, `photoUrls` + `cheminsPhotos` pour toutes, listes parallèles). Dans
l'export du dossier : la première photo garde son nom, les suivantes portent `_2`, `_3`…, le HTML
les lie (« photo », « photo 1 »…) et l'Excel les joint dans une cellule (`; `).

## Données et sécurité

| Élément | Règle |
|---|---|
| `chantier_materiel` avec `chantierId == '_general'` | admin et contremaître ; auteur obligatoire et vérifié ; seulement le matériel (refusé pour travaux, extras, photos, documents) |
| `chantiers/_general` | jamais créable comme vrai chantier |
| `materiel_general_vus/{idAdmin}` | lecture et écriture par cet admin seulement (`vus`, `nonLus`) |
| `chantier_materiel` Général, lecture / modification / suppression | un contremaître : seulement ses demandes ; un admin : toutes |
| `liste_achats/{id}` | admin seulement ; création signée par l'admin qui transfère ; seuls `complete` et `dateComplete` se modifient |
| Demande transférée (`transfere`, `transfereParNom`) | posés par un admin seulement ; le contremaître ne peut plus la modifier ni la supprimer |
| Photos | jusqu'à 6 par demande ; `chantiers/<compagnie>/_general/chantier_materiel/` (mêmes règles Storage que les autres photos de matériel) |
| Suppression d'une compagnie | efface aussi `materiel_general_vus`, `liste_achats` et le dossier `_general` du Storage |

## Déploiement

- **Règles Firestore à déployer AVANT le nouveau build** : sans elles, ajouter du matériel
  dans Général est refusé, la pastille ne peut pas enregistrer ce qui a été vu, et la liste
  privée du contremaître (requête sur son identifiant) et la Liste d'achats ne fonctionnent pas.
- Fonction `supprimerCompagnie` à redéployer (elle efface la nouvelle collection).

## Tests

`flutter test test/materiel_general_test.dart test/materiel_general_ecrans_test.dart` ;
règles : `cd tests/rules && npm run test:regles` ; serveur : `npm run test:functions`.
