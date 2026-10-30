# Revue indépendante phase 4 — 18 octobre 2026

## Contre-vérification après corrections

Boutique, passage après correctifs : **10/10 réussites** dans `review_shop.lua` et **21/21** dans `phase4_smoke.lua`. Le test sans base recherche désormais l'article par son nom, puisque le lanceur devient légitimement le premier article lorsque les toupies ne sont plus proposées. Un cas supplémentaire vérifie le refus d'une toupie depuis un ancien catalogue après passage de la base en état indisponible. Les quatre défauts de boutique décrits dans les relevés précédents sont couverts et passent. [Preuves et empreintes](evidence/shop-review-corrected-20261018/checks.json), [boutique](evidence/shop-review-corrected-20261018/review_shop.log), [parcours complet émulé](evidence/shop-review-corrected-20261018/phase4_smoke.log). Les achats natifs et l'accès ox_target restent à contrôler dans le jeu.

Dernier passage : **10/10 réussites** dans `review_phase4.lua`, après acquisition du verrou avant la première attente et contrôle par jeton. Les doubles ont été alignés sur le contrat vérifié de `Inventory.lock/unlock`. Les trois extensions ci-dessous passent désormais. [Résultats actuels](evidence/review-followup-20261018/review_phase4.log), [empreintes et commandes](evidence/review-followup-20261018/checks.json). Accord transmis à Archimedes pour intégrer ces corrections ; il ne constitue pas une validation SQL réelle, ni un essai de récupération opérateur des états `review/owed`.

La boutique fait l'objet d'une suite distincte `tests/review_shop.lua` : **5 réussites, 4 échecs** sur ce relevé. Catalogue, identifiants distincts, paiement et refus argent/capacité/distance passent dans les mocks. Restent l'état disponible annoncé à tort sans lieu, l'ancien shop restant utilisable après suppression des lieux, la désactivation par configuration inefficace pour ce shop déjà enregistré et l'achat sans UID si SQL est absent et les hooks non initialisés. [Résultats boutique](evidence/review-followup-20261018/review_shop.log). Ces cas sont transmis à Archimedes.

Les paragraphes suivants conservent la chronologie des passages précédents.

Les sept contrôles initiaux passent après correction. Le double de conflit certain a été aligné sur le contrat réel de `database.lua` : `false` sans erreur pour zéro ligne modifiée ; `false, err` désigne une issue incertaine. Le test générique `phase4_smoke.lua` passe indépendamment à **17/17**.

Trois extensions échouent encore : **7 réussites, 3 échecs** dans `review_phase4.lua`. [Résultats](evidence/phase4-fault-review-20261018/review_phase4-followup.log), [empreintes et codes retour](evidence/phase4-fault-review-20261018/followup-checks.json).

- Un changement d'identité durant le premier `getTop` précède la capture de l'identité dans `journaled` : l'opération continue avec la possession vérifiée pour l'ancien personnage.
- Un changement d'identité durant `setParts` retournant un conflit certain permet le remboursement au nouveau personnage ; la branche de compensation ne revérifie pas l'identité.
- Un verrou concurrent apparu durant le premier `getTop` est écrasé par `journaled`, puis supprimé à sa sortie.

Recommandation transmise : capturer l'identité et réserver la toupie avant la première attente, revérifier l'identité avant chaque mouvement, y compris la compensation, et ne libérer que le verrou détenu par l'opération. La revue reste ouverte. Les sections suivantes conservent les constats historiques du premier passage.

État au premier passage : **2 contrôles réussis, 5 échoués**. Qualification de l'atelier bloquée sur ces scénarios. Aucun essai SQL réel ou client GTA dans cette revue.

Commande : `lua5.4 tests/review_phase4.lua`. Le test charge les vrais modules `server/parts.lua`, `shared/stats.lua` et `config/parts.lua`, avec des doubles explicites de base et d'inventaire. Les retours de panne sont injectés directement à la frontière de ces dépendances. Ces tests ne remplacent pas les essais avec les mocks génériques ni avec MariaDB/ox_inventory.

Preuves du premier passage : [résultats](evidence/phase4-fault-review-20261018/faults.log), [commit, empreintes avant/après et code retour](evidence/phase4-fault-review-20261018/checks.json). Les six fichiers observés sont stables pendant cette exécution. Les résultats ne sont pas additionnés aux suites précédentes.

## Défauts reproduits

| Priorité | Cas | Observation | Correction attendue |
|---|---|---|---|
| Haute | Écriture réussie mais résultat SQL incertain | Le double applique `setParts`, puis retourne `false, db_timeout`. L'atelier rembourse la pièce alors que la configuration a changé. | Distinguer conflit certain et issue inconnue. Conserver une opération récupérable et réconcilier l'écriture avant de décider d'un remboursement. Le timeout local n'annule pas l'écriture distante. |
| Haute | Transition du journal refusée | `opMove` retourne faux ; l'atelier poursuit la mutation et annonce un succès sans transition durable vers `item_taken`. | Vérifier chaque transition, arrêter aux frontières incertaines et préserver un état de récupération. |
| Haute | Changement d'identité pendant une attente | `opStart` simule une attente durant laquelle le source représente désormais Bob. L'opération d'Alice continue à retirer la pièce du source. | Capturer une identité de session/personnage et la vérifier après chaque attente, avant tout effet sur l'inventaire. Une vérification unique au début ne suffit pas. |
| Haute | Réparation et compensation refusées | `setField` échoue et `giveRepair` refuse le retour ; le kit a disparu et aucun journal d'opération n'existe. | Journaliser aussi la réparation et sa compensation, avec dette récupérable attachée à l'identité stable. |
| Moyenne | Exception d'export inventaire | `takePart` lève une exception ; le verrou `workshop` reste posé. | Encadrer l'opération et garantir la libération, tout en conservant l'état durable nécessaire à la récupération. |

Les contrôles positifs vérifient l'échange normal des deux pièces et la compensation d'un refus certain d'écriture. Les assertions portent sur les pièces, la configuration, les opérations et les verrous, pas uniquement sur un retour `ok`.

## Suite de qualification

Archimedes a reçu les cinq reproductions. Ne pas modifier ces assertions pour accepter les pertes ou les opérations ambiguës. Adapter les doubles à toute interface de récupération ajoutée, puis vérifier effectivement les états et les soldes après reprise. Étendre ensuite aux frontières de déconnexion, aux écritures tardives, à la concurrence, aux migrations réelles et aux essais dans GTA selon [le plan phase 4](TESTS_PHASE4.md).

Les scènes ox_target disposent séparément d'une exécution indépendante de 39 contrôles réussis et les régressions phase 2 de 12 réussites. Un défaut supplémentaire de cache client après réponse `rate_limited` a été reproduit et transmis à Fermi ; il ne concerne pas la persistance SQL de ce rapport.
