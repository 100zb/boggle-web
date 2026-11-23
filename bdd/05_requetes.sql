-- SAE S3 Boggle - Module L2 - Requetes de demo (apres 04_tests_erreurs.sql)
SET search_path = public, crypto;
\set cle 'cle_de_test'

-- 1. Affichage d'une partie
SELECT * FROM afficher_partie(1);
SELECT * FROM afficher_grille(1);

-- 2. Grille au format du moteur C, pour exec() en PHP
SELECT grille_texte(1);

-- 3. Historique et stats d'un joueur
SELECT * FROM historique_joueur(1);
SELECT * FROM stats_joueur(1);

-- 4. Parties ou un joueur a joue (@>, index GIN)
SELECT id, date_debut FROM partie
WHERE resultat @> '{"joueurs": [{"pseudo": "sarah"}]}';

-- 5. Grilles qui contiennent un mot (?, index GIN)
SELECT id FROM partie WHERE grille->'solutions' ? 'GRAVIER';

-- 6. Grilles qui contiennent au moins un des mots (?|)
SELECT id FROM partie WHERE grille->'solutions' ?| ARRAY['MAIS', 'OUI'];

-- 7. Nombre de victoires (->, ->>)
SELECT resultat->'gagnant'->>'pseudo' AS joueur, COUNT(*) AS victoires
FROM partie
WHERE statut = 'terminee'
GROUP BY 1
ORDER BY victoires DESC;

-- 8. Meilleur score jamais fait (#>>)
SELECT id, resultat #>> '{gagnant,pseudo}' AS joueur, (resultat #>> '{gagnant,score}')::int AS score
FROM partie
WHERE statut = 'terminee'
ORDER BY 3 DESC
LIMIT 1;

-- 9. Mots les plus trouves, en lisant le JSON
SELECT m->>'mot' AS mot, COUNT(*) AS nb
FROM partie p,
     jsonb_array_elements(p.resultat->'joueurs') j,
     jsonb_array_elements(j->'mots') m
WHERE (m->>'valide')::boolean
GROUP BY 1
ORDER BY nb DESC, mot
LIMIT 10;

-- 10. Mots refuses (jsonpath)
SELECT id, jsonb_path_query(resultat, '$.joueurs[*].mots[*] ? (@.valide == false).mot') AS mot_refuse
FROM partie;

-- 11. Part des solutions trouvees par partie
SELECT id,
       jsonb_array_length(grille->'solutions') AS nb_solutions,
       jsonb_array_length(resultat->'mots_rates') AS nb_rates,
       ROUND(100.0 * (1 - jsonb_array_length(resultat->'mots_rates')::numeric / jsonb_array_length(grille->'solutions')), 1) AS pourcentage_trouve
FROM partie
WHERE statut = 'terminee';

-- 12. Les 5 plus longs mots rates d'une partie
SELECT r AS mot_rate
FROM partie, jsonb_array_elements_text(resultat->'mots_rates') r
WHERE id = 1
ORDER BY LENGTH(r) DESC, r
LIMIT 5;

-- 13. Vues
SELECT * FROM profil_public;
SELECT * FROM classement;

-- 14. Crypto : l'email est illisible sans la cle
SELECT id, pseudo, LEFT(encode(email_chiffre, 'hex'), 30) AS email_en_base, email_hash FROM joueur;
SELECT email_joueur(1, :'cle');
SELECT * FROM profil_prive(1, :'cle');
SELECT email_existe('ALI@test.fr', :'cle') AS deja_pris;

-- 15. RGPD : export puis anonymisation de karim
SELECT export_donnees(3, :'cle');
CALL supprimer_joueur(3);
SELECT * FROM afficher_partie(2);
SELECT pseudo, supprime, email_chiffre IS NULL AS email_efface FROM joueur WHERE id = 3;

-- 16. Anti-triche : la BDD decide seule si le mot est valide (operateur ?)
SELECT grille->'solutions' ? 'OUI' AS oui_dans_la_grille, grille->'solutions' ? 'ZZZZZZZZ' AS zzz_dans_la_grille
FROM partie WHERE id = 3;
INSERT INTO mot_propose (joueur_id, partie_id, mot, valide) VALUES (4, 3, 'ZZZZZZZZ', TRUE) RETURNING mot, valide, points;
INSERT INTO mot_propose (joueur_id, partie_id, mot) VALUES (4, 3, 'oui') RETURNING mot, valide, points;
SELECT score FROM participation WHERE joueur_id = 4 AND partie_id = 3;

-- 17. Partie abandonnee : on recule son debut pour simuler un onglet ferme depuis 1 h
UPDATE partie SET date_debut = date_debut - INTERVAL '1 hour' WHERE id = 3;
SELECT terminer_parties_expirees() AS nb_terminees;
SELECT terminer_parties_expirees() AS nb_terminees_2e_appel;
SELECT id, statut, date_fin - date_debut AS duree_reelle FROM partie WHERE id = 3;
SELECT id, statut FROM salon WHERE id = 2;

-- 18. Parcours complet avec le role du site
SET ROLE boggle_web;

-- email vide deux fois : accepte (vide = pas d'email)
SELECT inscrire('tom', '$2y$10$hash_fait_par_password_hash', '', :'cle') AS tom \gset
SELECT inscrire('zoe', '$2y$10$hash_fait_par_password_hash', '   ', :'cle') AS zoe \gset

SELECT * FROM infos_connexion('TOM');
CALL enregistrer_connexion(:tom);

INSERT INTO salon (nom, createur_id, nb_lignes, nb_colonnes, duree, nb_max_joueurs)
VALUES ('Duel', :tom, 2, 2, 60, 2) RETURNING id AS salon \gset
INSERT INTO membre_salon (salon_id, joueur_id) VALUES (:salon, :tom), (:salon, :zoe);
INSERT INTO message (salon_id, joueur_id, contenu) VALUES (:salon, :zoe, 'prete');

SELECT lancer_partie(:salon, 'R I E N', 'NIER REIN RIEN IRE NIE RIE') AS partie \gset
SELECT * FROM afficher_grille(:partie);
INSERT INTO mot_propose (joueur_id, partie_id, mot)
VALUES (:tom, :partie, 'rien'), (:tom, :partie, 'zzz'), (:zoe, :partie, 'nier'), (:zoe, :partie, 'rein')
RETURNING joueur_id, mot, valide, points;
SELECT terminer_partie(:partie) IS NOT NULL AS terminee;
SELECT * FROM afficher_partie(:partie);

CALL modifier_profil(:zoe, NULL, 'Nouvelle joueuse', TRUE);
SELECT pseudo, bio FROM profil_public;

RESET ROLE;
SELECT pseudo, email_chiffre IS NULL AS sans_email, email_hash IS NULL AS sans_hash, derniere_connexion IS NOT NULL AS connexion
FROM joueur WHERE id IN (:tom, :zoe);

-- 19. Duree de conservation : lea ne s'est pas connectee depuis 3 ans, un message a 2 ans
UPDATE joueur SET derniere_connexion = NOW() - INTERVAL '3 years' WHERE pseudo = 'lea';
UPDATE message SET date_envoi = NOW() - INTERVAL '2 years' WHERE id = 1;
CALL purger_donnees();
SELECT id, pseudo, supprime FROM joueur ORDER BY id;
SELECT id, joueur_id, contenu FROM message ORDER BY id;
SELECT partie, joueur, score FROM afficher_partie(3);

-- 20. Les index GIN sont bien utilises
SET enable_seqscan = off;
EXPLAIN SELECT id FROM partie WHERE resultat @> '{"joueurs": [{"id": 1}]}';
EXPLAIN SELECT id FROM partie WHERE grille->'solutions' ? 'GRAVIER';
SET enable_seqscan = on;

-- 21. Securite des comptes, avec le role du site
-- le PHP envoie le sha256 du jeton (ici calcule par psql pour la demo)
SELECT encode(digest('jeton_demo', 'sha256'), 'hex') AS h1, encode(digest('jeton_demo_2', 'sha256'), 'hex') AS h2 \gset
SET ROLE boggle_web;

-- 5 mauvais mots de passe sur ali : ali est bloque, meme depuis une autre ip ; sarah non
CALL noter_echec('ali', 'ip_a');
CALL noter_echec('ALI', 'ip_a');
CALL noter_echec('ali', 'ip_b');
CALL noter_echec('ali', 'ip_b');
CALL noter_echec('ali', 'ip_c');
SELECT connexion_bloquee('Ali', 'ip_d') AS ali_bloque, connexion_bloquee('sarah', 'ip_a') AS sarah_bloquee;

-- mot de passe oublie : on retrouve le joueur par son email (hmac), un email inconnu ne renvoie rien
SELECT * FROM joueur_par_email('ALI@test.fr', :'cle');
SELECT COUNT(*) AS nb FROM joueur_par_email('personne@test.fr', :'cle');

-- un 2e jeton demande tout de suite est refuse (anti-spam)
SELECT creer_jeton(1, :'h1') AS cree, creer_jeton(1, :'h2') AS deuxieme_trop_tot;
SELECT jeton_valide(:'h1') AS avant, jeton_valide(:'h2') AS jeton_refuse;
CALL reinitialiser_mdp(:'h1', '$2y$10$nouveau_hash_fait_par_password_hash');
SELECT jeton_valide(:'h1') AS apres;

-- le changement de mot de passe debloque le compte
SELECT connexion_bloquee('ali', 'ip_d') AS ali_bloque;

RESET ROLE;
SELECT pseudo, mdp_hash FROM joueur WHERE id = 1;
SELECT joueur_id, utilise, date_expiration - date_creation AS validite FROM jeton_reinit;
