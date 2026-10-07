# Suppression d'une compagnie

Réservée au **Proprio de l'application** (la fiche employé désignée dans
`config/proprio_app`). Onglet **Compagnies** → bouton « Supprimer la compagnie »
sous chaque compagnie (quel que soit son statut : en attente, approuvée, refusée).

## Ce qui est supprimé (définitivement, sans copie)

- les employés de la compagnie : super-admin, admins, contremaîtres, employés, avec
  leurs sessions, liens de création de NIP, codes de réinitialisation et compteurs ;
- les chantiers, photos, documents, travaux, matériel (dont la liste « Général » de la
  remorque et le registre « déjà vu » de chaque admin, `materiel_general_vus`), extras,
  commandes de charpente et feuilles de temps ;
- les fichiers du Storage (`chantiers/<compagnie>/` et `exports/<compagnie>/`) ;
- les données privées de la compagnie (`companies_prive`) et sa fiche.

Reste seulement une trace dans `journal_suppressions/<compagnie>` : numéro, nom,
statut d'avant, date, auteur et décompte. Aucun courriel ni nom d'employé. Cette
collection n'est lisible que par le serveur.

Les comptes anonymes Firebase Auth des appareils ne sont pas touchés (ils ne
contiennent rien) ; sans session, ils ne donnent accès à rien.

## Garde-fous

1. **Proprio seulement** : toute autre personne (super-admin de la compagnie visée
   compris) reçoit « permission refusée ».
2. **Double vérification dans l'app** : (1) un écran liste ce qui sera supprimé ;
   (2) il faut saisir le **numéro exact** de la compagnie.
3. **Le serveur vérifie le numéro** une troisième fois : un numéro absent, faux ou
   celui d'une autre compagnie est refusé et rien n'est modifié.
4. **La compagnie du Proprio est intouchable** (le bouton n'apparaît pas et le
   serveur refuse).
5. **Verrouillage immédiat** : dès la vérification, la compagnie passe au statut
   `suppression` ; connexions et accès Firestore sont refusés, sessions coupées,
   avant l'effacement des données.
6. **Reprise** : la fiche de la compagnie est effacée en dernier. Si la suppression
   s'interrompt (réseau, délai), la compagnie reste « Suppression en cours » et le
   bouton devient « Reprendre la suppression » : un nouvel appel (avec le numéro)
   termine le travail sans rien dupliquer.

## Déploiement

```
firebase deploy --only functions:supprimerCompagnie
firebase deploy --only firestore:rules
```

puis une nouvelle version de l'app (Codemagic) pour le bouton. La fonction attend
jusqu'à 9 minutes (`timeoutSeconds: 540`) ; l'app attend aussi 9 minutes.

## Tests

`cd tests/rules && npm run test:functions` (émulateurs) : refus de tous les autres
rôles, numéros faux, identifiants forgés, compagnie du Proprio, suppression complète
avec une compagnie témoin intacte, reprise après interruption, journal sans donnée
personnelle. Côté app : `flutter test test/confirmation_suppression_compagnie_test.dart`.
