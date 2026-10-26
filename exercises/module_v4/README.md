# Exercice du module V4

Objectif : séparer, sur une autre table que celle des démonstrations, le gain du mode batch
et celui du stockage en colonnes ; reconnaître l'écriture d'un agrégat qui perd le calcul
dans le balayage ; mesurer l'élimination de segments ; suivre les rowgroups d'une table
columnstore à travers un chargement, des modifications et une réorganisation.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure quelques
secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, au niveau de
  compatibilité 170, et montre les trois tables de l'exercice. Il donne les requêtes des quatre
  parties, en commentaire.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il vide à la fin la table qu'il
  a remplie.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M) et
`SET STATISTICS IO, TIME ON`. Le mode d'exécution se lit dans les propriétés de chaque
opérateur (`Actual Execution Mode`), le calcul fait dans le balayage dans
`Actual Number of Locally Aggregated Rows`.

Les trois tables :

- `Elearning.Activity`, le journal de la plateforme de formation à distance : 7,8 millions de
  lignes, dans un tas ;
- `Analytics.ActivityFact`, les mêmes lignes dans un index columnstore cluster ordonné sur
  `EventTime` ;
- `Analytics.LoadTest`, une table vide de même structure, munie elle aussi d'un index
  columnstore cluster.

## Partie 1. Trois fois le même agrégat

Le nombre d'événements et la durée totale par type d'événement, sur le tas en mode ligne forcé,
sur le tas en laissant l'optimiseur choisir, puis sur la table columnstore.

1. Relevez pour chacune les pages lues, le temps processeur et le mode d'exécution du
   balayage.
2. Qu'est-ce qui change entre la première et la deuxième ? Et entre la deuxième et la
   troisième ?
3. Sur la table columnstore, combien de lignes le balayage passe-t-il à son parent ? Où
   l'agrégat a-t-il été calculé ?

## Partie 2. Trois écritures d'une moyenne

La durée moyenne en minutes par type d'événement, écrite de trois façons.

1. Lesquelles rendent le même résultat ?
2. Laquelle coûte dix fois plus de processeur que les autres, et pourquoi ?
3. Quelle écriture donne le résultat exact au coût le plus bas ?

## Partie 3. Deux filtres

Deux requêtes sur la table columnstore : l'une filtre une année de `EventTime`, l'autre un
contact.

1. Combien de segments chacune lit-elle, et combien en saute-t-elle ?
2. Pourquoi la même table élimine-t-elle des segments pour l'une et pas pour l'autre ?

## Partie 4. La vie des rowgroups

Sur `Analytics.LoadTest`, après chaque étape, lisez les rowgroups avec la requête
donnée par `1-start.sql` :

1. insérez 150 000 lignes avec `TABLOCK` ;
2. videz la table, puis insérez les mêmes lignes avec `OPTION (MAXDOP 1)` ;
3. supprimez 10 000 lignes et mettez-en à jour 5 000 ;
4. lancez `ALTER INDEX ccix_LoadTest ON Analytics.LoadTest REORGANIZE` avec
   `COMPRESS_ALL_ROW_GROUPS = ON`, puis sans option.

Pour chaque étape : combien de groupes, dans quel état, avec quelle raison de taille, et
combien de lignes supprimées ? Pourquoi 150 000 lignes, plus que le seuil de 102 400, ne
donnent-elles pas toujours un groupe compressé ?
