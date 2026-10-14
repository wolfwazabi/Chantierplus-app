# Calcul des limons d'escalier

Onglet **Calcul → Escalier** d'un chantier. Escalier droit (une volée) à marches de
bois sur limons entaillés. Code : `lib/charpente/escalier.dart` (moteur, en pouces),
`escalier_texte.dart` (liste de matériaux et texte copiable),
`lib/screens/charpente/ecran_escalier.dart` et `schema_limon.dart` (écran et schéma).

## Ce que le calcul donne

- nombre et hauteur des contremarches, giron, profondeur des marches, course, pente ;
- limons : nombre (selon la largeur et l'entraxe), planche à commander (pieds pairs),
  longueur de coupe, gorge, coupes du pied et de la tête, angles ;
- **table de traçage** : chaque hauteur et chaque position est arrondie seule (1/16 po
  ou 1 mm), sans addition de valeurs arrondies, donc sans cumul d'erreur ;
- vérification des dimensions du Code, autres nombres de contremarches conformes,
  liste de matériaux, texte copiable.

## À partir de 2 données (ou plus)

Interrupteur « Partir de ce que je connais » en haut de l'écran. On coche ce qu'on sait
parmi cinq données : **hauteur, course, giron, contremarche, nombre de contremarches** ; le
calcul trouve le reste (`escalier_solveur.dart`, `resoudreEscalier`) et dit pour chaque
valeur si elle est « donnée » ou « trouvée », avec des notes sur les ajustements.

| Données | Ce qui est trouvé |
|---|---|
| hauteur + course | le nombre de contremarches qui respecte le Code (les deux limites) ; si plusieurs, le plus confortable |
| hauteur + giron | contremarche, course = (n − 1) × giron ; n le plus confortable |
| hauteur + contremarche | n = hauteur ÷ contremarche (arrondi) ; contremarche ajustée ; giron idéal |
| hauteur + nombre | contremarche = hauteur ÷ n ; giron idéal |
| hauteur seule | l'escalier idéal (contremarche la plus proche de 7 1/4 po) |
| course + giron | n marches = course ÷ giron (arrondi) ; giron ajusté ; contremarche idéale ; hauteur trouvée |
| course + contremarche, course + nombre, nombre + giron, nombre + contremarche, nombre seul | idem, avec le giron ou la contremarche idéal |
| contremarche + giron seulement | refusé : il manque la hauteur, la course ou le nombre |

La hauteur, la course et le nombre donnés sont **exacts** ; la contremarche et le giron
donnés sont des cibles qui s'ajustent (la note le dit). Si aucun nombre ne respecte le Code
avec les données, le moins éloigné est choisi et la vérification du Code le signale.

**Idéal.** Giron + 2 × contremarche = 635 mm (25 po), au milieu de la plage de confort de 600 à
650 mm ; contremarche visée 7 1/4 po (184 mm) quand rien ne la fixe. Les valeurs trouvées sont
arrondies au 1/16 po et ne sortent **jamais** des bornes du Code (un minimum est arrondi vers
le haut, un maximum vers le bas). Les autres nombres de contremarches conformes sont offerts
en « Autres choix » (un toucher impose ce nombre).

## Schémas des coupes et de la pente

Sous le tableau des coupes (`schema_coupes.dart`), trois schémas avec les mesures écrites :
le **gabarit** (triangle de l'équerre : contremarche, giron, diagonale, pente et son
complément), le **pied** du limon (coupe d'aplomb = contremarche − épaisseur de la marche ;
coupe de niveau sur le plancher ; pente) et la **tête** (coupe d'aplomb contre la poutre,
pointe du haut). Les mesures viennent de `etiquettesCoupes` (testée).

## Conventions

- `n` contremarches, `n − 1` marches (le plancher du haut est la dernière marche).
- `R = H ÷ n` ; `G` = giron voulu, ou `G = course ÷ (n − 1)` si la course est imposée.
- Repère : x vers le haut de l'escalier, y vers le haut ; origine au pied de la coupe
  d'aplomb du bas, sur le plancher fini du bas.
- La marche `k` a son dessus à `k·R` ; son siège dans le limon est à `k·R − t`
  (`t` = épaisseur de la marche), de `x = (k − 1)·G` à `k·G`.
- Les pointes des dents sont toutes sur le dessus de la planche ; le dessous lui est
  parallèle, à la profondeur de la planche (2×10 : 9 1/4 po, 2×12 : 11 1/4 po).
- **Gorge** = profondeur de la planche − `R·G ÷ √(R² + G²)` (mesurée à 90°).
- **Longueur de planche** = étendue réelle du contour du limon le long de la pente
  (pied et tête compris), pas `√(H² + course²)`.
- Nombre de limons : un à chaque bord, les autres à l'entraxe maximal ou moins.
- Choix automatique de `n` : la contremarche la plus proche de la valeur visée parmi
  celles que le Code permet (et, si la course est imposée, dont le giron est permis).

## Exigences vérifiées (CNB 2015, section 9.8, tel qu'adopté au Québec)

| Exigence | Escalier privé (logement) | Escalier commun |
|---|---|---|
| Contremarche | 125 à 200 mm | 125 à 180 mm |
| Giron | 255 à 355 mm | 280 mm minimum |
| Profondeur de la marche | de son giron à son giron + 25 mm | idem |
| Largeur (des limons, hors tout) | 860 mm minimum | 900 mm minimum |
| Échappée (rappel seulement) | 1 950 mm | 2 050 mm |
| Hauteur d'une volée | 3,7 m au plus (art. 9.8.3.3) | idem |
| Uniformité (traçage arrondi) | 5 mm entre voisines, 10 mm sur la volée | idem |

Hors Code : confort (giron + 2 × contremarche entre 600 et 650 mm, avertissement) et
gorge minimale de 3 1/2 po (règle de métier, erreur si moins).

Tolérance de conversion : 0,05 mm (7 7/8 po = 200,025 mm compte pour la limite de 200 mm).
Par défaut, le giron est 10 1/4 po : 10 po (254 mm) est 1 mm sous le minimum.

## Marches en composite

Option « Marches en composite » (groupe Marches et contremarches) et choix du produit
(`lib/charpente/composite.dart`, calcul dans `escalier_composite.dart`) :

- **Marches en cadre** : un nez sur toute la largeur, 2 côtés en onglet (profondeur de la
  marche) et des planches au centre ; planches à bord carré dans les longueurs vendues du
  produit. Écarts du fabricant : entre planches côte à côte, et au bout des planches du centre
  contre les côtés (valeur par temps doux ; le tableau selon la température est affiché).
- **Contremarches** en fascia (la plus basse hauteur vendue qui couvre la contremarche,
  refendue), avec un **2x traité de backing** derrière chacune (2x8, 2x10 ou 2x12 selon la
  hauteur). Pas de contreplaqué sous les marches.
- **Fixation selon le guide** : la plupart des fabricants interdisent leurs attaches cachées
  sur les marches (TimberTech, Fiberon, MoistureShield) : tout est vissé en surface, 2 vis par
  limon dans chaque planche en travers et 2 par côté, avec bouchons (ou vis de la couleur,
  ex. TOPLoc). Trex permet ses attaches Hideaway au centre (planches à bord carré rainurées à
  la toupie) : une par limon intérieur à chaque joint. Fascias : 2 vis par limon.
- **Limons** à l'entraxe du fabricant (ex. Trex Enhance 9 po, Select 200 mm et Transcend
  230 mm au Canada, TimberTech 10 po, Fiberon 12 po, MoistureShield 8 à 9 po) ; le
  « composite courant » prend 9 po (prudent).
- **Épaisseur de marche** du traçage des limons = épaisseur de la planche ; avertissement si
  le nez dépasse le maximum du fabricant (Trex 3/4 po, TimberTech 1 po, PVC 1/2 po…).

Sources : guides et fiches des fabricants consultés le 13 octobre 2026 (cités dans chaque
fiche). À revérifier avec le guide du produit posé : les gammes changent (MoistureShield a été
racheté par Deckorators en 2026), certaines valeurs n'ont pas pu être vérifiées (longueurs du
bord carré TimberTech, largeur réelle de la fascia AZEK, système de bouchons MoistureShield,
format des boîtes de bouchons — la liste donne le nombre de vis et de bouchons).

## Limites et prudence

- **Sources.** Les valeurs ont été recoupées dans des sources secondaires
  (publications du CNRC et de la Colombie-Britannique, qccodes.ca, plans-architecture.ca,
  texte de l'*Ontario Building Code* pour la profondeur des marches). Les PDF
  officiels n'étaient pas lisibles : **confirmez dans le texte officiel du Code de
  construction du Québec**, chapitre Bâtiment (RBQ), ou auprès de la Garantie de
  construction résidentielle. Les constantes sont dans `LimitesEscalier`.
- Dimensions seulement : portées, fixation, garde-corps, mains courantes, escaliers
  tournants, balancés et paliers ne sont pas calculés. Au-delà de 3,7 m, calculer
  chaque volée séparément.
- Les hauteurs sont mesurées du plancher **fini** du bas au plancher **fini** du haut.
- La pointe du haut du limon est à `H − t` : elle affleure l'ossature du plancher du
  haut si sous-plancher et finition ont l'épaisseur d'une marche.
- Le calcul n'est pas enregistré avec les commandes du chantier : « Copier le calcul ».

## Tests

`flutter test test/charpente/escalier_test.dart test/charpente/ecran_escalier_test.dart`

- cas calculés à la main (triangle 3-4-5 : 7 1/2 po × 10 po, tout est exact) ;
- 300 escaliers au hasard, vérifiés avec une géométrie refaite dans le test (distance
  point-droite, aire du contour par la formule du lacet, contour tourné à plat) ;
- limites du Code au millimètre (200 / 200,5 mm, 255 / 254 mm, 25 / 26 mm…) ;
- les tests détectent des erreurs volontaires de formule (essais de mutation).
