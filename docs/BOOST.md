# FlowDrive : quel boost régler ?

Ce document s'adresse aux joueurs comme aux IA. Il explique comment choisir le réglage de boost FlowDrive pour une machine donnée.

## 1. Ce que fait le boost FlowDrive

Beaucoup de tracteurs modernes ont un **boost** : de la puissance en plus, disponible seulement dans certaines conditions. Exemples : Valtra Sigma Power, Fendt DynamicPerformance, John Deere IPM, Case IH / New Holland Power Management.

Dans FlowDrive, le boost est actif dans deux cas :
- **en travail à la prise de force** ;
- **en transport**, au-dessus de 16 km/h sans outil baissé. Il se coupe sous 12 km/h.

Le reste du temps, en traction au champ ou à basse vitesse, la machine a sa puissance de base.

FlowDrive agit sur le **couple** : il multiplie la courbe de couple du moteur.

## 2. Les trois réglages (menu FlowDrive, `Maj + Alt + T`)

| Réglage du menu | Valeurs |
|---|---|
| **Boost** | Désactivé, ou un pourcentage de 1 à 30 (bouton « Boost : saisir % ») |
| **Puissance du jeu** | **inclus** ou **en plus** |

- **inclus** : la puissance affichée par le jeu est **déjà la puissance boostée**. FlowDrive **retire** le boost quand il ne s'applique pas (couple ÷ (1 + %)). En boost, la machine a la puissance du jeu.
- **en plus** : la puissance affichée par le jeu est **la puissance de base**. FlowDrive **ajoute** le boost quand il s'applique (couple × (1 + %)).

## 3. Règle de décision

Il faut trois informations :
1. **la puissance de la machine dans le jeu**, en ch : affichée dans le menu FlowDrive (ligne « Puissance du jeu (… ch) », depuis la 1.0.2) et dans le magasin ;
2. **la puissance réelle de base** (nominale ou maximale sans boost), d'après la fiche du constructeur ;
3. **la puissance réelle avec boost**, si la machine en a un, et **ses conditions** (PdF, transport, vitesse).

Ensuite :

| Situation | Réglage |
|---|---|
| La vraie machine **n'a pas de boost** (puissance constante) | **Désactivé** |
| Machine non concernée : chargeuse, télescopique, automotrice, moissonneuse, camion, voiture, électrique | **Désactivé** |
| Puissance du jeu **proche de la puissance avec boost** | **inclus** |
| Puissance du jeu **proche de la puissance de base** | **en plus** |

**Le pourcentage :**
- si la fiche donne le **couple** maxi avec et sans boost : % = (couple boost − couple base) / couple base × 100 ;
- sinon, avec la **puissance** : % = (puissance boost − puissance base) / puissance base × 100 ;
- arrondi à l'entier ; entre 1 et 30. Les vrais boosts font en général de 5 à 20 %.

**Cas particulier :** sur une machine dont le boost agit presque tout le temps en travail (moissonneuse en battage, par exemple), le réglage n'apporte rien. Laisser **Désactivé**.

## 4. Ce qu'on sait du jeu de base (mesuré)

- La puissance affichée dans le magasin correspond au maximum de la courbe de couple du moteur.
- **Puissance du jeu = puissance avec boost** pour John Deere, Case IH Puma, Valtra T et Fendt 728.
- **Puissance du jeu = puissance sans boost** pour Massey Ferguson 7S et 9S.
- Les tracteurs de mods suivent ce que l'auteur du mod a choisi. Il faut donc toujours comparer avec la puissance du magasin.

## 5. Pour une IA qui lit ce document

Pour une machine donnée (marque, modèle, puissance dans le jeu) :
1. cherche la fiche constructeur ou un essai sérieux : puissance et couple de base, puissance et couple avec boost, conditions du boost ;
2. applique la règle de la section 3 avec **la puissance du jeu donnée par le joueur** : un même tracteur peut avoir une puissance différente d'un mod à l'autre ;
3. réponds avec : le réglage **Boost** (Désactivé ou un %), le réglage **Puissance du jeu** (inclus ou en plus), le calcul en une ligne et les sources ;
4. si tu ne trouves pas de chiffres fiables, dis-le et conseille **Désactivé**. Ne jamais inventer un boost.
