# Exercice du module 5

Objectif : appliquer les deux gestes du module à d'autres objets que ceux des
démonstrations. Dans la première partie, capturer une charge par deux sessions d'événements
étendus et compter ses requêtes par forme ; dans la seconde, provoquer un verrou mortel sur
deux autres tables, le relire dans `system_health` et le corriger.

L'exercice se joue sur votre labo. Il crée des sessions d'événements étendus et les
supprime à la fin ; les fichiers `.xel` restent dans le dossier des journaux de l'instance
(`/var/opt/mssql/log` dans le conteneur).

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, et crée la procédure
  `dbo.ExerciseWorkload`, la charge de la première partie.
- `2-solution-capture.sql` est le corrigé de la première partie.
- `3a-window-1.sql` et `3b-window-2.sql` sont les deux transactions de la seconde partie, à
  lancer dans deux fenêtres de SSMS.
- `4-solution-deadlock.sql` est le corrigé de la seconde partie, à lancer dans une troisième
  fenêtre.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Lisez les corrigés après avoir
cherché.

## Partie 1. Les requêtes d'une charge

`dbo.ExerciseWorkload` envoie trois sortes de requêtes : 300 recherches d'un contact par son
identifiant, dont le texte est construit par concaténation ; 100 recherches par nom, avec un
paramètre ; trois rapports qui lisent des tables entières.

1. Créez une session qui écrit dans un fichier `.xel` les instructions de la base qui durent
   plus de 100 ms, avec l'action `sqlserver.query_hash_signed`. Quels événements faut-il
   écouter pour voir les instructions de la procédure, et pas seulement l'appel ?
2. Créez une seconde session qui compte les exécutions par `query_hash_signed`, dans une
   cible `histogram`, et qui garde les événements eux-mêmes dans un `ring_buffer`. Comment
   écarter les instructions de contrôle (`SET`, `WHILE`) ?
3. Démarrez les deux sessions, exécutez `dbo.ExerciseWorkload`, puis lisez le fichier.
   Quelles instructions dépassent 100 ms, et laquelle lit le plus de pages ? Quelle durée
   donne l'appel de la procédure lui-même ?
4. Lisez l'histogramme. Quelle forme de requête est la plus fréquente ?
5. Regroupez les événements du `ring_buffer` par texte, puis par `query_hash`. Pourquoi la
   requête la plus fréquente est-elle invisible dans le premier regroupement ?
6. Arrêtez les sessions. Que reste-t-il du fichier, de l'histogramme et du `ring_buffer` ?

## Partie 2. Un verrou mortel entre une facture et son paiement

Les deux transactions modifient la facture `FA2026-006089` et son paiement `106875`, dans
l'ordre inverse l'une de l'autre, avec une pause de cinq secondes entre les deux `UPDATE`.

1. Lancez `3a-window-1.sql` dans une fenêtre, puis `3b-window-2.sql` dans une autre dans les
   cinq secondes. Que reçoit chacune ?
2. Retrouvez le verrou mortel dans les fichiers de `system_health`. Quel processus a été
   choisi comme victime, et pourquoi celui-là ? Comparez leur `logused`.
3. Quelles ressources sont en jeu ? Pour chacune, quel index, quel mode de verrou tenu, quel
   mode demandé, et par qui ?
4. Le graphe peut mettre jusqu'à deux minutes à arriver dans le fichier. D'où vient ce délai,
   et comment le raccourcir pour votre lecture ?
5. Corrigez l'ordre d'accès de la fenêtre 2, rejouez les deux fenêtres, et vérifiez que
   `system_health` ne reçoit pas de nouveau verrou mortel. Combien de temps la fenêtre 2
   attend-elle ?
