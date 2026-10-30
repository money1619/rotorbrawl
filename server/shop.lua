-- Boutique SPIN ARENA : une seule boutique par point de vente, ouverte dans l'interface Arena (onglet Boutique,
-- catégories internes). Le catalogue et les prix viennent de config/server.lua, jamais du client ; chaque achat
-- (Shop.buy) revérifie la boutique, la distance de 3 m, le prix, l'argent et la place, puis débite et livre via
-- ox_inventory 2.45.0 (remboursement si la livraison échoue). Une toupie achetée reçoit son identifiant par le
-- hook createItem. Les boutiques natives d'ox_inventory (RegisterShop) ne sont plus utilisées : elles ajoutaient
-- leurs propres cibles au même endroit que le vendeur.
SpinArena = SpinArena or {}

local Shop = { points = {}, active = false, hooks = false, unresolved = {} }
Shop.TYPE = 'spinarena'
Shop.CATEGORY_ORDER = { 'tops', 'launchers', 'parts', 'repair' }
Shop.CATEGORIES = {
    tops      = { type = 'spinarena_tops',      name = 'SPIN ARENA — Toupies',          item = 'spin_top',        label = 'Toupies' },
    launchers = { type = 'spinarena_launchers', name = 'SPIN ARENA — Lanceurs',         item = 'spin_launcher',   label = 'Lanceurs' },
    parts     = { type = 'spinarena_parts',     name = 'SPIN ARENA — Pièces détachées', item = 'spin_part',       label = 'Pièces détachées' },
    repair    = { type = 'spinarena_repair',    name = 'SPIN ARENA — Réparation',       item = 'spin_repair_kit', label = 'Réparation' },
}
-- Objets non empilables : un seul exemplaire par achat
Shop.SINGLE = { spin_top = true, spin_launcher = true }

local function cfg() return SpinArena.ServerConfig.shop end

-- Chemin sans ox_inventory (QBCore / qs) : pont AEOM et module d'inventaire
local Bridge, Inv = SpinArena.Bridge, SpinArena.Inventory

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function resolveShopType(shopType)
    if shopType == Shop.TYPE then
        return nil, true
    end
    for key, cat in pairs(Shop.CATEGORIES) do
        if shopType == cat.type then
            return cat, true, key
        end
    end
    return nil, false
end

local function resolveCategoryKey(categoryKey)
    if categoryKey == nil then return nil end
    if Shop.CATEGORIES[categoryKey] then return categoryKey end
    for key, cat in pairs(Shop.CATEGORIES) do
        if categoryKey == cat.type then return key end
    end
    return false
end

-- Garde côté serveur sur la boutique native : une boutique désactivée (ou dont les points de vente ont disparu)
-- ne peut plus ni s'ouvrir ni vendre, même si ox_inventory garde son ancien enregistrement. Une toupie ne se vend
-- que si les toupies réelles sont actives (identifiant attribué par le hook createItem, ligne en base).
-- Vérification répétée à l'achat : une interface ouverte ne vaut pas autorisation à distance.
function Shop.canAccess(source, shopId)
    if not Shop.active then return false end
    if #Shop.points == 0 then return cfg().anywhere == true end
    local index = tonumber(shopId)
    if not index or index ~= math.floor(index) then return false end
    local point = Shop.points[index]
    if not point then return false end
    local ped = GetPlayerPed(tonumber(source) or 0)
    if not ped or ped == 0 then return false end
    local position = GetEntityCoords(ped)
    if not position then return false end
    local dx, dy, dz = position.x - point.x, position.y - point.y, position.z - point.z
    return dx * dx + dy * dy + dz * dz <= 9.0 -- trois mètres, même limite que l'interaction
end

function Shop.registerHooks()
    if Shop.hooks then return end
    local ox = exports.ox_inventory
    ox:registerHook('openShop', function(payload)
        local cat, isArenaShop = resolveShopType(payload and payload.shopType)
        if not isArenaShop then return true end
        if not Shop.canAccess(payload.source, payload.shopId) then return false end
        if cat and cat.item == 'spin_top' and not SpinArena.Tops.enabled() then return false end
        return true
    end)
    ox:registerHook('buyItem', function(payload)
        local cat, isArenaShop = resolveShopType(payload and payload.shopType)
        if not isArenaShop then return true end
        if not Shop.canAccess(payload.source, payload.shopId) then return false end
        if cat and payload.itemName ~= cat.item then return false end
        if payload.itemName == 'spin_top' and not SpinArena.Tops.enabled() then return false end
        return true
    end)
    Shop.hooks = true
end

-- Articles : une toupie par famille, le lanceur, chaque pièce du catalogue, le kit de réparation.
-- Si categoryKey ('tops', 'launchers', 'parts', 'repair') est fourni, ne renvoie que les articles de cette catégorie.
function Shop.items(categoryKey)
    local resolvedKey = resolveCategoryKey(categoryKey)
    if resolvedKey == false then return {} end

    local P, prices = SpinArena.Parts, cfg().prices
    local list = {}
    if resolvedKey == nil or resolvedKey == 'tops' then
        local families = {}
        for key in pairs(P.kits) do families[#families + 1] = key end
        table.sort(families)
        -- Sans base ni hooks d'inventaire, une toupie n'aurait pas d'identifiant : elle n'est pas proposée
        if SpinArena.Tops.enabled() then
            for _, key in ipairs(families) do
                list[#list + 1] = { name = 'spin_top', price = prices.top, metadata = { kit = key, label = 'Toupie ' .. P.kits[key].label } }
            end
        end
    end
    if resolvedKey == nil or resolvedKey == 'launchers' then
        local L = P.launchers
        for _, id in ipairs(L.order) do
            local def = L.catalog[id]
            list[#list + 1] = { name = 'spin_launcher', price = math.floor(prices.launcher * (def.priceMult or 1) + 0.5),
                                metadata = { launcher = id, label = def.label } }
        end
    end
    if resolvedKey == nil or resolvedKey == 'parts' then
        local parts = {}
        for id in pairs(P.catalog) do parts[#parts + 1] = id end
        table.sort(parts, function(a, b)
            local A, B = P.catalog[a], P.catalog[b]
            if A.slot ~= B.slot then return A.slot < B.slot end
            return a < b
        end)
        for _, id in ipairs(parts) do
            local def = P.catalog[id]
            list[#list + 1] = { name = 'spin_part', price = prices.partBase + prices.partPerPoint * def.cost,
                                metadata = { part = id, label = def.label } }
        end
    end
    if resolvedKey == nil or resolvedKey == 'repair' then
        list[#list + 1] = { name = 'spin_repair_kit', price = prices.repair }
    end
    return list
end

-- Points de vente : emplacements vendeur configurés (et arènes fixes uniquement si includeFixedArenas est activé)
function Shop.locations()
    local points = {}
    if cfg().includeFixedArenas == true then
        local fixed = {}
        for _, e in pairs(SpinArena.Arenas.fixed or {}) do fixed[#fixed + 1] = e end
        table.sort(fixed, function(a, b) return a.name < b.name end)
        for _, e in ipairs(fixed) do points[#points + 1] = { x = e.x, y = e.y, z = e.z + 1.0, label = e.name } end
    end
    for _, p in ipairs(cfg().locations) do points[#points + 1] = { x = p.x, y = p.y, z = p.z, label = p.label, heading = p.heading, ped = p.ped } end
    -- Points de vente des extensions (server/extensions.lua), validés à l'enregistrement
    local Ext = SpinArena.Extensions
    for _, p in ipairs(Ext and Ext.shopPoints and Ext.shopPoints() or {}) do
        points[#points + 1] = { x = p.x, y = p.y, z = p.z, label = p.label, heading = p.heading, ped = p.ped }
    end
    return points
end

-- Identifiant stable d'un article : « catégorie:clé » (toupie : famille ; pièce : identifiant du catalogue)
local function articleId(catKey, entry)
    local meta = entry.metadata or {}
    -- Lanceur : l'identifiant historique `launchers:spin_launcher` reste celui du lanceur de base
    if meta.launcher and meta.launcher ~= SpinArena.Parts.launchers.default then
        return catKey .. ':' .. entry.name .. '_' .. meta.launcher
    end
    return catKey .. ':' .. tostring(meta.kit or meta.part or entry.name)
end

-- Catalogue de la boutique unique, dans l'ordre des catégories : ce que l'interface affiche et ce que Shop.buy accepte
function Shop.catalog()
    local categories = {}
    for _, catKey in ipairs(Shop.CATEGORY_ORDER) do
        local items = {}
        for _, entry in ipairs(Shop.items(catKey)) do
            local meta = entry.metadata or {}
            items[#items + 1] = {
                id = articleId(catKey, entry), name = entry.name, price = entry.price,
                label = meta.label or Shop.CATEGORIES[catKey].label, single = Shop.SINGLE[entry.name] == true,
            }
        end
        categories[#categories + 1] = { key = catKey, label = Shop.CATEGORIES[catKey].label, items = items }
    end
    return categories
end

-- Article du catalogue serveur correspondant à un identifiant envoyé par le client (rien d'autre n'est repris du client)
function Shop.article(id)
    local catKey = type(id) == 'string' and id:match('^([%w_]+):') or nil
    if not catKey or not Shop.CATEGORIES[catKey] then return nil end
    for _, entry in ipairs(Shop.items(catKey)) do
        if articleId(catKey, entry) == id then return entry, catKey end
    end
    return nil
end

-- Argent et livraison : ox_inventory directement (chemin d'origine), sinon le pont AEOM (qb / qs).
-- Avec qb / qs, la monnaie 'money' = espèces du framework ; un autre nom = objet d'inventaire.
local function isOx() return SpinArena.Inventory.isOx() end
local function cashAccount() local c = cfg().currency or 'money' return c == 'money' and 'cash' or nil end

local function money(src)
    if not isOx() then
        local acc = cashAccount()
        local ok, n = pcall(function() return acc and Bridge.getMoney(src, acc) or Inv.count(src, cfg().currency) end)
        return ok and tonumber(n) or 0
    end
    local ok, n = pcall(function() return exports.ox_inventory:GetItemCount(src, cfg().currency or 'money') end)
    return ok and tonumber(n) or 0
end

-- Même contrat que les exports d'ox_inventory : true / false, ou erreur levée
local Store = {
    canCarry = function(src, name, count, metadata)
        if isOx() then return exports.ox_inventory:CanCarryItem(src, name, count, metadata) end
        return Inv.canCarry(src, name, count)
    end,
    debit = function(src, total)
        if isOx() then return exports.ox_inventory:RemoveItem(src, cfg().currency or 'money', total) end
        local acc = cashAccount()
        if acc then return Bridge.removeMoney(src, acc, total, 'spin_arena') end
        return Inv.remove(src, cfg().currency, total)
    end,
    credit = function(src, total)
        if isOx() then return exports.ox_inventory:AddItem(src, cfg().currency or 'money', total) end
        local acc = cashAccount()
        if acc then return Bridge.addMoney(src, acc, total, 'spin_arena') end
        return Inv.add(src, cfg().currency, total)
    end,
    deliver = function(src, name, count, metadata)
        if isOx() then return exports.ox_inventory:AddItem(src, name, count, metadata) end
        -- sans hook createItem : une toupie reçoit ici son identifiant (et un assemblage de départ selon kit)
        if name == 'spin_top' then
            local md = {}
            for k, v in pairs(metadata or {}) do md[k] = v end
            local kits = SpinArena.Parts.kits
            if not kits[md.kit] then md.kit = 'balance' end
            md.uid = SpinArena.Inventory.newUid()
            md.label = md.label or ('Toupie ' .. kits[md.kit].label)
            metadata = md
        end
        return Inv.add(src, name, count, metadata)
    end,
}

-- Achat dans la boutique unique. Ordre : boutique active → distance au point de vente → article du catalogue serveur
-- → quantité → toupies réelles actives → argent → place → débit → livraison (remboursement si la livraison échoue)
function Shop.buy(src, shopId, itemId, count)
    local C = SpinArena.Protocol.codes
    if not Shop.active then return { ok = false, code = C.shop_closed } end
    if not Shop.canAccess(src, shopId) then return { ok = false, code = C.too_far } end
    local entry, catKey = Shop.article(itemId)
    if not entry then return { ok = false, code = C.invalid } end
    count = math.floor(tonumber(count) or 1)
    if count < 1 or count > (tonumber(cfg().maxCount) or 10) then return { ok = false, code = C.invalid } end
    if Shop.SINGLE[entry.name] then count = 1 end
    if entry.name == 'spin_top' and not SpinArena.Tops.enabled() then return { ok = false, code = C.db_unavailable } end
    local total = entry.price * count
    if money(src) < total then return { ok = false, code = C.no_money, money = money(src) } end
    local metadata = entry.metadata and { kit = entry.metadata.kit, part = entry.metadata.part,
                                          launcher = entry.metadata.launcher, label = entry.metadata.label } or nil
    if not Store.canCarry(src, entry.name, count, metadata) then return { ok = false, code = C.inventory_full } end
    -- Débit, livraison et remboursement sont des appels d'exports synchrones (aucune attente entre eux) : la source
    -- ne peut pas changer de joueur pendant l'achat. Un refus (false) est un état connu : on s'arrête ou on rembourse.
    -- Une erreur levée ne prouve pas l'absence d'effet (l'export a pu agir puis échouer) : l'achat devient INCERTAIN,
    -- consigné durablement pour régularisation, sans compensation automatique.
    local identifier = SpinArena.Bridge and SpinArena.Bridge.identifier and SpinArena.Bridge.identifier(src) or nil
    local function uncertain(stage, err, extra)
        Shop.recordUnresolved({ src = src, identifier = identifier, item = itemId, count = count, amount = total,
            stage = stage, error = tostring(err), detail = extra })
        return { ok = false, code = C.error, uncertain = true, money = money(src) }
    end
    local paidOk, paid = pcall(function() return Store.debit(src, total) end)
    if not paidOk then return uncertain('debit', paid) end
    if not paid then return { ok = false, code = C.no_money, money = money(src) } end
    local addOk, added = pcall(function() return Store.deliver(src, entry.name, count, metadata) end)
    if not addOk then return uncertain('livraison', added, 'débit effectué') end
    if added then
        log('achat : %s a payé %d pour %s ×%d (%s)', src, total, tostring(itemId), count, catKey)
        return { ok = true, code = C.ok, item = itemId, count = count, paid = total, money = money(src) }
    end
    -- Livraison refusée après débit : remboursement, dont le résultat est vérifié lui aussi
    local refundOk, refunded = pcall(function() return Store.credit(src, total) end)
    if not refundOk then return uncertain('remboursement', refunded, 'débit effectué, livraison refusée') end
    if refunded then
        log('achat annulé pour %s : %s ×%d refusé par l\'inventaire, %d remboursé', src, tostring(itemId), count, total)
        return { ok = false, code = C.inventory_full, refunded = true, money = money(src) }
    end
    -- Débit effectué, livraison et remboursement refusés : non résolu (état connu, aucune nouvelle tentative)
    Shop.recordUnresolved({ src = src, identifier = identifier, item = itemId, count = count, amount = total,
        stage = 'remboursement', error = 'refusé par l\'inventaire', detail = 'débit effectué, livraison refusée' })
    return { ok = false, code = C.error, refunded = false, money = money(src) }
end

-- Achats non résolus ou incertains : en mémoire (/spin_admin achats) et ajoutés à data/shop_unresolved.log
-- (une ligne JSON par cas), pour qu'un administrateur régularise à la main
Shop.UNRESOLVED_FILE = 'data/shop_unresolved.log'
function Shop.recordUnresolved(entry)
    entry.at = os.time()
    Shop.unresolved[#Shop.unresolved + 1] = entry
    log('ACHAT À RÉGULARISER (%s) pour %s [%s] : %d pour %s ×%d — %s (%s)', entry.stage, tostring(entry.src),
        tostring(entry.identifier or '?'), entry.amount, tostring(entry.item), entry.count, entry.error, tostring(entry.detail or ''))
    local res = GetCurrentResourceName()
    local ok = pcall(function()
        local previous = LoadResourceFile(res, Shop.UNRESOLVED_FILE) or ''
        local line = json.encode(entry)
        if not SaveResourceFile(res, Shop.UNRESOLVED_FILE, previous .. line .. '\n', -1) then error('écriture refusée') end
    end)
    if not ok then log('ATTENTION : achat à régulariser non écrit dans %s (reste en mémoire et dans ce journal)', Shop.UNRESOLVED_FILE) end
end

-- (Ré)calcule les points de vente ; appelé au démarrage et après chaque changement d'arène fixe
function Shop.register()
    Shop.active = false
    if not SpinArena.Inventory.available() then
        Shop.points = {}
        return false
    end
    if isOx() then Shop.registerHooks() end
    if not cfg().enabled then
        Shop.points = {}
        return false
    end
    local points = Shop.locations()
    if #points == 0 and not cfg().anywhere then
        Shop.points = {}
        log('boutique : aucun point de vente (aucune arène fixe ni emplacement configuré)')
        return false
    end
    Shop.points = points
    Shop.active = true
    log('boutique : %d article(s), %s', #Shop.items(), #points > 0 and (#points .. ' point(s) de vente') or 'ouverte partout')
    return true
end

-- Ce que le client doit savoir pour proposer l'ouverture (ox_target / vendeur) et synchroniser les stations fixes
function Shop.info(src)
    local categories = {}
    for k, cat in pairs(Shop.CATEGORIES) do
        categories[k] = cat.type
    end
    local bucket = 0
    if src and SpinArena.Bridge and type(SpinArena.Bridge.context) == 'function' then
        local ctx = SpinArena.Bridge.context(src)
        if ctx and ctx.bucket ~= nil then bucket = ctx.bucket end
    end
    local stations = (SpinArena.Arenas and type(SpinArena.Arenas.stations) == 'function')
        and SpinArena.Arenas.stations(bucket) or {}
    return {
        ok = true, code = SpinArena.Protocol.codes.ok,
        enabled = Shop.active,
        type = Shop.TYPE,
        categories = categories,
        categoryOrder = Shop.CATEGORY_ORDER,
        anywhere = cfg().anywhere and #Shop.points == 0,
        points = Shop.points,
        stations = stations,
        catalog = Shop.active and Shop.catalog() or {},
        money = (Shop.active and src) and money(src) or nil,
    }
end

-- Versement d'espèces par le serveur (gains de tournoi) : même chemin que le remboursement d'un achat
function Shop.pay(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    return Store.credit(src, amount) and true or false
end

SpinArena.Shop = Shop
return Shop
