<?php

namespace App;

class Vue
{
    public static function afficher(string $nom, array $donnees = [], string $titre = 'Boggle'): void
    {
        extract($donnees);
        $flash = Session::lireFlash();
        ob_start();
        require __DIR__ . '/../views/' . $nom . '.php';
        $contenu = ob_get_clean();
        require __DIR__ . '/../views/layout.php';
    }
}
