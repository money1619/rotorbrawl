# Architecture — SPIN ARENA

Auteur : Archimedes. Date : 18 octobre 2026. Phase 0 : **conception uniquement**.

Aucun fichier de code n'existe. Les noms d'événements, de modules et de tables ci-dessous sont des **propositions** pour SPIN ARENA. Les API externes citées ont été lues dans les versions installées (voir [AUDIT.md](AUDIT.md)) ; chaque nouvel appel devra encore être vérifié avant son implémentation.

## 1. Résumé

- Le serveur fait autorité sur tout ce qui compte : participants, configurations, seed, simulation, fin de manche, résultat, récompenses.
- La simulation est un moteur Lua pur décrit dans [PHYSICS.md](PHYSICS.md). Il ne connaît ni FiveM, ni ESX, ni la base.
- Les clients affichent des **objets locaux non réseau**, interpolés entre des keyframes reçues par tranches. Aucune entité OneSync n'est créée pour les toupies.
- Les requêtes des clients ne contiennent que des **intentions** (« je défie le joueur 12 avec ma toupie ST-… »), jamais des statistiques, des positions de toupie ou un résultat.
- L'inventaire (ox_inventory) dit **qui possède** l'objet ; la base (oxmysql) dit **ce qu'est** la toupie (pièces, statistiques, verrou, historique).

## 2. Décisions

| # | Décision | Alternative écartée | Raison |
|---|---|---|---|
| D1 | Moteur 2D mathématique côté serveur | physique GTA des props | la physique GTA est calculée par un client, instable sur petits objets ([PHYSICS.md](PHYSICS.md) §1) |
| D2 | Manche calculée par tranches pendant le compte à rebours, puis diffusée avec une avance limitée | simulation en temps réel à chaque tick serveur | pas de dépendance au tick serveur ni aux à-coups ; rediffusion et vérification faciles ; le moteur reste un simple `step`, donc le temps réel reste possible si un jour le joueur agit pendant la manche |
| D3 | Objets locaux non réseau côté client | entités réseau OneSync | pas de propriétaire d'entité ni de migration ; nettoyage local plus simple. L'absence de fuite reste un objectif qui dépend du nettoyage (§12) et doit être testée |
| D4 | Événements explicites et ciblés | state bags / `GlobalState` | données fréquentes et à destination limitée ; `sv_enableNetworkedScriptEntityStates false` dans `server.cfg` montre que le serveur restreint déjà ce canal |
| D5 | Requêtes client avec `lib.callback.register` (ox_lib 3.32.3, `imports/callback/server.lua:116`) | `RegisterNetEvent` + événement de réponse fait main | réponse directe avec un code d'erreur ; reste une entrée non fiable |
| D6 | Toupie = objet `spin_top` avec `metadata.uid` ; configuration en base | configuration complète dans les métadonnées | les métadonnées sont copiées, et un objet dupliqué porterait sa propre configuration ; avec un `uid`, une copie pointe vers la même ligne et le même verrou |
| D7 | Récompenses « au plus une fois » | « exactement une fois » | impossible entre ox_inventory/ESX et SQL sans transaction commune ; voir [SECURITY.md](SECURITY.md) §9 |
| D8 | Mises désactivées par défaut | — | exigence §11 du cahier ; les limites d'ESX sont décrites dans [SECURITY.md](SECURITY.md) §9 |

## 3. Vue d'ensemble

```
CLIENT (non fiable)                          SERVEUR (autorité)
---------------------                        ---------------------------------------------
NUI (menus, HUD)                             main.lua : enregistre les callbacks, ordre fixe :
  │ NUI callbacks                              limite de fréquence → schéma → état → droits
client/nui.lua ──── lib.callback ─────────►    → distance → appel du module → journal
client/main.lua ◄── TriggerClientEvent ────  challenges.lua ──► matches.lua ──► physics/* (pur)
client/renderer.lua (objets locaux,                               │    │
  interpolation, effets)                                          │    └─► arenas.lua
                                                                  ▼
                                             parts.lua ─► inventory.lua (ox_inventory)
                                                     └──► database.lua (oxmysql)
                                             ranking.lua / tournaments.lua (abonnés aux fins de match)
```

## 4. Structure de fichiers

Adaptation de la structure du cahier (§6). On crée un fichier seulement quand sa phase commence. Les modules de physique sont pris tels quels ; `client/duel.lua` est fusionné dans `client/main.lua` (même responsabilité : suivre le match affiché) ; `tests/` est ajouté.

```
Chaos_Arena/                     (nom du dossier à confirmer, voir §16)
  fxmanifest.lua                 phase 1
  config/shared.lua              phase 1   valeurs envoyées aux clients (affichage, catalogue)
  config/server.lua              phase 1   valeurs serveur seulement (règles, récompenses, droits)
  shared/rng.lua                 phase 1   générateur pseudo-aléatoire du moteur
  shared/stats.lua               phase 4   pièces → caractéristiques bornées (pur)
  shared/protocol.lua            phase 2   noms d'événements, codes d'erreur, codage des keyframes
  shared/zones.lua               phase 5   point dans polygone (pur)
  server/physics/engine.lua      phase 1   état de manche, pas, fin
  server/physics/collisions.lua  phase 1
  server/physics/boundaries.lua  phase 1
  server/debug.lua               phase 1   commande admin de test (retirée ou désactivée ensuite)
  server/main.lua                phase 2
  server/security.lua            phase 2
  server/matches.lua             phase 2
  server/challenges.lua          phase 2
  server/arenas.lua              phase 2 (arène unique) puis 5
  server/database.lua            phase 4
  server/inventory.lua           phase 4
  server/parts.lua               phase 4
  server/ranking.lua             phase 6
  server/tournaments.lua         phase 6
  client/main.lua                phase 1 (affichage de test) puis 2
  client/renderer.lua            phase 1 (formes temporaires) puis 3
  client/effects.lua             phase 3
  client/launcher.lua            phase 3
  client/arena.lua               phase 2
  client/nui.lua                 phase 2
  client/preview.lua             phase 4
  web/                           phase 2 (HUD minimal) puis 3–4, voir ART_AND_UI.md
  locales/fr.lua, locales/en.lua phase 2
  sql/install.sql, sql/migrations/  phase 4
  stream/                        phase 3, uniquement des modèles réellement produits
  tests/run.lua, tests/*.lua     phase 1   exécutés avec lua5.4 hors du jeu
```

Les fichiers `config/server.lua` et `server/*` sont déclarés uniquement en `server_scripts` : tout fichier listé en `shared_scripts`, `client_scripts` ou `files` est téléchargé par les clients.

## 5. Modules serveur

Chaque module expose une table. Les dépendances vont dans un seul sens (tableau de haut en bas) : pas de dépendance circulaire. `ranking` et `tournaments` ne sont pas appelés par `matches` : ils s'abonnent à `Matches.onFinished(cb)`.

**Phases 2 et 3** : `matches` reçoit ses toupies et ses verrous par une interface (`TopSource`). Avant la phase 4, cette interface est un **profil de test** : toupies fixes de `config/shared.lua`, verrous en mémoire, aucune récompense, aucun SQL, aucun inventaire. Ce mode de test n'est pas commercialisable et le serveur l'annonce dans la console. L'implémentation réelle (`inventory` + `database`) remplace le profil en phase 4, sans changer `matches`.

| Module | Responsabilité | Interface proposée | Dépend de |
|---|---|---|---|
| `shared/rng` | aléa reproductible | `Rng.new(seed)`, `rng:next()`, `rng:range(a, b)` | — |
| `physics/*` | simulation pure | `Engine.newRound(params)`, `Engine.step(round)`, `Engine.result(round)`, `Engine.keyframe(round)` | `rng` |
| `shared/stats` | calcul des caractéristiques à partir des pièces, bornes, budget | `Stats.compute(parts) → stats, err` | config |
| `security` | limites de fréquence, validation de schéma, droits, distances | `Security.guard(src, action)`, `Security.check(schema, value)`, `Security.isAdmin(src)`, `Security.near(src, coords, radius)` | config |
| `database` | toutes les requêtes SQL (aucune ailleurs), migrations | `Db.getTop(uid)`, `Db.lockTop(uid, matchId)`, `Db.saveResult(match)`… | oxmysql |
| `inventory` | accès ox_inventory, hooks de verrou | `Inv.hasTop(src, uid)`, `Inv.takePart(src, partId)`, `Inv.givePart(src, partId)`, `Inv.lock(uid)`, `Inv.unlock(uid)` | ox_inventory |
| `parts` | atelier : assemblage, réparation | `Parts.assemble(src, uid, slot, partId)` | `inventory`, `database`, `stats` |
| `arenas` | registre, réservation, zones libres | `Arenas.reserve(id or spot, matchId)`, `Arenas.release(matchId)`, `Arenas.audience(matchId)` | config, `security` |
| `matches` | machine à états, exécution des manches, diffusion | `Matches.create(def)`, `Matches.forfeit(src)`, `Matches.onDropped(src)`, `Matches.onFinished(cb)` | `physics`, `arenas`, `TopSource` (profil de test, puis `inventory` + `database` en phase 4) |
| `challenges` | défis entre joueurs, expiration | `Challenges.send(src, target, uid, arena)`, `Challenges.respond(src, id, accept, uid)` | `matches`, `security` |
| `ranking` | classement, statistiques, saisons | abonné à `Matches.onFinished` | `database` |
| `tournaments` | inscriptions, tableau, abandons | crée des matchs par `Matches.create` | `matches`, `database` |
| `main` | enregistrement des callbacks, cycle de vie (`esx:playerDropped`, `esx:playerLogout`, `onResourceStop`, reprise au démarrage) | — | tous |

Accès ESX : `exports.es_extended:getSharedObject()` (`es_extended/shared/main.lua:3`), puis `ESX.GetPlayerFromId(src)`. Méthodes lues dans `es_extended/server/classes/player.lua` : `getIdentifier` (:167), `getAccount` (:223), `addAccountMoney` (:332), `removeAccountMoney` (:358). Événements serveur : `esx:playerDropped` (`server/main.lua:319`), `esx:playerLogout` (`server/main.lua:354`).

## 6. Modules client

| Module | Responsabilité |
|---|---|
| `client/main.lua` | état local des matchs affichés, réception des événements serveur, horloge de lecture |
| `client/renderer.lua` | création/suppression des objets locaux, interpolation, rotation visuelle |
| `client/effects.lua` | étincelles, impacts, traînées, sons, ralentis purement visuels |
| `client/launcher.lua` | lanceur en main, animation de préparation, position d'observation |
| `client/arena.lua` | objet ou repère d'arène, caméra d'observation facultative |
| `client/nui.lua` | pont NUI ↔ Lua ; ne transmet que des intentions au serveur |
| `client/preview.lua` | aperçu de toupie dans l'atelier |

Le client n'a aucune boucle par image en dehors d'un match affiché ou de l'atelier ouvert.

## 7. Cycle de vie d'un match

```
pending ──accept──► locking ──ok──► countdown(n) ──GO──► playing(n) ──fin──► round_over(n)
   │                   │                │                    │                  │
 refus/expiration   échec          abandon avant            abandon /        manche suivante
   ▼                   ▼            le 1er GO                déconnexion      ou settling
cancelled          cancelled        cancelled                forfeit ──► settling ──► finished
```

- `pending` : défi envoyé, expire après 30 s. Un joueur a au plus un défi sortant et trois entrants.
- `locking` : le serveur relit tout lui-même : participants, distances, bucket, véhicule, santé, possession des toupies, verrous SQL, réservation d'arène, et débit des mises si elles sont un jour activées. Chaque vérification qui suit un `await` est refaite si l'état a pu changer.
- `countdown(n)` : seed tirée, manche calculée par tranches, animation de lancement. Durée fixe (par exemple 5 s), prolongée si le calcul n'est pas fini.
- `playing(n)` : lecture ; le serveur suit sa propre horloge (`GetGameTimer`). La manche est finie quand le serveur atteint la fin calculée plus une marge, jamais sur un accusé client.
- `round_over(n)` : score mis à jour ; pause, puis `countdown(n+1)` ou `settling`.
- `settling` : écriture du résultat et des récompenses ([SECURITY.md](SECURITY.md) §9), levée des verrous, libération de l'arène.

Chaque état a une échéance surveillée par un minuteur. Une échéance dépassée annule le match avant le premier GO, ou le termine en `no_contest` après, et écrit une trace. Un match ne peut pas rester bloqué.

Format par défaut proposé : 2 manches gagnantes sur 3, 5 manches maximum (égalités comprises).

## 8. Exécution d'une manche

1. À l'entrée en `countdown`, `matches` crée la manche avec `Engine.newRound`.
2. Un fil `CreateThread` exécute `Engine.step` par tranches (taille fixée après mesure) avec `Wait(0)` entre deux tranches, jusqu'à la fin de la manche ou `maxSteps`.
3. Les keyframes sont rangées par tranches de 0,5 s.
4. Au GO, le serveur note `goAt = GetGameTimer()` et envoie chaque tranche quand son heure de lecture moins l'avance `L` (0,5 s) est atteinte. La tranche qui contient la fin n'est envoyée qu'à son heure ([PHYSICS.md](PHYSICS.md) §15).
5. Un événement de match (abandon, déconnexion, sortie de zone) arrête la diffusion et prime sur le résultat calculé.
6. À `goAt + durée + marge`, le serveur publie la fin de manche.

Limites de charge (configuration) : nombre de matchs simultanés, nombre de manches en cours de calcul, nombre de spectateurs par match. Valeurs fixées après les mesures de [TEST_PLAN.md](TEST_PLAN.md).

## 9. Protocole réseau

Préfixe d'événements constant `spin_arena:` défini dans `shared/protocol.lua`, indépendant du nom du dossier.

Client → serveur (`lib.callback`, réponse `{ ok = bool, code = string }`) :

| Nom | Données | Phase |
|---|---|---|
| `spin_arena:challenge` | `target` (entier), `uid` (chaîne), `arena` (identifiant ou nil) | 2 |
| `spin_arena:respond` | `id` (entier), `accept` (booléen), `uid` (chaîne ou nil) | 2 |
| `spin_arena:cancel` | `id` | 2 |
| `spin_arena:forfeit` | `matchId` | 2 |
| `spin_arena:spectate` | `matchId`, `on` (booléen) | 5 |
| `spin_arena:workshop` | `action`, `uid`, `slot`, `part` | 4 |

Serveur → client (`TriggerClientEvent`, toujours ciblé ; jamais `-1` pour des données de match). Préfixe `spin_arena:cl:` pour ne pas confondre avec les callbacks ci-dessus :

| Nom | Données |
|---|---|
| `spin_arena:cl:challenge` | défi reçu, modifié ou expiré |
| `spin_arena:cl:match` | en-tête : identifiant, arène (centre, cap, échelle, `R`, poches), joueurs (nom affiché, côté, cosmétiques), règles, score |
| `spin_arena:cl:countdown` | `matchId`, `round`, `startsInMs` |
| `spin_arena:cl:frames` | `matchId`, `round`, `seq`, `fromStep`, keyframes, événements, `last` |
| `spin_arena:cl:roundEnd` | `matchId`, `round`, côté gagnant ou égalité, motif, score |
| `spin_arena:cl:matchEnd` | résultat, récompenses à afficher |
| `spin_arena:cl:cancel` | `matchId`, motif |
| `spin_arena:cl:unsub` | le client sort de l'audience : il nettoie |

Keyframe : tableau plat d'entiers `{ step, x1, y1, w1, wob1, st1, x2, y2, w2, wob2, st2 }`, `x`/`y` en mm, `w` en 0,1 rad/s, `wob` de 0 à 255. Estimation (non mesurée) : environ 30 octets par keyframe avec msgpack, 20 keyframes/s, soit moins de 1 Ko/s par abonné et par match. Les données de match ne passent pas par les événements « latents », réservés aux gros volumes.

Repère monde : le client place le point `(x, y)` à `centre + rotation(cap) · (x, y) · échelle`, à la hauteur de la surface de la cuvette.

## 10. Horloge et interpolation

- Le serveur envoie `startsInMs`, réduit de la moitié du ping du destinataire (`GetPlayerPing`). C'est une estimation : l'écart réel entre clients sera mesuré en phase 2.
- Le client fixe `t0 = GetGameTimer() + startsInMs` et lit la manche au temps `(GetGameTimer() − t0) / 1000 − D`, avec un tampon `D = 0,2 s`.
- Interpolation linéaire entre keyframes ; les événements ont leur propre keyframe, donc les rebonds restent nets.
- Si les données manquent, le client gèle la scène et affiche « synchronisation » ; après 5 s sans données, il nettoie. Il n'extrapole pas indéfiniment.
- Paquets en double ou en retard : rejetés grâce à `matchId`, `round` et `seq` croissant.
- Un spectateur qui arrive en cours de manche reçoit l'en-tête puis les tranches à partir de la position actuelle.

## 11. Abandon, déconnexion, mort, sortie de zone

Gérés en temps réel par `matches`. Ils priment sur le résultat calculé.

| Moment | Un participant quitte, se déconnecte (`playerDropped`, `esx:playerLogout`), meurt, monte dans un véhicule, sort de la zone ou abandonne | Les deux à la fois |
|---|---|---|
| défi en attente | défi annulé | défi annulé |
| entre `locking` et le premier GO | match annulé, aucun résultat, verrous levés, mises remboursées | idem |
| après le premier GO | défaite par abandon (`forfeit`) ; l'adversaire gagne ; récompense de victoire par abandon réduite (configurable, et nulle sous une durée minimale de match) | les départs sont traités l'un après l'autre : le premier traité perd par abandon si l'adversaire est encore connecté ; si l'adversaire est déjà parti, `no_contest` |
| arrêt de la ressource ou crash | matchs en cours annulés, reprise au démarrage (§13) | — |

- Sortie de zone : avertissement, puis abandon après 5 s hors du rayon d'observation.
- Mort : abandon par défaut. Option `no_contest` pour les serveurs où les meurtres par un tiers posent problème. Avec `no_contest`, un joueur qui perd pourrait se faire tuer exprès : à choisir en connaissance de cause.
- Pas de reconnexion à un match en v1 (le `source` change). Une période de grâce par identifiant est une extension possible.
- Un départ ne relance jamais une manche et ne rapporte jamais rien à celui qui part.

## 12. Arènes, zones libres, spectateurs

**Arènes fixes** (configuration serveur) : identifiant, nom, centre, cap, échelle, `R`, poches, rayon pour rejoindre (6 m), rayon d'observation (25 m), nombre maximal de spectateurs, routing bucket, actif ou non. Les positions seront relevées en jeu par un administrateur ; aucune coordonnée n'est proposée en phase 0.

**Combats improvisés** (phase 5) : autorisés seulement dans des polygones approuvés de la configuration, hors des zones interdites. Le serveur place l'arène devant le joueur qui défie, à partir des coordonnées et du cap de son ped lus côté serveur. La hauteur au sol proposée par le client est seulement visuelle et bornée à ±1,5 m de celle du ped. L'arène est refusée si elle chevauche une autre arène active. Sans polygone configuré, la fonction est désactivée.

**Occupation** : une arène a au plus un match. Un joueur a au plus un match (comme participant) et regarde au plus un match.

**Audience** : les participants, plus les joueurs du même bucket dans le rayon d'observation, recalculée chaque seconde, plafonnée (les plus proches d'abord). Seule l'audience reçoit les tranches.

**Nettoyage** : le client supprime ses objets locaux à `roundEnd`, `cancel`, `matchEnd`, `unsub`, à l'arrêt de la ressource (`onResourceStop`), et après 5 s sans données. Le serveur libère réservations, verrous, minuteurs et tables du match dans tous les chemins de fin.

## 13. Persistance et reprise

Tables proposées (phase 4 puis 6), moteur à confirmer sur la base réelle (client `mysql` de l'hôte : MariaDB 10.11.8 ; version du serveur SQL à vérifier) :

| Table | Contenu | Contraintes |
|---|---|---|
| `spin_schema` | version du schéma | une ligne |
| `spin_tops` | `uid`, détenteur connu, famille, statistiques calculées et version de calcul, usure, compteurs, `locked_match`, `version` | PK `uid`, index `locked_match` |
| `spin_top_parts` | `uid`, emplacement, pièce | PK (`uid`, emplacement) |
| `spin_matches` | identifiant, statut, arène, règles, seeds, version du moteur, dates, résultat | index statut |
| `spin_match_players` | match, identifiant ESX, `uid`, statistiques figées, issue | PK (match, identifiant) |
| `spin_rewards` | match, identifiant, type, montant ou objet, statut `pending → granting → granted` ou `review` | UNIQUE (match, identifiant, type) |
| `spin_ops` | journal des opérations d'atelier qui touchent l'inventaire | statut, dates |
| `spin_ratings` | identifiant, saison, cote, victoires, défaites, égalités | PK (identifiant, saison) |

- Le résultat, les compteurs, l'usure et le classement sont écrits dans **une seule transaction SQL** (`MySQL.transaction.await`, wrapper `oxmysql/lib/MySQL.lua:88–97`), qui crée aussi les lignes `spin_rewards` en `pending`. Tout ce qui ne touche que SQL est donc atomique.
- Les effets hors SQL (argent ESX, objets ox_inventory) suivent [SECURITY.md](SECURITY.md) §9.
- Migrations : les DDL de MariaDB/MySQL valident implicitement la transaction en cours, donc une migration ne peut pas être annulée d'un bloc. Chaque migration doit être rejouable (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS` à vérifier sur la version réelle) et la version n'avance qu'à la fin.
- Reprise au démarrage de la ressource : matchs `locking`/`playing` → `cancelled` (`server_restart`) ; verrous de toupies sans match actif → levés ; récompenses `pending` → versées à la prochaine connexion du joueur (`esx:playerLoaded`) ; récompenses `granting` → `review` pour un administrateur.

## 14. Inventaire et pièces

Objets envisagés (définitions à ajouter en phase 4 au format `data/items.lua` d'ox_inventory 2.45.0, sans modifier l'existant sans accord) :

| Objet | Empilable | Métadonnées | Remarque |
|---|---|---|---|
| `spin_top` | non | `uid` (+ libellé affiché) | `uid` attribué par un hook `createItem` s'il manque |
| `spin_launcher` | oui si même modèle | `model` | les métadonnées identiques s'empilent (`table.matches`, `modules/inventory/server.lua:1127`) |
| `spin_part` | oui si même pièce | `part` | retrait exact avec `RemoveItem(..., strict = true)` (défaut, :1315) |
| `spin_repair_kit` | oui | — | |

- Possession : `GetSlotsWithItem(src, 'spin_top', { uid = uid }, false)` (`modules/inventory/server.lua:2209`) doit trouver l'objet au moment du verrouillage.
- Verrou : `UPDATE spin_tops SET locked_match = ? WHERE uid = ? AND locked_match IS NULL`, réussi seulement si une ligne est modifiée. Deux copies d'un même `uid` partagent donc le verrou.
- Hook `swapItems` (filtre `spin_top`, `modules/hooks/server.lua:89`) : refuse `move`, `give`, `swap`, `stack` et les dépôts au sol d'une toupie verrouillée ou en cours d'atelier. Le hook lit un ensemble en mémoire, sans SQL (il doit répondre vite).
- Emplacements de combat proposés (noms originaux) : **noyau** (masse, `kI`), **anneau** (attaque, défense), **châssis** (stabilité, poids), **pointe** (friction, mobilité, adhérence, amortissement). Cosmétiques à part : peinture, lueur du noyau, gravure. Chaque pièce a un coût ; la somme reste sous un budget ; `shared/stats.lua` additionne, borne et rejette.
- Assemblage : déroulé dans [SECURITY.md](SECURITY.md) §8.

## 15. Configuration

- `config/shared.lua` : affichage (arènes, catalogue des pièces pour l'atelier, couleurs). Le serveur ne relit jamais une valeur de ce fichier envoyée par le client : il lit sa propre copie.
- `config/server.lua` : règles, limites de fréquence, récompenses, plafonds journaliers, mises (`false` par défaut), zones libres, droits ACE, journalisation, webhook facultatif et vide par défaut.
- Paramètres physiques : dans `config/shared.lua` en lecture seule pour l'affichage, utilisés par le serveur depuis sa propre copie.

## 16. Décisions à valider par l'utilisateur

1. Nom du dossier : garder `Chaos_Arena` ou renommer en `spin_arena` avant la phase 1. Les événements utilisent `spin_arena:` dans les deux cas.
2. Format des matchs : 2 manches gagnantes sur 3, 5 manches maximum, égalité acceptée en partie libre et départage en tournoi.
3. Mort d'un participant : abandon (proposé) ou sans résultat.
4. Mises : désactivées (conforme au cahier). Récompenses de la v1 : uniquement expérience et classement, puis objets en phase 6.
5. Emplacements des arènes fixes et zones libres : à relever en jeu.

## 17. Fichiers à créer en premier (phase 1, après validation)

1. `tests/run.lua` et `tests/physics_test.lua` : cas de [PHYSICS.md](PHYSICS.md) §17, lancés avec `lua5.4`.
2. `shared/rng.lua`, `server/physics/engine.lua`, `collisions.lua`, `boundaries.lua` : moteur pur.
3. `config/shared.lua` : constantes physiques, une arène de test, deux toupies de test.
4. `fxmanifest.lua` : `lua54 'yes'`, aucune dépendance ESX/inventaire en phase 1.
5. `server/debug.lua` : commande réservée aux administrateurs (ACE) qui lance une manche à la position de l'administrateur et l'envoie à lui seul.
6. `client/main.lua` et `client/renderer.lua` : formes temporaires, interpolation, nettoyage.

Pas d'ESX, d'inventaire, de SQL, de NUI ni de modèle 3D en phase 1.
