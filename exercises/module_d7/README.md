# Exercice du module D7

Objectif : appliquer la routine du matin à une autre nuit du serveur de PachaData. Elle a eu
ses propres problèmes, qui ne sont pas ceux de la démonstration. Vous les trouvez avec les
quatre scripts de la routine, vous remontez à leur cause, puis vous corrigez et vous mesurez.

L'exercice se joue sur votre labo, après le module 1 (il lit la base `PachadataDBA`).
`1-start.sql` dure deux à trois minutes. Les deux fenêtres demandent deux sessions de SSMS.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining`, ramène son journal à 128 Mo, prend la photo du
  soir dans `PachadataDBA`, puis crée `Enrollment.GetAttendanceSheet`, la feuille d'émargement
  qu'un formateur imprime chaque matin : les inscrits d'une session. Il joue la soirée (300
  feuilles), puis la nuit. Ne lisez pas ce que fait la nuit avant d'avoir cherché.
- `2a-window-1.sql` et `2b-window-2.sql` font partie de la nuit : lancez le premier dans une
  fenêtre, puis le second dans une autre, à moins de cinq secondes d'intervalle.
- La routine : les scripts `01a-waits-since-yesterday.sql`, `01b-query-store.sql`,
  `01c-system-health.sql` et `01d-file-growth.sql` du dossier `demos/module_d7`, sans
  modification.
- `3-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime la procédure de
  l'exercice ; le `00-setup.sql` suivant restaure la base.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`).

## Partie 1. La routine

1. Lancez les quatre scripts de la routine, dans l'ordre. Pour chacun, notez ce qu'il signale.
2. Quelles attentes de la nuit viennent d'un verrou, et lesquelles d'une croissance de fichier ?
   Le module D2 vous a montré la signature d'une croissance du journal.
3. Le Query Store signale une régression. Quelle requête, combien de lectures par appel avant et
   après, et à quelle minute le plan a-t-il changé ?
4. Qu'a gardé `system_health` ? Pourquoi, cette fois, la session a-t-elle quelque chose à dire ?

## Partie 2. Les causes

1. Le plan de la feuille d'émargement a changé. Ouvrez les deux plans dans le Query Store :
   qu'est-ce qui manque au second ? Retrouvez dans la trace par défaut ce qui est arrivé à la
   table pendant la nuit (le script `02c-the-regression.sql` de la démonstration, étape 3,
   vous donne la forme de la requête ; les événements 46 et 47 sont la création et la
   suppression d'un objet).
2. Le moteur recommande de forcer le plan de la veille. Pourquoi n'est-ce pas la correction ici ?
   Essayez, et lisez ce que le Query Store en dit.
3. Le journal a grossi, et pourtant aucune transaction n'est ouverte ce matin. Quelle instruction
   a écrit ce journal ? Le Query Store garde, par requête, le journal écrit
   (`avg_log_bytes_used`). Comparez l'heure des croissances et la durée de l'instruction.
4. Selon le moment où vous lancez la routine, `log_reuse_wait_desc` dit `NOTHING` ou encore
   `ACTIVE_TRANSACTION`, alors que le `DELETE` est fini. Pourquoi, et qu'est-ce qui la fait changer ?
5. Lisez l'interblocage dans `system_health` : quelle session a été la victime, et sur quelles
   ressources les deux attendaient-elles ?

## Partie 3. Les corrections

1. Remettez ce qui manque à la feuille d'émargement, et mesurez une feuille.
2. Récrivez la purge pour que le journal ne grossisse plus : la base a une procédure pour cela.
   Mesurez-la sur les envois de 2023, et lisez l'occupation du journal après.
3. Qu'est-ce qui empêche les deux programmes de la nuit de s'interbloquer à nouveau ?
