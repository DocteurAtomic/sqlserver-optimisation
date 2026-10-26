# Exercice du module V2

Objectif : couvrir une requête par l'index qu'elle emploie déjà, faire servir un index filtré à
une procédure paramétrée, puis mesurer ce que ces deux index coûtent à l'envoi d'une
newsletter.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure quelques
secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, crée les deux procédures
  du back-office marketing sur lesquelles l'exercice travaille, et donne les requêtes des trois
  parties.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Les index et la procédure qu'il
  modifie restent modifiés ; le `00-setup.sql` du module suivant restaure la base.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M) et
`SET STATISTICS IO ON` avant de lancer chaque requête.

## Partie 1. L'historique d'un contact

La fiche d'un contact, dans le back-office, affiche les e-mails qu'il a reçus, du plus récent
au plus ancien :

```sql
EXEC Marketing.GetContactDeliveries @ContactId = 1234;
```

`Marketing.Delivery` contient quatre millions de livraisons, et un index
`ix_Delivery_ContactId` sur `ContactId` seul.

1. Combien de pages pour 36 lignes ? Quels opérateurs, et lequel coûte ?
2. Que contient la feuille de `ix_Delivery_ContactId`, sans que sa définition le dise ? Écrivez
   une requête sur le contact 1234 qui n'a pas besoin de l'index cluster.
3. Modifiez l'index pour qu'il couvre la procédure, sans créer de deuxième index, et mesurez.

## Partie 2. Les clics d'une campagne

Le rapport d'une newsletter liste les e-mails cliqués :

```sql
EXEC Marketing.GetCampaignDeliveries @CampaignId = 36, @Clicked = 1;
```

1. Combien de pages, et quel opérateur ? Pourquoi l'optimiseur n'emploie-t-il pas
   `ix_Delivery_CampaignId` ?
2. Seuls 6 % des e-mails sont cliqués. Créez un index filtré sur les e-mails cliqués, qui
   couvre la requête. La procédure s'en sert-elle ? Que dit le plan ?
3. Réécrivez la procédure pour qu'elle s'en serve, et mesurez.

## Partie 3. La newsletter d'octobre

La requête de la partie 3, dans `1-start.sql`, enregistre l'envoi de la newsletter d'octobre,
107 994 e-mails, dans une transaction annulée à la fin, et rend le journal écrit.

1. Lancez-la sur la base livrée, avant les parties 1 et 2 (rejouez `1-start.sql` si besoin),
   et relevez le journal et les pages de chaque index (`sys.dm_db_partition_stats`) avant et
   après.
2. Relancez-la avec vos index. Qu'est-ce qui a changé, dans quel index, et pourquoi ?
3. Les pages d'un index reviennent-elles à leur nombre de départ après l'annulation ?
