# Exercice du module V5

Objectif : sur une autre procédure que celle des démonstrations, mesurer la sensibilité aux
paramètres dans les deux ordres d'appel, comprendre pourquoi l'optimisation des plans sensibles
aux paramètres (PSP) ne s'applique pas, et choisir un remède en le mesurant.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure une dizaine de
secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, au niveau de
  compatibilité 170 (la PSP y est active, c'est sa valeur par défaut), crée l'index
  `nix_activity_moduleid` sur `Elearning.Activity (ModuleId)` et la procédure
  `Elearning.GetModuleActivity`, puis montre les modules les plus et les moins actifs. Il donne
  les requêtes de chaque partie, en commentaire.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Sa partie 2 crée une session
  d'événements étendus, `psp_skipped`, et la supprime ; sa fin supprime l'index et la procédure
  créés par `1-start.sql`.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M) et
`SET STATISTICS IO, TIME ON`. SSMS ouvre ses sessions en `ARITHABORT ON` : tous vos appels
partagent donc les mêmes plans, ce qui suffit ici.

La procédure rend l'activité d'un module de la formation à distance, par type d'événement et
par appareil, pour le tableau de bord des formateurs :

```sql
CREATE OR ALTER PROCEDURE Elearning.GetModuleActivity @ModuleId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.EventTypeCode, a.Device, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
    FROM Elearning.Activity AS a
    WHERE a.ModuleId = @ModuleId
    GROUP BY a.EventTypeCode, a.Device;
END;
```

`Elearning.Activity` contient 7,8 millions de lignes, dans un tas. Le module 808 compte 49 887
événements, le module 992 en compte 170.

## Les questions

1. Appelez la procédure pour le module 992 puis pour le module 808, après un `sp_recompile` ;
   puis dans l'ordre inverse, après un autre `sp_recompile`. Relevez pour chaque appel les pages
   lues, le temps processeur et la forme du plan. Lequel des deux ordres coûte le plus cher, et à
   qui ?
2. Pour quelle valeur le plan en cache a-t-il été compilé ? Lisez-la dans le plan.
3. La base est au niveau 170, la PSP est active. Combien d'entrées le cache contient-il pour la
   requête de la procédure, et de quel type ? Que manque-t-il, par rapport à la vidéo 5 ?
4. Cherchez pourquoi. L'événement étendu
   `parameter_sensitive_plan_optimization_skipped_reason` se déclenche à la compilation quand la
   PSP écarte une requête ; `query_with_parameter_sensitivity` se déclenche quand elle la retient,
   avec l'asymétrie mesurée. Comparez avec `Report.RecipientsByCampaign`.
5. Choisissez un remède écrit dans le code et mesurez-le sur les mêmes appels qu'à la question 1.
   Comparez au moins deux remèdes.
