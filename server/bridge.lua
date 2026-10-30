-- Accès au framework et à l'état des joueurs, posé sur le pont AEOM (bridge/server.lua, chargé avant) :
-- ESX, QBCore ou Qbox ; sans framework, on utilise les natives FiveM.
-- Toutes les informations viennent du serveur (OneSync), jamais d'un message du client.
SpinArena = SpinArena or {}

local Core = Bridge   -- pont AEOM (global), masqué ci-dessous par le Bridge propre à SPIN ARENA
local Bridge = {}

function Bridge.online(src)
    return src ~= nil and GetPlayerName(src) ~= nil
end

-- Identifiant stable du personnage (ESX identifier / QB citizenid) ou du compte (licence FiveM)
function Bridge.identifier(src)
    local id = Core and Core.getIdentifier(src)
    if id then return id end
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. tostring(src))
end

function Bridge.name(src)
    local name = Core and Core.getPlayer(src) and Core.getName(src) or GetPlayerName(src)
    return name or ('#' .. tostring(src))
end

-- Contexte physique du joueur lu côté serveur ; nil si le joueur n'a pas de ped
function Bridge.context(src)
    if not Bridge.online(src) then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return {
        ped = ped,
        coords = { x = c.x, y = c.y, z = c.z },
        heading = GetEntityHeading(ped),
        bucket = GetPlayerRoutingBucket(src),
        inVehicle = GetVehiclePedIsIn(ped, false) ~= 0,
        dead = GetEntityHealth(ped) <= 0,
    }
end

-- Mort : événements envoyés par le client du framework (un client ne peut pénaliser que lui-même)
--   ESX : esx:onPlayerDeath · QBCore : hospital:server:SetDeathStatus(true) (qb-ambulancejob)
--   tous : baseevents:onPlayerDied / onPlayerKilled si la ressource baseevents tourne
function Bridge.onDeath(cb)
    RegisterNetEvent('esx:onPlayerDeath', function() cb(source) end)
    RegisterNetEvent('hospital:server:SetDeathStatus', function(isDead)
        if isDead == true then cb(source) end
    end)
    if Core and Core.name ~= 'esx' then
        RegisterNetEvent('baseevents:onPlayerDied', function() cb(source) end)
        RegisterNetEvent('baseevents:onPlayerKilled', function() cb(source) end)
    end
end

-- Départ : déconnexion, ou retour au choix du personnage
function Bridge.onLeave(cb)
    AddEventHandler('playerDropped', function(reason)
        cb(source, 'disconnect', reason)
    end)
    AddEventHandler('esx:playerLogout', function(playerId)
        cb(playerId, 'logout')
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId)
        -- depuis le réseau, un client ne peut décharger que lui-même
        cb(GetInvokingResource() and tonumber(playerId) or source, 'logout')
    end)
end

-- Personnage chargé : cb(src)
function Bridge.onLoaded(cb)
    if Core then Core.onLoaded(cb) end
end

SpinArena.Bridge = Bridge
return Bridge
