-- SAE S3 Boggle - Module L2 - Role du site (moindre privilege)
-- le PHP se connecte avec boggle_web, jamais avec le proprietaire de la base
-- 'a_changer' est remplace a l'installation : ALTER ROLE boggle_web PASSWORD '...'

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'boggle_web') THEN
        CREATE ROLE boggle_web LOGIN PASSWORD 'a_changer';
    END IF;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO boggle_web', current_database());
END;
$$;

GRANT USAGE ON SCHEMA public TO boggle_web;

-- par defaut tout le monde peut executer toutes les fonctions : on l'enleve
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

-- lecture des donnees de jeu (pas de donnees perso dedans)
GRANT SELECT ON salon, membre_salon, partie, participation, mot_propose, message TO boggle_web;
GRANT SELECT (id, pseudo, supprime) ON joueur TO boggle_web;
GRANT SELECT ON profil_public, classement TO boggle_web;
-- jeton_reinit et tentative_connexion : aucun droit direct, seulement par les fonctions

-- ecriture : seulement les colonnes que le joueur choisit
-- (pas de statut de salon, pas de valide / points pour un mot)
GRANT INSERT (nom, createur_id, nb_lignes, nb_colonnes, duree, nb_max_joueurs) ON salon TO boggle_web;
GRANT INSERT (salon_id, joueur_id) ON membre_salon TO boggle_web;
GRANT DELETE ON membre_salon TO boggle_web;
GRANT INSERT (salon_id, joueur_id, contenu) ON message TO boggle_web;
GRANT INSERT (joueur_id, partie_id, mot) ON mot_propose TO boggle_web;
GRANT USAGE ON SEQUENCE salon_id_seq, message_id_seq, mot_propose_id_seq TO boggle_web;

-- tout le reste passe par les fonctions
GRANT EXECUTE ON FUNCTION
    lancer_partie(INT, TEXT, TEXT),
    terminer_partie(INT),
    terminer_parties_expirees(),
    grille_texte(INT),
    afficher_partie(INT),
    afficher_grille(INT),
    historique_joueur(INT),
    stats_joueur(INT),
    inscrire(VARCHAR, VARCHAR, VARCHAR, TEXT),
    infos_connexion(VARCHAR),
    email_joueur(INT, TEXT),
    email_existe(VARCHAR, TEXT),
    profil_prive(INT, TEXT),
    export_donnees(INT, TEXT),
    connexion_bloquee(VARCHAR, VARCHAR),
    joueur_par_email(VARCHAR, TEXT),
    creer_jeton(INT, VARCHAR),
    jeton_valide(VARCHAR)
TO boggle_web;

GRANT EXECUTE ON PROCEDURE
    enregistrer_connexion(INT),
    modifier_identite(INT, VARCHAR, VARCHAR, TEXT),
    modifier_profil(INT, VARCHAR, VARCHAR, BOOLEAN),
    supprimer_joueur(INT),
    noter_echec(VARCHAR, VARCHAR),
    effacer_echecs(VARCHAR),
    reinitialiser_mdp(VARCHAR, VARCHAR)
TO boggle_web;

-- purger_donnees : pas donnee au site, lancee par l'admin
