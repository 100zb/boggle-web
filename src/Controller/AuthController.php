<?php

namespace App\Controller;

use App\Config;
use App\Mailer;
use App\Model\JoueurModel;
use App\Model\SecuriteModel;
use App\Session;
use App\Validation;

class AuthController extends Controller
{
    // hash d'un mot de passe aleatoire : si le pseudo n'existe pas, on fait quand meme
    // un password_verify pour que la reponse prenne le meme temps
    private const FAUX_HASH = '$2y$10$b3bQosT9pDpF620xEsZ8beA50NJfGP7alRcCKC3FrQQne.fR9Bk06';

    public function accueil(): void
    {
        if (Session::joueurId() !== null) {
            $this->rediriger('/parties');
        }
        $this->vue('accueil', [], 'Boggle - Connexion');
    }

    public function connexion(): void
    {
        $pseudo = trim($this->champ('pseudo'));
        $mdp = $this->champ('mdp');
        $ipHash = hash_hmac('sha256', $this->ip(), Config::get('CLE'));
        $securite = new SecuriteModel();

        if ($securite->connexionBloquee($pseudo, $ipHash)) {
            Session::flash('Trop de tentatives. Réessaie dans 15 minutes.', 'erreur');
            $this->rediriger('/');
        }

        $joueurs = new JoueurModel();
        $joueur = Validation::pseudo($pseudo) === null ? $joueurs->infosConnexion($pseudo) : null;
        $mdpOk = password_verify($mdp, $joueur['mdp_hash'] ?? self::FAUX_HASH);

        if ($joueur === null || !$mdpOk) {
            $securite->noterEchec($pseudo, $ipHash);
            Session::flash('Pseudo ou mot de passe incorrect.', 'erreur');
            $this->rediriger('/');
        }

        $securite->effacerEchecs($pseudo);
        $joueurs->enregistrerConnexion($joueur['id']);
        Session::connecter($joueur['id'], $joueur['pseudo']);
        $this->rediriger('/parties');
    }

    public function formulaireInscription(): void
    {
        $this->vue('inscription', ['erreurs' => [], 'pseudo' => '', 'email' => ''], 'Boggle - Créer un compte');
    }

    public function inscription(): void
    {
        $pseudo = trim($this->champ('pseudo'));
        $email = trim($this->champ('email'));
        $mdp = $this->champ('mdp');

        $erreurs = array_filter([
            Validation::pseudo($pseudo),
            Validation::email($email),
            Validation::motDePasse($mdp, $this->champ('confirmation'), $pseudo),
            $this->champ('consentement') === 'oui' ? null : 'Tu dois accepter la politique de confidentialité.',
        ]);

        if (!$erreurs) {
            $resultat = (new JoueurModel())->inscrire($pseudo, $mdp, $email);
            if ($resultat === 'pseudo') {
                $erreurs[] = 'Ce pseudo est déjà pris.';
            } elseif ($resultat === 'email') {
                $erreurs[] = 'Cette adresse email est déjà utilisée.';
            } else {
                Session::connecter($resultat, $pseudo);
                Session::flash('Bienvenue ' . $pseudo . ', ton compte est créé.');
                $this->rediriger('/parties');
            }
        }

        $this->vue('inscription', ['erreurs' => $erreurs, 'pseudo' => $pseudo, 'email' => $email], 'Boggle - Créer un compte');
    }

    public function deconnexion(): void
    {
        Session::detruire();
        session_start();
        Session::flash('Tu es déconnecté.');
        $this->rediriger('/');
    }

    public function formulaireOubli(): void
    {
        $this->vue('oubli', [], 'Boggle - Mot de passe oublié');
    }

    // meme message que l'email existe ou non : on ne doit pas pouvoir tester les adresses
    public function oubli(): void
    {
        $email = trim($this->champ('email'));

        if (Validation::email($email) === null && $email !== '') {
            $joueur = (new JoueurModel())->parEmail($email);
            if ($joueur !== null) {
                $jeton = bin2hex(random_bytes(32));
                if ((new SecuriteModel())->creerJeton($joueur['id'], $jeton)) {
                    $lien = rtrim(Config::get('APP_URL'), '/') . '/reinitialiser?jeton=' . $jeton;
                    Mailer::envoyer($email, 'Boggle : nouveau mot de passe',
                        "Bonjour " . $joueur['pseudo'] . ",\n\n"
                        . "Pour choisir un nouveau mot de passe, ouvre ce lien (valable 30 minutes, une seule fois) :\n"
                        . $lien . "\n\n"
                        . "Si tu n'as rien demandé, ignore ce message : ton mot de passe ne change pas.\n");
                }
            }
        }

        Session::flash('Si un compte utilise cette adresse, un email vient d\'être envoyé. Le lien est valable 30 minutes.');
        $this->rediriger('/');
    }

    public function formulaireReinitialisation(): void
    {
        $jeton = $_GET['jeton'] ?? '';
        if (!is_string($jeton) || !preg_match('/^[0-9a-f]{64}$/', $jeton) || !(new SecuriteModel())->jetonValide($jeton)) {
            $this->vue('erreur', ['message' => 'Ce lien n\'est plus valable. Fais une nouvelle demande.'], 'Lien expiré');
            return;
        }
        $this->vue('reinitialisation', ['jeton' => $jeton, 'erreur' => null], 'Boggle - Nouveau mot de passe');
    }

    public function reinitialisation(): void
    {
        $jeton = $this->champ('jeton');
        $mdp = $this->champ('mdp');
        $erreur = Validation::motDePasse($mdp, $this->champ('confirmation'));

        if ($erreur !== null) {
            $this->vue('reinitialisation', ['jeton' => $jeton, 'erreur' => $erreur], 'Boggle - Nouveau mot de passe');
            return;
        }

        if ((new JoueurModel())->changerMotDePasse($jeton, $mdp)) {
            Session::flash('Mot de passe changé, tu peux te connecter.');
        } else {
            Session::flash('Ce lien n\'est plus valable. Fais une nouvelle demande.', 'erreur');
        }
        $this->rediriger('/');
    }
}
