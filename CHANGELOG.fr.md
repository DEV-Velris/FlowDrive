# Historique des versions

[English](CHANGELOG.md) · **Français**

## 1.2.0.0
- **Boîtes à rapports fixes (powershift, semi-powershift, boîtes manuelles utilisées en automatique).** Rétrogradation automatique sous charge. Quand le moteur reste très chargé sous le régime qui garde 85 % de la puissance maxi, FlowDrive demande le rapport inférieur s'il donne plus de puissance et laisse de la marge avant le régime maxi. Une montée de rapport est refusée pendant 4 s après cette rétrogradation (pas de va-et-vient).
- FlowDrive n'agit que si le jeu passe lui-même les rapports (réglage de boîte sur automatique, ou véhicule qui ne se passe pas à la main). Un joueur qui passe les rapports à la main n'est jamais touché.
- **Garde à la montée.** Le jeu accepte des rapports qui ne donnent que 50 % de la puissance maxi et peut monter de plusieurs rapports d'un coup : sous charge, il monte dans un rapport où le moteur peine, puis redescend. FlowDrive refuse (ou réduit) maintenant une montée si le moteur dépasserait 80 % de charge après. Il ne demande plus non plus de rétrogradation pendant les 3 s où le jeu l'annule après une montée.
- Frein moteur : au moins 1,5 s entre deux rétrogradations successives. Les lignes du log indiquent la gamme active, et les changements de gamme faits par le jeu sont journalisés (`gammes : … jeu gamme a -> b`).
- **Frein moteur.** Pied levé depuis 0,6 s au-dessus de 6 km/h, la boîte rétrograde quand le régime passe sous 30 % de la plage (jusqu'à 50 % avec une charge lourde attelée), si le régime après passage reste sous 75 % de la plage. Le jeu ne le faisait que sous 25 %.
- **Gammes automatiques.** Montée de la gamme depuis le dernier rapport à 90 % de la plage de régime (le jeu attend 50 tr/min sous le maxi), dans le rapport qui donne le plus de puissance, seulement si le moteur reste sous 80 % de charge. Descente de gamme quand le moteur peine sous charge au rapport le plus bas. Au moins 4 s entre deux changements de gamme.
- Trois nouveaux réglages généraux (menu, ceux de l'hôte en multijoueur) : rétrograder sous charge, frein moteur, gammes automatiques.
- Le choix marche/arrêt du menu et la touche existent aussi sur ces véhicules ; la bulle d'aide du menu donne l'état. Les autres fonctions (rampes, gammes, PdF, boost…) ne sont pas disponibles sur les boîtes à rapports fixes.
- Une ligne de log par véhicule au chargement (`boite : …`) indique ce que le moteur dit de la boîte et ce que FlowDrive en fait. Avec la touche de mesure (debug), chaque changement de rapport est journalisé (`rapports : …`), celui du jeu comme celui de FlowDrive.

## 1.1.0.0
- **Multijoueur (expérimental).** Les réglages de chaque machine (touches et menu) sont envoyés au serveur et aux autres joueurs, ainsi qu'au joueur qui rejoint la partie.
- En multijoueur, le serveur calcule la boîte. Il envoie aux joueurs ce qu'il faut pour l'affichage, DashboardLive et les messages (rampe auto, gamme active, moteur froid, boost, température moteur, préchauffage).
- L'approche lente et le régime hydraulique automatique fonctionnent aussi pour un joueur qui a rejoint la partie.
- L'hydraulique, le préchauffage et la protection froid suivent les réglages de l'hôte (grisés dans le menu des autres joueurs).
- Les messages ne s'affichent plus qu'au joueur assis dans la machine (plus de messages venant de la machine d'un ouvrier).
- En multijoueur, les lignes du log indiquent le rôle : `[FlowDrive][hote]`, `[FlowDrive][serveur]` ou `[FlowDrive][joueur]`. Rien ne change en solo.

## 1.0.2.0
- Le menu affiche la puissance de la machine dans le jeu, sur la ligne « Puissance du jeu (… ch) », pour la comparer à la vraie fiche et choisir le boost.
- Bulles d'aide du boost mises à jour (vrais boosts : 5 à 20 %).
- Commentaires du code en anglais. Le comportement ne change pas.

## 1.0.1.0
- Préchauffage : il ne part plus en montant dans une machine froide. Il part à l'appui sur la touche de démarrage (Entrée), puis le moteur démarre. Il part en montant seulement si le démarrage automatique du jeu est activé.
- Correction : en 1.0.0, le moteur pouvait démarrer tout seul après un préchauffage, sans appui sur la touche.

## 1.0.0.0
- Titre et description définitifs.
- Seul le menu garde une touche par défaut (`Maj + Alt + T`). Le panneau de mesure et l'essai froid peuvent recevoir une touche dans les commandes.

## 0.8.0
- Boost désactivé par défaut sur toutes les machines.
- Pourcentage de boost saisi au clavier (1 à 30, 0 = désactivé).
- Nouveau réglage « Puissance du jeu » : inclus ou en plus.
- Rampe **Auto** par défaut : la rampe est choisie selon le travail, la charge et le type de machine.

## 0.7.0
- Compatibilité vérifiée avec ADS, Courseplay, EngineBrakeforceCompensation et DashboardLive.
- Changement de gamme refusé au-dessus de 10 km/h.

## 0.6.x
- Menu de réglages, affichage à l'écran, écrans DashboardLive, textes FR et EN.
- Mesure de consommation corrigée.

## 0.5.0
- Préchauffage, protection moteur froid, température d'ADS, mode essai froid.

## 0.4.x
- Moissonneuses : gammes récolte et route, débit auto.

## 0.3.x
- Chargeuses, télescopiques et automotrices (profil HST), régime hydraulique, approche lente.

## 0.2.x
- PdF éco, régimes mémorisés, boost.

## 0.1.x
- CVT de tracteur : rampes, régime éco, limite de charge, gamme champ, frein moteur.
