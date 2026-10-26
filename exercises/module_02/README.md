# Exercice du module 2

Objectif : appliquer les gestes du module à d'autres tables que celles des démonstrations.
Lire une page de `Contact.Contact`, mesurer à froid et à chaud deux tables qui contiennent les
mêmes lignes, et suivre le journal d'une transaction pendant qu'elle est ouverte.

L'exercice se joue sur votre labo, dans une seule session. La partie 2 met la base hors ligne
puis en ligne pour vider son cache : jamais sur un serveur de production.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée et affiche les trois
  tables de l'exercice.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il ne laisse rien derrière
  lui : la transaction de la partie 3 est annulée.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur, qui connaît déjà le mot de passe :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_02/1-start.sql
```

## Partie 1. Une page de Contact.Contact

1. Dans quelle page, et à quel emplacement (slot), se trouve le contact 1234 ? La
   pseudo-colonne `%%physloc%%` et la fonction `sys.fn_PhysLocFormatter` vous le disent.
2. Lisez l'en-tête de cette page avec `sys.dm_db_page_info`, en mode `DETAILED`. Combien de
   lignes contient-elle, combien d'octets libres ? Quelles sont la page précédente et la page
   suivante ? Sont-elles voisines dans le fichier ?
3. Combien de lignes une page de `Contact.Contact` contient-elle en moyenne, et quelle est la
   taille moyenne d'une ligne (`sys.dm_db_index_physical_stats`, niveau feuille de l'index
   cluster) ? Comparez avec les 250 lignes de 30 octets par page de `Elearning.Activity`, vues
   en démonstration.

## Partie 2. La taille des lignes

`Contact.ProspectUS` et `Contact.ProspectUS_N` contiennent le même million de prospects. La
seconde déclare ses colonnes de texte en `nvarchar` au lieu de `varchar`.

1. Combien de pages occupe chacune des deux tables ?
2. Videz le cache de la base (mise hors ligne puis en ligne), puis comptez deux fois de suite,
   dans chaque table, les prospects de Boston, sous `SET STATISTICS IO, TIME ON`. Relevez pour
   chaque exécution les lectures logiques, physiques et anticipées.
3. Combien d'attentes `PAGEIOLATCH_SH` votre session a-t-elle subies, et pendant combien de
   temps ? Lisez `sys.dm_exec_session_wait_stats` avant et après.
4. Qu'est-ce qui change d'une table à l'autre, et qu'est-ce qui change entre la première et
   la seconde exécution ?

## Partie 3. Le journal d'une transaction ouverte

1. Ouvrez une transaction, et passez en majuscules la ville des prospects de Boston dans
   `Contact.ProspectUS`. Combien d'enregistrements du journal et combien d'octets la
   transaction a-t-elle écrits (`sys.dm_tran_database_transactions`) ?
2. Sans valider, lancez un `CHECKPOINT`. Que dit `log_reuse_wait_desc` dans
   `sys.databases` ? Combien de pages sales reste-t-il dans le cache pour la base ?
3. Annulez la transaction. Les pages que le point de contrôle a écrites sur le disque
   contenaient une modification non validée : qu'est-ce qui garantit que la base reste
   cohérente ?
