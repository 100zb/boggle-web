<?php use App\Csrf; use App\Session; ?>
<div class="titre-page">
    <h1>Salut <?= e(Session::pseudo()) ?> !</h1>
    <form method="post" action="/parties/nouvelle">
        <?= Csrf::champ() ?>
        <button type="submit" class="bouton">+ Nouvelle partie</button>
    </form>
</div>

<section>
    <h2>Parties ouvertes</h2>
    <table class="tableau">
        <thead>
        <tr><th>Salon</th><th>Grille</th><th>Joueurs</th><th>Statut</th><th></th></tr>
        </thead>
        <tbody>
        <?php foreach ($parties as $partie): ?>
            <tr>
                <td><?= e($partie['salon']) ?></td>
                <td><?= e($partie['taille']) ?></td>
                <td><?= $partie['joueurs'] ?> / <?= $partie['max'] ?></td>
                <td><span class="statut"><?= e($partie['statut']) ?></span></td>
                <td><button type="button" class="bouton bouton-petit" disabled>Rejoindre</button></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</section>

<section>
    <h2>Mes dernières parties</h2>
    <table class="tableau">
        <thead>
        <tr><th>Date</th><th>Salon</th><th>Score</th><th>Classement</th></tr>
        </thead>
        <tbody>
        <?php foreach ($historique as $ligne): ?>
            <tr>
                <td><?= e($ligne['date']) ?></td>
                <td><?= e($ligne['salon']) ?></td>
                <td><?= $ligne['score'] ?> pts</td>
                <td><?= e($ligne['rang']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
</section>

<p class="aide">Ces parties sont des exemples : les salons et l'historique arrivent dans la suite du projet.</p>
