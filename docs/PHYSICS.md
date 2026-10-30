# Modèle physique — SPIN ARENA

Auteur : Archimedes. Date : 18 octobre 2026. Phase 0 : **conception uniquement**.

Rien dans ce document n'est implémenté ni testé. Toutes les valeurs numériques sont des **hypothèses de départ** à mesurer et calibrer en phase 1 avec les tests de [TEST_PLAN.md](TEST_PLAN.md). Ce document ne prétend pas que le moteur est déterministe entre machines ni synchronisé entre clients.

## 1. Décision principale

La manche est simulée par un **modèle mathématique 2D écrit en Lua standard, exécuté uniquement par le serveur**. On n'utilise pas la physique native de GTA.

Pourquoi :

- La physique GTA des petits objets est calculée par le client propriétaire de l'entité. Avec OneSync, le serveur ne simule pas cette physique : il reçoit des positions envoyées par les clients. Le résultat dépendrait donc d'un client, ce que le cahier des charges interdit (§5.2, §7).
- Les petits objets GTA à haute vitesse traversent les collisions, s'endorment ou rebondissent de façon instable selon le FPS.
- Un modèle pur (sans native, sans horloge, sans entité) se teste hors du jeu avec `lua5.4`, présent sur l'hôte d'après [AUDIT.md](AUDIT.md).

Ce qu'on accepte de perdre : pas de vraie 3D (pas de saut, pas de basculement visible calculé), pas de géométrie détaillée des pièces. La hauteur, l'inclinaison et l'oscillation sont des **paramètres** du modèle 2D, rendus visuellement par le client.

## 2. Repère et unités

- Repère local à l'arène : origine au centre de la cuvette, axes `x`, `y` horizontaux, en mètres. Le client convertit en coordonnées monde avec le centre, le cap et l'échelle de l'arène (voir [ARCHITECTURE.md](ARCHITECTURE.md) §9).
- Unités SI : m, s, kg, rad, rad/s, J, N·s.
- Le moteur n'utilise pas `vector3`/`vec2` de CfxLua (indisponibles dans `lua5.4`) : uniquement des nombres.
- Rayons de collision et dimensions visuelles doivent correspondre : les valeurs finales dépendent des modèles prévus par Fermi dans [ART_AND_UI.md](ART_AND_UI.md). Les valeurs ci-dessous supposent une cuvette « de table » de 1,2 m de diamètre pour rester lisible dans GTA.

## 3. État simulé

Par toupie `i` :

| Champ | Sens | Unité |
|---|---|---|
| `x, y` | position horizontale | m |
| `vx, vy` | vitesse horizontale | m/s |
| `w` | vitesse de rotation (toujours ≥ 0) | rad/s |
| `dir` | sens de rotation : `+1` ou `-1` | — |
| `ang` | angle de rotation, modulo 2π | rad |
| `wob` | oscillation (instabilité), de 0 à 1 | — |
| `status` | `spinning`, `stopping`, `stopped`, `ejected` | — |
| `stopSince` | pas où la condition d'arrêt a commencé | pas |

L'énergie de rotation se déduit : `E = 0,5 · kI · m · r² · w²`.

Par manche : numéro de pas, état du générateur pseudo-aléatoire, temps de recharge des contacts par paire, liste des événements, keyframes.

## 4. Caractéristiques d'entrée

Le moteur reçoit des caractéristiques **déjà calculées et bornées par le serveur** à partir des pièces enregistrées en base (`shared/stats.lua`, [ARCHITECTURE.md](ARCHITECTURE.md) §5). Il ne lit jamais une donnée client. Il refuse de démarrer si une valeur est absente, non finie ou hors borne.

| Caractéristique | Rôle | Bornes proposées |
|---|---|---|
| `m` masse | inertie aux chocs | 0,035 – 0,065 kg |
| `r` rayon de contact | collisions | 0,040 – 0,060 m |
| `kI` répartition de masse | réserve d'énergie (0,5 = disque plein, 0,7 = masse en périphérie) | 0,45 – 0,75 |
| `atk` attaque | force des impacts donnés, rebond | 0 – 1 |
| `def` défense | résistance aux pertes d'énergie et à l'oscillation | 0 – 1 |
| `stab` stabilité | vitesse sous laquelle l'oscillation commence | 0 – 1 |
| `tipFric` friction de pointe | perte de rotation constante | 2,0 – 7,0 rad/s² |
| `mob` mobilité | vitesse d'orbite visée | 0,1 – 1,8 m/s |
| `trac` adhérence | rapidité à atteindre l'orbite | 0,5 – 3,0 s⁻¹ |
| `damp` amortissement | perte de vitesse horizontale | 0,15 – 0,8 s⁻¹ |
| `w0` rotation de lancement | réserve initiale | 200 – 300 rad/s |
| `v0` vitesse de lancement | entrée dans la cuvette | 0,3 – 0,9 m/s |

`w0` et `v0` viennent du lanceur et de la toupie, pas d'une saisie du joueur. Pas de mini-jeu d'adresse en v1 : une animation ne donne aucun avantage caché (§5.1 du cahier).

Les effets cosmétiques n'apparaissent jamais dans ce tableau.

## 5. Pas de temps et ordre d'un pas

Pas fixe proposé : `dt = 1/120 s`. À comparer avec `1/60 s` au banc d'essai de phase 1 (coût, stabilité, traversées) avant de retenir une valeur.

Ordre fixe d'un pas (toujours le même, indépendant du joueur qui a créé le défi) :

1. **Rotation et oscillation** de chaque toupie active (§6).
2. **Forces et intégration** : accélérations, puis vitesse, plafond de vitesse, puis position (Euler semi-implicite). `ang += w · dt`.
3. **Collisions** entre paires `i < j`, avec détection continue sur le déplacement du pas (§8).
4. **Bords** de l'arène pour chaque toupie (§9).
5. **Statuts** : on calcule d'abord les nouveaux statuts de toutes les toupies, puis on les applique ensemble, pour qu'aucune toupie ne soit avantagée par l'ordre de parcours.
6. **Fin de manche** (§10), puis **keyframe** si le pas est un pas d'échantillonnage ou porte un événement.

Garde-fou absolu : `maxSteps = ceil(Tmax / dt) + 1`. Au-delà, la manche se termine en « temps écoulé », même si une autre règle a échoué.

## 6. Rotation et oscillation

Perte de rotation par pas :

```
w ← max(0, w − (tipFric + beta · w) · (1 + kWob · wob) · dt)
```

- `tipFric` : frottement de la pointe (pointe plate = forte perte et forte mobilité, pointe fine = faible perte et faible mobilité).
- `beta · w` : frottement de l'air.
- `kWob · wob` : une toupie qui oscille frotte davantage.

Sans choc, cette équation a une solution exacte, utilisée par les tests (durée jusqu'à `wStop` avec `wob = 0`) :

```
t = (1/beta) · ln((w0 + tipFric/beta) / (wStop + tipFric/beta))
```

Exemple avec `beta = 0,02`, `w0 = 250`, `wStop = 40` : pointe fine `tipFric = 2,5` → environ 41 s ; pointe plate `tipFric = 6` → environ 24 s. Ces durées sont dans la plage visée (manches de 15 à 45 s) et restent sous `Tmax = 60 s`.

Oscillation :

- Seuil : `wWob = 140 − 80 · stab` rad/s (de 140 pour `stab = 0` à 60 pour `stab = 1`).
- Si `w < wWob` : `wob += kWobUp · (1 − w / wWob) · dt`.
- Sinon : `wob −= kWobDown · wob · dt`.
- Chaque choc ajoute de l'oscillation (§8). `wob` est borné à `[0, 1]`.
- `wob = 1` signifie que la toupie touche le sol avec son corps : elle compte comme arrêtée (§10).

## 7. Déplacement

Accélération totale de chaque toupie active :

1. **Cuvette** : `a = −kBowl · p`. Pour une cuvette parabolique de profondeur `h` et de rayon `R` : `kBowl = 2 · g · h / R²`. Avec `h = 0,05 m` et `R = 0,60 m` : `kBowl ≈ 2,7 s⁻²`.
2. **Entraînement par la pointe** (orbite) : on vise une vitesse tangentielle `vOrb = mob · (w / wRef) · dir`, avec `wRef = 250 rad/s`. `a = trac · (vOrb − v·t) · t`, où `t` est la direction tangentielle unitaire. Cette force est atténuée près du centre (`fade = min(1, |p| / 0,08)`) pour éviter une direction indéfinie. Les toupies d'attaque orbitent vite près du bord, les toupies d'endurance restent au centre. C'est une **force de jeu non conservative**, assumée : elle peut ajouter de l'énergie de translation. Son coût en rotation n'est pas calculé à part : il est compris dans le `tipFric` plus élevé des pointes mobiles. Variante à comparer en phase 1 : débiter la rotation de la puissance fournie (`m · a·v` quand elle est positive). Conséquence pour les tests : « l'énergie ne croît jamais » ne se vérifie que sur des chocs isolés (entraînement, cuvette et perturbation coupés).
3. **Amortissement** : `a = −damp · v`.
4. **Perturbation** : petit vecteur tiré du générateur de la manche, d'amplitude `sigma · (1 + 4 · wob)`. Elle casse les symétries parfaites et rend l'oscillation visible dans la trajectoire.

Plafond de vitesse : `vMax = 3,0 m/s`. Il sert aussi à garantir l'absence de traversée (§8).

## 8. Collisions entre toupies

Les toupies sont des disques. Pour la paire `(i, j)` : normale `n = (pj − pi) / d`, recouvrement `delta = ri + rj − d`.

1. **Séparation** : si `delta > 0`, on écarte les deux disques le long de `n`, au prorata de l'inverse des masses. Si `d` est presque nul, `n` vient de la vitesse relative, sinon du générateur : jamais de division par zéro.
2. **Impulsion de rebond**, seulement si les disques se rapprochent (`vn = (vj − vi)·n < 0`) :
   `Jb = −(1 + e) · vn / (1/mi + 1/mj)`, avec `e = clamp(0,35 + 0,3 · (atk_i + atk_j)/2, 0,2, 0,8)`.
3. **Impulsion de frottement des bords tournants** : à l'impact, les surfaces glissent l'une sur l'autre à la vitesse `sigma = |dir_i · w_i · r_i + dir_j · w_j · r_j|`. Même sens de rotation : les vitesses s'additionnent, le choc est violent. Sens opposés : elles se compensent en partie. On ajoute :
   `Js = kSmash · min(sigma, sigmaCap) · mRed · (0,5 + (atk_i + atk_j)/2)`, avec `mRed = mi·mj/(mi+mj)`.
   `Js` n'est appliquée qu'au **début** d'un contact, puis la paire a une recharge (0,1 s) pour éviter une rafale d'impulsions tant que les disques se touchent.
4. **Déviation latérale** : impulsion tangentielle `Jt = muC · (Jb + Js)` opposée au glissement. C'est elle qui donne les ricochets de côté.
5. **Perte d'énergie de rotation** : travail dissipé `W = kW · Jt · sigma`, plus l'énergie cinétique ajoutée par `Js` (rien n'est créé : l'énergie de translation ajoutée est prise sur la rotation). `W` est partagé : part de `i` proportionnelle à `clamp(0,5 + 0,5 · (atk_j − def_i), 0,15, 0,85)`, puis normalisée avec la part de `j`. On convertit ensuite l'énergie restante en `w`.
6. **Oscillation de choc** : `wob_i += kImpWob · (J / mi) · atk_j / (0,5 + stab_i + def_i/2)`.
7. **Événement** `hit` avec le pas, la position du contact et une intensité (pour les étincelles et le son côté client).

Impulsions égales et opposées : la quantité de mouvement est conservée par `Jb`, `Js` et `Jt`.

**Bilan d'énergie, borné avant application** : on calcule d'abord ce que `Js` ajouterait en énergie de translation (`ΔKs`) et le travail `W` qu'il entraînerait. Si `ΔKs + W` dépasse l'énergie de rotation disponible au-dessus du seuil d'arrêt (`Edisp = Σ max(0, E − E(wStop))` des deux toupies), on réduit `Js` (et donc `Jt` et `W`) par un facteur calculé **avant** d'appliquer quoi que ce soit. Corriger les réserves après coup ne suffit pas : l'énergie de translation aurait déjà été créée. Le test du §17.4 vérifie que l'énergie totale ne croît jamais.

**Traversées** : une distance parcourue par pas plus petite que la somme des rayons ne suffit pas. Un contact rasant peut se produire au milieu du pas alors que les positions de début et de fin ne se recouvrent pas. Le moteur fait donc une **détection continue** entre deux disques : il résout `|d0 + Δv · t| = ri + rj` pour `t` dans `[0, dt]` (équation du second degré), applique le contact à l'instant trouvé, puis termine le pas. Le coût est borné : une paire en duel, et au plus un contact résolu par paire et par pas. Les autres contacts du même pas sont traités au pas suivant. `vMax = 3 m/s` limite en plus la profondeur d'un éventuel recouvrement. Les cas rasants, frontaux et à vitesse maximale sont testés (§17.12), à 1/120 et à 1/60 s.

Plus de deux toupies (mode futur) : paires traitées dans un ordre fixe, avec un biais d'ordre possible à mesurer. Le duel n'est pas concerné.

## 9. Bords, poches et éjections

L'arène a un rayon intérieur `R`, une paroi et des **poches** : des secteurs angulaires sans paroi (3 poches de 24° par défaut, configurables par arène, possiblement aucune pour une arène portable).

Quand `|p| + r > R` :

1. On calcule le point de franchissement sur le segment du pas (interpolation), pas seulement la position finale.
2. Le secteur est testé par produits scalaires et vectoriels avec les directions des poches pré-calculées, sans `atan2` dans la boucle (fonctions trigonométriques de la libm évitées pendant la simulation, voir §11).
3. Dans une poche et vitesse sortante `vOut > vPocket` (0,10 m/s) : **éjection**.
4. Sur la paroi et `vOut > vOver` (1,6 m/s) : **éjection par-dessus la paroi**.
5. Sinon : rebond (`e = 0,55`), repositionnement à `R − r`, perte d'énergie de rotation proportionnelle au choc et oscillation, événement `wall`.

Une toupie éjectée quitte la simulation. Sa trajectoire de sortie affichée par le client est purement visuelle.

## 10. Fin de manche

Conditions vérifiées après l'application simultanée des statuts du pas :

| Priorité | Situation dans le même pas | Résultat |
|---|---|---|
| 1 | les deux toupies ont un arrêt confirmé | celle dont l'arrêt a commencé plus tôt perd (`spin_out`) ; même pas de début → égalité |
| 1 | les deux toupies ont une condition de fin, dont au moins une éjection | égalité, motif `double_out` |
| 2 | une seule toupie éjectée | l'autre gagne, motif `ring_out` |
| 2 | une seule toupie avec arrêt confirmé | l'autre gagne, motif `spin_out` |
| 3 | `t ≥ Tmax` | la plus grande `w` restante gagne si l'écart dépasse `tieEps` (2 %), sinon égalité, motif `time` |
| 4 | `step ≥ maxSteps` | même règle que `time`, journalisé comme anomalie |

Les règles sont symétriques : échanger les deux toupies échange le résultat.

**Arrêt confirmé** : la condition `w < wStop` (40 rad/s) ou `wob ≥ 1` doit tenir sans interruption pendant `stopConfirm` (0,75 s, configurable). Si la condition cesse avant, le compteur repart à zéro. L'heure d'arrêt retenue est le début de la condition.

Égalité : en partie libre, elle est acceptée. En tournoi ou si la règle l'interdit, le **match** joue une manche supplémentaire avec une nouvelle seed ; au-delà d'un nombre maximal de manches, le match se termine en égalité ou au cumul des `w` restantes (règle à choisir, [ARCHITECTURE.md](ARCHITECTURE.md) §16).

Abandon, déconnexion, mort et sortie de zone ne sont pas des règles physiques : ils sont gérés en temps réel par la machine à états du match et **priment sur le résultat calculé** ([ARCHITECTURE.md](ARCHITECTURE.md) §11).

## 11. Aléa et reproductibilité

- Générateur propre au moteur (xorshift ou PCG sur les entiers 64 bits de Lua 5.4), avec un état par manche. Jamais `math.random` dans le moteur : son état est partagé par tout le code de la ressource.
- La seed de la manche est tirée par le serveur **après** le verrouillage des configurations. Elle n'est jamais envoyée aux clients avant la fin de la manche.
- Aucun parcours `pairs` dans le moteur : son ordre n'est pas garanti. Uniquement des tableaux indexés.
- Pas d'horloge (`os.time`, `os.clock`, `GetGameTimer`) dans le moteur.
- Reproductibilité visée : même code, même entrée, même seed, même runtime → même trace. C'est utile pour les tests, les rediffusions et les litiges. Elle n'est **pas** promise entre `lua5.4` sur Linux et CfxLua (Linux ou Windows) : `sqrt` est exacte en IEEE 754, mais `sin`, `cos` et `exp` peuvent différer selon la libm. Les comparaisons entre runtimes se feront avec une tolérance documentée. Le jeu n'en dépend pas, puisque seul le serveur calcule.

## 12. Familles et compromis

Les familles sont des préréglages de pièces, pas des règles spéciales du moteur. Les pièces ont un budget : gagner sur une caractéristique coûte sur une autre ([ARCHITECTURE.md](ARCHITECTURE.md) §14).

| Famille | Point fort | Faiblesse attendue |
|---|---|---|
| Attaque | `atk`, `mob` élevés, pointe plate | perd vite sa rotation, risque de sortir seule par une poche |
| Défense | `def`, masse | lente, perd au temps contre l'endurance |
| Endurance | `tipFric` faible, `stab` élevée | reste au centre, fragile aux chocs puissants |
| Équilibre | valeurs moyennes | aucun avantage net |
| Mobilité | `mob`, `trac` élevés, légère | facile à éjecter, oscille tôt |

Cibles d'équilibrage à vérifier en phase 1 puis 4 par simulation de masse (par exemple 2 000 manches par paire, seeds enregistrées) :

- Chaque confrontation entre familles entre 25 % et 75 % de victoires.
- Aucune configuration autorisée au-dessus de 60 % contre l'ensemble des autres.
- Moins de 10 % d'égalités, durée médiane entre 15 et 40 s.
- Les trois fins (éjection, arrêt, temps) apparaissent toutes.

Ces cibles sont des objectifs, pas des résultats.

## 13. Paramètres initiaux

| Paramètre | Valeur de départ | Commentaire |
|---|---|---|
| `dt` | 1/120 s | comparer avec 1/60 |
| `R` | 0,60 m | dépend du modèle d'arène |
| `h` (profondeur) | 0,05 m | donne `kBowl ≈ 2,7 s⁻²` |
| `Tmax` | 60 s | configurable par règle |
| `beta` | 0,02 s⁻¹ | frottement de l'air |
| `kWob` | 2,0 | effet de l'oscillation sur la perte de rotation |
| `kWobUp` / `kWobDown` | 0,8 / 0,5 s⁻¹ | |
| `wStop` | 40 rad/s | |
| `stopConfirm` | 0,75 s | configurable (§5.3 du cahier) |
| `wRef` | 250 rad/s | |
| `sigma` (perturbation) | 0,05 m/s² | |
| `vMax` | 3,0 m/s | |
| `kSmash` | 0,04 | |
| `sigmaCap` | 30 m/s | |
| `muC` | 0,25 | |
| `kW` | 0,5 | |
| `kImpWob` | 0,05 | |
| recharge de contact | 0,1 s | |
| `eWall` | 0,55 | |
| `vPocket` / `vOver` | 0,10 / 1,6 m/s | |
| poches | 3 × 24° | par arène |
| `tieEps` | 2 % | |
| départ | rayon 0,6·R, positions opposées, angle de départ tiré au sort | symétrique |
| aléa de lancement | ±2 % sur `w0`, ±5° sur la direction | tiré par le serveur |

## 14. Exécution sur le serveur

Le moteur expose des fonctions pures. L'exécution est confiée au module `matches` ([ARCHITECTURE.md](ARCHITECTURE.md) §8) :

```lua
local round  = Engine.newRound(params)  -- arène, toupies validées, règles, seed ; erreur si une entrée est invalide
local events = Engine.step(round)       -- avance d'un pas fixe
local done, outcome = Engine.result(round)
local frame  = Engine.keyframe(round)   -- tableau compact pour le réseau
```

- La manche est calculée **pendant le compte à rebours**, par tranches de pas avec un `Wait(0)` entre deux tranches. On n'exécute jamais `Tmax / dt` pas d'un seul bloc. La taille des tranches sera fixée après mesure (objectif : rester sous quelques millisecondes par tranche).
- Mémoire bornée : keyframes à 20 Hz (et à chaque événement), soit environ 1 200 images par toupie pour 60 s, libérées à la fin de la manche. Nombre de manches calculées en même temps plafonné par la configuration.
- Le serveur garde le résultat pour lui. Le client reçoit les keyframes par tranches, avec une avance limitée (§15).
- Si la manche n'est pas finie au moment du « GO » (serveur surchargé), le lancement est retardé et le compte à rebours prolongé, plutôt que d'afficher une manche incomplète.

Aucun chiffre de performance n'est annoncé : le coût d'un pas sera mesuré en phase 1 (`lua5.4`, puis CfxLua sur le serveur).

## 15. Données envoyées au rendu

- Keyframe : pas, puis pour chaque toupie `x`, `y` (en mm, entiers), `w` (en 0,1 rad/s), `wob` (0 à 255), statut. Le format exact est dans [ARCHITECTURE.md](ARCHITECTURE.md) §9.
- Événements : `hit`, `wall`, `wobble`, `ring_out`, `spin_out`, avec leur pas exact. Ils créent une keyframe supplémentaire à ce pas, pour que l'interpolation ne lisse pas un rebond.
- `ang` n'est pas envoyé : le client fait tourner le modèle à partir de `w`, avec une vitesse apparente plafonnée pour éviter l'effet stroboscopique.
- **Fenêtre d'anticipation** : avec une avance de diffusion `L` (0,5 s proposée ; plage à qualifier en phase 2 entre 0,25 et 1,5 s selon le jitter mesuré : plus petite = moins d'anticipation mais plus de gels), un client modifié peut voir jusqu'à `L` secondes à l'avance qu'une toupie va sortir ou s'arrêter, même sans champ « vainqueur ». On réduit cette fenêtre : la tranche qui contient l'événement de fin n'est envoyée qu'à son heure de lecture, et le client absorbe avec son tampon. On neutralise surtout l'intérêt d'anticiper : pas de mises pendant une manche, et un abandon ou une déconnexion ne relance pas la manche et ne rapporte rien au joueur qui part.

## 16. Limites assumées

- Pas de 3D réelle : pas de saut, pas de collision verticale, pas de toupie qui monte sur l'autre.
- Les pièces influencent des caractéristiques, pas une géométrie de contact détaillée. La modulation par la forme des lames (selon `ang` au contact) est une extension possible, désactivée en v1.
- Pas d'échange de rotation entre sens opposés en v1 (le modèle réduit seulement les dégâts dans ce cas).
- Les valeurs du §13 sont inventées pour être cohérentes entre elles. Elles ne sont pas mesurées sur de vraies toupies, et ce n'est pas le but : le but est un jeu lisible et équilibré.

## 17. Tests propres au modèle

À ajouter aux cas généraux de [TEST_PLAN.md](TEST_PLAN.md) (phase 1) :

1. Décroissance libre : durée jusqu'à `wStop` conforme à la formule du §6, à `dt` près.
2. Cuvette sans entraînement ni perturbation : oscillation autour du centre de période `2π/√kBowl`, amortie par `damp`.
3. Choc frontal sans rotation : conservation de la quantité de mouvement, coefficient de restitution respecté.
4. Choc isolé avec rotation (entraînement, cuvette et perturbation coupés) : énergie totale (rotation + translation) qui ne croît jamais pendant le contact.
5. Même sens / sens opposés : `sigma` et pertes plus fortes dans le premier cas.
6. Recharge de contact : une seule impulsion `Js` par contact.
7. Poche et paroi : franchissement exactement sur la limite d'une poche, vitesse juste sous et juste au-dessus de `vOver`.
8. Arrêt qui reprend avant `stopConfirm` : pas de victoire.
9. Permutation des toupies (A contre B, puis B contre A avec positions miroir) : résultats symétriques sur un grand nombre de seeds.
10. Statistiques d'équilibrage du §12 sur des seeds enregistrées.
11. Mesure du coût par pas et par manche, à 1/120 et 1/60 s.
12. Détection continue : contact rasant au milieu d'un pas, disques qui se croisent à `vMax` en sens opposés, départ déjà en recouvrement. Aucun contact manqué ni recouvrement durable.
13. Bilan avant application : choc avec des toupies presque arrêtées, `Js` réduite, aucune énergie créée.

## 18. Phase 1 : écarts avec la conception et calibrage

Ajout du 18 octobre 2026, après les premiers essais du moteur. Les sections 7 et 13 décrivent la conception d'origine ; en cas de différence, c'est cette section et `config/shared.lua` qui font foi.

**Entraînement (remplace §7.2).** Avec l'entraînement tangentiel prévu, la toupie d'attaque tournait en orbite à 0,4–0,5 m du centre et ne touchait jamais la toupie d'endurance (0 choc sur 300 manches). La cuvette exerce une force centrale qui conserve le moment angulaire, et l'entraînement tangentiel le recharge en continu : aucune trajectoire ne pouvait passer près du centre. Le moteur poursuit maintenant une **vitesse cible vectorielle** :

```
d   = dir · t + lean · (−u)          (t tangente, u direction radiale)
lean = flowerLean · max(0, phase − flowerThreshold) / (1 − flowerThreshold)
a   = kDrive · trac · fade · (vOrb · d/|d| − v)
```

`phase` est un sinus de pulsation `flowerFreq`, de phase initiale tirée au sort, tourné par une matrice pré-calculée (pas de `sin` dans la boucle). Pendant la phase haute, la toupie plonge vers le centre et sa vitesse tangentielle est freinée : c'est le « motif en fleur ». La force reste non conservative (§7).

**Paramètres modifiés ou ajoutés :**

| Paramètre | Conception | Phase 1 | Raison |
|---|---|---|---|
| `h` (arène de test) | 0,05 m | 0,08 m (`kBowl ≈ 4,36 s⁻²`) | orbites plus serrées |
| `beta` | 0,02 | 0,01 | manches un peu plus longues |
| `kSmash` | 0,04 | 0,15 | les chocs doivent pouvoir éjecter |
| `kW` | 0,5 | 1,5 | les chocs doivent vider la rotation |
| `muWall` | — | 0,2 | frottement contre la paroi (§9), manquait au tableau |
| `flowerLean`, `flowerFreq`, `flowerThreshold` | — | 4 ; 0,8 rad/s ; 0,5 | motif en fleur |
| `startRadius`, `launchAngle`, `launchJitter`, `w0Jitter` | « départ » du §13 | 0,6 ; 20° ; 5° ; 2 % | lancement |

**Mesures** (deux toupies de test de `config/shared.lua`, côtés alternés) :

| Runtime | Manches | Attaque / endurance / nul | Éjections | Durée médiane | Calcul par manche |
|---|---|---|---|---|---|
| `lua5.4` (5.4.6) | 600 (300 par côté) | 62 % (côté 1), 68 % (côté 2) / reste / 0 | ≈ 30 % | 14–15 s | ≈ 9 µs par pas, 13–24 ms par manche |
| FiveM CfxLua, artefact 35265 Linux, instance de test | 300 | 186 / 114 / 0 | 77 (26 %) | 14,2 s | p50 23 ms, p95 51 ms (`os.clock`, CPU du processus, découpé en tranches de 600 pas) |

Ce sont des mesures sur deux toupies de test, pas une validation de l'équilibre des familles (§12). Le motif `time` n'apparaît pas : les deux toupies s'arrêtent avant 60 s. Aucun essai visuel en jeu ni multijoueur n'est encore fait.

**Anticipation mesurée sur le code (§15).** Les tranches ordinaires couvrent 0,5 s et partent 0,5 s avant leur début : un client peut voir jusqu'à 1 s d'avance. Les 0,5 dernières secondes partent en morceaux de 0,1 s envoyés à leur heure : la fin n'est pas visible plus de 0,1 s à l'avance. À reprendre en phase 2 avec les mesures de latence.

## 19. Rotation gauche (anneau inversé, 28 octobre 2026)

Le moteur gérait déjà le sens de rotation (`dir`) : glissement au contact (§8) et contre la paroi (§9), sens de l'orbite (§7). Il manquait seulement une pièce pour le choisir. `ring_reverse` (« Anneau inversé ») porte `dir = -1` ; `Stats.compute` donne `dir = -1` à toute toupie qui le monte.

- **Même sens** : au point de contact, les surfaces vont en sens contraires ; glissement fort, chocs durs, grosses pertes de rotation.
- **Sens contraires** : les surfaces roulent ensemble ; glissement faible, contacts doux, manches plus longues.

**Banc** (`lua`, 24 seeds × 2 côtés par case, lancers neutres, chaque kit contre les 5 kits en sens normal ; victoires − défaites sur 48) :

| Kit | Anneau | attaque | équilibre | défense | endurance | mobilité | total | durée moy. |
|---|---|---|---|---|---|---|---|---|
| balance | d'origine | −28 | 0 | +18 | −31 | +40 | −1 | 18,9 s |
| balance | inversé, sans contrepartie | +48 | −18 | +48 | −12 | +48 | +114 | 32,2 s |
| balance | inversé, w0 −25 (retenu) | +48 | −48 | +14 | −48 | +48 | +14 | 29,9 s |
| endurance | d'origine | −12 | +31 | +12 | 0 | +32 | +63 | 12,8 s |
| endurance | inversé, sans contrepartie | +48 | −6 | +48 | 0 | +48 | +138 | 32,0 s |
| endurance | inversé, w0 −25 (retenu) | +48 | −48 | +30 | −48 | +48 | +30 | 30,9 s |
| attaque | inversé, w0 −25 | −48 | −48 | −48 | −48 | −48 | −240 | 20,5 s |
| défense | inversé, w0 −25 | +12 | −48 | −48 | −48 | −32 | −164 | 26,3 s |

Sans contrepartie, l'inversion seule gagnait presque tout. Retenu : coût 20 points (comme l'anneau standard), réserve de rotation `w0 −25`. L'anneau inversé devient une **réponse à l'attaque** sur une base équilibre ou endurance, perdante contre l'endurance et l'équilibre en sens normal, et inutile sur une attaque (l'attaque perd l'anneau à griffes). Les manches entre sens contraires durent deux fois plus (≈ 30 s, sous `Tmax = 60 s`). Mesure hors jeu ; l'équilibre réel reste à observer en jeu.
