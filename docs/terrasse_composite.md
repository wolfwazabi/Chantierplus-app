# Plateforme : dessus du plancher en composite

Onglet Plancher, groupe « Dessus du plancher » : **Feuilles** (sous-plancher, un agrandissement)
ou **Composite** (une plateforme, une terrasse) avec le produit choisi
(`lib/charpente/composite.dart`). Calcul : `lib/charpente/terrasse.dart` ; projet :
`ParametresPlancher.composite` (clé JSON `composite`, présente seulement s'il y a du composite).

## Comment c'est posé (choix de Philip, 13 octobre 2026)

- **Cadre** (« picture frame ») de planches à **rive carrée** sur **les 4 côtés**, en onglet
  aux coins, aussi contre la maison (à 1/4 po du mur ; Philip, 16 octobre 2026). Ailleurs, il
  dépasse la fascia de 1/2 po (moins si le fabricant le limite : Trex et TimberTech 3/4, Fiberon Good Life et
  ArmorGuard 1/2, MoistureShield Elevate 1/4).
- **Centre** : planches **rainurées perpendiculaires aux solives**, une attache cachée du
  fabricant **par solive par planche** ; écart côte à côte du produit (3/16 po), écart au bout
  contre le cadre (temps doux). **Première et dernière planche** : des planches entières, et le
  reste réparti entre la première et la dernière rangée, refendues à la même largeur
  ((planche + reste) / 2, donc au moins une demi-planche) : jamais de lisière de 1 po difficile
  à visser (demande de Philip, 16 octobre 2026). Un reste de 1/8 po ou moins est pris par les
  écarts aux bords ; une planche à refendre de moins de 1/2 po est seule (la dernière). La
  première et la dernière rangée sont vissées en surface (2 vis par solive) le long du cadre.
  Rangée plus longue que la plus longue planche : morceaux égaux et joints bout à bout, signalés
  (solive doublée ou bloc selon le guide).
- **Fascia** du même produit sur les rives, sauf contre la maison ; hauteur : la plus basse
  vendue qui couvre la rive ; vis selon le fabricant (Trex 3 aux 18 po, TimberTech 2 aux 12 po,
  Fiberon 3 aux 12 po, MoistureShield 3 aux 16 po, AZEK 3 aux 12 po).
- **Blocage en échelle** (bois des solives) aux 16 po sous le cadre qui **longe les solives** :
  il porte le cadre et le bout des planches du centre.
- **Vis en surface** du cadre : 2 par appui (solive ou bloc), avec bouchons si le produit en a.
  Fiberon : 2 vis de plus au milieu de chaque planche du centre (« épingler »).
- **Avertissement** si l'entraxe des solives dépasse celui du fabricant (au Canada : Trex
  Enhance 12 po — « 300 mm » au CCMC 13125-R ; les autres 16 po).

La commande remplace le sous-plancher par : planches à rive carrée, planches rainurées, fascias
(catégorie « Composite »), boîtes d'attaches, vis et bouchons, vis de fascia, blocage
(« Plancher (blocage du cadre) »). La 3D dessine le cadre, les planches et la fascia à la place
des feuilles (z = 0 : dessus des planches).

## Sources (consultées le 13 octobre 2026)

- **Trex** : *2026 Trex Decking Installation Guide* (online.flippingbook.com/view/63974767/) et
  CCMC 13125-R (modifié 2026-05-28) : Enhance 300 mm au Canada, Select et Transcend 400 mm ;
  côté 5 mm (3/16) ; bout à bout 6 mm entre 3 et 15 °C ; Hideaway 1 par solive par planche
  (90 = 50 pi²) ; cadre : 2 vis aux 16 po, appuis ajoutés sous la bordure ; fascia 0,56 × 7,25 ou
  11,375 po × 12 pi, 3 vis aux 18 po.
- **TimberTech** : guide Composite REV 09/23 et Advanced PVC REV 07/26 (assets.timbertech.com) ;
  16 po max ; CONCEALoc 1 par solive (175 = 100 pi²) ; joints sur solive doublée ; cadre : blocage
  aux 16 po ; fascia composite 0,575 × 11,95 po, PVC 0,5 × 11,75 po.
- **Fiberon** : instructions PE FIB-0354-LIT 09/26 (et version canadienne-française 11/22) ;
  16 po ; Phantom Universal 1 par solive + 2 vis en surface au milieu ; fascia 0,75 × 11,25 po,
  3 vis aux 12 po ; ventilation ≥ 1 1/2 po.
- **MoistureShield** : guide mars 2021 (révisé 2024), fiches 04-26, CCMC 13191-R (Vision) ; 16 po
  (400 mm) ; Aegis ou Deck Clip 1 de chaque côté par solive (90 = 50 pi²) ; fascia 0,67 × 11,25
  po, 3 vis aux 12 à 16 po ; Elevate : débord 1/4 po, pas de bouchons, pas de CCMC.

À revérifier avec le guide du produit posé : les gammes et les guides changent. Non publiés par
les fabricants (donc pas calculés) : appui minimal aux joints, dégagement au-dessus du sol d'une
terrasse surélevée.

## Escalier jumelé au plancher

Onglet **Escalier** de la charpente (entre Murs et 3D) : « Inclure un escalier ». Le calcul est
celui de l'écran Escalier (`EcranEscalier(projet: true)`), avec :

- la **hauteur de la plateforme** (du sol fini au dessus fini) comme hauteur totale ;
- des marches **en composite du même produit** que le dessus du plancher (en bois si le plancher
  est en feuilles) ; la plus haute contremarche est la **fascia du plancher** (elle n'est pas
  comptée avec l'escalier) ;
- sa **place** : le côté du plancher (pas celui de la maison), **centré** ou **à une distance du
  coin de gauche** vu de l'extérieur ; un escalier trop large pour le côté est refusé avec un
  message.

Choix enregistrés dans le projet (`ParametresEscalier`, `lib/charpente/escalier_projet.dart` ;
clés `escalierActif` et `escalier`, absentes des projets sans escalier). La 3D place l'escalier
contre la face de la fascia (ou de la rive) du côté choisi, son haut au dessus du plancher
(`placerEscalier`). La commande ajoute les limons (« Escalier (limons) »), les marches, les
fascias, les 2x12 à plat et la quincaillerie ; les mêmes articles que le plancher s'additionnent.
L'assistant IA ne connaît pas encore le composite ni l'escalier : ils sont gardés tels quels
quand il modifie le calcul.
