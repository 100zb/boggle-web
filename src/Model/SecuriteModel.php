<?php

namespace App\Model;

use App\Database;
use PDO;

class SecuriteModel
{
    private PDO $bdd;

    public function __construct()
    {
        $this->bdd = Database::get();
    }

    public function connexionBloquee(string $pseudo, string $ipHash): bool
    {
        $req = $this->bdd->prepare('SELECT connexion_bloquee(?, ?)');
        $req->execute([$pseudo, $ipHash]);
        return (bool) $req->fetchColumn();
    }

    public function noterEchec(string $pseudo, string $ipHash): void
    {
        $req = $this->bdd->prepare('CALL noter_echec(?, ?)');
        $req->execute([$pseudo, $ipHash]);
    }

    public function effacerEchecs(string $pseudo): void
    {
        $req = $this->bdd->prepare('CALL effacer_echecs(?)');
        $req->execute([$pseudo]);
    }

    // on ne stocke que le sha256 du jeton
    public function creerJeton(int $joueurId, string $jeton): bool
    {
        $req = $this->bdd->prepare('SELECT creer_jeton(?, ?)');
        $req->execute([$joueurId, hash('sha256', $jeton)]);
        return (bool) $req->fetchColumn();
    }

    public function jetonValide(string $jeton): bool
    {
        $req = $this->bdd->prepare('SELECT jeton_valide(?)');
        $req->execute([hash('sha256', $jeton)]);
        return (bool) $req->fetchColumn();
    }
}
