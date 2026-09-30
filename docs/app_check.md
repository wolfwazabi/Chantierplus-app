# App Check : mise en service

État : le code de l'app est prêt (`_activerAppCheck` dans `lib/main.dart`), les Cloud
Functions vérifient le jeton (`verifierAppCheck`), mais l'application est en mode
**surveillance** (`APP_CHECK_OBLIGATOIRE=false` dans `functions/.env.boreal-8cd7c`) :
les appels sans jeton sont acceptés et journalisés (« Appel sans jeton App Check »).

Ne PAS imposer avant que tous les appareils utilisés envoient un jeton. Windows,
macOS et Linux n'ont aucun fournisseur d'attestation : ils cesseraient de marcher.

## 1. Enregistrer les applications (console Firebase → App Check → Applications)

- **Android** : fournisseur *Play Integrity*.
  - Lier le projet à Google Play (console Play → Intégrité de l'application).
  - Ajouter les empreintes SHA-256 de la clé de signature Play et de la clé d'upload.
    Empreinte de la clé d'upload :
    `keytool -list -v -keystore android\app\upload-keystore.jks -alias upload`
  - Play Integrity ne reconnaît que les applications installées depuis Google Play
    (piste de test interne suffisante). Un APK installé à la main est refusé.
- **iOS** : fournisseur *App Attest* (compte Apple Developer requis).
- **Web** : fournisseur *reCAPTCHA Enterprise* ; compiler avec
  `--dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=<clé>`.
- **Développement** (téléphone en mode debug) : au premier lancement, le jeton de
  débogage s'affiche dans les journaux (`adb logcat | findstr DebugAppCheckProvider`).
  L'enregistrer dans App Check → Applications → Gérer les jetons de débogage.

## 2. Vérifier que les jetons arrivent

```
firebase functions:log --project boreal-8cd7c -n 200
```

Chaque appel encore journalisé « Appel sans jeton App Check » vient d'un appareil non
attesté. Attendre qu'il n'y en ait plus pour les appareils réels.

## 3. Imposer

- Cloud Functions : mettre `APP_CHECK_OBLIGATOIRE=true` dans `functions/.env.boreal-8cd7c`,
  puis `firebase deploy --only functions --project boreal-8cd7c`.
- Firestore et Storage : console → App Check → Produits → **Appliquer**
  (surveiller d'abord les métriques de requêtes vérifiées).
- La page de création du NIP (`/inscription`, navigateur) n'utilise pas App Check :
  elle est protégée par le jeton à usage unique et les limites par IP.

Retour arrière : remettre `APP_CHECK_OBLIGATOIRE=false` et redéployer ; désactiver
« Appliquer » dans la console.
