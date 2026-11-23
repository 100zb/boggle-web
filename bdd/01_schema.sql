-- SAE S3 Boggle - Module L2 - Schema (PostgreSQL)

DROP TABLE IF EXISTS tentative_connexion, jeton_reinit, message, mot_propose, participation, partie, membre_salon, salon, profil, joueur CASCADE;

-- pgcrypto dans son propre schema, sans droit pour le role du site
-- (sur Neon, les fonctions de pgcrypto appartiennent a l'admin du cloud :
-- un REVOKE fait par nous ne marche pas dessus, alors on ferme le schema)
DROP EXTENSION IF EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS crypto;
REVOKE ALL ON SCHEMA crypto FROM PUBLIC;
CREATE EXTENSION pgcrypto SCHEMA crypto;

-- email chiffre (pgp_sym_encrypt) + hmac de l'email pour l'unicite
-- la cle est passee par le PHP, elle n'est jamais stockee en base
CREATE TABLE joueur (
    id SERIAL PRIMARY KEY,
    pseudo VARCHAR(30) NOT NULL,
    mdp_hash VARCHAR(255) NOT NULL,
    email_chiffre BYTEA,
    email_hash CHAR(64) UNIQUE,
    date_inscription TIMESTAMP NOT NULL DEFAULT NOW(),
    date_consentement TIMESTAMP NOT NULL DEFAULT NOW(),
    derniere_connexion TIMESTAMP NOT NULL DEFAULT NOW(),
    supprime BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (pseudo ~ '^[A-Za-z0-9_]{3,30}$')
);

-- 'Ali' et 'ali' ne peuvent pas exister en meme temps
CREATE UNIQUE INDEX idx_joueur_pseudo ON joueur (LOWER(pseudo));

-- tout est facultatif (RGPD : minimisation), prive par defaut
CREATE TABLE profil (
    joueur_id INT PRIMARY KEY REFERENCES joueur(id) ON DELETE CASCADE,
    nom_chiffre BYTEA,
    prenom_chiffre BYTEA,
    avatar VARCHAR(255),
    bio VARCHAR(300),
    est_public BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE salon (
    id SERIAL PRIMARY KEY,
    nom VARCHAR(50) NOT NULL,
    createur_id INT NOT NULL REFERENCES joueur(id),
    nb_lignes INT NOT NULL DEFAULT 4 CHECK (nb_lignes BETWEEN 2 AND 10),
    nb_colonnes INT NOT NULL DEFAULT 4 CHECK (nb_colonnes BETWEEN 2 AND 10),
    duree INT NOT NULL DEFAULT 180 CHECK (duree > 0),
    nb_max_joueurs INT NOT NULL DEFAULT 4 CHECK (nb_max_joueurs BETWEEN 1 AND 10),
    statut VARCHAR(10) NOT NULL DEFAULT 'attente' CHECK (statut IN ('attente', 'en_cours', 'ferme')),
    date_creation TIMESTAMP NOT NULL DEFAULT NOW()
);

-- qui est dans le salon avant le lancement
CREATE TABLE membre_salon (
    salon_id INT REFERENCES salon(id) ON DELETE CASCADE,
    joueur_id INT REFERENCES joueur(id),
    date_arrivee TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (salon_id, joueur_id)
);

-- grille : {"lignes": 4, "colonnes": 4, "cases": ["G","A",...,"QU",...], "solutions": [...]}
-- resultat : rempli par terminer_partie(), trace complete de la partie
CREATE TABLE partie (
    id SERIAL PRIMARY KEY,
    salon_id INT NOT NULL REFERENCES salon(id),
    grille JSONB NOT NULL,
    statut VARCHAR(10) NOT NULL DEFAULT 'en_cours' CHECK (statut IN ('en_cours', 'terminee')),
    date_debut TIMESTAMP NOT NULL DEFAULT NOW(),
    date_fin TIMESTAMP,
    resultat JSONB,
    CHECK (date_fin IS NULL OR date_fin >= date_debut),
    CHECK (grille ? 'lignes' AND grille ? 'colonnes' AND jsonb_typeof(grille->'cases') = 'array'),
    CHECK (jsonb_array_length(grille->'cases') = (grille->>'lignes')::int * (grille->>'colonnes')::int),
    CHECK (statut = 'en_cours' OR resultat IS NOT NULL)
);

CREATE TABLE participation (
    joueur_id INT REFERENCES joueur(id),
    partie_id INT REFERENCES partie(id) ON DELETE CASCADE,
    score INT NOT NULL DEFAULT 0,
    PRIMARY KEY (joueur_id, partie_id)
);

CREATE TABLE mot_propose (
    id SERIAL PRIMARY KEY,
    joueur_id INT NOT NULL,
    partie_id INT NOT NULL,
    mot VARCHAR(30) NOT NULL,
    valide BOOLEAN NOT NULL DEFAULT FALSE,
    points INT NOT NULL DEFAULT 0,
    date_proposition TIMESTAMP NOT NULL DEFAULT NOW(),
    FOREIGN KEY (joueur_id, partie_id) REFERENCES participation(joueur_id, partie_id) ON DELETE CASCADE,
    UNIQUE (joueur_id, partie_id, mot)
);

CREATE TABLE message (
    id SERIAL PRIMARY KEY,
    salon_id INT NOT NULL REFERENCES salon(id) ON DELETE CASCADE,
    joueur_id INT NOT NULL REFERENCES joueur(id),
    contenu VARCHAR(500) NOT NULL,
    date_envoi TIMESTAMP NOT NULL DEFAULT NOW()
);

-- mot de passe oublie : on stocke le sha256 du jeton envoye par email, jamais le jeton
-- (si la base fuite, les liens en cours ne sont pas utilisables)
CREATE TABLE jeton_reinit (
    id SERIAL PRIMARY KEY,
    joueur_id INT NOT NULL REFERENCES joueur(id) ON DELETE CASCADE,
    jeton_hash CHAR(64) NOT NULL UNIQUE,
    date_creation TIMESTAMP NOT NULL DEFAULT NOW(),
    date_expiration TIMESTAMP NOT NULL,
    utilise BOOLEAN NOT NULL DEFAULT FALSE
);

-- limitation des tentatives de connexion (en base : une session se vide facilement)
-- pseudo tape en minuscules (meme s'il n'existe pas), ip hachee par le PHP avec la cle
CREATE TABLE tentative_connexion (
    id SERIAL PRIMARY KEY,
    pseudo VARCHAR(30) NOT NULL,
    ip_hash CHAR(64) NOT NULL,
    date_tentative TIMESTAMP NOT NULL DEFAULT NOW()
);


-- Index
-- GIN sur le resultat : parties d'un joueur avec @>
CREATE INDEX idx_partie_resultat ON partie USING GIN (resultat jsonb_path_ops);
-- GIN sur les solutions : grilles qui contiennent un mot avec ? et ?|
CREATE INDEX idx_partie_solutions ON partie USING GIN ((grille->'solutions'));
-- btree sur des valeurs extraites du JSON
CREATE INDEX idx_partie_gagnant ON partie ((resultat->'gagnant'->>'pseudo'));
CREATE INDEX idx_partie_taille ON partie (((grille->>'lignes')::int), ((grille->>'colonnes')::int));

CREATE INDEX idx_partie_salon ON partie (salon_id, statut);
CREATE INDEX idx_participation_partie ON participation (partie_id);
CREATE INDEX idx_mot_partie ON mot_propose (partie_id, joueur_id);
CREATE INDEX idx_message_salon ON message (salon_id, date_envoi);
CREATE INDEX idx_message_date ON message (date_envoi);
CREATE INDEX idx_jeton_joueur ON jeton_reinit (joueur_id);
CREATE INDEX idx_tentative_pseudo ON tentative_connexion (pseudo, date_tentative);
CREATE INDEX idx_tentative_ip ON tentative_connexion (ip_hash, date_tentative);
