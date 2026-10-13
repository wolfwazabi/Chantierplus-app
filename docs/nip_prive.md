# NIP haché : espace privé (`employees_prive`)

Avant : le NIP haché (`pinHash`) était dans le document `employees`, que **tout admin de la compagnie
(et son navigateur)** reçoit en lisant la liste des employés. Le hachage est un HMAC avec le secret
`PIN_PEPPER`, donc inutilisable sans ce secret, mais l'exposition était inutile (demandé par la session
du site web, décidé par Philip : « oui »).

Maintenant :

- `employees_prive/{employeeId}` = `{pinHash, pinModifieLe, companyId}` : **serveur seul** (règle
  `allow read, write: if false`). Les clients, admins compris, n'y lisent ni n'y écrivent rien.
- `employees.nipCree` (booléen, maintenu par le serveur) dit seulement qu'un NIP existe : « NIP créé » ou
  « à créer ». Il est faux à la création d'un employé et après une réinitialisation ou un retrait.
- Le serveur écrit le NIP uniquement dans le nouvel emplacement : inscription d'une compagnie, création
  par lien, changement par l'employé, « NIP oublié » mené à terme. Retrait, réinitialisation,
  réactivation et suppression de la fiche détruisent le NIP aux deux endroits. La suppression de
  compagnie efface aussi `employees_prive`.

## Transition (rien n'est coupé)

Tant qu'une fiche n'est pas migrée, ses NIP sont lus à l'**ancien** emplacement : toutes les fonctions
lisent « le nouvel emplacement d'abord, puis l'ancien champ ». La fonction planifiée `migrerNipsPrives`
(chaque nuit à 4 h, Montréal) déplace les fiches une à une : dans une transaction, elle **copie** le NIP
vers `employees_prive` **puis** retire `pinHash`/`pinModifieLe` de `employees` et pose `nipCree: true`.
Elle est idempotente, n'écrase jamais un NIP déjà présent dans le nouvel emplacement et ne journalise
qu'un **nombre**. Quand tout est migré (relancer donne 0), cette fonction pourra être retirée.

L'application (et le site web) lisent `nipCree === true` **ou** un `pinHash` non vide : avant, pendant et
après la migration. Une version de l'application construite AVANT ce changement affiche « Invitation en
attente » pour tous les employés une fois la migration faite (affichage seulement : les connexions ne
changent pas) ; le prochain build règle cela.

## Tests

`tests/rules/functions.test.mjs` (« NIP haché : espace privé ») : connexion sur les deux emplacements,
priorité au nouvel emplacement, création/changement/« NIP oublié », réinitialisation, retrait,
réactivation, suppression, renvoi d'invitation, migration (pages, idempotence, jamais d'écrasement,
personne déconnecté) ; `nip_prive.unit.test.mjs` ; `test/nip_employe_test.dart`.
