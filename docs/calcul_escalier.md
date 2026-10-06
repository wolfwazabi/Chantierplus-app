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
| Largeur libre | 860 mm minimum | 900 mm minimum |
| Échappée (rappel seulement) | 1 950 mm | 2 050 mm |
| Hauteur d'une volée | 3,7 m au plus (art. 9.8.3.3) | idem |
| Uniformité (traçage arrondi) | 5 mm entre voisines, 10 mm sur la volée | idem |

Hors Code : confort (giron + 2 × contremarche entre 600 et 650 mm, avertissement) et
gorge minimale de 3 1/2 po (règle de métier, erreur si moins).

Tolérance de conversion : 0,05 mm (7 7/8 po = 200,025 mm compte pour la limite de 200 mm).
Par défaut, le giron est 10 1/4 po : 10 po (254 mm) est 1 mm sous le minimum.

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
