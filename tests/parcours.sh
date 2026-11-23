#!/bin/bash
# test du parcours complet : ./parcours.sh http://localhost:8000
U=${1:-http://localhost:8000}
J=/tmp/cj.txt; rm -f $J
ok() { echo "OK   $1"; }; ko() { echo "FAIL $1"; FAIL=1; }
csrf() { curl -s -b $J -c $J "$U$1" | grep -o 'name="csrf" value="[^"]*"' | head -1 | cut -d'"' -f4; }
post() { local p=$1; shift; curl -s -b $J -c $J -o /tmp/rep.html -w "%{http_code} %{redirect_url}" "$U$p" "$@"; }
suivre() { curl -s -b $J -c $J "$U$1"; }
P="ali_$RANDOM"; MDP='Boggle-Test-2026!'; MAIL="$P@test.fr"

T=$(csrf /inscription)
[[ $(post /inscription --data-urlencode "pseudo=$P" --data-urlencode "mdp=$MDP" --data-urlencode "confirmation=$MDP") == 403* ]] && ok "POST sans jeton CSRF -> 403" || ko "csrf"
post /inscription --data-urlencode "csrf=$T" --data-urlencode "pseudo=$P" --data-urlencode "mdp=azerty" --data-urlencode "confirmation=azerty" --data-urlencode "consentement=oui" >/dev/null
grep -q "entre 12 et 72" /tmp/rep.html && ok "mot de passe faible refuse" || ko "mdp faible"
post /inscription --data-urlencode "csrf=$T" --data-urlencode "pseudo=<script>" --data-urlencode 'email="><script>alert(1)</script>' --data-urlencode "mdp=$MDP" --data-urlencode "confirmation=$MDP" >/dev/null
grep -q '<script>alert' /tmp/rep.html && ko "XSS reflete" || ok "XSS : saisie echappee ($(grep -o '&quot;&gt;&lt;script&gt;' /tmp/rep.html | head -1))"
grep -q "politique de confidentialit" /tmp/rep.html && grep -q "Le pseudo doit" /tmp/rep.html && ok "consentement + pseudo invalide refuses" || ko "validations"
S1=$(grep boggle $J | awk '{print $7}')
R=$(post /inscription --data-urlencode "csrf=$T" --data-urlencode "pseudo=$P" --data-urlencode "email=$MAIL" --data-urlencode "mdp=$MDP" --data-urlencode "confirmation=$MDP" --data-urlencode "consentement=oui")
[[ $R == *"/parties" ]] && ok "inscription -> /parties" || ko "inscription ($R)"
S2=$(grep boggle $J | awk '{print $7}'); [[ $S1 != $S2 ]] && ok "id de session change a la connexion" || ko "regenerate"
suivre /parties | grep -q "Salut $P" && ok "page 2 affiche le pseudo" || ko "page 2"
T=$(csrf /inscription)
post /inscription --data-urlencode "csrf=$T" --data-urlencode "pseudo=${P^^}" --data-urlencode "mdp=$MDP" --data-urlencode "confirmation=$MDP" --data-urlencode "consentement=oui" >/dev/null
grep -q "déjà pris" /tmp/rep.html && ok "meme pseudo en majuscules refuse" || ko "pseudo double"
T=$(csrf /parties); [[ $(post /deconnexion --data-urlencode "csrf=$T") == 302* ]] && ok "deconnexion" || ko "deconnexion"
[[ $(curl -s -b $J -o /dev/null -w "%{http_code}" $U/parties) == 302 ]] && ok "page 2 refusee apres deconnexion" || ko "acces apres deconnexion"

T=$(csrf /); post /connexion --data-urlencode "csrf=$T" --data-urlencode "pseudo=${P^^}" --data-urlencode "mdp=$MDP" >/dev/null
suivre /parties | grep -q "Salut $P" && ok "connexion (pseudo en majuscules)" || ko "connexion"
T=$(csrf /parties); post /deconnexion --data-urlencode "csrf=$T" >/dev/null

T=$(csrf /); post /connexion --data-urlencode "csrf=$T" --data-urlencode "pseudo=inconnu_$RANDOM" --data-urlencode "mdp=x" >/dev/null
M1=$(suivre / | grep -o 'Pseudo ou mot de passe incorrect')
for i in 1 2 3 4 5; do T=$(csrf /); post /connexion --data-urlencode "csrf=$T" --data-urlencode "pseudo=$P" --data-urlencode "mdp=mauvais$i" >/dev/null; done
T=$(csrf /); post /connexion --data-urlencode "csrf=$T" --data-urlencode "pseudo=$P" --data-urlencode "mdp=$MDP" >/dev/null
[[ -n $M1 ]] && ok "pseudo inconnu : meme message que mauvais mot de passe" || ko "message"
suivre / | grep -q "Trop de tentatives" && ok "bloque apres 5 echecs, meme avec le bon mot de passe" || ko "limitation"

rm -f /tmp/mails/box/new/* 2>/dev/null
T=$(csrf /mot-de-passe-oublie); post /mot-de-passe-oublie --data-urlencode "csrf=$T" --data-urlencode "email=personne_$RANDOM@test.fr" >/dev/null; A=$(suivre /)
T=$(csrf /mot-de-passe-oublie); post /mot-de-passe-oublie --data-urlencode "csrf=$T" --data-urlencode "email=${MAIL^^}" >/dev/null; B=$(suivre /)
[[ $(echo "$A" | grep -o 'Si un compte[^<]*') == $(echo "$B" | grep -o 'Si un compte[^<]*') ]] && ok "oubli : meme message email connu / inconnu" || ko "enumeration"
sleep 1; LIEN=$(cat /tmp/mails/box/new/* 2>/dev/null | grep -o 'http[^ ]*reinitialiser?jeton=[0-9a-f]*' | tail -1)
[[ -n $LIEN ]] && ok "email recu : ${LIEN:0:60}..." || ko "email"
[[ $(ls /tmp/mails/box/new | wc -l) == 1 ]] && ok "un seul email (rien pour l'adresse inconnue)" || ko "nb emails"
JETON=${LIEN##*=}
suivre "/reinitialiser?jeton=$JETON" | grep -q "Nouveau mot de passe" && ok "lien ouvre le formulaire" || ko "formulaire reinit"
NOUV='Nouveau-Boggle-2027?'
T=$(csrf "/reinitialiser?jeton=$JETON"); post /reinitialiser --data-urlencode "csrf=$T" --data-urlencode "jeton=$JETON" --data-urlencode "mdp=$NOUV" --data-urlencode "confirmation=$NOUV" >/dev/null
suivre / | grep -q "Mot de passe chang" && ok "mot de passe change" || ko "reinit"
suivre "/reinitialiser?jeton=$JETON" | grep -q "plus valable" && ok "lien inutilisable une 2e fois" || ko "usage unique"
T=$(csrf /); post /connexion --data-urlencode "csrf=$T" --data-urlencode "pseudo=$P" --data-urlencode "mdp=$NOUV" >/dev/null
suivre /parties | grep -q "Salut $P" && ok "connexion avec le nouveau mot de passe (compte debloque)" || ko "connexion apres reinit"
T=$(csrf /parties); [[ $(post /parties/nouvelle --data-urlencode "csrf=$T") == *"/parties" ]] && ok "bouton nouvelle partie" || ko "nouvelle partie"
exit ${FAIL:-0}
