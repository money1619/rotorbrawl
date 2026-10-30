# Revue indépendante de la phase 2 — 18 octobre 2026

Le serveur de duel et son client ont été relus sur disque, puis exécutés hors jeu avec les vraies ressources dans des environnements à natives/réseau simulés. Cette revue ne valide pas un affichage GTA ni un duel entre deux vrais clients. Aucun déploiement, redémarrage ou envoi à un joueur réel n'a été effectué par Turing.

## Code réellement relu

`config/server.lua`, `shared/protocol.lua`, `server/bridge.lua`, `security.lua`, `arenas.lua`, `runner.lua`, `matches.lua`, `challenges.lua`, `main.lua`, manifeste `0.2.0`, ainsi que les contrats du renderer et les suites de tests. Le point de départ était le commit `6726c7c` ; l'équipe a ensuite intégré les corrections pendant la revue. Le commit observé lors du relevé final est enregistré dans [checks-and-version.json](evidence/phase2-review-initial-20261018/checks-and-version.json), avec les empreintes avant/après des sources effectivement testées. Des corrections non encore committées existaient : le hash du commit seul ne suffit donc pas à identifier ce test.

Le code comporte maintenant des défis, un registre de matchs commun, deux participants, un score sur plusieurs manches, des réservations d'arènes et une diffusion ciblée. Les profils sont toujours les deux profils de test de configuration ; aucune propriété d'objet, récompense ou persistance SQL n'est simulée comme définitive. Le contexte ESX est facultatif et la dépendance d'interface/callback est ox_lib.

## Résultats indépendants conservés

Sources stables pendant les exécutions selon le relevé SHA-256 :

| Suite exécutée | Résultat | Preuve |
|---|---|---|
| `lua5.4 tests/run.lua` | **112/112** | [journal](evidence/phase2-review-initial-20261018/run.log) |
| `lua5.4 tests/server_unit_test.lua` | **39/39** | [journal](evidence/phase2-review-initial-20261018/server_unit_test.log) |
| `lua5.4 tests/duel_test.lua` | **48/48** | [journal](evidence/phase2-review-initial-20261018/duel_test.log) |
| `lua5.4 tests/review_phase2.lua` | **12/12** | [journal](evidence/phase2-review-initial-20261018/review_phase2.log) |
| `lua5.4 tests/emulator.lua` | **37/37** | [journal](evidence/phase2-review-initial-20261018/emulator.log) |

Ne pas additionner ces nombres comme autant de scénarios indépendants : les suites se recouvrent. Les 48 vérifications du duel utilisent maintenant un **même match partagé** entre deux clients émulés, avec une spectatrice proche et un joueur éloigné, contrairement aux sessions debug indépendantes des 37 contrôles historiques. La synchronisation d'un vrai client GTA et le comportement des natives restent hors de leur portée.

Les cas D01–D08 sont exercés dans la suite du duel : acceptation, refus, annulation, déconnexion, paquets perturbés, acceptations concurrentes, score/finale et injection d'erreur. Les critères de sortie de [VALIDATION_GTA_ET_DUEL.md](VALIDATION_GTA_ET_DUEL.md) gardent un étage distinct de mesures avec deux vrais clients ; les suites présentes ne suffisent pas à le cocher.

## Défauts trouvés et corrections vérifiées

| Défaut constaté pendant la revue | Correction effectuée par l'équipe | Régression indépendante |
|---|---|---|
| `finish`/`cancel` effectuaient les envois avant la libération ; une exception pouvait conserver les index alors que `done=true` interdisait une seconde finalisation | nettoyage avant notification et protection par destinataire | une erreur d'envoi à la fin/annulation ne conserve ni match, joueur ni arène |
| erreur de notification d'en-tête lors de la création susceptible de laisser un match réservé | protection des envois et de l'initialisation, libération sur erreur | erreur sur en-tête puis contrôle des registres et de l'échéance |
| notification d'invitation avant armement de son minuteur ; si elle échouait, le défi restait occupé indéfiniment | minuteur armé avant envoi, notification protégée | invitation injectée en erreur puis attente TTL + 2 s : aucun défi sortant immortel |
| participants de deux duels proches ajoutés comme spectateurs l'un de l'autre ; le renderer unique affichait le mauvais match | exclusion des participants et des spectateurs déjà engagés ailleurs | deux matchs séparés de 10 m : chaque client conserve sa propre scène |
| `m1-100` et l'id de défi pouvaient être réutilisés au redémarrage | namespace de démarrage pour les matchs, départ de compteur renouvelé pour les défis | redémarrage de ressource dans le même créneau d'horloge : références distinctes |
| un ancien compte à rebours pouvait annuler un GO recalculé plus récemment | révision de départ dans les messages serveur et rejet des anciennes révisions côté client | réception révision 2 puis révision 1 : l'heure récente est conservée |

La suite indépendante vérifie également quatre contextes d'admission sur des états neufs, **sans masquer un refus de distance par un rate limit** : joueur éloigné, bucket différent, mort, véhicule. Les quatre refus attendus sont obtenus sans allocation de défi/match.

Le renouvellement des références évite les collisions systématiques reproduites ; ce n'est pas une preuve mathématique d'unicité globale permanente ni un mécanisme d'autorisation. Les contrôles d'appartenance/état restent nécessaires.

## Instance FiveM observée séparément

La [photographie de déploiement](evidence/phase2-review-initial-20261018/deployed-observation.json) confirme `Chaos_Arena` et `ox_lib` annoncés actifs sur 30126, artefact 35265, build 2699, OneSync true et **zéro joueur**. Le manifeste sur disque de l'instance correspond à `0.2.0`.

Au moment de ce relevé, `server/matches.lua` et `client/renderer.lua` de la copie de test différaient des dernières sources revues (correctifs de révision). La revue verte hors jeu ne prouve donc pas que ces deux correctifs sont déjà chargés dans FiveM. Les empreintes comparées sont conservées ; un rechargement ultérieur doit être signalé et vérifié séparément. Le code chargé en mémoire ne dispose toujours pas d'une attestation d'empreinte.

**Contrôle final après redéploiement annoncé vers 16:28 UTC :** la [nouvelle photographie](evidence/phase2-review-initial-20261018/deployed-observation-final.json) confirme **20 fichiers d'exécution identiques source/copie**, dont les correctifs de révision, au commit observé `0b6b4e22375bc01fc90dd5ce253fc7651fd44eec`. Le [dernier chargement consigné](evidence/phase2-review-initial-20261018/cfx-final-load.log) ne contient aucune `SCRIPT ERROR`. OneSync reste true et zéro joueur est connecté. L'écart de déploiement initial est donc résolu au contrôle sur disque ; la correspondance du code en mémoire reste déduite du rechargement, pas attestée par une empreinte runtime. Turing n'a effectué aucun déploiement.

L'[extrait du journal CfxLua](evidence/phase2-review-initial-20261018/cfx-phase2-extract.log) montre le démarrage de la phase 2 et un banc de **100 manches** de physique : seeds `49819324477049–49819324477148`, 59 victoires attaque / 41 endurance, 33 éjections / 67 arrêts, durée médiane 14,0 s, calcul CPU par manche p50 25,90 ms / p95 53,76 ms. Ce banc reste une commande debug serveur : il ne valide ni le chemin réseau réel de deux participants ni le rendu GTA ni ox_target.

## Règles et risques à conserver explicitement

- Les départs sont traités dans l'ordre causal des événements serveur. Si le premier est traité alors que l'adversaire est encore connecté, le premier perd ; s'ils sont déjà tous deux hors ligne, le résultat est `no_contest`. Une « même seconde » ou un « même tick » ne garantit pas un nul automatique. La documentation d'architecture a été ajustée ; cette règle doit être communiquée aux testeurs.
- Les données OneSync utilisées pour les distances restent des positions synchronisées, falsifiables par un client modifié. Le serveur ne reçoit pas de statistiques ou de vainqueur déclarés comme vérité par le client.
- Les arènes de cette version sont improvisées devant le challenger ; les zones approuvées et l'ancrage de terrain ne sont pas validés. Utiliser l'instance isolée pour cette qualification ; ne pas annoncer une intégration RP publique conforme aux zones autorisées.
- L'heure de départ est encore estimée par délai relatif/demi-ping, avec tampon fixe. La révision empêche une régression de l'heure, mais ne constitue pas une calibration d'horloges. Le départ, le décalage de lecture et les gels doivent être mesurés sur **deux vrais clients** avant validation de phase 2.
- Le renderer a évolué pour les manches, score et bannière finale ; son comportement et son coût sur GPU, son sol, ses textes et ses exports optionnels ne sont pas validés en GTA par cette revue.
- Les réactions à toutes les pannes possibles, à l'uptime long ou à une charge maximale ne sont pas prouvées par ces douze régressions. Aucun nombre de matchs simultanés supportés n'est certifié.

## Conclusion de revue

Aucun échec restant parmi les cinq suites ci-dessus sur les empreintes testées. Les défauts reproduits ont une régression durable dans `tests/review_phase2.lua`. **Phase 2 implémentée et testée hors jeu, pas validée avec deux vrais clients FiveM.** Le déploiement des derniers correctifs est contrôlé sur disque et dans le journal de rechargement ; reste à appliquer les procédures réelles du README et de VALIDATION_GTA_ET_DUEL avec preuves de version et deux observations corrélées. Inventaire, progression, récompenses et tournois restent en attente.
