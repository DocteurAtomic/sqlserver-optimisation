# Exercice du module V6

Objectif : appliquer à deux autres pièces de code les gestes du module. Remplacer une boucle et
un curseur par des requêtes ensemblistes ; trouver pourquoi une fonction scalaire n'est pas
intégrée, la rendre intégrable, puis juger si l'intégration suffit.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure quelques secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, au niveau de
  compatibilité 170, puis crée trois objets écrits comme on les trouve souvent en production :
  - `Enrollment.CashRunningTotal @Year`, l'encaissement de chaque jour d'une année et son cumul
    depuis le 1er janvier ;
  - `Course.GetFillStatus @SessionId`, une fonction scalaire qui rend l'état de remplissage d'une
    session (`NO ROOM`, `FULL`, `ALMOST FULL`, `OPEN`) d'après les places de sa salle et les
    inscriptions ;
  - `Course.SessionList @Start, @End`, la liste des sessions d'une période, qui appelle la
    fonction pour chaque session.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime à la fin ce que
  `1-start.sql` a créé.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`).

Laissez `SET STATISTICS IO` et `TIME` désactivés autour de `Enrollment.CashRunningTotal` : ils
écrivent un message par instruction de la boucle. Lisez les lectures et le temps processeur dans
`sys.dm_exec_procedure_stats` après l'appel (`last_logical_reads`, `last_worker_time`).

## Partie 1. La trésorerie de l'année

```sql
EXEC Enrollment.CashRunningTotal @Year = 2025;
```

1. Combien de lectures et de temps processeur coûte l'appel ?
2. Quelle instruction de la procédure coûte presque tout ? Combien de fois s'exécute-t-elle, et
   pourquoi lit-elle autant ?
3. Réécrivez la procédure sans boucle ni curseur, en gardant son nom, son paramètre et son
   résultat. Deux outils suffisent : une fonction qui produit une suite de nombres (SQL Server
   2022, niveau 160) et une fonction de fenêtrage.
4. Vérifiez que les 365 lignes sont identiques à celles d'avant, puis mesurez.

## Partie 2. L'état de remplissage des sessions

```sql
EXEC Course.SessionList @Start = '20110101', @End = '20271231';
```

1. Mesurez la liste. Combien de fois la fonction est-elle appelée, et combien de lectures
   fait-elle ?
2. La base est au niveau 170 et l'intégration des fonctions scalaires n'y est pas désactivée.
   Que dit `sys.sql_modules` de `Course.GetFillStatus` ?
3. Relisez la liste des constructions qu'une fonction intégrable admet, dans la documentation de
   l'intégration des fonctions scalaires. La cause diffère de celle de la démonstration du
   module. Laquelle est-ce ?
4. Réécrivez la fonction pour qu'elle devienne intégrable, sans changer son nom, sa signature ni
   ses règles. Vérifiez `is_inlineable`, puis mesurez la liste de nouveau et comparez son
   résultat à celui d'avant.
5. Regardez le plan réel de la liste avec la fonction intégrée. Qu'est-ce qui reste fait une fois
   par session ? Écrivez la liste sans fonction et mesurez-la.

Rendez à la base son état de départ en jouant la fin du corrigé, ou en relançant le
`00-setup.sql` du module suivant.
