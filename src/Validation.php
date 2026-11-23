<?php

namespace App;

class Validation
{
    // meme regle que le CHECK de la table joueur
    public static function pseudo(string $pseudo): ?string
    {
        if (!preg_match('/^[A-Za-z0-9_]{3,30}$/', $pseudo)) {
            return 'Le pseudo doit faire 3 à 30 caractères : lettres sans accent, chiffres ou _.';
        }
        return null;
    }

    public static function email(string $email): ?string
    {
        if ($email !== '' && (strlen($email) > 254 || !filter_var($email, FILTER_VALIDATE_EMAIL))) {
            return 'Adresse email invalide.';
        }
        return null;
    }

    // CNIL (deliberation 2022-100) : 80 bits d'entropie, ex. 12 caracteres avec les 4 types
    // 72 octets max : au-dela, bcrypt ignore la fin du mot de passe
    public static function motDePasse(string $mdp, string $confirmation, string $pseudo = ''): ?string
    {
        if (strlen($mdp) < 12 || strlen($mdp) > 72) {
            return 'Le mot de passe doit faire entre 12 et 72 caractères.';
        }
        if (!preg_match('/[a-z]/', $mdp) || !preg_match('/[A-Z]/', $mdp)
            || !preg_match('/[0-9]/', $mdp) || !preg_match('/[^A-Za-z0-9]/', $mdp)) {
            return 'Le mot de passe doit contenir une minuscule, une majuscule, un chiffre et un caractère spécial.';
        }
        if ($pseudo !== '' && stripos($mdp, $pseudo) !== false) {
            return 'Le mot de passe ne doit pas contenir ton pseudo.';
        }
        if ($mdp !== $confirmation) {
            return 'Les deux mots de passe sont différents.';
        }
        return null;
    }
}
