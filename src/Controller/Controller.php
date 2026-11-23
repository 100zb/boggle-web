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

    // derriere le proxy de Render, la vraie ip est la derniere ajoutee dans X-Forwarded-For
    protected function ip(): string
    {
        $transmis = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
        if (Config::get('DERRIERE_PROXY') === 'oui' && $transmis !== '') {
            $ips = explode(',', $transmis);
            return trim(end($ips));
        }
        return $_SERVER['REMOTE_ADDR'] ?? '';
    }
}
