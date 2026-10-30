# Revue intégrée Arena — 18 octobre 2026

Référence observée : `11562a5`. Quinze suites lancées depuis la ressource, avec au plus trois processus de test simultanés. Les empreintes des sources restent identiques avant et après cette campagne.

Preuves : [commandes, codes retour et empreintes](evidence/integrated-review-20261018/checks.json). Les journaux individuels portent le nom des scripts dans le même dossier. Il s'agit de Lua local et d'émulation avec dépendances simulées, sans client GTA ni base SQL réelle.

| Suite | Résultat |
|---|---|
| run | 112/112 |
| server_unit_test | 66/66 |
| duel_test | 48/48 |
| ranking_test | 23/23 |
| tournaments_test | 36/36 |
| complete_top_test | 10/10 |
| parts_combinations_test | 320 combinaisons parcourues, 168 admises et 152 refusées selon le budget ; six compromis et cinq kits vérifiés |
| phase4_smoke | 22/22 |
| review_phase2 | 12/12 |
| review_phase4 | 10/10 |
| review_shop | 10/10 |
| emulator | 37/37 |
| target_test | 23 réussites, 16 échecs |
| phase3_4_client_test | 15 réussites, 12 échecs |
| review_client_loading | 0 réussite, 2 échecs |

Les suites se recouvrent : les compteurs ne constituent pas un total de scénarios indépendants.

Les deux suites client historiques doivent adapter les scénarios utilisant les profils gratuits à la nouvelle règle, via des toupies possédées ou une autorisation explicite limitée aux fixtures. La configuration publique doit rester restrictive. Les échecs de ces suites ne sont donc pas tous des défauts de production. Le test de chargement retardé reproduit séparément l'absence de reprise de préparation du lanceur lorsque les ressources arrivent après la première demande. Fermi a reçu les journaux et conserve la responsabilité des fichiers client.

L'accès client à la boutique n'est pas présent dans le `client/main.lua` observé pour cette campagne ; la livraison serveur et les tests d'achat émulé ne prouvent pas que le joueur peut ouvrir le magasin dans GTA.

La règle toupie complète, les corrections d'atelier, les achats émulés et les tournois passent leurs suites actuelles. Les essais SQL réels, l'achat dans GTA, le rendu et la campagne complète à deux clients restent nécessaires. Aucune phase n'est déclarée validée en jeu par ce rapport.
