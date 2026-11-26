# FlowDrive : fonctionnement détaillé (1.2)

## Principe

FlowDrive ne réécrit jamais le régime ou le rapport après coup. Il **répond aux questions que le jeu pose au moteur** à chaque image, par des accroches sur `VehicleMotor` (`Utils.overwrittenFunction`). Chaque accroche appelle d'abord la fonction d'origine, et celles des autres mods (ADS compris), puis ajuste le résultat. Sur une machine où FlowDrive n'est pas actif, elle ne change rien.

| Accroche `VehicleMotor` | Ce que FlowDrive y fait |
|---|---|
| `getMinMaxGearRatio` | relève le rapport mini : gamme lente, approche lente, débit auto |
| `getAccelerationLimit` | accélération maxi de la rampe |
| `getMotorRotationAccelerationLimit` | vitesse de montée du régime selon la rampe |
| `getRequiredMotorRpmRange` | plafond de régime (éco, limite de charge, froid) ; planchers (régime mémorisé, hydraulique, approche, frein moteur) |
| `getTorqueCurveValue` | multiplie le couple (boost), puis `updateMotorProperties()` à chaque changement |

Là où le jeu ne passe pas par ces fonctions, FlowDrive écrit directement les champs du moteur :
- `ptoMotorRpmRatio` pour la PdF éco ;
- `lowBrakeForceScale` pour le frein pied levé ;
- `lastPtoRpm` pour tenir un régime boîte au neutre.

## Fichiers

| Fichier | Rôle |
|---|---|
| `modDesc.xml` | 13 actions (seul le menu a une touche par défaut), textes FR et EN |
| `scripts/FlowDriveMain.lua` | constantes, réglages généraux (`modSettings`), enregistrement de la spécialisation sur les types Motorized + Drivable (sauf locomotives), accroches moteur, touche de démarrage pour le préchauffage |
| `scripts/FlowDriveSpec.lua` | spécialisation `flowDrive` : état par machine, sauvegarde, éligibilité et profils, loi de conduite (`onUpdate`), préchauffage et froid, table DashboardLive, affichage, panneau de mesure, actions |
| `scripts/FlowDriveMenu.lua`, `gui/FlowDriveMenu.xml` | fenêtre de réglages (dérivée de `MessageDialog`) |
| `l10n/l10n_fr.xml`, `l10n/l10n_en.xml` | textes |

## Machines concernées et profils

| Profil | Machines | Régime hydraulique | Frein pied levé | Gamme lente |
|---|---|---|---|---|
| `cvt` | catégorie `TRACTOR*`, boîte non manuelle | 50 % de la plage | ×1,0 | champ, 55 % de la vitesse maxi |
| `hst` | chargeuses, télescopiques, compactes, chariots, mélangeuses automotrices | 60 % | ×1,5 | travail, 50 % |
| `harvester` | moissonneuses | 60 % (100 % en battage) | ×1,5 | récolte, 40 %, automatique en battage |

Les régimes sont donnés en part de la plage ralenti → nominal. L'électrique et les locomotives restent au jeu. Les boîtes à rapports fixes ont un traitement à part (section suivante). Si CVT Addon est actif sur une machine, FlowDrive ne fait rien sur celle-ci.

## Boîtes à rapports fixes (1.2)

Fichier `scripts/FlowDriveGears.lua`. Le jeu choisit le rapport dans `VehicleMotor:findGearChangeTargetGearPrediction` ; ses constantes de score sont locales à la fonction. FlowDrive appelle donc la fonction d'origine (et celles des autres mods), puis corrige le rapport renvoyé.

**Détection (lue dans le moteur, pas devinée) :** boîte continue si `minForwardGearRatio` existe, à rapports si `forwardGears` existe ; type de rapports et de gammes (`gearType`, `groupType`), passage manuel possible (`manualShiftGears`, `manualShiftGroups`). Résultat dans le log au chargement (`boite : …`).

**Quand FlowDrive agit :** rapports fixes, moteur non électrique, FlowDrive actif sur la machine, et `motor:getUseAutomaticGearShifting()` vrai (réglage de boîte du joueur sur automatique, ou véhicule qui ne se passe pas à la main). Si le joueur passe les rapports à la main, FlowDrive ne fait rien. Les gammes ne sont pas encore traitées. Côté serveur seulement.

**Rétrogradation sous charge :** si la charge moteur lissée reste au-dessus de 85 % pendant 0,8 s, accélérateur enfoncé, vitesse au-dessus de 2 km/h, et que le régime est sous celui qui garde 85 % de la puissance maxi, FlowDrive passe au rapport inférieur à condition que :
- le régime après passage reste sous ralenti + 82 % de la plage ;
- la puissance au nouveau régime soit au moins 5 % plus haute.

Après cette rétrogradation, la montée de rapport demandée par le jeu est refusée pendant 4 s, sauf au-dessus de ralenti + 92 % de la plage (pas de va-et-vient). Un seul rapport à la fois.

**Garde à la montée (anti va-et-vient) :** le jeu accepte des rapports qui ne donnent que 50 % de la puissance maxi, et peut monter de plusieurs rapports d'un coup ; le moteur peine alors, FlowDrive voudrait redescendre, et ça recommence. Quand la charge lissée dépasse 50 % et que l'accélérateur est enfoncé, FlowDrive calcule la charge que le moteur aurait après la montée (charge actuelle × puissance actuelle / puissance au nouveau régime). Si elle dépasse 80 % (sous le seuil de 85 % de la rétrogradation, donc sans va-et-vient), la montée est refusée ou réduite au rapport le plus haut qui passe. Réglage : « rétrograder sous charge ».

**Délai du jeu :** après une montée de rapport du jeu, le moteur de jeu annule pendant 3 s toute rétrogradation demandée à l'accélération (`allowGearChangeTimer`). FlowDrive ne la demande pas pendant ce délai (sinon la demande est perdue et loguée pour rien) et la fait dès qu'il est écoulé.

**Frein moteur (pied levé) :** accélérateur sous 5 % depuis 0,6 s, au-dessus de 6 km/h : rétrogradation si le régime est sous ralenti + 30 % de la plage (jusqu'à + 50 % avec une charge attelée lourde, même facteur de masse que le frein moteur des CVT) et que le régime après passage reste sous ralenti + 75 %. Deux rétrogradations de frein moteur de suite sont séparées d'au moins 1,5 s. La montée de rapport est alors refusée 2 s, sauf si le conducteur réaccélère. Le jeu ne rétrograde pied levé que sous 25 % de la plage (`findGearChangeTargetGearPrediction` donne un score nul aux rapports inférieurs au-dessus).

**Gammes automatiques** (`getUseAutomaticGroupShifting()`, gamme non verrouillée) :
- *montée :* au dernier rapport de la gamme, accélérateur enfoncé, régime à ralenti + 90 % de la plage (le jeu attend maxi − 50 tr/min). FlowDrive choisit dans la gamme suivante le rapport qui donne le plus de puissance sous ralenti + 82 %, à condition que le moteur reste sous 80 % de charge après le passage. Le changement se fait avec `VehicleMotor:setGearGroup`, comme le jeu ;
- *descente :* au rapport 1 de la gamme, même condition de charge que la rétrogradation, on prend dans la gamme inférieure le plus grand rapport qui donne au moins 5 % de puissance en plus sous ralenti + 82 % ;
- 4 s minimum entre deux changements de gamme ; pas de changement de gamme entre marche avant et arrière.

Réglages généraux (menu, ceux de l'hôte en multijoueur) : « rétrograder sous charge », « frein moteur », « gammes automatiques ».

**Ce que le jeu fait déjà (lu dans `updateGear`)** : après un changement de rapport, il interdit 3 s une rétrogradation à l'accélération si le dernier passage était une montée (`allowGearChangeTimer`). La rétrogradation sous charge de FlowDrive passe donc après ce délai.

## Loi de conduite

Un mode décide du régime visé. La valeur est ensuite lissée (montée en 0,4 s, descente en 2,5 s).

| Mode | Régime visé |
|---|---|
| régime mémorisé | celui de la mémoire (65 et 90 % de la plage par défaut, réglables par pas de 50 tr/min) |
| prise de force | régime de PdF + 3 % |
| pied levé | régime éco mini, plus un frein moteur selon la rampe |
| limite de charge | après 1,5 s de pleine charge sans accélérer : −15 % en transport, −25 % en traction |
| accélération | charge visée 70 %, au moins le régime de la rampe |
| éco | charge visée 80 % |

Ensuite :
1. le régime ne descend jamais sous celui qu'il faut pour tenir la vitesse au rapport mini (+5 %) ;
2. il respecte les planchers hydraulique et approche lente ;
3. il est plafonné quand le moteur est froid.

## Rampes

| Rampe | Accélération maxi | Usage |
|---|---|---|
| 1 | 0,4 m/s² | très doux |
| 2 | 0,8 m/s² | travail, forte charge |
| 3 | 1,3 m/s² | transport à vide |
| 4 | 2,0 m/s² | chargeuse |

**Auto** (réglage par défaut) :
- rampe 4 sur une HST ;
- sur une moissonneuse : 2 en battage, 3 sinon ;
- sur un tracteur : 2 avec un outil baissé, la PdF, ou une masse totale supérieure à 2 fois celle du tracteur ; 3 sinon.

La situation doit durer 2 s avant que la rampe change. Moteur froid : rampe 2 au plus.

## Boost

Voir [BOOST.md](BOOST.md). Il est actif en PdF, ou en transport au-dessus de 16 km/h (coupé sous 12 km/h), avec au moins 1,5 s entre deux changements.
- Mode « inclus » : couple × 1/(1 + %) hors boost.
- Mode « en plus » : couple × (1 + %) en boost.

## Froid

- **Préchauffage :** il part à l'appui sur la touche de démarrage quand l'air est sous 5 °C et le moteur sous 30 °C. Il dure 2 s, plus 0,52 s par degré sous 5 °C, au plus 15 s. Le moteur démarre tout seul à la fin. Avec le démarrage automatique du jeu, il part en montant dans la machine.
- **Moteur froid :** sous 50 °C avec ADS (40 °C sans), le régime est plafonné à 72 % du maxi et la rampe à 2. Cela se lève 2 °C au-dessus du seuil. La PdF reste prioritaire.
- **Température utilisée :** celle d'ADS s'il est installé, sinon celle du jeu.

## Autres fonctions

- **PdF éco :** `ptoMotorRpmRatio` × 0,78, comme un boîtier 540E / 1000E.
- **Régime hydraulique :** quand un vérin bouge (sur la machine ou un outil attelé), le régime monte. Il est maintenu 0,8 s, puis redescend en 1 s.
- **Approche lente** (touche tenue) : la vitesse maxi baisse de 5 km/h par seconde, jusqu'à 1 km/h, en gardant le régime.
- **Débit auto** (moissonneuses) : la vitesse visée baisse au-dessus de 90 % de charge moteur et remonte sous 75 %.
- **Gamme :** le changement est refusé au-dessus de 10 km/h.
- **Frein pied levé :** `lowBrakeForceScale` × facteur de rampe × √(masse propre / masse totale) × multiplicateur du profil. Avec EngineBrakeforceCompensation, FlowDrive repart de la valeur d'origine.
- **DashboardLive :** FlowDrive crée `vehicle.spec_CVTaddon` avec les champs `forDBL_*` que lisent les écrans, seulement si CVT Addon n'est pas là.

## Multijoueur (1.1, expérimental)

- **Qui calcule quoi :** le jeu n'appelle les accroches de boîte que sur le serveur. La loi de conduite (rampes, régime, gammes, boost, débit auto, moteur froid) tourne donc sur le serveur (`self.isServer`). Chez un joueur qui a rejoint la partie, FlowDrive ne fait que l'affichage, DashboardLive et les messages.
- **Réglages par machine :** `FlowDriveSettingsEvent` (fichier `scripts/FlowDriveEvents.lua`). Le joueur qui change un réglage l'envoie ; le serveur l'applique et le transmet aux autres. Un joueur qui arrive reçoit tous les réglages (`onWriteStream` / `onReadStream`).
- **Commandes du joueur :** `FlowDriveInputEvent`, du joueur vers le serveur, quand l'approche lente ou un vérin change d'état. Le serveur ne voit pas les commandes de vérin d'un joueur distant, seulement leur position.
- **État d'affichage :** le serveur compare l'état au plus toutes les 250 ms et ne l'envoie que s'il a changé (`onWriteUpdateStream`) : rampe auto, gamme active, moteur froid, boost appliqué, PdF, régime mémorisé, débit auto, limite de charge, approche, hydraulique, température moteur (arrondie au demi-degré), préchauffage, et les trois réglages de l'hôte.
- **Préchauffage :** avec la touche de démarrage, la minuterie tourne chez le joueur, puis le moteur démarre par l'événement du jeu. Avec le démarrage automatique, c'est le serveur qui démarre : il fait le préchauffage et l'envoie au joueur.
- **Réglages généraux :** hydraulique, préchauffage et protection froid agissent sur la conduite ; ceux de l'hôte s'appliquent à tous. Affichage, position et DashboardLive restent propres à chaque joueur.
- **Log :** en multijoueur, `[FlowDrive][hote]`, `[FlowDrive][serveur]` (serveur dédié) ou `[FlowDrive][joueur]`. Au lancement : `partie lancee : role=… multijoueur=…`. Réglages : `reglages envoyes` et `reglages recus`.

## Ce qu'on sait du moteur FS25 (mesuré ou lu)

- Les accroches sont appelées à chaque image. La vitesse vaut environ k × régime / rapport.
- `getAccelerationLimit` limite l'accélération, pas le ralentissement.
- Pied levé, au-dessus de 3,6 km/h, le jeu freine avec `lowBrakeForceScale`.
- Le régime de PdF est imposé dans `VehicleMotor:update` (`getMaxPtoRpm × ptoMotorRpmRatio`).
- Boîte au neutre, le régime suit max(`lastPtoRpm`, `minRpm`) et ignore `getRequiredMotorRpmRange`.
- Le jeu appelle `getMotorNotAllowedWarning` aussi pour l'aide des touches : cette fonction ne doit rien déclencher.
- Multijoueur : la conduite (`updateVehiclePhysics`, donc les accroches de boîte) ne tourne que sur le serveur, et la température moteur du jeu n'est calculée que sur le serveur (voir la section Multijoueur).
