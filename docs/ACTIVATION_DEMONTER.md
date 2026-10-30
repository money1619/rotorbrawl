# Bouton « Démonter » sur la toupie dans ox_inventory — à activer par Money

**État :** préparé, **non appliqué**. Côté Chaos_Arena, tout est prêt (événement client local `spin_arena:cl:disassembleSlot`, confirmation, démontage revalidé par le serveur). Seul le fichier d'objets d'ox_inventory reste à modifier, avec l'accord de Money.

En attendant, on démonte depuis le panneau « Mes toupies » de l'interface Arena.

## Ce qui change dans ox_inventory

Fichier `resources/[ox]/ox_inventory/data/items.lua`, entrée `spin_top` (ajoutée le 18/10 pour SPIN ARENA). On ajoute seulement le bloc `buttons` :

```lua
	['spin_top'] = {
		label = 'Toupie de combat',
		weight = 200,
		stack = false,
		close = true,
		description = 'Toupie SPIN ARENA',
		-- Bouton de l'inventaire : démonter (toutes les pièces reviennent). Le serveur Chaos_Arena revalide tout.
		buttons = {
			{
				label = 'Démonter',
				action = function(slot)
					TriggerEvent('spin_arena:cl:disassembleSlot', slot)
				end,
			},
		},
	},
```

C'est le même format que dans `install/ox_inventory_items.lua`, la référence d'installation de SPIN ARENA. Le format des boutons a été vérifié dans ox_inventory 2.45.0 (`client.lua`, `useButton`), et la même forme est déjà utilisée par un autre script du serveur. Diff préparé par Archimedes : `items_demonter.diff`.

## Sécurité

- L'événement est **local** : `AddEventHandler` sans `RegisterNetEvent`, donc ni le réseau ni un autre joueur ne peut le déclencher. C'est vérifié dans l'émulateur : un envoi par le réseau est ignoré.
- Le client n'envoie que l'identifiant de la toupie. Le serveur revalide le propriétaire, le verrou et l'absence de match, puis rend toutes les pièces (journalisé, avec compensation).
- Une confirmation est obligatoire : boîte ox_lib (« Démonter cette toupie ? »), ou à défaut deux appuis dans les 5 s.

## Activation (procédure)

1. Sauvegarder `data/items.lua`.
2. Appliquer le bloc ci-dessus.
3. ox_inventory ne relit `data/items.lua` **qu'à son démarrage**. Il faut donc redémarrer ox_inventory, ou tout le serveur, **sans joueurs connectés** (fenêtre de maintenance). **Ne jamais faire `restart ox_inventory` avec des joueurs en ligne** : les inventaires ouverts et les ressources qui en dépendent seraient perturbés.
4. Ensuite, redémarrer Chaos_Arena (le hook et l'événement s'enregistrent au démarrage).
5. Vérifier en jeu : clic droit sur une toupie → « Démonter » → confirmation → les pièces apparaissent dans l'inventaire, la toupie disparaît. Puis vérifier qu'une toupie engagée dans un match ne peut pas être démontée (`top_locked`).

## Retour arrière

Remettre la sauvegarde de `data/items.lua` à la prochaine maintenance. Le reste de Chaos_Arena n'en dépend pas : le panneau « Mes toupies » continue de proposer le démontage.

## Tests

`tests/fivem_emu/assembly_swap_test.lua`, scénario 11, vérifie trois choses : un événement réseau est ignoré, une confirmation refusée ne démonte rien, une confirmation acceptée rend les 4 pièces et retire la toupie. **Pas encore essayé dans GTA.**
