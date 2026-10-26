# Exercice du module 1

Le premier coup d'œil, appliqué à une autre requête que celle de la démonstration : un
rapport lent lancé dans une fenêtre, observé depuis une autre pendant qu'il tourne. Avant cela,
l'inventaire de ce que le moteur voit du labo.

Il se joue sur le labo, après le `00-setup.sql` du module (`demos/module_01`), sans la charge
de fond : arrêtez `charge.sh` s'il tourne, pour ne voir que le rapport. Rien n'est créé ni
modifié.

## Les fichiers

- `1-start.sql` : la fenêtre 1. Elle affiche son numéro de session, puis lance
  `Report.LapsedReaders`, qui dure une vingtaine de secondes sur le labo.
- `2-solution.sql` : le corrigé, à lancer dans la fenêtre 2 pendant que la fenêtre 1
  travaille. Les réponses, mesurées sur le labo, sont en commentaire à la fin.

## Les questions

1. Que voit le moteur de la machine (`sys.dm_os_sys_info`) : combien de processeurs et
   d'ordonnanceurs, combien de mémoire ? Comparez aux limites du conteneur dans
   `compose.yaml`. D'où viennent les écarts ?
2. Pendant que le rapport tourne, trouvez sa requête depuis la fenêtre 2 : état, attente en
   cours, temps processeur et durée, lectures logiques, degré de parallélisme, instruction
   exacte. Le rapport attend-il, ou calcule-t-il ?
3. Ses tâches attendent-elles quelque chose en ce moment (`sys.dm_os_waiting_tasks`) ?
4. Suivez son avancement opérateur par opérateur dans `sys.dm_exec_query_profiles`. Quel
   opérateur s'écarte de son estimation, et de combien ? Qu'est-ce que cela dit du plan ?
   Pourquoi les opérateurs de tri restent-ils à zéro ?
5. Qu'a attendu la session depuis son ouverture (`sys.dm_exec_session_wait_stats`) ?
   Que disent ces attentes du temps passé par le rapport ?

## Le corrigé

Les réponses sont à la fin de `2-solution.sql`.
