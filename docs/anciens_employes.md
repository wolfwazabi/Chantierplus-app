# Anciens employés (retrait avec fiche conservée, loi 25)

Quand un admin retire un employé, celui-ci perd **tout accès** tout de suite, mais sa fiche reste un
temps limité dans « Anciens employés » pour pouvoir le **réactiver** (employés saisonniers). Demandé
par la session du site web client ; décidé par Philip (12 octobre 2026) : **24 mois**.

## Ce qui est conservé (et rien d'autre)

`employees/{id}` passe à `actif: false` et garde : nom, courriel, rôle, `retireLe` (date),
`supprimeApresLe` (date de suppression automatique, +24 mois) et `motifRetrait`. Le **NIP est détruit**
(`pinHash` et `pinModifieLe` supprimés), ainsi que les sessions, les liens d'invitation, les codes de
« NIP oublié » et les codes de connexion web en attente. Aucune note, aucun texte libre.

Le **motif** est une liste fermée de six valeurs : `non-precise` (défaut), `saisonnier`,
`depart-volontaire`, `fin-contrat`, `absence-prolongee`, `autre`. Volontairement **jamais du texte
libre** : un champ libre recevrait des renseignements de santé, qui sont sensibles (« absence
prolongée » couvre la maladie sans la nommer). Toute autre valeur est refusée (`invalid-argument`).

## Les fonctions

| Fonction | Rôle |
|---|---|
| `retirerAccesEmploye({employeeId, motif?})` | admin ; mêmes protections que `supprimerEmploye` (pas soi-même, pas le super-admin, seul le super-admin touche un admin, même compagnie) ; refuse un employé déjà retiré ; retourne `{ok, supprimeApresLe}` |
| `reactiverEmploye({employeeId})` | admin ; seulement un ancien employé (`failed-precondition` sinon) ; supprime `retireLe`, `supprimeApresLe`, `motifRetrait` ; **jamais l'ancien NIP** : lien à usage unique (7 jours) et courriel « Bon retour » ; 3 par heure et par employé ; même retour que `enregistrerEmploye` |
| `supprimerEmploye({employeeId})` | inchangée : efface la fiche **tout de suite** (droit à l'effacement), y compris celle d'un ancien employé ; les feuilles de temps déjà enregistrées restent dans les registres de la compagnie |
| `purgerAnciensEmployes` | planifiée chaque nuit à 3 h 30 (Montréal) : supprime les fiches `actif == false` dont `supprimeApresLe` est passé, avec le même nettoyage ; ne journalise qu'un **nombre** |

Refus des anciens employés partout : `connexionEmploye` et `connexionWeb` (échec générique),
`contexteEmploye` (toutes les fonctions), `firestore.rules` (`sessionEstValide`) et `storage.rules`
(sur l'employé déjà lu : toujours 2 documents au plus), « NIP oublié » (réponse neutre, aucun
courriel), lien de création du NIP, récupération du numéro de compagnie.
`enregistrerEmploye` refuse de modifier un ancien employé ou de reprendre son courriel
(« Cette personne figure dans « Anciens employés » : réactivez-la ou supprimez sa fiche. »).

Index Firestore : `employees (actif, supprimeApresLe)` pour la purge.

## Dans l'application

- **Admin → Employés** : la liste ne montre que les actifs (le filtre se fait dans l'application :
  Firestore ne sait pas chercher un champ absent). « Retirer » explique ce qui est gardé et pendant
  combien de temps, et propose le motif (liste, sans texte libre).
- Icône **Anciens employés** (en haut à droite) : retiré le, motif, suppression automatique le ;
  « Réactiver » (envoie le courriel d'invitation) et « Supprimer la fiche maintenant ».
- Un appareil dont l'employé vient d'être retiré est déconnecté.

## Déploiement

Règles Firestore et Storage + index, puis **toutes** les fonctions (`firebase deploy --only
firestore:rules,firestore:indexes,storage:montreal` puis `firebase deploy --only functions`), **avant**
le build de l'application. La première fois, le déploiement crée la tâche planifiée (Cloud Scheduler).
Tant que ce n'est pas déployé, l'espace web garde son drapeau `ARCHIVAGE_SERVEUR_PRET` à `false`.

## Tests

`tests/rules/functions.test.mjs` (« Anciens employés »), `firestore.test.mjs` / `storage.test.mjs`
(« anciens employés »), `anciens_employes.unit.test.mjs` (motifs, dates), `test/anciens_employes_test.dart`.
