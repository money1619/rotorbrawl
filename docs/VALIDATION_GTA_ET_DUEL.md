# Validation GTA réelle et duel partagé minimal

Date : 18 octobre 2026. **Procédure et conception, pas une déclaration de validation ni des commandes de duel déjà disponibles.** Point de départ vérifié : [audit réel et preuves](AUDIT_VALIDATION_2026-10-18.md).

## 1. Test réel du prototype, sans changement de serveur

Le serveur de test tourne déjà. Ne pas lancer une deuxième instance, ni exécuter `ensure Chaos_Arena` pour « vérifier » : `ensure` redémarre une ressource déjà active. Aucun redémarrage n’est nécessaire pour commencer le parcours visuel sur la copie auditée. Le correctif d’exception décrit dans l’audit n’est toutefois pas encore déployé : son chargement contrôlé devra être distingué d’un simple test, puis la version du parcours relevée à nouveau. Connexion distante et affichage ne peuvent être testés que depuis un vrai client FiveM/GTA V.

### Préparation

1. Sur le PC de test, ouvrir FiveM avec GTA V disponible, puis F8 : `connect 192.99.0.20:30126`. L'instance est masquée de la liste. Si la connexion échoue, conserver le message exact et l'heure ; l'écoute locale du port ne prouve pas le passage du pare-feu externe. Ne pas essayer le serveur RP sur un autre port à la place.
2. Attendre le chargement et le spawn. Relever le build/version client, l'heure, le ping approximatif et les réglages/FPS. Se placer à pied, immobile, sur une surface extérieure plate et dégagée, sans marche ni véhicule à deux mètres devant. Le serveur n'a pas de script de téléportation fourni par SPIN ARENA.
3. Vérifier les droits : `/spin_test` exige l'ACE serveur `command.spin_test`. En cas de refus, un administrateur vérifie `test_ace <principal_du_testeur> command.spin_test` dans la console serveur. Si nécessaire, il peut accorder uniquement cette ACE au principal exact du testeur avec `add_ace <principal_du_testeur> command.spin_test allow`. Aucun droit n'est modifié par les auteurs de cette procédure. Ne pas ouvrir la commande à tous les joueurs ; ne pas supprimer ensuite une autorisation préexistante.
4. Ouvrir F8 pour repérer d'éventuelles erreurs Lua, puis refermer pour observer. Si le client permet `resmon 1`, relever son coût au repos, pendant la manche et après nettoyage ; un refus de cette commande de développement n'est pas une erreur de SPIN ARENA. `resmon 0` ferme l'affichage. Aucune désactivation d'anti-triche ou installation d'exécuteur Lua n'est requise.

Références vérifiées : [connexion et console client](https://docs.fivem.net/docs/client-manual/console-commands/), [ACE et commandes serveur](https://docs.fivem.net/docs/server-manual/server-commands/), [RegisterCommand restreint](https://docs.fivem.net/docs/scripting-manual/migrating-from-deprecated/creating-commands/).

### Parcours A — arrêt de rotation et nettoyage normal

Dans le chat : `/spin_test attack endurance 1` (F8 : `spin_test attack endurance 1`, sans slash).

| Étape | Contrôle à réaliser dans GTA | Résultat attendu / preuve à conserver |
|---|---|---|
| 1. Placement | observer avant de déplacer le personnage | anneau centré environ 2 m devant le personnage, rayon 0,60 m ; trois repères rouges de poches ; pas d'intersection ou flottement incohérent du repère de sol sur ce terrain plat |
| 2. Hauteur des toupies | regarder de côté, puis de dessus si la caméra le permet | deux formes orange/cyan visibles ; hauteur conforme au bol mathématique (`h = 0,08 m`, plus haut vers le bord), sans saut vertical parasite. Le prototype ne contient pas de vraie surface de bol 3D : un écart voulu jusqu'à 8 cm au-dessus du plan central n'est pas à confondre avec un mauvais sol |
| 3. Compte à rebours | lire le texte dès l'apparition de l'arène | « LANCEMENT DANS … s », descendant vers zéro ; pas de départ fictif en l'absence d'heure. Relever texte masqué ou chevauchement : les coordonnées de HUD actuelles présentent ce risque |
| 4. Rotation/mouvement | observer le point repère sur chaque toupie et les trajectoires | rotation et déplacement lisibles, aucun contrôle joueur sur la toupie ; environ 200 ms de tampon d'affichage après le GO estimé, à mesurer et non à considérer comme synchronisation prouvée |
| 5. Impacts/limites | observer les rencontres et les flashs | trajectoires qui changent aux chocs, aucun passage manifeste à travers l'autre disque, rebond visuel sur une paroi pleine. Cette seed contient 4 impacts et 1 rebond de paroi dans la trace Lua courante |
| 6. Résultat | comparer HUD et console serveur | profil attaque (côté 1) gagnant, motif `spin_out`, environ 16,10 s de temps simulé pour la photographie auditée ; le journal serveur donne matchId/seed/motif. La victoire n'est pas à déduire d'une déclaration du client |
| 7. Nettoyage | attendre après le résultat et observer encore 5 s | bandeau maintenu environ 3,5 s après réception de fin, puis plus d'arène, toupie, flash ni texte du match ; aucun nouveau dessin ni erreur F8. Relancer ensuite la même commande pour vérifier que la place est libre |

Les chiffres de seed sont des **résultats du moteur Lua actuel**, pas une observation GTA déjà réalisée. Si paramètres ou moteur changent, recalculer le cas avant d'utiliser ces attentes. Le résultat final est écrit dans la console serveur ; le chat de démarrage ne constitue pas ce journal de résultat.

### Parcours B — éjection

Revenir sur le même terrain plat et exécuter `/spin_test attack endurance 2`. Le moteur actuel termine par `ring_out`, gagnant côté 1, après environ **1,583 s** simulée. Filmer si nécessaire pour revoir cette manche courte. Vérifier le passage de la limite, le statut éjecté et la sortie visuelle (0,65 s), puis le résultat serveur et le nettoyage. Les poches autorisent une sortie à faible vitesse ; une sortie par-dessus une paroi est aussi possible à vitesse suffisante. Ne pas confondre ces règles mathématiques avec une collision GTA native.

### Parcours C — annulation et répétition

Exécuter `/spin_test attack endurance 1`, puis `/spin_test stop` pendant le compte à rebours. Vérifier la disparition et l'absence de réapparition pendant au moins 5 s. Refaire le test en arrêtant pendant le combat. L'arrêt dépend de l'arrivée du message réseau : ne pas exiger zéro milliseconde. Aucun résultat normal ne doit apparaître ensuite. Relancer et constater que la commande est acceptée.

Une seconde commande pendant une manche doit être refusée comme « déjà en cours » ; un autre joueur exécutant `/spin_test` obtient aujourd'hui **son propre test privé**, pas une place dans cette manche. La commande console `spin_test bench 300` ne montre aucune toupie dans GTA.

### Fiche à remplir, pas de valeurs fictives

```text
Date/heure/fuseau :
Version serveur/source (audit ou nouvelle empreinte) :
Version/build client, FPS, ping :
Testeur A (pseudonyme, pas d'identifiant privé) :
Terrain/lieu et état du personnage :
Parcours A : placement / hauteur / visibilité / décompte / impacts / résultat / nettoyage :
Parcours B : limite / éjection / résultat / nettoyage :
Parcours C : stop avant départ / stop en combat / absence de réapparition / nouvelle commande :
Erreurs F8 exactes et heure :
Ligne de résultat serveur correspondante (matchId, seed, motif) :
Captures/vidéo et observations :
Réussi / échoué / bloqué, avec motif pour chaque contrôle :
```

**Critère de passage du rendu du prototype :** les sept contrôles du parcours A, l'éjection B et les deux annulations C sont observés sur un vrai client, traces rattachées à la même version ; défauts de sol/visibilité/HUD et nettoyage corrigés ou explicitement bloquants. Une vidéo de rejeu web, une image générée ou un JSON d'émulation ne remplace pas cette fiche.

Les diagnostics actuels (chat de lancement, télémétrie `w/wob/statut`, avertissement de synchronisation, F8, journal serveur) suffisent pour le premier parcours. Aucun nouveau panneau ou outil intrusif n'est ajouté. Si le sol est incorrect, documenter d'abord le terrain et l'écart ; une future sonde client pourra diagnostiquer le sol, mais ne devra pas changer unilatéralement la hauteur de l'arène partagée.

## 2. Proposition du duel partagé — périmètre minimal

**À implémenter et tester séparément.** L'équipe peut préparer le code de phase 2 sur une autorisation distincte ; cela ne valide pas les étapes GTA ci-dessus. Le lot initial comprend deux joueurs consentants, une arène fixe vérifiée en jeu, deux profils de test validés côté serveur, deux manches gagnantes avec cinq manches maximum (égalités comprises), refus/annulation/abandon et nettoyage. Un match n'est calculé qu'une fois et diffusé aux deux participants. `/spin_test` reste un outil individuel et ne devient pas implicitement un match public.

En attente : spectateurs et zones libres avancées (phase 5), atelier/inventaire/SQL (phase 4), classement/XP/récompenses/tournois (phase 6), modèles et animations définitifs (phase 3). Aucun argent, objet ni progression n'est crédité. Les profils `attack`/`endurance` sont provisoires et explicitement non commerciaux.

### Identité, admission et réservations

- Identifiant serveur de match : préfixe de session de ressource (`epoch`) distinct après redémarrage + compteur monotone ; vérifier les collisions dans le registre. L'identifiant est une référence, jamais un secret autorisant une action.
- Associer chaque participant à son `source` **et à une génération de connexion**. Une réutilisation du même numéro après déconnexion ne donne pas accès à l'ancien match. L'identité de l'appelant vient du contexte serveur, jamais d'un champ client.
- Réserver les deux joueurs et l'arène avant toute opération susceptible de céder l'exécution. Un index par joueur et par arène refuse les inscriptions concurrentes ; les doubles acceptations ne créent pas deux matchs. Après un `await`, revérifier génération, état et réservation.
- Un défi en attente par joueur pour ce prototype ; expiration proposée 30 s. Cible différente, connectée, à moins de 10 m selon les données serveur, même bucket ; joueurs à pied, vivants et disponibles ; point d'arène fixe autorisé à portée. Les positions des peds synchronisées restent falsifiables par un client modifié : ce contrôle réduit les abus, ce n'est pas une garantie anti-téléportation.
- Le client ne peut sélectionner que la clé d'un profil autorisé. Stats et seed proviennent de la copie serveur, figées au verrouillage. Aucun champ position d'arène, masse, rotation initiale, vainqueur, score ou récompense n'est accepté du client.

### États et politique de fin

```text
pending --acceptation--> preparing --> countdown --> playing --> round_over
   |                        |              |            |             |
refus/expiration       erreur/timeout   annulation   abandon/drop   manche suivante
   |                        |              |            |             |
   +---------------------> cancelled       +---------> settling <----+
                                                        |
                                                     finished
```

Chaque transition reçoit une version croissante et a une échéance. `preparing` : 8 s proposées ; compte à rebours 3 s ; une manche au plus `Tmax + tampon commun + marge` ; pause 4 s ; borne globale du match fixée selon le maximum de cinq manches. Les valeurs sont à qualifier, pas des performances acquises.

Avant le premier GO : refus, annulation, départ ou contexte devenu invalide → annulation sans vainqueur. Après le premier GO : abandon/déconnexion/mort → victoire de l'adversaire selon la règle validée ; départ des deux dans la même décision serveur → `no_contest`. Entre les manches, l'abandon reste un abandon du match. Une erreur interne → `no_contest`, pas une victoire arbitraire. Si la fin normale a déjà été figée, une déconnexion ultérieure ne change pas le résultat. Définir cet ordre dans les tests de concurrence.

`finish(match, outcome)` est idempotent : un seul état terminal, un seul résultat diffusé, libération des deux index joueurs, réservation d'arène, minuteurs, jobs et buffers dans tous les cas, y compris exceptions. Conserver un tombstone terminal de durée/nombre bornés pour rejeter les vieux paquets, puis libérer le reste. Les clients nettoient sur fin, annulation, désabonnement, arrêt de ressource et échéance d'absence de données. Aucun versement à rendre idempotent dans ce lot.

### Horloge et cohérence visuelle

Ne pas envoyer simplement deux délais « 3 s » puis annoncer une synchronisation. Les `GetGameTimer` client et serveur n'ont pas la même origine. Prévoir un échange horodaté, plusieurs échantillons de RTT et une estimation d'offset fondée sur les échantillons les moins retardés. Ces mesures ne servent qu'à l'affichage ; un client qui ment ne peut ni retarder le résultat serveur ni modifier le lancement physique.

Le serveur fixe un instant de GO et une révision de lancement après préparation. Il diffuse aux deux participants **le même matchId, epoch, numéro de manche, révision, arène monde et calendrier serveur**. L'en-tête contient toute l'initialisation ; le compte à rebours est une mise à jour versionnée, pas un prérequis susceptible d'être perdu. Les messages arrivés tard ou les anciens en-têtes ne remettent pas la scène en arrière.

Prévoir un **tampon de lecture commun au match**, choisi avant le GO d'après les mesures des deux clients et plafonné. Deux tampons différents choisis indépendamment produiraient deux combats vus à des moments différents. Cible proposée à vérifier : écart de départ visuel entre clients ≤ 100 ms en réseau stable, avec leur RTT/gigue consignés. Si l'incertitude dépasse cette cible, retarder la préparation ou signaler une synchronisation insuffisante ; ne pas déclarer le test réussi par changement de seuil après coup.

Moteur actuel conservé : calcul Lua serveur fixe à 120 Hz, jobs bornés et yielding, keyframes à cadence réduite et avant/après événements. Le serveur émet une même trace vers une audience limitée aux deux joueurs ; ils interpolent sans décider du résultat. Les trames portent epoch/match/manche/révision/seq ; doublons rejetés, messages périmés ignorés. Ne pas interpoler au travers d'un trou contenant potentiellement une collision : réordonner/drainer les tranches contiguës, geler ou demander une reprise bornée. Aucun envoi à tous les joueurs (`-1`).

La fin publiée est pilotée par l'horloge serveur et la durée simulée, avec marge d'affichage cohérente avec le tampon commun ; aucun accusé client ne fixe le vainqueur. Les futurs événements restent visibles avec une avance limitée : le prototype actuel peut exposer jusqu'à 1 s de futur dans une tranche ordinaire, 0,1 s dans la tranche finale. Aucun pari n'est autorisé et aucun abandon ne relance la seed.

### Contrats proposés, pas des API déjà disponibles

Pour rester proche de l'architecture prévue, utiliser `ox_lib` **3.32.3 déjà installé sur le serveur RP**, si cette dépendance est retenue. La copie isolée SpinTest n'en dispose pas encore : son installation/chargement et les scripts d'import doivent être vérifiés avant usage. Aucun remplacement de dépendance, aucune intégration ESX/SQL nécessaire au moteur ; un bridge ESX facultatif ne doit pas empêcher les tests standalone.

Intentions proposées : `spin_arena:challenge {target, top}`, `respond {id, accept, top}`, `cancel {id}`, `forfeit {}`, `state {}`. Réponses courtes `{ok, code, …}` ; erreurs de schéma, fréquence, disponibilité, distance, bucket, contexte et expiration définies et traduites. Ajouter un contrat de calibration/ready/resync borné si la synchronisation retenue l'exige ; noms finaux à figer avant le code.

Événements serveur ciblés : `spin_arena:cl:challenge`, `match`, `countdown`, `frames`, `roundEnd`, `matchEnd`, `cancel`. Conserver les champs du rendu actuel et ajouter epoch/version/identité des participants/score. Même `(epoch, matchId, round, revision)` signifie un doublon ; une nouvelle manche réinitialise ses buffers sans perdre le score. Une ancienne manche ne remplace jamais une plus récente. Bannière finale distincte d'une fin de manche.

Le contexte réseau, les types stricts, longueurs, nombres finis, limites par action/joueur et plafonds globaux sont vérifiés sur le serveur. Le résultat ne dispose d'aucun événement d'écriture client. Référence : [Cfx, sécurité des événements](https://docs.fivem.net/docs/developers/server-security/), [OneSync et données serveur](https://docs.fivem.net/docs/scripting-reference/onesync/). Les exports/callbacks externes doivent être reliés aux sources installées avant implémentation.

## 3. Fichiers à modifier par petits lots

| Lot | Fichiers proposés | Changement / preuve exigée |
|---|---|---|
| correction du prototype avant réutilisation | `server/debug.lua`, tests d'erreur associés | correctif source déjà vérifié (37/37 émulation), à charger et contrôler sur l’instance avant réutilisation ; préserver le test d’injection et vérifier la libération réelle |
| extraction réutilisable en cours | `server/runner.lua`, chargeurs des tests debug/émulateur, manifeste | mutualiser le calcul/découpage sans changer la physique ; 112/112 et 37/37 hors jeu, câblage FiveM à terminer |
| intégration minimale | `shared/protocol.lua`, `server/security.lua`, `server/arenas.lua` | contrats, limites et schémas, réservation unique ; tests purs sans natives |
| orchestration serveur | `server/matches.lua`, `server/challenges.lua`, `server/main.lua` | machine à états commune, deux joueurs, consentement, horloges, résultat et nettoyage ; interfaces injectable clock/transport/players/engine pour tests |
| bridge facultatif | `server/bridge.lua` | noms et contexte des joueurs, ESX seulement si présent ; aucune propriété d'inventaire fictive |
| câblage | `fxmanifest.lua`, `config/shared.lua` et éventuellement configuration serveur dédiée | ordre des modules, éventuel import ox_lib et limites ; arène réellement relevée, pas de coordonnées présentées comme validées avant GTA |
| rendu/commandes | `client/main.lua`, `client/renderer.lua`, `locales/fr.lua`, `locales/en.lua` | défi/refus/acceptation/abandon, horloge versionnée, score/manches multiples, séparation des textes qui se chevauchent |
| vérifications | `tests/duel_test.lua` ou modules de test équivalents, `tests/run.lua`, `tests/emulator.lua` | huit cas ci-dessous, injection d'erreurs, vraie trace unique diffusée à deux clients émulés |
| suivi | README, PROJECT_STATUS, CHANGELOG | commandes réellement livrées et résultats par environnement, preuves associées à la révision |

Ces noms désignent des modules internes proposés, pas des fonctions FiveM inventées. Ne pas créer de fichiers vides. `server/physics/*` reste inchangé sauf défaut démontré par une régression. Les commandes de duel éventuelles `/spin_defi`, `/spin_accepter`, `/spin_refuser`, `/spin_abandon` sont **proposées, pas disponibles dans la photographie auditée** ; une annulation avant départ doit aussi disposer d'un contrôle explicite.

## 4. Huit tests reproductibles du duel

Préconditions communes : version/empreinte figée, arène fixe libre vérifiée, deux joueurs A/B connectés et disponibles, aucune récompense. Au départ et à la fin de chaque cas, relever le registre des joueurs/matchs/arènes et le nombre de jobs/buffers. Les mécanismes d'introspection appartiennent aux tests/diagnostics administrateur, pas à une API client de confiance.

| ID | Actions contrôlées | Attendu serveur | Attendu sur deux clients réels / traces |
|---|---|---|---|
| D01 Acceptation | A défie B ; B accepte avec un profil autorisé ; attendre le GO | un seul matchId, deux réservations, une seule simulation et une arène ; stats calculées depuis config | même matchId/arène/manche/révision ; même GO et même trace ; enregistrer les deux écrans et mesurer l'écart de départ, cible stable ≤ 100 ms |
| D02 Refus | A défie B ; B refuse avant 30 s | défi terminal `declined`, aucun match ni arène occupée | refus notifié aux deux, aucun décompte/prop ; nouveau défi accepté ensuite |
| D03 Annulation | après acceptation, A annule avant GO ; laisser parvenir les trames en vol ; répéter avant acceptation | un seul terminal annulé, aucun score ; jobs et réservations libérés | les deux scènes disparaissent, aucune réapparition ou résultat normal dans les 5 s suivantes |
| D04 Déconnexion | après GO et avant fin calculée, B quitte ; reconnecter B (nouvelle génération), puis répéter avec double départ | forfait B au plus une fois ; plus aucun envoi à l'ancienne connexion ; double départ `no_contest` selon ordre défini | A reçoit le motif serveur ; la nouvelle connexion de B ne reprend pas le match ; place/arène réutilisables |
| D05 Retard/désordre | injecter retard, doublons, message de countdown avant en-tête, ancienne manche après la suivante et tranche manquante ; conserver les temps d'injection | état/résultat inchangés ; reprise et buffers bornés ; aucune donnée client ne modifie le GO/résultat | aucune régression de manche/score ; aucun faux départ ; gel signalé et borné si données manquent ; aucun lissage à travers collision inconnue. Injection déterministe dans l'émulation ; réseau dégradé réel mesuré séparément |
| D06 Deux demandes simultanées | A déclenche deux défis/acceptations dans le même créneau, puis deux joueurs tentent de réserver A | une réservation seulement ; autre réponse `busy`/conflit, jamais deux matchs ; limite de fréquence distincte du verrou métier | un seul en-tête autoritaire affiché, pas de scène remplacée par un deuxième match |
| D07 Fin normale | exécuter des seeds documentées jusqu'à deux manches gagnées ; répéter égalité et limite cinq manches | score mis à jour une fois par manche ; un seul `matchEnd`, vainqueur/motif autoritaires ; tous verrous libérés | même score/résultat sur A et B, bannière puis nettoyage ; le test individuel seed 1 ne remplace pas ce parcours partagé |
| D08 Erreur et nettoyage | injecter exception moteur, échec de diffusion et contexte joueur invalide à chaque état ; répéter deux appels de finalisation | erreur journalisée avec matchId/état ; `no_contest` ou annulation selon moment ; aucun index, arène ou job bloqué ; nouvelle partie possible | aucun vainqueur inventé, scène annulée ou watchdog borné ; aucune boucle de rendu persistante. Injection en tests isolés, pas en serveur RP |

Ajouter aux permutations : expiration sans réponse, acceptation après expiration, refus par un tiers, spoof d'id, types/nombres non finis, sortie de bucket, mort, changement d'état pendant un `await`, arrêt de ressource et ancienne session serveur. Les commandes/actions administrateur utilisées pour provoquer ces cas sont documentées et désactivées dans la livraison publique.

### Séparation obligatoire des résultats

| Niveau | À écrire aujourd'hui pour D01–D08 | Preuve exigée avant validation |
|---|---|---|
| automatisation logique | **non exécuté pour un vrai gestionnaire de duel partagé** ; les quatre tests debug actuels ne suffisent pas | runner chargeant les vrais modules, horloge virtuelle, assertions sur registres/terminaux, logs/code 0 pour chaque Dxx |
| émulation avec deux participants du même match | **non exécuté** dans les 33 contrôles existants | deux environnements clients abonnés à une seule simulation, journaux de messages et métriques de chaque Dxx ; pas deux `/spin_test` distincts |
| serveur CfxLua | banc physique existant uniquement | vrai gestionnaire chargé, dépendances vérifiées et journaux des commandes/événements ; aucun rendu client prétendu |
| vrais clients FiveM | **non exécuté** | fiche signée par observations de deux clients, deux vidéos ou captures horodatées, logs serveur corrélés, version exacte ; défauts et tests bloqués explicités |

Une injection de réseau désordonné dans l'émulation teste la robustesse applicative hors des garanties du transport FiveM ; elle ne prouve pas qu'un tel désordre est survenu dans FiveM. Distinguer précision des positions en lecture active, proportion/durée des gels, décalage temporel et résultat serveur.

## 5. Décision de sortie

Le rendu de phase 1 attend encore son essai GTA et la correction des défauts bloquants observés. Le duel partagé de phase 2 ne sera déclaré validé qu'après D01–D08 automatisés, leur émulation sur **un seul match partagé**, puis les parcours indispensables avec **deux vrais clients**, avec exceptions/nettoyage contrôlés. Si un client GTA n'est pas disponible, marquer les cases bloquées et arrêter la déclaration de validation, pas inventer une preuve.

Aucun inventaire, tournoi, système de progression, pari ni récompense ne commence pour contourner ces critères. Aucune approbation de conception ou autorisation de poursuivre le code ne vaut validation d'un test.
