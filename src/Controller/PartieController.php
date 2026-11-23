<?php

namespace App\Controller;

use App\Session;

class PartieController extends Controller
{
    public function liste(): void
    {
        $this->exigerConnexion();

        // parties fictives pour l'instant : les salons arrivent avec la suite de la SAE
        $parties = [
            ['salon' => 'Salon des amis', 'taille' => '4x4', 'joueurs' => 3, 'max' => 4, 'statut' => 'En attente'],
            ['salon' => 'Duel rapide', 'taille' => '4x4', 'joueurs' => 2, 'max' => 2, 'statut' => 'En cours'],
            ['salon' => 'Grande grille', 'taille' => '5x5', 'joueurs' => 1, 'max' => 6, 'statut' => 'En attente'],
        ];
        $historique = [
            ['date' => '21/11/2026', 'salon' => 'Salon des amis', 'score' => 14, 'rang' => '1er / 3'],
            ['date' => '19/11/2026', 'salon' => 'Duel rapide', 'score' => 6, 'rang' => '2e / 2'],
        ];

        $this->vue('parties', ['parties' => $parties, 'historique' => $historique], 'Boggle - Parties');
    }

    public function nouvelle(): void
    {
        $this->exigerConnexion();
        Session::flash('La création de partie arrive bientôt.');
        $this->rediriger('/parties');
    }
}
