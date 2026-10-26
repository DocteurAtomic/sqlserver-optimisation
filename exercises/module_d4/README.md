# Exercice du module D4

Objectif : appliquer les gestes du module à une autre base que celle des démonstrations.
Remplir `tempdb` par chacune de ses trois familles et lire chacune avec le bon instrument,
retenir le magasin de versions par une transaction oubliée, puis compter les tables
temporaires qu'une procédure crée vraiment, avant et après l'avoir corrigée.

L'exercice ne change pas l'instance : tout se passe dans la base d'exercice `ExoTempdb`, que
`1-start.sql` crée et que le corrigé supprime. Jouez-le sur votre labo, après le
`99-cleanup.sql` du module et le redémarrage du conteneur, `charge.sh` arrêté.

## Les fichiers

- `1-start.sql` crée `ExoTempdb` en RCSI, comme `PachadataTraining`, y copie le million de
  prospects de `Contact.ProspectUS` dans `dbo.Prospect`, crée la procédure de la partie 2,
  puis donne le squelette des deux parties, qui ne s'exécute pas tant que vous n'avez pas
  retiré la ligne `SET NOEXEC ON`.
- `2-forgotten-transaction.sql` est la transaction oubliée de la partie 1, question 3 : elle
  modifie un prospect, attend deux minutes et demie sans valider, puis valide.
- `3-solution.sql` est le corrigé, à lire après avoir cherché. Il dure environ cinq minutes,
  surtout en attentes du nettoyage du magasin de versions, et supprime `ExoTempdb` à la fin.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_d4/1-start.sql
```

La partie 1 se joue dans une seule session (une fenêtre de SSMS) : la table temporaire et les
compteurs de session lui appartiennent. La question 3 demande une seconde fenêtre. La partie 2
appelle 2 000 fois une procédure qui renvoie cinquante lignes : dans SSMS, cochez avant de la
lancer « Ignorer les résultats après l'exécution » (Options de la requête, Résultats, Grille).

## Partie 1. Les familles de tempdb

1. Copiez tous les prospects dans une table temporaire. Lisez les pages que la session a
   allouées et libérées (`sys.dm_db_session_space_usage`), puis ce que `tempdb` contient par
   famille (`sys.dm_db_file_space_usage`, lue dans `tempdb`). Pourquoi la session a-t-elle
   libéré des pages alors que la table existe toujours ?
2. Lancez le tri du squelette, limité par `MAX_GRANT_PERCENT = 0.1`, puis relisez les mêmes
   compteurs de session. Qu'est-ce qui a changé, et que reste-t-il dans `tempdb` après la
   requête ? Où le plan réel le signale-t-il ?
3. Lancez `2-forgotten-transaction.sql` dans une seconde fenêtre, puis, dans la première, la
   mise à jour de tous les autres prospects. Lisez le magasin de versions par base
   (`sys.dm_tran_version_store_space_usage`) et les transactions qui peuvent encore avoir
   besoin d'une version (`sys.dm_tran_active_snapshot_database_transactions`) : tout de suite,
   une minute et demie plus tard, puis après la fin de la seconde fenêtre. Pourquoi les
   versions restent-elles alors que la mise à jour est validée ?

## Partie 2. La table temporaire d'une procédure

1. Relevez `Temp Tables Creation Rate` avant et après les 2 000 appels de
   `dbo.GetMailingBatch`. Combien de tables temporaires l'instance a-t-elle vraiment créées ?
2. Lisez la procédure, et modifiez-la pour que SQL Server puisse mettre sa table en cache.
   Mesurez à nouveau : nombre de tables créées et durée des 2 000 appels.
3. La modification corrige un second défaut, qui n'apparaît qu'avec plusieurs sessions
   simultanées. Lequel ?
