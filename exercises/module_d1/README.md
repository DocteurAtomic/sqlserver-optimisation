# Exercice du module D1

Objectif : appliquer les gestes du module à d'autres requêtes et à d'autres valeurs que celles
des démonstrations. Observer ce qu'une requête parallèle coûte et attend, mesurer un même
agrégat à trois degrés de parallélisme puis relever le seuil de coût au-dessus de son plan en
série, et calculer `max server memory` en retirant la pile des threads de travail.

L'exercice change la configuration de l'instance. Jouez-le sur votre labo, après le
`99-cleanup.sql` du module. Le corrigé remet les valeurs du labo à la fin.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée (`MAXDOP` 2 dans la
  base), affiche les réglages de l'instance et la mémoire que voit le moteur, puis donne les
  deux requêtes de l'exercice : les contacts qui ont reçu le plus d'e-mails
  (`Marketing.Delivery`, 4 millions de lignes), et les villes qui ont le plus de prospects
  (`Contact.ProspectUS`, un million de lignes).
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure un peu plus d'une minute,
  et remet `cost threshold for parallelism` à 5, `max server memory` sans plafond et
  `show advanced options` à 0.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_d1/1-start.sql
```

## Partie 1. Une requête parallèle

1. Dans une nouvelle fenêtre, lancez la requête des e-mails avec `OPTION (MAXDOP 4)`, sous
   `SET STATISTICS TIME ON`. Combien de processeur, combien d'écoulé ? Quelles attentes la
   session a-t-elle accumulées (`sys.dm_exec_session_wait_stats`) ?
2. Même chose avec `OPTION (MAXDOP 1)`, dans une nouvelle fenêtre. Que gagne le parallélisme,
   et que coûte-t-il ?

## Partie 2. Le degré et le seuil

1. Videz le cache de la base (`ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE`), puis
   lancez cinq fois la requête des villes avec `OPTION (MAXDOP 1)`, cinq fois avec
   `OPTION (MAXDOP 4)`, cinq fois sans indicateur (`GO 5` répète un lot).
2. Pour chaque variante, lisez dans `sys.dm_exec_query_stats` le dernier DOP, le processeur et
   la durée moyens, et le coût du plan (`StatementSubTreeCost` du plan en cache). Quel DOP prend
   la requête sans indicateur, et pourquoi ?
3. Quel coût l'optimiseur compare-t-il au seuil ? Relevez `cost threshold for parallelism`
   juste au-dessus, relancez la requête sans indicateur et relisez son DOP.
4. Remettez le seuil à 5.

## Partie 3. max server memory

1. Calculez `max server memory` pour une instance seule, d'après la recommandation de Learn : la mémoire
   que voit le moteur, moins la pile des threads de travail (2 Mo par thread en 64 bits, fois
   `max_workers_count`), puis 75 % du reste. Comparez avec les 3 687 Mo de la démonstration.
2. Posez cette valeur. Comptez les plans en cache juste avant et juste après le `RECONFIGURE`.
3. Lisez la cible dans `sys.dm_os_sys_info` et dans le compteur `Target Server Memory (KB)` de
   `sys.dm_os_performance_counters`, dix secondes puis une minute après. Les deux sources
   donnent-elles la même valeur ? Que devient la mémoire validée ?
4. Remettez `max server memory` sans plafond (2 147 483 647) et `show advanced options` à 0.
