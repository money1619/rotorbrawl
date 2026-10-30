# PROJET SPIN ARENA — DÉVELOPPEMENT PROFESSIONNEL FIVEM

## 1. TON RÔLE

Tu es un développeur senior spécialisé dans FiveM, GTA V, Lua, ESX Legacy, ox_inventory, oxmysql, OneSync, NUI (HTML/CSS/JavaScript), synchronisation réseau, optimisation et sécurité des ressources multijoueurs.

Tu travailles comme un véritable ingénieur logiciel : tu analyses avant de coder, tu vérifies les API, tu construis des modules indépendants, tu testes les fonctionnalités et tu documentes les résultats.

Tu dois développer un projet commercialisable, maintenable, sécurisé et compatible avec un serveur FiveM RP.

Ne te contente pas de proposer du code ou un plan. Tu dois travailler directement dans le dépôt du projet, lorsque les outils et permissions disponibles le permettent.

## 2. OBJECTIF DU PROJET

Créer SPIN ARENA, un système original de combats de toupies mécaniques pour FiveM.

Le projet s'inspire uniquement du concept général des combats de toupies. Il doit posséder sa propre identité artistique, ses propres modèles, ses propres noms et ses propres effets.

Le système doit permettre aux joueurs de :

- Posséder des toupies et des lanceurs.
- Personnaliser leurs toupies avec des pièces stratégiques et cosmétiques.
- Défier d'autres joueurs.
- Lancer des combats automatiques basés sur une simulation physique contrôlée.
- Combattre dans des arènes fixes et dans des zones autorisées du monde ouvert.
- Gagner des récompenses et progresser.
- Participer à des tournois et consulter des classements.
- Observer les combats d'autres joueurs.

## 3. CONTRAINTES TECHNIQUES

Environnement cible :

- FiveM avec les versions de serveur et artefacts compatibles avec les API retenues.
- ESX Legacy.
- ox_inventory.
- oxmysql.
- Lua pour les scripts client et serveur.
- NUI en HTML, CSS et JavaScript pour les interfaces.
- Modèles 3D et textures personnalisés, avec les formats compatibles avec GTA V/FiveM.

Avant toute implémentation, inspecte le dépôt existant et identifie les versions et dépendances réellement disponibles.

N'invente jamais un export, un événement, une native GTA, une fonction ou une API. Consulte la documentation appropriée et vérifie la compatibilité.

Ne remplace pas une dépendance existante et ne réécris pas une architecture déjà fonctionnelle sans raison technique documentée.

## 4. PROPRIÉTÉ INTELLECTUELLE — RÈGLE ABSOLUE

SPIN ARENA doit être une création originale.

Interdictions :

- Ne pas utiliser la marque BEYBLADE comme nom du produit.
- Ne pas copier les modèles, logos, personnages, illustrations, musiques, sons, animations ou designs distinctifs d'une franchise existante.
- Ne pas extraire des ressources protégées d'un jeu ou d'un produit commercial.
- Ne pas reproduire à l'identique des modèles à partir de captures d'écran ou de photographies.
- Ne pas supposer qu'une ressource gratuite peut être redistribuée commercialement.

Créer une identité industrielle futuriste originale : métal usiné, titane, mécanismes visibles, noyaux lumineux discrets et pièces mécaniques interchangeables.

Toutes les ressources externes doivent disposer d'une licence compatible avec leur utilisation et leur éventuelle redistribution commerciale. Documente les auteurs, les licences et les autorisations.

Le nom SPIN ARENA est provisoire jusqu'à vérification de sa disponibilité juridique.

## 5. GAMEPLAY

### 5.1 Lancement

Le joueur équipe son lanceur et sélectionne sa toupie.

Le système valide le matériel et les participants, puis exécute une animation de préparation et un compte à rebours synchronisé.

Les toupies sont lancées simultanément.

Les animations ne doivent pas donner d'avantage caché.

### 5.2 Combat automatique

Le joueur ne dirige pas sa toupie pendant la manche.

Les trajectoires et les collisions dépendent des caractéristiques de la toupie et de la simulation physique.

Prévoir :

- Position et vitesse horizontales.
- Angle et vitesse de rotation.
- Énergie de rotation restante.
- Masse simulée.
- Puissance d'impact.
- Stabilité.
- Friction et mobilité.
- Collisions et impulsions.
- Limites d'arène et éjections.
- Conditions d'arrêt et durée maximale.

Ne cherche pas à simuler parfaitement toutes les lois physiques. Construis une simulation simplifiée, cohérente, stable et adaptée à FiveM.

Le résultat doit être déterminé par le serveur. Les clients ne peuvent pas imposer le vainqueur.

### 5.3 Conditions de victoire

Prévoir au minimum :

- Éjection hors de l'arène.
- Arrêt de rotation confirmé pendant une durée configurable.
- Fin du temps avec départage défini.
- Égalité lorsque les règles le permettent.
- Interruption et abandon.
- Déconnexion d'un participant.

Empêche les matchs bloqués et les doubles récompenses.

### 5.4 Familles de toupies

Prévoir plusieurs archétypes :

- Attaque.
- Défense.
- Équilibre.
- Endurance.
- Mobilité.

Les caractéristiques doivent présenter des compromis. Aucune configuration ne doit être automatiquement supérieure dans toutes les situations.

Sépare les caractéristiques de combat des effets cosmétiques.

## 6. ARCHITECTURE TECHNIQUE

Organise la ressource en modules indépendants.

Structure cible indicative :

spin_arena/
- fxmanifest.lua
- config/
- shared/
- client/main.lua
- client/duel.lua
- client/renderer.lua
- client/effects.lua
- client/launcher.lua
- client/arena.lua
- client/nui.lua
- client/preview.lua
- server/main.lua
- server/matches.lua
- server/challenges.lua
- server/physics/engine.lua
- server/physics/collisions.lua
- server/physics/boundaries.lua
- server/arenas.lua
- server/parts.lua
- server/inventory.lua
- server/tournaments.lua
- server/ranking.lua
- server/security.lua
- server/database.lua
- web/
- locales/fr.lua
- locales/en.lua
- sql/install.sql
- stream/
- README.md
- PROJECT_STATUS.md
- CHANGELOG.md
- LICENSE

Adapte cette structure si une décision technique justifiée permet de simplifier le projet.

Ne crée pas des dizaines de fichiers vides. Chaque module doit avoir une responsabilité réelle et être intégré au système.

Définis clairement les interfaces entre modules et évite les dépendances circulaires.

## 7. PHYSIQUE ET SYNCHRONISATION

La simulation physique est le principal risque technique du projet.

Commence par un prototype minimal.

Privilégie une simulation mathématique contrôlée plutôt que la physique native non fiable de petits objets GTA.

Le serveur doit être l'autorité sur :

- L'état du match.
- Les paramètres initiaux du lancement.
- Les caractéristiques validées des toupies.
- Les collisions qui déterminent le résultat.
- Les conditions de victoire.
- Le gagnant et les récompenses.

Les clients doivent afficher les toupies, interpoler les positions reçues et gérer localement les effets visuels.

Utilise un pas de simulation fixe, des mises à jour réseau raisonnables et des mécanismes d'interpolation.

Ne transmets pas inutilement chaque position à chaque image.

Évalue les risques de divergence entre clients, de latence, de surcharge serveur et de désynchronisation.

Ne prétends pas que le moteur est déterministe ou synchronisé avant d'avoir réalisé des tests multijoueurs.

Si une fonctionnalité est trop coûteuse ou instable dans FiveM, explique la limitation et propose une solution simplifiée.

## 8. APPARENCE ET INTERFACE

Direction artistique : industrielle futuriste.

Palette de référence :
- Noir industriel.
- Gris graphite.
- Titane et acier brossé.
- Cyan électrique.
- Orange impact.

Les toupies doivent avoir des silhouettes originales, des matériaux crédibles et des pièces visuellement interchangeables.

Lanceurs et animations :
- Lanceur tenu par le personnage.
- Animation de préparation.
- Lancement synchronisé.
- Position d'observation après le lancement.

Interface compacte et professionnelle, jamais inutilement volumineuse.

Menus principaux :
- Ma toupie.
- Défis.
- Arènes.
- Tournois.
- Classement.

HUD de combat :
- Identité des participants.
- Énergie de rotation.
- Manche et chronomètre.
- Événements importants.
- Résultat final.

Les effets visuels comprennent les étincelles, les impacts, les traînées et des ralentis purement visuels lorsque c'est réalisable.

N'invente pas des fichiers 3D qui n'existent pas. Si des modèles sont nécessaires, documente leurs spécifications et les outils requis pour les produire et les intégrer.

## 9. INVENTAIRE ET PERSONNALISATION

Intègre le projet à ESX Legacy, ox_inventory et oxmysql.

Objets envisagés :
- spin_top
- spin_launcher
- spin_part
- spin_repair_kit

Vérifie les formats de définition des objets compatibles avec la version installée d'ox_inventory.

Chaque toupie doit posséder un identifiant unique.

Le serveur doit vérifier :
- Le propriétaire.
- Les pièces réellement possédées.
- La compatibilité des composants.
- Les statistiques calculées.
- Les transactions d'assemblage.
- Les changements de configuration.
- Les récompenses et transferts.

Ne considère jamais les métadonnées envoyées par le client comme une source fiable.

Prévoyez les migrations SQL, les index, les transactions nécessaires et la gestion des erreurs de persistance.

## 10. ARÈNES ET MONDE OUVERT

Le système doit prendre en charge :

1. Des arènes fixes configurées par l'administrateur.
2. Des combats improvisés dans des zones approuvées.
3. Des spectateurs.
4. Des limites spatiales.
5. Une capacité maximale.
6. Des interdictions dans certaines zones.
7. Le nettoyage des entités et des états à la fin du combat.

Refuse un combat si les participants sont dans une situation incompatible avec les règles.

Empêche le chevauchement de matchs et l'utilisation d'une arène déjà occupée.

Ne crée pas de mécanisme physique complexe dans la première version.

## 11. TOURNOIS ET PROGRESSION

À développer après la validation des duels :

- Classement général.
- Statistiques par joueur.
- Historique des matchs.
- Classements saisonniers.
- Tournois publics et privés.
- Inscriptions.
- Tableau à élimination directe.
- Gestion des abandons.
- Récompenses configurables.
- Permissions d'organisateur.

Toute récompense doit être validée et accordée côté serveur, une seule fois.

Les mises monétaires sont optionnelles et désactivées par défaut jusqu'à validation des mécanismes de débit, de remboursement et de prévention des abus.

## 12. SÉCURITÉ ET PERFORMANCE

Traite tous les événements réseau et toutes les entrées NUI comme non fiables.

Vérifie côté serveur les permissions, distances, états de match, objets, configurations et transactions.

Prévois :
- Limitation de fréquence des événements.
- Protection contre les requêtes répétées.
- Prévention des récompenses dupliquées.
- Nettoyage après déconnexion.
- Libération des entités et ressources temporaires.
- Gestion des erreurs SQL.
- Journalisation utile sans spam.
- Contrôles de charge et tests multijoueurs.

Évite les boucles intensives et les créations d'entités inutiles.

N'ajoute pas d'obfuscation ou de mécanisme caché.

## 13. MÉTHODE DE TRAVAIL OBLIGATOIRE

Travaille en phases avec des critères d'acceptation.

### Phase 0 — Audit et conception

Inspecte le dépôt et les dépendances.

Produis :
- Une analyse de l'existant.
- Les dépendances et leurs versions.
- L'architecture retenue.
- Les risques techniques.
- Les critères de réussite.
- Le plan de tests.
- Les ressources externes nécessaires.

Ne commence pas immédiatement le développement complet.

### Phase 1 — Prototype physique

Implémente uniquement :
- Deux toupies de test.
- Une arène simple.
- Rotation et mouvement.
- Friction et collisions.
- Arrêt et éjection.
- Conditions de victoire minimales.

Utilise des formes temporaires si aucun modèle final n'est disponible.

Teste les calculs automatiquement lorsque possible, puis dans un vrai serveur FiveM.

### Phase 2 — Multijoueur

Ajoute les défis, le lancement synchronisé, l'état des matchs, les snapshots et les résultats autoritaires.

Teste au minimum avec deux clients.

### Phase 3 — Rendu et animations

Intègre les modèles et les animations réellement disponibles.

Teste le comportement sur plusieurs clients et à différentes latences.

### Phase 4 — Inventaire et atelier

Ajoute les pièces, les configurations, les objets et la persistance.

### Phase 5 — Arènes et spectateurs

Ajoute les zones fixes, les zones libres autorisées et le nettoyage.

### Phase 6 — Progression et tournois

Ajoute les classements, les récompenses et les compétitions.

### Phase 7 — Audit final

Réalise les tests de régression, de sécurité, de performance, de reconnexion et d'installation.

Ne passe à la phase suivante que lorsque les critères essentiels de la phase actuelle sont validés.

## 14. TESTS ET TRANSPARENCE

Pour chaque fonctionnalité, distingue clairement :

- Implémentée.
- Testée automatiquement.
- Testée dans FiveM.
- Testée en multijoueur.
- Validée.
- Non testée.
- Bloquée par une dépendance externe.

Ne dis jamais « tout fonctionne » sans preuves.

N'invente jamais des résultats de tests, des journaux de serveur ou des modèles 3D.

Si tu ne peux pas démarrer FiveM ou tester une fonctionnalité dans le jeu, indique-le explicitement et fournis une procédure de test reproductible.

Corrige les erreurs avant d'ajouter de nouvelles fonctionnalités.

Ne masque pas les défauts par des valeurs fictives ou des implémentations temporaires présentées comme définitives.

## 15. SUIVI DU PROJET

Maintiens les fichiers suivants :

PROJECT_STATUS.md
- Phase actuelle.
- Fonctionnalités terminées.
- Fonctionnalités testées.
- Tests réussis et échoués.
- Problèmes connus.
- Prochaines tâches.

README.md
- Installation.
- Dépendances.
- Configuration.
- Objets d'inventaire.
- Base de données.
- Commandes et permissions.
- Procédures de dépannage.

CHANGELOG.md
- Changements importants par version.

Conserve également une liste des ressources artistiques et de leurs licences.

## 16. PREMIÈRE ACTION

Commence maintenant par la PHASE 0 uniquement.

Inspecte le dépôt existant et les outils disponibles. Si le dépôt est vide, indique-le et prépare la structure minimale de conception.

Ne génère pas immédiatement le script complet.

Présente-moi :
1. L'état réel du projet.
2. Les dépendances détectées.
3. L'architecture proposée.
4. Les principaux risques de FiveM.
5. Les fichiers à créer en premier.
6. Les tests nécessaires pour valider la physique.
7. Les limitations et les ressources externes requises.

Attends ma validation de la conception avant de commencer le prototype physique.

Priorité absolue : un jeu réellement fonctionnel, original, testable, sécurisé et adapté aux capacités de FiveM.
