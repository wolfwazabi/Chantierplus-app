# Calcul de charpente (Chantier → Calcul → Charpente)

Calcul exact du bois d'un plancher et de murs, vue 3D par couches et liste
d'achat enregistrable. Tout le calcul est fait dans l'application (Dart pur,
`lib/charpente/`), testé sans réseau ; l'assistant IA ne fait que convertir une
description en paramètres.

## Ce que fait le calcul

- **Plancher** : forme rectangulaire, à côtés et angles (n'importe quels angles,
  n'importe quel nombre de côtés) ou à coordonnées ; solives à 12, 16, 19,2 ou
  24 po c/c (ou autre entraxe), direction automatique (plus courte portée) ou
  imposée, solives de rive (doubles au choix), solives de bordure (doublées au
  choix), étriers (aucun / un bout / deux bouts), entremises (0 à 3 rangées),
  sous-plancher en 4×8, 4×9, 4×10 ou 4×12 avec joints décalés, chaque joint sur
  le centre d'une solive, avec la pièce à couper de chaque feuille.
  **Plancher sur pieux vissés** (réglages de l'entrepreneur, voir
  `exemples_reels_plancher.md`) : côté de la maison (sa rive reste simple, les
  autres sont doublées ; si elle est faite de plusieurs morceaux, elle est doublée
  et les joints sont alternés), étriers seulement sur les solives intérieures,
  clous d'étriers (case à cocher pour les compter ou non ; nombre par étrier au choix : 6, 8, 10, 12, 14, 16 ou autre ; par boîte, avec marge), entremises automatiques
  (une rangée chaque fois que la portée dépasse 7 à 10 pi) en pose alternée, coupes
  séparées (solives, rives et entremises chacune dans leurs planches), poutres de
  plusieurs plis en bois traité sur toute la largeur, pieux (nombre, premier à
  1 pi du bord, entraxe calculé) et pattes en 6×6 traité qui rehaussent les pieux.
- **Murs** : un mur par côté du contour du plancher ou murs libres ; montants,
  coins, lisses (1 ou 2 hautes), rois, jacks, linteaux, appuis, courts montants,
  feuilles (OSB, 4×9, **OSB isolant R-4 Isobrace**), membrane, fourrures,
  revêtement ; portes et fenêtres avec les jeux de la fiche GCR FT-9.7.6.1
  (baie = dormant + 1/2 à 1 1/2 po en largeur et 1 à 1 3/4 po en hauteur).
  **Pose du linteau**, par ouverture (vitrage qui monte près de la sablière ; CNB
  partie 9, art. 9.23.11.3 et 9.23.12) :
  - *sous les lisses* (courant) ;
  - *sous une lisse simple* : la lisse du dessous est coupée sur la longueur du
    linteau, celle du dessus passe sans joint et le relie au mur (+1 1/2 po) ;
  - *à la place des lisses* : les lisses hautes sont coupées, le linteau monte
    jusqu'au dessus du mur et se relie aux murs voisins par une plaque d'acier
    galvanisé 3 × 6 po (0,91 mm) ou une éclisse 1 × 4 de 12 po, 3 clous de 2 1/2 po
    de chaque côté (+3 po avec 2 lisses) ; 2 plaques par linteau dans la commande ;
  - *sans linteau* : la charge est reprise par une poutre ou des poteaux conçus
    par un ingénieur (Loi sur les ingénieurs ; non calculés), une traverse à plat
    ferme le haut de la baie.
  Quand une ouverture ne passe pas, le message donne le calcul et la pose qui la
  ferait passer. Une pose remontée inutile ne coupe rien (lisses entières).
  Source : CNB 2015 (texte reproduit), intentions du CNRC ; le libellé du CNB 2020
  modifié Québec (en vigueur depuis le 17 avril 2025, CNB 2015 permis pendant la
  transition) n'a pas été relu mot à mot : à confirmer.
- **Vue 3D** : couches du plancher (solives → + sous-plancher) et des murs
  (ossature → + feuilles → + membrane → + fourrures → + revêtement) ; toucher une
  pièce affiche sa mesure en bref dans une petite pastille à côté d'elle, et sa fiche
  complète (feuille de départ, longueur à la pointe longue des coupes d'angle,
  découpes d'ouverture…) sous la vue : on descend pour la lire, le dessin ne
  rapetisse jamais ; cotes ; dessus / face.
- **Commande** : liste d'achat regroupée (même section = une ligne), lignes
  ajoutées à la main, copie, courriel, et enregistrement par chantier
  (`chantier_commandes` : brouillon → commandée → reçue, calcul rouvrable).
- **Assistant IA** : une description en français devient un projet validé.
- **Calcul à partir d'un plan** (PDF ou photos) : voir `lecture_plans.md`.
- **Écran allégé** : la forme et les solives (section, entraxe en menu : 12, 16,
  19,2, 24 po ou « Autre… ») restent visibles ; les réglages sont repliés en groupes
  (Direction et rives, Étriers et clous, Entremises, Poutres et pieux, Sous-plancher,
  Bois ; pour les murs : Lisses et montants, Linteaux, Feuilles, Fourrures) avec le
  résumé de leurs valeurs ; un groupe ouvert le reste quand on change d'onglet.
  L'exemple de saisie d'une mesure (10'6", 10-6…) n'apparaît que dans le champ en
  cours. Escalier : détails des marches et limons repliés de même.
- **Réglages habituels** (`reglages_habituels.dart`) : « Garder » fait des réglages
  de l'onglet (plancher ou murs : rives, étriers, entremises, poutres, sous-plancher,
  bois, ossature…) le point de départ des prochains calculs ; jamais les mesures
  (forme, côté de la maison, hauteur des murs, portes et fenêtres). Un nouveau calcul
  et un chantier sans calcul en partent ; « Remettre » les rétablit (avec
  « Annuler »). Gardés sur l'appareil. La lecture d'un plan les envoie au serveur,
  qui les applique seulement là où le plan ne dit rien.

## Conventions de calcul

- Unités internes : pouces. Les mesures se saisissent en 10'6", 10-6, 126" ou en
  mètres selon le choix dans Préférences ; un nombre seul = pieds (impérial) ou
  mètres (métrique).
- Longueurs de bois : à la **pointe longue** des coupes d'angle ; planches de 8 à
  20 pi ; chaque coupe est placée dans la planche la plus courte possible
  (trait de scie de 1/8 po), les chutes servent aux petites pièces. À longueur de bois égale, des planches
  à la mesure des pièces remplacent une longue planche à recouper (dix solives de 10 pi : dix 10 pi). Les montants
  et les jacks ont chacun leur planche (on achète des 8 pi).
- Solives : leurs bouts sont sur la face intérieure des rives (contour décalé de
  l'épaisseur de la rive) ; près d'un sommet aigu la solive se termine en pointe.
- Feuilles de plancher : bandes en travers des solives, la dernière refendue (au
  moins 12 po), joints décalés d'au moins 24 po entre rangées voisines.
- Feuilles de mur : verticales, joints sur le centre d'un montant (ou sur le
  linteau / l'appui dans une baie), dernière colonne d'au moins 12 po ; les baies
  sont découpées après la pose. Les couches extérieures vont de sommet à sommet
  du contour.
- Coins d'équerre : un mur passe, l'autre s'y appuie (raccourci de la profondeur
  de l'autre, coin à 3 montants) ; coin rentrant : le mur qui passe est prolongé ;
  autres angles : onglets, montants de bout reculés contre la coupe.

## Limites (à lire avant de commander)

- **Dimensionnement structural non vérifié** : portée admissible des solives,
  linteaux, poutres, ancrages, clouage. L'application avertit à chaque calcul ; le
  choix des sections reste à valider avec le Code de construction du Québec
  (tables de la partie 9) ou un ingénieur. Les tables officielles n'étaient pas
  disponibles pour les vérifier ici.
- Les formes irrégulières comptent les feuilles avec leur rectangle englobant
  (estimation prudente) ; les chutes en biais ne sont pas réutilisées.
- Pas de toit, d'escalier, de poutres ni de poteaux ; les cloisons en T ajoutent
  seulement leurs montants d'appui (la cloison elle-même se calcule comme mur libre).
- La quincaillerie (clous, colle…) s'ajoute à la main dans la commande.

## Assistant IA : activation

La clé d'API se met dans Secret Manager, jamais dans l'application ni dans le dépôt :

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase deploy --only functions:assistantCharpente
```

- Fonction `assistantCharpente` (Montréal) : admin et contremaître seulement,
  App Check comme les autres fonctions, 20 demandes par heure et par employé, 200
  par jour et par compagnie. Modèle : paramètre `MODELE_ASSISTANT` (Claude Haiku
  4.5 par défaut). Sans clé, l'application répond « L'assistant IA n'est pas
  encore activé ».
- Le modèle est forcé d'appeler un outil dont le résultat est **filtré** côté
  serveur (liste blanche de champs, bornes, valeurs permises) puis relu et
  recalculé par l'application ; l'utilisateur confirme avant d'appliquer.
- Aucun contenu n'est conservé : seuls la compagnie et la longueur du texte sont
  journalisés.

## Déploiement

1. Règles Firestore (nouvelle collection `chantier_commandes`) :
   `firebase deploy --only firestore:rules`.
2. Fonction de l'assistant (après avoir posé la clé, voir ci-dessus).
3. Nouvelle version de l'application (Codemagic pour l'iPhone) : l'onglet Calcul
   contient maintenant « Feuilles » et « Charpente ».

## Tests

```bash
flutter test test/charpente        # moteur (plancher, murs, 3D, commande, projet) et écrans
cd tests/rules && npm test         # règles Firestore/Storage, fonctions (dont l'assistant)
```

Les fichiers `test/charpente/projet_defaut.json` et `projet_assistant.json` sont
lus par les tests Dart **et** par les tests de l'assistant : ils garantissent que
le serveur et l'application parlent le même format de projet.
