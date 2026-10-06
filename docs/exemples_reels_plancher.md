# Commandes de plancher réelles : le calcul les reproduit

Deux planchers de véranda/solarium sur pieux vissés, commandés à la main par
l'entrepreneur (listes manuscrites) et dessinés sur plans de permis. Ils servent de
référence au calcul de plancher : les tests `test/charpente/plancher_reel_test.dart`
et `ecran_plancher_reel_test.dart` les reproduisent. Les noms des clients ne sont pas
conservés ici.

## Règles de l'entrepreneur (confirmées par lui)

- Le bois d'œuvre se vend en **longueurs paires : 8, 10, 12, 14, 16, 18, 20 pi**. Une
  longueur de 15 pi n'existe pas : on arrondit à la longueur du commerce au-dessus.
- Solives 2×8 à 16 po c/c, de la maison vers le bord extérieur ; contreplaqué 5/8 po
  embouveté.
- **Solives de bordure doublées** sur les deux côtés (parallèles aux solives).
- **Rive avant** (bord extérieur) **doublée** ; **rive côté maison simple**. Si une rive
  dépasse la plus longue planche et doit être faite de deux morceaux : on la double et on
  alterne les joints.
- **Étriers** seulement du côté maison (l'autre bout repose sur la poutre) et seulement
  pour les solives intérieures.
- **Entremises** : une rangée tous les 7 à 10 pi de portée, **pose alternée** (blocs
  décalés d'un côté et de l'autre pour les clouer).
- **Poutres** : 2 poutres de 3 plis 2×8 traité, sur toute la largeur du solarium (pièce
  commerciale ≥ largeur réelle, p. ex. 14 pi 1 po → 16 pi), parallèles à la maison.
- **Pieux vissés** : leur position est toujours inscrite sur le plan (le premier est à
  1 pi du bord du plancher, puis l'entraxe du plan : 6 pi ou 6 pi 6 po ; 3 par poutre).
- **6×6 traité** : sert à **rehausser la patte** quand le pieu est trop bas ; la poutre
  repose par-dessus. Quantité = nombre de pieux × hauteur de patte (mesure du terrain).
- **Étriers** : il prend souvent des LUS28 (10 clous chacun) ; le nombre exact de clous
  n'est pas critique : assez pour le plancher, sans trop d'excédent.
- Hors liste : colle à plancher, laine, toiture, rouleau d'aluminium (« pas besoin »).

## Réglages de l'app pour reproduire ses commandes

Solives de bordure doublées · rives doubles · côté de la maison choisi · étriers à un bout,
sans les solives de bordure · entremises automatiques en pose alternée · coupes séparées ·
poutres (2 × 3 plis 2×8, 3 pieux, premier à 12 po) · hauteur de patte.

## Exemple A : 15 pi × 14 pi (solives de 14 pi)

| | Liste de l'entrepreneur | Calcul de l'app |
|---|---|---|
| 2×8 × 14' | 16 | **16** : 15 solives (13 positions + 2 de bordure doublées) + 1 planche d'entremises |
| 2×8 × 16' | 4 | 3 : rive avant ×2 + rive maison ×1 (**1 de moins**) |
| Contreplaqué embouveté | 7 | **7** |
| Étriers 2×8 | 12 | 11 (solives intérieures ; 1 de réserve possible) |
| Poutres 2×8 × 16' traité | 6 | **6** (2 poutres × 3 plis, 16' pour 15') |
| 6×6 traité | 1 × 8' | **1 × 8'** (6 pieux × 16 po) |
| Clous d'étriers | 1 boîte | **1 boîte** (11 × 10 clous + 5 %) |

## Exemple B : 14 pi × 12 pi (mesure réelle 14 pi 1 po × 12 pi ½ po)

| | Liste de l'entrepreneur | Calcul de l'app |
|---|---|---|
| 2×8 × 12' | 14 | **14** (12 positions + 2 de bordure doublées) |
| 2×8 × 14' | rives 4 + entremises 1 = 5 | 4 : rive avant ×2 + rive maison ×1 + 1 planche d'entremises (**1 de moins**) |
| Étriers 2×8 | 10 | **10** |
| Contreplaqué embouveté 5/8 | 6 | **6** (7 avec 12 pi ½ po : une 4e rangée pour ½ po) |
| Poutres 2×8 × 16' traité | 6 | 6 × 14' à 14 pi, **6 × 16'** à 14 pi 1 po |
| 6×6 × 10' traité | 1 | **1 × 10'** (6 pieux × 20 po) |
| Clous d'étriers | 2 boîtes | 1 boîte (10 × 10 clous + 5 %) : il en a pris 2 |

Dans les deux cas, il commande **une planche de la longueur des rives de plus** que le
calcul : c'est une **planche de réserve** (« quelques fois je prends plus de planches si
jamais une arrive courbée ou de mauvaise qualité »). Le calcul ne l'ajoute pas ; on
l'ajoute à la main dans la liste de commande (ligne manuelle) quand on le veut.

## Choix du calcul

- **Trait de scie** : compté partout (1/8 po entre deux coupes) sauf pour les pattes,
  dont la hauteur est une mesure approximative du terrain (6 pattes de 16 po = un 6×6
  de 8 pi).
- **Entremises automatiques** : rangées = ⌈portée ÷ portée sans entremises⌉ − 1, réparties
  également ; portée sans entremises réglable (par défaut 10 pi). Un bloc est posé entre
  chaque paire de solives voisines.
- **Rive doublée en plusieurs morceaux** : le 1er pli est fait de morceaux égaux, le 2e
  commence et finit par un demi-morceau (joints au milieu des morceaux de l'autre pli,
  jamais de morceau plus court qu'un demi-morceau).
- **Clous** : clous nécessaires = étriers × clous par étrier × (1 + marge de 5 %), arrondis
  à la boîte au-dessus (boîte de 120 : 1 lb de 10d × 1 1/2 po).
- **Anciens projets** : un projet enregistré avant ces réglages se relit avec les valeurs
  d'avant (rives doublées partout, tous les étriers, entremises à la main, coupes
  groupées, pas de poutres).

## Sous-plancher (contreplaqué embouveté)

L'entrepreneur veut le **nombre exact de feuilles**, posées de façon conforme et
stratégique : feuilles en travers des solives, joints d'extrémité sur le centre d'une
solive, joints décalés d'un rang à l'autre, chutes réutilisées. Exemple : plancher de
16 pi de large = rangs de 8-8, 4-8-4, 8-8… (les deux demi-feuilles d'un rang 4-8-4 viennent
d'une même feuille) : 6 feuilles pour 16 × 12 pi, sans perte. Le calcul (`_planifierPanneaux`)
cherche la pose qui utilise le moins de feuilles, essaie de commencer par chaque côté et
garde la meilleure ; chaque feuille et chaque joint se voient dans la vue 3D (couche
« + sous-plancher »). Les rangs sont comptés depuis un côté du plancher : 8-8 puis
4-8-4, ou 4-8-4 puis 8-8 selon le côté (même nombre de feuilles).

## Pas encore fait

- **Contreplaqué** : à 12 pi ½ po, une 4e rangée de feuilles pour ½ po (7 au lieu de 6).
  À régler : tolérance sur la dimension ou dimension de l'ossature.
- Poutres et pieux ne sont pas dessinés dans la vue 3D.
- Un plancher qui n'est pas un rectangle : les poutres sont comptées sur la largeur hors
  tout (avertissement).
