<?php

namespace App;

class Router
{
    private array $routes = [];

    public function get(string $chemin, array $action): void
    {
        $this->routes['GET'][$chemin] = $action;
    }

    public function post(string $chemin, array $action): void
    {
        $this->routes['POST'][$chemin] = $action;
    }

    public function lancer(string $methode, string $uri): void
    {
        $chemin = rtrim(parse_url($uri, PHP_URL_PATH) ?: '/', '/') ?: '/';
        $action = $this->routes[$methode][$chemin] ?? null;

        if ($action === null) {
            http_response_code(404);
            Vue::afficher('erreur', ['message' => 'Cette page n\'existe pas.'], 'Page introuvable');
            return;
        }

        // un seul endroit pour verifier le jeton CSRF de tous les formulaires
        if ($methode === 'POST' && !Csrf::verifier()) {
            http_response_code(403);
            Vue::afficher('erreur', ['message' => 'Formulaire expiré, recharge la page et réessaie.'], 'Erreur');
            return;
        }

        [$classe, $fonction] = $action;
        (new $classe())->$fonction();
    }
}
