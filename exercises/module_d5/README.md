# Exercice du module D5

Objectif : appliquer les gestes du module à une autre charge que celle des démonstrations.
L'équipe du e-learning exporte chaque nuit l'activité des stagiaires par un outil qui se
connecte sous `export_user`. Vous isolez cet export dans son propre pool et son propre
groupe, avec des limites décidées d'avance, puis vous mesurez ce que l'export a reçu, connecté
en `sa` puis en `export_user`.

L'exercice change l'instance, comme le module : il crée une connexion, un pool, un groupe et
une fonction classifieur. Jouez-le sur votre labo après le `99-cleanup.sql` du module, qui
laisse le gouverneur désactivé et sans fonction classifieur, `charge.sh` arrêté. Une instance
n'a qu'une fonction classifieur : si `1-start.sql` en montre une, jouez d'abord ce
`99-cleanup.sql`.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining`, lit l'état du gouverneur et le nombre
  d'ordonnanceurs, crée la connexion `export_user` (mot de passe `Lab#Export2026`), qui lit le
  schéma `Elearning`, puis donne le squelette, qui ne s'exécute pas tant que vous n'avez pas
  retiré la ligne `SET NOEXEC ON`.
- `2-solution.sql` est le corrigé des parties 1 et 2, puis l'export de la partie 3 en `sa`.
- `3-export-as-export-user.sql` se joue connecté en `export_user` : l'export, puis une table
  temporaire construite sur toute l'activité.
- `4-solution-measures.sql` est le corrigé de la partie 4, en `sa`.
- `5-cleanup.sql` supprime la fonction, le groupe, le pool et la connexion, et désactive le
  gouverneur.

Lisez les corrigés après avoir cherché. Ouvrez les fichiers dans SSMS, connecté au labo
(`localhost,14333`), ou passez-les à `sqlcmd` dans le conteneur :

```bash
docker exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C < exercises/module_d5/1-start.sql
```

Pour la fenêtre `export_user` dans SSMS : Requête, Connexion, Modifier la connexion,
authentification SQL Server. Avec `sqlcmd`, `-U export_user` à la place de `-U sa`.

## Partie 1. Les objets

1. Créez le pool `ExportPool`, qui peut prendre un processeur de votre labo et pas plus, quelle
   que soit la charge, et au plus 20 % de la mémoire de l'instance. Quel réglage de processeur
   choisissez-vous, et quelle valeur sur votre labo ?
2. Créez le groupe `Export` dans ce pool : requêtes en série, octroi d'au plus 5 % de la
   mémoire du pool par requête, 64 Mo de `tempdb` pour tout le groupe.

## Partie 2. La classification

1. Écrivez la fonction classifieur `dbo.ClassifyExport`, qui envoie `export_user` dans
   `Export` et toute autre session dans `default`, déclarez-la au gouverneur et appliquez la
   configuration. Pourquoi ne pas classer sur `APP_NAME()` ?

## Partie 3. L'export, deux fois

1. Lancez l'export du squelette dans la fenêtre `sa`, puis `3-export-as-export-user.sql` dans
   la fenêtre `export_user`. La seconde partie de ce script construit une table temporaire :
   que se passe-t-il ?

## Partie 4. Les mesures

1. Pour chaque plan de l'export en cache, relevez le dernier degré de parallélisme, le dernier
   octroi, la mémoire utilisée, les pages déversées et le temps de processeur
   (`sys.dm_exec_query_stats`). Qu'est-ce qui distingue les deux exécutions ?
2. Relevez, par groupe, le plus gros octroi, le pic d'espace `tempdb` et les violations de la
   limite (`sys.dm_resource_governor_workload_groups`).

Pour finir, jouez `5-cleanup.sql`.
