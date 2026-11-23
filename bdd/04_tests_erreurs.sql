-- SAE S3 Boggle - Module L2 - Cas qui doivent etre refuses
-- a lancer juste apres install.sql : chaque requete doit afficher une ERROR (30 en tout)
\set ON_ERROR_STOP off
SET search_path = public, crypto;
\set cle 'cle_de_test'

-- 1. salon deja en partie
INSERT INTO membre_salon (salon_id, joueur_id) VALUES (2, 1);

-- 2. mot dans une partie terminee
INSERT INTO mot_propose (joueur_id, partie_id, mot) VALUES (1, 1, 'vague');

-- 3. meme mot deux fois
INSERT INTO mot_propose (joueur_id, partie_id, mot) VALUES (4, 3, 'VAGUE');

-- 4. joueur qui ne participe pas a la partie
INSERT INTO mot_propose (joueur_id, partie_id, mot) VALUES (2, 3, 'oui');

-- 5. salon plein (3 joueurs max)
INSERT INTO membre_salon (salon_id, joueur_id) VALUES (1, 4);

-- 6. grille de la mauvaise taille
SELECT lancer_partie(1, 'A B C', '');

-- 7. email deja utilise (meme en majuscules)
SELECT inscrire('copie', 'x', 'SARAH@test.fr', :'cle');

-- 8. mauvaise cle de dechiffrement
SELECT email_joueur(1, 'mauvaise_cle');

-- 9. partie pas encore terminee
SELECT * FROM afficher_partie(3);

-- 10. pseudo deja pris avec une autre casse
SELECT inscrire('Ali', 'x', NULL, :'cle');

-- 11. pseudo avec un espace (contournerait l'unicite)
SELECT inscrire('ali ', 'x', NULL, :'cle');

-- 12. salon inexistant
SELECT lancer_partie(99, 'A B C D', '');

-- 13. partie inexistante
SELECT terminer_partie(99);

-- 14. partie deja terminee
SELECT terminer_partie(1);

-- 15. joueur inexistant
CALL supprimer_joueur(99);

-- 16. mot propose apres la fin du chrono (on recule le debut de la partie, puis on annule)
BEGIN;
UPDATE partie SET date_debut = date_debut - INTERVAL '1 hour' WHERE id = 3;
INSERT INTO mot_propose (joueur_id, partie_id, mot) VALUES (4, 3, 'oui');
ROLLBACK;

-- 17. un 2e clic sur "Lancer" quand la partie est deja lancee
SELECT lancer_partie(2, 'G A I R R U V E QU E O T A S M J', 'OUI');

-- Mot de passe oublie (le PHP envoie le sha256 du jeton)

-- 18. lien qui n'existe pas
CALL reinitialiser_mdp(encode(digest('jeton_invente', 'sha256'), 'hex'), 'x');

-- 19. lien utilise une 2e fois (usage unique)
BEGIN;
SELECT creer_jeton(2, encode(digest('jeton_sarah', 'sha256'), 'hex'));
CALL reinitialiser_mdp(encode(digest('jeton_sarah', 'sha256'), 'hex'), 'hash_1');
CALL reinitialiser_mdp(encode(digest('jeton_sarah', 'sha256'), 'hex'), 'hash_2');
ROLLBACK;

-- 20. lien expire (on avance l'expiration dans le passe, puis on annule)
BEGIN;
SELECT creer_jeton(2, encode(digest('jeton_vieux', 'sha256'), 'hex'));
UPDATE jeton_reinit SET date_expiration = NOW() - INTERVAL '1 minute';
CALL reinitialiser_mdp(encode(digest('jeton_vieux', 'sha256'), 'hex'), 'x');
ROLLBACK;

-- 21. jeton pour un joueur qui n'existe pas
SELECT creer_jeton(99, encode(digest('jeton_fantome', 'sha256'), 'hex'));

-- Ce que le role du site n'a pas le droit de faire
SET ROLE boggle_web;

-- 22. tricher sur un score
UPDATE participation SET score = 999 WHERE joueur_id = 4;

-- 23. forcer valide a TRUE
INSERT INTO mot_propose (joueur_id, partie_id, mot, valide) VALUES (4, 3, 'ZZZ', TRUE);

-- 24. lire les emails chiffres ou les hash de mot de passe
SELECT email_chiffre, mdp_hash FROM joueur;

-- 25. lancer la purge (reservee a l'admin)
CALL purger_donnees();

-- 26. appeler directement une fonction de pgcrypto (schema crypto ferme au site)
SELECT encode(crypto.hmac('ali@test.fr', 'cle_au_hasard', 'sha256'), 'hex');

-- 27. lire les jetons de reinitialisation
SELECT * FROM jeton_reinit;

-- 28. fabriquer son propre jeton pour le compte d'un autre
INSERT INTO jeton_reinit (joueur_id, jeton_hash, date_expiration) VALUES (1, 'x', NOW() + INTERVAL '1 day');

-- 29. lire les tentatives de connexion
SELECT * FROM tentative_connexion;

-- 30. effacer ses echecs de connexion sans s'etre connecte
DELETE FROM tentative_connexion;

RESET ROLE;
