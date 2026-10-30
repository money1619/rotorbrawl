-- AEOM Bridge (client) - Copyright (c) 2026 AEOM Development. Licence : voir LICENSE de la ressource.
-- Couche de compatibilite framework + inventaire + ciblage. Fichier ouvert : adaptable a un framework custom.
--   Frameworks : es_extended (ESX), qb-core (QBCore), qbx_core (Qbox)       -> Bridge.*
--   Inventaires : ox_inventory, qs-inventory, qb-inventory (+ ps / lj), ESX -> Inv.*
--   Ciblage : ox_target, qb-target                                          -> Target.*
-- Detection automatique ; forcer avec Config.Bridge = { framework = ..., inventory = ..., target = 'ox'|'qb' }
-- Source unique : D:\FXServer\tools\aeom_bridge (ne pas modifier la copie d'un script sans reporter le changement).

local cfg = (rawget(_G, 'Config') or {}).Bridge or {}

local function started(res) return GetResourceState(res) == 'started' end

Bridge = { name = cfg.framework or 'auto', version = '1.0.0' }
Inv = { name = cfg.inventory or 'auto' }
Target = { name = cfg.target or 'auto' }
-- References locales : le pont reste coherent meme si la ressource remplace ensuite ces globales
local Bridge, Inv, Target = Bridge, Inv, Target

if Bridge.name == 'auto' then
    if started('qbx_core') then Bridge.name = 'qbx'
    elseif started('es_extended') then Bridge.name = 'esx'
    elseif started('qb-core') then Bridge.name = 'qb'
    else Bridge.name = 'none' end
end
local fw = Bridge.name

local ESX, QB
if fw == 'esx' then ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then QB = exports['qb-core']:GetCoreObject() end

if Inv.name == 'auto' then
    if started('ox_inventory') then Inv.name = 'ox'
    elseif started('qs-inventory') then Inv.name = 'qs'
    elseif fw == 'qb' or fw == 'qbx' then Inv.name = 'qb'
    elseif fw == 'esx' then Inv.name = 'esx'
    else Inv.name = 'none' end
end
local inv = Inv.name

if Target.name == 'auto' then
    if started('ox_target') then Target.name = 'ox'
    elseif started('qb-target') then Target.name = 'qb'
    else Target.name = 'none' end
end
local tgt = Target.name

-- [fix 25/10/2026] ox_target / qb-target démarré APRÈS modern_gangs : on l'attend (60 s max) au lieu de tout désactiver.
-- À appeler dans un thread. Renvoie true quand un ciblage est disponible.
function Target.waitReady(timeout)
    if tgt ~= 'none' then return true end
    if cfg.target and cfg.target ~= 'auto' then return false end
    local limit = GetGameTimer() + (timeout or 60000)
    while GetGameTimer() < limit do
        if started('ox_target') then tgt = 'ox' elseif started('qb-target') then tgt = 'qb' end
        if tgt ~= 'none' then Target.name = tgt; return true end
        if GetResourceState('ox_target') == 'missing' and GetResourceState('qb-target') == 'missing' then return false end
        Wait(500)
    end
    return false
end


--------------------------------------------------------------------------- joueur
-- Donnees brutes du framework (ESX.PlayerData / QB PlayerData)
function Bridge.getPlayerData()
    if fw == 'esx' then return ESX.GetPlayerData() end
    if fw == 'qbx' then return exports.qbx_core:GetPlayerData() end
    if fw == 'qb' then return QB.Functions.GetPlayerData() end
    return {}
end

function Bridge.isLoaded()
    if fw == 'esx' then return ESX.IsPlayerLoaded() end
    if fw == 'qb' or fw == 'qbx' then
        local d = Bridge.getPlayerData()
        return d ~= nil and d.citizenid ~= nil
    end
    return NetworkIsPlayerActive(PlayerId())
end

function Bridge.getIdentifier()
    local d = Bridge.getPlayerData() or {}
    return fw == 'esx' and d.identifier or d.citizenid
end

local function normJob(j)
    if not j then return nil end
    if fw == 'esx' then
        return {
            name = j.name, label = j.label, grade = tonumber(j.grade) or 0, gradeLabel = j.grade_label,
            onDuty = j.onDuty ~= false, isBoss = j.grade_name == 'boss',
        }
    end
    local g = type(j.grade) == 'table' and j.grade or { level = j.grade }
    return {
        name = j.name, label = j.label, grade = tonumber(g.level) or 0, gradeLabel = g.name,
        onDuty = j.onduty ~= false, isBoss = j.isboss == true,
    }
end

-- { name, label, grade, gradeLabel, onDuty, isBoss } ou nil
function Bridge.getJob()
    local d = Bridge.getPlayerData()
    return normJob(d and d.job)
end

function Bridge.hasJob(jobs, minGrade, requireDuty)
    local j = Bridge.getJob()
    if not j then return false end
    if type(jobs) == 'string' then jobs = { jobs } end
    for _, name in ipairs(jobs) do
        if j.name == name then
            if minGrade and j.grade < minGrade then return false end
            if requireDuty and not j.onDuty then return false end
            return true
        end
    end
    return false
end

-- account : 'cash' | 'bank' | 'black' (affichage seulement : le serveur decide)
function Bridge.getMoney(account)
    account = account or 'cash'
    local d = Bridge.getPlayerData() or {}
    if fw == 'esx' then
        local name = ({ cash = 'money', bank = 'bank', black = 'black_money' })[account] or account
        for _, a in ipairs(d.accounts or {}) do
            if a.name == name then return a.money or 0 end
        end
        return 0
    end
    if account == 'black' then return Inv.count(cfg.blackMoneyItem or 'black_money') end
    return d.money and d.money[account] or 0
end

-- type : 'inform' | 'success' | 'error' | 'warning'
function Bridge.notify(msg, ntype, duration)
    if started('ox_lib') and lib and lib.notify then
        lib.notify({ description = msg, type = ntype or 'inform', duration = duration })
    elseif fw == 'esx' then
        ESX.ShowNotification(msg, ntype, duration)
    elseif fw == 'qb' or fw == 'qbx' then
        TriggerEvent('QBCore:Notify', msg, ntype == 'inform' and 'primary' or ntype, duration)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

--------------------------------------------------------------------------- evenements
-- cb() quand le personnage est charge (et tout de suite s'il l'est deja : redemarrage de la ressource)
function Bridge.onLoaded(cb)
    if fw == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function() cb() end)
    elseif fw == 'qb' or fw == 'qbx' then
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end
    CreateThread(function()
        if Bridge.isLoaded() then cb() end
    end)
end

function Bridge.onUnloaded(cb)
    if fw == 'esx' then
        RegisterNetEvent('esx:onPlayerLogout', function() cb() end)
    elseif fw == 'qb' or fw == 'qbx' then
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() cb() end)
    end
end

-- cb(job) avec le metier normalise
function Bridge.onJobChange(cb)
    if fw == 'esx' then
        RegisterNetEvent('esx:setJob', function(job) cb(normJob(job)) end)
    elseif fw == 'qb' or fw == 'qbx' then
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) cb(normJob(job)) end)
    end
end

--------------------------------------------------------------------------- inventaire (lecture)
function Inv.count(item)
    if inv == 'ox' then return exports.ox_inventory:Search('count', item) or 0 end
    if inv == 'qs' then
        local ok, n = pcall(function() return exports['qs-inventory']:Search(item) end)
        return ok and tonumber(n) or 0
    end
    if inv == 'qb' then
        local d, n = Bridge.getPlayerData() or {}, 0
        for _, it in pairs(d.items or {}) do
            if it and it.name == item then n = n + (it.amount or it.count or 0) end
        end
        return n
    end
    if inv == 'esx' then
        for _, it in ipairs((Bridge.getPlayerData() or {}).inventory or {}) do
            if it.name == item then return it.count or 0 end
        end
    end
    return 0
end

function Inv.has(item, qty) return Inv.count(item) >= (qty or 1) end

-- Objets du joueur : { { name, slot, count, metadata } }
function Inv.getItems()
    local out, raw = {}, nil
    if inv == 'ox' then
        for _, it in pairs(exports.ox_inventory:GetPlayerItems() or {}) do
            out[#out + 1] = { name = it.name, slot = it.slot, count = it.count, metadata = it.metadata }
        end
        return out
    end
    if inv == 'qs' then
        local ok, l = pcall(function() return exports['qs-inventory']:getUserInventory() end)
        raw = ok and l or {}
    elseif inv == 'qb' then
        raw = (Bridge.getPlayerData() or {}).items or {}
    elseif inv == 'esx' then
        for _, it in ipairs((Bridge.getPlayerData() or {}).inventory or {}) do
            if (it.count or 0) > 0 then out[#out + 1] = { name = it.name, count = it.count } end
        end
        return out
    end
    for slot, it in pairs(raw or {}) do
        if it and it.name then out[#out + 1] = { name = it.name, slot = it.slot or slot, count = it.amount or it.count, metadata = it.info } end
    end
    return out
end

-- Definition d'un objet { label, weight, ... } (ox_inventory seulement) ; nil sinon
function Inv.itemData(item)
    if inv ~= 'ox' then return nil end
    return exports.ox_inventory:Items(item)
end

-- Libelle d'un objet (nom technique si inconnu)
function Inv.label(item)
    local d = Inv.itemData(item)
    return d and d.label or item
end

-- Emplacement de l'arme en main (ox_inventory) ; nil avec les autres inventaires
function Inv.currentWeaponSlot()
    if inv ~= 'ox' then return nil end
    local w = exports.ox_inventory:getCurrentWeapon()
    return w and w.slot
end

-- Arme en main { name, slot, ... } (ox_inventory) ; nil avec les autres inventaires
function Inv.currentWeapon()
    if inv ~= 'ox' then return nil end
    return exports.ox_inventory:getCurrentWeapon()
end

-- Image d'un objet pour une NUI (nui://...) ; nil si inconnue
function Inv.image(item)
    if inv == 'ox' then return ('nui://ox_inventory/web/images/%s.png'):format(item) end
    if inv == 'qs' then return ('nui://qs-inventory/html/images/%s.png'):format(item) end
    if inv == 'qb' then return ('nui://qb-inventory/html/images/%s.png'):format(item) end
    return nil
end

--------------------------------------------------------------------------- ciblage
-- Options au format ox_target : { name, label, icon, distance, groups, items, canInteract(entity, distance, coords),
--   onSelect(data) } ; data.entity est fourni avec qb-target aussi.
local zones = {}   -- id -> nom qb-target

local function qbOptions(options)
    local out, dist = {}, 2.0
    for _, o in ipairs(options) do
        dist = math.max(dist, o.distance or 2.0)
        -- items en liste (qb-target n'accepte qu'un objet) : verifie ici, tous ou un seul selon anyItem
        local list = type(o.items) == 'table' and o.items or nil
        local function hasItems()
            if not list then return true end
            for _, it in pairs(list) do
                local ok = Inv.has(type(it) == 'string' and it or tostring(it))
                if o.anyItem and ok then return true end
                if not o.anyItem and not ok then return false end
            end
            return not o.anyItem
        end
        out[#out + 1] = {
            label = o.label, icon = o.icon, item = type(o.items) == 'string' and o.items or nil,
            job = o.groups,
            canInteract = (o.canInteract or list) and function(entity, distance, data)
                if not hasItems() then return false end
                if not o.canInteract then return true end
                return o.canInteract(entity, distance, data and data.coords or GetEntityCoords(PlayerPedId()))
            end,
            action = function(entity)
                if o.onSelect then o.onSelect({ entity = entity, name = o.name }) end
                if o.event then TriggerEvent(o.event, { entity = entity }) end
                if o.serverEvent then TriggerServerEvent(o.serverEvent, { entity = entity }) end
            end,
        }
    end
    return { options = out, distance = dist }
end

local seq = 0
local function newName(prefix)
    seq = seq + 1
    return ('%s_%s_%d'):format(GetCurrentResourceName(), prefix, seq)
end

-- Zone boite : coords (vec3), size (vec3), heading ; renvoie un id pour Target.removeZone
function Target.addBox(coords, size, heading, options, debug)
    if tgt == 'ox' then
        return exports.ox_target:addBoxZone({ coords = coords, size = size, rotation = heading or 0.0, debug = debug, options = options })
    end
    if tgt == 'qb' then
        local name = newName('box')
        exports['qb-target']:AddBoxZone(name, coords, size.y, size.x, {
            name = name, heading = heading or 0.0, debugPoly = debug,
            minZ = coords.z - size.z / 2, maxZ = coords.z + size.z / 2,
        }, qbOptions(options))
        zones[name] = name
        return name
    end
end

function Target.addSphere(coords, radius, options, debug)
    if tgt == 'ox' then
        return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = debug, options = options })
    end
    if tgt == 'qb' then
        local name = newName('sphere')
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = debug, useZ = true }, qbOptions(options))
        zones[name] = name
        return name
    end
end

function Target.removeZone(id)
    if not id then return end
    if tgt == 'ox' then exports.ox_target:removeZone(id)
    elseif tgt == 'qb' then
        exports['qb-target']:RemoveZone(id)
        zones[id] = nil
    end
end

local function labels(options)
    local out = {}
    for _, o in ipairs(options) do out[#out + 1] = o.label end
    return out
end

local function names(options)
    local out = {}
    for _, o in ipairs(options) do out[#out + 1] = o.name end
    return out
end

-- Entite locale (non reseau)
function Target.addLocalEntity(entity, options)
    if tgt == 'ox' then exports.ox_target:addLocalEntity(entity, options)
    elseif tgt == 'qb' then exports['qb-target']:AddTargetEntity(entity, qbOptions(options)) end
end

function Target.removeLocalEntity(entity, options)
    if tgt == 'ox' then exports.ox_target:removeLocalEntity(entity, options and names(options))
    elseif tgt == 'qb' then exports['qb-target']:RemoveTargetEntity(entity, options and labels(options)) end
end

-- Entite reseau (netId)
function Target.addEntity(netId, options)
    if tgt == 'ox' then exports.ox_target:addEntity(netId, options)
    elseif tgt == 'qb' then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 then exports['qb-target']:AddTargetEntity(ent, qbOptions(options)) end
    end
end

function Target.removeEntity(netId, options)
    if tgt == 'ox' then exports.ox_target:removeEntity(netId, options and names(options))
    elseif tgt == 'qb' then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 then exports['qb-target']:RemoveTargetEntity(ent, options and labels(options)) end
    end
end

function Target.addModel(models, options)
    if tgt == 'ox' then exports.ox_target:addModel(models, options)
    elseif tgt == 'qb' then exports['qb-target']:AddTargetModel(models, qbOptions(options)) end
end

function Target.removeModel(models, options)
    if tgt == 'ox' then exports.ox_target:removeModel(models, options and names(options))
    elseif tgt == 'qb' then exports['qb-target']:RemoveTargetModel(models, options and labels(options)) end
end

-- Tous les vehicules / tous les joueurs
function Target.addGlobalVehicle(options)
    if tgt == 'ox' then exports.ox_target:addGlobalVehicle(options)
    elseif tgt == 'qb' then exports['qb-target']:AddGlobalVehicle(qbOptions(options)) end
end

function Target.removeGlobalVehicle(options)
    if tgt == 'ox' then exports.ox_target:removeGlobalVehicle(names(options))
    elseif tgt == 'qb' then exports['qb-target']:RemoveGlobalVehicle(labels(options)) end
end

function Target.addGlobalPlayer(options)
    if tgt == 'ox' then exports.ox_target:addGlobalPlayer(options)
    elseif tgt == 'qb' then exports['qb-target']:AddGlobalPlayer(qbOptions(options)) end
end

function Target.removeGlobalPlayer(options)
    if tgt == 'ox' then exports.ox_target:removeGlobalPlayer(names(options))
    elseif tgt == 'qb' then exports['qb-target']:RemoveGlobalPlayer(labels(options)) end
end

-- Zones qb-target retirees a l'arret de la ressource (ox_target le fait seul)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or tgt ~= 'qb' then return end
    for name in pairs(zones) do exports['qb-target']:RemoveZone(name) end
end)
