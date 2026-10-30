# Essai en jeu : arènes fixes, zones, classement, tournois

Procédures pour vérifier avec de vrais clients GTA les modules serveur `server/arenas.lua` (phase 5), `server/ranking.lua` et `server/tournaments.lua` (phase 6). Rien de ce qui suit n'a encore été validé en jeu : les résultats attendus viennent du code et des tests hors jeu (émulateur).

Tests hors jeu correspondants : `lua5.4 tests/server_unit_test.lua` (arènes), `tests/ranking_test.lua`, `tests/tournaments_test.lua`, `tests/tournaments_wiring_test.lua` (vrais callbacks et vrai match dans l'émulateur).

## Prérequis

| Point | Pourquoi |
|---|---|
| OneSync actif (`+set onesync on` au lancement) | position, monde et état des joueurs lus côté serveur |
| `add_ace group.admin command.spin_admin allow` | commande `/spin_admin` |
| `add_ace group.admin spin_arena.organizer allow` (ou `spin_arena.admin`) | **créer un tournoi** : `command allow` ne suffit pas, l'ACE d'organisateur est vérifiée à part |
| Instance avec ESX, oxmysql et ox_inventory, et **une vraie toupie complète possédée** (objet d'inventaire) par joueur | règle « pas de combat sans toupie complète possédée » : c'est elle qu'on valide. SpinTest (sans ESX, base ni inventaire) ne convient pas à cet essai |
| 2 joueurs (3 pour les spectateurs, 4 pour un tableau à 4) | |

## 1. Arènes fixes et zones

1. Admin, debout sur un sol plat : `/spin_admin arena add club_1`. Attendu : « club_1 ajoutée » ; console serveur : `arena club_1 ajoutée par …`.
2. `/spin_admin arena list` (aussi en console). Attendu : une ligne avec la position, le cap et le monde.
3. Deux joueurs à moins de 15 m de `club_1` se défient. Attendu : l'arène du match est **au centre de club_1** (pas 2,5 m devant le joueur qui défie).
4. Défi ailleurs, à plus de 15 m de toute arène fixe. Attendu : arène improvisée devant celui qui défie (`improvisedAnywhere = true` par défaut).
5. Passer `improvisedAnywhere = false`, redémarrer la ressource, refaire un défi loin de tout. Attendu : refus avec le code `no_zone`.
6. `/spin_admin zone add parc 30` à un autre endroit, puis défi à moins de 30 m. Attendu : arène improvisée acceptée.
7. Redémarrer la ressource. Attendu : console `1 arène(s) fixe(s) et 1 zone(s) chargées` ; `data/arenas.json` contient les deux.
8. `/spin_admin arena remove club_1`, `/spin_admin zone remove parc`. Attendu : « … supprimée », absentes de la liste et du fichier.

Cas d'erreur à essayer : nom avec espace ou de plus de 32 caractères (« nom invalide »), même nom deux fois (« existe déjà »), deuxième arène fixe collée à la première (« trop près »), `arena add` depuis la console (« à faire en jeu »).

## 2. Classement

1. Jouer un match jusqu'au bout (victoire aux manches). Console attendue : `… classé (saison 1) : <A> +12 -> 1012, <B> -12 -> 988` (à égalité de cote, K = 24).
2. Un abandon (`forfeit`) **avant 30 s** depuis la création du match. Attendu : console `… non classé : early_forfeit`, aucune cote modifiée.
3. Un match sans résultat (les deux joueurs partent, ou `/spin_admin cancel` après le départ). Attendu : aucune cote modifiée.
4. Callback `spin_arena:leaderboard` (affichage client à venir, voir « Points restants ») : `top` trié par cote, ma ligne `me` même hors du top ; aucun identifiant (licence, personnage) dans la réponse.

Le classement est **en mémoire** : il repart de zéro au redémarrage tant que le Store SQL n'est pas branché.

## 3. Tournois

Lieu du tournoi = position de l'organisateur à la création. Un joueur est « présent » à moins de 15 m du lieu, dans le même monde, vivant, à pied et libre (pas dans un autre match).

1. Organisateur au lieu : `/spin_admin tournoi create 4 2 Coupe du soir`. Attendu : « tournoi 1 créé » ; tous les joueurs reçoivent la notification `tournament_created`.
2. `/spin_admin tournoi list`. Attendu : `1 Coupe du soir : signup, 0/4 joueurs`.
3. Inscription des joueurs : callback `spin_arena:tournament_join` `{ id = 1, top = <toupie> }` (**aucune interface client pour l'instant**, voir « Points restants »).
4. Deux joueurs inscrits, puis attendre la fin des 2 minutes, ou `/spin_admin tournoi start 1`. Attendu : `tournament_started`, puis `tournament_match_ready` aux deux joueurs ; le match démarre seul quand les deux sont au lieu.
5. Laisser le match se terminer. Attendu : annonce `tournament_won` à tout le serveur ; `list` affiche `finished, … vainqueur <nom>` ; le match compte aussi pour le classement.
6. Absence : un joueur reste à plus de 15 m pendant 3 min. Attendu : il perd par forfait (`absent`), l'autre passe.
7. Toupie invalide : le joueur vend ou démonte sa toupie entre l'inscription et la rencontre. Attendu : `tournament_invalid_top`, forfait de ce joueur.
8. Déconnexion pendant l'attente de la rencontre : l'adversaire passe (`left`).
9. `/spin_admin tournoi cancel 1` en cours de match. Attendu : `tournament_cancelled` ; le match en cours continue normalement mais ne compte plus pour le tournoi.

Avec 3 joueurs dans un tournoi de 4 : un joueur est exempté au premier tour (tirage au sort). Moins de 2 inscrits à l'échéance : tournoi annulé (`not_enough_players`).

## Points restants (avant un essai complet)

- **Client (Fermi)** : aucune interface pour s'inscrire à un tournoi, le quitter ou voir le tableau (`tournamentJoin` / `tournamentLeave` / `tournamentStatus`), ni pour afficher le classement (`leaderboard`). Sans elle, les étapes 3.3 et 2.4 ne sont faisables qu'en appelant les callbacks à la main.
- **Traductions (Fermi)** : codes `no_zone`, `not_allowed`, `tournament_closed`, `tournament_full`, `already_registered`, et notifications `tournament_created`, `tournament_started`, `tournament_match_ready`, `tournament_eliminated`, `tournament_won`, `tournament_no_winner`, `tournament_cancelled`, `tournament_invalid_top`.
- **Config (Archimedes)** : dans `config/server.lua`, le commentaire de `tournaments.venueRadius` dit « distance maximale entre les deux joueurs » ; c'est la distance de chaque joueur **au lieu** du tournoi (d'où 30 m au plus entre eux). `maxReplays` s'applique aussi aux nuls, pas seulement aux annulations.
- **Classement** : Store SQL non branché (cotes perdues au redémarrage).
- **ACE** : penser à `spin_arena.organizer` sur l'instance d'essai.
- **Instance d'essai** : il faut une instance ESX + SQL + ox_inventory avec de vraies toupies complètes. `allowTestProfiles = true` (profils gratuits) ne sert qu'aux bancs de débogage identifiés comme tels ; un essai fait avec ce réglage ne valide pas la règle « toupie complète possédée » et ne doit pas être présenté comme une validation en jeu.
