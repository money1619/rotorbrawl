# CHANGELOG — SPIN ARENA

## Arènes par la config, arène transportable, table de tournoi, cordon — 2026-10-30
**Rien n'est testé en jeu** ; tests hors jeu verts.
- **Cordon :** la toupie assemblée attend que ses quatre modèles soient chargés ENSEMBLE avant de se créer (avant, chaque pièce
  libérait son modèle et tout était recréé en boucle) ; au bout de 3 s, repli sur la toupie monobloc (client/top_model.lua).
- **Arènes fixes par la config :** `arena.fixedList` (config/server.lua), fusionnées avec data/arenas.json, prioritaires, jamais
  réécrites dans le fichier, non supprimables en jeu.
- **Arène transportable :** objet `spin_portable_arena` (install/ox_inventory_items.lua) ; le challenger qui le porte installe une
  table « Poche » (R 0,30 m) devant lui, partout, même hors zone. Variante `pocket` (`portable = true`).
- **Table de tournoi :** variante `colisee` (R 1,20 m, 4 poches), arène fixe seulement (`/spin_admin arena add <nom> colisee`).
  Pas encore de gradins ni de panneau de tournoi.
- **Modèles :** `stream/spin_arena_table_pocket.ydr`, `spin_arena_table_colisee.ydr`, `spin_arena_extra.ytyp`
  (tools/models/build_tables_extra.py). Échelle et aspect à vérifier en jeu ; pas de nouveau visuel de marque.
- **Homologation (server/homologation.lua) :** seuls les matchs homologués comptent au classement. Règles (config/server.lua
  `homologation`) : table fixe, joueurs distincts, pas de toupie de test, 6 matchs par heure au plus entre deux mêmes joueurs. Un
  match homologué reçoit un certificat signé HMAC-SHA256 (clé : `data/homologation.key`, ignorée par git, ou convar
  `spin_arena_homologation_key`) que le classement revérifie, journal inclus. Les autres matchs sont « amicaux ». L'écran de fin
  affiche MATCH HOMOLOGUÉ (n° de certificat) ou MATCH AMICAL (motif). **Changement de comportement :** les tables improvisées et
  portables ne classent plus par défaut (`arenaKinds`). Un classement mondial exigerait un service central qui vérifie ces certificats.
- **Deux éditions (docs/EDITIONS.md) :** `python -I tools/package.py` construit `dist/Chaos_Arena-<version>-free.zip` (GitHub, licence
  AEOM actuelle) et `-pro.zip` (Tebex, `LICENSE_PRO` = brouillon commercial). Marqueurs `-- @pro` dans les configs ; tournois et
  homologation remplacés par `tools/edition/pro_stub.lua` dans l'édition gratuite. Nouveau code de réponse `pro_only`.
- Après mise à jour : `/spin_admin arena remove` des arènes de test si les modèles changent, puis `ensure Chaos_Arena`.

## Pièces à trois étages, finitions Éclat et Turbo, thème d'arène — 2026-10-29 (demande de Maxim)

Règle du projet (docs/ASSET_REGISTER.md) : aucun nom, logo, silhouette ni pièce d'une marque existante. Tout ce qui suit
est à nous : le vocabulaire des finitions, les pièces et l'interface s'inspirent seulement des principes du genre.
**Rien n'est testé en jeu** ; vérifié hors jeu (moteur réel, émulateur, banc de combats, rendu NUI dans un navigateur).

### Pièces (config/parts.lua, shared/stats.lua)
- Quatre emplacements, clés internes inchangées (les toupies déjà assemblées restent valides) : **Lame** (`ring`), **Noyau** (`core`),
  **Verrou** (`frame`, crans = résistance à l'éclatement `burst`), **Embout** (`tip`, accroche du rail `dash`).
- Renommées : Lame Orbite / Griffe / Rempart / Galet / Contre-courant ; Verrou 4 crans / large 5 / bas 6 / à pics 3 ; Embouts Standard, Aiguille, Plat, Bille, Gomme.
- Nouvelles : **Lame Scie** (attaque 0,95 en tout, défense très basse), **Verrou 9 crans** (presque impossible à faire éclater), **Embout Engrenage** (accroche le rail à 100 %, use sa rotation).
- Icônes des trois nouvelles pièces : variantes teintées des icônes existantes (install/icons_money/ox_images, déclarées dans `partIcons`).

### Moteur (server/physics, config/shared.lua `physics`)
- **Éclatement** : chaque choc entame le verrou de la toupie frappée (`burstLock` × résistance) ; à zéro elle éclate et perd la manche (finition `burst`). Un même choc ne fait éclater qu'une toupie ; même sens de rotation = chocs plus durs ; une toupie qui ralentit tient moins bien. `burstLock = 0` coupe la fonction. Banc : ~15 % des manches.
- **Rail turbo** : une arène peut porter un rail (`arenaVariants.turbo.railBoost`). Une toupie à embout `dash` qui roule dans son sens sur la bande extérieure accroche le rail, accélère le long du bord puis est relancée vers l'adversaire ; sa frappe lui fait perdre moins de rotation. Une éjection dans la seconde et demie qui suit un choc venu du rail = finition `turbo_out`. Nouvelle variante d'arène **turbo** (modèle provisoire, table Vector).
- Nouveaux événements `burst`, `dash`, `dash_end` (effets : client/effects.lua, client/spectacle.lua, son : web/combat_audio.js).

### Règles par points (config/server.lua `match.scoring`)
- Premier à 4 points, 7 manches au plus : **Sortie** (éjection) 2, **Arrêt** (rotation épuisée) 1, **Éclat** 2, **Turbo** 3. `mode = 'rounds'` rend l'ancien décompte (2 manches gagnantes).
- Panneau de la table : « Manche N · premier à 4 points » puis « SORTIE Sam +2 » ; résumé de fin : finition et points de chaque manche.

### Lanceurs à boost — phase 2 (config/parts.lua `launchers`, shared/launch.lua, server/matches.lua, server/shop.lua)
- Cinq types, un seul objet `spin_launcher` : le type est dans `metadata.launcher` (sans métadonnée = Cordon). Le premier lanceur de l'inventaire (emplacement le plus bas) sert en match, fixé à l'ouverture du match.
- **Cordon** (base) ; **Manivelle** : un peu plus de rotation, lancer plus lent, jauge −15 % ; **Ressort** : départ vif et plus d'attaque, jauge −20 % ; **Précision** : jauge +35 %, tirage tolérant +150 ms, inclinaison +40 % ; **Rail** : +0,2 d'accroche du rail turbo, départ plus vif, jauge −10 %.
- Le serveur seul applique les effets (jauge, fenêtre de tirage, caractéristiques de départ) ; le client affiche le nom et les effets dans le titre et les règles de la jauge, et sur la fiche de la boutique (bonus en vert, défauts en rouge). Prix = prix du lanceur × coefficient (config `shop.prices.launcher`, `priceMult`). Identifiant historique `launchers:spin_launcher` conservé pour le Cordon.
- Réglage au banc (toupies identiques, 120 manches) : la rotation de départ pèse très lourd (+0,5 % ≈ 55 % de victoires), la vitesse presque rien : écart final de 48 % à 55 %.
- Pour donner un lanceur à la main : `exports.ox_inventory:AddItem(src, 'spin_launcher', 1, { launcher = 'crank', label = 'Lanceur Manivelle' })` (install/ox_inventory_items.lua).

### Modèles 3D (Blender 4.0 + Sollumz 2.8, tools/models/)
- Export direct en `.ydr` natif : `sollumz_common.py` (clone d'un drawable existant, maillage `sa_common.Builder`, texture nommée d'après le modèle).
- **21 modèles de pièces** (`build_parts.py`, `stream/spin_pt_<emplacement>_<id>.ydr`) dessinés dans le repère de la toupie assemblée ; le client (`client/top_model.lua`) en assemble quatre : l'embout est la racine, verrou, lame et noyau y sont attachés sans décalage. Chaque assemblage a donc sa propre silhouette (6 lames × 5 verrous × 6 embouts × 4 noyaux). Repli sur l'ancien modèle monobloc si un modèle de pièce manque ; chargement différé géré (rien ne reste créé à moitié). Le serveur envoie les quatre pièces de chaque toupie dans l'en-tête de manche (`tops[i].parts`).
- **Table Turbo** (`build_table_turbo.py`, `spin_arena_table_turbo.ydr`) : mêmes pieds et jupe que Vector, cuvette R 0,60 m, rail orange visible à ras de la surface, collision embarquée ; la variante d'arène `turbo` l'utilise. Déclarés dans `spin_arena_parts.ytyp` et `spin_arena_stadiums.ytyp` (fxmanifest). Entrées au registre des assets (`docs/ASSET_REGISTER.md` §4.1 ter).
- Rendus de contrôle hors jeu : toutes les formes réimportées et rendues ; rien n'est vu dans GTA (échelle, orientation et collision à vérifier en jeu).

### Interface (web/style.css, bloc « Thème arène » en fin de fichier)
- Rouge/bleu des deux camps, or des finitions, titres italiques en capitales, panneaux à pans coupés. Départ : « LANCEZ ! ». Retirer le bloc pour revenir à l'ancien thème.
- Panneau de visée en bas à gauche et compact (centré, il cachait le ped). Résumé de fin : noms dans le bon ordre (le serveur envoie un tableau Lua numéroté à partir de 1).

### Lanceur et préparation (client/launcher.lua)
- Pose à deux mains, main gauche qui suit le cordon (SetIkTarget), rotation calibrée en jeu, nettoyage des props à l'arrêt de la ressource (un crash client a eu lieu avec le lanceur en main), cuvette vide avant le GO, envol plus long quand le joueur est loin de la table.
- Outils de test en jeu : `/spin_autotest [full|anims|calibrate]`, `/spin_prop`.

### Tests
- Nouveau : tests/finishes_test.lua (24 vérifications : pièces, éclatement, rail, points) et tests/launchers_test.lua (28 : catalogue, effets, boutique, inventaire, jauge d'un match). tests/emulator.lua, scénario 7 : bruit réseau propre au scénario et éclatements coupés (l'écart d'affichage dépendait de la durée des manches des scénarios précédents).
- Non fait : nouveaux modèles 3D (stade à rail visible, grande arène de tournoi, arène portable, lanceurs), choix des positions d'arènes par configuration.

## Spectacle du combat et rotation gauche — 2026-10-28 (demande de Maxim, d'après ses images de toupies de combat)

**Rien n'est testé en jeu.** Vérifié hors jeu seulement : natives simulées et émulateur (voir « Tests »).

- **Étincelles.** Les contacts font une gerbe d'étincelles `core/ent_brk_sparks` (déjà utilisée par aeom_mechanic) au lieu de la bouffée de flamme `veh_backfire` : choc 0,30, paroi 0,18, éjection 0,40 (`Effects.PTFX`, retour arrière noté en commentaire). `spin_out` et `wobble` ne font plus d'étincelles (ils en faisaient : ce ne sont pas des chocs).
- **Éclairs.** Chaque choc éclaire la cuvette (`DrawLightWithRange`, couleur étincelle ; rouge à l'éjection), selon sa force, pendant le flash existant (380 ms).
- **Traînées lumineuses** derrière chaque toupie, de la couleur de sa peinture, plus vives quand elle tourne vite, éteintes à l'arrêt (320 ms de trace, deux brins `DrawLine`), plus une lueur colorée sous chaque toupie.
- **Poches éclairées.** Les poches de sortie de la table sont soulignées en ambre pendant le match ; celle par où une toupie sort clignote en rouge 1,6 s.
- **Fins réalistes.** Éjectée : la toupie vole hors de la table (direction de sa sortie), tombe au sol, rebondit, glisse et reste couchée jusqu'à la fin du maintien (avant : elle filait 0,65 s puis disparaissait). Arrêtée : elle bascule sur le côté (68°, 450 ms, petit rebond). En mouvement : elle penche vers l'intérieur de ses virages (14° au plus).
- **Ralenti du coup final.** Après une éjection ou un arrêt décisif, la dernière seconde (1,2 s) est rejouée à 0,4 fois la vitesse, avec étincelles, éclairs et sons, et « RALENTI » à l'écran pour sa propre table. Seules les keyframes déjà reçues sont relues : aucun message réseau de plus. Le maintien de fin est prolongé de la durée du ralenti (~4 s), borné ; une nouvelle manche l'interrompt.
- **Lanceurs visibles par tous** (`client/launcher_rivals.lua`). Chaque client affiche, dans la main des autres participants, une copie locale de leur lanceur et de leur toupie accrochée ; elle s'emballe quand le serveur annonce que ce côté a lancé (« prêts »), puis vole vers la cuvette au GO. Le serveur ajoute `srcs` (identifiants serveur des deux joueurs, 0 pour l'adversaire simulé) à l'en-tête de manche ; le client les borne. Pas de cordon chez les autres : la prise et le tirage d'un autre joueur ne sont pas transmis.
- **Geste de lancer dynamique.** Au GO, le personnage fait un lancer vers l'avant et le bas (`anim@heists@narcotics@trash` / `throw_b`, déjà utilisé par aeom_petitsboulots et uw_needs), préchargé pendant la préparation ; repli sur l'ancien geste « donner » si le dictionnaire manque. Au tirage, le lanceur recule d'un coup (`PROPS.kick`).
- **Sons.** Sifflement de rotation qui suit la vraie rotation de la toupie suivie (sa propre toupie ; la plus rapide pour un spectateur) et s'éteint à l'arrêt ; il remplace le fond sonore fixe de 65 s. Bruit métallique au choc et frottement contre la paroi (bruit filtré, synthèse Web Audio originale). Le sifflement est borné (120 s au plus, silence après 1,5 s sans nouvelle, coupé à la fin).
- **Toupie selon ses pièces.** La silhouette 3D suit l'anneau monté (`Stats.model`) : griffes → attaque, bouclier → défense, lisse → équilibre, standard ou inversé → endurance, ou mobilité sur une pointe gomme/plate. Avant : la famille du kit le plus proche. Les cinq kits gardent leur silhouette. Les couleurs (traînée, lueur) suivent la peinture.
- **Rotation gauche.** Nouvelle pièce `ring_reverse` « Anneau inversé » (20 points, `dir = -1`, réserve de rotation −25). Le moteur gérait déjà le sens (glissement au contact et contre la paroi) : même sens = chocs durs, sens contraires = contacts doux, manches plus longues. Sans contrepartie l'inversion seule gagnait presque tout ; avec w0 −25 elle devient une réponse à l'attaque, perdante contre l'endurance et l'équilibre en sens normal (banc dans docs/PHYSICS.md §19). Boutique et atelier affichent « rotation gauche ». Icône : celle de l'anneau standard en miroir, teintée violet (`spin_part_ring_reverse.png`, `web/img/parts/ring_reverse.webp`).
- **Réglages** : `Config.spectacle` (config/shared.lua) ; chaque bloc se coupe par `enabled = false`.

### À faire avant de tester

- Copier `install/images/spin_part_ring_reverse.png` dans `ox_inventory/web/images/` (sinon l'anneau inversé affiche une image cassée dans l'inventaire). Rien n'a été copié : autre ressource.
- Relancer Chaos_Arena (`ensure Chaos_Arena`) au prochain redémarrage ; aucun changement SQL.

### À vérifier en jeu

1. Taille et lisibilité des étincelles `ent_brk_sparks` sur une toupie de 10 cm (`Effects.PTFX.*.baseScale`) ; force des éclairs (`impactLight.intensity`) de jour et de nuit.
2. Traînées : visibles à 2-5 m sans clignoter ; lueur sous les toupies pas trop forte (`trails.glowIntensity`).
3. Poches : lignes ambre posées sur le rebord de chaque modèle de table (Bastion, Atelier, Prism, Vector) et pas dans le vide.
4. Toupie éjectée : vol crédible, posée sur le sol (le sol sous la table est supposé plat, à la hauteur de l'origine du modèle), pas enfoncée ni en l'air, couchée sur le côté.
5. Toupie arrêtée : bascule dans la cuvette sans traverser le fond.
6. Ralenti : se déclenche après une éjection ou un arrêt, dure ~3 s, n'empêche pas la manche suivante ni l'écran de fin de match.
7. Lanceurs des autres : visibles par l'adversaire et un spectateur, bien dans la main, toupie qui s'emballe quand l'autre a lancé, envol au GO, rien ne reste en main après le geste ; avec 2 vrais clients.
8. Geste `throw_b` : rendu avec le lanceur en main (il peut demander de réajuster `/spin_prop hand`) ; recul au tirage.
9. Sifflement de rotation : volume, montée/descente avec la rotation, silence à la fin et en quittant la zone.
10. Anneau inversé : la toupie tourne visiblement dans l'autre sens (en main et dans la cuvette), achat et assemblage, icône dans l'inventaire.
11. FPS avec 4 tables en combat à portée (lumières dynamiques et lignes en plus).

### Tests

- Nouveau `tests/spectacle_test.lua` (38/38, natives simulées, vrais fichiers client) : rotation gauche et silhouettes, poches, traînées, inclinaison, combat complet (lanceurs des deux duellistes chez un spectateur, envol et rangement, étincelles sans wobble, éclair, poche qui clignote, toupie éjectée au sol hors de la table et couchée, ralenti 0,4×, maintien prolongé puis nettoyage), toupie arrêtée qui bascule, réglage coupé, participant (seul le lanceur adverse ajouté, sens de rotation connu, emballement quand l'adversaire a lancé).
- `combat_audio_test.js` étendu (une seule voix de sifflement, bornée, coupée par le niveau 0 et par l'arrêt) ; `launcher_props_test` (51/51) attend le nouveau geste ; `icons_mapping_test` couvre l'icône ajoutée.
- Toutes les autres suites Lua et JS : mêmes résultats qu'avant ces changements.
- **Suites émulées réparées (28/10).** Depuis la centralisation du pont (27/10), `bridge/server.lua` appelle `exports['aeom-bridge']`, absent des émulateurs : toutes les suites émulées échouaient au chargement. Nouveau `tests/helpers/with_bridge.lua`, appelé par chaque test émulé : il charge `[creations]/aeom-bridge` (serveur seul) avant Chaos_Arena et simule `SetBlockingOfNonTemporaryEvents`. `part_icons_test` retire la Pointe bille de `partIcons` le temps de l'achat (elle a une icône depuis le 21/10). Les 62 suites Lua de `tests/` et `tests/fivem_emu/` passent sous Windows (`FIVEM_EMU=D:/FXServer/tools/fivem-emulator`) ; `cfx_integration.lua` reste le harnais CfxLua, à lancer sur un vrai serveur.
- **Accueil et vendeur sans script de ciblage** (`client/concierge.lua`, `client/shop_vendor.lua`) : si `TargetCompat` vaut nil (ni ox_target ni qb-target), le PNJ est posé sans option au lieu de lever une erreur. Avec ox_target, rien ne change.

## Lanceur à tirette et combats moins réglés — 2026-10-28 (demande de Maxim)

- **Lancer en trois gestes.** ← / → incline le lanceur (bord · droit · centre), ESPACE **tenu** saisit la tirette au bon moment sur la jauge (la prise), ESPACE **relâché** tire : le serveur mesure la durée entre les deux messages, idéale de 150 à 450 ms (`pullMinMs`, `pullMaxMs`, `pullFadeMs`). Qualité = 55 % prise + 45 % tirage (`gripWeight`). La commande `spin_launch` reste un appui rapide : tirage nul, qualité plafonnée à `gripWeight` (« bon » au mieux).
- **Serveur seul juge.** Nouveau callback `spin_arena:launch_grip` (schéma strict, limite de fréquence, nonce à usage unique) ; `launch_release` accepte `tilt` (−1, 0, 1, entier). Rien de numérique n'est renvoyé : seulement des libellés (`grade`, `grip`, `pull`). Le client n'envoie ni force ni durée.
- **Inclinaison.** Elle ajoute ±`tiltAngle` (45°) à la direction de lancement ; un lancer vers le centre aide nettement contre l'endurance (+10 à +12 points mesurés pour équilibre et mobilité), sans qu'aucun choix ne domine les autres. L'inclinaison ne change ni la position ni la rotation de départ.
- **Effet du lancer.** `speedGain` passe de 5 à 15 % (±25 % passent aussi le test). `spinGain` reste à 1 % : dès ±2 % un favori s'inverse (`tests/launch_unit_test.lua`, mesuré le 28/10).
- **Combats.** Départ aléatoire par toupie (`startSpread`, `startRadiusJitter`, `launchJitter`, `w0Jitter`), rythme de plongée propre à chaque toupie (`flowerJitter`), recherche de l'adversaire selon attaque − défense/2 (`kSeek`), bruit plus fort (`sigma` 0,05 → 0,2) tempéré par la stabilité (`stabNoise`). Toutes les constantes sont facultatives pour le moteur : à 0, on retrouve l'ancien comportement.
- **NUI.** Le lanceur est dessiné d'après le vrai modèle `spin_launcher` (tube à bande cyan, molette, poignée pistolet à bagues, gâchette, griffes à témoin cyan, toupie suspendue dessous, tirette arrière). Il s'incline avec le choix ; le cordon sort de la tirette pendant la prise (même courbe qu'en jeu : tendu jusqu'à la fin de la zone verte, puis il retombe), claque au tirage pendant que la toupie floute. Jauge de tirage verte puis rouge, détail « Prise · Tirage », sons synthétisés. Sans `:has()` (navigateur CEF ancien).
- **En jeu : vraie animation avec props** (`client/launcher.lua`). Le lanceur est dans la main droite et **la toupie du joueur est accrochée sous ses griffes** (avant, seule la toupie était tenue). ESPACE tenu : un cordon (DrawLine, deux brins et une poignée) sort de la tirette arrière et se tend, le lanceur tremble ; relâché : le cordon claque, la toupie s'emballe (vitesse selon la qualité renvoyée par le serveur) ; au GO, elle quitte les griffes et **vole jusqu'à son point de départ dans la cuvette** au lieu de disparaître (celle de la cuvette reste masquée pendant l'envol). Props locaux : seul le lanceur les voit. Un fil d'animation tourne à chaque image seulement quand quelque chose bouge. `Launcher.PROPS.enabled = false` rend l'ancien comportement.
- **Réglage en jeu : `/spin_prop`.** Le repère de l'os de la main ne se devine pas hors jeu : `/spin_prop demo` rejoue prise, tirage et envol sans match ; `show` / `off` gardent le lanceur en main ; `hand x y z rx ry rz` et `mount y topZ` repositionnent à chaud ; `print` écrit les valeurs à recopier dans `Launcher.PROPS` (`hand`, `mount`). Valeurs de départ non vérifiées en jeu.
- **Limites.** Aucun modèle de cordon n'existe et Blender n'est pas installé : le cordon est tracé, pas modélisé. La main gauche ne tire pas le cordon (aucune animation de tirage vérifiée sur le serveur). Les autres joueurs ne voient pas le lanceur (props locaux).
- **Touches.** `RegisterKeyMapping` : `+spin_pull` (ESPACE), `spin_tilt_edge` (←), `spin_tilt_center` (→). L'ancienne touche « Lancer la toupie » (`spin_launch`) n'est plus liée : si ESPACE déclenche aussi un lancer rapide, retirer l'ancien raccourci dans les paramètres de FiveM.
- **Tests.** `launch_test` L10 (53/53), `launch_unit_test` (11/11), `launch_gauge_test.js`, et `tests/fivem_emu/launch_client_test.lua` (vrai client et vrai serveur : inclinaison, prise, tirage, double prise, relâchement avant la réponse du serveur). `tests/launcher_props_test.lua` (51 vérifications, natives simulées) couvre props, cordon, emballement, envol, nettoyage et `/spin_prop` ; il a révélé et fait corriger deux défauts (props recréés après l'envol, prise tardive d'un match terminé). `practice_client_test` : 500 ms laissées au spectateur (RTT 200 ms) avant de vérifier qu'il a reçu la fin. Rendu des props dans la main, orientation, animations et sons : à vérifier dans GTA.

## Tables sur pied — 2026-10-19 (demande de Money, modèles de Fermi)

- Les 4 variantes prennent les nouvelles tables sur pied : Standard → **Bastion**, Compacte → **Atelier**, Éjection → **Prism**, Large → **Vector**. La géométrie simulée ne change pas : mêmes rayon, profondeur et poches, avec un paraboloïde vérifié et 0 relief dans la cuvette. Chaque modèle a son `floorHeight` (0,800 / 0,780 / 0,820 / 0,760 m), ce qui fixe la hauteur des toupies et des panneaux, et son `rOuter` (rayon hors tout), utilisé pour les écarts entre tables et avec le vendeur.
- Les stations ne bougent pas (`data/arenas.json` inchangé) ; la station actuelle `legion_square` (Standard) devient visuellement une Bastion. **Retour arrière :** les anciens `model`, `floorHeight` et `rOuter` sont notés en commentaire dans `config/shared.lua`, et les cuvettes restent dans `stream/`.
- `stream/spin_arena_tables_pedestal.ytyp` est déclaré dans `fxmanifest.lua`.
- Écarts vérifiés sur les 4 stations installées : de 3,4 à 4,8 m entre tables (minimum requis 2,9 à 3,15 m), de 5,0 à 9,8 m du vendeur.
- Tests : les attentes sont lues dans la config (aucun nom de modèle codé en dur) ; `variants_test` 19/19 ; `hologram_multiscene` (Babbage) vérifie z = topZ + hauteur avec 0,800 / 0,780 m. Rendu, hauteur réelle par rapport au ped et collision du joueur : à vérifier dans GTA.

## Plusieurs combats visibles — 2026-10-19 (demande de Money)

- **Serveur :** un joueur suit jusqu'à `arena.maxWatched` = 4 matchs à portée, son propre match compris. Avec 1, on retrouve l'ancien comportement. Au-delà de ce plafond, il ne reçoit rien de plus. Nonces et entrées restent réservés aux participants.
- **Client :** une scène par match. Son propre duel reste la scène principale : texte à l'écran, sons de départ, lanceur. Les combats voisins sont rendus à côté. Au-delà de `Renderer.MAX_SCENES` = 4, les scènes les plus lointaines passent en mode réduit : état à jour, mais sans toupies ; elles ne sont jamais supprimées en silence. Les fins, annulations et désabonnements sont indépendants.
- **Panneaux (contrat avec Babbage) :** `Renderer.scenes()` renvoie des copies triées par distance (table, variante, état, départ, score, prêts, vainqueur…) ; `Renderer.onScenesChanged(cb)` prévient à chaque changement. Une annulation reste annoncée 5 s.
- Tests : `multi_scenes_test` 16/16 (deux duels proches, une spectatrice qui voit les deux, paquets intercalés, sortie puis retour, plafonds, annulation ; mutations vérifiées), `review_phase2` adapté (13/13). FPS et rendu à l'écran non mesurés : à vérifier en GTA.

## Tables variantes — 2026-10-19 (demande de Money)

- **Modèles 3D (Fermi, 7be4389) :** Compacte, Éjection et Large, plus la Standard, avec leur collision.
- **Paramètres serveur :** chaque station fixe a sa variante (`data/arenas.json`, champ `variant`, Standard par défaut) et le serveur simule SA géométrie (rayon, profondeur, poches). Le moteur ne gère pas de frottement propre à une table : la Large n'est « glissante » que par sa faible pente. Participants et joueurs autour reçoivent le même modèle et la même géométrie. Mesure sur 160 combats par table : éjections Standard 12 %, Compacte 21 %, Éjection 32 %, Large 37 %, toutes les manches bornées.
- **Stations ajoutées :** `legion_compact`, `legion_ejection` et `legion_glide`, autour de `legion_square` (coordonnées de Fermi, z = 30,137 comme la station actuelle). Écarts entre 3,4 et 4,8 m (minimum 2,76 à 2,98 m), et 5,0 à 9,8 m du vendeur. **Terrain, mobilier et z à vérifier dans GTA.** La station actuelle et le vendeur ne bougent pas.
- `/spin_admin arena add <nom> [standard|compact|ejection|glide]` refuse une table trop proche d'une autre (rayons hors tout + `minGap`) ou du vendeur. Un seul blip par groupe de tables (moins de 15 m).
- **Limite ouverte :** un joueur ne voit encore qu'UN combat à la fois (une scène client, une audience serveur). Plusieurs combats simultanés sur des tables voisines sont simulés, mais un joueur autour n'en voit qu'un : lot multi-scènes à venir.
- Tests : `variants_test` 18/18 (mutations vérifiées), `bowl_variants_test` 3/3.

## Assemblage dans ox_inventory — 2026-10-19 (demande de Money)

- Construction des toupies par glisser-déposer dans l'inventaire ox_inventory, en utilisant le hook `swapItems` de la version 2.45.0 installée, sans API de glisser-déposer inventée. L'échange ox est annulé et l'opération journalisée de l'atelier est faite à la place, dans un fil, sans aucune attente SQL dans le hook :
  - pièce sur toupie, ou toupie sur pièce : la pièce est montée et l'ancienne revient ;
  - kit de réparation sur toupie : usure remise à zéro ;
  - pièce sur pièce d'un autre emplacement : nouvelle toupie en montage, avec un nouvel uid ;
  - deux pièces du même emplacement : simple échange de cases.
- Toupie incomplète enregistrée telle quelle en base (JSON partiel, sans migration), visible et modifiable, mais refusée en combat (`top_invalid`) jusqu'aux quatre emplacements. Budget vérifié à chaque ajout.
- Refus sans rien consommer : toupie verrouillée, demande déjà en cours pour le joueur (`busy`), dépassement du budget, identifiant déjà pris. Hors de l'inventaire du joueur (autre joueur, coffre, sol), le comportement ox ordinaire est conservé. Retour au joueur par `spin_arena:cl:notify` (`assemble_ok`, `assemble_new`, `repair_ok` ou code d'erreur).
- Tests : `assembly_test` 23/23 avec le mock ox_inventory de l'émulateur (même payload d'échange), mutations vérifiées. Non essayé dans la vraie interface ox_inventory ni dans GTA.

## Station physique — 2026-10-19 (demande de Money)

- Cuvette permanente à chaque station fixe, hors combat (`Renderer.syncStationProps`) : objet local figé, recréé seulement si la liste des stations change, réessai pendant le chargement du modèle, nettoyé à l'arrêt. Un combat sur la station réutilise sa cuvette au lieu d'en créer une seconde et ne la supprime pas.
- Cuvette `spin_arena_bowl` : collision embarquée dans le `.ydr` (Blender + Sollumz, forme simplifiée : paroi, rebord, fond à 0,75 m), apparence inchangée (textures et sommets identiques). Activée sur la cuvette permanente des stations ; désactivée sur les cuvettes de combat improvisé, qui apparaissent sous les joueurs. `build_all.sh` la réapplique. À confirmer en GTA.
- Station `legion_square` et vendeur aux coordonnées de Money : X, Y et cap conservés. Z fourni = 31,117 (hauteur du ped) ; Z enregistré = **30,137**, sol calculé par la convention de `/spin_admin arena add` (ped − `pedToGround` 0,98). À confirmer en GTA.
- Le modèle est une **cuvette sur pied** (1,40 × 1,40 × 0,894 m), pas une table d'arène.

## Boutique unique — 2026-10-18 (demande de Money)

- Une seule interaction ox_target sur le vendeur (« Boutique SPIN ARENA ») ouvre l'onglet **Boutique** de l'interface Arena, avec les catégories en onglets internes : Toupies, Lanceurs, Pièces détachées, Réparation. Fini les quatre options sur le PNJ, la zone ox_target en double au même endroit et les cinq boutiques natives d'ox_inventory qui ajoutaient leurs propres cibles.
- Achat par le nouveau callback `spin_arena:shop_buy` : seuls l'identifiant d'article (`catégorie:clé`), la quantité et le point de vente partent du client. Le serveur revérifie la boutique, les 3 m, l'article dans **son** catalogue, la quantité (objets non empilables : 1 ; empilables : 1 à `shop.maxCount`), les toupies réelles, l'argent (`shop.currency`, objet ox_inventory) et la place, puis débite et livre ; remboursement si la livraison échoue. Fréquence limitée (`rateLimits.shopBuy`), schéma strict (un champ prix est refusé).
- Interface : solde affiché, articles trop chers désactivés, messages d'erreur en français, libellés échappés.
- Débit, livraison et remboursement vérifiés (erreur levée = échec) ; si ni la livraison ni le remboursement ne passent, l'achat est consigné comme **non résolu** (console, `/spin_admin achats`) sans prétendre avoir remboursé ni réessayer à l'aveugle. Les trois appels sont des exports synchrones : la source ne peut pas changer de joueur pendant l'achat.
- Cuvette `spin_arena_bowl` : collision embarquée dans le `.ydr` (Blender + Sollumz, forme simplifiée), apparence inchangée (textures et sommets identiques). Activée sur la cuvette permanente des stations (on ne la traverse plus) ; désactivée sur les cuvettes de combat improvisé, qui apparaissent sous les joueurs. `build_all.sh` la réapplique. À confirmer en GTA.
- Station `legion_square` : X, Y et cap fournis par Money conservés. Z fourni = 31,117 (hauteur du ped, relevée comme le vendeur) ; Z enregistré = **30,137**, sol calculé par la convention de `/spin_admin arena add` (ped − `pedToGround` 0,98). À confirmer en GTA.
- Tests : `review_shop` réécrit sur `Shop.buy` (18/18, dont remboursement, livraison qui lève une erreur, remboursement refusé ou en erreur, vérifiés par mutation), parcours `phase3_4_client` (62/62) et `phase4_smoke` (23/23) par le vrai callback, `nui_test` (9/9), `shop_vendor_test`, nouveau `shop_web_test.js`. Non essayé en jeu.

## 0.5.1 — matériel et compatibilité RP, 2026-10-18

- Accueil F7 utilisable sans viser une entité, avec atelier, défis en cours, boutique, classement et tournois. Six cas de câblage vérifiés.
- Quatre icônes d'inventaire originales en SVG et PNG transparent, générées par un outil Python sans bibliothèque externe.
- Validation client d'assemblage alignée sur le coût numérique renvoyé par Stats.validate ; des statistiques mises en cache ne rendent pas une toupie incomplète sélectionnable.
- Événements de fin, annulation et désabonnement filtrés par identifiant de match : un ancien message retardé n'efface plus le duel courant. Neuf cas de régression couverts.
- Lanceur réel requis par défaut ; possession et identité revérifiées après les attentes SQL de création du match. Les verrous sont libérés si le matériel ou le personnage a changé.
- Nettoyage du lanceur limité à ses animations actives ; aucun effacement global des animations secondaires lorsqu'une scène de spectateur se ferme.
- Journal du classement illisible ou non inscriptible : nouveaux combats suspendus, aucune réinitialisation silencieuse des cotes ni écrasement de la preuve. Reprise après retour de l'écriture.
- Couverture : 15 contrôles d'admission et de matériel, trois contrôles de chargement/nettoyage, onze cas de classement persistant et 160 manches entre les cinq assemblages. L'équilibrage et le rendu GTA restent à qualifier.

## 0.5.0 — candidate de qualification, 2026-10-18

- Parcours client ox_target et ox_lib : toupies possédées, boutique native, atelier, classement et tournois. Aucun profil gratuit proposé en production.
- Chargement différé du lanceur et des animations repris ; modèles locaux et zones nettoyés. La vérification visuelle GTA reste distincte.
- Pièces achetées avec une étiquette reconnues et consommées par leur identifiant de composant, sans exiger une égalité complète des métadonnées décoratives.
- Classement SQL : transaction des deux cotes et d'un marqueur de match ; journal local des résultats en attente, reprise et déduplication après une issue SQL incertaine.
- Instance d'intégration complète sur 30127, base séparée et vrais exports ESX/oxmysql/ox_inventory ; aucun changement du serveur RP ni de l'instance map 30126.
- Tests reproductibles : runner de toutes les suites Lua, migrations/contraintes sur MariaDB jetable et harness CfxLua réservé à l'instance isolée. Documentation d'installation et de recette actualisée.
- Aucune réussite visuelle ou à deux vrais clients GTA n'est revendiquée par ces contrôles serveur.

## Duel partagé — revue de phase 2, 2026-10-18

- Serveur/client de défi et match commun livrés par l'équipe, manifeste 0.2.0, ox_lib ; aucun inventaire ni versement.
- Revue indépendante : 48 contrôles du duel, 39 unités serveur, 12 régressions nouvelles, 112 tests de base et 37 contrôles historiques réussis hors jeu ; journaux persistants.
- Corrections : nettoyage avant notification, invitations toujours expirables, priorité à son propre duel, références renouvelées au rechargement, compte à rebours versionné.
- CfxLua : chargement de la phase 2 et banc debug de 100 manches relus ; écart initial source/copie résolu après redéploiement (20 fichiers identiques, dernier chargement sans SCRIPT ERROR, commit observé 0b6b4e2). Aucun vrai client ni phase 2 déclarée validée.

## Audit de validation réelle et préparation du duel — 2026-10-18

- Relecture effective du code, du manifeste, des suites et des journaux ; comparaison des neuf fichiers d'exécution source/SpinTest. Version de manifeste 0.1.0 ; code en mémoire seulement inféré des chargements/dates.
- 112 tests et 33 vérifications d'émulation relancés, self-test client et syntaxe réussis ; preuves complètes désormais conservées dans docs/evidence/audit-20261018T160012Z.
- Injection isolée d’une exception moteur : test debug restant occupé, défaut confirmé puis corrigé par l’équipe ; source revérifiée à 112/112 et 37/37 émulation, sans panne provoquée dans le serveur réel. Copie serveur différente : correction non encore déployée au contrôle de 16:11:22 UTC.
- Procédure GTA avec seeds vérifiées, fiche de relevé, plan du duel partagé, fichiers concernés et huit cas d'acceptation ajoutés. Aucun rendu réel ou duel partagé déclaré validé.
- Aucun redémarrage de serveur ni modification de code de jeu par Turing dans cet audit ; adaptation des chargeurs de tests au runner extrait en parallèle par l’équipe, 112/112 et 37/37 revérifiés ; aucune donnée métier supprimée. Inventaire, progression et tournois restent en attente.

## Prototype physique — 2026-10-18, en développement

- Conception approuvée ; phase 1 autorisée, dossier Chaos_Arena conservé.
- Ajout d'un runner Lua indépendant et de tests sur le contrat du moteur réel : validation d'entrées, générateur local, états finis, borne de durée, reproductibilité, interleaving et fin idempotente.
- Banc CPU optionnel sur les mêmes seeds à 120 et 60 Hz ; mesures p50/p95/p99, coût par pas, nombre de keyframes/événements et mémoire Lua retenue.
- 112 tests réussis : 108 physiques sur le moteur réel en Lua 5.4.6 et 4 sur l’adaptateur de commande avec une horloge simulée ; banc 100 seeds à 120 et 60 Hz exécuté, mesures et empreintes dans PROJECT_STATUS.md. Banc FiveM serveur exécuté séparément ; aucun test visuel ou multijoueur exécuté.
- Moteur et rendu temporaire livrés par l’équipe ; événement moteur normalisé et régressions du rendu corrigées (statuts terminaux et watchdog de fin). Self-test client réussi hors jeu. Commande admin et manifeste livrés ; intégration en jeu et documentation en cours de finalisation ; aucune intégration inventaire/SQL/NUI dans cette phase.

- Validation serveur CfxLua sur instance isolée : ressource chargée et 300 manches simulées, 186 victoires attaque / 114 endurance, sans client ; journal vérifié et résultats détaillés dans PROJECT_STATUS.md.
- Diffusion debug ajustée : dernière demi-seconde découpée en tranches de 0,1 s sans avance ; 110 tests relancés avec succès après ce changement. Essai visuel en jeu restant nécessaire avant la phase 2.

- Second banc serveur de 300 manches avec OneSync activé, journal vérifié et convar confirmée via info.json : 173 victoires attaque / 127 endurance ; toujours sans validation client ou multijoueur.

- Émulateur de joueurs ajouté par Archimedes : vrai code client/serveur, natives et réseau virtuels ; revue indépendante finale 33/33 réussie après correction de l’ordre du compte à rebours, des doublons d’en-tête et de la réception tardive des trames. Réseau/natives simulés, sans client GTA.
- Correction des trames avant collision : position, rotation, oscillation et statut du tick précédent conservés ; suite étendue à 112 tests réussis et banc CPU Lua remesuré.

- Nouveau banc CfxLua après correction des keyframes et de l’horloge : 300 manches, 189 victoires attaque / 110 endurance / 1 nul, OneSync confirmé actif, source et copie de test identiques ; journal relu. Toujours aucun test client GTA ou duel partagé.

## Conception initiale — 2026-10-18, sans version exécutable

- Cahier des charges utilisateur conservé intégralement.
- Audit du dossier Chaos_Arena initialement vide, des dépendances et des API installées.
- Architecture serveur/physique/sécurité et direction rendu/NUI soumises à revue d'équipe.
- Plan de tests par phase et suivi séparant calculs automatiques, FiveM et multijoueur.
- Nom du produit provisoire, licence et ressources artistiques finales non attribuées.
- Aucune implémentation de gameplay, aucun item/migration installé et aucun test de match revendiqué.
- Passage au prototype physique suspendu à la validation explicite de la conception par l'utilisateur.

### Boutique fixe — 18 octobre 2026

- Vendeur local à Legion Square, interaction ox_target vers la boutique ox_inventory existante.
- Achats partout désactivés ; nettoyage à l’arrêt et protection contre les chargements de modèle devenus obsolètes.
- 22 suites Lua/émulation réussies ; placement du vendeur en GTA restant à vérifier.

### Fenêtre ajustable — 18 octobre 2026

- Déplacement par le titre, redimensionnement au coin, recentrage et réglage au clavier.
- Mémorisation locale des proportions ; fenêtre bornée et contenu réorganisé après changement de résolution.
- Tests de géométrie et de cycle pointeur sur 11 dimensions, dont ultrawide ; rendu GTA non qualifié.

### Accueil et vendeur séparés — 18 octobre 2026

- Raccourci F7 et options globales retirés ; accueil Arena sur un PNJ dédié à l’ancien emplacement.
- Vendeur à 225.5, -798.2, 30.7, avec quatre catégories et son blip.
- Nettoyage des deux PNJ et régressions des accès testés hors jeu ; placement réel à vérifier.
