<?php use App\Csrf; use App\Session; ?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= e($titre) ?></title>
    <link rel="stylesheet" href="/css/style.css">
    <link rel="icon" href="/img/de.svg" type="image/svg+xml">
</head>
<body>
<header class="entete">
    <a href="/" class="logo" aria-label="Boggle, retour à l'accueil">
        <span class="de">B</span><span class="de">O</span><span class="de">G</span><span class="de">G</span><span class="de">L</span><span class="de">E</span>
    </a>
    <?php if (Session::joueurId() !== null): ?>
        <div class="compte">
            <span>Connecté : <strong><?= e(Session::pseudo()) ?></strong></span>
            <form method="post" action="/deconnexion">
                <?= Csrf::champ() ?>
                <button type="submit" class="bouton bouton-discret">Se déconnecter</button>
            </form>
        </div>
    <?php endif; ?>
</header>

<main class="contenu">
    <?php if ($flash): ?>
        <p class="flash flash-<?= e($flash['type']) ?>" role="status"><?= e($flash['message']) ?></p>
    <?php endif; ?>
    <?= $contenu ?>
</main>

<footer class="pied">
    SAÉ S3 BUT Informatique · IUT de Marne-la-Vallée · <a href="/confidentialite">Données personnelles</a>
</footer>
</body>
</html>
