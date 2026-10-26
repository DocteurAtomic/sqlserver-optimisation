# Exercice du module V8

Objectif : appliquer à deux autres procédures les gestes du module. Voir le memory grant feedback
corriger une procédure d'une exécution à la suivante, le lire dans le Query Store, puis le couper
pour cette procédure seule ; mesurer l'effet de l'OPPO sur une autre recherche à critères
facultatifs, et le coût de sa désactivation.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure quelques secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, au niveau de
  compatibilité 170, ajoute un index sur `Contact.ProspectUS (LastName)`, puis crée deux procédures
  écrites avec des défauts déjà vus dans le cours :
  - `Elearning.LongestActivities @Since, @MinSeconds`, les activités e-learning des deux premiers
    millions, depuis une date et au-dessus d'une durée, triées par durée. Son développeur a copié
    les paramètres dans des variables locales « pour éviter le reniflage des paramètres » ;
  - `Contact.FindProspects @ZipCode, @LastName`, la recherche de l'équipe commerciale dans les
    prospects américains, par code postal ou par nom, les deux facultatifs
    (`Col = @p OR @p IS NULL`).
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime à la fin ce que
  `1-start.sql` a créé et remet la base au niveau 170.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`), plan réel activé (`Ctrl+M`) : l'octroi
de mémoire se lit dans les propriétés de l'opérateur `SELECT`, élément `MemoryGrantInfo`.

## Partie 1. Le tri des activités les plus longues

```sql
EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
```

1. Passez la base au niveau 140, puis exécutez la procédure trois fois. Lisez à chaque fois la
   mémoire accordée, la mémoire utilisée et les pages déversées
   (`sys.dm_exec_query_stats` : `last_grant_kb`, `last_used_grant_kb`, `last_spills`). Pourquoi
   rien ne change-t-il d'une exécution à l'autre ? Pourquoi l'estimation du tri est-elle fausse ?
2. Repassez la base au niveau 170 et exécutez-la de nouveau trois fois. Que montrent les mêmes
   colonnes, et `IsMemoryGrantFeedbackAdjusted` dans le plan réel ?
3. Retrouvez le retour dans le Query Store. Dans quel état est-il, et que contient
   `feedback_data` ?
4. Faites recompiler la procédure, puis exécutez-la une fois. Quelle mémoire reçoit la première
   exécution du nouveau plan, et pourquoi ?
5. Coupez le memory grant feedback pour cette procédure seule, sans modifier son code ni la
   configuration de la base, puis mesurez deux exécutions. Effacez ensuite ce que vous avez posé.

## Partie 2. La recherche des prospects

```sql
EXEC Contact.FindProspects @LastName = 'Kowalski';
EXEC Contact.FindProspects @ZipCode = '62086';
```

1. Exécutez les deux recherches dans cet ordre, avec `SET STATISTICS IO ON`. Combien de pages
   lit chacune ?
2. Retrouvez les variantes de la requête dans le Query Store. Quel paramètre facultatif l'OPPO
   a-t-elle retenu ?
3. Réécrivez la procédure pour désactiver l'OPPO dans son code, puis rejouez les deux recherches
   dans le même ordre. Que coûte la seconde, et pourquoi ?

Rendez à la base son état de départ en jouant la fin du corrigé, ou en relançant le
`00-setup.sql` du module suivant.
