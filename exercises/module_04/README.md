# Exercice du module 4

Objectif : appliquer les gestes du module à une autre procédure que celle des
démonstrations. Retrouver une régression dans le Query Store, forcer le bon plan et en mesurer
l'effet, bloquer un rapport ad hoc par un indicateur du Query Store, et suivre un forçage
quand le code de la procédure change.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure environ une
minute : il attend l'intervalle suivant du Query Store entre ses deux périodes de charge.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, vide son Query Store,
  puis joue une charge sur `Contact.ProspectsByParameter`, la recherche de prospects par code
  postal du service marketing (`ZipCode LIKE @zip`) : une première période, une
  recompilation, puis la période qui suit. Entre les deux, quelque chose s'est mal passé. Ne
  lisez pas le script avant d'avoir cherché.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il ne laisse rien derrière
  lui : le forçage et l'indicateur sont retirés, et la procédure modifiée à la partie 4
  retrouve sa définition d'origine.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), ou passez-les à `sqlcmd` dans le
conteneur, qui connaît déjà le mot de passe :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_04/1-start.sql
```

Avec `sqlcmd`, commencez vos propres scripts par `SET ARITHABORT ON;`, comme le font ceux du
cours : sinon votre session ne partage ni le plan en cache ni la requête du Query Store avec
celle de SSMS.

## Partie 1. Retrouver la régression

1. Quelles sont les requêtes les plus coûteuses de la dernière heure, en temps processeur
   total ? Combien de plans la première a-t-elle ?
2. Pour la requête de `Contact.ProspectsByParameter`, donnez, intervalle par intervalle, le
   plan employé, le nombre d'exécutions et les lectures moyennes, minimales et maximales.
   Quelle forme a chaque plan ?
3. Le moteur a-t-il repéré la régression ? Que propose-t-il ?

## Partie 2. Forcer, et mesurer

1. Forcez le plan qui lit le moins en moyenne.
2. Rejouez la séquence de la charge : `sp_recompile`, un premier appel pour `'9%'`, puis un
   appel pour le code postal `'10001'`. Combien de lectures pour chacun, sous `SET STATISTICS
   IO ON` ? Comparez avec ce que lisait chacun dans la période régressée.
3. Le forçage est-il appliqué, sans échec ? Le plan forcé convient-il à toutes les valeurs du
   paramètre ? Qu'est-ce que ce forçage ne corrige pas ?

## Partie 3. Bloquer un rapport ad hoc

Un utilisateur lance à la main un rapport qui compte les prospects par ville sur toute la
table (`SELECT TOP (5) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City
ORDER BY Prospects DESC;`).

1. Exécutez-le une fois, puis retrouvez son `query_id` dans le Query Store.
2. Interdisez-le par l'indicateur `ABORT_QUERY_EXECUTION` (SQL Server 2025). Que se passe-t-il
   à l'exécution suivante ? Quel numéro d'erreur ?
3. Que garde le Query Store de ces exécutions (`execution_type_desc`) ?
4. Retirez l'indicateur. L'interdiction vise-t-elle une intention ou un texte ?

## Partie 4. Le code modifié

Gardez le plan forcé de la partie 2.

1. Ajoutez un commentaire dans la procédure, sur la ligne qui précède l'instruction `SELECT`,
   puis appelez-la. La requête garde-t-elle son `query_id` ? Le plan forcé s'applique-t-il ?
2. Ajoutez maintenant la colonne `City` à la liste du `SELECT`, puis appelez-la. Que voit le
   Query Store ? Le forçage suit-il ?
3. Remettez la procédure dans son état d'origine et retirez le forçage.
