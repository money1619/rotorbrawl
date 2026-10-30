# Direction Artistique, Interface NUI et Rendu Client — SPIN ARENA

Date : 18 octobre 2026 (Phase 0 — Conception uniquement, aucun code ni asset livré).

---

## 1. État réel en Phase 0

À l'issue de l'audit initial du dossier `resources/[Money]/Chaos_Arena` :

- **Aucun fichier client Lua (`client/*.lua`), aucune interface NUI (`web/*`) et aucun modèle ou texture (`stream/*`) n'existent dans le dépôt.**
- Ce document définit l'architecture visuelle, l'ergonomie NUI, le pipeline de rendu client FiveM et les spécifications techniques des ressources graphiques à produire pour les Phases 1 à 6, après validation de la Phase 0 par l'utilisateur.
- **Aucun fichier 3D (`.ydr`, `.ytd`, `.ytyp`, `.ybn`, `.ycd`) n'est inventé ni supposé présent.** Tant que les modèles finaux originaux ne sont pas produits, validés et inscrits dans [`docs/ASSET_REGISTER.md`](ASSET_REGISTER.md), les phases de prototypage (Phases 1 et 2) utiliseront exclusivement des représentations géométriques temporaires explicitement documentées.

---

## 2. Identité artistique et règles de propriété intellectuelle

### 2.1 Positionnement visuel : « Mécanique Industrielle Futuriste »

SPIN ARENA repose sur une direction artistique originale d'ingénierie mécanique de précision :

- **Matériaux dominants** : alliages de titane usiné CNC, acier brossé, carbone mat, polymères techniques haute densité, visserie hexagonale apparente et rotors métalliques gravés.
- **Signature lumineuse** : noyaux gyroscopiques à éclairage LED industriel discret (anneau central et témoins d'état), sans effets magiques, surnaturels ni créatures.
- **Modularité lisible** : chaque toupie distingue visuellement ses composants fonctionnels (couronne d'impact / anneau extérieur, châssis de masse, noyau gyroscopique, pointe de contact) et ses finitions cosmétiques (anodisation, gravure, couleur de noyau).

### 2.2 Garde-fous absolus de propriété intellectuelle

1. **Identité originale** : aucune marque tierce, dénomination, logo, typographie distinctive, nomenclature ou slogan de franchise ne doit servir d’identité au produit, à ses interfaces ou à ses assets. La citation documentaire des interdictions du cahier des charges ne constitue pas une identité de produit.
2. **Aucun rip ni décalque 3D** : aucun modèle, texture, son ou animation ne peut être extrait d'un jeu commercial ni reproduit à l'identique depuis des photographies de jouets existants.
3. **Statut du nom** : la dénomination **SPIN ARENA** est utilisée à titre provisoire pendant le développement jusqu'à vérification juridique par le titulaire du projet.

---

## 3. Palette de référence et système de design NUI

### 3.1 Palette chromatique officielle

| Token CSS | Nom de référence | Code Hex | Rôle dans l'interface et les matériaux |
|---|---|---|---|
| `--sa-bg-noir` | Noir industriel | `#0D0F12` | Fond principal des panneaux NUI (opacité 92–96 %), châssis interne |
| `--sa-surface-graphite` | Gris graphite | `#1A1E24` | Cartes de modules, jauges de fond, conteneurs d'inventaire et de tableaux |
| `--sa-metal-titane` | Titane & acier brossé | `#8C96A4` | Bordures techniques fines (`1px`), textes secondaires, icônes métalliques |
| `--sa-metal-clair` | Acier poli | `#D8DEE9` | Titres, valeurs numériques principales, chronomètre, typographie haute lisibilité |
| `--sa-accent-cyan` | Cyan électrique | `#00E5FF` | État actif, sélection, jauge d'énergie de rotation stable, noyau standard |
| `--sa-accent-orange` | Orange impact | `#FF5500` | Alertes d'impact, collisions critiques, bouton de défi/lancement, perte critique de RPM |
| `--sa-status-success` | Vert télémétrie | `#10B981` | Matériel validé, prêt au lancement, victoire confirmée |
| `--sa-status-danger` | Rouge arrêt | `#EF4444` | Éjection hors arène, arrêt de rotation, erreur ou refus serveur |

### 3.2 Principes d'ergonomie et de compacité

- **Encombrement minimal** : l'interface NUI occupe une surface contenue (panneau central modulaire `max-width: 960px`, `max-height: 620px` en mode menu ; bandeaux périphériques compacts en mode HUD de combat) afin de laisser l'arène et l'action visibles en jeu.
- **Lisibilité télémétrique** : inspiration « banc d'essai mécanique / télémétrie de compétition » avec coins biseautés (`clip-path` léger ou bordures techniques), valeurs chiffrées tabulaires (`font-variant-numeric: tabular-nums`) et barres de progression segmentées.
- **Zéro dépendance externe non auditée** : HTML5, CSS3 natif (variables CSS, Flexbox/Grid) et JavaScript ES2022 sans framework lourd ni CDN externe, avec pour **objectif de conception (non testé en Phase 0)** un chargement local rapide hors-ligne dans CEF (Chromium Embedded Framework de FiveM) et l'absence de dépendance tierce non licenciée.

---

## 4. Architecture de l'interface NUI (`web/` et `client/nui.lua`)

> **Note de Phase 0 sur les API et natives** : Toutes les fonctions natives FiveM/GTA et callbacks mentionnés dans les sections 4 et 5 (`SetNuiFocus`, `SendNUIMessage`, `RegisterNUICallback`, `CreateObjectNoOffset`, `FreezeEntityPosition`, `SetEntityCollision`, `SetEntityInvincible`, `SetEntityCoordsNoOffset`, `SetEntityRotation`, `DrawMarker`, `AttachEntityToEntity`, `RequestAnimDict`, `CreateCamWithParams`, `RenderScriptCams`, `RequestNamedPtfxAsset`, `UseParticleFxAssetNextCall`, `DeleteObject`, `RemoveAnimDict`, `RemoveNamedPtfxAsset`, `DestroyCam`) sont des **propositions de conception à vérifier contre la documentation Cfx.re et à tester sur le build GTA `2699` lors des phases d'implémentation**. Aucune de ces intégrations n'est implémentée ni testée en Phase 0.

### 4.1 Les 5 menus principaux (Mode Interactif — Focus NUI actif)

L'interface principale s'ouvre sur action explicite du joueur (commande, interaction `ox_lib` près d'une table d'atelier/arène ou utilisation d'objet) et s'articule autour de cinq onglets :

1. **Ma toupie (Atelier & Configuration)**
   - Sélection de la toupie possédée (identifiant unique vérifié serveur).
   - Vue éclatée / aperçu 3D ou schématique des emplacements de pièces :
     - **Pièces stratégiques** (affectent les caractéristiques d'entrée bornées et calculées côté serveur selon [`docs/PHYSICS.md`](PHYSICS.md) : masse `m` en $\text{kg}$, rayon `r` en $\text{m}$, répartition `kI`, attaque `atk`, défense `def`, stabilité `stab`, friction de pointe `tipFric` en $\text{rad/s}^2$, mobilité `mob` en $\text{m/s}$, adhérence `trac` en $\text{s}^{-1}$, amortissement `damp` en $\text{s}^{-1}$).
     - **Options cosmétiques** (couleur d'anodisation, teinte du noyau lumineux, effet d'étincelles), strictement séparées des caractéristiques de combat.
   - Comparateur des 5 archétypes (**Attaque**, **Défense**, **Équilibre**, **Endurance**, **Mobilité**) sous forme de barres comparatives mettant en évidence les compromis (ex. gain d'impact = perte d'endurance ou de stabilité).
   - État d'usure et bouton de maintenance (utilisation de `spin_repair_kit` validée serveur).
2. **Défis (Duels 1v1)**
   - Liste des joueurs éligibles à proximité (filtrée et validée serveur selon distance et disponibilité).
   - Choix de l'arène (arène fixe proche ou zone libre autorisée) et des règles de manche (1 manche gagnante / Bo3, durée maximale).
   - Réception, acceptation ou refus d'une invitation avec compte à rebours d'expiration.
3. **Arènes (Carte & Spectateur)**
   - Liste des arènes fixes configurées sur le serveur et leur état temps réel (`Libre`, `En préparation`, `Combat en cours`, `Tournoi`).
   - Nombre de spectateurs présents / capacité maximale.
   - Action « Rejoindre en spectateur » ou indication GPS sur la carte lorsque l'arène est ouverte.
4. **Tournois (Compétitions)**
   - Liste des tournois publics et privés (ouverts aux inscriptions, en cours, terminés).
   - Arbre à élimination directe (bracket lisible par tour) avec statut des matchs et gestion des abandons/forfaits.
   - Panneau d'organisation (visible uniquement si le serveur confirme les permissions d'organisateur/admin).
5. **Classement (Progression & Historique)**
   - Classement général et saisonnier (ELO / points, victoires, défaites, taux d'éjection vs endurance).
   - Fiche statistique personnelle du joueur et historique des derniers matchs vérifiés en base.

### 4.2 HUD de combat temps réel (Mode Overlay — Focus NUI désactivé)

Pendant un duel ou en mode spectateur, le joueur conserve le contrôle de sa caméra ou de sa posture d'observation (`SetNuiFocus(false, false)`), tandis que l'overlay NUI affiche :

- **Bandeau supérieur compact** :
  - Manche actuelle (ex. `MANCHE 2 / 3`), chronomètre synchronisé serveur (`01:15`) et nom de l'arène.
  - Cartouches gauche (Joueur A) et droite (Joueur B) : nom RP/identifiant affiché, archétype de toupie, jauge de rotation restante distinguant rigoureusement (conformément à [`docs/PHYSICS.md`](PHYSICS.md) §2–3) :
    - la **vitesse angulaire de rotation** `w` ($\omega$, en $\text{rad/s}$, ou ratio $w / w_0$ en `%`),
    - l'**énergie de rotation déduite** $E = 0{,}5 \cdot k_I \cdot m \cdot r^2 \cdot w^2$ (en Joules, $\text{J}$, ou ratio $E / E_0$ en `%$),
    - et l'indicateur d'oscillation/instabilité `wob` ($0$ à $1$).
- **Compte à rebours de lancement synchronisé** :
  - Séquence visuelle `3 — 2 — 1 — LANCEMENT !` calée sur l'horodatage serveur du match.
- **Journal d'événements d'arène (toast latéral non intrusif)** :
  - Notifications brèves pilotées par les événements des keyframes serveur : *Impact lourd ($\Delta w$ en $\text{rad/s}$ / $\Delta E$ en $\text{J}$)*, *Choc critique*, *Contact bord*, *Éjection !*, *Rotation arrêtée*.
- **Écran de résultat final** :
  - Annonce du vainqueur déterminé par le serveur, motif officiel de fin de manche (*Éjection hors arène*, *Arrêt de rotation confirmé*, *Décision au temps*, *Abandon / Déconnexion*), résumé des récompenses accordées et fermeture automatique.

### 4.3 Contrats de communication `client/nui.lua` ↔ `web/` et sécurité NUI

- **Sens Lua → NUI (`SendNUIMessage`)** :
  - Enveloppe JSON normalisée `{ action = "<domaine>:<evenement>", payload = { ... } }` (ex. `ui:open`, `ui:close`, `hud:startMatch`, `hud:tickTelemetry`, `hud:impactEvent`, `hud:matchResult`, `workshop:updateState`).
  - **Fréquence maîtrisée** : le HUD de combat est mis à jour à la cadence des keyframes/snapshots réseau (10 à 20 Hz maximum) avec interpolation CSS (`transition: width 80ms linear`), jamais à chaque frame `Wait(0)`.
- **Sens NUI → Lua (`RegisterNUICallback`)** :
  - Toutes les entrées issues du DOM/JavaScript sont considérées comme **non fiables**.
  - `client/nui.lua` vérifie le type et la structure des paramètres, applique un anti-rebond local (cooldown UI de 250 ms par action), puis transmet uniquement des identifiants (`topId`, `partSlot`, `targetServerId`, `arenaId`) au serveur qui effectue la validation d'autorité.
  - **Prévention XSS obligatoire** : dans `web/`, aucun nom de joueur, nom personnalisé de toupie ou titre de tournoi n'est injecté via `innerHTML` ; utilisation exclusive de `textContent` ou de création de nœuds DOM sécurisés.

---

## 5. Rendu 3D client, animations et effets (`client/renderer.lua`, `client/launcher.lua`, `client/effects.lua`)

### 5.1 Séparation stricte entre simulation serveur et rendu client

Conformément à la section 7 du cahier des charges et à [`docs/PHYSICS.md`](PHYSICS.md) :

- **Aucune physique GTA native sur les toupies** : les entités représentant les toupies côté client sont prévues en mode purement visuel (proposition : `CreateObjectNoOffset` en entité locale `isNetwork = false` pour éviter les conflits de migration d'autorité OneSync sur de petits props rapides, avec `FreezeEntityPosition(entity, true)`, `SetEntityCollision(entity, false, false)` et `SetEntityInvincible(entity, true)` — comportement à vérifier en jeu sur le build `2699`).
- **Interpolation locale fluide** :
  - `client/renderer.lua` reçoit les tranches de keyframes autoritaires selon [ARCHITECTURE.md, section 9](ARCHITECTURE.md#9-protocole-réseau) : pas, positions horizontales `x/y` quantifiées en millimètres, vitesse angulaire `w` en dixièmes de rad/s, oscillation `wob` sur 0–255 et statut. Les événements portent leur pas. Les vitesses horizontales et l’angle `ang` ne sont pas transmis ; la rotation visuelle est intégrée localement à partir de `w`.
  - Entre deux keyframes serveur, une boucle de rendu locale active uniquement pendant le match (`Wait(0)` limitée aux joueurs participants et spectateurs dans le rayon de l'arène) interpole la position horizontale, calcule la hauteur $z(r)$ selon la courbure mathématique de la cuvette de l'arène, applique l'inclinaison d'oscillation (`wob`) et fait tourner le modèle autour de son axe local Z (`SetEntityCoordsNoOffset`, `SetEntityRotation`).

### 5.2 Stratégie progressive de représentation visuelle (Phase 1 vs Phase 3)

| Phase | Représentation visuelle utilisée | Statut & Justification |
|---|---|---|
| **Phase 1 & 2** (Prototype physique & Multijoueur) | **Formes géométriques temporaires** : petits props cylindriques/mécaniques natifs de GTA V (noms de modèles à vérifier dans le build `2699`) + anneaux et vecteurs directionnels via `DrawMarker` (cylindre plat, cône central, code couleur Cyan/Orange). | Permet de tester et valider mathématiquement et en multijoueur les trajectoires, les rayons de collision, la friction, les limites d'arène et les éjections **sans inventer de fichier 3D inexistant**. |
| **Phase 3** (Rendu et animations) | **Modèles 3D originaux streamés** (`.ydr` / `.ytd` / `.ytyp` dans `stream/`) pour chaque famille de toupie, les lanceurs et l'arène. | Activé uniquement après livraison et validation en jeu des modèles originaux listés dans [`docs/ASSET_REGISTER.md`](ASSET_REGISTER.md). |

### 5.3 Lanceurs et séquence d'animations synchronisées (`client/launcher.lua`)

1. **Équipement et mise en place** : les deux participants sont placés aux points de lancement opposés autour du périmètre de l'arène, orientés vers le centre. Proposition à vérifier en jeu : attachement du prop lanceur à l'os de la main du ped (`AttachEntityToEntity` sur `SKEL_R_Hand` ou `PH_R_Hand`).
2. **Préparation et compte à rebours** : chargement du dictionnaire d'animation (`RequestAnimDict`) vérifié avant le départ. L'animation d'armement s'exécute pendant le compte à rebours serveur.
3. **Lancement simultané sans avantage caché** : l'instant $t_0$ de mise en jeu des deux toupies est déclenché uniquement par le signal serveur. La durée ou le style visuel de l'animation ne modifie jamais les paramètres initiaux (`w0`, `v0`) calculés par le serveur.
4. **Posture d'observation** : après le tir, le personnage adopte une posture d'observation hors de la surface de roulement, et le joueur peut basculer entre la vue personnage et une caméra plongeante d'arène (`CreateCamWithParams`, `RenderScriptCams`) libérée en fin de match.

### 5.4 Effets visuels et sonores (`client/effects.lua`)

- **Impacts et collisions** : déclenchement local d'étincelles métalliques (proposition à vérifier sur le build `2699` : particules PTFX natives GTA V via `RequestNamedPtfxAsset` / `UseParticleFxAssetNextCall`, calibrées selon l'intensité d'impact transmise par le serveur) et flash lumineux fugace au point de contact.
- **Traînées et retour d'énergie** : anneau lumineux au sol sous la toupie (passant du cyan électrique `#00E5FF` à l'orange `#FF5500` lorsque la vitesse angulaire `w` passe sous le seuil de début d'oscillation `wob` avant arrêt).
- **Ralenti visuel de fin de manche (optionnel et purement local)** : bref effet visuel de caméra sur l'éjection finale ou le dernier impact décisif, sans modifier l'horloge du serveur ni désynchroniser les clients.
- **Objectifs de performance et de nettoyage (à vérifier en Phases 1 à 5)** :
  - Cible hors match et loin d'une arène active : **0 entité créée, 0 boucle `Wait(0)` active** (à mesurer sous `resmon`).
  - Procédure de nettoyage systématique (`DeleteObject`, `RemoveAnimDict`, `RemoveNamedPtfxAsset`, `DestroyCam`, `RenderScriptCams(false, ...)`, fermeture NUI) à exécuter et tester lors de la fin du match, de l'éloignement du spectateur ou de l'événement `onResourceStop`.

---

## 6. Chaîne de production 3D / 2D et contraintes techniques

### 6.1 Outils inspectés et limites constatées en Phase 0

- **Sur le serveur inspecté (`/home/fivem2`)** :
  - Les sources de l'outil CLI/Web **`unified-gta-tool`** (`/home/fivem2/unified-gta-tool/unified-gta-tool-main/README.md`) ont été inspectées : l'outil déclare la prise en charge des formats `.ytd` (inspection JSON, import/export DDS, recompression), `.ydr` / `.yft` / `.ydd` (diagnostic JSON, conversion GLB ↔ YDR statique via `glb2ydr`), `.ytyp` (`make-ytyp`) et `.ycd` (animations). En revanche, **il ne gère pas la création de collisions `.ybn` autonomes** et **aucune conversion ou validation d'asset SPIN ARENA n'a été exécutée en Phase 0**. Il constitue donc un **outil candidat pour un contrôle partiel hors-ligne** des formats qu'il supporte, à valider en Phase 3.
  - **Blender n'est pas installé sur ce serveur Linux** (`which blender` négatif lors de l'audit). La modélisation 3D et l'export initial vers les formats GTA V devront être réalisés sur un poste de création (Blender + Sollumz / CodeWalker) avant contrôle et test en jeu dans FiveM.

### 6.2 Spécifications cibles des modèles à produire pour la Phase 3

| Catégorie | Format FiveM cible | Budget géométrique visé (Triangles) | Textures (`.ytd` DDS) | Contraintes d'intégration à vérifier en jeu |
|---|---|---|---|---|
| **Toupie complète / Corps** (5 familles) | `.ydr` + `.ytyp` | $\le 2\,500$ tris (LOD High), $\le 800$ tris (LOD Med) | $512 \times 512$ ou $1024 \times 1024$ (formats DDS tels que DXT1/BC1 ou DXT5/BC3 à valider avec l'exporteur et le build GTA `2699`) | Pivot centré exactement à la pointe de contact $(0,0,0)$ ; axe Z vertical ; rayon cohérent avec `r` ($0{,}040$–$0{,}060\text{ m}$) de [`docs/PHYSICS.md`](PHYSICS.md). |
| **Lanceur mécanique** | `.ydr` + `.ytyp` | $\le 1\,800$ tris | $512 \times 512$ (format DDS à valider sur build `2699`) | Point d'attache aligné pour la prise en main du ped (`PH_R_Hand` / `SKEL_R_Hand`). |
| **Arène fixe (Bol / Table)** | `.ydr` + `.ybn` + `.ytyp` | $\le 6\,000$ tris | $1024 \times 1024$ ou $2048 \times 2048$ (format DDS à valider sur build `2699`) | Collision statique `.ybn` pour l'environnement ; cuvette interne alignée sur le diamètre ($1{,}2\text{ m}$ proposé) et la courbure de [`docs/PHYSICS.md`](PHYSICS.md). |
| **Icônes d'inventaire** (`ox_inventory`) | `.png` (`web/images/`) | N/A (2D) | $128 \times 128$ px ou $256 \times 256$ px, fond transparent | Fichiers requis en Phase 4 : `spin_top.png`, `spin_launcher.png`, `spin_part.png`, `spin_repair_kit.png`. |
