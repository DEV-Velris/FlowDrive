# FlowDrive

[English](README.md) · **Français**

Mod pour **Farming Simulator 25** : un comportement réaliste des boîtes à variation continue (CVT) et hydrostatiques (HST). Il s'applique à toutes les machines compatibles, sans rien à acheter ni à configurer.

- Site et assistant boost : **https://dev-velris.github.io/FlowDrive/**
- Version : **1.0.2.0** ([historique des versions](CHANGELOG.fr.md))
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

Le boost est **désactivé par défaut**. Le menu affiche la puissance de la machine dans le jeu, sur la ligne « Puissance du jeu (… ch) ». Il suffit de la comparer à la fiche réelle du tracteur. La règle de décision et les machines déjà vérifiées sont dans [docs/BOOST.md](docs/BOOST.md). L'[assistant boost](https://dev-velris.github.io/FlowDrive/#boost) prépare la question pour une IA (Google mode IA, ChatGPT, Claude, Perplexity) à partir de la marque, du modèle et de la puissance du jeu.

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
| `docs/` | site (`index.html`, publié par GitHub Pages), fonctionnement détaillé, guide du boost (en français) |
| `tools/` | `build.ps1` (fabrique le zip), `luacheck_blocks.js` (vérifie la structure des fichiers Lua) |

## Fabriquer le zip

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

Le script vérifie les fichiers Lua (si Node.js est installé). Il crée ensuite `dist/FS25_FlowDrive.zip` et une copie numérotée `dist/FS25_FlowDrive_<version>.zip`. Pour installer, copier `FS25_FlowDrive.zip` dans le dossier `mods`, **jeu fermé**. Le nom du zip ne doit pas changer : le jeu reconnaît un mod à ce nom.

## Auteur

Velris
