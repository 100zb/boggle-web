# BDD Boggle (module L2)

PostgreSQL 16, extension `pgcrypto` (installee dans un schema `crypto` a part).

```
createdb boggle
psql -d boggle -f install.sql          # schema + fonctions + donnees de test + role du site
psql -d boggle -f 04_tests_erreurs.sql # 30 cas refuses, chacun doit afficher une ERROR
psql -d boggle -f 05_requetes.sql      # requetes de demo (a lancer apres 04)
```

En production (Neon), on installe `01_schema.sql`, `02_fonctions.sql` et `droits.sql`, **sans** `03_donnees.sql` (pas de comptes de test avec des mots de passe connus), puis `ALTER ROLE boggle_web PASSWORD '...'`.

| Fichier | Contenu |
|---|---|
| `01_schema.sql` | tables, contraintes, index |
| `02_fonctions.sql` | triggers, fonctions, procedures, vues |
| `03_donnees.sql` | jeu de test |
| `droits.sql` | role `boggle_web` et ses droits |
| `04_tests_erreurs.sql` | ce qui doit etre refuse |
| `05_requetes.sql` | ce qui doit marcher |

## Tables

| Table | Role |
|---|---|
| `joueur` | pseudo, hash du mot de passe, email chiffre, derniere connexion |
| `profil` | infos facultatives (nom et prenom chiffres, avatar, bio), prive par defaut |
| `salon` | reglages de la partie : taille, duree, nb max de joueurs |
| `membre_salon` | qui attend dans le salon avant le lancement |
| `partie` | grille en JSONB, statut, resultat final en JSONB |
| `participation` | joueur + partie + score (association n-n) |
| `mot_propose` | chaque mot propose, valide ou non, avec ses points |
| `message` | chat du salon |
| `jeton_reinit` | mot de passe oublie : hash du jeton, expiration, usage unique |
| `tentative_connexion` | echecs de connexion (pseudo tape, ip hachee), pour bloquer le brute force |

## Deroulement cote PHP

Le site se connecte avec le role `boggle_web`.

1. inscription : `SELECT inscrire(pseudo, password_hash(...), email, CLE)` (email vide accepte)
2. connexion : `SELECT connexion_bloquee(pseudo, ip_hash)`, puis `SELECT * FROM infos_connexion(pseudo)`, puis `password_verify` en PHP ; si echec `CALL noter_echec(pseudo, ip_hash)`, si reussite `CALL effacer_echecs(pseudo)` et `CALL enregistrer_connexion(id)`
3. mot de passe oublie : `SELECT * FROM joueur_par_email(email, CLE)` ; si trouve, jeton = `random_bytes(32)`, `SELECT creer_jeton(id, sha256(jeton))` et envoi du lien par email ; puis `SELECT jeton_valide(sha256(jeton))` pour afficher le formulaire et `CALL reinitialiser_mdp(sha256(jeton), password_hash(...))`
4. a chaque chargement de page : `SELECT terminer_parties_expirees()`
5. salon : `INSERT INTO salon`, `INSERT INTO membre_salon`, `INSERT INTO message`
6. lancement : `exec(grid_build)` puis `exec(solve)`, puis `SELECT lancer_partie(salon, cases, solutions)`
7. chaque mot : `INSERT INTO mot_propose (joueur_id, partie_id, mot) RETURNING valide, points`. C'est la BDD qui dit si le mot est bon, le PHP n'appelle plus `dictionnary_lookup` ni `grid_path`
8. fin du chrono : `SELECT terminer_partie(id)`
9. historique : `SELECT * FROM historique_joueur(id)`, `SELECT * FROM afficher_partie(id)`
10. profil : `CALL modifier_profil(...)`, `CALL modifier_identite(...)`, `SELECT * FROM profil_prive(id, CLE)`

Cote admin, une fois par nuit (cron) : `psql -d boggle -c "CALL purger_donnees()"`.

`grid_path` reste utile seulement pour surligner le chemin d'un mot dans la grille. `grille_texte(id)` redonne `4 4 G A I R ...` pour l'appeler.

## Choix a defendre

**Relationnel pendant la partie, JSONB pour l'archive.**
Pendant le jeu, les cles etrangeres et les triggers garantissent l'integrite : un joueur ne peut proposer un mot que s'il participe, une seule fois par mot, et seulement tant que la partie est en cours et que le temps n'est pas ecoule. Ajouter une ligne a chaque mot est plus simple que reecrire un gros JSON.
A la fin, `terminer_partie` fige tout dans `partie.resultat` (joueurs, scores, rangs, mots, gagnant, mots rates). C'est la trace de la partie demandee par la consigne, et c'est ce que lisent `afficher_partie` et `historique_joueur` avec les operateurs JSON.

**Grille en tableau JSON.** `QU` est une seule case du tableau, donc la taille de la grille est juste la longueur du tableau. Le CHECK verifie que lignes x colonnes = nombre de cases.

**Anti-triche.**
- Au lancement, `solve` donne toutes les solutions de la grille, stockees dans `grille->'solutions'`.
- Le trigger `avant_mot` calcule lui-meme `valide` avec l'operateur JSON `?` (le mot est-il dans le tableau ?). Il calcule aussi les points, et il met `date_proposition` a `NOW()`.
- Meme si le PHP envoie `valide = TRUE`, `points = 11` ou une fausse date, ces valeurs sont ecrasees. En plus, le role du site n'a pas le droit d'ecrire dans ces colonnes.
- Effet de bord : un seul `exec()` par partie (`solve`) au lieu de deux par mot.

**Index.**
- GIN `jsonb_path_ops` sur `resultat` sert `@>` (les parties d'un joueur).
- GIN sur `grille->'solutions'` sert `?` et `?|` (les grilles qui contiennent un mot).
- btree sur des expressions (gagnant, taille) pour filtrer et trier.
- `EXPLAIN` dans `05_requetes.sql` montre que les index sont utilises.

**Stats calculees, pas stockees.** `stats_joueur` et la vue `classement` recalculent tout, ce qui evite des valeurs incoherentes. Seul le score d'une participation est mis a jour par trigger, parce qu'on l'affiche en direct pendant la partie.

**Affichage avec un SELECT.** Une `PROCEDURE` PostgreSQL s'appelle avec `CALL` et ne renvoie pas de lignes. C'est pour ca que `afficher_partie` est une fonction `RETURNS TABLE`. Les vraies procedures du projet sont `supprimer_joueur`, `modifier_identite`, `modifier_profil`, `enregistrer_connexion`, `noter_echec`, `effacer_echecs`, `reinitialiser_mdp` et `purger_donnees`.

**Parties abandonnees.** Si tout le monde ferme l'onglet, personne n'appelle `terminer_partie` et le salon reste bloque. `terminer_parties_expirees()` termine toutes les parties dont le chrono est fini. La date de fin enregistree est la fin du chrono, pas l'heure du nettoyage. Pas besoin de cron : le PHP l'appelle a chaque page, et ca ne coute rien quand il n'y a rien a faire.

**Verrous (concurrence).**
- Avant, `verif_salon` faisait `COUNT` puis `INSERT`. Deux joueurs qui arrivent en meme temps comptent tous les deux 1 place libre, et le salon depasse sa limite.
- Maintenant, `verif_salon` et `lancer_partie` commencent par `SELECT ... FROM salon WHERE id = ... FOR UPDATE`. La 2e transaction attend que la 1re ait fini, puis voit le salon plein ou deja lance.
- `terminer_partie` verrouille aussi la partie, pour eviter qu'elle soit terminee deux fois.
- `terminer_parties_expirees` utilise `SKIP LOCKED` : si une autre page est deja en train de terminer une partie, on la saute au lieu d'attendre.
- `reinitialiser_mdp` verrouille le jeton : deux envois du formulaire en meme temps n'utilisent pas deux fois le meme lien.
- Teste avec deux sessions `psql` en meme temps : le 2e joueur recoit « salon plein », le 2e clic sur « Lancer » recoit « pas en attente », et une seule partie est creee.
- Pour le montrer a l'oral, ouvrir deux terminaux `psql`. Dans le 1er : `BEGIN; INSERT INTO membre_salon ...;`, sans valider. Dans le 2e : le meme `INSERT`, qui reste bloque. Faire `COMMIT` dans le 1er : le 2e recoit l'erreur.

**Moindre privilege (`droits.sql`).**
- Le site se connecte avec `boggle_web`, jamais avec le proprietaire de la base. Si quelqu'un trouve une injection SQL dans le PHP, il ne peut faire que ce que ce role a le droit de faire.
- Lecture : les tables de jeu (salon, partie, scores, mots, messages), qui ne contiennent pas de donnees perso. Sur `joueur`, seulement les colonnes `id`, `pseudo` et `supprime` : pas d'email chiffre ni de hash de mot de passe.
- Aucun droit direct sur `jeton_reinit` et `tentative_connexion` : on ne peut ni lire les jetons, ni s'en fabriquer un, ni effacer ses echecs de connexion.
- Ecriture directe : seulement certaines colonnes de `salon`, `membre_salon`, `message` et `mot_propose` (pas `valide`, `points` ni `statut`). Les triggers verifient le reste.
- Tout le reste passe par les fonctions, qui sont `SECURITY DEFINER` : elles s'executent avec les droits de leur proprietaire. Le site peut donc mettre a jour un score via le trigger, mais pas avec un `UPDATE participation`.
- `SET search_path = public, crypto` sur ces fonctions empeche quelqu'un de les detourner avec une fonction du meme nom placee dans un autre schema.
- `REVOKE EXECUTE ... FROM PUBLIC` : par defaut, PostgreSQL laisse tout le monde executer toutes les fonctions. Le site n'a que les fonctions listees. `purger_donnees` n'en fait pas partie, elle est reservee a l'admin.
- `pgcrypto` est dans un schema `crypto` sur lequel le site n'a aucun droit. Sur Neon, les fonctions de `pgcrypto` appartiennent a l'admin du cloud, donc notre `REVOKE` ne les touche pas : on l'a vu en testant (`boggle_web` pouvait appeler `hmac`). Fermer le schema marche partout.
- Le mot de passe du role (`a_changer`) est remplace a l'installation, et il va dans les variables d'environnement du site comme la cle de chiffrement.

**Crypto.**
- Le mot de passe est hache en PHP (`password_hash`), jamais en clair, meme pas dans la requete.
- L'email, le nom et le prenom sont chiffres avec `pgp_sym_encrypt`. Si quelqu'un vole un dump de la base, il ne lit rien.
- La cle est dans la config PHP, jamais dans la base.
- Le meme email chiffre deux fois donne deux resultats differents, donc on ne peut pas mettre `UNIQUE` dessus. On stocke donc a cote un `hmac` de l'email (avec la meme cle) qui est `UNIQUE`.
- Pourquoi un hmac et pas un simple sha256 : un sha256 se casse en testant une liste d'emails, le hmac ne se casse pas sans la cle.
- Un email vide (`''` ou des espaces, ce qu'envoie un formulaire vide) est transforme en `NULL`. Sinon tous les joueurs sans email auraient le meme hmac et seraient refuses par le `UNIQUE`.

**Securite des comptes.**
- Mot de passe oublie : l'email etant chiffre, `joueur_par_email` le retrouve par son hmac. Le jeton envoye par email (`random_bytes(32)` en PHP) n'est jamais stocke : seulement son sha256. Si la base fuite, les liens en cours sont inutilisables. Un sha256 simple suffit ici parce que le jeton est aleatoire sur 256 bits (impossible a deviner, contrairement a un email).
- Le jeton vaut 30 minutes, ne sert qu'une fois, et demander un nouveau lien annule les anciens. Un 2e lien demande moins de 2 minutes apres est ignore (pas de spam d'emails).
- Changer son mot de passe remet a zero les echecs de connexion.
- Limitation des tentatives : 5 echecs sur un pseudo ou 20 depuis une ip en 15 minutes bloquent la connexion. C'est en base et pas en session, parce qu'un attaquant vide ses cookies a chaque essai.
- Un echec est note meme si le pseudo n'existe pas, sinon le blocage dirait quels pseudos existent.
- L'ip est une donnee perso : le PHP l'envoie hachee avec la cle, et les tentatives sont effacees au bout d'1 jour.

**Pseudo.**
- L'index `UNIQUE` sur `LOWER(pseudo)` empeche `Ali` d'exister a cote de `ali` (usurpation).
- Le CHECK `^[A-Za-z0-9_]{3,30}$` refuse les espaces et les caracteres qui se ressemblent (un `a` cyrillique par exemple).
- La connexion par `infos_connexion` ignore la casse.

**RGPD.**
- Minimisation : seuls le pseudo et le mot de passe sont obligatoires. L'email et le profil sont facultatifs. Sans email, pas de recuperation du mot de passe (le site le dit a l'inscription).
- Protection par defaut (article 25) : le profil est prive tant que le joueur ne choisit pas de le rendre public (`est_public DEFAULT FALSE`).
- `date_consentement` est enregistree a l'inscription.
- Droit d'acces : `export_donnees(id, cle)` renvoie toutes les donnees du joueur en JSON.
- Droit a l'effacement : `CALL supprimer_joueur(id)` anonymise au lieu de supprimer. Le pseudo, l'email, le mot de passe, le profil, ses jetons et ses messages sont effaces, y compris le pseudo dans les resultats JSON. Les scores restent, donc l'historique des autres joueurs n'est pas casse.
- Le profil prive n'apparait pas dans la vue `profil_public`, et l'email n'y apparait jamais.

**Duree de conservation.**
- `derniere_connexion` est mise a jour a chaque connexion. A l'inscription, elle vaut la date d'inscription, donc un compte jamais utilise finit aussi par etre purge.
- Comptes : anonymises apres **2 ans** sans connexion. C'est la duree que la CNIL juge proportionnee pour supprimer un compte inactif. Un compte de jeu gratuit n'a aucune raison d'etre garde plus longtemps.
- Messages du chat : effaces apres **1 an**. Le chat ne sert que pendant la partie, mais on garde un peu d'historique pour pouvoir traiter un signalement (insulte, harcelement).
- Jetons expires ou utilises, tentatives de connexion de plus d'1 jour : effaces.
- `CALL purger_donnees()` applique ces regles. Les durees des comptes et messages sont des parametres, par exemple `CALL purger_donnees('3 years', '6 months')`.
- Amelioration possible : prevenir le joueur par email un mois avant, comme le recommande la CNIL. C'est au PHP de l'envoyer.

## Lien avec le moteur C

Regle de score identique a `score.c` (`points_mot`) : 3-4 lettres = 1, 5 = 2, 6 = 3, 7 = 5, 8+ = 11. `QU` compte pour 2 lettres.
Un mot est valide s'il est dans la liste donnee par `solve` au lancement. C'est la meme chose que `dictionnary_lookup` + `grid_path`, puisque `solve` cherche justement les mots du dictionnaire qui ont un chemin dans la grille.

Les solutions dans `03_donnees.sql` ont ete calculees avec `dico.txt` (221 et 412 mots).

## Installation testee

- PostgreSQL 16 en local : `install.sql` sans erreur, 30/30 refus dans `04`, 0 erreur dans `05`.
- Neon (PostgreSQL 16.16, 23/11/2026) : `pgcrypto` disponible, `CREATE ROLE` autorise pour le proprietaire. Verifie en `boggle_web` : pas d'acces a `mdp_hash`, a `jeton_reinit` ni a `crypto.hmac` ; inscription et jeton fonctionnent.

## A demander a M. Louvet

- `pgcrypto` est-il installe sur le serveur de l'IUT ? (`CREATE EXTENSION pgcrypto` necessite parfois un admin)
- A-t-on le droit de creer un role (`CREATE ROLE` demande le droit `CREATEROLE`) ? Sinon, `droits.sql` echoue mais le reste est deja installe.
