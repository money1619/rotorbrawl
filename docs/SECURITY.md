# Sécurité, validation et persistance — SPIN ARENA

Auteur : Archimedes. Date : 18 octobre 2026. Phase 0 : **conception uniquement**.

Aucune de ces protections n'est implémentée ni testée. Les comportements d'ESX, d'ox_inventory et d'oxmysql cités ont été lus dans le code installé ; ils devront être revérifiés si ces ressources changent de version.

## 1. Modèle de menace

| Acteur | Ce qu'il peut faire |
|---|---|
| Joueur avec un client modifié (exécuteur Lua, menu) | déclencher n'importe quel événement réseau ou callback avec n'importe quelles données, à n'importe quelle fréquence ; appeler les callbacks NUI ; lire tout ce que le serveur lui envoie ; fausser sa position (téléportation) ; modifier son affichage local |
| Joueur normal qui triche par le jeu | se déconnecter ou mourir au bon moment, multiplier les comptes, s'entendre avec un autre joueur, harceler par des défis, occuper une arène |
| Tiers en jeu | tuer un participant, perturber une arène |
| Administrateur | utiliser les commandes d'administration ; ses actions doivent laisser une trace |
| Panne | crash du serveur, arrêt de la ressource, base SQL indisponible, inventaire qui refuse une opération |

Hors périmètre : un autre script du serveur compromis ou malveillant, l'accès direct à la base, le système d'exploitation.

## 2. Ce qu'il faut protéger

Argent ESX, objets (toupies, pièces, lanceurs, kits), unicité des toupies, résultats et classements, récompenses, disponibilité du serveur, et données personnelles minimales (identifiants ESX dans les journaux).

## 3. Principes

1. Le client envoie des **intentions**, jamais des faits : pas de statistiques, de métadonnées, de positions de toupie, de seed, de vainqueur ni de montant.
2. Tout ce que le serveur utilise, il le relit lui-même : base, inventaire, coordonnées du ped (OneSync), état du match.
3. Une requête invalide échoue sans effet de bord et avec un code d'erreur court. Elle ne fait jamais planter le serveur (`lib.callback` exécute déjà le gestionnaire dans un `pcall`, `imports/callback/server.lua:116–121`).
4. Toute opération qui touche l'argent ou les objets est **journalisée en base avant** l'effet externe, et ne peut pas être rejouée.
5. Tout état a une fin : échéances, nettoyage, reprise au démarrage.
6. Pas d'obfuscation, pas de mécanisme caché, pas de code chargé à distance (§15).

## 4. Traitement d'une requête

Chaque callback enregistré dans `server/main.lua` suit le même ordre, dans `server/security.lua` :

1. **Fréquence** : seau de jetons par joueur et par action (§6). Au-delà : refus `rate_limited`, compteur d'abus.
2. **Schéma** : types exacts, entiers dans leurs bornes, chaînes de longueur maximale et au format attendu (`uid` : préfixe et caractères autorisés), booléens réels. Les tables non prévues sont refusées. Rien n'est converti « au mieux ».
3. **Joueur** : objet ESX chargé (`ESX.GetPlayerFromId`), joueur pas déjà occupé par une autre opération (§10).
4. **État** : la requête correspond à l'état actuel du défi ou du match, et le joueur y participe.
5. **Droits** : ACE (`IsPlayerAceAllowed`) pour les actions d'administration et d'organisation.
6. **Contexte** : distance (coordonnées du ped lues côté serveur), même routing bucket, pas dans un véhicule, en vie. Ces natives serveur sont déjà utilisées par d'autres ressources installées (`GetPlayerRoutingBucket` dans es_extended, `GetVehiclePedIsIn` et `GetEntityHealth` dans des scripts tiers) ; leur comportement exact sera vérifié dans la documentation Cfx avant usage.
7. **Action** dans le module concerné.
8. **Journal** : une ligne courte et utile ; jamais une ligne par image ou par keyframe.

## 5. Entrées du serveur

| Entrée | Vérifications propres (en plus du §4) |
|---|---|
| `spin_arena:challenge` | cible connectée, différente du joueur, à moins de 10 m, même bucket ; pas déjà en match ; au plus 1 défi sortant et 3 entrants ; toupie possédée et non verrouillée ; arène libre et à portée, ou zone libre autorisée |
| `spin_arena:respond` | défi existant, adressé à ce joueur, non expiré ; toupie possédée ; toutes les vérifications du défi refaites au verrouillage |
| `spin_arena:cancel` | défi émis par ce joueur, encore en attente |
| `spin_arena:forfeit` | joueur participant du match donné ; idempotent (un deuxième appel ne fait rien) |
| `spin_arena:spectate` | match existant, joueur dans le rayon d'observation et le même bucket, plafond de spectateurs |
| `spin_arena:workshop` | action dans une liste fermée ; toupie possédée, non verrouillée ; pièce possédée avec ses métadonnées exactes ; compatibilité et budget calculés par `shared/stats.lua` |
| Commandes d'administration | ACE `spin_arena.admin` (ou `spin_arena.organizer` pour les tournois), arguments validés, action journalisée avec l'auteur |
| Callbacks NUI | traités par le client comme non fiables ; ils ne font que relayer une intention vers les callbacks serveur ci-dessus |

Aucune entrée n'accepte : statistiques, métadonnées d'objet, position de toupie, seed, vainqueur, score, montant, identifiant ESX d'un autre joueur.

## 6. Limites de fréquence et de charge

Valeurs de départ, à ajuster après tests :

| Action | Limite |
|---|---|
| défi | 1 toutes les 3 s, rafale de 2 ; 10 par minute |
| réponse, annulation, abandon | 2 par seconde |
| spectateur | 1 par seconde |
| atelier | 2 par seconde, et une seule opération à la fois par joueur |
| total par joueur | 10 requêtes par seconde ; au-delà, journalisation de l'abus et refus pendant 10 s |

Plafonds globaux configurables : matchs simultanés, manches en calcul, spectateurs par match, défis en attente. Au-delà, refus propre (`server_busy`), jamais de file infinie.

## 7. Toupies et unicité

- Chaque `spin_top` porte `metadata.uid`, généré côté serveur : par le hook `createItem` si l'objet est créé sans `uid` (`modules/items/server.lua:224–233` : le hook peut renvoyer de nouvelles métadonnées), sinon à l'enregistrement en base.
- La base fait foi sur la configuration. Les métadonnées affichées dans l'inventaire (libellé, image) sont décoratives.
- Un objet dupliqué par un bug externe garde le même `uid`. Les deux copies partagent la même ligne et le même verrou : elles ne peuvent pas jouer en même temps. Si le même `uid` est vu chez deux joueurs différents, le serveur le journalise pour un administrateur.
- Verrou SQL conditionnel (`... WHERE uid = ? AND locked_match IS NULL`, une ligne modifiée exactement) au début du match, levé dans tous les chemins de fin et au démarrage de la ressource.
- Hook `swapItems` (`modules/hooks/server.lua:89`) filtré sur `spin_top` : il refuse les actions `move`, `give`, `swap`, `stack` et les dépôts au sol (`toInventory = 'newdrop'`) d'une toupie verrouillée ou en cours d'atelier. Il lit un ensemble en mémoire : pas d'`await` dans un hook.
- Les retraits forcés (confiscation, vidage d'inventaire par un administrateur) peuvent contourner le hook. Le règlement du match ne dépend donc pas de la présence de l'objet à la fin : il s'appuie sur la ligne SQL.

## 8. Atelier : opérations entre inventaire et base

Une transaction commune à ox_inventory et SQL est impossible. On utilise un journal d'opérations (`spin_ops`) et des compensations.

Exemple : remplacer la pointe d'une toupie.

1. Contrôles : fréquence, toupie possédée et non verrouillée, pièce possédée (métadonnées exactes), compatibilité et budget, place pour l'ancienne pièce (`CanCarryItem`, `modules/inventory/server.lua:1406`). Verrou en mémoire sur le `uid` et sur le joueur.
2. `spin_ops` : insertion `pending` avec tout le détail.
3. `RemoveItem(src, 'spin_part', 1, { part = nouvelle }, nil, nil, true)` (`:1315`). Échec → opération `failed`, rien d'autre.
4. Transaction SQL : nouvelle pièce, statistiques recalculées, `version + 1` (condition sur l'ancienne version), opération `item_taken`.
5. Échec SQL → compensation : `AddItem` de la nouvelle pièce, opération `compensated`. Si la compensation échoue aussi → `review`.
6. Opération `returning` (mise à jour conditionnelle `WHERE status = 'item_taken'`), puis `AddItem` de l'ancienne pièce.
7. Succès → opération `done`, verrous mémoire levés. Échec certain (retour `false`) → opération `owed` : la pièce est due, jamais perdue sans trace.

Une pièce due suit le même cycle que les récompenses (§9) : `owed` → `returning` → `done`, et `review` si le cycle est interrompu. Elle n'est jamais rendue deux fois.

Chaque valeur de retour d'ox_inventory est vérifiée (`AddItem` et `RemoveItem` renvoient `success, response`). Une exception est traitée comme un échec dont l'effet est inconnu, donc `review`. Au démarrage, une opération restée `pending`, `item_taken` ou `returning` passe en `review` : on ne la rejoue pas automatiquement, car on ne sait pas si l'objet a déjà bougé. Seules les opérations `owed` (échec certain, rien versé) sont reprises automatiquement.

## 9. Argent et récompenses

**Ce que fait ESX 1.12.4** (`es_extended/server/classes/player.lua`) :

- `removeAccountMoney` (:358) **ne vérifie pas le solde**. Le test d'« underflow » compare `money − x > money`, ce qui est faux pour tout montant positif. Le compte peut donc devenir négatif. La fonction ne renvoie rien.
- `addAccountMoney` (:332) ne renvoie rien non plus. Un montant ≤ 0 ou non numérique lève une erreur.
- L'argent est en mémoire. ESX l'enregistre en base toutes les 10 minutes (`server/common.lua:27`) et à la déconnexion. Après un crash, les mouvements des dernières minutes peuvent disparaître. La sauvegarde immédiate (`Core.SavePlayer`, `server/functions.lua:201`) est interne à es_extended et n'est pas une API publique.

Conséquences :

- Avant tout débit, lire le solde (`getAccount(nom).money`), valider le montant (entier positif, plafonné), puis débiter, en `pcall`.
- On ne peut pas prouver qu'un versement ou un débit a survécu à un crash. Il n'y a donc pas de garantie « exactement une fois » entre SQL et ESX/ox_inventory.

**Récompenses, au plus une fois** :

1. La transaction SQL de fin de match crée les lignes `spin_rewards` en `pending`, avec la contrainte UNIQUE (match, identifiant, type). Un deuxième règlement du même match échoue sur cette contrainte.
2. Pour chaque ligne : `UPDATE ... SET status = 'granting' WHERE id = ? AND status = 'pending'`. On continue seulement si une ligne a été modifiée.
3. Versement (argent ESX ou `AddItem`), avec contrôle du retour quand il existe.
4. `status = 'granted'`.
5. Une ligne restée en `granting` (crash entre 2 et 4) passe en `review` au démarrage, pour décision d'un administrateur. Elle n'est **jamais** retentée automatiquement. On préfère une récompense en attente de revue à une récompense versée deux fois.
6. Joueur hors ligne : la ligne reste `pending` jusqu'à sa prochaine connexion (`esx:playerLoaded`).

Classement, statistiques et usure sont uniquement en SQL et écrits dans la même transaction que le résultat : ils sont atomiques.

**Mises** : désactivées par défaut (§11 du cahier). Les activer exigerait un séquestre (`débit → séquestre → paiement ou remboursement`) avec les mêmes états. Un séquestre `debited` trouvé après un crash ne peut pas être remboursé automatiquement : ESX peut ne pas avoir enregistré le débit, et le remboursement le doublerait. Il passe en revue. Cette limite est une raison de garder les mises désactivées tant qu'elle n'est pas résolue et testée.

**Plafonds** : récompenses journalières par joueur, gains réduits contre un même adversaire répété, aucune récompense pour un match plus court qu'une durée minimale ni pour une égalité ou un `no_contest`.

## 10. Courses et concurrence

- Un joueur ne peut avoir qu'une opération sensible en cours (défi en verrouillage, atelier, règlement). Les autres demandes reçoivent `busy`.
- Après chaque `await` (SQL, inventaire), l'état est revérifié avant d'agir : le joueur a pu partir, le match a pu être annulé, l'objet a pu bouger.
- Les mises à jour SQL sensibles sont conditionnelles (`WHERE status = ...`, `WHERE version = ...`) et l'on vérifie le nombre de lignes modifiées.
- Deux acceptations simultanées du même défi : la première fait passer le défi en `locking`, la seconde voit un état différent et échoue.

## 11. Déconnexion, crash, reprise

- Politique de jeu : [ARCHITECTURE.md](ARCHITECTURE.md) §11. Une déconnexion ne relance pas une manche et ne rapporte rien à celui qui part.
- `playerDropped` / `esx:playerDropped` / `esx:playerLogout` : abandon ou annulation selon l'état, retrait de l'audience, verrous mémoire levés, défis annulés.
- `onResourceStop` : chaque client nettoie ses objets locaux ; le serveur marque les matchs actifs `cancelled` s'il en a le temps.
- Démarrage : reprise décrite dans [ARCHITECTURE.md](ARCHITECTURE.md) §13. Rien n'est versé deux fois ; ce qui est ambigu part en revue.

## 12. NUI

- Tout texte venant d'un joueur (nom, nom de toupie) est inséré avec `textContent`, jamais `innerHTML`. Les noms de toupie sont bornés en longueur et filtrés côté serveur.
- Les callbacks NUI ne font que relayer une intention. Le client ne garde aucune vérité (ni argent, ni statistiques).
- Le focus NUI est libéré dans tous les chemins de fermeture (fin de match, mort, arrêt de la ressource).
- Pas de ressources chargées depuis Internet dans la NUI. Polices, images et scripts sont livrés avec la ressource et inscrits au registre des assets.

## 13. Fuite d'information

- La seed et le résultat d'une manche ne sont jamais envoyés avant la fin de la manche.
- L'avance de diffusion laisse une fenêtre d'anticipation limitée ([PHYSICS.md](PHYSICS.md) §15). Son intérêt est réduit : pas de mises pendant une manche, pas de relance, et un départ coûte un abandon. Risque résiduel : un joueur ou un spectateur peut annoncer une fin quelques dixièmes de seconde à l'avance, par exemple à un complice. C'est sans effet sur le résultat ni sur les récompenses, mais cela gênerait des paris extérieurs au jeu.
- Un client ne reçoit les tranches que s'il fait partie de l'audience d'un match.
- Les identifiants ESX ne sont jamais envoyés aux autres clients : uniquement des noms d'affichage.

## 14. Abus de jeu

- **Farming par entente** : gains réduits contre un même adversaire, plafonds journaliers, durée minimale de match, rien pour les abandons rapides. Journal des paires de joueurs suspectes pour les administrateurs. Les comptes multiples ne peuvent pas être empêchés techniquement : on limite l'intérêt.
- **Harcèlement par défis** : limites du §6, refus automatique si le joueur est déjà sollicité, option pour ignorer les défis.
- **Occupation d'une arène** : échéances à chaque état, un match par arène, un match par joueur.
- **Téléportation** : la position du ped vient du client par la synchronisation OneSync. Un tricheur peut la fausser. Les contrôles de distance empêchent les abus ordinaires mais ne sont pas une frontière de sécurité. C'est une raison supplémentaire de garder les mises désactivées.
- **Mort provoquée par un tiers** : avec la règle « abandon », un complice peut faire perdre un participant. Journalisé ; règle modifiable ([ARCHITECTURE.md](ARCHITECTURE.md) §11).

## 15. Administration, journaux, transparence

- Droits par ACE uniquement, déclarés dans le README avec leur effet. Aucun identifiant codé en dur.
- Toute action d'administration (annuler un match, régler une récompense en revue, réinitialiser un classement) est journalisée avec l'auteur.
- Journaux à niveaux (`error`, `warn`, `info`, `debug`), limités en fréquence par motif. Pas de ligne par image ou par keyframe.
- Le code reste lisible : pas d'obfuscation, pas de `load` ou `loadstring` sur des données reçues, pas de `PerformHttpRequest` sauf le webhook facultatif, vide par défaut et déclaré dans la configuration. Ces règles se vérifient en revue avant chaque livraison.

## 16. Tests de sécurité

À intégrer à [TEST_PLAN.md](TEST_PLAN.md), sur la phase indiquée :

| Phase | Test | Attendu |
|---|---|---|
| 2 | appeler chaque callback avec types faux, chaînes trop longues, tables imbriquées, nombres non finis | refus, aucun effet, aucun crash |
| 2 | envoyer un vainqueur, une seed ou des statistiques dans une requête | ignoré : champ refusé par le schéma |
| 2 | 100 défis par seconde | limite appliquée, serveur stable |
| 2 | deux acceptations simultanées du même défi | un seul match |
| 2 | déconnexion à chaque état du match | un seul état terminal, conforme à [ARCHITECTURE.md](ARCHITECTURE.md) §11 |
| 2 | abandon appelé deux fois | un seul effet |
| 4 | donner, déplacer, jeter ou empiler une toupie verrouillée | refus par le hook |
| 4 | même `uid` dans deux inventaires, deux matchs en même temps | un seul verrou réussi, journal d'alerte |
| 4 | atelier avec pièce absente, mauvaises métadonnées, inventaire plein, SQL en panne à chaque étape | aucun objet créé ni perdu sans trace ; `compensated`, `owed` ou `review` |
| 4 | crash simulé entre chaque étape de l'atelier | reprise en `review`, pas de rejouage |
| 6 | règlement du même match deux fois | refusé par la contrainte UNIQUE |
| 6 | crash entre `granting` et `granted` | `review`, pas de second versement |
| 6 | récompense pour un joueur hors ligne | versée une fois à la connexion |
| 6 | débit avec solde insuffisant (si les mises sont activées un jour) | refusé avant appel à ESX |
| 5 | spectateur hors rayon ou dans un autre bucket | aucune tranche reçue |
| 3–5 | texte de joueur contenant du HTML dans la NUI | affiché comme texte |

## 17. Risques résiduels

- Pas de garantie « exactement une fois » pour l'argent et les objets : au plus une fois, avec revue administrateur.
- Positions et distances reposent sur des données de synchronisation qu'un tricheur peut fausser.
- Comptes multiples et ententes : limités, pas empêchés.
- Opérations d'inventaire faites par d'autres ressources (confiscation, vidage) hors de notre contrôle.
- Le comportement exact des natives serveur citées et des versions futures d'ESX/ox reste à confirmer à chaque mise à jour.
