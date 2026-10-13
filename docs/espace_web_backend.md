# Espace client web : ce que le serveur offre

Demandé par la session « Construire le site web Chantier+ » (espace `client.chantierplus.app`,
réservé aux super-admins, admins et contremaîtres). Tout est côté serveur : le navigateur n'est
jamais l'autorité. **Rien de ceci ne change `connexionEmploye` ni l'application mobile.**

## 1. Connexion web en deux étapes

| Étape | Fonction | Entrée | Résultat |
|---|---|---|---|
| 1 | `connexionWeb` | `numeroCompagnie`, `courriel`, `pin` | `{etape: "code", expireDans: 600, courrielMasque: "p***@gmail.com"}` |
| 2 | `validerConnexionWeb` | `code` (6 chiffres) | même réponse que `connexionEmploye` (`id, nom, courriel, role, estProprietaire, estProprioApp, companyId, companyNom`) |

**Étape 1.** Mêmes validations et mêmes limites que `connexionEmploye` (10 échecs / 15 min par adresse IP,
30 / 15 min par compagnie, message unique « Numéro de compagnie, courriel ou NIP invalide. »).
Un employé (rôle `employe`) avec le bon NIP reçoit `permission-denied` « Cet espace est réservé aux
super-admins, admins et contremaîtres. » : aucune session, aucun code, aucun courriel. Pour un admin ou
un contremaître, un code à 6 chiffres est écrit sous forme d'empreinte dans `connexions_web/{uid}`
(serveur seul, expire dans 10 min) et envoyé par courriel (sujet « Code de connexion — Chantier+ »).
Limite d'envoi : 5 par heure et par employé. Si le courriel ne part pas, le code est supprimé et
l'erreur `unavailable` est retournée. Une nouvelle demande remplace le code précédent.

**Étape 2.** Le code ne sert qu'à l'appareil qui l'a demandé (le document porte l'identifiant de session
anonyme). Mauvais code : `permission-denied` « Code invalide. », compté ; au 5e échec le code est
supprimé (`resource-exhausted`) et il faut recommencer l'étape 1. Code absent ou expiré :
`failed-precondition` « Code expiré. Recommencez. ». Le format doit être exactement 6 chiffres
(`invalid-argument` sinon, sans consommer d'essai). Au succès le code est consommé (usage unique) et
`sessions/{uid}` reçoit `canal: "web"` et `expireLe` (+12 h). Entre les deux étapes l'employé peut avoir
été retiré, rétrogradé en « employé » ou sa compagnie bloquée : le serveur revérifie, sans session à la clé.

Chaque erreur de l'étape 2 porte `details.raison` pour que le client n'ait pas à lire le texte :
`code-invalide` (on peut réessayer), `code-expire`, `essais-epuises`, `session-invalide`,
`role-refuse` (tout sauf `code-invalide` : retour à l'étape 1).

Un retrait d'employé, un changement ou une réinitialisation de NIP effacent aussi ses codes en attente.
La suppression d'une compagnie efface ses `connexions_web`.

## 2. Expiration des sessions web

`sessions/{uid}.expireLe` n'existe que pour les sessions web. Il est respecté dans :

- `firestore.rules` : `sessionEstValide` (`!('expireLe' in s) || s.expireLe > request.time`) ;
- `storage.rules` : `sessionValide`, même condition, **sur le document de session déjà lu** (aucune
  lecture Firestore de plus : la limite de 2 documents reste respectée, `storage_limite.unit.test.mjs`) ;
- `functions/src/commun.js` : `contexteEmploye` refuse avec « Session expirée. Reconnectez-vous. ».

Un `expireLe` illisible (texte, nombre, null) est traité comme expiré. Les sessions de l'application
n'ont pas ce champ : elles ne changent pas.

## 3. `corrigerFeuilleTemps` (admin)

Entrée `{employeeId, lundiDate, jours}` (mêmes formats que `enregistrerFeuilleTemps`). L'employé doit
appartenir à la compagnie de l'admin (sinon `not-found`). Même calcul serveur que la saisie normale
(corps commun `calculerEtEnregistrerFeuille`) : aucune valeur de paie ne vient du client. Pas de
verrouillage du mardi 18 h, mais pas de saisie au-delà de la semaine prochaine. Limite : 200 par heure et
par admin (compteur `corrfeuille_`, distinct de celui de la saisie normale). Pour une **semaine passée**
déjà enregistrée, les règles de paie copiées dans la feuille servent à recalculer les journées modifiées
(les journées inchangées gardent leurs valeurs d'origine) : une correction ne réécrit pas le passé avec
les règles d'aujourd'hui. La semaine courante et la suivante utilisent les règles actuelles.
Une journée envoyée vide n'efface jamais une journée déjà soumise.

**Historique des corrections** (`corrections`, écrit par le serveur seulement, ici comme dans
`enregistrerFeuilleTemps`) : chaque journée déjà soumise puis modifiée ajoute une entrée
`{jour, le, par, parRole, changements, heuresAvant, heuresApres}` :

- `jour` : index de la journée (0 = lundi) ; `le` : même ISO que `jours[jour].modifieApresVerrouillageLe` ;
- `par` / `parRole` : `employeeId` et rôle de l'**appelant** (l'admin qui corrige, ou l'employé
  lui-même) ; aucun nom de personne (Loi 25) ;
- `changements` : `[{champ, avant, apres}]` pour `chantierNom` (les noms ; comparé aussi par
  identifiant), `estAucun`, `heureDebutMinutes`, `heureFinMinutes`, `pauseMatin`, `diner`,
  `tempsVoyagementMinutes` ; un champ absent d'une ancienne journée vaut sa valeur par défaut
  (pas de faux changement) ;
- `heuresAvant` / `heuresApres` : heures travaillées de la journée (`null` si non travaillée).

Champ absent tant qu'aucune correction n'a eu lieu ; renvoi identique = rien d'ajouté ; au plus
60 entrées (les plus anciennes partent). Les feuilles individuelles (écrites par l'app) n'en ont pas.
Lisible par l'employé (sa feuille) et par l'admin ; aucun client ne peut l'écrire.

## 4. Renvoi d'invitation : `enregistrerEmploye` avec `renvoiInvitation: true`

Pour un employé qui n'a pas encore créé son NIP : un nouveau lien (7 jours, une seule fois) remplace
l'ancien et un courriel « Rappel : créez votre NIP — Chantier+ » est envoyé (numéro de compagnie, courriel
de connexion, lien). **Ne touche ni au NIP ni aux sessions.** Refusé (`failed-precondition` « Cet employé
a déjà créé son NIP. ») si un NIP existe au moment de l'écriture (vérifié dans la transaction). Mêmes
règles de rôle qu'avant (seul le super-admin touche un admin). Limite : 3 envois par heure et par employé
(les refus ne comptent pas). Sans `employeeId`, ou combiné à `reinitialiserNip`, le serveur répond
`invalid-argument`. Retour : `{id, courrielEnvoye: true}` ou `{id, courrielEnvoye: false, lienInvitation}`.
L'application mobile : sur la fiche d'un employé sans NIP, le bouton « Renvoyer l'invitation » remplace
« Réinitialiser le NIP ».

## 5. CORS du bucket

`cors.json` n'autorise plus que `https://client.chantierplus.app`, `http://localhost:5173` et
`http://localhost:5500` (l'application mobile native n'est pas concernée par le CORS). À appliquer par
Philip : vérifier d'abord ce qui est en place, puis

```bash
gsutil cors get gs://chantierplus-mtl
gsutil cors set cors.json gs://chantierplus-mtl
```

À tester ensuite avec un vrai dépôt de document depuis l'espace web : si le navigateur réclame d'autres
en-têtes de réponse, il faut les ajouter à `responseHeader`.

## 6. Appareil de confiance (30 jours)

Pour ne pas redemander le code par courriel à chaque connexion : **le code reste obligatoire à la
première connexion sur un appareil**, puis au plus une fois par 30 jours **si l'utilisateur coche la case**
(décochée par défaut). **Le NIP est TOUJOURS exigé** : le jeton remplace seulement le code. Volé seul, il
n'ouvre rien. L'application mobile et les connexions sans la case ne changent pas.

- `validerConnexionWeb({code, faireConfiance: true})` : après un bon code, un jeton aléatoire de 32 octets
  (base64url) est retourné **une seule fois** dans `appareil: {jeton, expireDans: 2592000}`. Seul son
  hachage (HMAC avec `PIN_PEPPER`) est conservé, avec `employeeId`, `companyId`, `creeLe` et `expireLe`
  (+30 jours) dans `appareils_web/{hachage}` : serveur seul, TTL Firestore. **Aucune adresse IP, aucun
  agent utilisateur.** Au plus 5 appareils par employé (le plus ancien part au 6e). Un courriel prévient
  l'utilisateur.
- `connexionWeb({..., jetonAppareil})` : **après** la vérification du NIP (aucun renseignement sans le bon
  NIP), un jeton valable pour CET employé et CETTE compagnie ouvre la session sans code :
  `{etape: "connecte", ...profil}`. Sinon (absent, faux, mal formé, expiré, d'un autre employé) : le flux
  habituel avec code, sans dire pourquoi, avec `jetonRefuse: true` dans la réponse si un jeton avait été
  envoyé (le client efface le sien). Ce chemin ne consomme pas la limite de 5 codes par heure. Un employé
  (rôle « employé »), un ancien employé, une compagnie bloquée : refusés comme toujours.
- Révocation automatique des appareils : retrait ou suppression d'un employé, changement ou
  réinitialisation du NIP (y compris « NIP oublié »), passage au rôle « employé », suppression de la
  compagnie. En plus, le jeton est revérifié à chaque usage.
- `revoquerAppareilWeb({jeton})` (« Ne plus faire confiance à cet appareil ») : sans session ; répond
  toujours `{ok: true}` ; 20 demandes par heure et par adresse IP.

## Déploiement (ordre)

1. `firebase deploy --only firestore:rules,firestore:indexes,storage` (règles d'expiration, collection
   `connexions_web`, politique TTL sur `connexions_web.expireLe`). Sans danger : les sessions existantes
   n'ont pas d'`expireLe`.
2. `firebase deploy --only functions` (**toutes** les fonctions : `contexteEmploye` et
   `supprimerSessionsDe` sont partagés ; les secrets `PIN_PEPPER` et `RESEND_API_KEY` existent déjà).
3. CORS (ci-dessus).
4. Prévenir la session du site web, qui bascule l'appel de `connexionEmploye` vers `connexionWeb`.

La suppression d'une compagnie (`supprimerCompagnie`) fait partie du même déploiement : elle efface
maintenant aussi `connexions_web` et les compteurs `connweb_`, `renvoi_`, `corrfeuille_`, `recalcul_`.

## Tests

`tests/rules/functions.test.mjs` : « Connexion web », « Sessions de l'espace web », « correction par un
admin », « Renvoi de l'invitation » ; `firestore.test.mjs` et `storage.test.mjs` : expiration ;
`test/employe_formulaire_test.dart` : bouton de l'application.

Essais de mutation (on casse volontairement une règle pour vérifier qu'un test échoue) : pour les règles
Firestore des photos et des extras, toutes les mutations sont détectées. Pour le code serveur de la
connexion web, les 4 premiers essais (refus des employés, limite de 5 essais, comparaison du code,
expiration du code) sont détectés ; le reste (consommation du code, session sans `expireLe`,
correction de feuille, renvoi d'invitation) reste à refaire.
