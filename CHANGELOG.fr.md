# Historique des versions

[English](CHANGELOG.md) · **Français**

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
