# Exercice du module V1

Objectif : réécrire trois prédicats pour qu'ils cherchent dans un index, puis donner à une
table importée les types qui conviennent à ce qu'elle contient, et trouver la conversion que
ce changement de type introduit.

L'exercice se joue sur votre labo, dans une seule session. `1-start.sql` dure une vingtaine de
secondes.

## Les fichiers

- `1-start.sql` restaure `PachadataTraining` telle qu'elle est livrée, charge la table
  `Contact.ContactImport` de la partie 2, et donne les requêtes de la partie 1 et le squelette
  de la partie 2.
- `2-solution.sql` est le corrigé, à lire après avoir cherché. Il supprime à la fin les deux
  tables de la partie 2.

Ouvrez-les dans SSMS, connecté au labo (`localhost,14333`). Activez le plan réel (Ctrl+M) et
`SET STATISTICS IO ON` avant de lancer chaque requête.

## Partie 1. Les codes postaux des prospects

`Contact.ProspectUS` contient un million de prospects, dans un tas. `ZipCode` est un
`varchar(20)`, indexé seul par `nix_prospectus_zipcode`.

```sql
-- 1. Les prospects dont le code postal commence par 100 (Manhattan).
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE LEFT(ZipCode, 3) = '100';

-- 2. Les prospects sans code postal, NULL ou vide.
SELECT COUNT(*) AS WithoutZipCode
FROM Contact.ProspectUS
WHERE COALESCE(ZipCode, '') = '';

-- 3. Les prospects d'un code postal, tel qu'un formulaire l'envoie.
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE ZipCode = 62086;
```

Pour chacune : quel opérateur lit les données, combien de pages sont lues, et pourquoi ?
Réécrivez-la pour qu'elle rende les mêmes lignes en cherchant dans l'index, et mesurez.
Pour la troisième, dites aussi ce que la conversion change au sens de la requête.

## Partie 2. La table importée

`Contact.ContactImport` contient 480 560 contacts, importés par un outil de migration qui a
choisi les types sans regarder les données : `bigint` pour les identifiants, `nvarchar(255)`
pour les chaînes, `nchar` pour le téléphone et le genre, `datetime2(7)` pour la date de
naissance, et la collation d'une installation américaine par défaut,
`SQL_Latin1_General_CP1_CI_AS`. Un index existe sur `Email`.

1. Mesurez ce que chaque colonne contient vraiment : longueur maximale des chaînes, valeurs
   distinctes de `Title` et `Gender`, plus grande valeur des identifiants, partie horaire des
   dates.
2. Créez `Contact.ContactClean`, avec les mêmes colonnes et la même collation, dans les types
   les plus proches de ce contenu, avec sa clé primaire. Copiez-y les lignes, créez l'index
   `nix_contactclean_email` sur `Email`, et comparez les pages des deux tables et de leurs
   index (`sys.dm_db_partition_stats`).
3. L'application cherche un contact par son adresse, et son pilote envoie la chaîne en
   `nvarchar(4000)`. Lancez la recherche du squelette sur les deux tables, avec l'adresse
   `a.aba@institut-trefois.fr`. Comparez les lectures et les plans. Que s'est-il passé, et où
   faut-il le corriger ?
