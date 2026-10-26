# Exercice du module D3

Objectif : appliquer les gestes du module à d'autres charges que celle des démonstrations.
Relever les attentes d'une charge qui écrit sur un intervalle et dire qui les a attendues,
mesurer par les compteurs ce que coûte une requête concaténée par rapport à la même requête
paramétrée, puis comparer sur une base seule le cache de plans d'une charge ad hoc sans
option, avec `OPTIMIZE_FOR_AD_HOC_WORKLOADS` et avec le paramétrage forcé.

L'exercice ne change pas l'instance : les options de la partie 3 se posent sur la base
d'exercice `ExoWaits`, que `1-start.sql` crée et que le corrigé supprime. Jouez-le sur votre
labo, après le `99-cleanup.sql` du module, `charge.sh` arrêté.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée (paramétrage simple),
  crée `ExoWaits` (une table de clics vide, et 300 000 prospects copiés de
  `Contact.ProspectUS`), puis donne le squelette des trois parties, qui ne s'exécute pas
  tant que vous n'avez pas retiré la ligne `SET NOEXEC ON`.
- `2-load.sql` est la charge de la partie 1 : 45 secondes d'insertions validées ligne à
  ligne dans `ExoWaits.dbo.ClickLog`, entrecoupées d'un comptage parallèle des prospects de
  Boston dans `Contact.ProspectUS`.
- `3-solution.sql` est le corrigé, à lire après avoir cherché. Il dure une minute et demie,
  et supprime `ExoWaits` à la fin.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_d3/1-start.sql
```

Les charges des parties 2 et 3 renvoient chacune des milliers de petits résultats : dans
SSMS, cochez avant de les lancer « Ignorer les résultats après l'exécution » (Options de la
requête, Résultats, Grille), sinon la grille ralentit la mesure.

## Partie 1. Les attentes d'une autre charge

1. Lancez `2-load.sql` dans une première fenêtre. Dans une seconde, dans les cinq secondes,
   prenez deux relevés de `sys.dm_os_wait_stats` à trente secondes d'intervalle, sans les
   attentes de repos (la liste de `demos/module_d3/01a-waits-interval.sql`). Donnez pour
   chaque attente sa part du total, sa durée moyenne et sa part de signal.
2. Quelles signatures reconnaissez-vous ? À quelle partie de la charge correspond chacune ?
3. Pendant que la charge tourne, lisez les attentes de sa session dans
   `sys.dm_exec_session_wait_stats`. Les attentes du journal viennent-elles cette fois de la
   session elle-même ou d'une tâche de fond ? Quel remède proposeriez-vous, et dans quoi ?

## Partie 2. Les compteurs d'une autre requête

1. Relevez `Batch Requests/sec`, `SQL Compilations/sec` et le compteur `optimizations` de
   `sys.dm_exec_query_optimizer_info`, lancez la charge A du squelette (2 000 lots, la page
   d'une session du catalogue, son identifiant concaténé dans le texte), puis
   calculez la différence et le débit par seconde.
2. Même mesure pour la charge B, la même requête passée par `sp_executesql` avec un
   paramètre.
3. Combien de compilations et combien d'optimisations par lot dans chaque charge ? D'où
   vient la compilation qui reste dans la charge B ? Que laisse chaque charge dans le cache ?

## Partie 3. Le cache de plans d'une base

1. Videz le cache de `ExoWaits` (`ALTER DATABASE SCOPED CONFIGURATION CLEAR
   PROCEDURE_CACHE`), lancez la boucle de 500 requêtes concaténées du squelette, et comptez
   ses plans par `cacheobjtype` : nombre, taille, plans utilisés une fois, optimisations.
2. Même chose avec l'option de base `OPTIMIZE_FOR_AD_HOC_WORKLOADS = ON`.
3. Même chose avec `ALTER DATABASE ExoWaits SET PARAMETERIZATION FORCED`.
4. Laquelle des deux options réduit la mémoire, laquelle réduit les optimisations ? Pourquoi
   l'option de base vaut-elle mieux, pour un essai, que `optimize for ad hoc workloads` de
   l'instance ?
