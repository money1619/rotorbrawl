# Plan de validation — SPIN ARENA

État : procédure à implémenter après validation de la conception. Aucun test de gameplay exécuté en phase 0. Les fréquences et seuils proposés restent des cibles à mesurer ; les paramètres retenus figurent dans PHYSICS.md.

## Preuves attendues pour chaque passage de phase

Chaque résultat doit conserver : version du code, version du runtime, configuration/seed, nombre d'essais, attendu/observé, sortie brute pertinente, durée et limite connue. Une simple capture d'écran ne prouve ni l'autorité serveur ni l'unicité d'une récompense.

| Phase | Essais nécessaires | Critères essentiels de sortie |
|---|---|---|
| 0 | lecture des manifestes/API, inventaire des assets, revue croisée des documents | conception cohérente, limites explicites, validation utilisateur avant code |
| 1 | moteur Lua standard + affichage sur un serveur FiveM de test | deux toupies, mouvement/rotation/friction/collision, arrêt/éjection/timeout sans état bloqué ; aucune valeur non finie |
| 2 | au moins deux clients FiveM réels + latence contrôlée | même match/résultat autoritaire, départ commun, interpolation et récupération des snapshots ; test déconnexion |
| 3 | ressources artistiques réellement produites, 30/60/144 FPS, deux clients | animation sans avantage, aucun handle orphelin, lisibilité et budgets mesurés |
| 4 | ESX + ox_inventory installés + vraie base SQL de test | possession et assemblage sécurisés ; panne SQL/inventaire/restart sans duplication ni perte silencieuse |
| 5 | arènes et zones approuvées, joueurs/spectateurs concurrents | réservation exclusive, accès borné, nettoyage et sortie spectateur sûrs |
| 6 | classement/tournoi/rewards, crashs/reconnexions | résultat et récompense idempotents, bracket cohérent, mises désactivées tant que débit/refund non validés |
| 7 | installation vierge + migrations + régression complète + charge | défauts bloquants corrigés, résultats publiés, licence/assets documentés ; pas d'étiquette commercialisable avant preuves |

## Phase 1 : calculs automatiques

Le futur moteur ne doit dépendre ni d'exports FiveM, ni du temps mural, ni d'entités GTA. Un appel de test injecte le pas fixe, les caractéristiques bornées, l'état initial et la seed éventuelle. Proposition à qualifier : pas de 1/120 s, manche préparée côté serveur en jobs bornés, puis émission de tranches de keyframes avec une avance proposée de 0,5 s, à qualifier entre 0,25 et 1,5 s. Comparer aussi un pas de 1/60 s ; aucun de ces paramètres ne constitue une performance validée.

Cas obligatoires :

- Rejet de NaN/infini, masse/rayon nuls ou négatifs, coordonnées hors borne et état incohérent.
- Mouvement sans collision : friction monotone, énergie/rotation bornées, arrêt confirmé pendant une durée et pas une seule frame.
- Collision frontale, tangentielle et simultanée : séparation des disques, impulsion finie, absence de création d'énergie non prévue par le modèle.
- Disques initialement confondus et vitesse relative nulle : direction de séparation définie sans division par zéro.
- Grande vitesse : aucun passage entre deux toupies ou à travers un bord faute de sous-pas/limite de déplacement ; budget de sous-pas borné.
- Bord : point exactement sur la limite, sortie confirmée, double éjection dans le même pas, rebond si prévu, priorité de fin explicite.
- Arrêt simultané et timeout : égalité/départage symétriques, aucun avantage provenant de l'ordre de parcours des joueurs.
- Même état/seed/pas et ordre d'inputs sur le même runtime : reproductibilité numérique comparée avec tolérance documentée ; ne pas extrapoler cette propriété au multijoueur sans essai réel.
- Durée de simulation identique avec différentes cadences d'appel hôte : accumulateur de temps, rattrapage plafonné, comportement explicite en surcharge ; le FPS client ne modifie jamais le calcul serveur.
- Balayage de cas sur des seeds enregistrées : terminaison dans la durée maximale, invariants à chaque pas et trace des contre-exemples.

Plan de commandes futures, à créer en phase 1 (aucun fichier de test ni runner n'existe encore) : `lua5.4 tests/run.lua`, `luac5.4 -p <fichier Lua standard>`. Ajouter les mêmes cas au harness FiveM pour les adaptateurs ; ne pas présenter un mock comme un test du moteur GTA.

## Phase 1 : procédure FiveM reproductible

1. Installer uniquement le prototype validé dans une instance de développement isolée. Relever versions, build et mode OneSync.
2. Choisir et vérifier une surface de test plane, connue de l'administrateur, sans PNJ/vehicules interférant avec l'observation. Aucune arène réelle n'est préconfigurée en phase 0.
3. Créer deux représentations temporaires locales et afficher le tick, le temps de simulation, les vitesses/énergies, le motif de fin et l'identifiant du scénario.
4. Rejouer les cas sans collision, collision frontale, glissement tangent, éjection, double arrêt et timeout ; comparer aux résultats Lua attendus.
5. Suspendre/reprendre l'affichage, arrêter la ressource, mourir/changer de ped et sortir de la zone : vérifier caméra, focus, contrôles, props et sons nettoyés.
6. Enregistrer les traces et les mesures du profiler. Le passage à la phase 2 reste fermé tant que ces essais essentiels ne passent pas.

## Phase 2 : réseau et multijoueur

Deux clients minimum, un troisième spectateur à partir de la phase 5. Mesurer RTT/jitter/pertes réels plutôt que déduire la latence d'un délai d'animation.

Scénarios : RTT de référence puis 50/100/200 ms de latence ajoutée, jitter, paquets retardés/perdus, snapshots dupliqués ou réordonnés, reconnexion, arrivée tardive, changement de routing bucket, déconnexion à chaque transition. Une déconnexion doit produire un unique terminal selon la politique définie dans ARCHITECTURE.md.

Les tranches de keyframes/snapshots portent un identifiant de match, un tick/version monotone et l'état nécessaire au rendu. Une trame calculée à l'avance ne clôture pas le match : les tests doivent provoquer abandon/déconnexion pendant sa lecture et vérifier l'absence de publication prématurée du gagnant ou de récompense. Tester aussi ce qu'un client modifié peut déduire des keyframes futures : retirer un champ winner ne masque pas une éjection déjà visible dans les points. La politique de fin doit retenir les états terminaux ou annoncer précisément cette fenêtre d'anticipation ; un abandon ne doit permettre aucun nouveau tirage du résultat. Mesurer mémoire par manche et budget CPU des jobs de précalcul ; aucune boucle longue ne doit affamer les autres ressources. Le client rejette les anciens messages, ne prédit pas le vainqueur et ne fait pas continuer indéfiniment la scène quand les données cessent. Une interpolation retardée est proposée ; mesurer l'erreur visuelle et décider les tolérances avant de conclure à la synchronisation.

Les commandes NUI falsifiées (winner, seed, caractéristiques, UUID ou arenaId tiers), les actions hors distance/état, les identifiants anciens, le spam et la double acceptation ne doivent jamais changer le résultat ni accorder une récompense. Ne pas envoyer des positions par frame à tous les joueurs.

## Persistance et inventaire, phases 4 et 6

Simuler et reproduire sur la vraie pile : deux assemblages simultanés du même objet, transfert pendant un match, pièces absentes, slot remplacé pendant un await, métadonnées modifiées, personnage changé sous le même source, inventaire plein, AddItem/RemoveItem false ou exception, SQL refusé/déconnecté, interruption à chaque étape, redémarrage puis retry.

Attendu : unicité des IDs, propriétaire/compte persistants, configuration calculée côté serveur, aucun objet/argent gratuit, compensation durable et observable. Les tests doivent démontrer la reprise d'un résultat/reward déjà enregistré sans second versement ; une clé UNIQUE en base n'est pas à elle seule une preuve d'unicité des effets externes. Le protocole proposé privilégie « au plus une fois » : une ligne laissée en `granting` après un crash est ambiguë, sans nouvel essai automatique, et doit apparaître en revue administrateur. Tester ce chemin et la procédure de rapprochement ; ne jamais annoncer une garantie globale « exactement une fois ».

Migrations : installation vierge, upgrade, relance après interruption au milieu, duplication d'index, échec SQL réel et version non avancée à tort. Les tests de mocks complètent, sans remplacer, ceux sur MySQL/MariaDB réellement retenu.

## Charge et budgets à qualifier

Mesurer 1 match, puis 4/8/16 simultanés jusqu'à la capacité réellement acceptable ; annoncer uniquement les niveaux mesurés. Relever p50/p95/p99 du calcul par tick, backlog, temps serveur, bande passante par abonné, mémoire avant/après, entités et handles côté client, ainsi que le FPS/resmon.

Hypothèses de départ : calcul pur, snapshots peu fréquents et ciblés, aucun polling à la frame hors match/proximité. Fixer les budgets chiffrés après une mesure sur le matériel cible et documenter les conditions d'arrêt en surcharge ; aucun chiffre de performance n'est validé aujourd'hui.

## Matrice de sécurité complémentaire

La matrice détaillée de [SECURITY.md, section 16](SECURITY.md#16-tests-de-sécurité) fait partie des critères de ce plan : schémas invalides et spam, acceptations concurrentes, abandons répétés en phase 2 ; transferts verrouillés et doublons UID, pannes/crash à chaque étape atelier en phase 4 ; restrictions spectateurs en phase 5 ; double règlement et interruption entre `granting` et `granted` en phase 6. Chaque cas doit disposer de sa trace et de son résultat dans PROJECT_STATUS.md avant validation de la phase correspondante. Aucun de ces essais n’a été exécuté en phase 0.
