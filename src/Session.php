<?php

namespace App;

class Session
{
    private const INACTIVITE_MAX = 1800;

    public static function demarrer(): void
    {
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        session_name('boggle');
        session_set_cookie_params([
            'lifetime' => 0,
            'path' => '/',
            'secure' => Config::prod(),
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
        session_start();

        if (isset($_SESSION['joueur_id']) && time() - ($_SESSION['activite'] ?? 0) > self::INACTIVITE_MAX) {
            self::detruire();
            session_start();
            self::flash('Ta session a expiré, reconnecte-toi.');
        }
        $_SESSION['activite'] = time();
    }

    public static function connecter(int $id, string $pseudo): void
    {
        session_regenerate_id(true);
        $_SESSION['joueur_id'] = $id;
        $_SESSION['pseudo'] = $pseudo;
        unset($_SESSION['csrf']);
    }

    public static function joueurId(): ?int
    {
        return $_SESSION['joueur_id'] ?? null;
    }

    public static function pseudo(): ?string
    {
        return $_SESSION['pseudo'] ?? null;
    }

    public static function detruire(): void
    {
        $_SESSION = [];
        $p = session_get_cookie_params();
        setcookie(session_name(), '', [
            'expires' => time() - 3600,
            'path' => $p['path'],
            'secure' => $p['secure'],
            'httponly' => true,
            'samesite' => $p['samesite'],
        ]);
        session_destroy();
    }

    public static function flash(string $message, string $type = 'info'): void
    {
        $_SESSION['flash'] = ['message' => $message, 'type' => $type];
    }

    public static function lireFlash(): ?array
    {
        $flash = $_SESSION['flash'] ?? null;
        unset($_SESSION['flash']);
        return $flash;
    }
}
