<?php

// tout ce qui est affiche passe par e() (protection XSS)
function e(?string $texte): string
{
    return htmlspecialchars($texte ?? '', ENT_QUOTES, 'UTF-8');
}
