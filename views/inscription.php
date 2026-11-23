<?php use App\Csrf; ?>
<section class="carte carte-large">
    <h1>Créer un compte</h1>

    <?php if ($erreurs): ?>
        <div class="flash flash-erreur" role="alert">
            <ul>
                <?php foreach ($erreurs as $erreur): ?>
                    <li><?= e($erreur) ?></li>
                <?php endforeach; ?>
            </ul>
        </div>
    <?php endif; ?>

    <form method="post" action="/inscription">
        <?= Csrf::champ() ?>
        <label for="pseudo">Pseudo</label>
        <input type="text" id="pseudo" name="pseudo" value="<?= e($pseudo) ?>" autocomplete="username" required
               minlength="3" maxlength="30" pattern="[A-Za-z0-9_]{3,30}" aria-describedby="aide-pseudo"
               spellcheck="false" autocapitalize="off" autocorrect="off">
        <p class="aide" id="aide-pseudo">3 à 30 caractères : lettres sans accent, chiffres ou _. Il sera visible des autres joueurs.</p>

        <label for="email">Email <span class="facultatif">(facultatif)</span></label>
        <input type="email" id="email" name="email" value="<?= e($email) ?>" autocomplete="email" maxlength="254"
               aria-describedby="aide-email" spellcheck="false">
        <p class="aide" id="aide-email">Il sert uniquement à récupérer ton mot de passe. Sans email, un mot de passe oublié ne pourra pas être récupéré.</p>

        <label for="mdp">Mot de passe</label>
        <input type="password" id="mdp" name="mdp" autocomplete="new-password" required minlength="12" maxlength="72"
               aria-describedby="aide-mdp">
        <p class="aide" id="aide-mdp">Au moins 12 caractères, avec une minuscule, une majuscule, un chiffre et un caractère spécial. Une phrase est plus facile à retenir.</p>

        <label for="confirmation">Confirme le mot de passe</label>
        <input type="password" id="confirmation" name="confirmation" autocomplete="new-password" required minlength="12" maxlength="72">

        <div class="case">
            <input type="checkbox" id="consentement" name="consentement" value="oui" required>
            <label for="consentement">J'ai lu la <a href="/confidentialite">politique de confidentialité</a> et j'accepte que mes données soient utilisées pour faire fonctionner le jeu.</label>
        </div>

        <button type="submit" class="bouton">Créer mon compte</button>
    </form>
    <p class="liens"><a href="/">Déjà un compte ? Se connecter</a></p>
</section>
