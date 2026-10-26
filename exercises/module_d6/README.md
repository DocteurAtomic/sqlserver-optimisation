# Exercice du module D6

Objectif : appliquer les trois gestes de maintenance du module à une autre table, celle des
transactions de LuminaQuant. Mesurer quand une statistique se recalcule seule, choisir les
index à créer et celui à désactiver, puis traiter un index fragmenté en lisant ce que coûte
chaque commande.

L'exercice se joue sur votre labo. `1-start.sql` dure une dizaine de secondes, `2-load.sql`
quelques secondes. La dernière question de la partie 3 demande deux sessions.

## Les fichiers

- `1-start.sql` crée la base `ExoMaintenance`, en mode de récupération simple, avec une table
  `dbo.Trade` : les 1 413 356 transactions du 5 mars 2025, copiées de `LuminaQuant`, qui n'est
  que lue. Il crée quatre index : la clé primaire cluster sur `TradeId`, un index sur l'heure
  d'exécution, un index sur le prix rempli à 100 %, et un index sur `ExternalId`, l'identifiant
  d'une ancienne passerelle de courtage.
- `2-load.sql` insère les 30 000 premières transactions du 6 mars une par une, comme le fait
  l'application, puis lance quelques fois les rapports de la nouvelle application de risque.
- `3-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime `ExoMaintenance` à la
  fin.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Les estimations se lisent dans le
plan réel (Ctrl+M) : `Estimated Number of Rows` contre `Actual Number of Rows`.

## Partie 1. La statistique de l'heure d'exécution

1. Lisez la statistique de `IX_Trade_ExecutedAt` dans `sys.dm_db_stats_properties`, et la
   dernière étape de son histogramme. Combien de modifications a-t-elle subies, et combien en
   faut-il pour que SQL Server la recalcule seul ? Et avec la règle d'avant SQL Server 2016 ?
2. Lancez la somme des transactions du 6 mars avec le plan réel :

   ```sql
   SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade
   WHERE ExecutedAt >= '20250306' OPTION (RECOMPILE);
   ```

   Que vaut l'estimation, et d'où vient ce nombre ? Le module a montré la règle d'une égalité
   au-delà de l'histogramme ; celle d'une inégalité est différente.
3. Insérez juste assez de transactions suivantes pour que le compteur s'arrête une
   modification sous le seuil, relancez la requête, relisez la statistique. Puis ajoutez-en une.
   Qu'est-ce qui change, et sur combien de lignes la statistique a-t-elle été calculée ?

## Partie 2. Index manquants et index inutilisé

1. Lisez les suggestions d'index manquants de la base, classées par score. Lesquelles
   pourraient être servies par un seul index ? Écrivez-le, et dites ce que vous laissez de côté.
2. Mesurez les deux premiers rapports de `2-load.sql` avant et après sa création. Que deviennent
   les suggestions ?
3. Lisez l'utilisation des index de la table. Lequel est écrit sans jamais être lu ? Depuis quand
   ces compteurs courent-ils, et qu'est-ce qui vous retiendrait de le supprimer aujourd'hui ?
   Mettez-le hors service sans perdre sa définition, et vérifiez la place qu'il occupe.

Lisez les suggestions avant toute reconstruction d'index dans la base : la partie 3 vous dira
pourquoi.

## Partie 3. L'index du prix

1. Comparez l'état des feuilles des index de la table (fragmentation, remplissage, nombre de
   pages) et les pages allouées pendant les insertions. Pourquoi l'index du prix est-il le seul
   abîmé ?
2. Réorganisez-le, en mesurant le temps et le journal écrit. Que devient sa statistique ?
3. Reconstruisez-le en ligne et de façon reprenable, avec les mêmes mesures. Que devient sa
   statistique cette fois, et ses compteurs d'utilisation ?
4. Dans une première session, reconstruisez la clé primaire en ligne, reprenable, sur un seul
   thread. Dans une seconde, pendant qu'elle tourne, mettez-la en pause, lisez son état, puis
   reprenez-la. Que reste-t-il dans `sys.index_resumable_operations` à la fin ?
