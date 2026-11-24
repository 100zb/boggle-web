# Boggle : site web (SAÉ S3, module L3)

Site du jeu de Boggle en PHP objet, sans framework. Il s'appuie sur la base PostgreSQL du module L2 (dossier `bdd/`).
Le site se connecte avec le rôle `boggle_web` et passe par les fonctions SQL de `bdd/02_fonctions.sql`.

- Site en ligne : https://boggle-web.onrender.com (plan gratuit : le premier chargement peut prendre une minute)
- Base : Neon (PostgreSQL 16, Francfort)

## Architecture

```
public/index.php        contrôleur frontal : configuration, en-têtes de sécurité, routes
src/Router.php          associe une URL à un contrôleur, vérifie le jeton CSRF de tous les POST
src/Controller/         AuthController (comptes), PartieController (page des parties), PageController
src/Model/              JoueurModel, SecuriteModel : requêtes préparées vers les fonctions SQL
src/Session.php         cookie de session, connexion, expiration, messages flash
src/Csrf.php            jeton anti-CSRF
src/Validation.php      règles du pseudo, de l'email et du mot de passe
src/Mailer.php          envoi d'emails avec PHPMailer
src/Vue.php + views/    gabarit commun (layout.php) et une vue par page
bdd/                    scripts SQL du module L2
docker/                 configuration Apache et PHP de l'image
```

Pour ajouter une page : une méthode dans un contrôleur, une vue dans `views/`, une ligne dans `public/index.php`.

## Installation en local

Il faut PHP 8.1 ou plus avec `pdo_pgsql`, Composer et PostgreSQL 16.

```
composer install
createdb boggle
cd bdd && psql -d boggle -f install.sql && cd ..
cp .env.example .env      # puis remplir DB_PASSWORD (a_changer en local) et CLE
php -S localhost:8000 -t public
```

`install.sql` charge aussi le jeu de test (comptes `ali`, `sarah`...). Pour tester les emails sans vrai serveur, on peut lancer un faux SMTP qui écrit les messages dans un dossier :

```
pip install aiosmtpd
python3 -m aiosmtpd -n -l 127.0.0.1:1025 -c aiosmtpd.handlers.Mailbox ./mails
```
puis `SMTP_HOST=127.0.0.1`, `SMTP_PORT=1025`, `SMTP_SECURE=aucun` dans `.env`.

## Variables d'environnement

Toutes dans `.env.example`. Aucune n'est dans le dépôt : en local elles sont dans `.env` (ignoré par git), en ligne dans Render.

| Variable | Rôle |
|---|---|
| `APP_ENV` | `dev` affiche les erreurs ; tout le reste vaut `prod` (erreurs cachées) |
| `APP_URL` | adresse du site, utilisée pour le lien du mot de passe oublié |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSLMODE` | connexion PostgreSQL avec le rôle `boggle_web` |
| `CLE` | clé de chiffrement des emails et du hmac (`openssl rand -hex 32`) |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_SECURE`, `MAIL_FROM` | envoi des emails |
| `DERRIERE_PROXY` | `oui` sur Render : la vraie IP est lue dans `CF-Connecting-IP` (Render passe par Cloudflare) |

## Déploiement

1. Base Neon : exécuter `01_schema.sql`, `02_fonctions.sql` et `droits.sql` (pas `03_donnees.sql`), puis `ALTER ROLE boggle_web PASSWORD '...'`.
2. Render : New > Web Service > ce dépôt GitHub, runtime **Docker**, plan **Free**, région Frankfurt. Ajouter les variables d'environnement.
3. Chaque `git push` sur `main` redéploie le site.

Le `Dockerfile` part de `php:8.3-apache`, ajoute `pdo_pgsql`, installe PHPMailer avec Composer et sert le dossier `public/` seulement. Apache écoute sur la variable `PORT` donnée par Render.

**Emails** : le plan gratuit de Render bloque les ports SMTP 25, 465 et 587. On passe donc par Brevo sur le port 2525 (STARTTLS), toujours avec PHPMailer. PHPMailer est installé depuis son dépôt git officiel (voir `composer.json`).

## Sécurité

| Mesure | Pourquoi |
|---|---|
| `password_hash` / `password_verify` | le mot de passe n'est jamais stocké, seulement un hash bcrypt salé |
| 12 caractères min., 4 types (CNIL, délibération 2022-100) | 80 bits d'entropie, le niveau demandé quand le mot de passe est le seul facteur |
| 72 caractères max. | bcrypt ignore ce qui dépasse 72 octets |
| Requêtes préparées partout (PDO, `EMULATE_PREPARES` à false) | pas d'injection SQL : les valeurs ne sont jamais collées dans la requête |
| `e()` = `htmlspecialchars` sur tout ce qui est affiché | pas de XSS : un `<script>` saisi s'affiche comme du texte |
| Jeton CSRF sur tous les formulaires, vérifié dans le routeur | un autre site ne peut pas faire poster un formulaire à notre place ; un seul endroit, impossible de l'oublier |
| Cookie de session `HttpOnly`, `Secure`, `SameSite=Lax` | JavaScript ne lit pas le cookie, il ne passe qu'en HTTPS, et pas dans les requêtes venant d'autres sites |
| `session_regenerate_id` à la connexion | contre la fixation de session : l'id d'avant la connexion ne sert plus |
| `use_strict_mode` | PHP refuse un id de session inventé par le client |
| Expiration après 30 min d'inactivité, déconnexion en POST | une session oubliée ne reste pas ouverte ; un simple lien ne peut pas déconnecter |
| 5 échecs par pseudo ou 20 par IP en 15 min, stocké en BDD | contre le brute force ; en session, l'attaquant viderait ses cookies |
| Même message pour pseudo inconnu et mauvais mot de passe, et `password_verify` même si le pseudo n'existe pas | on ne peut pas savoir quels pseudos existent, ni par le message, ni par le temps de réponse |
| Mot de passe oublié : même message que l'email existe ou non | pas d'énumération des comptes |
| Jeton `random_bytes(32)`, seul son sha256 est en base, 30 min, usage unique | impossible à deviner ; une fuite de la base ne donne pas de lien utilisable |
| Lien construit avec `APP_URL`, pas avec l'en-tête `Host` | un attaquant ne peut pas faire envoyer un lien vers son propre site |
| HTTPS (Render) + `Strict-Transport-Security` | le navigateur refuse ensuite le HTTP |
| CSP `default-src 'self'` | le navigateur n'exécute que nos fichiers : pas de script injecté ni de ressource externe |
| `X-Frame-Options: DENY`, `frame-ancestors 'none'` | le site ne peut pas être affiché dans une iframe (clickjacking) |
| `X-Content-Type-Options: nosniff` | le navigateur ne devine pas le type d'un fichier |
| `Referrer-Policy: same-origin` | le lien de réinitialisation (avec le jeton) n'est jamais envoyé à un autre site |
| `display_errors` à Off en prod, erreurs dans le journal de Render | pas de chemin ni de requête SQL montrés à l'utilisateur |
| `expose_php` Off, `ServerTokens Prod` | on n'annonce pas les versions de PHP et d'Apache |
| Seul `public/` est servi | `src/`, `views/`, `.env` ne sont pas accessibles par URL |
| Secrets en variables d'environnement, `.env` dans `.gitignore` | rien de secret dans git |
| Rôle `boggle_web` (moindre privilège) | même avec une injection SQL, pas d'accès aux hash ni aux emails chiffrés |

RGPD : consentement à l'inscription (case obligatoire), page « Données personnelles », email facultatif, aucune ressource externe ni traceur. En base : email chiffré, profil privé par défaut, export, anonymisation, durées de conservation (voir `bdd/README.md`).

## Tests

`tests/parcours.sh http://localhost:8000` joue le parcours complet avec curl : CSRF, XSS, inscription, connexion, blocage, mot de passe oublié, usage unique du lien.
