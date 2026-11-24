<?php

namespace App\Controller;

use App\Config;
use App\Session;
use App\Vue;

abstract class Controller
{
    protected function vue(string $nom, array $donnees = [], string $titre = 'Boggle'): void
    {
        Vue::afficher($nom, $donnees, $titre);
    }

    protected function rediriger(string $chemin): void
    {
        header('Location: ' . $chemin);
        exit;
    }

    protected function exigerConnexion(): void
    {
        if (Session::joueurId() === null) {
            Session::flash('Connecte-toi pour accéder à cette page.');
            $this->rediriger('/');
        }
    }

    // un champ de formulaire peut arriver sous forme de tableau (pseudo[]=...) : on le refuse
    protected function champ(string $nom): string
    {
        $valeur = $_POST[$nom] ?? '';
        return is_string($valeur) ? $valeur : '';
    }

    // Render passe par Cloudflare : REMOTE_ADDR vaut ::1 pour tout le monde.
    // CF-Connecting-IP est rempli par Cloudflare (un client ne peut pas l'imposer),
    // alors que X-Forwarded-For peut etre invente par le client
    protected function ip(): string
    {
        $cloudflare = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? '';
        if (Config::get('DERRIERE_PROXY') === 'oui' && $cloudflare !== '') {
            return $cloudflare;
        }
        return $_SERVER['REMOTE_ADDR'] ?? '';
    }
}
