<?php use App\Csrf; ?>
<section class="carte">
    <h1>Nouveau mot de passe</h1>

    <?php if ($erreur): ?>
        <p class="flash flash-erreur" role="alert"><?= e($erreur) ?></p>
    <?php endif; ?>

    <form method="post" action="/reinitialiser">
        <?= Csrf::champ() ?>
        <input type="hidden" name="jeton" value="<?= e($jeton) ?>">

        <label for="mdp">Nouveau mot de passe</label>
        <input type="password" id="mdp" name="mdp" autocomplete="new-password" required minlength="12" maxlength="72"
               aria-describedby="aide-mdp">
        <p class="aide" id="aide-mdp">Au moins 12 caractères, avec une minuscule, une majuscule, un chiffre et un caractère spécial.</p>

        <label for="confirmation">Confirme le mot de passe</label>
        <input type="password" id="confirmation" name="confirmation" autocomplete="new-password" required minlength="12" maxlength="72">

        <button type="submit" class="bouton">Changer le mot de passe</button>
    </form>
</section>
