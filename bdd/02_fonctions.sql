-- SAE S3 Boggle - Module L2 - Fonctions, triggers, vues
-- SECURITY DEFINER : la fonction tourne avec les droits de son proprietaire,
-- search_path = public, crypto : seulement nos schemas (pgcrypto est dans crypto),
-- le role du site (boggle_web) n'a besoin que du droit EXECUTE (voir droits.sql)

----------------------------------------------------------------
-- Score (meme regle que score.c, QU compte pour 2 lettres)
----------------------------------------------------------------
CREATE OR REPLACE FUNCTION points_mot(m VARCHAR) RETURNS INT AS $$
DECLARE
    n INT := LENGTH(m);
BEGIN
    IF n < 3 THEN RETURN 0;
    ELSIF n <= 4 THEN RETURN 1;
    ELSIF n = 5 THEN RETURN 2;
    ELSIF n = 6 THEN RETURN 3;
    ELSIF n = 7 THEN RETURN 5;
    ELSE RETURN 11;
    END IF;
END;
$$ LANGUAGE plpgsql;


----------------------------------------------------------------
-- Triggers
----------------------------------------------------------------

-- avant un mot : partie en cours, temps pas depasse,
-- la BDD decide elle-meme si le mot est valide (anti-triche)
CREATE OR REPLACE FUNCTION avant_mot() RETURNS TRIGGER AS $$
DECLARE
    v_statut VARCHAR;
    v_fin TIMESTAMP;
    v_grille JSONB;
BEGIN
    SELECT p.statut, p.date_debut + s.duree * INTERVAL '1 second', p.grille
    INTO v_statut, v_fin, v_grille
    FROM partie p JOIN salon s ON s.id = p.salon_id
    WHERE p.id = NEW.partie_id;

    IF v_statut <> 'en_cours' THEN
        RAISE EXCEPTION 'La partie % est terminee', NEW.partie_id;
    END IF;

    NEW.date_proposition := NOW();
    IF NEW.date_proposition > v_fin THEN
        RAISE EXCEPTION 'Temps ecoule pour la partie %', NEW.partie_id;
    END IF;

    NEW.mot := UPPER(TRIM(NEW.mot));
    NEW.valide := (v_grille->'solutions') ? NEW.mot;
    IF NEW.valide THEN
        NEW.points := points_mot(NEW.mot);
    ELSE
        NEW.points := 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;

CREATE TRIGGER trg_avant_mot
BEFORE INSERT ON mot_propose
FOR EACH ROW EXECUTE FUNCTION avant_mot();


-- apres un mot : on ajoute les points au score du joueur
CREATE OR REPLACE FUNCTION maj_score() RETURNS TRIGGER AS $$
BEGIN
    UPDATE participation
    SET score = score + NEW.points
    WHERE joueur_id = NEW.joueur_id AND partie_id = NEW.partie_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;

CREATE TRIGGER trg_maj_score
AFTER INSERT ON mot_propose
FOR EACH ROW EXECUTE FUNCTION maj_score();


-- entree dans un salon : salon en attente et pas plein
-- FOR UPDATE : deux joueurs qui arrivent en meme temps passent l'un apres l'autre
CREATE OR REPLACE FUNCTION verif_salon() RETURNS TRIGGER AS $$
DECLARE
    v_statut VARCHAR;
    v_max INT;
    v_nb INT;
BEGIN
    SELECT statut, nb_max_joueurs INTO v_statut, v_max
    FROM salon WHERE id = NEW.salon_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Salon % introuvable', NEW.salon_id;
    END IF;
    IF v_statut <> 'attente' THEN
        RAISE EXCEPTION 'Le salon % n''accepte plus de joueurs', NEW.salon_id;
    END IF;

    SELECT COUNT(*) INTO v_nb FROM membre_salon WHERE salon_id = NEW.salon_id;
    IF v_nb >= v_max THEN
        RAISE EXCEPTION 'Le salon est plein (% joueurs max)', v_max;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;

CREATE TRIGGER trg_verif_salon
BEFORE INSERT ON membre_salon
FOR EACH ROW EXECUTE FUNCTION verif_salon();


----------------------------------------------------------------
-- Deroulement d'une partie
----------------------------------------------------------------

-- p_cases : sortie de grid_build    ex 'G A I R R U V E QU E O T A S M J'
-- p_solutions : sortie de solve     ex 'GRAVIER OUI RUE ...'
CREATE OR REPLACE FUNCTION lancer_partie(p_salon INT, p_cases TEXT, p_solutions TEXT)
RETURNS INT AS $$
DECLARE
    v_salon salon%ROWTYPE;
    v_cases TEXT[];
    v_id INT;
BEGIN
    -- un 2e clic sur "Lancer" attend ici, puis voit le salon en_cours
    SELECT * INTO v_salon FROM salon WHERE id = p_salon FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Salon % introuvable', p_salon;
    END IF;
    IF v_salon.statut <> 'attente' THEN
        RAISE EXCEPTION 'Le salon % n''est pas en attente', p_salon;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM membre_salon WHERE salon_id = p_salon) THEN
        RAISE EXCEPTION 'Aucun joueur dans le salon %', p_salon;
    END IF;

    v_cases := string_to_array(UPPER(TRIM(p_cases)), ' ');
    IF array_length(v_cases, 1) IS DISTINCT FROM v_salon.nb_lignes * v_salon.nb_colonnes THEN
        RAISE EXCEPTION 'La grille ne fait pas % x %', v_salon.nb_lignes, v_salon.nb_colonnes;
    END IF;

    INSERT INTO partie (salon_id, grille)
    VALUES (p_salon, jsonb_build_object(
        'lignes', v_salon.nb_lignes,
        'colonnes', v_salon.nb_colonnes,
        'cases', to_jsonb(v_cases),
        'solutions', to_jsonb(string_to_array(UPPER(TRIM(p_solutions)), ' '))))
    RETURNING id INTO v_id;

    INSERT INTO participation (joueur_id, partie_id)
    SELECT joueur_id, v_id FROM membre_salon WHERE salon_id = p_salon;

    UPDATE salon SET statut = 'en_cours' WHERE id = p_salon;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- redonne la grille au format du moteur C (pour exec() en PHP)
-- ex : 4 4 G A I R R U V E QU E O T A S M J
CREATE OR REPLACE FUNCTION grille_texte(p_partie INT) RETURNS TEXT AS $$
    SELECT (grille->>'lignes') || ' ' || (grille->>'colonnes') || ' ' ||
           (SELECT string_agg(c, ' ' ORDER BY i) FROM jsonb_array_elements_text(grille->'cases') WITH ORDINALITY AS t(c, i))
    FROM partie
    WHERE id = p_partie;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- fin du chrono : on fige tout dans resultat (JSONB)
CREATE OR REPLACE FUNCTION terminer_partie(p_partie INT) RETURNS JSONB AS $$
DECLARE
    v_statut VARCHAR;
    v_fin TIMESTAMP;
    v_res JSONB;
BEGIN
    -- verrou : si deux pages terminent la meme partie, la 2e attend
    SELECT p.statut, LEAST(NOW(), p.date_debut + s.duree * INTERVAL '1 second')
    INTO v_statut, v_fin
    FROM partie p JOIN salon s ON s.id = p.salon_id
    WHERE p.id = p_partie
    FOR UPDATE OF p;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partie % introuvable', p_partie;
    END IF;
    IF v_statut <> 'en_cours' THEN
        RAISE EXCEPTION 'La partie % n''est pas en cours', p_partie;
    END IF;

    SELECT jsonb_build_object(
        'salon', s.nom,
        'duree', s.duree,
        'date_debut', p.date_debut,
        'date_fin', v_fin,
        'joueurs', (
            SELECT jsonb_agg(jsonb_build_object(
                       'id', j.id,
                       'pseudo', j.pseudo,
                       'score', pa.score,
                       'rang', (SELECT COUNT(*) + 1 FROM participation x WHERE x.partie_id = p_partie AND x.score > pa.score),
                       'mots', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mot', m.mot, 'valide', m.valide, 'points', m.points) ORDER BY m.date_proposition, m.id), '[]')
                                FROM mot_propose m WHERE m.partie_id = p_partie AND m.joueur_id = j.id)
                   ) ORDER BY pa.score DESC, j.pseudo)
            FROM participation pa JOIN joueur j ON j.id = pa.joueur_id
            WHERE pa.partie_id = p_partie),
        'gagnant', (
            SELECT jsonb_build_object('id', j.id, 'pseudo', j.pseudo, 'score', pa.score)
            FROM participation pa JOIN joueur j ON j.id = pa.joueur_id
            WHERE pa.partie_id = p_partie
            ORDER BY pa.score DESC, j.pseudo
            LIMIT 1),
        'mots_rates', (
            SELECT COALESCE(jsonb_agg(sol), '[]')
            FROM jsonb_array_elements_text(p.grille->'solutions') sol
            WHERE sol NOT IN (SELECT m.mot FROM mot_propose m WHERE m.partie_id = p_partie AND m.valide)))
    INTO v_res
    FROM partie p JOIN salon s ON s.id = p.salon_id
    WHERE p.id = p_partie;

    UPDATE partie SET statut = 'terminee', date_fin = v_fin, resultat = v_res WHERE id = p_partie;
    UPDATE salon SET statut = 'attente' WHERE id = (SELECT salon_id FROM partie WHERE id = p_partie);
    RETURN v_res;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- termine les parties dont le chrono est fini mais que personne n'a terminees
-- (tout le monde a ferme l'onglet). Le PHP l'appelle au chargement des pages.
-- SKIP LOCKED : si une autre page est deja en train de la terminer, on passe
CREATE OR REPLACE FUNCTION terminer_parties_expirees() RETURNS INT AS $$
DECLARE
    v_id INT;
    v_nb INT := 0;
BEGIN
    FOR v_id IN
        SELECT p.id
        FROM partie p JOIN salon s ON s.id = p.salon_id
        WHERE p.statut = 'en_cours'
          AND p.date_debut + s.duree * INTERVAL '1 second' < NOW()
        FOR UPDATE OF p SKIP LOCKED
    LOOP
        PERFORM terminer_partie(v_id);
        v_nb := v_nb + 1;
    END LOOP;
    RETURN v_nb;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


----------------------------------------------------------------
-- Affichage / historique (lecture du JSONB)
----------------------------------------------------------------

-- SELECT * FROM afficher_partie(1);
CREATE OR REPLACE FUNCTION afficher_partie(p_partie INT)
RETURNS TABLE (partie INT, date_debut TIMESTAMP, salon TEXT, taille TEXT, grille TEXT,
               rang INT, joueur TEXT, score INT, mots_trouves TEXT, mots_refuses TEXT, gagnant TEXT) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM partie p WHERE p.id = p_partie AND p.statut = 'terminee') THEN
        RAISE EXCEPTION 'Partie % introuvable ou pas terminee', p_partie;
    END IF;

    RETURN QUERY
    SELECT p.id,
           p.date_debut,
           p.resultat->>'salon',
           (p.grille->>'lignes') || 'x' || (p.grille->>'colonnes'),
           (SELECT string_agg(c, ' ') FROM jsonb_array_elements_text(p.grille->'cases') c),
           (j->>'rang')::int,
           j->>'pseudo',
           (j->>'score')::int,
           (SELECT string_agg(m->>'mot', ', ') FROM jsonb_array_elements(j->'mots') m WHERE (m->>'valide')::boolean),
           (SELECT string_agg(m->>'mot', ', ') FROM jsonb_array_elements(j->'mots') m WHERE NOT (m->>'valide')::boolean),
           p.resultat #>> '{gagnant,pseudo}'
    FROM partie p, jsonb_array_elements(p.resultat->'joueurs') j
    WHERE p.id = p_partie
    ORDER BY (j->>'rang')::int, j->>'pseudo';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- SELECT * FROM afficher_grille(1);
CREATE OR REPLACE FUNCTION afficher_grille(p_partie INT)
RETURNS TABLE (ligne INT, lettres TEXT) AS $$
    SELECT ((t.i - 1) / (p.grille->>'colonnes')::int + 1)::int,
           string_agg(t.c, ' ' ORDER BY t.i)
    FROM partie p, jsonb_array_elements_text(p.grille->'cases') WITH ORDINALITY AS t(c, i)
    WHERE p.id = p_partie
    GROUP BY 1
    ORDER BY 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- SELECT * FROM historique_joueur(1);
CREATE OR REPLACE FUNCTION historique_joueur(p_joueur INT)
RETURNS TABLE (partie INT, date_debut TIMESTAMP, score INT, rang INT, nb_joueurs INT, nb_mots INT, gagne BOOLEAN) AS $$
    SELECT p.id,
           p.date_debut,
           (j->>'score')::int,
           (j->>'rang')::int,
           jsonb_array_length(p.resultat->'joueurs'),
           jsonb_array_length(j->'mots'),
           (p.resultat->'gagnant'->>'id')::int = p_joueur
    FROM partie p, jsonb_array_elements(p.resultat->'joueurs') j
    WHERE p.resultat @> jsonb_build_object('joueurs', jsonb_build_array(jsonb_build_object('id', p_joueur)))
      AND (j->>'id')::int = p_joueur
    ORDER BY p.date_debut DESC;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- stats calculees, jamais stockees
CREATE OR REPLACE FUNCTION stats_joueur(p_joueur INT)
RETURNS TABLE (nb_parties BIGINT, victoires BIGINT, meilleur_score INT, score_moyen NUMERIC, nb_mots_valides BIGINT) AS $$
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE (p.resultat->'gagnant'->>'id')::int = p_joueur),
           COALESCE(MAX(pa.score), 0),
           COALESCE(ROUND(AVG(pa.score), 1), 0),
           (SELECT COUNT(*) FROM mot_propose m WHERE m.joueur_id = p_joueur AND m.valide)
    FROM participation pa JOIN partie p ON p.id = pa.partie_id
    WHERE pa.joueur_id = p_joueur AND p.statut = 'terminee';
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


----------------------------------------------------------------
-- Comptes et crypto : la cle vient toujours du PHP
----------------------------------------------------------------

-- p_mdp_hash = resultat de password_hash() en PHP
-- un email vide ('' ou des espaces) est traite comme pas d'email
CREATE OR REPLACE FUNCTION inscrire(p_pseudo VARCHAR, p_mdp_hash VARCHAR, p_email VARCHAR, p_cle TEXT)
RETURNS INT AS $$
DECLARE
    v_email TEXT := LOWER(NULLIF(TRIM(p_email), ''));
    v_id INT;
BEGIN
    INSERT INTO joueur (pseudo, mdp_hash, email_chiffre, email_hash)
    VALUES (p_pseudo, p_mdp_hash,
            pgp_sym_encrypt(v_email, p_cle),
            encode(hmac(v_email, p_cle, 'sha256'), 'hex'))
    RETURNING id INTO v_id;

    INSERT INTO profil (joueur_id) VALUES (v_id);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- connexion : le PHP recupere le hash puis fait password_verify()
-- 'ALI' retrouve le compte 'ali'
CREATE OR REPLACE FUNCTION infos_connexion(p_pseudo VARCHAR)
RETURNS TABLE (id INT, pseudo VARCHAR, mdp_hash VARCHAR) AS $$
    SELECT j.id, j.pseudo, j.mdp_hash
    FROM joueur j
    WHERE LOWER(j.pseudo) = LOWER(TRIM(p_pseudo)) AND NOT j.supprime;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- appelee apres un password_verify() reussi
CREATE OR REPLACE PROCEDURE enregistrer_connexion(p_joueur INT) AS $$
BEGIN
    UPDATE joueur SET derniere_connexion = NOW() WHERE id = p_joueur AND NOT supprime;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Joueur % introuvable', p_joueur;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


CREATE OR REPLACE FUNCTION email_joueur(p_joueur INT, p_cle TEXT) RETURNS TEXT AS $$
    SELECT pgp_sym_decrypt(email_chiffre, p_cle) FROM joueur WHERE id = p_joueur;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


CREATE OR REPLACE FUNCTION email_existe(p_email VARCHAR, p_cle TEXT) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM joueur
                   WHERE email_hash = encode(hmac(LOWER(NULLIF(TRIM(p_email), '')), p_cle, 'sha256'), 'hex'));
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


CREATE OR REPLACE PROCEDURE modifier_identite(p_joueur INT, p_nom VARCHAR, p_prenom VARCHAR, p_cle TEXT) AS $$
BEGIN
    UPDATE profil
    SET nom_chiffre = pgp_sym_encrypt(NULLIF(TRIM(p_nom), ''), p_cle),
        prenom_chiffre = pgp_sym_encrypt(NULLIF(TRIM(p_prenom), ''), p_cle)
    WHERE joueur_id = p_joueur;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Joueur % introuvable', p_joueur;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- avatar, bio et visibilite du profil
CREATE OR REPLACE PROCEDURE modifier_profil(p_joueur INT, p_avatar VARCHAR, p_bio VARCHAR, p_public BOOLEAN) AS $$
BEGIN
    UPDATE profil
    SET avatar = NULLIF(TRIM(p_avatar), ''), bio = NULLIF(TRIM(p_bio), ''), est_public = p_public
    WHERE joueur_id = p_joueur;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Joueur % introuvable', p_joueur;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- profil complet, seulement pour le joueur lui-meme
CREATE OR REPLACE FUNCTION profil_prive(p_joueur INT, p_cle TEXT)
RETURNS TABLE (pseudo VARCHAR, email TEXT, nom TEXT, prenom TEXT, avatar VARCHAR, bio VARCHAR, est_public BOOLEAN) AS $$
    SELECT j.pseudo,
           pgp_sym_decrypt(j.email_chiffre, p_cle),
           pgp_sym_decrypt(pr.nom_chiffre, p_cle),
           pgp_sym_decrypt(pr.prenom_chiffre, p_cle),
           pr.avatar, pr.bio, pr.est_public
    FROM joueur j JOIN profil pr ON pr.joueur_id = j.id
    WHERE j.id = p_joueur;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


----------------------------------------------------------------
-- Securite des comptes : tentatives de connexion, mot de passe oublie
----------------------------------------------------------------

-- TRUE si on doit refuser la connexion : 5 echecs sur ce pseudo
-- ou 20 echecs depuis cette ip dans les 15 dernieres minutes
CREATE OR REPLACE FUNCTION connexion_bloquee(p_pseudo VARCHAR, p_ip_hash VARCHAR) RETURNS BOOLEAN AS $$
    SELECT (SELECT COUNT(*) FROM tentative_connexion
            WHERE pseudo = LOWER(LEFT(TRIM(p_pseudo), 30)) AND date_tentative > NOW() - INTERVAL '15 minutes') >= 5
        OR (SELECT COUNT(*) FROM tentative_connexion
            WHERE ip_hash = p_ip_hash AND date_tentative > NOW() - INTERVAL '15 minutes') >= 20;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- un echec est note meme si le pseudo n'existe pas (sinon on saurait lesquels existent)
-- on efface au passage les tentatives de plus d'un jour (minimisation)
CREATE OR REPLACE PROCEDURE noter_echec(p_pseudo VARCHAR, p_ip_hash VARCHAR) AS $$
BEGIN
    DELETE FROM tentative_connexion WHERE date_tentative < NOW() - INTERVAL '1 day';
    INSERT INTO tentative_connexion (pseudo, ip_hash) VALUES (LOWER(LEFT(TRIM(p_pseudo), 30)), p_ip_hash);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- connexion reussie : le compteur du pseudo repart a zero
CREATE OR REPLACE PROCEDURE effacer_echecs(p_pseudo VARCHAR) AS $$
BEGIN
    DELETE FROM tentative_connexion WHERE pseudo = LOWER(LEFT(TRIM(p_pseudo), 30));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- l'email est chiffre : on le retrouve par son hmac
CREATE OR REPLACE FUNCTION joueur_par_email(p_email VARCHAR, p_cle TEXT)
RETURNS TABLE (id INT, pseudo VARCHAR) AS $$
    SELECT j.id, j.pseudo
    FROM joueur j
    WHERE j.email_hash = encode(hmac(LOWER(NULLIF(TRIM(p_email), '')), p_cle, 'sha256'), 'hex')
      AND NOT j.supprime;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- p_jeton_hash = sha256 du jeton envoye par email, valable 30 minutes
-- les anciens jetons du joueur ne marchent plus
-- FALSE si un jeton a deja ete demande il y a moins de 2 minutes (pas de spam d'emails)
CREATE OR REPLACE FUNCTION creer_jeton(p_joueur INT, p_jeton_hash VARCHAR) RETURNS BOOLEAN AS $$
BEGIN
    PERFORM 1 FROM joueur WHERE id = p_joueur AND NOT supprime FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Joueur % introuvable', p_joueur;
    END IF;

    IF EXISTS (SELECT 1 FROM jeton_reinit
               WHERE joueur_id = p_joueur AND date_creation > NOW() - INTERVAL '2 minutes') THEN
        RETURN FALSE;
    END IF;

    UPDATE jeton_reinit SET utilise = TRUE WHERE joueur_id = p_joueur AND NOT utilise;
    INSERT INTO jeton_reinit (joueur_id, jeton_hash, date_expiration)
    VALUES (p_joueur, p_jeton_hash, NOW() + INTERVAL '30 minutes');
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- pour afficher le formulaire seulement si le lien est encore bon
CREATE OR REPLACE FUNCTION jeton_valide(p_jeton_hash VARCHAR) RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM jeton_reinit
                   WHERE jeton_hash = p_jeton_hash AND NOT utilise AND date_expiration > NOW());
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- usage unique : FOR UPDATE, deux envois du formulaire en meme temps ne passent pas tous les deux
CREATE OR REPLACE PROCEDURE reinitialiser_mdp(p_jeton_hash VARCHAR, p_mdp_hash VARCHAR) AS $$
DECLARE
    v_joueur INT;
BEGIN
    SELECT joueur_id INTO v_joueur
    FROM jeton_reinit
    WHERE jeton_hash = p_jeton_hash AND NOT utilise AND date_expiration > NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lien invalide ou expire';
    END IF;

    UPDATE jeton_reinit SET utilise = TRUE WHERE joueur_id = v_joueur;
    UPDATE joueur SET mdp_hash = p_mdp_hash WHERE id = v_joueur AND NOT supprime;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lien invalide ou expire';
    END IF;
    DELETE FROM tentative_connexion WHERE pseudo = (SELECT LOWER(pseudo) FROM joueur WHERE id = v_joueur);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


----------------------------------------------------------------
-- RGPD
----------------------------------------------------------------

-- droit d'acces : toutes les donnees d'un joueur en JSON
CREATE OR REPLACE FUNCTION export_donnees(p_joueur INT, p_cle TEXT) RETURNS JSONB AS $$
    SELECT jsonb_build_object(
        'compte', (SELECT to_jsonb(pp) FROM profil_prive(p_joueur, p_cle) pp),
        'date_inscription', j.date_inscription,
        'date_consentement', j.date_consentement,
        'derniere_connexion', j.derniere_connexion,
        'parties', (SELECT COALESCE(jsonb_agg(to_jsonb(h)), '[]') FROM historique_joueur(p_joueur) h),
        'messages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('salon', m.salon_id, 'date', m.date_envoi, 'contenu', m.contenu)), '[]')
                     FROM message m WHERE m.joueur_id = p_joueur))
    FROM joueur j
    WHERE j.id = p_joueur;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public, crypto;


-- droit a l'effacement : on anonymise au lieu de supprimer,
-- pour ne pas casser l'historique des autres joueurs
CREATE OR REPLACE PROCEDURE supprimer_joueur(p_joueur INT) AS $$
DECLARE
    v_pseudo VARCHAR := 'joueur_supprime_' || p_joueur;
BEGIN
    UPDATE joueur
    SET pseudo = v_pseudo, mdp_hash = '', email_chiffre = NULL, email_hash = NULL, supprime = TRUE
    WHERE id = p_joueur;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Joueur % introuvable', p_joueur;
    END IF;

    DELETE FROM profil WHERE joueur_id = p_joueur;
    DELETE FROM membre_salon WHERE joueur_id = p_joueur;
    DELETE FROM jeton_reinit WHERE joueur_id = p_joueur;
    UPDATE message SET contenu = '[message supprime]' WHERE joueur_id = p_joueur;

    -- le pseudo est aussi dans les resultats JSON
    UPDATE partie
    SET resultat = jsonb_set(
            jsonb_set(resultat, '{joueurs}',
                (SELECT jsonb_agg(CASE WHEN (j->>'id')::int = p_joueur
                                       THEN jsonb_set(j, '{pseudo}', to_jsonb(v_pseudo))
                                       ELSE j END)
                 FROM jsonb_array_elements(resultat->'joueurs') j)),
            '{gagnant,pseudo}',
            CASE WHEN (resultat->'gagnant'->>'id')::int = p_joueur
                 THEN to_jsonb(v_pseudo) ELSE resultat->'gagnant'->'pseudo' END)
    WHERE resultat @> jsonb_build_object('joueurs', jsonb_build_array(jsonb_build_object('id', p_joueur)));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


-- duree de conservation : lancee chaque nuit par l'admin (cron), pas par le site
-- comptes sans connexion depuis 2 ans -> anonymises ; messages de plus d'1 an -> effaces
-- jetons expires et tentatives de connexion de plus d'1 jour -> effaces
CREATE OR REPLACE PROCEDURE purger_donnees(p_inactivite INTERVAL DEFAULT '2 years',
                                           p_messages INTERVAL DEFAULT '1 year') AS $$
DECLARE
    v_id INT;
    v_nb_comptes INT := 0;
    v_nb_messages INT;
BEGIN
    FOR v_id IN SELECT id FROM joueur WHERE NOT supprime AND derniere_connexion < NOW() - p_inactivite LOOP
        CALL supprimer_joueur(v_id);
        v_nb_comptes := v_nb_comptes + 1;
    END LOOP;

    DELETE FROM message WHERE date_envoi < NOW() - p_messages;
    GET DIAGNOSTICS v_nb_messages = ROW_COUNT;

    DELETE FROM jeton_reinit WHERE date_expiration < NOW() OR utilise;
    DELETE FROM tentative_connexion WHERE date_tentative < NOW() - INTERVAL '1 day';

    RAISE NOTICE '% compte(s) anonymise(s), % message(s) efface(s)', v_nb_comptes, v_nb_messages;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, crypto;


----------------------------------------------------------------
-- Vues
----------------------------------------------------------------

-- ce que les autres voient : pas d'email, pas de nom
CREATE OR REPLACE VIEW profil_public AS
SELECT j.id, j.pseudo, pr.avatar, pr.bio, j.date_inscription,
       (SELECT COUNT(*) FROM participation pa WHERE pa.joueur_id = j.id) AS nb_parties
FROM joueur j
JOIN profil pr ON pr.joueur_id = j.id
WHERE pr.est_public AND NOT j.supprime;

CREATE OR REPLACE VIEW classement AS
SELECT j.pseudo, SUM(pa.score) AS total, COUNT(*) AS nb_parties, MAX(pa.score) AS meilleur
FROM participation pa
JOIN joueur j ON j.id = pa.joueur_id
JOIN partie p ON p.id = pa.partie_id
WHERE p.statut = 'terminee' AND NOT j.supprime
GROUP BY j.pseudo
ORDER BY total DESC;
