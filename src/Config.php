<?php

namespace App;

class Config
{
    // en local : lit le fichier .env ; en ligne les variables viennent de Render
    public static function charger(string $fichier): void
    {
        if (!is_file($fichier)) {
            return;
        }
        foreach (file($fichier, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $ligne) {
            $ligne = trim($ligne);
            if ($ligne === '' || $ligne[0] === '#' || !str_contains($ligne, '=')) {
                continue;
            }
            [$nom, $valeur] = explode('=', $ligne, 2);
            if (getenv(trim($nom)) === false) {
                putenv(trim($nom) . '=' . trim($valeur));
            }
        }
    }

    public static function get(string $nom, string $defaut = ''): string
    {
        $valeur = getenv($nom);
        return $valeur === false ? $defaut : $valeur;
    }

    // par defaut on est en production : il faut demander explicitement le mode dev
    public static function prod(): bool
    {
        return self::get('APP_ENV', 'prod') !== 'dev';
    }
}
