# Fil « Activité » (Admin)

Une catégorie **Activité** en tête de l'écran Admin : ce qui vient d'être saisi ou modifié, du plus récent
au plus ancien, avec **une pastille sur la tuile** (le nombre de nouveautés) et **un point rouge à côté de
chaque nouveauté** dans la liste.

```
Changements apportés aux heures par Félix           6:24 2026/07/10
Nouvelle photo sur projet Brouillard par Jeremy     17:10 2026/07/09
Nouveau matériel manquant sur projet Brouillard par Jeremy   17:01 2026/07/09
Heures entrées par Jeff                             15:30 2026/07/06
```

## Ce qui apparaît

| Sorte | Phrase | D'où ça vient |
|---|---|---|
| Heures | « Heures entrées par X » (première saisie), « Changements apportés aux heures par X » (mise à jour), « Heures de X modifiées par Y » (corrigées par un admin) | `feuilles_temps` : `creeLe`, `dateModification`, `modifieParId/Nom` (écrits par le serveur) |
| Photos | « Nouvelle photo sur projet P par X » | `chantier_photos` |
| Matériel (chantiers et Général) | « Nouveau matériel manquant sur projet P par X » | `chantier_materiel` |
| Travaux | « Nouveau travail à faire sur projet P par X » | `chantier_travaux` |
| Extras | « Nouvel extra sur projet P par X » | `chantier_extras` |
| Documents | « Nouveau document sur projet P par X » | `chantier_documents` |
| Achats | « Matériel transféré à la Liste d'achats par X » | `liste_achats` |

Sous la phrase : la date (« 17:10 2026/07/09 ») et le détail (texte du matériel, nom du document…).
Des **filtres** par sorte (avec leur propre pastille) permettent de ne voir que les photos, les heures, etc.

Les éléments créés **avant** cette mise à jour n'ont pas de nom d'auteur : ils s'affichent « par un employé ».
Seuls les **ajouts** (et les heures) sont suivis ; marquer du matériel « obtenu » ou modifier un texte ne
crée pas de ligne pour l'instant.

## Les pastilles

- Un changement est **nouveau** s'il date d'**après votre dernière visite** et n'est **pas de vous** :
  vos propres gestes n'allument jamais votre pastille.
- La **première fois**, rien n'est nouveau (on ne signale pas tout l'historique).
- Les pastilles **restent pendant la visite** ; elles s'éteignent quand vous **quittez la page**, ou tout de
  suite avec **« Tout marquer comme vu »** (icône en haut à droite).
- Chaque admin a sa propre visite : `activite_vus/{idAdmin}` = `{companyId, vuJusqua}` ; lisible et
  modifiable par lui seul ; la date ne peut pas être dans le futur.
- Tirer vers le bas actualise le fil.

## Qui a fait le geste

Pour savoir « par qui », les photos, le matériel et les travaux d'un chantier, et les documents, notent
maintenant leur auteur (`ajoutePar`, `ajouteParNom`) : champ **facultatif** (les anciennes versions de
l'application continuent de fonctionner), et, s'il est présent, **forcément l'employé connecté** (règles
Firestore). Les feuilles de temps notent leur date de création et le dernier acteur côté **serveur**.

## Déploiement

1. Règles Firestore **et** index (`firebase deploy --only "firestore:rules,firestore:indexes,storage:montreal"`) :
   **avant** le build de l'application, sinon l'ajout d'une photo ou de matériel serait refusé (champs de
   l'auteur inconnus des anciennes règles). Les nouveaux index mettent quelques minutes à se construire :
   le fil se remplit après.
2. Fonctions (`firebase deploy --only functions`) : l'inscription de la date de création et du dernier acteur
   des heures, et la suppression de compagnie qui efface aussi `activite_vus`.
3. Build Codemagic.

## Tests

`test/activite_test.dart` (phrases, nouveautés, lecture réunie, écran, tuile), `tests/rules/firestore.test.mjs`
(« Fil Activité »), `tests/rules/functions.test.mjs` (« la feuille garde sa date de création »).
