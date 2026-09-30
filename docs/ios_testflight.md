# iPhone : distribuer Chantier+ aux testeurs (TestFlight)

Tu es sur Windows : un build iOS exige un Mac. On utilise **Codemagic** (Mac dans le
nuage) pour compiler et envoyer l'app à **TestFlight**, l'outil d'Apple pour les
essais avant publication. Les testeurs installent l'app TestFlight, puis Chantier+.

Identifiant de l'app (déjà configuré partout) : `app.chantierplus`.

## 1. Programme Apple Developer (99 $ US / an)

1. https://developer.apple.com/programs/enroll/ , connecté avec ton identifiant Apple.
2. Choisis « Individu » (rapide) ou « Organisation » (exige un numéro D-U-N-S).
   Le nom du vendeur dans l'App Store sera ton nom ou celui de l'organisation.
3. Approbation : de quelques heures à quelques jours.

## 2. Créer l'app dans App Store Connect

1. https://appstoreconnect.apple.com → Apps → « + » → Nouvelle app.
2. Plateforme iOS, nom **Chantier+**, langue principale Français (Canada),
   identifiant de bundle `app.chantierplus`, SKU libre (ex. `chantierplus`).
   Si `app.chantierplus` n'apparaît pas, l'enregistrer d'abord dans
   developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.
3. Note l'**ID Apple** (numérique) de l'app : Informations sur l'app.

## 3. Clé API App Store Connect (pour que Codemagic se connecte)

App Store Connect → Utilisateurs et accès → Intégrations → Clés d'API → « + »,
rôle **App Manager**. Télécharge le fichier `.p8` (téléchargeable une seule fois) et
note l'ID de la clé et l'ID de l'émetteur. **Ne partage jamais ce fichier** (ni avec
Claude) : tu le donnes seulement à Codemagic.

## 4. Codemagic

1. Le dépôt doit être sur GitHub, GitLab ou Bitbucket (dépôt **privé**).
   Le projet n'a pas encore de dépôt distant. Aucun secret n'est suivi par git
   (`key.properties` et le fichier `.jks` sont ignorés).
2. https://codemagic.io → connecte le dépôt → utiliser `codemagic.yaml`.
3. Teams → Integrations → App Store Connect : ajoute la clé (nom **Chantier+**,
   ID de la clé, ID de l'émetteur, fichier `.p8`).
4. Dans `codemagic.yaml`, remplace `REMPLACER_PAR_L_ID_APPLE` par l'ID de l'étape 2.
5. Signature : Codemagic crée le certificat et le profil de distribution avec la clé
   API. Rien à faire à la main.
6. Lancer le workflow **Chantier+ iOS (TestFlight)**. La compilation prend une
   vingtaine de minutes, puis la version apparaît dans TestFlight.

Plan gratuit de Codemagic : quelques centaines de minutes de Mac par mois, largement
suffisant pour des essais.

## 5. Inviter les testeurs

- **Testeurs internes** (jusqu'à 100, membres de ton équipe App Store Connect) :
  aucune révision Apple, disponible tout de suite.
- **Testeurs externes** (jusqu'à 10 000, par courriel ou lien public) : la première
  version passe une courte révision Apple (« Beta App Review »), généralement moins
  d'une journée.
  App Store Connect → ton app → TestFlight → Groupes externes → ajouter les courriels.
- Chaque testeur installe **TestFlight** (App Store), ouvre l'invitation, puis installe
  Chantier+. Chaque version expire après 90 jours.

## 6. Avant la publication publique

- Politique de confidentialité en ligne (URL obligatoire dans App Store Connect).
- Icônes et captures d'écran (les icônes sont dans `ios/Runner/Assets.xcassets`).
- App Check : voir `docs/app_check.md` (App Attest exige de cocher la capacité « App
  Attest » de l'app et d'ajouter l'entitlement ; à faire avant d'imposer App Check).
- Comme l'app permet de créer un compte (compagnie ou particulier), Apple exige aussi
  une façon de **supprimer son compte** dans l'app (règle 5.1.1(v)). Non implémenté.
