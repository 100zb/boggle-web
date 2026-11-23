<?php

namespace App\Model;

use App\Config;
use App\Database;
use PDO;
use PDOException;

class JoueurModel
{
    private PDO $bdd;

    public function __construct()
    {
        $this->bdd = Database::get();
    }

    // renvoie l'id du joueur, ou 'pseudo' / 'email' si deja pris
    public function inscrire(string $pseudo, string $mdp, string $email): int|string
    {
        try {
            $req = $this->bdd->prepare('SELECT inscrire(?, ?, ?, ?)');
            $req->execute([$pseudo, password_hash($mdp, PASSWORD_DEFAULT), $email, Config::get('CLE')]);
            return (int) $req->fetchColumn();
        } catch (PDOException $e) {
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'idx_joueur_pseudo')) {
                return 'pseudo';
            }
            if ($e->getCode() === '23505' && str_contains($e->getMessage(), 'email_hash')) {
                return 'email';
            }
            throw $e;
        }
    }

    public function infosConnexion(string $pseudo): ?array
    {
        $req = $this->bdd->prepare('SELECT * FROM infos_connexion(?)');
        $req->execute([$pseudo]);
        return $req->fetch() ?: null;
    }

    public function enregistrerConnexion(int $id): void
    {
        $req = $this->bdd->prepare('CALL enregistrer_connexion(?)');
        $req->execute([$id]);
    }

    public function parEmail(string $email): ?array
    {
        $req = $this->bdd->prepare('SELECT * FROM joueur_par_email(?, ?)');
        $req->execute([$email, Config::get('CLE')]);
        return $req->fetch() ?: null;
    }

    // false si le lien n'est plus valable (deja utilise, expire)
    public function changerMotDePasse(string $jeton, string $mdp): bool
    {
        try {
            $req = $this->bdd->prepare('CALL reinitialiser_mdp(?, ?)');
            $req->execute([hash('sha256', $jeton), password_hash($mdp, PASSWORD_DEFAULT)]);
            return true;
        } catch (PDOException $e) {
            if (str_contains($e->getMessage(), 'Lien invalide')) {
                return false;
            }
            throw $e;
        }
    }
}
