# Audit de l'existant — SPIN ARENA

Date : 18 octobre 2026, America/Toronto. Phase 0 uniquement.

## Périmètre réel

Le dossier `resources/[Money]/Chaos_Arena` était vide au premier inventaire : aucun manifeste, Lua, NUI, modèle, SQL ou test. Ce chemin est conservé pendant la conception ; `spin_arena` est le nom technique proposé pour une future ressource, à confirmer. Aucun renommage ni ajout à `server.cfg` n'a été effectué.

La base ESX et ce dossier ne possédaient pas de dépôt Git détectable à l'audit. L'initialisation éventuelle d'un dépôt dédié ne doit jamais englober les configurations privées de FXServer.

Les documents présents après l'audit sont des livrables de conception, pas un jeu installable. Aucun ancien script de golf ou de marché noir ne constitue une implémentation de SPIN ARENA.

## Dépendances détectées

| Composant | Version observée | Preuve | Portée de la vérification |
|---|---|---|---|
| FXServer Linux | `FXServer-master v1.0.0.35265 linux` | réponse locale `http://127.0.0.1:30121/info.json`, champ `server` | serveur déjà actif, pas démarré/redémarré par cet audit |
| GTA game build | `2699` | `server.cfg:32` et `info.json.vars.sv_enforceGameBuild` | build configuré et annoncé ; pas de client GTA lancé |
| OneSync | `on` | argument `+set onesync on` du processus de jeu | configuration active observée ; aucun test de synchronisation SPIN ARENA |
| ESX Legacy | `1.12.4` | `resources/[core]/es_extended/fxmanifest.lua:6` | version déclarée du code installé, ressource annoncée dans info.json |
| ox_inventory | `2.45.0` | `resources/[ox]/ox_inventory/fxmanifest.lua:7` | version déclarée, API lue localement, ressource annoncée |
| ox_lib | `3.32.3` | `resources/[ox]/ox_lib/fxmanifest.lua:9` | version déclarée, ressource annoncée |
| oxmysql | `2.12.0` | `resources/[ox]/oxmysql/fxmanifest.lua:8` | version déclarée, wrapper Lua présent, ressource annoncée |
| MySQL/MariaDB | non identifiée | aucune connexion SQL réalisée | moteur/version, schéma, index et droits à vérifier sur une base de test en phase 4 |

Les manifestes ox_lib et oxmysql demandent un artefact serveur au moins `7290` ; ox_inventory demande au moins `6116` et OneSync. Le serveur observé dépasse ces minimums déclarés, ce qui ne remplace pas les tests d'intégration.

`ox_inventory/init.lua:17` utilise `GetConvar('inventory:framework', 'esx')`. Le défaut est ESX ; la valeur effective de cette convar n'a pas été interrogée dans le runtime. La présence d'ESX ne suffit pas à valider les échanges entre ressources.

Anomalie de configuration à contrôler avant installation : `server.cfg:84` contient `exec @ox_inventory/config.cfg`, mais ce fichier n'existe pas dans le dossier ox_inventory examiné. L'inventaire est néanmoins annoncé actif. Aucune correction de ce serveur partagé n'est incluse dans cette phase ; vérifier les convars réellement utilisées et le journal de démarrage avant la phase 4.

Ordre observé : ox_lib, groupes `[standalone]`, `[core]`, `[esx_addons]`, puis oxmysql/ox_inventory explicites. ESX dépend déjà d'oxmysql ; ne pas réordonner ce serveur sans diagnostic. La future ressource devra déclarer ses dépendances au lieu de compter sur l'ordre des dossiers.

## API effectivement lues dans la copie installée

| Besoin futur | Interface existante | Source locale |
|---|---|---|
| Objet ESX | export `getSharedObject` | `es_extended/shared/main.lua:3` |
| Lecture du slot tenu | `GetSlot(inv, slotId)` | `ox_inventory/modules/inventory/server.lua:969`, export :979 |
| Lecture des objets | `GetInventoryItems(inv, owner)` | même fichier, export :251 |
| Remise | `AddItem(inv, item, count, metadata, slot, cb)` | même fichier :1105, export :1221 |
| Comptage | `Search(inv, search, items, metadata)` | même fichier :1227, export :1272 |
| Retrait ciblé | `RemoveItem(inv, item, count, metadata, slot, ignoreTotal, strict)` | même fichier :1315, export :1400 |
| Capacité | `CanCarryItem(inv, item, count, metadata)` | même fichier :1406, export :1435 |
| Métadonnées | `SetMetadata(inv, slotId, metadata)` | même fichier :1005, export :1049 |
| Contrôle des transferts | `registerHook(event, cb, options)` / `removeHooks(id)` | `ox_inventory/modules/hooks/server.lua:89`, :125 |
| Transaction SQL | `MySQL.transaction.await(query, parameters)` généré par le wrapper | `oxmysql/lib/MySQL.lua:88–97` |

Ces interfaces existent dans les sources, mais aucun appel métier SPIN ARENA ne les a encore testées. `SetMetadata` ne fournit pas une validation métier ni une transaction distribuée. Ne pas supposer qu'une opération d'inventaire et une transaction oxmysql se valident ensemble.

Le format `data/items.lua` de cette installation utilise des tables indexées par nom, avec notamment `label`, `weight`, `stack`, `client` et `server`. Les définitions futures `spin_top` et `spin_launcher` devront être non empilables si leurs métadonnées portent une identité ; leurs exemples ne seront ajoutés qu'en phase 4 après vérification des règles de transfert. Aucun item installé/modifié aujourd'hui.

## Outils disponibles et limites

Lua/luac `5.4.6`, Node.js `18.13.0` et Git `2.40.1` sont présents. Blender n'est pas dans le PATH. Aucun client FiveM/GTA, outil de capture réseau de deux clients ou chaîne d'export 3D complète n'a été validé pendant cet audit. L'existence d'un FXServer actif ne donne pas accès aux clients humains nécessaires aux phases 1 à 3.

La syntaxe CfxLua peut contenir des extensions que luac standard ne comprend pas. Le moteur mathématique sera écrit en Lua standard pour être testable hors jeu ; les adaptateurs FiveM nécessiteront aussi une validation sur le runtime CfxLua.

## Documentation primaire consultée

- [Cfx — OneSync](https://docs.fivem.net/docs/scripting-reference/onesync/) : réplication, visibilité et limites de portée ; ne pas utiliser la visibilité d'un ped côté client comme preuve d'état serveur.
- [Cfx — Secure Your Events](https://docs.fivem.net/docs/developers/server-security/) : validation serveur des requêtes réseau.
- [Cfx — Fullscreen NUI](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/) : manifeste, messages et focus NUI.
- [Cfx — NUI Callbacks](https://docs.fivem.net/docs/scripting-manual/nui-development/nui-callbacks/) : callbacks et réponses.

Pour les exports ox, les sources installées ci-dessus sont la référence de compatibilité de cet audit. L'ancienne adresse documentaire `coxdocs.dev/oxmysql/Functions/transaction` redirige vers une page générale : elle n'est pas utilisée comme preuve du contrat transactionnel. Chaque nouveau nom d'event/export/native devra être relié à une source vérifiée avant son implémentation.

## Points à résoudre avant les phases correspondantes

1. Valider cette conception et le chemin technique avant la phase 1.
2. Réserver un créneau de test sur serveur de développement, puis deux vrais clients pour la phase 2.
3. Relever la version SQL et tester les contraintes/erreurs sur une base isolée avant l'atelier/persistance.
4. Choisir les emplacements réels des arènes par contrôle en jeu : aucune coordonnée fictive n'est déclarée jouable.
5. Produire ou commander les modèles/animations/sons originaux, conserver les sources et les droits.
6. Décider le titulaire des droits et la licence de distribution du produit ; aucune disponibilité juridique du nom n'a été affirmée.
