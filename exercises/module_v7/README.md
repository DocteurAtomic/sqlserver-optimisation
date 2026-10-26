# Exercice du module V7

Objectif : appliquer les gestes du module à d'autres tables. Trouver le seuil d'escalade d'une
table et ce que protège un verrou de plage ; trouver un blocage puis le lever par RCSI ; rendre
sûre une numérotation que deux sessions se disputent.

L'exercice se joue sur votre labo. `1-start.sql` dure quelques secondes ; les parties 2 et 3
demandent deux fenêtres de requête, et une troisième pour observer.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, au niveau de
  compatibilité 170, avec RCSI actif, puis crée `Enrollment.AddInvoiceLine`, la procédure qui
  ajoute une ligne à une facture. Il affiche la facture `FA2026-007300` et le nombre de sessions
  du catalogue.
- `2-windows.sql` contient les scènes des parties 2 et 3 : chaque bloc `window A` ou `window B`
  se colle dans sa propre fenêtre.
- `3-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime à la fin la procédure
  et remet RCSI, comme dans la base livrée.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`).

## Partie 1. L'escalade et les verrous de plage

1. Sur `Course.Session`, modifiez `Price` sur un nombre croissant de lignes
   (`UPDATE TOP (@rows)`), chaque fois dans une transaction annulée, et comptez dans
   `sys.dm_tran_locks` les verrous de clé, de page et le verrou `X` de table. À quel nombre de
   lignes l'escalade se produit-elle ? Combien de verrous la session tenait-elle juste avant ?
2. Le nombre de lignes diffère de celui de `Enrollment.Invoice` (6 115 dans la vidéo 1).
   Pourquoi ?
3. En `SERIALIZABLE`, comptez les verrous qui restent après `WHERE Price > 3000`, puis après
   `WHERE StartDate >= '20261101' AND StartDate < '20261201'`. Qu'est-ce que chaque lecture
   empêche ? D'où vient la différence ?

## Partie 2. Le planificateur et les commerciaux

1. Désactivez RCSI, depuis `master` :
   `ALTER DATABASE PachadataTraining SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;`
2. Lancez la fenêtre A (le planificateur, transaction laissée ouverte), puis la fenêtre B (les
   commerciaux). Depuis une troisième fenêtre, trouvez qui bloque la fenêtre B et ce qu'il a
   envoyé.
3. Annulez la fenêtre A (`ROLLBACK`), réactivez RCSI, rejouez. Que rend la fenêtre B, en combien
   de temps, et quel prix lit-elle ?

## Partie 3. Les lignes de facture

1. Lancez la fenêtre A, puis la fenêtre B une seconde après. Que se passe-t-il, avec RCSI comme
   sans ?
2. Corrigez `Enrollment.AddInvoiceLine` pour que deux ajouts sur la même facture se suivent sans
   erreur, sans faire attendre les ajouts sur d'autres factures. Rejouez la scène.
3. Pourquoi ni une séquence ni `SERIALIZABLE` ne conviennent-ils ?

Rendez à la base son état de départ en jouant la fin du corrigé, ou en relançant le
`00-setup.sql` du module suivant.
