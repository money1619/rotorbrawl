# Registre des Ressources Artistiques, Dépendances et Licences — SPIN ARENA

Date : 18 octobre 2026 (Phase 0 — Audit et conception uniquement).

---

## 1. État réel des fichiers à la Phase 0

Conformément aux règles de transparence (sections 4, 8, 14 et 15 du cahier des charges) :

- **Aucun modèle 3D (`.ydr`), aucune archive de textures (`.ytd`), aucun manifeste d'archétypes (`.ytyp`), aucune collision (`.ybn`), aucune animation personnalisée (`.ycd`), aucun fichier audio et aucune image d'interface ou d'inventaire (`.png`, `.svg`, `.webp`) n'est présent dans `resources/[Money]/Chaos_Arena` à la Phase 0.**
- Aucun fichier 3D ou multimédia fictif n'est inventé ni déclaré livré.
- Aucun fichier `LICENSE` produit n'est créé en Phase 0 : le titulaire des droits et la licence commerciale finale du projet **SPIN ARENA** (dont le nom lui-même demeure provisoire jusqu'à vérification juridique de disponibilité) devront être arrêtés par l'utilisateur avant toute distribution.

---

## 2. Politique de Propriété Intellectuelle et de Conformité Commerciale

Toute ressource graphique, sonore, 3D ou typographique intégrée à SPIN ARENA au cours des Phases 1 à 7 doit respecter impérativement les critères suivants avant d'être ajoutée au dépôt :

1. **Création originale ou licence commerciale explicite** :
   - Chaque asset doit être soit créé sur mesure pour SPIN ARENA (avec cession ou titularité des droits documentée), soit acquis sous une licence autorisant explicitement **l'intégration et la redistribution dans un produit commercial payant** (ex. CC0 1.0 Universal, licence commerciale studio signée avec droit de sous-distribution embarquée).
   - **Interdiction des licences restreintes** : aucune ressource sous licence *CC BY-NC* (Non-Commercial), *Editorial Use Only*, *Personal Use Only* ou à licence absente/ambiguë n'est autorisée.
2. **Exclusion absolue de toute franchise existante** :
   - Interdiction formelle d'utiliser le nom *Beyblade* ou tout nom de gamme, logo, silhouette caractéristique, pièce iconique, rip de jeu vidéo, enregistrement audio ou illustration provenant d'une marque existante.
3. **Traçabilité obligatoire avant commit** :
   - Aucun fichier ne peut entrer dans `stream/`, `web/` ou les images `ox_inventory` sans une entrée complète dans la section 4 du présent registre précisant : **Auteur**, **Source / Outil de création**, **Licence exacte**, **Preuve d'autorisation commerciale** et **Contrôle technique adapté au format** (inspection partielle via `unified-gta-tool` uniquement pour les formats GTA qu'il prend en charge — `.ydr`, `.ytd`, `.ytyp`, `.ycd` — non applicable aux `.png`, `.svg`, `.ogg` ni aux `.ybn` autonomes, et toujours complétée par un test en jeu).

---

## 3. Dépendances logicielles externes observées (Non incluses dans la ressource)

Ces composants sont installés sur le serveur FiveM cible et appelés par leurs interfaces publiques documentées dans [`docs/AUDIT.md`](AUDIT.md). Ils ne sont **jamais copiés** à l'intérieur du dossier de la ressource SPIN ARENA :

| Dépendance | Version observée sur le serveur | Emplacement observé | Licence amont déclarée (référence) | Mode d'utilisation par SPIN ARENA |
|---|---|---|---|---|
| **ESX Legacy (`es_extended`)** | `1.12.4` | `resources/[core]/es_extended` | GNU GPL v3.0 (dépôt amont ESX) | Appel d'exports/événements externes uniquement (aucune copie de code) |
| **ox_inventory** | `2.45.0` | `resources/[ox]/ox_inventory` | GNU GPL v3.0 (Overextended) | Appel d'exports serveur (`GetSlot`, `AddItem`, `RemoveItem`, `SetMetadata`, `registerHook`) |
| **ox_lib** | `3.32.3` | `resources/[ox]/ox_lib` | LGPL v3.0 (Overextended) | Chargement via `@ox_lib/init.lua` externe |
| **oxmysql** | `2.12.0` | `resources/[ox]/oxmysql` | LGPL v3.0 (Overextended) | Chargement via `@oxmysql/lib/MySQL.lua` externe |

---

## 4. Registre prévisionnel des assets requis par phase

Tant qu'une ligne porte le statut **`Non créé (Phase 0)`**, le code des Phases 1 et 2 doit obligatoirement utiliser la colonne **Solution de repli (Phase 1–2)** sans référencer le fichier final inexistant.

### 4.1 Modèles 3D et collisions (`stream/`) — Cible : Phase 3

| ID Asset | Catégorie & Description | Fichiers cibles prévus (`stream/`) | Statut actuel | Solution de repli autorisée (Phases 1–2) | Auteur / Source | Licence requise | Validation technique |
|---|---|---|---|---|---|---|---|
| `AST-3D-001` | **Toupie Famille Attaque** (*Apex Striker* — couronne angulaire usinée) | `sa_top_attack.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Prop natif GTA V (à vérifier sur build `2699`) + marqueur `DrawMarker` (Cyan/Orange) | À produire / commander | Originale / Commerciale | Contrôle partiel `unified-gta-tool` (`.ydr`/`.ytd`) + test stream en jeu FiveM |
| `AST-3D-002` | **Toupie Famille Défense** (*Aegis Bastion* — anneau massif haute inertie) | `sa_top_defense.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Prop natif GTA V (à vérifier sur build `2699`) + marqueur `DrawMarker` | À produire / commander | Originale / Commerciale | Contrôle partiel `unified-gta-tool` (`.ydr`/`.ytd`) + test stream en jeu FiveM |
| `AST-3D-003` | **Toupie Famille Équilibre** (*Vector Nexus* — profil hybride symétrique) | `sa_top_balance.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Prop natif GTA V (à vérifier sur build `2699`) + marqueur `DrawMarker` | À produire / commander | Originale / Commerciale | Contrôle partiel `unified-gta-tool` (`.ydr`/`.ytd`) + test stream en jeu FiveM |
| `AST-3D-004` | **Toupie Famille Endurance** (*Chrono Gyro* — volant d'inertie lisse, pointe faible friction) | `sa_top_stamina.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Prop natif GTA V (à vérifier sur build `2699`) + marqueur `DrawMarker` | À produire / commander | Originale / Commerciale | Contrôle partiel `unified-gta-tool` (`.ydr`/`.ytd`) + test stream en jeu FiveM |
| `AST-3D-005` | **Toupie Famille Mobilité** (*Pulse Veloce* — châssis allégé titane, pointe réactive) | `sa_top_mobility.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Prop natif GTA V (à vérifier sur build `2699`) + marqueur `DrawMarker` | À produire / commander | Originale / Commerciale | Contrôle partiel `unified-gta-tool` (`.ydr`/`.ytd`) + test stream en jeu FiveM |
| `AST-3D-006` | **Lanceur mécanique industriel** (tenu en main par le ped) | `sa_launcher_mk1.ydr`, `sa_tops.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Animation main nue ou prop générique GTA V (à vérifier en jeu) | À produire / commander | Originale / Commerciale | Alignement bone `PH_R_Hand` en jeu + contrôle partiel `unified-gta-tool` |
| `AST-3D-007` | **Arène fixe standard** (Bol métallique concave + table industrielle) | `sa_arena_std.ydr`, `sa_arena_std.ybn`, `sa_arenas.ytd`, `sa_props.ytyp` | Non créé (Phase 0) | Tracé géométrique d'arène au sol (`DrawMarker` cylindrique/anneau) | À produire / commander | Originale / Commerciale | Concordance rayon/courbure avec `PHYSICS.md` + test collision `.ybn` en jeu |
| `AST-3D-008` | **Arène portable / monde ouvert** (Anneau déployable) | `sa_arena_portable.ydr`, `sa_arena_portable.ybn`, `sa_arenas.ytd` | Non créé (Phase 0) | Tracé géométrique au sol (`DrawMarker`) | À produire / commander | Originale / Commerciale | Concordance rayon avec `PHYSICS.md` + test en jeu |

### 4.1 bis Modèles générés par script (livrés dans `stream/`, 18 octobre 2026)

Ces fichiers remplacent, pour le prototype, les cibles prévisionnelles du §4.1 (noms `spin_*` au lieu de `sa_*`). Texture intégrée à chaque `.ydr` (atlas 256 × 256 DXT1, pas de `.ytd` séparé). Régénération : `bash tools/models/build_all.sh`.

| ID Asset | Description | Fichier (`stream/`) | Statut | Auteur / Source | Licence | Validation technique |
|---|---|---|---|---|---|---|
| `AST-3D-101` | **Cuvette de jeu sur pied (Standard)** — parabolique R = 0,60 m, h = 0,08 m, paroi 0,06 m, 3 poches de 24° (90°/210°/330°) ; fond à z = 0,750 m de l'origine (au sol) ; 1,40 × 1,40 × 0,894 m ; 5 500 tris | `spin_arena_bowl.ydr` | Livré, **collision embarquée** (polygonale simplifiée : paroi, rebord, fond à 0,75 m, matériau PLASTIC_HOLLOW ; `tools/models/build_bowl_collision.py` + `embed_bowl_collision.sh`) ; solide aux stations fixes seulement | Généré par script : `tools/models/build_bowl.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-101b` | **Cuvette Compacte** — parabolique R = 0,46 m, h = 0,09 m, paroi haute 0,075 m, 2 poches étroites de 18° (90°/270°), liseré orange ; fond à z = 0,750 m ; 1,12 × 1,12 × 0,919 m ; 5 504 tris | `spin_arena_bowl_compact.ydr` | Livré, **collision embarquée** (polygonale simplifiée R_out = 0,56 m, R_in = 0,50 m, H_top = 0,919 m, fond à 0,75 m, PLASTIC_HOLLOW) ; solide aux stations fixes seulement | Généré par script : `tools/models/build_bowl.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-101c` | **Cuvette Éjection** — parabolique R = 0,60 m, h = 0,055 m, paroi basse 0,038 m, 4 poches larges de 38° (45°/135°/225°/315°), plaques de sortie orange vif ; fond à z = 0,750 m ; 1,40 × 1,40 × 0,847 m ; 5 376 tris | `spin_arena_bowl_ejection.ydr` | Livré, **collision embarquée** (polygonale simplifiée R_out = 0,70 m, R_in = 0,64 m, H_top = 0,847 m, fond à 0,75 m, PLASTIC_HOLLOW) ; solide aux stations fixes seulement | Généré par script : `tools/models/build_bowl.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-101d` | **Cuvette Glissante** — parabolique R = 0,68 m, h = 0,045 m, paroi 0,055 m, 3 poches de 28° (90°/210°/330°), surface claire anodisée cyan ; fond à z = 0,750 m ; 1,56 × 1,56 × 0,854 m ; 5 464 tris | `spin_arena_bowl_glide.ydr` | Livré, **collision embarquée** (polygonale simplifiée R_out = 0,78 m, R_in = 0,72 m, H_top = 0,854 m, fond à 0,75 m, PLASTIC_HOLLOW) ; solide aux stations fixes seulement | Généré par script : `tools/models/build_bowl.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-102` | **Toupie Attaque** — couronne à 6 lames en dents de scie, pointe plate, noyau orange ; 0,100 × 0,094 × 0,055 m ; 1 336 tris | `spin_top_attack.ydr` | Livré | Généré par script : `tools/models/build_tops.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-103` | **Toupie Défense** — anneau épais à 8 bossages et 8 vis, pointe bille, noyau cyan ; 0,100 × 0,100 × 0,051 m ; 1 676 tris | `spin_top_defense.ydr` | Livré | Généré par script : `tools/models/build_tops.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-104` | **Toupie Endurance** — volant d'inertie à jante lourde, noyau-fuseau, pointe fine, noyau cyan ; 0,100 × 0,100 × 0,068 m ; 1 488 tris | `spin_top_endurance.ydr` | Livré | Généré par script : `tools/models/build_tops.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-105` | **Toupie Équilibre** — anneau octogonal à 4 ergots + plateau anodisé, pointe semi-plate, noyau cyan ; 0,100 × 0,100 × 0,060 m ; 1 596 tris | `spin_top_balance.ydr` | Livré | Généré par script : `tools/models/build_tops.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-106` | **Toupie Mobilité** — cadre ajouré (jante, 4 rayons, 4 ailettes), pointe caoutchouc large, noyau orange ; 0,100 × 0,100 × 0,054 m ; 1 440 tris | `spin_top_mobility.ydr` | Livré | Généré par script : `tools/models/build_tops.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-107` | **Lanceur tenu en main** — corps tubulaire, poignée, gâchette, molette, support à 4 griffes ; 0,062 × 0,144 × 0,099 m ; 1 096 tris | `spin_launcher.ydr` | Livré (attache main non réglée) | Généré par script : `tools/models/build_launcher.py` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |
| `AST-3D-108` | **Archétypes** des 10 modèles ci-dessus (`lodDist` 60 m : 4 cuvettes + 5 toupies + 1 lanceur) | `spin_arena.ytyp` | Livré | Généré par script : `tools/models/build_all.sh` + `sa_common.py` (Blender 4.5, géométrie et texture procédurales) | À définir par le propriétaire ; aucune ressource tierce (ni modèle, ni texture, ni police) | `json` + `ydr2xml` (boîte englobante) + aller-retour `ydr2glb` via `tools/models/build_all.sh` (unified-gta-tool) ; **non testé en jeu** |

### 4.1 ter Pièces de toupie, table Turbo et icônes (livrés dans `stream/` et `install/`, 29 octobre 2026)

Génération directe en `.ydr` natif par **Blender 4.0 + Sollumz 2.8.2 (PyMateria)** sur le poste de développement (sans convertisseur externe) : `tools/models/sollumz_common.py` clone le drawable d'un modèle existant (même atlas de couleurs, un seul matériau `default.sps`), remplace le maillage par celui de `sa_common.Builder` et exporte. Rendus de contrôle : réimport Sollumz + rendu Workbench. Aucune ressource tierce (ni modèle, ni texture, ni police), aucun nom ni forme d'une marque existante.

| ID Asset | Description | Fichier (`stream/`, `install/`) | Statut | Auteur / Source | Licence | Validation technique |
|---|---|---|---|---|---|---|
| `AST-3D-201` | **21 modèles de pièces de toupie**, un par pièce du catalogue, dans le repère de la toupie assemblée (origine = pointe de l'embout) : 6 embouts (Standard, Aiguille, Plat, Bille, Gomme, Engrenage, ≤ 0,020 m × 0,014 m), 5 verrous à crans (4, 5, 6, 3 pointes, 9), 6 lames (Orbite, Griffe, Rempart, Galet, Contre-courant, Scie, ≤ 0,100 m), 4 noyaux (standard, lesté, allégé, à couronne) ; 144 à 708 tris chacun | `spin_pt_<tip\|frame\|ring\|core>_<id>.ydr` (21 fichiers) | Livré (non vu en jeu) | Généré par script : `tools/models/build_parts.py` + `sollumz_common.py` + `sa_common.py` (Blender 4.0, géométrie et texture procédurales) | Création originale, propriété de l'éditeur | Réimport Sollumz : matériau et texture nommés d'après le modèle, boîtes englobantes dans l'enveloppe commune, assemblage de six toupies rendu |
| `AST-3D-202` | **Table Turbo** — cuvette R = 0,60 m, h = 0,08 m, paroi 0,06 m, 3 poches de 26°, mêmes pieds et même jupe que la table Vector (D hors tout 1,71 m) ; **rail** orange de 0,70 R à 0,80 R posé à ras de la surface (1,2 mm) avec 12 losanges cyan ; collision embarquée (cylindre creux) ; 7 112 tris | `spin_arena_table_turbo.ydr` | Livré (non vu en jeu) | Généré par script : `tools/models/build_table_turbo.py` (constructeur de `build_pedestal_tables.py`) | Création originale | Réimport Sollumz : 7 112 tris, collision composite + BVH, boîte 1,71 × 1,71 × 0,932 m ; rendu de dessus |
| `AST-3D-203` | **Archétypes** des 21 pièces et de la table Turbo (`lodDist` 60 m) | `spin_arena_parts.ytyp`, `spin_arena_stadiums.ytyp` | Livré | Exportés par Sollumz (`sollumz.export_ytyp_io`) | Création originale | Réimport Sollumz : 21 + 1 archétypes, noms résolus |
| `AST-UI-101` | **Icônes inventaire** des pièces Lame Scie, Verrou 9 crans, Embout Engrenage : variantes teintées (rotation de teinte, miroir) des icônes existantes `spin_part_ring_smash`, `spin_part_frame_low` et `spin_part_tip_flat` | `install/icons_money/ox_images/spin_part_ring_saw.png`, `…_frame_nine.png`, `…_tip_gear.png` | Livré | Dérivées par script (Pillow) des icônes de la planche Money du 19/10/2026 | Même statut que leurs sources (planche fournie par Money) | Contrôle visuel, `tests/icons_mapping_test.lua` |

### 4.2 Animations et Effets Visuels — Cible : Phase 3

| ID Asset | Catégorie & Description | Ressource / Fichier cible | Statut actuel | Solution retenue / Repli (Phases 1–3) | Auteur / Source | Licence |
|---|---|---|---|---|---|---|
| `AST-ANIM-001` | Animation de préparation, compte à rebours et lancement synchronisé | Dictionnaires d'animations natifs GTA V (ou `.ycd` custom optionnel en Phase 3) | Non sélectionné (Phase 0) | Proposition : animations natives GTA V existantes (noms à vérifier en jeu sur build `2699` avec `RequestAnimDict`) | Rockstar Games (natif runtime GTA V, non redistribué) ou création `.ycd` originale | Natif runtime (0 fichier extrait) ou Originale |
| `AST-VFX-001` | Étincelles d'impact, flash de collision et traînée énergétique | Particules natives GTA V + `DrawMarker` (à vérifier sur build `2699`) | Conception uniquement (non testé) | Effets natifs GTA V pilotés par `client/effects.lua` sans fichier binaire externe | Natif runtime GTA V | Natif runtime (0 fichier extrait) |

### 4.3 Interface NUI, Audio et Icônes d'Inventaire (`web/` & `ox_inventory`) — Cible : Phases 2 à 4

| ID Asset | Catégorie & Description | Fichiers cibles prévus | Phase requise | Statut actuel | Auteur / Source | Licence requise |
|---|---|---|---|---|---|---|
| `AST-UI-001` | Feuilles de style, scripts et composants SVG vectoriels NUI (HUD + 5 menus) | `web/index.html`, `web/style.css`, `web/app.js`, `web/assets/*.svg` | Phase 2 (HUD) / Phase 4–6 (Menus) | Non créé (Phase 0) | Création interne équipe SPIN ARENA | Code & SVG 100 % originaux |
| `AST-ICON-001` | Icône Toupie | `install/images/spin_top.png` et `.svg` | Phase 4 | Créée, 128 × 128 RGBA ; affichage GTA à tester | Géométrie originale, `tools/icons/build_icons.py`, aucune ressource externe | Distribution à définir par le propriétaire |
| `AST-ICON-002` | Icône Lanceur | `install/images/spin_launcher.png` et `.svg` | Phase 4 | Créée, 128 × 128 RGBA ; affichage GTA à tester | Géométrie originale, `tools/icons/build_icons.py`, aucune ressource externe | Distribution à définir par le propriétaire |
| `AST-ICON-003` | Icône Pièce détachée | `install/images/spin_part.png` et `.svg` | Phase 4 | Créée, 128 × 128 RGBA ; affichage GTA à tester | Géométrie originale, `tools/icons/build_icons.py`, aucune ressource externe | Distribution à définir par le propriétaire |
| `AST-ICON-004` | Icône Kit de réparation | `install/images/spin_repair_kit.png` et `.svg` | Phase 4 | Créée, 128 × 128 RGBA ; affichage GTA à tester | Géométrie originale, `tools/icons/build_icons.py`, aucune ressource externe | Distribution à définir par le propriétaire |
| `AST-SFX-001` | Chocs métalliques, paroi, éjection, rotation, lancement et compte à rebours | `web/combat_audio.js`, `client/effects.lua` | Phase 3 | Synthèse originale créée ; ordonnancement testé hors jeu, écoute CEF/GTA non validée | Turing, oscillateurs/enveloppes originaux, aucun enregistrement ni bibliothèque externe | Distribution à définir par le propriétaire ; repli natif sans redistribution d’assets GTA |

---

## 5. Procédure de validation avant passage d'un asset en statut « Validé »

Complément du 18 octobre 2026 : les icônes AST-ICON-001 à AST-ICON-004 sont désormais créées dans `install/images/` (SVG sources et PNG 128 × 128 RGBA). Auteur : génération géométrique originale par l'équipe du projet, script `tools/icons/build_icons.py`, sans ressource externe ni police. Palette graphite, métal, cyan et orange. Inspection visuelle hors jeu effectuée ; affichage dans ox_inventory encore à contrôler dans GTA. La licence de distribution reste celle à définir par le propriétaire pour le projet ; aucune licence tierce n'est supposée.

1. **Vérification de licence** : ajout du nom de l'auteur, de l'URL/contrat source et de la licence exacte dans les tableaux ci-dessus.
2. **Contrôle structurel partiel hors-ligne (`unified-gta-tool`, pour les formats GTA supportés uniquement)** : uniquement pour les fichiers `.ydr`, `.ytd`, `.ytyp` et `.ycd` (non applicable aux `.png`, `.svg`, `.ogg` ni aux collisions `.ybn` autonomes), exécution des commandes d'analyse en lecture seule (`json`, diagnostic de géométrie et formats de textures) via l'outil candidat `/home/fivem2/unified-gta-tool/unified-gta-tool-main`. **Important : une analyse par outil hors-ligne ne constitue qu'un contrôle partiel et ne garantit jamais l'absence de crash ou d'anomalie de rendu dans le client GTA V / FiveM.**
3. **Validation obligatoire en jeu FiveM (Phase 3)** : chargement réel de l'asset dans un client FiveM sur le build cible (`2699`), vérification de l'absence de crash ou d'erreur console client, contrôle du pivot $(0,0,0)$ au sol, validation des collisions `.ybn` et mesure de l'impact `resmon` / mémoire de streaming.
