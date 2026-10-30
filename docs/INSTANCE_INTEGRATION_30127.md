# Instance Arena avec dépendances réelles

Créée le 18 octobre 2026 : `/home/fivem2/FXServer/txData/SpinArenaIntegration`, port TCP/UDP **30127**, non publiée dans la liste. Le serveur RP 30121 et la sonde de map 30126 restent séparés.

## Composition

- FXServer Linux artefact 35265, OneSync activé.
- ESX Legacy 1.12.4, cron, ox_lib 3.32.3, ox_target 1.18.0, ox_inventory 2.45.0, oxmysql 2.12.0.
- Schéma `spin_arena_integration`, nouvellement créé, sans copie des joueurs ni des inventaires RP.
- Schémas ESX de base, identité, licences et véhicules issus des fichiers SQL installés. Tables d'inventaire et d'Arena initialisées sur cette base seulement.
- Copie propre des ressources ; quatre objets Arena ajoutés uniquement à l'inventaire de cette instance. Paramètres de connexion dans `server.cfg`, permissions de fichier 0600, jamais copiés dans les preuves.
- Provider de spawn/apparence installé sur l'hôte (`fivem-appearance`, MIT), colonne ESX `users.skin`, et 15 000 unités d'argent liquide pour les nouveaux comptes de test seulement. Ces réglages ne changent pas l'économie du serveur RP. Le build GTA de cette instance est fixé à 2699.

Le premier lancement a révélé deux problèmes de préparation : les exemples mapmanager/basic-gamemode étaient incompatibles avec ESX et les tables licences/véhicules manquaient. La configuration isolée a été corrigée et ce lancement historique est conservé dans `integration-initial.log`. Le serveur RP n'a pas été redémarré.

## Contrôles effectués

`tests/sql_integration_test.py` vérifie les migrations et requêtes sur une base au nom unique, supprimée à la fin. Ce test ne sélectionne pas la base RP.

`tests/cfx_integration.lua` est ajouté au manifeste **de la copie de test seulement**. La commande console `spin_qa` vérifie le nom de base avant toute fixture, puis utilise un inventaire temporaire, les exports installés et des lignes SQL identifiées. Les fixtures sont nettoyées après exécution. Aucun événement réseau n'expose ce harness aux joueurs.

Le journal de console est `integration.log`. `console.in` alimente uniquement cette instance ; `processes.json` conserve les identifiants des deux processus locaux de test. Ne pas réutiliser cette console pour la production ou la map.

## À faire avec de vrais clients

Connexion F8 : `connect 192.99.0.20:30127`. L'écoute locale et l'endpoint HTTP sont contrôlés. Le navigateur Tessel a effectivement ouvert `http://192.99.0.20:30127/dynamic.json` et lu le serveur ESX avec zéro joueur ; cela ne valide ni UDP ni la connexion d'un vrai client GTA. Aucun joueur réel n'a participé aux tests serveur cités ici.

Suivre [RECETTE_PARCOURS_JOUEUR.md](RECETTE_PARCOURS_JOUEUR.md) avec deux comptes de test. Configurer les droits et soldes de ces comptes par les outils d'administration existants, sans activer les profils gratuits. Vérifier aussi le chargement du personnage ESX et le spawn sur cette configuration minimale ; leur absence d'erreur au démarrage ne constitue pas une connexion client réussie.

Les chemins et ports sont des informations d'exploitation de l'hôte, pas une installation universelle à copier telle quelle chez un client commercial.
