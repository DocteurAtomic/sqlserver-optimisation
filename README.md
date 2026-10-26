# SQL Server, l'optimisation

Labo, démonstrations et exercices du cours en ligne
[« SQL Server, l'optimisation »](https://www.docteuratomic.com) de Docteur Atomic.

## Le labo

Il faut Docker (ou Podman) avec `compose`, `curl` et un shell bash (sous Windows, WSL ou
Git Bash), et environ 8 Go de mémoire libre.

    git clone https://github.com/DocteurAtomic/sqlserver-optimisation.git
    cd sqlserver-optimisation
    ./setup/install.sh

Le script télécharge les sauvegardes de `PachadataTraining` (626 Mo) et de `LuminaQuant`
(964 Mo), vérifie leurs sommes SHA-256, démarre SQL Server 2025 Developer dans le conteneur
`sqloptcourse` et restaure les deux bases. Avec Podman :
`COMPOSE="podman compose" ENGINE=podman ./setup/install.sh`.

Le conteneur est limité à 6 Go de mémoire et 4 processeurs : les modules sur la mémoire et
le parallélisme en dépendent. L'Agent SQL Server est actif.

Se connecter : SSMS ou un autre client sur `localhost,14333`, utilisateur `sa`, mot de passe
`Course-2026!lab` (un mot de passe de labo, à ne jamais reprendre ailleurs ;
`MSSQL_SA_PASSWORD` et `SQLPORT` le changent avant le premier démarrage).

## Le contenu

- `demos/module_XX` : les scripts joués dans les vidéos du module, dans l'ordre de leur
  numéro. `00-setup.sql` restaure `PachadataTraining` par `master.dbo.reset_training`, puis
  installe le symptôme du module : son en-tête dit ce qu'il fait. `99-cleanup.sql`, quand il
  existe, rend l'instance à son état d'origine. `charge.sh` lance les sessions d'une charge.
  L'en-tête de chaque script dit où il se joue.
- `exercises/module_XX` : les fichiers de l'exercice du module, corrigé compris.
- `setup/run-scripts.sh` rejoue tous les scripts qui tournent seuls ; l'intégration continue
  le lance à chaque modification.

Les modules `01` à `05` forment le tronc commun, `d1` à `d7` le parcours DBA, `v1` à `v8` le
parcours développeur.

Jouez ces scripts sur le labo, jamais sur un serveur de production : ils dégradent exprès
la base et l'instance.

## Les bases

`PachadataTraining` est la base de démonstration anglaise de Pachadata : un organisme de
formation fictif, ses stages, sessions, inscriptions, factures et sa plateforme
d'e-learning. Les personnes sont fictives. Sa documentation est dans le dépôt
[rudi-bruchez/formations](https://github.com/rudi-bruchez/formations/tree/main/bases-exemples/PachadataTraining).
`LuminaQuant` contient 24 millions de transactions financières fictives. Les sauvegardes ne
sont pas dans ce dépôt, le script les télécharge.

## Licence

Le code est sous licence MIT ([`LICENSE`](LICENSE)).

---

# SQL Server Performance Tuning

Lab, demos and exercises of the Docteur Atomic online course on SQL Server performance
tuning. Run `./setup/install.sh` (Docker or Podman with compose, curl, bash, about 8 GB of
free memory): it downloads the `PachadataTraining` and `LuminaQuant` backups, checks their
SHA-256, starts SQL Server 2025 Developer (6 GB, 4 processors, Agent on) and restores both
databases. `demos/` holds the scripts shown in the videos and `exercises/` the exercise
files, one folder per module; each module's `00-setup.sql` restores the database and
installs the problem the module investigates. The code is released under the MIT license.
