# Heures et voyagement

Règles de paie de la compagnie : **Admin → Heures et voyagement** (pauses, dîner,
voyagement). Le calcul est fait par le serveur (`functions/src/feuille_temps.js`) ; l'app
n'affiche que ce que le serveur a enregistré, sauf pour la semaine en cours (aperçu).

## Voyagement payé

Seul le temps **au-delà du seuil** est payé, **au pourcentage choisi** :

    minutes payées = (minutes de voyagement − seuil) × pourcentage ÷ 100   (jamais négatif)

| Voyagement | Seuil | Temps au-delà | Pourcentage | Payé |
|---|---|---|---|---|
| 2 h | 60 min | 1 h | 100 % | 1 h |
| 2 h | 60 min | 1 h | 50 % | 30 min |
| 2 h | 30 min | 1 h 30 | 100 % | 1 h 30 |
| 2 h | 30 min | 1 h 30 | 75 % | 1 h 07,5 |
| 45 min | 60 min | 0 | — | rien |

Le seuil s'applique **par journée**. Seuil à 0 : tout le voyagement est payé au
pourcentage.

## Quand les règles changent

- **Semaine courante** : les feuilles déjà saisies sont recalculées avec les nouvelles
  règles (heures payées, voyagement payé, totaux). Automatique après « Enregistrer pour la
  compagnie » ; le bouton « Recalculer la semaine courante » le refait à la demande
  (fonction `recalculerSemaineCourante`, réservée aux admins de la compagnie).
- **Semaines précédentes** : jamais modifiées. Le recalcul ne touche que la semaine
  courante de la compagnie. Une semaine antérieure renvoyée au serveur garde les valeurs
  d'origine de chaque journée dont la saisie n'a pas changé (heures, pauses, chantier,
  voyagement) ; une journée corrigée est recalculée avec les règles du moment. À l'écran,
  une semaine antérieure affiche les valeurs enregistrées, pas un recalcul.
- La saisie de l'employé (heures, pauses, voyagement) est toujours conservée : seuls les
  montants calculés changent.

## Historique de la formule

Avant octobre 2026, le voyagement dès le seuil était payé en entier au pourcentage (90 min
à partir de 60 min, 50 % : 45 min payées). Les feuilles enregistrées avant le changement
gardent ces valeurs ; seule la semaine courante est recalculée avec la nouvelle formule.

## Tests

`cd tests/rules && npm run test:unitaires` (formule, semaines figées, recalcul) et
`npm run test:functions` (émulateurs : changement de règles, semaine passée intacte,
autre compagnie intacte, droits). Côté app : `flutter test test/regles_paie_test.dart
test/regles_paie_screen_test.dart test/jour_travail_test.dart`.
