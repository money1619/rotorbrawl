# Icônes d'inventaire de Money (planche du 19/10/2026) — correspondance avec le catalogue

**Statut : icônes installées et associées le 21/10/2026.** Les correspondances de la planche du 19/10 sont conservées ; trois icônes originales complètent le catalogue.

Les choix des lignes ambiguës sont **purement visuels** : les noms affichés, les identifiants et les caractéristiques des pièces ne changent pas. Une icône « disque lourd » sur le Châssis large ne rend pas ce châssis plus lourd : dans le jeu, la masse vient seulement des noyaux.

## Correspondance de la planche de Money (`ox_images/`)

| Fichier pour ox_inventory | Vignette de la planche | Pièce |
|---|---|---|
| `spin_part_ring_smash.png` | spin_ring_attaque | Anneau à griffes |
| `spin_part_ring_guard.png` | spin_ring_defense | Anneau bouclier |
| `spin_part_ring_round.png` | spin_ring_equilibre | Anneau lisse |
| `spin_part_ring_std.png` | spin_ring_endurance | Anneau standard (choix visuel) |
| `spin_part_frame_std.png` | spin_disc_standard | Châssis standard |
| `spin_part_frame_wide.png` | spin_disc_lourd | Châssis large (choix visuel) |
| `spin_part_frame_low.png` | spin_disc_leger | Châssis bas (choix visuel) |
| `spin_part_frame_spike.png` | spin_disc_special | Châssis à pics (choix visuel) |
| `spin_part_core_std.png` | spin_core_standard | Noyau standard |
| `spin_part_core_rim.png` | spin_core_avance | Noyau à couronne (choix visuel) |
| `spin_part_core_heavy.png` | spin_core_stabilise | Noyau lesté (choix visuel) |
| `spin_part_tip_flat.png` | spin_tip_plate | Pointe plate |
| `spin_part_tip_sharp.png` | spin_tip_conique | Pointe fine |
| `spin_part_tip_rubber.png` | spin_tip_mobile | Pointe gomme |
| `spin_part_ring_reverse.png` | (aucune : dérivée de `spin_part_ring_std.png`, en miroir et teintée violet, 28/10) | Anneau inversé (rotation gauche) |
| `spin_launcher.png` | spin_launcher_standard | objet Lanceur (remplace l'image actuelle, après sauvegarde) |

Les images de la planche ne couvrent pas `core_light`, `tip_std` et `tip_ball`. Trois icônes originales ont été créées pour ces pièces et ajoutées à `ox_images/` et `install/images/` : noyau allégé ouvert, pointe standard plate et pointe bille métallique. Le capot et le lanceur avancé n'existent pas dans le catalogue.

## Historique : proposition initiale

- `source/planche_money_2026-10-19.png` : la planche d'origine, intacte.
- `vignettes/*.png` : 17 vignettes de 256 × 256, découpées dans la planche. Sans titre, badge ni nom ; objet entier, proportions conservées. Le fond de chaque carte est gardé, la transparence n'est pas faite (voir « Limites »).

## Mécanisme (vérifié par Archimedes dans ox_inventory 2.45 installé)

L'interface prend `metadata.imageurl`, sinon `metadata.image` (fichier `ox_inventory/web/images/<image>.png`), sinon l'image de l'objet. Pour une icône par pièce : `metadata.image = 'spin_part_<id>'` et le fichier `spin_part_<id>.png` dans `ox_inventory/web/images`. `metadata.part` et `metadata.uid` ne changent jamais. Une image n'empêche pas de mélanger les pièces de familles différentes : l'icône n'est qu'un dessin.

## Correspondance proposée (catalogue actuel : 4 emplacements, 17 pièces)

| Vignette (planche) | Pièce du jeu (`metadata.part`) | Confiance | Raison |
|---|---|---|---|
| spin_ring_attaque | `ring_smash` (Anneau à griffes) | sûre | attaque +0,4 |
| spin_ring_defense | `ring_guard` (Anneau bouclier) | sûre | défense +0,2 |
| spin_ring_equilibre | `ring_round` (Anneau lisse) | probable | attaque −, défense +, stabilité + |
| spin_ring_endurance | `ring_std` (Anneau standard) | **à décider** | aucun anneau « endurance » dans le catalogue |
| spin_disc_standard | `frame_std` (Châssis standard) | sûre | disque → châssis (Archimedes) |
| spin_disc_lourd | aucune proposition | **à décider** | aucun châssis ne change la masse (serveur) ; « lourd » correspond plutôt à `core_heavy` (masse +0,006), qui est un noyau |
| spin_disc_leger | aucune proposition | **à décider** | aucun châssis ne change la masse ; « léger » correspond plutôt à `core_light` (masse −0,004), qui est un noyau |
| spin_disc_special | aucune proposition | **à décider** | pas d'équivalent ; candidats possibles : `frame_spike` (attaque +0,15) ou `frame_wide` (rayon +, stabilité +0,15) |
| spin_core_standard | `core_std` (Noyau standard) | sûre | |
| spin_core_avance | `core_rim` (Noyau à couronne) ? | **à décider** | inertie +0,08, la plus forte des noyaux |
| spin_core_stabilise | aucune proposition | **à décider** | aucun noyau ne donne de stabilité (stab) ; `core_heavy` a masse +, inertie + |
| spin_tip_plate | `tip_flat` (Pointe plate) | sûre | |
| spin_tip_conique | `tip_sharp` (Pointe fine) | sûre | pointe conique |
| spin_tip_mobile | `tip_rubber` (Pointe gomme) | probable | mobilité +0,4 |
| spin_launcher_standard | objet `spin_launcher` (image de l'objet) | sûre | |
| spin_launcher_avance | aucun | — | pas de lanceur avancé dans le jeu : **aucun objet créé** |
| spin_capot_standard | aucun | — | pas d'emplacement « capot » (5e emplacement = migration à part) |

**Vérification avec les caractéristiques du serveur (`config/parts.lua`)** : les châssis (= disques) changent rayon, stabilité, attaque et mobilité, jamais la masse. « Lourd » et « léger » ne s'appliquent donc à aucun châssis ; la masse se règle par les noyaux (`core_heavy` +0,006, `core_light` −0,004, `core_rim` +0,004). Les trois pièces sans visuel correspondant sur la planche ont reçu des icônes originales adaptées à leurs noms et à leurs fonctions.

**Pièces sans vignette de la planche Money** : `core_light`, `tip_std` et `tip_ball` ont maintenant leurs icônes originales décrites ci-dessus. Les pièces du catalogue ont toutes une icône dédiée.

## Association des images

Les 17 fichiers `spin_part_<id>.png` sont copiés dans `ox_inventory/web/images/` et dans `install/images/`. `config/shared.lua` active chaque identifiant dans `partIcons`; le hook `createItem` de `server/inventory.lua` pose `metadata.image = 'spin_part_<id>'` lors de la création de chaque pièce. Cette association est visuelle et ne change ni les statistiques ni `metadata.part`. Les pièces déjà présentes dans les inventaires ne reçoivent pas rétroactivement cette métadonnée.

## Limites

- **Pas de transparence** : les objets sombres sur un fond sombre, avec des halos lumineux, ne se détourent pas proprement sans un outil de détourage dédié (masque à la main ou modèle de segmentation). Un détourage automatique simple aurait abîmé les bords ou les reflets. Le fond de carte est gardé tel quel ; dans la case sombre d'ox_inventory, il reste discret.
- Ces vignettes sont des **icônes**, pas la preuve que les modèles 3D du jeu leur ressemblent.

## Application

Les PNG sont déjà copiés dans ox_inventory et les identifiants sont activés dans Chaos_Arena. ox_inventory déclare les images au démarrage (`fxmanifest.lua` : `files { 'web/images/*.png' }`) : un redémarrage d'ox_inventory sans joueur connecté est nécessaire pour servir les trois nouveaux fichiers.
