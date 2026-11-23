<?php

namespace App\Controller;

class PageController extends Controller
{
    public function confidentialite(): void
    {
        $this->vue('confidentialite', [], 'Boggle - Confidentialité');
    }
}
