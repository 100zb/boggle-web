<?php

require __DIR__ . '/../vendor/autoload.php';

use App\Config;
use App\Controller\AuthController;
use App\Controller\PageController;
use App\Controller\PartieController;
use App\Router;
use App\Session;
use App\Vue;

Config::charger(__DIR__ . '/../.env');

// en production : rien d'affiche, tout dans le journal
error_reporting(E_ALL);
ini_set('display_errors', Config::prod() ? '0' : '1');
ini_set('log_errors', '1');

header("Content-Security-Policy: default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'");
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: same-origin');
if (Config::prod()) {
    header('Strict-Transport-Security: max-age=31536000');
}

set_exception_handler(function (Throwable $e) {
    error_log((string) $e);
    http_response_code(500);
    $message = Config::prod() ? 'Une erreur est survenue, réessaie plus tard.' : $e->getMessage();
    Vue::afficher('erreur', ['message' => $message], 'Erreur');
});

Session::demarrer();

$routeur = new Router();
$routeur->get('/', [AuthController::class, 'accueil']);
$routeur->post('/connexion', [AuthController::class, 'connexion']);
$routeur->get('/inscription', [AuthController::class, 'formulaireInscription']);
$routeur->post('/inscription', [AuthController::class, 'inscription']);
$routeur->post('/deconnexion', [AuthController::class, 'deconnexion']);
$routeur->get('/mot-de-passe-oublie', [AuthController::class, 'formulaireOubli']);
$routeur->post('/mot-de-passe-oublie', [AuthController::class, 'oubli']);
$routeur->get('/reinitialiser', [AuthController::class, 'formulaireReinitialisation']);
$routeur->post('/reinitialiser', [AuthController::class, 'reinitialisation']);
$routeur->get('/parties', [PartieController::class, 'liste']);
$routeur->post('/parties/nouvelle', [PartieController::class, 'nouvelle']);
$routeur->get('/confidentialite', [PageController::class, 'confidentialite']);

$routeur->lancer($_SERVER['REQUEST_METHOD'], $_SERVER['REQUEST_URI']);
