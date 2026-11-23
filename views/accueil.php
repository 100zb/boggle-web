<?php use App\Csrf; ?>
<div class="accueil">
    <section class="presentation">
        <h1>Trouve un maximum de mots avant la fin du sablier</h1>
        <p>Une grille de dés, 3 minutes, et des mots à former en reliant des lettres voisines, même en diagonale. Joue seul ou contre tes amis.</p>
        <div class="grille" aria-hidden="true">
            <?php foreach (['E', 'U', 'E', 'S', 'O', 'I', 'N', 'I', 'I', 'J', 'E', 'L', 'M', 'I', 'A', 'E'] as $i => $lettre): ?>
                <span class="de<?= in_array($i, [9, 5, 4, 2], true) ? ' de-chemin' : '' ?>"><?= $lettre ?></span>
            <?php endforeach; ?>
        </div>
        <p class="legende">J-O-I-E : 4 lettres, 1 point.</p>
    </section>

    <section class="carte">
        <h2>Se connecter</h2>
        <form method="post" action="/connexion">
            <?= Csrf::champ() ?>
            <label for="pseudo">Pseudo</label>
            <input type="text" id="pseudo" name="pseudo" autocomplete="username" required maxlength="30"
                   spellcheck="false" autocapitalize="off" autocorrect="off">

            <label for="mdp">Mot de passe</label>
            <input type="password" id="mdp" name="mdp" autocomplete="current-password" required maxlength="72">

            <button type="submit" class="bouton">Se connecter</button>
        </form>
        <p class="liens">
            <a href="/mot-de-passe-oublie">Mot de passe oublié ?</a>
        </p>
        <p class="separation">Pas encore de compte ?</p>
        <a href="/inscription" class="bouton bouton-secondaire">Créer un compte</a>
    </section>
</div>
