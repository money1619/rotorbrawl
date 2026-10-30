# Phase 4 — plan de qualification SQL, inventaire et atelier

Préparé le 18 octobre 2026. **Plan uniquement : aucun résultat de phase 4 annoncé.** Les interfaces et migrations sont en cours de livraison par Archimedes. Les noms de méthodes seront repris du code livré, sans inventer d'export.

## Niveaux de preuve

1. Tests Lua : calcul des caractéristiques et validation des entrées avec modules réels.
2. Émulation : callbacks réels et dépendances simulées, ordonnanceur contrôlé, injections de pannes. Un mock SQL ne prouve ni les transactions ni les contraintes d'un vrai moteur SQL.
3. Intégration : base et inventaire dédiés aux essais, versions relevées, migration réelle et contrôle SQL après chaque opération.
4. Clients GTA : deux personnages, interactions ox_target, inventaires visibles et reconnexions. Les effets visuels et animations nécessitent une observation dans le jeu.

À chaque exécution conserver : commit et empreintes des fichiers, versions des dépendances, commande, code de retour, compteurs, erreurs, état avant/après et niveau de preuve. Ne pas stocker d'identifiants de connexion ni de données de joueurs réels.

## Invariants de sécurité

- Le propriétaire vient de l'identité serveur du personnage ; un numéro de session réutilisé ne confère aucune propriété.
- L'UID identifie une seule toupie persistante ; copier une métadonnée ne crée pas un droit de propriété.
- Pièces, compatibilité et caractéristiques sont recalculées côté serveur. Le client ne fournit jamais les statistiques faisant autorité.
- Une opération validée consomme exactement les pièces prévues et produit exactement son résultat. Un refus ne modifie rien.
- Les demandes concurrentes, doublons et reprises après erreur ne dupliquent aucun objet.
- Un échec entre inventaire et SQL doit avoir une issue définie : compensation vérifiée ou état de récupération durable et observable. Deux systèmes ne deviennent pas atomiques par une simple transaction SQL.
- Une configuration utilisée par un match ne peut pas être modifiée en cours de manche ; le snapshot de combat reste immuable.

## Matrice des cas à implémenter

| ID | Scénario | Vérification attendue |
|---|---|---|
| P4-01 | Installation sur base vide puis seconde exécution | Tables et index présents ; données inchangées lors de la reprise selon la procédure de migration documentée. |
| P4-02 | UID déjà présent, propriétaire absent, référence invalide | Contraintes ou validation serveur refusent l'écriture ; aucune toupie supplémentaire. |
| P4-03 | Joueur sans lanceur, sans toupie ou sans pièce | Refus explicite sans inscription au match ni consommation. |
| P4-04 | Toupie appartenant à un autre personnage ; métadonnées copiées | Refus malgré l'UID présenté ; aucune fuite de configuration privée. |
| P4-05 | Assemblage compatible avec toutes les pièces possédées | Une seule configuration enregistrée ; pièces réellement consommées selon le contrat livré. |
| P4-06 | Pièce inconnue, incompatible, quantité négative, fractionnaire, NaN, infinie, charge trop grande | Refus borné en temps ; aucun état persistant modifié. |
| P4-07 | Statistiques, propriétaire, UID de sortie ou récompense forgés | Champs non autoritaires ignorés ou demande rejetée ; résultat recalculé par le serveur. |
| P4-08 | Toutes les combinaisons du catalogue | Valeurs finies, limites respectées, compromis conservés ; cosmétiques sans effet de combat. |
| P4-09 | Deux assemblages simultanés du même objet | Au plus un succès sur la même version ; aucun double débit ni écrasement silencieux. |
| P4-10 | Deux joueurs demandent la même toupie ou la même pièce | Isolation des propriétaires et exclusion mutuelle vérifiées. |
| P4-11 | Rejeu d'une demande réussie ; réponse réseau perdue | Résultat récupérable ou refus sûr ; aucun second débit ou objet. |
| P4-12 | Échec SQL avant/après chaque écriture ; exception et timeout | Pas de succès annoncé sans persistance ; verrous libérés ou récupération durable explicitement signalée. |
| P4-13 | Retrait inventaire refusé ; ajout refusé car plein ou trop lourd | Pas de perte silencieuse ; compensation ou récupération vérifiée sur chaque frontière. |
| P4-14 | Déconnexion, changement de personnage ou réutilisation du source pendant une attente SQL | Aucune réponse ni attribution au nouveau personnage ; opération terminée ou récupérable. |
| P4-15 | Arrêt de ressource à chaque frontière inventaire/SQL puis reprise | Aucun verrou temporaire immortel ; opérations incomplètes détectées et réconciliées. |
| P4-16 | Atelier pendant défi, compte à rebours et match | Politique explicite ; aucun changement des paramètres déjà validés pour le match. |
| P4-17 | ESX, oxmysql ou ox_inventory absent/arrêté/rechargé | Fonctionnalité indisponible explicitement ; aucun remplacement silencieux par une toupie gratuite en production. |
| P4-18 | Spam, requête mal formée, identifiant inexistant | Limitation de fréquence et validation avant les opérations coûteuses ; pas de journalisation excessive. |
| P4-19 | Reconnexion et redémarrage sur jeu de données de test | Propriété et configuration identiques à l'état durable ; aucun objet supplémentaire. |
| P4-20 | Régression du duel après activation de l'inventaire | Statistiques chargées côté serveur, inscriptions exclusives, fin et nettoyage conservés. |

Pour P4-09/10/14, suspendre explicitement le mock juste avant l'écriture ou le retrait puis entrelacer les callbacks. Des appels simplement séquentiels ne prouvent pas l'absence de course.

## Préparation des doubles de dépendances

Le fichier embarqué `tests/vendor/fivem_emu.lua` expose actuellement un mécanisme de fausses ressources. La présence de mocks complets ESX/oxmysql/ox_inventory n'est pas encore constatée dans cette copie. Vérifier la livraison avant de les utiliser.

Les doubles doivent enregistrer les opérations, prendre des instantanés indépendants des inventaires et de la base, gérer les erreurs et suspensions demandées et reproduire les retours réellement utilisés par l'adaptateur. Les assertions comparent les soldes et objets avant/après ; elles ne se limitent pas au champ `ok` d'un callback. Les scénarios de compensation imposent également un échec de la compensation.

## Critères d'acceptation et limites

Tous les refus de sécurité et cas de duplication doivent passer. Les pannes partielles doivent avoir un comportement documenté, reproductible et sans perte silencieuse. Les transactions et migrations restent non validées jusqu'à exécution sur le moteur SQL cible. L'inventaire réel et les interactions restent non validés jusqu'aux essais sur l'instance dédiée.

Le retour utilisateur « ça fonctionne », relayé par Archimedes, indique un essai en jeu du prototype. Il ne renseigne pas à lui seul les huit scénarios du duel, les migrations SQL ou l'atelier.

Inventaire et atelier ne seront déclarés prêts qu'avec preuves associées aux fichiers effectivement livrés. Récompenses, économie, progression et tournois ne font pas partie de ce lot de tests.
