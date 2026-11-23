<?php

namespace App;

use PDO;

class Database
{
    private static ?PDO $pdo = null;

    public static function get(): PDO
    {
        if (self::$pdo === null) {
            $dsn = sprintf(
                'pgsql:host=%s;port=%s;dbname=%s;sslmode=%s',
                Config::get('DB_HOST'),
                Config::get('DB_PORT', '5432'),
                Config::get('DB_NAME'),
                Config::get('DB_SSLMODE', 'require')
            );
            self::$pdo = new PDO($dsn, Config::get('DB_USER'), Config::get('DB_PASSWORD'), [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
        }
        return self::$pdo;
    }
}
