-- AEOM Bridge (serveur) - Copyright (c) 2026 AEOM Development. Licence : voir LICENSE de la ressource.
-- Couche de compatibilite framework + inventaire. Fichier ouvert : adaptable a un framework custom.
--   Frameworks : es_extended (ESX), qb-core (QBCore), qbx_core (Qbox)       -> Bridge.*
--   Inventaires : ox_inventory, qs-inventory, qb-inventory (+ ps / lj), ESX -> Inv.*
-- Detection automatique ; forcer avec Config.Bridge = { framework = 'esx'|'qb'|'qbx', inventory = 'ox'|'qs'|'qb'|'esx' }

local cfg = (rawget(_G, 'Config') or {}).Bridge or {}
local resName = GetCurrentResourceName()

local function started(res) return GetResourceState(res) == 'started' end

Bridge = { name = cfg.framework or 'auto', version = '1.0.0' }
Inv = { name = cfg.inventory or 'auto' }
-- References locales : le pont reste coherent meme si la ressource remplace ensuite les globales Bridge / Inv
local Bridge, Inv = Bridge, Inv

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
Inv.metadata = inv == 'ox' or inv == 'qs' or inv == 'qb'

--------------------------------------------------------------------------- joueurs
-- Objet joueur du framework (xPlayer ESX, Player QB/Qbox) ou nil
function Bridge.getPlayer(src)
    src = tonumber(src)
    if not src then return nil end
    if fw == 'esx' then return ESX.GetPlayerFromId(src) end
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if fw == 'qb' then return QB.Functions.GetPlayer(src) end
    return nil
end

local function pdata(src)
    local p = Bridge.getPlayer(src)
    return p and p.PlayerData
end

-- Identifiant du personnage (identifier ESX, citizenid QB/Qbox)
function Bridge.getIdentifier(src)
    if fw == 'esx' then
        local x = Bridge.getPlayer(src)
        return x and x.identifier or nil
    end
    local d = pdata(src)
    return d and d.citizenid or nil
end

-- Joueur connecte a partir de l'identifiant du personnage
function Bridge.getSourceFromIdentifier(identifier)
    if not identifier then return nil end
    if fw == 'esx' then
        local x = ESX.GetPlayerFromIdentifier(identifier)
        return x and x.source or nil
    end
    if fw == 'qbx' then
        local p = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source or nil
    end
    if fw == 'qb' then
        local p = QB.Functions.GetPlayerByCitizenId(identifier)
        return p and p.PlayerData.source or nil
    end
    return nil
end

-- Nom RP « Prenom Nom »
function Bridge.getName(src)
    if fw == 'esx' then
        local x = Bridge.getPlayer(src)
        if not x then return GetPlayerName(src) end
        local first, last = x.get and x.get('firstName'), x.get and x.get('lastName')
        if first and last then return ('%s %s'):format(first, last) end
        return x.getName and x.getName() or GetPlayerName(src)
    end
    local d = pdata(src)
    local c = d and d.charinfo
    if c and c.firstname then return ('%s %s'):format(c.firstname, c.lastname or '') end
    return GetPlayerName(src)
end

-- Sources des joueurs dont le personnage est charge
function Bridge.getPlayers()
    local out = {}
    if fw == 'esx' then
        for _, x in pairs(ESX.GetExtendedPlayers()) do out[#out + 1] = x.source end
    elseif fw == 'qbx' then
        for src in pairs(exports.qbx_core:GetQBPlayers()) do out[#out + 1] = tonumber(src) end
    elseif fw == 'qb' then
        for _, src in pairs(QB.Functions.GetPlayers()) do out[#out + 1] = tonumber(src) end
    else
        for _, id in ipairs(GetPlayers()) do out[#out + 1] = tonumber(id) end
    end
    return out
end

--------------------------------------------------------------------------- metier
-- { name, label, grade (nombre), gradeLabel, onDuty, isBoss } ou nil
function Bridge.getJob(src)
    if fw == 'esx' then
        local x = Bridge.getPlayer(src)
        local j = x and x.job
        if not j then return nil end
        return {
            name = j.name, label = j.label, grade = tonumber(j.grade) or 0, gradeLabel = j.grade_label,
            onDuty = j.onDuty ~= false, isBoss = j.grade_name == 'boss',
        }
    end
    local d = pdata(src)
    local j = d and d.job
    if not j then return nil end
    local g = type(j.grade) == 'table' and j.grade or { level = j.grade }
    return {
        name = j.name, label = j.label, grade = tonumber(g.level) or 0, gradeLabel = g.name,
        onDuty = j.onduty ~= false, isBoss = j.isboss == true,
    }
end

-- jobs : nom ou liste de noms ; minGrade facultatif ; requireDuty facultatif
function Bridge.hasJob(src, jobs, minGrade, requireDuty)
    local j = Bridge.getJob(src)
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

function Bridge.setJob(src, name, grade)
    local p = Bridge.getPlayer(src)
    if not p then return false end
    if fw == 'esx' then
        if not ESX.DoesJobExist(name, grade or 0) then return false end
        p.setJob(name, grade or 0)
        return true
    end
    if fw == 'qbx' then return exports.qbx_core:SetJob(src, name, grade or 0) ~= false end
    return p.Functions.SetJob(name, grade or 0) ~= false
end

-- Metier d'un personnage connecte OU hors ligne (identifiant du personnage).
-- onlyIfJob : ne change rien si son metier actuel n'est pas celui-la. Hors ligne : necessite oxmysql (MySQL global).
function Bridge.setJobByIdentifier(identifier, name, grade, onlyIfJob)
    grade = tonumber(grade) or 0
    local src = Bridge.getSourceFromIdentifier(identifier)
    if src then
        local j = Bridge.getJob(src)
        if onlyIfJob and (not j or j.name ~= onlyIfJob) then return false end
        if j and j.name == name and j.grade == grade then return true end
        return Bridge.setJob(src, name, grade)
    end
    if fw == 'qbx' then
        if onlyIfJob then
            local off = exports.qbx_core:GetOfflinePlayer(identifier)
            local j = off and off.PlayerData.job
            if not j or j.name ~= onlyIfJob then return false end
        end
        return exports.qbx_core:SetJob(identifier, name, grade) ~= false
    end
    assert(MySQL, 'Bridge.setJobByIdentifier : ajouter @oxmysql/lib/MySQL.lua avant bridge/server.lua')
    if fw == 'esx' then
        local sql, args = 'UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { name, grade, identifier }
        if onlyIfJob then sql, args[#args + 1] = sql .. ' AND job = ?', onlyIfJob end
        return (MySQL.update.await(sql, args) or 0) > 0
    end
    if fw == 'qb' then
        local def = Bridge.getJobs()[name]
        local sql = [[UPDATE players SET job = JSON_SET(job, '$.name', ?, '$.label', ?, '$.grade.level', ?, '$.grade.name', ?)
            WHERE citizenid = ?]]
        local args = { name, def and def.label or name, grade, def and def.grades[grade] or tostring(grade), identifier }
        if onlyIfJob then
            sql = sql .. [[ AND JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?]]
            args[#args + 1] = onlyIfJob
        end
        return (MySQL.update.await(sql, args) or 0) > 0
    end
    return false
end

-- Liste des metiers declares : { [name] = { label, grades = { [n] = label } } }
function Bridge.getJobs()
    local out = {}
    if fw == 'esx' then
        for name, j in pairs(ESX.GetJobs() or {}) do
            local grades = {}
            for g, gd in pairs(j.grades or {}) do grades[tonumber(g)] = gd.label end
            out[name] = { label = j.label, grades = grades }
        end
    elseif fw == 'qb' or fw == 'qbx' then
        local jobs = fw == 'qbx' and exports.qbx_core:GetJobs() or QB.Shared.Jobs
        for name, j in pairs(jobs or {}) do
            local grades = {}
            for g, gd in pairs(j.grades or {}) do grades[tonumber(g)] = gd.name end
            out[name] = { label = j.label, grades = grades }
        end
    end
    return out
end

--------------------------------------------------------------------------- argent
-- account : 'cash' | 'bank' | 'black' (argent sale)
-- argent sale QB/Qbox : objet Config.Bridge.blackMoneyItem (defaut 'black_money')
local BLACK_ITEM = cfg.blackMoneyItem or 'black_money'
local ESX_ACCOUNT = { cash = 'money', bank = 'bank', black = 'black_money' }

function Bridge.getMoney(src, account)
    account = account or 'cash'
    local p = Bridge.getPlayer(src)
    if not p then return 0 end
    if fw == 'esx' then
        local a = p.getAccount(ESX_ACCOUNT[account] or account)
        return a and a.money or 0
    end
    if account == 'black' then return Inv.count(src, BLACK_ITEM) end
    return p.PlayerData.money and p.PlayerData.money[account] or 0
end

function Bridge.addMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return amount == 0 end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    if fw == 'esx' then
        p.addAccountMoney(ESX_ACCOUNT[account] or account, amount, reason)
        return true
    end
    if account == 'black' then return Inv.add(src, BLACK_ITEM, amount) end
    return p.Functions.AddMoney(account, amount, reason) ~= false
end

-- Retire seulement si le solde suffit ; renvoie true/false
function Bridge.removeMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return amount == 0 end
    if Bridge.getMoney(src, account) < amount then return false end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    if fw == 'esx' then
        p.removeAccountMoney(ESX_ACCOUNT[account] or account, amount, reason)
        return true
    end
    if account == 'black' then return Inv.remove(src, BLACK_ITEM, amount) end
    return p.Functions.RemoveMoney(account, amount, reason) ~= false
end

--------------------------------------------------------------------------- droits, notifications
-- Admin : ACE (command / group.admin) puis groupe du framework
function Bridge.isAdmin(src)
    if IsPlayerAceAllowed(src, 'command') or IsPlayerAceAllowed(src, 'group.admin') then return true end
    if fw == 'esx' then
        local x = Bridge.getPlayer(src)
        local g = x and x.getGroup and x.getGroup()
        return g == 'admin' or g == 'superadmin'
    end
    if fw == 'qb' then return QB.Functions.HasPermission(src, 'admin') or QB.Functions.HasPermission(src, 'god') end
    return false
end

-- type : 'inform' | 'success' | 'error' | 'warning'
function Bridge.notify(src, msg, ntype, duration)
    if started('ox_lib') then
        TriggerClientEvent('ox_lib:notify', src, { description = msg, type = ntype or 'inform', duration = duration })
    elseif fw == 'esx' then
        TriggerClientEvent('esx:showNotification', src, msg, ntype, duration)
    elseif fw == 'qb' or fw == 'qbx' then
        TriggerClientEvent('QBCore:Notify', src, msg, ntype == 'inform' and 'primary' or ntype, duration)
    end
end

--------------------------------------------------------------------------- permis / licences
-- ESX : table user_licenses (esx_license) ; QB / Qbox : metadata.licences du personnage. Hors ligne non gere.
function Bridge.hasLicense(src, ltype)
    if fw == 'esx' then
        local id = Bridge.getIdentifier(src)
        assert(MySQL, 'Bridge.hasLicense : ajouter @oxmysql/lib/MySQL.lua avant bridge/server.lua')
        return id ~= nil and MySQL.scalar.await('SELECT 1 FROM user_licenses WHERE owner = ? AND type = ?', { id, ltype }) ~= nil
    end
    local d = pdata(src)
    local l = d and d.metadata and d.metadata.licences
    return l ~= nil and l[ltype] == true
end

function Bridge.addLicense(src, ltype)
    if fw == 'esx' then
        -- esx_license:addLicense ecrit en base ; d'autres scripts l'ecoutent (ex. jsfour-idcard)
        TriggerEvent('esx_license:addLicense', src, ltype)
        return true
    end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    local l = p.PlayerData.metadata.licences or {}
    l[ltype] = true
    p.Functions.SetMetaData('licences', l)
    return true
end

function Bridge.removeLicense(src, ltype)
    if fw == 'esx' then
        TriggerEvent('esx_license:removeLicense', src, ltype)
        return true
    end
    local p = Bridge.getPlayer(src)
    if not p then return false end
    local l = p.PlayerData.metadata.licences or {}
    l[ltype] = false
    p.Functions.SetMetaData('licences', l)
    return true
end

--------------------------------------------------------------------------- evenements
-- cb(src) quand un personnage est charge / decharge ; cb(src, job) quand le metier change
function Bridge.onLoaded(cb)
    if fw == 'esx' then
        AddEventHandler('esx:playerLoaded', function(src) cb(src) end)
    elseif fw == 'qb' or fw == 'qbx' then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(p) cb(p and p.PlayerData and p.PlayerData.source or source) end)
    end
end

function Bridge.onUnloaded(cb)
    if fw == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) cb(src) end)
    elseif fw == 'qb' or fw == 'qbx' then
        -- depuis le reseau (GetInvokingResource() == nil), un client ne peut decharger que lui-meme
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
            if not GetInvokingResource() then return cb(source) end
            cb(tonumber(src) or source)
        end)
    end
    AddEventHandler('playerDropped', function() cb(source) end)
end

function Bridge.onJobChange(cb)
    if fw == 'esx' then
        AddEventHandler('esx:setJob', function(src) cb(src, Bridge.getJob(src)) end)
    elseif fw == 'qb' or fw == 'qbx' then
        AddEventHandler('QBCore:Server:OnJobUpdate', function(src) cb(src, Bridge.getJob(src)) end)
    end
end

--------------------------------------------------------------------------- vehicules possedes
-- Table SQL des vehicules : ESX owned_vehicles(owner, plate, vehicle) ; QB/Qbox player_vehicles(citizenid, plate, mods)
Bridge.vehicles = (fw == 'esx' or fw == 'none')
    and { table = 'owned_vehicles', owner = 'owner', plate = 'plate', props = 'vehicle' }
    or { table = 'player_vehicles', owner = 'citizenid', plate = 'plate', props = 'mods' }

--------------------------------------------------------------------------- inventaire
local function qbItems()
    if fw == 'qb' then return QB.Shared.Items end
    return nil
end

function Inv.count(src, item)
    if inv == 'ox' then return exports.ox_inventory:Search(src, 'count', item) or 0 end
    if inv == 'qs' then return exports['qs-inventory']:GetItemTotalAmount(src, item) or 0 end
    if inv == 'qb' then
        local d, n = pdata(src), 0
        for _, it in pairs(d and d.items or {}) do
            if it and it.name == item then n = n + (it.amount or it.count or 0) end
        end
        return n
    end
    if inv == 'esx' then
        local x = Bridge.getPlayer(src)
        local it = x and x.getInventoryItem(item)
        return it and (it.count or 0) or 0
    end
    return 0
end

function Inv.has(src, item, qty) return Inv.count(src, item) >= (qty or 1) end

-- Emplacements d'un objet : { { slot = n, count = n, metadata = table|nil } }
function Inv.slots(src, item)
    local out = {}
    if inv == 'ox' then
        for _, s in pairs(exports.ox_inventory:Search(src, 'slots', item) or {}) do
            out[#out + 1] = { slot = s.slot, count = s.count, metadata = s.metadata }
        end
    elseif inv == 'qs' or inv == 'qb' then
        local items = inv == 'qs' and exports['qs-inventory']:GetInventory(src) or (pdata(src) or {}).items
        for slot, s in pairs(items or {}) do
            if s and s.name == item then out[#out + 1] = { slot = s.slot or slot, count = s.amount or s.count, metadata = s.info } end
        end
    elseif Inv.count(src, item) > 0 then
        out[1] = { slot = item, count = Inv.count(src, item) }   -- ESX : pas d'emplacements
    end
    return out
end

-- Tous les objets du joueur : { { name, slot, count, metadata } }
function Inv.getItems(src)
    local out = {}
    if inv == 'ox' then
        for _, s in pairs(exports.ox_inventory:GetInventoryItems(src) or {}) do
            if s and s.name then out[#out + 1] = { name = s.name, slot = s.slot, count = s.count, metadata = s.metadata } end
        end
    elseif inv == 'qs' or inv == 'qb' then
        local items = inv == 'qs' and exports['qs-inventory']:GetInventory(src) or (pdata(src) or {}).items
        for slot, s in pairs(items or {}) do
            if s and s.name then out[#out + 1] = { name = s.name, slot = s.slot or slot, count = s.amount or s.count, metadata = s.info } end
        end
    elseif inv == 'esx' then
        local x = Bridge.getPlayer(src)
        for _, it in ipairs(x and x.getInventory() or {}) do
            if (it.count or 0) > 0 then out[#out + 1] = { name = it.name, slot = it.name, count = it.count } end
        end
    end
    return out
end

-- { name, count, metadata } de l'emplacement, ou nil
function Inv.getSlot(src, slot)
    if inv == 'ox' then
        local s = exports.ox_inventory:GetSlot(src, slot)
        return s and { name = s.name, count = s.count, metadata = s.metadata } or nil
    end
    if inv == 'qs' or inv == 'qb' then
        local items = inv == 'qs' and exports['qs-inventory']:GetInventory(src) or (pdata(src) or {}).items
        for i, s in pairs(items or {}) do
            if s and (s.slot or i) == slot then return { name = s.name, count = s.amount or s.count, metadata = s.info } end
        end
    end
    return nil
end

function Inv.canCarry(src, item, qty)
    qty = qty or 1
    if inv == 'ox' then return exports.ox_inventory:CanCarryItem(src, item, qty) == true end
    if inv == 'qs' then return exports['qs-inventory']:CanCarryItem(src, item, qty) ~= false end
    if inv == 'qb' then
        if started('qb-inventory') then
            local ok, can = pcall(function() return exports['qb-inventory']:CanAddItem(src, item, qty) end)
            if ok and can ~= nil then return can and true or false end
        end
        return true
    end
    if inv == 'esx' then
        local x = Bridge.getPlayer(src)
        return x ~= nil and x.canCarryItem(item, qty)
    end
    return false
end

function Inv.add(src, item, qty, metadata, slot)
    qty = qty or 1
    if qty <= 0 then return true end
    if inv == 'ox' then return exports.ox_inventory:AddItem(src, item, qty, metadata, slot) == true end
    if inv == 'qs' then return exports['qs-inventory']:AddItem(src, item, qty, slot, metadata) == true end
    if inv == 'qb' then
        local p = Bridge.getPlayer(src)
        local ok = p and p.Functions.AddItem(item, qty, slot, metadata)
        local def = ok and qbItems() and qbItems()[item]
        if def then TriggerClientEvent('inventory:client:ItemBox', src, def, 'add', qty) end
        return ok and true or false
    end
    if inv == 'esx' then
        local x = Bridge.getPlayer(src)
        if not x or not x.canCarryItem(item, qty) then return false end
        x.addInventoryItem(item, qty)
        return true
    end
    return false
end

-- Retire seulement si la quantite est disponible ; slot facultatif (objet precis avec metadonnees)
function Inv.remove(src, item, qty, slot)
    qty = qty or 1
    if qty <= 0 then return true end
    if Inv.count(src, item) < qty then return false end
    if inv == 'ox' then return exports.ox_inventory:RemoveItem(src, item, qty, nil, slot) == true end
    if inv == 'qs' then return exports['qs-inventory']:RemoveItem(src, item, qty, slot) ~= false end
    if inv == 'qb' then
        local p = Bridge.getPlayer(src)
        local ok = p and p.Functions.RemoveItem(item, qty, slot)
        local def = ok and qbItems() and qbItems()[item]
        if def then TriggerClientEvent('inventory:client:ItemBox', src, def, 'remove', qty) end
        return ok and true or false
    end
    if inv == 'esx' then
        local x = Bridge.getPlayer(src)
        if not x then return false end
        x.removeInventoryItem(item, qty)
        return true
    end
    return false
end

function Inv.setMetadata(src, slot, metadata)
    if inv == 'ox' then return exports.ox_inventory:SetMetadata(src, slot, metadata) end
    if inv == 'qs' then return exports['qs-inventory']:SetItemMetadata(src, slot, metadata) end
    if inv == 'qb' then
        local p = Bridge.getPlayer(src)
        local items = p and p.PlayerData.items
        if items and items[slot] then
            items[slot].info = metadata
            p.Functions.SetInventory(items)
        end
    end
end

-- Libelle d'un objet (nom technique si inconnu)
function Inv.label(item)
    if inv == 'ox' then
        local d = exports.ox_inventory:Items(item)
        return d and d.label or item
    end
    local list = Inv.items()
    local d = list and list[item]
    return d and d.label or item
end

-- Objets declares { [name] = { label, ... } } ; nil si inconnu
function Inv.items()
    if inv == 'ox' then return exports.ox_inventory:Items() end
    if inv == 'qs' then
        local ok, l = pcall(function() return exports['qs-inventory']:GetItemList() end)
        return ok and l or nil
    end
    if inv == 'qb' then return qbItems() end
    if inv == 'esx' and ESX.GetItems then
        local ok, l = pcall(ESX.GetItems)
        return ok and l or nil
    end
    return nil
end

-- Objet utilisable : cb(src, slot, metadata). Avec ox_inventory, declarer plutot server.export dans items.lua ;
-- ici on passe par le hook usingItem d'ox_inventory pour garder un seul code.
function Inv.registerUsable(item, cb)
    if inv == 'ox' then
        exports(('use_%s'):format(item), function(event, _, inventory, slot)
            if event == 'usingItem' then
                local s = exports.ox_inventory:GetSlot(inventory.id, slot)
                cb(inventory.id, slot, s and s.metadata)
                return false
            end
        end)
        return
    end
    local function call(src, data)
        data = type(data) == 'table' and data or {}
        cb(src, data.slot, data.info)
    end
    if inv == 'qs' then exports['qs-inventory']:CreateUsableItem(item, call)
    elseif fw == 'qbx' then exports.qbx_core:CreateUseableItem(item, call)
    elseif fw == 'qb' then QB.Functions.CreateUseableItem(item, call)
    elseif fw == 'esx' then ESX.RegisterUsableItem(item, function(src) cb(src) end) end
end

-- Coffre / stockage partage (ox : RegisterStash ; qb/qs : ouvert cote client avec Inv.openStash)
function Inv.registerStash(id, label, slots, weight, owner)
    if inv == 'ox' then exports.ox_inventory:RegisterStash(id, label, slots or 50, weight or 100000, owner) end
end

print(('[%s] framework : ^5%s^7 | inventaire : ^5%s^7'):format(resName, fw, inv))
