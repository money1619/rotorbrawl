# Audit de validation réelle — 18 octobre 2026

Périmètre figé : prototype phase 1, photographié le **18 octobre 2026 à 16:00:12 UTC / 12:00:12 America/Toronto**. Cet audit précède les éventuels travaux de phase 2 menés ensuite par l'équipe. Aucune phase n'est déclarée validée par ce document. Aucun serveur ni ressource n'a été redémarré pour cet audit ; aucune configuration, permission ou donnée métier n'a été supprimée ou modifiée.

## 1. Fichiers effectivement observés

Dossier source : `resources/[Money]/Chaos_Arena`. Copie de test : `/home/fivem2/FXServer/txData/SpinTest/resources/[test]/Chaos_Arena`.

Le [relevé des 23 fichiers initiaux](evidence/audit-20261018T160012Z/files.json) contient tailles, dates UTC, SHA-256 et comparaison avec la copie de test. À cette première photographie, aucun dépôt Git n’était détectable. Un dépôt a été initialisé ensuite pendant la revue ; voir le complément daté ci-dessous. Il ne reconstruit pas rétroactivement un historique des modifications antérieures au premier commit. Les dates de modification et les anciens rapports ne remplacent pas cet historique.

| Fichiers présents | Responsabilité réelle | Comparaison source / copie de test au relevé |
|---|---|---|
| `fxmanifest.lua` | version déclarée `0.1.0`, liste des scripts | identique |
| `config/shared.lua` | profils attaque/endurance, arène et paramètres | identique |
| `shared/rng.lua` | RNG indépendant par simulation | identique |
| `server/physics/engine.lua`, `collisions.lua`, `boundaries.lua` | moteur serveur 2D Lua pur, trames avant/après événements | identiques |
| `server/debug.lua` | commande admin individuelle, calcul et diffusion | identique |
| `client/main.lua`, `client/renderer.lua` | événements, interpolation, marqueurs locaux | identiques |
| `tests/run.lua`, `physics_test.lua`, `emulator.lua` | suites hors jeu, non chargées par le manifeste | identiques, également copiés mais non exécutés par le serveur |
| `README.md`, huit documents dans `docs/` | installation, conception, spécifications, tests et licences | identiques |
| `PROJECT_STATUS.md`, `CHANGELOG.md` | suivi plus récent côté source | différents ; ces différences documentaires ne modifient pas le code exécuté |

Par rapport aux empreintes historiques du banc CPU dans PROJECT_STATUS, `server/debug.lua` et `tests/physics_test.lua` ont encore évolué. Les corrections récentes du rendu sont présentes dans le fichier effectivement lu, pas déduites d'un message d'équipe. Les empreintes courantes principales sont :

```text
fxmanifest.lua             9750af53096d6af2cfb3af75193fba564a2772d8172ce35d3fd0f9546c622ece
server/physics/engine.lua  7615befc99cc5813c01c753cf240b5c65f3835d6a45b04e7e145c6ce8a4a170b
server/debug.lua           cd45b51d043d3561605469b6b47a712210b79482d3316b81a829f99679857039
client/main.lua            77db534c38c17631627ded178ab80a22fc1dd22170f5c02b5b0f5539c86be69e
client/renderer.lua        c3be793f1e1fb047dd44c2555c6b4e934e4b519262499d131924435ffedc246b
```

Pour cet audit, les ajouts sont ce rapport, la procédure/plan associés et les preuves dans `docs/evidence/`, plus les liens dans README/suivi/changelog. Aucun script de gameplay n'a été modifié par Turing. Des modifications ultérieures d'autres membres ne sont pas couvertes par cette photographie : consulter leurs empreintes et relancer les vérifications avant déploiement.

## 2. Instance et version réellement observables

La [réponse publique sélectionnée](evidence/audit-20261018T160012Z/runtime.json) confirme :

- FXServer `35265` Linux, GTA build `2699`, `onesync_enabled = "true"`.
- Ressource `Chaos_Arena` annoncée active ; `chat`, `hardcap`, `sessionmanager`, `mapmanager`, `spawnmanager`, `basic-gamemode`, `fivem-map-skater` présents. Pas d'ESX, d'ox_lib ou d'oxmysql sur cette instance de test.
- Port `30126`, quatre places configurées ; zéro joueur au relevé. L'accès distant et les permissions d'un futur testeur ne sont pas validés par cette réponse locale.

La [vérification du processus et des commandes de chargement](evidence/audit-20261018T160012Z/runtime-load-inference.json) confirme le processus `50262`, son dossier `txData/SpinTest` et les options `+set onesync on +exec server.cfg`. Les neuf fichiers d'exécution sur disque sont identiques à la source ; leurs dates sont antérieures au dernier rechargement consigné, à **15:51:05 UTC**. Le journal contient bien les démarrages de `Chaos_Arena`.

**Conclusion limitée :** la version de manifeste est `0.1.0`, et les éléments observés concordent avec la source ci-dessus chargée au dernier redémarrage de ressource. C'est une **inférence**, pas une attestation cryptographique de la mémoire de FXServer : aucun identifiant de build/empreinte embarqué n'est exposé par le prototype. Ne pas confondre une comparaison de fichiers avec la lecture du code en mémoire. Aucun client connecté ne permet non plus de contrôler sa copie téléchargée pendant cet audit.

Le serveur de test est masqué de la liste (`sv_master1 ""`). Cela ne constitue pas un contrôle d'accès. La commande est restreinte par `RegisterCommand(..., true)` ; la configuration accorde `command allow` au groupe admin. Les identités privées configurées ne sont pas reproduites dans ce rapport. L'ACE effective du testeur doit être contrôlée avant son essai.

## 3. Tests relancés et preuves conservées

Les commandes ont été exécutées sur la photographie ci-dessus, sans moteur factice dans les tests physiques. Les [commandes et codes de retour](evidence/audit-20261018T160012Z/checks.json) sont conservés.

| Vérification | Résultat relancé | Preuve | Ce qu'elle ne valide pas |
|---|---|---|---|
| `lua5.4 tests/run.lua` | **112/112**, code 0 : 108 cas physiques, 4 cas adaptateur | [journal complet](evidence/audit-20261018T160012Z/physics.log) | Cfx client, ACE réelles, GPU, réseau réel |
| `lua5.4 tests/emulator.lua --json …` | **33/33**, code 0 | [journal](evidence/audit-20261018T160012Z/emulator.log), [rejeu JSON](evidence/audit-20261018T160012Z/emulator.json) | véritable duel partagé, client GTA, natives réelles |
| `Renderer.selfTest()` | succès, code 0 | [journal](evidence/audit-20261018T160012Z/renderer.log) | visibilité GTA ou rendu sur GPU |
| `luac5.4 -p` sur les Lua présents | succès, code 0 | [journal](evidence/audit-20261018T160012Z/syntax.log) | sémantique des natives, disponibilité des dépendances |
| Injection d'une exception dans `Engine.step` | **défaut de nettoyage reproduit**, hors suite de 112 | [reproduction et code injecté](evidence/audit-20261018T160012Z/fault-injection.log) | ce n'est pas un succès de gestion d'erreur ni une panne observée en production |

L'émulation charge le vrai serveur et le vrai client dans des environnements séparés. Natives, horloge, réseau et joueurs sont simulés. Trois sessions `/spin_test` différentes ne constituent pas deux participants du même match. Ses 33 succès ne couvrent pas les huit scénarios d'un futur duel partagé.

Mesures reproduites : erreur maximale de position en lecture active 2,1/1,9/1,5 mm ; départ 222/265/287 ms après GO, écart entre profils 65 ms. Profil RTT 250 ms : 41 images gelées sur 3 865 images de lecture ; scénario chaotique : zéro gel et erreur active maximale 1,9 mm. Le débit d'environ 0,56–0,57 Kio/s est une estimation de taille msgpack sans en-têtes réseau.

## 4. Ce qui a réellement tourné dans FiveM

Les journaux originaux existent dans `/home/fivem2/FXServer/txData/SpinTest/` ; leur [extrait conservé pour l'audit](evidence/audit-20261018T160012Z/cfx-server-extract.log) sélectionne les chargements, résultats et éventuelles erreurs sans recopier de secrets de configuration.

| Essai historique serveur | Journal original | Résultats |
|---|---|---|
| premier, OneSync désactivé | `spintest-bench-300.log` | 300 manches, 186 attaque / 114 endurance / 0 nul ; 77 éjections, 223 arrêts |
| second, OneSync activé | `spintest-bench-300-onesync.log` | 300 manches, 173 / 127 / 0 ; 77 éjections, 223 arrêts |
| après correction des trames/horloge | `spintest-bench-300-record.log` et `spintest.log` | 300 manches, 189 / 110 / 1 ; 93 éjections, 207 arrêts ; médiane 14,0 s ; CPU par manche p50 21,58 ms, p95 50,08 ms |

Le troisième journal contient aussi des lignes d'essais précédents : c'est un journal cumulé, pas trois cents nouvelles manches pour chaque ligne de démarrage. Les seeds et détails historiques restent dans PROJECT_STATUS. Aucune nouvelle commande de banc n'a été envoyée au serveur pendant cet audit.

Ces preuves valident **le chargement et la simulation côté serveur CfxLua uniquement**. Il n'y a aucune preuve de rendu GTA, de sol correct, de collision visuellement lisible, d'ACE appliquée à un vrai joueur ou de duel partagé entre deux vrais clients. L'hôte Linux n'a pas de client GTA/FiveM pilotable ni Wine dans son PATH ; je ne peux pas exécuter cette validation visuelle ici.

## 5. Défauts et limites restants

| Priorité | Constat réel | Conséquence / traitement requis |
|---|---|---|
| bloquant pour déclarer la phase 1 validée | aucun essai client GTA enregistré | exécuter et remplir la procédure liée ci-dessous |
| bloquant pour déclarer un duel partagé prêt | seul `server/debug.lua` gère une session par administrateur ; aucun défi/consentement/match commun dans la photographie | concevoir puis tester les modules du duel avant de l'annoncer disponible |
| élevé, reproduit hors jeu | une exception inattendue dans le fil de calcul debug laisse `active[src]` occupé ; pas de message d'annulation ; la commande suivante est refusée comme occupée | finalisation idempotente commune aux erreurs/annulations/déconnexions, protection du fil et test d'injection avant réutilisation |
| élevé pour un match partagé | horloge actuelle basée sur délai relatif corrigé par demi-ping, tampon fixe 200 ms | pas d'horloge commune mesurée ; tampon commun et calibration de l'horloge à qualifier |
| élevé | nettoyage prévu dans les chemins habituels, mais pas de garantie sur toutes les exceptions | ne pas assimiler 112 succès à un audit complet des erreurs |
| visuel | centre `ped.z - 0,98 m`, sans mesure du sol 2 m devant | flotte/intersection possible sur pente, marche, intérieur ; tester d'abord sur sol plat |
| visuel, constat de code | bandeau de préparation/résultat et télémétrie de la première toupie utilisent tous deux `(0.5, 0.12)` | chevauchement probable ; confirmer en GTA et séparer les lignes avant validation visuelle |
| protocole | `debug-N` recommence au rechargement, état client sans version globale de session | isolation insuffisante des anciens paquets pour un futur service de matchs ; ajouter epoch, génération de connexion et version d'état |
| charge | tranches de 600 pas, quatre sessions debug ; pas de mesure de charge concurrente/réseau réel | définir limites par mesure ; les ms par manche ne sont pas les ms par frame serveur |

Les dimensions vérifiées sont `R = 0,60 m`, `h = 0,08 m` dans la configuration active, pas la valeur de repli `0,05` du renderer. Les effets temporaires utilisent 380 ms pour les flashs et 0,65 s pour la sortie visuelle. Aucun modèle 3D final n'existe. Les limites d'arène sont celles du modèle serveur ; la cuvette et ses parois ne sont pas des collisions GTA.

## 6. Complément après correction source — 16:11:22 UTC

L'équipe a initialisé un dépôt pendant la revue. Révision source testée : `1f50334` (commit du correctif de nettoyage et des documents d'audit), succédant à `8df1bb4` (import initial du prototype). Les versions documentaires sont encore complétées après ce commit ; aucune publication ni commande Git modifiant l'historique n'a été exécutée par Turing.

Archimedes a protégé les fils de la commande de test par `pcall`, avec libération/annulation en cas d'erreur, et ajouté un scénario d'injection à l'émulateur. Ce changement répond au défaut reproduit ci-dessus ; il ne constitue pas un développement d'inventaire ou de duel partagé.

Les [preuves de la seconde vérification](evidence/audit-fix-20261018T161122Z/checks-and-version.json) enregistrent le commit complet, les empreintes source/copie, les codes retour et la stabilité des sources pendant les tests :

| Vérification source corrigée | Résultat | Preuve |
|---|---|---|
| tests physiques/adaptateur | **112/112**, code 0 | [journal](evidence/audit-fix-20261018T161122Z/physics.log) |
| émulation, avec erreur moteur injectée | **37/37**, code 0 | [journal](evidence/audit-fix-20261018T161122Z/emulator.log) |
| self-test renderer et syntaxe | succès | [renderer](evidence/audit-fix-20261018T161122Z/renderer.log), [syntaxe](evidence/audit-fix-20261018T161122Z/syntax.log) |

**Différence de déploiement observée :** `server/debug.lua` corrigé a l'empreinte `2da29d5bc0602d5722342b4f5722eaa8a0c6296ef1213694527e706afc3ce5b9`, tandis que la copie SpinTest conserve `cd45b51d043d3561605469b6b47a712210b79482d3316b81a829f99679857039`. `tests/emulator.lua` diffère aussi, mais n'est pas un script chargé par FiveM. Les huit autres fichiers d'exécution restent identiques. Le manifeste est toujours `0.1.0` dans les deux copies : ce numéro seul ne distingue pas les correctifs.

Le correctif est donc **vérifié hors jeu dans la source, pas validé dans le runtime actuellement déployé**. Le défaut de nettoyage reste un risque de la copie serveur ancienne jusqu'à son chargement contrôlé et ses nouvelles preuves. Aucun rechargement de ressource ni redémarrage de serveur n'a été effectué pour combler cette différence pendant cet audit. Le banc serveur historique de 300 manches ne valide pas ce nouveau chemin d'erreur.

La phase 2 peut être en préparation séparée : les huit scénarios de duel restent non exécutés tant qu'un gestionnaire commun à deux participants n'est pas livré et testé. Les 37 succès concernent toujours des sessions debug individuelles émulées.

### Préparation de phase 2 observée après le complément

Pendant la finalisation du rapport, Archimedes a commencé l'extraction du calcul/découpage vers `server/runner.lua` et créé `config/server.lua` et `shared/protocol.lua`. `server/debug.lua` et `tests/emulator.lua` utilisent désormais ce runner dans la source de travail. Ce ne sont pas des preuves d'un gestionnaire de duel livré ou chargé.

Turing a modifié **uniquement les chargeurs de tests** `tests/run.lua` et `tests/physics_test.lua` pour charger le runner dans le bon environnement d'horloge/yield. La [troisième vérification hors jeu](evidence/audit-runner-20261018/checks-and-version.json), sur des sources stables, donne encore [112/112](evidence/audit-runner-20261018/physics.log) et [37/37](evidence/audit-runner-20261018/emulator.log).

Ces modifications sont postérieures au snapshot et au commit de correctif ci-dessus. Le manifeste source observé à cette étape n'importe pas encore le runner : la branche de travail est **en intégration**, pas un paquet à copier puis redémarrer. Ne pas mélanger la version de test déployée et ces fichiers de préparation. Le prochain lot doit vérifier son manifeste, ses imports/dépendances, sa version et ses propres tests avant tout rechargement contrôlé. Le présent audit n'a chargé aucun de ces nouveaux modules dans FiveM.

## 7. Suite autorisée par ce rapport

Procédure GTA, plan technique du duel et huit cas d'acceptation : [VALIDATION_GTA_ET_DUEL.md](VALIDATION_GTA_ET_DUEL.md). Les contrôles réels restent à renseigner. L'équipe indique avoir reçu séparément une demande de poursuite de phase 2 : cela n'efface ni le blocage de validation client ni les limites de cet audit figé.

Inventaire, atelier, SQL, récompenses, progression, tournois, modèles définitifs et zones ouvertes restent hors de ce lot. Aucune phase ne passe à « validée » par simple ajout de fichiers ou succès d'une émulation.
