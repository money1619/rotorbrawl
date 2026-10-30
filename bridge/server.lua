-- AEOM Shim (serveur) - Copyright (c) 2026 AEOM Development. Licence : voir LICENSE de la ressource.
-- Pont centralise : Bridge.* / Inv.* sont executes par la ressource aeom-bridge (server/compat.lua).
-- Ce fichier garde les memes noms que l'ancien pont embarque : le code du script n'a pas change.
-- Source unique : D:\FXServer\tools\aeom_bridge\shim (installer avec sync.py shim). Retour arriere : sync.py restore.

local BRIDGE = 'aeom-bridge'

if GetResourceState(BRIDGE) ~= 'started' then
    print(('^1[%s] aeom-bridge n\'est pas demarre : ajoute "ensure aeom-bridge" avant cette ressource dans server.cfg^7'):format(GetCurrentResourceName()))
end

local function remote(group)
    return setmetatable({}, {
        __index = function(t, name)
            local fn = function(...) return exports[BRIDGE]:Compat(group, name, ...) end
            rawset(t, name, fn)
            return fn
        end,
    })
end

local info = exports[BRIDGE]:CompatInfo()

Bridge = remote('Bridge')
Inv = remote('Inv')
Bridge.name, Bridge.version, Bridge.vehicles = info.fw, info.version, info.vehicles
Inv.name, Inv.metadata = info.inv, info.metadata

-- Objet utilisable : avec ox_inventory, l'export use_<item> doit appartenir a CETTE ressource
-- (items.lua : server.export = '<ressource>.use_<item>'), les autres inventaires passent par aeom-bridge.
function Inv.registerUsable(item, cb)
    if info.inv == 'ox' then
        exports(('use_%s'):format(item), function(event, _, inventory, slot)
            if event == 'usingItem' then
                local s = exports.ox_inventory:GetSlot(inventory.id, slot)
                cb(inventory.id, slot, s and s.metadata)
                return false
            end
        end)
        return
    end
    exports[BRIDGE]:Compat('Inv', 'registerUsable', item, cb)
end
