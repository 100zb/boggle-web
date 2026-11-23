<?php use App\Csrf; ?>
<section class="carte">
    <h1>Mot de passe oublié</h1>
    <p>Indique l'email de ton compte : tu recevras un lien pour choisir un nouveau mot de passe.</p>
    <form method="post" action="/mot-de-passe-oublie">
        <?= Csrf::champ() ?>
        <label for="email">Email</label>
        <input type="email" id="email" name="email" autocomplete="email" required maxlength="254" spellcheck="false">
        <button type="submit" class="bouton">Recevoir le lien</button>
    </form>
    <p class="aide">Si tu n'as pas donné d'email à l'inscription, ton mot de passe ne peut pas être récupéré.</p>
    <p class="liens"><a href="/">Retour à la connexion</a></p>
</section>
