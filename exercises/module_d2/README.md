# Exercice du module D2

Objectif : appliquer les gestes du module à d'autres objets que ceux des démonstrations.
Mesurer sur leur intervalle deux lectures connues, à froid ; faire grandir le journal d'une
base d'exercice par pourcentage, compter ses VLF, le corriger, et vérifier sur votre labo la
règle de découpage ; répartir une table sur un groupe de deux fichiers.

L'exercice se joue sur votre labo, dans une seule session. La partie 1 met `PachadataTraining`
hors ligne puis en ligne pour vider son cache : jamais sur un serveur de production. Les parties
2 et 3 travaillent sur une base à elles, `ExoStorage`.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, affiche ses fichiers, les
  dossiers par défaut de l'instance, et les deux tables de la partie 1 : `Contact.ProspectUS`,
  un tas d'un million de prospects, et `Marketing.Delivery`, 4 millions d'envois avec une clé
  primaire cluster sur `DeliveryId`.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il dure une quinzaine de
  secondes, et supprime `ExoStorage` à la fin.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_d2/1-start.sql
```

## Partie 1. Les lectures à froid

1. Videz le cache de la base (mise hors ligne puis en ligne). Prenez un instantané de
   `sys.dm_io_virtual_file_stats`, comptez les prospects de Boston dans `Contact.ProspectUS`, et
   calculez sur l'intervalle les lectures, les Mo lus, les Ko par lecture et les ms par lecture
   de chaque fichier.
2. Videz de nouveau le cache, et faites la même mesure sur 2 000 recherches par clé au hasard
   dans `Marketing.Delivery`.
3. Laquelle des deux a la latence la plus haute ? Pourquoi ne faut-il pas en conclure que le
   disque est plus lent pour elle ? Que lit le fichier journal ?

## Partie 2. Un journal en croissance de 10 %

1. Créez la base `ExoStorage` en mode de récupération simple, le fichier de données à 512 Mo,
   et le journal (8 Mo, hérités de `model`) en croissance de 10 %.
2. Créez une table `dbo.Payload` (une clé `int IDENTITY`, une colonne `char(500)`), et insérez
   400 000 lignes en une seule instruction.
3. Combien de VLF le journal compte-t-il, de quelle taille au plus petit et au plus grand ?
   Listez les premiers VLF dans l'ordre du fichier (`vlf_begin_offset`) : que reconnaissez-vous
   dans leurs tailles ?
4. Corrigez le journal : réduction, puis taille de 512 Mo en une étape, croissance de 256 Mo.
   Combien de VLF reste-t-il ?
5. La règle de 2022 : à partir d'un journal de 64 Mo, faites-le grandir de 64 Mo, et comptez les
   VLF ajoutés. Recommencez à partir de 64 Mo avec une croissance de 65 Mo. Learn annonce un
   seul VLF pour une croissance de 64 Mo au plus : que mesurez-vous ?

## Partie 3. Un groupe de deux fichiers

1. Ajoutez à `ExoStorage` un groupe de fichiers `Archive` de deux fichiers de 128 Mo, croissance
   de 64 Mo, dans le dossier de données par défaut de l'instance
   (`SERVERPROPERTY('InstanceDefaultDataPath')`), qui grandissent ensemble
   (`AUTOGROW_ALL_FILES`).
2. Déplacez `dbo.Payload` dans ce groupe, sans changer le nom de sa clé primaire.
3. Comment ses pages se répartissent-elles entre les deux fichiers ? Et dans `PRIMARY`, juste
   après le déplacement ?
4. Doublez la table. Que deviennent les deux fichiers ?
