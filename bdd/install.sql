-- psql -d boggle -f install.sql
\set ON_ERROR_STOP on
\i 01_schema.sql
\i 02_fonctions.sql
\i 03_donnees.sql
\i droits.sql
