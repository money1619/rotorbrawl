-- ROTORBRAWL — objets à ajouter dans ox_inventory/data/items.lua (format d'ox_inventory 2.45.0)
-- Copiez les entrées ci-dessous dans la table renvoyée par data/items.lua, puis redémarrez ox_inventory.
--
-- spin_top  : non empilable ; metadata.uid est attribué par ROTORBRAWL (hook createItem). metadata.kit facultatif
--             à la création : attack, defense, endurance, balance ou mobility (sinon balance).
--             Exemple admin : /giveitem <id> spin_top 1 ne donne pas de kit ; par script :
--             exports.ox_inventory:AddItem(src, 'spin_top', 1, { kit = 'attack' })
-- spin_part : empilable par pièce ; metadata.part = identifiant du catalogue (config/parts.lua), par exemple
--             exports.ox_inventory:AddItem(src, 'spin_part', 1, { part = 'tip_sharp' })
-- spin_repair_kit : remet l'usure d'une toupie à zéro à l'atelier.

return {
    ['spin_top'] = {
        label = 'Toupie de combat',
        weight = 200,
        stack = false,
        close = true,
        description = 'Toupie ROTORBRAWL',
        -- Boutons de l'inventaire (clic droit), décision de Money du 19/10 : démonter (toutes les pièces reviennent),
        -- renommer, peindre. Événements client LOCAUX ; le serveur Chaos_Arena revalide tout (propriétaire, verrou,
        -- match, nom UTF-8). Pris en compte par ox_inventory seulement à son redémarrage (docs/ACTIVATION_DEMONTER.md).
        buttons = {
            {
                label = 'Démonter',
                action = function(slot)
                    TriggerEvent('spin_arena:cl:disassembleSlot', slot)
                end,
            },
            {
                label = 'Renommer',
                action = function(slot)
                    TriggerEvent('spin_arena:cl:renameSlot', slot)
                end,
            },
            {
                label = 'Peindre',
                action = function(slot)
                    TriggerEvent('spin_arena:cl:paintSlot', slot)
                end,
            },
        },
    },
    ['spin_part'] = {
        label = 'Pièce de toupie',
        weight = 50,
        stack = true,
        close = false,
        description = 'Pièce de rechange pour l\'atelier ROTORBRAWL',
    },
    -- Un seul objet pour tous les lanceurs : le type est dans metadata.launcher (cord, crank, spring, precision, rail,
    -- config/parts.lua), par exemple exports.ox_inventory:AddItem(src, 'spin_launcher', 1, { launcher = 'crank', label = 'Lanceur Manivelle' }).
    -- Sans metadata.launcher : lanceur Cordon (de base). Le lanceur de l'emplacement le plus bas est celui utilisé en match.
    ['spin_launcher'] = {
        label = 'Lanceur',
        weight = 150,
        stack = false,
        close = true,
        description = 'Lanceur de toupie ROTORBRAWL',
    },
    ['spin_repair_kit'] = {
        label = 'Kit de réparation',
        weight = 100,
        stack = true,
        close = true,
    },
}
