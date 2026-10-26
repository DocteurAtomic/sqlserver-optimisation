# Exercice du module V3

Objectif : retrouver les règles de l'estimateur sans statistique, mesurer ce qu'une statistique
change et quand elle le change, puis prévoir une estimation en lisant l'histogramme et la
densité avant d'exécuter la requête.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure quelques
secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, désactive
  `AUTO_CREATE_STATISTICS` et supprime les statistiques que l'optimiseur avait créées sur
  `Contact.ProspectUS_N`. Il donne les requêtes des trois parties, en commentaire.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime à la fin la
  statistique qu'il a créée et réactive `AUTO_CREATE_STATISTICS`.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M) : les
estimations se lisent sur l'opérateur `Table Scan`, `Estimated Number of Rows` contre
`Actual Number of Rows`.

`Contact.ProspectUS_N` contient un million de prospects américains, dans un tas, sans index.
Après `1-start.sql`, elle n'a plus aucune statistique.

## Partie 1. Sans statistique

Quatre requêtes filtrent sur `City` : une égalité, un `LIKE` sur un préfixe, une inégalité, et
trois villes en `IN` avec un tri.

1. Relevez l'estimation et le nombre réel de lignes de chaque requête. Quelle règle donne chaque
   estimation, à partir du million de lignes ?
2. Que dit le plan du tri de la quatrième requête, et pourquoi ?

## Partie 2. La statistique

Créez une statistique sur `City`, en lecture complète.

1. Relancez la première requête telle quelle, puis avec `OPTION (RECOMPILE)`. Qu'est-ce qui
   change, et pourquoi pas la première fois ?
2. Relancez les trois autres avec `OPTION (RECOMPILE)`. Que sont devenues les estimations, et le
   tri ?

## Partie 3. Lire avant d'exécuter

Lisez la statistique avec `DBCC SHOW_STATISTICS`. Avant de lancer les deux requêtes sur Columbus,
la valeur écrite puis la valeur dans une variable, dites ce que l'optimiseur va estimer, et à
partir de quelle partie de la statistique.
