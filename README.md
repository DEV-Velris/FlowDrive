# FlowDrive

Mod pour **Farming Simulator 25** : un comportement réaliste des boîtes à variation continue (CVT) et hydrostatiques (HST). Il s'applique à toutes les machines compatibles, sans rien à acheter ni à configurer.

- Version : **1.0.1.0**
- Solo uniquement (le multijoueur est prévu en 1.1).
- **Ne pas utiliser avec CVT Addon.** Les deux modifient la même chose. Si CVT Addon est actif sur une machine, FlowDrive ne fait rien sur celle-ci.

## Ce que fait le mod

| Machines | Fonctions |
|---|---|
| Tracteurs (CVT) | Rampes d'accélération (Auto ou 1 à 4) ; régime éco ; limite de charge ; gammes champ et route ; frein moteur adapté au poids attelé ; PdF éco ; régimes mémorisés ; boost réglable |
| Chargeuses, télescopiques, automotrices (HST) | Régime hydraulique automatique quand un vérin bouge ; gamme travail ; approche lente |
| Moissonneuses | Gammes récolte et route (récolte automatique en battage) ; débit auto (la vitesse baisse quand le moteur sature) |
| Toutes | Préchauffage à la touche de démarrage par temps froid ; protection moteur froid ; écrans DashboardLive qui lisaient CVT Addon |

Les boîtes manuelles, les machines électriques et les locomotives restent gérées par le jeu.

Le fonctionnement détaillé est dans [docs/FONCTIONNEMENT.md](docs/FONCTIONNEMENT.md).

## Réglages

- **Menu FlowDrive : `Maj gauche + Alt gauche + T`**, dans la machine. Il permet de régler, pour chaque machine : marche, rampe, gamme, PdF éco, régime mémorisé, boost, puissance du jeu (boost inclus ou en plus) et débit auto. Il contient aussi les réglages généraux : hydraulique, préchauffage, protection froid, affichage, DashboardLive.
- Les autres fonctions n'ont pas de touche par défaut. On peut leur en donner une dans *Options → Commandes* (lignes « FlowDrive : … ») :
  - rampe suivante ;
  - gamme suivante ;
  - PdF éco ;
  - régime mémorisé (arrêt / 1 / 2), + et − ;
  - boost ;
  - débit auto ;
  - approche lente (touche tenue) ;
  - marche / arrêt ;
  - panneau de mesure ;
  - essai froid.

Les réglages par machine sont enregistrés dans la sauvegarde. Les réglages généraux vont dans `modSettings/FS25_FlowDrive.xml`.

## Quel boost régler ?

Le boost est **désactivé par défaut**. Pour savoir quoi mettre sur un tracteur, voir [docs/BOOST.md](docs/BOOST.md). Ce document donne la règle de décision et la liste des machines déjà vérifiées. Il est écrit pour être lu aussi par une IA : on lui donne le lien, la marque, le modèle et la puissance affichée dans le magasin du jeu.

## Compatibilité testée

- Advanced Damage System (stable et beta) : FlowDrive utilise sa température moteur.
- Courseplay : FlowDrive s'applique aussi aux ouvriers.
- DashboardLive.
- EngineBrakeforceCompensation.
- ValtraPackage.

## Contenu du dépôt

| Dossier | Contenu |
|---|---|
| `FS25_FlowDrive/` | le mod, tel qu'il est zippé |
| `docs/` | fonctionnement détaillé, guide du boost |
| `tools/` | `build.ps1` (fabrique le zip), `luacheck_blocks.js` (vérifie la structure des fichiers Lua) |
| `CHANGELOG.md` | historique des versions |

## Fabriquer le zip

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

Le script vérifie les fichiers Lua (si Node.js est installé). Il crée ensuite `dist/FS25_FlowDrive.zip` et une copie numérotée `dist/FS25_FlowDrive_<version>.zip`. Pour installer, copier `FS25_FlowDrive.zip` dans le dossier `mods`, **jeu fermé**.

## Auteur

Velris
