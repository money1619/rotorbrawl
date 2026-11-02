-- Accès à l'inventaire (docs/SECURITY.md §7) : possession des toupies et des pièces, verrous, hooks.
-- ox_inventory 2.45.0 : chemin complet (hooks : verrou des toupies, assemblage par glisser-déposer, identifiants).
-- qb-inventory / qs-inventory (pont AEOM, bridge/server.lua) : possession, achats et atelier par menus ; pas de
-- glisser-déposer ni de verrou d'inventaire (une toupie engagée est revérifiée par uid à chaque étape).
-- Sans inventaire : seules les toupies de test sont disponibles.
SpinArena = SpinArena or {}

local Store = Inv   -- pont AEOM (global), masqué ci-dessous par le module propre à ROTORBRAWL
local Inv = { locked = {}, hooks = {} }

Inv.ITEM_TOP = 'spin_top'
Inv.ITEM_PART = 'spin_part'
Inv.ITEM_REPAIR = 'spin_repair_kit'
Inv.ITEM_LAUNCHER = 'spin_launcher'
Inv.ITEM_PORTABLE = 'spin_portable_arena'

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function ox() return exports.ox_inventory end
local function isOx() return GetResourceState('ox_inventory') == 'started' end
Inv.isOx = isOx

-- Inventaire utilisable : ox_inventory, ou qb / qs par le pont
function Inv.available()
    return isOx() or (Store ~= nil and (Store.name == 'qb' or Store.name == 'qs'))
end

-- qb / qs : emplacements d'un objet dont les métadonnées vérifient match(metadata)
local function storeSlots(src, item, match)
    local out = {}
    for _, s in ipairs(Store.slots(src, item)) do
        local md = s.metadata or {}
        if not match or match(md) then out[#out + 1] = { slot = s.slot, count = s.count or 1, metadata = md } end
    end
    return out
end

-- Identifiant de toupie : préfixe ST, horodatage et aléa en base 36 (unicité garantie par la clé primaire)
local DIGITS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
local function base36(n)
    local s = ''
    repeat
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = n // 36
    until n == 0
    return s
end

function Inv.newUid()
    return ('ST%s%s'):format(base36(os.time()), base36(math.random(0, 36 ^ 6 - 1)))
end

Inv.UID_PATTERN = '^ST[0-9A-Z]+$'

-- Emplacements de toupies du joueur (une toupie par emplacement : l'objet n'est pas empilable)
function Inv.tops(src)
    if not Inv.available() then return {} end
    local slots = isOx() and (ox():GetSlotsWithItem(src, Inv.ITEM_TOP) or {}) or storeSlots(src, Inv.ITEM_TOP)
    local list = {}
    for _, slot in ipairs(slots) do
        local uid = slot.metadata and slot.metadata.uid
        if type(uid) == 'string' and uid:match(Inv.UID_PATTERN) then
            list[#list + 1] = { uid = uid, slot = slot.slot, metadata = slot.metadata }
        end
    end
    return list
end

function Inv.findTop(src, uid)
    for _, t in ipairs(Inv.tops(src)) do
        if t.uid == uid then return t end
    end
    return nil
end

function Inv.launcherCount(src)
    if not Inv.available() then return 0 end
    if not isOx() then return Store.count(src, Inv.ITEM_LAUNCHER) end
    return ox():GetItemCount(src, Inv.ITEM_LAUNCHER) or 0
end

-- Type du lanceur utilisé en match : celui du premier emplacement (le plus bas) qui contient un lanceur ;
-- un lanceur sans type (ancien objet) est le lanceur de base
function Inv.launcherType(src)
    local L = SpinArena.Parts.launchers
    if not Inv.available() then return L.default end
    local slots
    if isOx() then
        slots = ox():GetSlotsWithItem(src, Inv.ITEM_LAUNCHER) or {}
        table.sort(slots, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    else
        slots = storeSlots(src, Inv.ITEM_LAUNCHER)
    end
    local first = slots[1]
    local id = first and first.metadata and first.metadata.launcher
    if type(id) == 'string' and L.catalog[id] then return id end
    return L.default
end

-- Arène transportable : variante de table de l'objet spin_portable_arena (metadata.variant, 'pocket' par défaut) si le
-- joueur en porte un ; nil sinon. Seules les variantes marquées portable dans la config sont acceptées.
function Inv.portableVariant(src)
    if not Inv.available() then return nil end
    local slots
    if isOx() then
        slots = ox():GetSlotsWithItem(src, Inv.ITEM_PORTABLE) or {}
        table.sort(slots, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    else
        slots = storeSlots(src, Inv.ITEM_PORTABLE)
    end
    local first = slots[1]
    if not first then return nil end
    local id = first.metadata and first.metadata.variant
    local V = SpinArena.Config.arenaVariants
    if type(id) == 'string' and V[id] and V[id].portable then return id end
    return V.pocket and 'pocket' or nil   -- édition gratuite : pas de table transportable
end

function Inv.partCount(src, partId)
    if not Inv.available() then return 0 end
    if not isOx() then
        local n = 0
        for _, s in ipairs(storeSlots(src, Inv.ITEM_PART, function(md) return md.part == partId end)) do n = n + s.count end
        return n
    end
    -- Match the authoritative part id while allowing decorative shop metadata (label, description).
    return ox():GetItemCount(src, Inv.ITEM_PART, { part = partId }, false) or 0
end

function Inv.takePart(src, partId)
    if not isOx() then
        local s = storeSlots(src, Inv.ITEM_PART, function(md) return md.part == partId end)[1]
        return s ~= nil and Store.remove(src, Inv.ITEM_PART, 1, s.slot)
    end
    return ox():RemoveItem(src, Inv.ITEM_PART, 1, { part = partId }, nil, nil, false)
end

function Inv.givePart(src, partId)
    if not isOx() then return Store.add(src, Inv.ITEM_PART, 1, { part = partId }) end
    return ox():AddItem(src, Inv.ITEM_PART, 1, { part = partId })
end

function Inv.canCarryPart(src, partId)
    if not isOx() then return Store.canCarry(src, Inv.ITEM_PART, 1) end
    return ox():CanCarryItem(src, Inv.ITEM_PART, 1, { part = partId })
end

-- Nouvelle toupie montée dans l'inventaire : l'uid est fixé ici (le hook createItem le conserve)
function Inv.canCarryTop(src)
    if not isOx() then return Store.canCarry(src, Inv.ITEM_TOP, 1) end
    return ox():CanCarryItem(src, Inv.ITEM_TOP, 1)
end

function Inv.giveTop(src, uid, label)
    if not isOx() then return Store.add(src, Inv.ITEM_TOP, 1, { uid = uid, label = label }) end
    return ox():AddItem(src, Inv.ITEM_TOP, 1, { uid = uid, label = label })
end

-- Retire la toupie de SON emplacement (relu juste avant) ; rend la copie des métadonnées pour une compensation
function Inv.takeTop(src, uid)
    local t = Inv.findTop(src, uid)
    if not t then return nil end
    local meta = {}
    for k, v in pairs(t.metadata) do meta[k] = v end
    if not isOx() then
        if not Store.remove(src, Inv.ITEM_TOP, 1, t.slot) then return nil end
        return meta
    end
    if not ox():RemoveItem(src, Inv.ITEM_TOP, 1, nil, t.slot) then return nil end
    return meta
end

function Inv.giveTopBack(src, meta)
    if not isOx() then return Store.add(src, Inv.ITEM_TOP, 1, meta) end
    return ox():AddItem(src, Inv.ITEM_TOP, 1, meta)
end

function Inv.repairCount(src)
    if not Inv.available() then return 0 end
    if not isOx() then return Store.count(src, Inv.ITEM_REPAIR) end
    return ox():GetItemCount(src, Inv.ITEM_REPAIR) or 0
end

function Inv.takeRepair(src)
    if not isOx() then return Store.remove(src, Inv.ITEM_REPAIR, 1) end
    return ox():RemoveItem(src, Inv.ITEM_REPAIR, 1)
end

function Inv.giveRepair(src)
    if not isOx() then return Store.add(src, Inv.ITEM_REPAIR, 1) end
    return ox():AddItem(src, Inv.ITEM_REPAIR, 1)
end

-- Libellé affiché dans l'inventaire (décoratif : la base fait foi)
function Inv.describeTop(src, uid, label, description)
    local t = Inv.findTop(src, uid)
    if not t then return end
    local meta = {}
    for k, v in pairs(t.metadata) do meta[k] = v end
    meta.label, meta.description = label, description
    if not isOx() then return Store.setMetadata(src, t.slot, meta) end
    ox():SetMetadata(src, t.slot, meta)
end

-- Verrous en mémoire, lus par le hook swapItems (qui doit répondre sans attendre la base).
-- lock renvoie un jeton ; unlock avec ce jeton ne libère que son propre verrou.
function Inv.lock(uid, reason)
    local token = { reason = reason or true }
    Inv.locked[uid] = token
    return token
end

function Inv.unlock(uid, token)
    if token == nil or Inv.locked[uid] == token then Inv.locked[uid] = nil end
end

function Inv.registerHooks()
    if not isOx() then return end   -- hooks : ox_inventory seulement
    -- Une toupie engagée dans un match ou en cours d'atelier ne peut être ni déplacée, ni donnée, ni jetée
    Inv.hooks[#Inv.hooks + 1] = ox():registerHook('swapItems', function(payload)
        local slot = payload.fromSlot
        local uid = type(slot) == 'table' and slot.metadata and slot.metadata.uid
        if uid and Inv.locked[uid] then return false end
        return true
    end, { itemFilter = { [Inv.ITEM_TOP] = true } })
    -- Assemblage par glisser-déposer : une pièce déposée sur une toupie (ou l'inverse), un kit sur une toupie, deux
    -- pièces d'emplacements différents l'une sur l'autre. Le hook ne fait aucune attente : il annule l'échange et
    -- confie l'opération à un fil (server/parts.lua, Assembly.onSwap).
    Inv.hooks[#Inv.hooks + 1] = ox():registerHook('swapItems', function(payload)
        local A = SpinArena.Assembly
        if not A then return true end
        return A.onSwap(payload)
    end, { itemFilter = { [Inv.ITEM_TOP] = true, [Inv.ITEM_PART] = true, [Inv.ITEM_REPAIR] = true } })
    -- Icône par pièce (purement visuelle) : ox_inventory 2.45 affiche metadata.image (<imagepath>/<image>.png).
    -- Seulement pour les pièces listées dans Config.partIcons (fichier présent) ; sinon l'image générique de l'objet.
    Inv.hooks[#Inv.hooks + 1] = ox():registerHook('createItem', function(payload)
        local meta = payload.metadata
        if type(meta) ~= 'table' then return meta end
        local icons = SpinArena.Config and SpinArena.Config.partIcons or {}
        if type(meta.part) == 'string' and icons[meta.part] and meta.image == nil then
            meta.image = 'spin_part_' .. meta.part
        end
        return meta
    end, { itemFilter = { [Inv.ITEM_PART] = true } })
    -- Toute toupie créée sans identifiant en reçoit un (et un assemblage de départ selon metadata.kit)
    Inv.hooks[#Inv.hooks + 1] = ox():registerHook('createItem', function(payload)
        local meta = payload.metadata
        if type(meta) ~= 'table' then meta = {} end
        if type(meta.uid) ~= 'string' or not meta.uid:match(Inv.UID_PATTERN) then
            meta.uid = Inv.newUid()
            local kits = SpinArena.Parts.kits
            if not kits[meta.kit] then meta.kit = 'balance' end
            meta.label = meta.label or ('Toupie ' .. kits[meta.kit].label)
        end
        return meta
    end, { itemFilter = { [Inv.ITEM_TOP] = true } })
    log('hooks ox_inventory enregistrés (toupies verrouillées, assemblage par glisser-déposer, identifiants)')
end

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() or not isOx() then return end
    for _, id in ipairs(Inv.hooks) do pcall(function() ox():removeHooks(id) end) end
end)

SpinArena.Inventory = Inv
return Inv
