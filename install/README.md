# SPIN ARENA (Chaos_Arena) — installation des objets

ox_inventory 2.45.0 déclare ses objets dans `ox_inventory/data/items.lua` : les objets ne passent **pas** par SQL.
Le SQL du script est réel mais concerne ses **données** (toupies, classement, journal) : `sql/install.sql`, rejouable,
et exécuté de toute façon au démarrage par `server/database.lua` si oxmysql est présent.

## Contenu
| Fichier | Rôle |
|---|---|
| `ox_inventory_items.lua` | Référence des 4 définitions `spin_*` ; le fichier principal du dépôt contient maintenant ces mêmes objets |
| `images/` | Icônes à copier dans ox_inventory : les 4 objets + les 18 pièces `spin_part_<id>.png` + leurs sources `.svg` |

## Installation (ox_inventory)
1. Ajouter les 4 entrées de `ox_inventory_items.lua` dans `ox_inventory/data/items.lua` uniquement si elles ne s'y trouvent pas déjà.
   Le dépôt les contient dans `resources/[ox]/ox_inventory/data/items.lua`. `spin_top` porte les boutons Démonter / Renommer / Peindre.
2. Copier `images/*.png` dans `ox_inventory/web/images/` si les icônes ne s'y trouvent pas déjà.
3. Après installation, redémarrer ox_inventory sans joueur connecté, puis démarrer `Chaos_Arena`.

Les pièces partagent l'objet `spin_part` ; chaque pièce choisit son icône par `metadata.image = spin_part_<id>`
(posé par le script à la création), d'où les 18 fichiers `spin_part_<id>.png`.
**28/10/2026 :** `spin_part_ring_reverse.png` (anneau inversé) est nouveau : à copier dans `ox_inventory/web/images/`.

## Provenance des images
Toutes les icones sont originales : `spin_top`, `spin_part`, `spin_repair_kit` sont dessinees pour SPIN ARENA ; les icones des pieces et du lanceur sont rendues depuis les modeles 3D du script.
