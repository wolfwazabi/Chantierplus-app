# Notifications sur le téléphone des admins

Demandé le 16 octobre 2026 : être averti sur son téléphone quand quelque chose est entré, pour
les **admins seulement**, chaque catégorie **activable ou fermée** (Admin > Notifications).

## Ce qui part, et vers qui

| Catégorie | Quand | Exemple |
|---|---|---|
| Extras | un extra est entré | « Extra — Chalet Nord » : Porte ajoutée (Paul) |
| Travaux à compléter | un travail est entré | « Travail à compléter — Chalet Nord » |
| Matériel manquant | du matériel est entré (chantier ou Général) | « Matériel manquant — Général » : Vis × 2 boîtes |
| Heures | un employé envoie ou corrige ses heures (**à chaque envoi**) | « Heures — Émile » : Lundi — total de la semaine : 7,75 h |
| Photos | des photos sont ajoutées : **une** notification par auteur et par chantier toutes les 10 minutes | « Photos — Chalet Nord » |
| Documents | un document est déposé | « Document — Chalet Nord » : Plan.pdf |

- Aux **admins actifs** de la compagnie, **jamais à l'auteur** lui-même.
- Préférences : `preferences_notifications/{employeeId}` (oui/non par catégorie ; absent = oui),
  écrites par l'admin pour lui seul ; elles le suivent sur tous ses téléphones.
- Appareils : `appareils_notifications/{uid de la session}` (jeton FCM), écrit par le téléphone
  de l'admin à la connexion, effacé à la déconnexion. Le serveur n'envoie qu'aux appareils dont
  la session est encore ouverte ; un jeton refusé par Google est oublié.
- Serveur : `functions/src/notifications.js`, déclencheurs `notifierExtra`, `notifierTravail`,
  `notifierMateriel`, `notifierPhoto`, `notifierDocument` (création d'un document), et l'envoi
  des heures dans `enregistrerFeuilleTemps`. Une notification manquée ne fait jamais échouer
  l'enregistrement.
- App : `lib/services/notifications_push.dart` (permission, jeton, bandeau quand l'app est
  ouverte), écran `lib/screens/admin/notifications_admin_screen.dart`.
- Permission : le téléphone la demande tout seul (« Autoriser les notifications ? ») la
  première fois qu'un admin ouvre l'app connecté ou se connecte ; les employés ne reçoivent
  rien, on ne leur demande rien. Refusée, seule l'app Réglages peut la rouvrir : Admin >
  Notifications affiche alors « bloquées » avec « Ouvrir les réglages » (module
  `app_settings`, page des notifications de Chantier+ ; iOS 15.4 et plus), et activer une
  catégorie le propose aussi. Au retour dans l'app, l'écran relit la permission et
  enregistre le jeton du téléphone.

## À faire une fois (Philip) avant le build

**iPhone** (Apple exige une clé ; c'est toi qui la crées et la saisis) :

1. developer.apple.com > Certificates, Identifiers & Profiles > **Identifiers** >
   `app.chantierplus` > cocher **Push Notifications** > Save.
2. **Keys** > « + » > nom « Chantier+ notifications » > cocher **Apple Push Notifications
   service (APNs)** > Continue > Register > **télécharger le fichier .p8** (une seule fois
   possible) ; noter le **Key ID** et le **Team ID** (en haut à droite).
3. console.firebase.google.com > projet **boreal-8cd7c** > Paramètres du projet > **Cloud
   Messaging** > Configuration de l'application Apple > **Clé d'authentification APNs** >
   Importer : le fichier .p8, le Key ID et le Team ID.

**Android** : rien à faire (Firebase s'en occupe).

**Ensuite** : déploiement des fonctions et des règles Firestore (sur ton accord), puis le build
Codemagic (le profil iOS est recréé avec les notifications ; `ios/Runner/Runner.entitlements`).

## Tests

- `tests/rules/notifications.unit.test.mjs` : les messages.
- `tests/rules/functions.test.mjs` (« Notifications sur le téléphone des admins ») : extras aux
  deux admins, auteur exclu, catégorie fermée, photos regroupées, heures, appareil déconnecté
  (en émulateur, les envois sont écrits dans `envois_notifications_emulateur`).
- `tests/rules/firestore.test.mjs` : appareils et préférences (admins seulement, les siens).
- `test/notifications_admin_test.dart` : l'écran des catégories.
