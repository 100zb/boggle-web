<?php

namespace App;

class Csrf
{
    public static function jeton(): string
    {
        if (empty($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf'];
    }

    public static function champ(): string
    {
        return '<input type="hidden" name="csrf" value="' . self::jeton() . '">';
    }

    public static function verifier(): bool
    {
        $recu = $_POST['csrf'] ?? null;
        return is_string($recu) && isset($_SESSION['csrf']) && hash_equals($_SESSION['csrf'], $recu);
    }
}
