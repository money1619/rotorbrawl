# ROTORBRAWL — free edition

**English** | [Français](#rotorbrawl--édition-gratuite)

Tabletop spinning-top battles for FiveM: part assembly, server-decided duels, a per-server ranking. Original universe and names
(no existing brand or toy). The resource is called `Chaos_Arena`; "ROTORBRAWL" is the product name.

> **Free edition.** A **Pro** edition is planned (tournaments, ranked matches with a signed certificate, Turbo / Pocket /
> Colosseum tables, a portable arena, four extra launchers, three extra parts). Not available yet.

## Screenshots (taken in game)

The images show the full version: the **Turbo** table and some launchers (Crank, Spring, Precision, Rail) are Pro-only. The free edition has the Standard, Compact, Ejection and Large tables and the Cord launcher.

![Launch gauge: hold SPACE in the zone, release sharply](screenshots/lancer-jauge.jpg)
*Three-step launch: tilt, hold SPACE in the zone, release.*

![Practice result against the bot](screenshots/victoire-entrainement.jpg)
*End of a practice match: score, rounds and duration.*

![Launchers and tops](screenshots/galerie-lanceurs-toupies.jpg)
*Test gallery: the launchers and the five top families.*

## What is included
- The **buy → assemble → challenge → fight → repair** loop.
- 1v1 duels: the server computes everything, clients only render. Practice against a simulated opponent.
- Four-part tops (Ring, Core, Lock, Tip), 18 parts, wear and repair.
- Round finishes: Ring-out, Stop, Burst; points per round, first to 4.
- Cord launcher with a pull gauge, two-hand animation.
- Standard, Compact, Ejection and Large tables; fixed arenas placed with `/spin_admin arena add` or through `arena.fixedList` in
  `config/server.lua`.
- Shop (ox_inventory), server ranking, NUI interface.
- Framework: **ESX Legacy tested in game** with ox_inventory and ox_target. QBCore and Qbox are supported by the built-in bridge (`bridge/`), with qb-inventory or qs-inventory (shop and workshop through menus; the drag-and-drop workshop needs ox_inventory) and qb-target, **but these setups have not been tested in game yet**: please report any problem.

## Installation
1. Dependencies: `oxmysql`, `ox_lib`, a framework (ESX, QBCore or Qbox), `ox_inventory`, `ox_target`. The framework / inventory
   bridge ships in `bridge/` (open files, no other resource to install).
2. Copy the `Chaos_Arena` folder into your resources.
3. Add the items from `install/ox_inventory_items.lua` to ox_inventory and copy the images from `install/` into
   `ox_inventory/web/images/`.
4. `server.cfg`:
   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure es_extended      # or qb-core / qbx_core
   ensure ox_target
   ensure ox_inventory
   ensure Chaos_Arena
   add_ace group.admin command.spin_admin allow
   add_ace group.admin spin_arena.admin allow
   ```
5. The resource creates its SQL tables at startup (see `sql/install.sql`). Back up before any migration.

## Honest status
Models, physics, interface and animations were checked offline (real engine, emulator, Lua/JS tests) and partly in game. Things to
check on your server: model scale and orientation, launcher animations, the positions of your tables.

## License
`LICENSE`: modification allowed, resale forbidden, credit to AEOM Development required. Third-party components (ESX, ox_*,
GTA V data) keep their own license; ROTORBRAWL is not affiliated with any publisher or toy manufacturer.

---

# ROTORBRAWL — édition gratuite

[English](#rotorbrawl--free-edition) | **Français**

Combats de toupies mécaniques pour FiveM : l'assemblage de pièces, des duels décidés par le serveur, un classement par serveur.
Univers et noms originaux (aucune marque, aucun jouet existant). La ressource s'appelle `Chaos_Arena` ; « ROTORBRAWL » est un nom
de travail.

> **Édition gratuite.** Une édition **Pro** existe (tournois, matchs homologués avec certificat signé, tables Turbo / Poche /
> Colisée, arène transportable, quatre lanceurs de plus, trois pièces de plus).

## Captures (prises en jeu)

Les images montrent la version complète : la table **Turbo** et certains lanceurs (Manivelle, Ressort, Précision, Rail) sont réservés à l'édition Pro. L'édition gratuite a les tables Standard, Compacte, Éjection et Large, et le lanceur Cordon.

![Jauge de lancer : tenir ESPACE dans la zone, relâcher d'un coup sec](screenshots/lancer-jauge.jpg)
*Lancer en trois gestes : incliner, tenir ESPACE dans la zone, relâcher.*

![Résultat d'un entraînement contre le bot](screenshots/victoire-entrainement.jpg)
*Fin d'un entraînement : score, manches et durée.*

![Lanceurs et toupies](screenshots/galerie-lanceurs-toupies.jpg)
*Galerie de test : les lanceurs et les cinq familles de toupies.*

## Ce qui est inclus
- Parcours **acheter → assembler → défier → combattre → réparer**.
- Duels 1 contre 1 : le serveur calcule tout, les clients affichent. Entraînement contre un adversaire simulé.
- Toupie à 4 pièces (Lame, Noyau, Verrou, Embout), 18 pièces, usure et réparation.
- Finitions de manche : Sortie, Arrêt, Éclat ; points par manche, premier à 4.
- Lanceur Cordon avec jauge de tirage, animation des deux mains.
- Tables Standard, Compacte, Éjection, Large ; arènes fixes placées par `/spin_admin arena add` ou par `arena.fixedList` dans
  `config/server.lua`.
- Boutique (ox_inventory), classement du serveur, interface NUI.
- Framework : **ESX Legacy testé en jeu** avec ox_inventory et ox_target. QBCore et Qbox sont pris en charge par le pont intégré (`bridge/`), avec qb-inventory ou qs-inventory (boutique et atelier par menus ; l'atelier par glisser-déposer exige ox_inventory) et qb-target, **mais ces configurations n'ont pas encore été testées en jeu** : signalez tout problème.

## Installation
1. Dépendances : `oxmysql`, `ox_lib`, un framework (ESX, QBCore ou Qbox), `ox_inventory`, `ox_target`. Le pont
   framework / inventaire est livré dans `bridge/` (fichiers ouverts, aucune autre ressource à installer).
2. Copier le dossier `Chaos_Arena` dans les ressources.
3. Ajouter les objets de `install/ox_inventory_items.lua` à ox_inventory et copier les images de `install/` dans
   `ox_inventory/web/images/`.
4. `server.cfg` :
   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure es_extended      # ou qb-core / qbx_core
   ensure ox_target
   ensure ox_inventory
   ensure Chaos_Arena
   add_ace group.admin command.spin_admin allow
   add_ace group.admin spin_arena.admin allow
   ```
5. La ressource crée ses tables SQL au démarrage (voir `sql/install.sql`). Sauvegarde avant toute migration.

## État honnête
Les modèles, la physique, l'interface et les animations ont été vérifiés hors jeu (moteur réel, émulateur, tests Lua/JS) et en
partie en jeu. Les points à contrôler sur ton serveur : échelle et orientation des modèles, animations du lanceur, positions de tes tables.

## Licence
`LICENSE` : modification autorisée, revente interdite, crédit obligatoire à AEOM Development. Les éléments de tiers (ESX, ox_*,
données GTA V) gardent leur licence ; ROTORBRAWL n'est affilié à aucun éditeur ni fabricant de jouets.
