# Exercice du module 3

Objectif : lire trois plans d'exécution réels sur d'autres tables que celles des
démonstrations, et dire pour chacun ce que fait le moteur, où partent les pages, et si
l'estimation tient.

L'exercice se joue sur votre labo, dans une seule session. Il ne modifie rien, sauf à la
dernière question, qui crée un index et le supprime ensuite.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée et affiche les index
  des tables de l'exercice.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il ne laisse rien derrière
  lui : l'index de la partie 3 est supprimé à la fin.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M)
et `SET STATISTICS IO ON` avant de lancer chaque requête : les réponses se lisent dans le
plan, en survolant les opérateurs ou dans leurs propriétés (F4), et dans l'onglet des
messages.

## Partie 1. Les sessions d'un cours

```sql
SELECT s.SessionId, s.StartDate, s.Price, s.StatusCode
FROM Course.Session AS s
WHERE s.CourseId = 169;
```

1. Quel opérateur lit `Course.Session`, et combien de pages lit-il ?
2. L'index `nix_temp_02` commence par `CourseId`. Pourquoi l'optimiseur ne s'en sert-il pas ?
3. Relancez la requête pour le cours 106. Qu'est-ce qui change dans le plan, et combien de
   pages sont lues ?
4. Combien de sessions chaque cours a-t-il, et combien de pages la table occupe-t-elle ?
   Expliquez les deux choix de l'optimiseur.

## Partie 2. Les notes des évaluations de 2026

```sql
SELECT q.Position, q.Label, COUNT(*) AS Answers, AVG(1.0 * a.Rating) AS AverageRating
FROM Enrollment.Evaluation AS v
JOIN Enrollment.Answer AS a ON a.EvaluationId = v.EvaluationId
JOIN Enrollment.Question AS q ON q.QuestionId = a.QuestionId
WHERE v.EvaluationDate >= '20260101'
GROUP BY q.Position, q.Label
ORDER BY q.Position;
```

1. Lisez le plan de droite à gauche. Par quel algorithme `Evaluation` et `Answer`
   sont-elles jointes, et laquelle des deux construit la table de hachage ?
2. À quel endroit du plan le regroupement est-il fait, avant ou après la jointure avec
   `Enrollment.Question` ? Combien de lignes reste-t-il à joindre aux questions ?
3. Le balayage de `Answer` rend 59 872 lignes. Combien en a-t-il lu (*Number of Rows Read*) ?
   Qu'est-ce qui a écarté les autres ?
4. Le `SELECT` affiche un avertissement. Lequel ? Comparez la mémoire accordée et la mémoire
   employée.
5. Dans quel mode d'exécution (*Actual Execution Mode*) tournent la jointure et le
   regroupement ?

## Partie 3. Les événements d'un apprenant

```sql
SELECT a.EventTypeCode, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
FROM Elearning.Activity AS a
WHERE a.ContactId = 53616
GROUP BY a.EventTypeCode;
```

1. Quel opérateur lit la table, et pourquoi ce nom plutôt que *Clustered Index Scan* ?
2. Combien de pages lit-il, pour combien de lignes gardées ? L'estimation est-elle juste ?
3. Le plan est parallèle. À quoi le voyez-vous, et pourquoi y a-t-il deux opérateurs
   `Stream Aggregate` ?
4. Le plan propose un index. Lequel, avec quel impact estimé ? Créez-le sous le nom
   `nix_exercise_03`, relancez la requête, et relevez les pages lues par la requête et la
   taille de l'index. Le créeriez-vous en production pour cette requête seule ?
   Supprimez-le ensuite.
