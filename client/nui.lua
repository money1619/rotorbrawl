-- ============================================================================
-- SPIN ARENA — Interface NUI HTML (web/index.html, web/style.css, web/app.js)
-- ============================================================================
-- Se greffe sur SpinArena.Client sans modifier le protocole serveur ni remplacer
-- la boutique sécurisée d'ox_inventory. Préserve le repli ox_lib lorsque les
-- natives NUI (SendNUIMessage / SetNuiFocus) ne sont pas présentes.
-- ============================================================================

SpinArena = SpinArena or {}

local NUI = SpinArena.NUI or {}
SpinArena.NUI = NUI

NUI.state = NUI.state or {
    open              = false,
    sessionId         = 0,
    tab               = 'home',
    focusUid          = nil,
    focusTournamentId = nil,
}
NUI.state.sessionId = tonumber(NUI.state.sessionId) or 0

local VALID_TABS = {
    home        = true,
    challenges  = true,
    leaderboard = true,
    tournaments = true,
    shop        = true, -- boutique unique : ouverte seulement depuis un vendeur (Client.openShop)
}

local function getClient()
    return SpinArena and SpinArena.Client
end

local function getParts()
    return SpinArena and SpinArena.Parts
end

local function getStats()
    return SpinArena and SpinArena.Stats
end

local function isParticipantInMatch()
    local C = getClient()
    return C ~= nil and C.state ~= nil and C.state.match ~= nil and C.state.match.role == 'participant'
end

function NUI.isAvailable()
    if NUI.forceDisabled == true then return false end
    return type(SendNUIMessage) == 'function' and type(SetNuiFocus) == 'function'
end

local function nextSession()
    NUI.state.sessionId = (tonumber(NUI.state.sessionId) or 0) + 1
    return NUI.state.sessionId
end

local function isSessionValid(sessionId)
    return NUI.state.open == true
        and NUI.state.sessionId == sessionId
        and not isParticipantInMatch()
        and NUI.isAvailable()
end

local function safeSendNui(payload)
    if type(SendNUIMessage) ~= 'function' then return false end
    local ok = pcall(SendNUIMessage, payload)
    return ok
end

local function safeSetFocus(hasFocus, hasCursor)
    if type(SetNuiFocus) ~= 'function' then return false end
    local ok = pcall(SetNuiFocus, hasFocus == true, hasCursor == true)
    return ok
end

-- dir : sens de rotation de la pièce (-1 = anneau inversé), ajouté en tête du résumé
local function formatModsSummary(mods, dir)
    local prefix = (tonumber(dir) == -1) and 'rotation gauche' or nil
    if type(mods) ~= 'table' or next(mods) == nil then
        return prefix or 'Aucun modificateur'
    end
    local keys = {}
    for k in pairs(mods) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = tonumber(mods[k]) or 0
        local sign = v >= 0 and '+' or ''
        out[#out + 1] = ('%s %s%s'):format(k, sign, tostring(v))
    end
    if prefix then table.insert(out, 1, prefix) end
    return table.concat(out, ', ')
end

local function isTopComplete(top)
    if type(top) ~= 'table' then return false end
    local statsMod = getStats()
    if statsMod and type(statsMod.validate) == 'function' then
        return statsMod.validate(top.parts) ~= nil
    end
    local partsCfg = getParts()
    local slots = (partsCfg and partsCfg.slots) or { 'core', 'ring', 'frame', 'tip' }
    if type(top.parts) ~= 'table' then return false end
    for i = 1, #slots do
        if type(top.parts[slots[i]]) ~= 'string' then return false end
    end
    return true
end

-- Calcule explicitement le coût et le budget d'un assemblage (y compris au-dessus du budget)
local function computePartsCostAndBudget(parts, wear, fallbackCost, defaultBudget)
    local C = getClient()
    local partsCfg = getParts() or {}
    local statsMod = getStats()
    local budget = tonumber(partsCfg.budget) or tonumber(defaultBudget) or 100

    if statsMod and type(statsMod.validate) == 'function' and type(parts) == 'table' then
        local validCost = statsMod.validate(parts)
        if tonumber(validCost) then
            return tonumber(validCost), budget
        end
    end

    if C and type(C.computeTopStatsAndCost) == 'function' and type(parts) == 'table' then
        local _, computedCost, computedBudget = C.computeTopStatsAndCost(parts, wear)
        if tonumber(computedBudget) then
            budget = tonumber(computedBudget)
        end
        if tonumber(computedCost) then
            return tonumber(computedCost), budget
        end
    end

    local catalog = type(partsCfg.catalog) == 'table' and partsCfg.catalog or {}
    local slots = type(partsCfg.slots) == 'table' and partsCfg.slots or { 'core', 'ring', 'frame', 'tip' }
    if type(parts) == 'table' then
        local sum = 0
        local foundAny = false
        for i = 1, #slots do
            local pId = parts[slots[i]]
            local pDef = type(pId) == 'string' and catalog[pId] or nil
            if pDef and tonumber(pDef.cost) then
                sum = sum + tonumber(pDef.cost)
                foundAny = true
            end
        end
        if foundAny then
            return sum, budget
        end
    end

    return tonumber(fallbackCost) or 0, budget
end

-- Construit la photographie complète des données pour l'interface HTML
-- (4 emplacements réels core/ring/frame/tip, budget et caractéristiques depuis SpinArena.Parts / SpinArena.Stats)
-- Boutique (maquette de Money) : noms et couleurs AFFICHÉS des 5 kits. Les identifiants techniques (attack, defense…)
-- ne changent pas : les toupies déjà possédées restent valables. Correspondance proposée, à valider par Money.
NUI.SHOP_DISPLAY = {
    attack    = { name = 'VOLTIS', color = '#1e8bff' },
    defense   = { name = 'TITAN',  color = '#2ecc71' },
    endurance = { name = 'UMBRA',  color = '#9b59ff' },
    balance   = { name = 'KYROS',  color = '#f1c40f' },
    mobility  = { name = 'FLARE',  color = '#ff7a1a' },
}

-- Barres affichées (0 à 100), calculées UNIQUEMENT depuis les valeurs du catalogue (SpinArena.Parts) et les bornes
-- du moteur (SpinArena.Stats.BOUNDS) : attaque = atk, défense = def, stabilité = stab, mobilité = mob ;
-- endurance = frottement de pointe inversé (moins de frottement, rotation plus longue). Indicatif, pas une mesure.
local function shopBars(stats)
    local Stats = getStats()
    local B = Stats and Stats.BOUNDS
    if type(stats) ~= 'table' or type(B) ~= 'table' then return nil end
    local function norm(v, k, invert)
        local b = B[k]
        if type(v) ~= 'number' or type(b) ~= 'table' or b[2] == b[1] then return nil end
        local x = (v - b[1]) / (b[2] - b[1])
        if invert then x = 1 - x end
        return math.floor(math.max(0, math.min(1, x)) * 100 + 0.5)
    end
    return {
        attack = norm(stats.atk, 'atk'), defense = norm(stats.def, 'def'),
        endurance = norm(stats.tipFric, 'tipFric', true), stability = norm(stats.stab, 'stab'),
        mobility = norm(stats.mob, 'mob'),
    }
end

local EFFECT_LABELS = { atk = 'Attaque', def = 'Défense', stab = 'Stabilité', mob = 'Mobilité', tipFric = 'Frottement de pointe',
    m = 'Masse', kI = 'Inertie', w0 = 'Rotation de départ', r = 'Rayon', trac = 'Adhérence', damp = 'Amortissement', v0 = 'Lancer' }
local function shopEffects(mods)
    local keys, out = {}, {}
    for k in pairs(type(mods) == 'table' and mods or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = tonumber(mods[k]) or 0
        out[#out + 1] = { key = k, label = EFFECT_LABELS[k] or k, value = v, text = (v >= 0 and '+' or '') .. tostring(v) }
    end
    return out
end

-- Ajoute aux articles du catalogue serveur ce que l'écran de boutique affiche (sans rien changer à l'achat) :
-- toupie → kit, nom affiché, couleur, assemblage, barres, coût ; pièce → emplacement, coût, effets
function NUI.decorateShop(categories)
    local P, Stats = getParts(), getStats()
    if type(categories) ~= 'table' then return {} end
    for _, cat in ipairs(categories) do
        for _, it in ipairs(type(cat.items) == 'table' and cat.items or {}) do
            local key = type(it.id) == 'string' and it.id:match('^[%w_]+:([%w_]+)$') or nil
            if cat.key == 'tops' and key and P and P.kits and P.kits[key] then
                local kit = P.kits[key]
                local disp = NUI.SHOP_DISPLAY[key] or {}
                it.kit, it.display, it.color = key, disp.name or kit.label, disp.color
                it.family = kit.label
                local parts = {}
                for _, slot in ipairs(P.slots or {}) do
                    local id = kit.parts[slot]
                    parts[#parts + 1] = { slot = slot, slotLabel = P.slotLabels and P.slotLabels[slot] or slot,
                                          id = id, label = P.catalog[id] and P.catalog[id].label or id }
                end
                it.parts = parts
                if Stats and Stats.compute then
                    local ok, s, cost = pcall(Stats.compute, kit.parts, 0)
                    if ok and s then it.bars, it.cost, it.budget = shopBars(s), cost, P.budget end
                end
            elseif cat.key == 'launchers' and P and P.launchers then
                -- « spin_launcher » = lanceur de base ; « spin_launcher_<type> » = les autres
                local id = (key == 'spin_launcher') and P.launchers.default or (key or ''):match('^spin_launcher_([%w]+)$')
                local def = id and P.launchers.catalog[id]
                local L = SpinArena and SpinArena.Launch
                if def then
                    it.launcher, it.display, it.description = id, def.label, def.desc
                    it.effects = (L and L.describe and L.describe(def) or {})
                end
            elseif cat.key == 'parts' and key and P and P.catalog and P.catalog[key] then
                local def = P.catalog[key]
                it.part, it.slot = key, def.slot
                it.slotLabel = P.slotLabels and P.slotLabels[def.slot] or def.slot
                it.cost, it.budget = def.cost, P.budget
                it.effects = shopEffects(def.mods)
                if def.dir == -1 then
                    -- Rotation gauche : affichée comme un effet (valeur positive : ce n'est pas un défaut)
                    table.insert(it.effects, 1, { key = 'dir', label = 'Sens de rotation', value = 1, text = 'gauche' })
                end
            end
        end
    end
    return categories
end

function NUI.buildSnapshot(opts)
    opts = type(opts) == 'table' and opts or {}
    local C = getClient()
    local partsCfg = getParts() or {}
    local catalog = type(partsCfg.catalog) == 'table' and partsCfg.catalog or {}
    local slots = type(partsCfg.slots) == 'table' and partsCfg.slots or { 'core', 'ring', 'frame', 'tip' }
    local slotLabels = type(partsCfg.slotLabels) == 'table' and partsCfg.slotLabels or {
        core  = 'Noyau',
        ring  = 'Lame',
        frame = 'Verrou',
        tip   = 'Embout',
    }
    local budget = tonumber(partsCfg.budget) or 100
    local wearMax = tonumber(partsCfg.wearMax) or 40
    local wearFree = tonumber(partsCfg.wearFree) or 10
    local paintsRaw = type(partsCfg.paints) == 'table' and partsCfg.paints or {}
    local kitsRaw = type(partsCfg.kits) == 'table' and partsCfg.kits or {}

    local paintList = {}
    local paintKeys = {}
    for k in pairs(paintsRaw) do paintKeys[#paintKeys + 1] = k end
    table.sort(paintKeys)
    for i = 1, #paintKeys do
        local k = paintKeys[i]
        local p = paintsRaw[k] or {}
        paintList[#paintList + 1] = {
            key   = k,
            label = tostring(p.label or k),
            color = type(p.color) == 'table' and p.color or { 195, 202, 212 },
        }
    end

    local ownedBySlot = {}
    for i = 1, #slots do
        local s = slots[i]
        local list = (C and type(C.getOwnedPartsBySlot) == 'function') and C.getOwnedPartsBySlot(s) or {}
        local enriched = {}
        for j = 1, #list do
            local it = list[j]
            enriched[#enriched + 1] = {
                part        = it.part,
                label       = it.label,
                slot        = it.slot,
                cost        = tonumber(it.cost) or 0,
                count       = tonumber(it.count) or 0,
                mods        = it.mods or {},
                modsSummary = formatModsSummary(it.mods, it.dir or (catalog[it.part] and catalog[it.part].dir)),
            }
        end
        ownedBySlot[s] = enriched
    end

    local topsRes = (C and type(C.fetchTops) == 'function' and not opts.skipFetchTops) and C.fetchTops() or nil
    local rawTops = (topsRes and topsRes.ok and type(topsRes.tops) == 'table' and topsRes.tops)
        or (C and C.state and type(C.state.tops) == 'table' and C.state.tops)
        or {}

    if C and not C.selectedTopUid then
        for i = 1, #rawTops do
            local t = rawTops[i]
            if type(t) == 'table' and type(t.uid) == 'string' and not t.locked and isTopComplete(t) then
                C.selectedTopUid = t.uid
                break
            end
        end
    end

    local tops = {}
    for i = 1, #rawTops do
        local t = rawTops[i]
        if type(t) == 'table' and type(t.uid) == 'string' then
            local fStats = (C and type(C.formatTopStats) == 'function') and C.formatTopStats(t) or nil
            local cost, topBudget = computePartsCostAndBudget(
                t.parts,
                t.wear,
                fStats and fStats.cost or nil,
                budget
            )
            local famKey = tostring(t.family or 'balance')
            local famLabel = (kitsRaw[famKey] and kitsRaw[famKey].label) or famKey
            local paintKey = tostring(t.paint or 'titanium')
            local paintDef = paintsRaw[paintKey]
            local paintLabel = (paintDef and paintDef.label) or paintKey
            local paintColor = (paintDef and type(paintDef.color) == 'table' and paintDef.color) or { 195, 202, 212 }
            local complete = isTopComplete(t)

            local slotDetails = {}
            for sIdx = 1, #slots do
                local slot = slots[sIdx]
                local currentPartId = type(t.parts) == 'table' and t.parts[slot] or nil
                local currentDef = currentPartId and catalog[currentPartId] or nil
                local candidates = {}
                local slotOwned = ownedBySlot[slot] or {}
                for cIdx = 1, #slotOwned do
                    local item = slotOwned[cIdx]
                    local nextParts = {}
                    if type(t.parts) == 'table' then
                        for pk, pv in pairs(t.parts) do nextParts[pk] = pv end
                    end
                    nextParts[slot] = item.part
                    local nextCost, nextBudget = computePartsCostAndBudget(nextParts, t.wear, cost, topBudget)
                    local overBudget = nextCost > nextBudget
                    local isEquipped = (item.part == currentPartId)
                    candidates[#candidates + 1] = {
                        part        = item.part,
                        label       = item.label,
                        cost        = item.cost,
                        count       = item.count,
                        modsSummary = item.modsSummary,
                        nextCost    = nextCost,
                        budget      = nextBudget,
                        overBudget  = overBudget,
                        isEquipped  = isEquipped,
                        canEquip    = (not t.locked) and (not isEquipped) and (not overBudget),
                    }
                end

                slotDetails[#slotDetails + 1] = {
                    slot        = slot,
                    slotLabel   = slotLabels[slot] or slot,
                    partId      = currentPartId,
                    partLabel   = (currentDef and currentDef.label) or tostring(currentPartId or 'Aucune'),
                    cost        = (currentDef and tonumber(currentDef.cost)) or 0,
                    modsSummary = formatModsSummary(currentDef and currentDef.mods, currentDef and currentDef.dir),
                    candidates  = candidates,
                }
            end

            tops[#tops + 1] = {
                uid         = t.uid,
                name        = tostring(t.name or t.uid),
                family      = famKey,
                familyLabel = famLabel,
                paint       = paintKey,
                paintLabel  = paintLabel,
                paintColor  = paintColor,
                wear        = tonumber(t.wear) or 0,
                wearMax     = wearMax,
                wearFree    = wearFree,
                wins        = tonumber(t.wins) or 0,
                losses      = tonumber(t.losses) or 0,
                draws       = tonumber(t.draws) or 0,
                locked      = t.locked == true,
                complete    = complete,
                isSelected  = (C and C.selectedTopUid == t.uid) or false,
                cost        = cost,
                budget      = topBudget,
                bars        = fStats or {
                    atkPct       = 50,
                    defPct       = 50,
                    stabPct      = 50,
                    endurancePct = 50,
                    mobPct       = 50,
                    wearPct      = 0,
                    budgetPct    = math.min(100, math.floor((cost / math.max(1, topBudget)) * 100 + 0.5)),
                    cost         = cost,
                    maxBudget    = topBudget,
                },
                slots       = slotDetails,
            }
        end
    end

    if C and not opts.skipFetchState and type(C.fetchState) == 'function' then
        pcall(C.fetchState)
    end
    local incoming = {}
    if C and C.state and type(C.state.incoming) == 'table' then
        for i = 1, #C.state.incoming do
            local inc = C.state.incoming[i]
            if type(inc) == 'table' and tonumber(inc.id) then
                incoming[#incoming + 1] = {
                    id       = tonumber(inc.id),
                    from     = tonumber(inc.from),
                    fromName = tostring(inc.fromName or '?'),
                    top      = tostring(inc.top or '?'),
                }
            end
        end
    end
    local outgoing = nil
    if C and C.state and type(C.state.outgoing) == 'table' and tonumber(C.state.outgoing.id) then
        local out = C.state.outgoing
        outgoing = {
            id     = tonumber(out.id),
            to     = tonumber(out.to or out.target),
            toName = tostring(out.toName or ('#' .. tostring(out.to or out.target or '?'))),
            top    = tostring(out.top or '?'),
        }
    end

    local lbRes = (C and opts.includeLeaderboard and not opts.skipFetchLeaderboard and type(C.fetchLeaderboard) == 'function')
        and C.fetchLeaderboard()
        or (C and C.state and C.state.leaderboard)
        or nil
    local leaderboard = {
        season = tonumber(lbRes and lbRes.season) or 1,
        me     = (lbRes and type(lbRes.me) == 'table') and lbRes.me or nil,
        top    = (lbRes and type(lbRes.top) == 'table') and lbRes.top or {},
    }

    local trRes = (C and opts.includeTournaments and not opts.skipFetchTournaments and type(C.fetchTournaments) == 'function')
        and C.fetchTournaments()
        or (C and C.state and C.state.tournaments)
        or nil
    local tournaments = {
        mine        = trRes and trRes.mine or nil,
        tournaments = (trRes and type(trRes.tournaments) == 'table') and trRes.tournaments or {},
    }

    return {
        tab               = NUI.state.tab or 'home',
        focusUid          = NUI.state.focusUid,
        focusTournamentId = NUI.state.focusTournamentId,
        selectedTopUid    = C and C.selectedTopUid or nil,
        catalog = {
            slots      = slots,
            slotLabels = slotLabels,
            budget     = budget,
            wearMax    = wearMax,
            wearFree   = wearFree,
            paints     = paintList,
        },
        tops        = tops,
        challenges  = {
            incoming = incoming,
            outgoing = outgoing,
        },
        leaderboard = leaderboard,
        tournaments = tournaments,
        shop        = NUI.state.shop,
    }
end

function NUI.open(tab, opts)
    if isParticipantInMatch() then
        return false
    end
    if not NUI.isAvailable() then
        return false
    end
    opts = type(opts) == 'table' and opts or {}
    local targetTab = (type(tab) == 'string' and VALID_TABS[tab]) and tab or 'home'
    local session = nextSession()
    NUI.state.open = true
    NUI.state.tab = targetTab
    if opts.focusUid ~= nil then
        NUI.state.focusUid = tostring(opts.focusUid)
    end
    if opts.focusTournamentId ~= nil then
        NUI.state.focusTournamentId = tonumber(opts.focusTournamentId)
    end

    if type(lib) == 'table' and type(lib.hideContext) == 'function' then
        pcall(lib.hideContext, false)
    end

    local snapOpts = {
        includeLeaderboard   = (targetTab == 'leaderboard'),
        includeTournaments   = (targetTab == 'tournaments'),
        skipFetchTops        = opts.skipFetchTops,
        skipFetchState       = opts.skipFetchState,
        skipFetchLeaderboard = opts.skipFetchLeaderboard,
        skipFetchTournaments = opts.skipFetchTournaments,
    }
    local data = NUI.buildSnapshot(snapOpts)
    if not isSessionValid(session) then
        if not NUI.state.open or isParticipantInMatch() then
            NUI.state.open = false
            safeSetFocus(false, false)
        end
        return false
    end
    safeSetFocus(true, true)
    safeSendNui({
        action = 'open',
        tab    = targetTab,
        data   = data,
    })
    return true
end

function NUI.refresh(opts)
    local session = NUI.state.sessionId
    if not isSessionValid(session) then
        return false
    end
    opts = type(opts) == 'table' and opts or {}
    local data = NUI.buildSnapshot({
        includeLeaderboard = opts.includeLeaderboard or (NUI.state.tab == 'leaderboard'),
        includeTournaments = opts.includeTournaments or (NUI.state.tab == 'tournaments'),
        skipFetchTops      = opts.skipFetchTops,
        skipFetchState     = opts.skipFetchState,
    })
    if not isSessionValid(session) then
        if not NUI.state.open or isParticipantInMatch() then
            NUI.state.open = false
            safeSetFocus(false, false)
        end
        return false
    end
    safeSendNui({
        action = 'update',
        tab    = NUI.state.tab,
        data   = data,
    })
    return true
end

function NUI.close(reason)
    local wasOpen = NUI.state.open
    nextSession()
    NUI.state.open = false
    NUI.state.shop = nil -- la boutique se rouvre seulement auprès d'un vendeur
    safeSetFocus(false, false)
    if wasOpen or NUI.isAvailable() then
        safeSendNui({
            action = 'close',
            reason = tostring(reason or 'closed'),
        })
    end
    return true
end

local function snapshotIfSessionValid(session, snapOpts)
    if not isSessionValid(session) then
        if not NUI.state.open or isParticipantInMatch() then
            NUI.state.open = false
            safeSetFocus(false, false)
        end
        return nil
    end
    local snap = NUI.buildSnapshot(snapOpts)
    if not isSessionValid(session) then
        if not NUI.state.open or isParticipantInMatch() then
            NUI.state.open = false
            safeSetFocus(false, false)
        end
        return nil
    end
    return snap
end

-- Enregistrement sécurisé des callbacks NUI (chaque callback valide les entrées et répond toujours à cb)
local function registerSafeCallback(name, handler)
    if type(RegisterNUICallback) ~= 'function' then return end
    RegisterNUICallback(name, function(data, cb)
        local reply = function(res)
            if type(cb) == 'function' then
                pcall(cb, res)
            end
        end
        if type(data) ~= 'table' then
            data = {}
        end
        local ok, res = pcall(handler, data)
        if not ok or type(res) ~= 'table' then
            reply({ ok = false, code = 'error' })
            return
        end
        reply(res)
    end)
end

function NUI.registerCallbacks()
    local C = getClient()

    registerSafeCallback('nui:close', function(_data)
        NUI.close('user_close')
        return { ok = true }
    end)

    registerSafeCallback('nui:switchTab', function(data)
        local session = NUI.state.sessionId
        if not isSessionValid(session) then
            return { ok = false, code = 'closed', closed = true }
        end
        local tab = type(data.tab) == 'string' and data.tab or nil
        if not tab or not VALID_TABS[tab] then
            return { ok = false, code = 'invalid' }
        end
        NUI.state.tab = tab
        if type(data.focusUid) == 'string' then
            NUI.state.focusUid = data.focusUid
        end
        if tonumber(data.focusTournamentId) then
            NUI.state.focusTournamentId = tonumber(data.focusTournamentId)
        end
        local snap = snapshotIfSessionValid(session, {
            includeLeaderboard = (tab == 'leaderboard'),
            includeTournaments = (tab == 'tournaments'),
        })
        if not snap then
            return { ok = false, code = 'closed', closed = true }
        end
        return { ok = true, data = snap }
    end)

    registerSafeCallback('nui:refresh', function(data)
        local session = NUI.state.sessionId
        if not isSessionValid(session) then
            return { ok = false, code = 'closed', closed = true }
        end
        local tab = (type(data.tab) == 'string' and VALID_TABS[data.tab]) and data.tab or NUI.state.tab
        NUI.state.tab = tab
        local snap = snapshotIfSessionValid(session, {
            includeLeaderboard = (tab == 'leaderboard') or (data.includeLeaderboard == true),
            includeTournaments = (tab == 'tournaments') or (data.includeTournaments == true),
        })
        if not snap then
            return { ok = false, code = 'closed', closed = true }
        end
        return { ok = true, data = snap }
    end)

    -- Boutique : absente du menu F7 NUI (accessible uniquement sur la carte via PNJ + ox_target)
    registerSafeCallback('nui:openShop', function(_data)
        return { ok = false, code = 'vendor_only' }
    end)

    -- Achat depuis l'onglet Boutique : identifiant d'article et quantité seulement (prix et catalogue serveur)
    registerSafeCallback('nui:shopBuy', function(data)
        local shop = NUI.state.shop
        if not C or not shop or NUI.state.tab ~= 'shop' or isParticipantInMatch() then
            return { ok = false, code = 'shop_closed' }
        end
        local item = type(data.item) == 'string' and data.item or ''
        local count = math.floor(tonumber(data.count) or 1)
        local res = C.buyShop(shop.id, item, count)
        if type(res) ~= 'table' then res = { ok = false, code = 'error' } end
        if tonumber(res.money) then shop.money = tonumber(res.money) end
        if res.ok then NUI.refresh({ skipFetchState = true }) end
        return { ok = res.ok == true, code = tostring(res.code or 'error'), money = shop.money,
                 count = res.count, paid = res.paid, item = res.item }
    end)

    registerSafeCallback('nui:selectTop', function(data)
        local session = NUI.state.sessionId
        if not C then return { ok = false, code = 'error' } end
        local uid = type(data.uid) == 'string' and data.uid or nil
        if not uid or uid == '' then
            return { ok = false, code = 'invalid' }
        end
        local topsRes = C.fetchTops()
        local list = (topsRes and topsRes.ok and type(topsRes.tops) == 'table') and topsRes.tops or {}
        local found = nil
        for i = 1, #list do
            if type(list[i]) == 'table' and list[i].uid == uid then
                found = list[i]
                break
            end
        end
        if not found then
            return { ok = false, code = 'not_found' }
        end
        if found.locked then
            return { ok = false, code = 'top_locked' }
        end
        if not isTopComplete(found) then
            return { ok = false, code = 'incomplete_top' }
        end
        C.selectedTopUid = uid
        NUI.state.focusUid = uid
        return {
            ok   = true,
            uid  = uid,
            data = snapshotIfSessionValid(session, { skipFetchTops = true, skipFetchState = true }),
        }
    end)

    -- « Mes toupies » retiré (19/10/2026) : plus aucun rappel d'atelier dans l'interface. Renommer, peindre et démonter
    -- passent par les boutons de l'objet dans ox_inventory (client/main.lua), assemblage et réparation par glisser-déposer.

    registerSafeCallback('nui:challengePlayer', function(data)
        local session = NUI.state.sessionId
        if not C or type(C.challenge) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local targetId = tonumber(data.targetId)
        local top = type(data.top) == 'string' and data.top or (C and C.selectedTopUid) or nil
        if not targetId or targetId < 1 or not top or top == '' then
            return { ok = false, code = 'invalid' }
        end
        local res = C.challenge(math.floor(targetId), top)
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            data = snapshotIfSessionValid(session, { skipFetchTops = true }),
        }
    end)

    registerSafeCallback('nui:respondChallenge', function(data)
        local session = NUI.state.sessionId
        if not C or type(C.respond) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local id = tonumber(data.id)
        local accept = (data.accept == true)
        local top = type(data.top) == 'string' and data.top or (C and C.selectedTopUid) or nil
        if not id or id < 1 or (accept and (not top or top == '')) then
            return { ok = false, code = 'invalid' }
        end
        local res = C.respond(math.floor(id), accept, top)
        if type(res) == 'table' and res.ok and accept then
            NUI.close('challenge_accepted')
            return { ok = true, closed = true }
        end
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            data = snapshotIfSessionValid(session, { skipFetchTops = true }),
        }
    end)

    registerSafeCallback('nui:cancelChallenge', function(data)
        local session = NUI.state.sessionId
        if not C or type(C.cancelChallenge) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local id = tonumber(data.id)
        local res = C.cancelChallenge(id)
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            data = snapshotIfSessionValid(session, { skipFetchTops = true }),
        }
    end)

    registerSafeCallback('nui:createTournament', function(data)
        local session = NUI.state.sessionId
        if not C or type(C.createTournament) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local name = type(data.name) == 'string' and data.name or nil
        local size = tonumber(data.size)
        local minutes = tonumber(data.minutes)
        if not name or not size or not minutes then
            return { ok = false, code = 'invalid' }
        end
        local res = C.createTournament(name, math.floor(size), math.floor(minutes))
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            id   = type(res) == 'table' and res.id or nil,
            data = snapshotIfSessionValid(session, { includeTournaments = true, skipFetchTops = true }),
        }
    end)

    registerSafeCallback('nui:joinTournament', function(data)
        local session = NUI.state.sessionId
        if not C or type(C.joinTournament) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local id = tonumber(data.id)
        local top = type(data.top) == 'string' and data.top or (C and C.selectedTopUid) or nil
        if not id or id < 1 or not top or top == '' then
            return { ok = false, code = 'invalid' }
        end
        local res = C.joinTournament(math.floor(id), top)
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            data = snapshotIfSessionValid(session, { includeTournaments = true, skipFetchTops = true }),
        }
    end)

    registerSafeCallback('nui:leaveTournament', function(_data)
        local session = NUI.state.sessionId
        if not C or type(C.leaveTournament) ~= 'function' then
            return { ok = false, code = 'error' }
        end
        local res = C.leaveTournament()
        return {
            ok   = type(res) == 'table' and res.ok == true or false,
            code = type(res) == 'table' and res.code or 'error',
            data = snapshotIfSessionValid(session, { includeTournaments = true, skipFetchTops = true }),
        }
    end)
end

-- Branchement sur les points d'entrée existants de SpinArena.Client avec repli ox_lib intact
function NUI.attachToClient()
    local C = getClient()
    if not C or C._nuiAttached then return false end
    C._nuiAttached = true

    local origOpenHome        = C.openHome
    local origOpenChallenges  = C.openChallenges
    local origOpenLeaderboard = C.openLeaderboard
    local origOpenTournaments = C.openTournaments
    local origOpenShop        = C.openShop
    local origChallengeEvent  = C.onChallengeEvent

    -- fn attend le serveur (lib.callback.await) : deux appels peuvent se chevaucher. Le vrai showContext est
    -- capturé une seule fois et masqué par un compteur, sinon le second appel restaurerait le stub pour de bon.
    local realShowContext, suppressOxContext = nil, 0
    local function callWithoutShowingOxContext(fn, ...)
        if type(lib) ~= 'table' or type(lib.showContext) ~= 'function' then
            return fn(...)
        end
        if not realShowContext then
            realShowContext = lib.showContext
            lib.showContext = function(...)
                if suppressOxContext > 0 then return end
                return realShowContext(...)
            end
        end
        suppressOxContext = suppressOxContext + 1
        local ok, res = pcall(fn, ...)
        suppressOxContext = suppressOxContext - 1
        if not ok then error(res) end
        return res
    end

    C.openHome = function()
        if isParticipantInMatch() then return false end
        if NUI.isAvailable() then
            local preSession = NUI.state.sessionId
            callWithoutShowingOxContext(origOpenHome)
            if NUI.state.sessionId ~= preSession or isParticipantInMatch() then
                return false
            end
            return NUI.open('home')
        end
        return origOpenHome()
    end

    C.openChallenges = function()
        if isParticipantInMatch() then return { ok = false, code = 'in_match' } end
        if NUI.isAvailable() then
            local preSession = NUI.state.sessionId
            local res = callWithoutShowingOxContext(origOpenChallenges)
            if type(res) == 'table' and res.ok and NUI.state.sessionId == preSession and not isParticipantInMatch() then
                NUI.open('challenges', { skipFetchState = true })
            end
            return res
        end
        return origOpenChallenges()
    end

    C.openLeaderboard = function()
        if isParticipantInMatch() then return { ok = false, code = 'in_match' } end
        if NUI.isAvailable() then
            local preSession = NUI.state.sessionId
            local res = callWithoutShowingOxContext(origOpenLeaderboard)
            if type(res) == 'table' and res.ok and NUI.state.sessionId == preSession and not isParticipantInMatch() then
                NUI.open('leaderboard', { skipFetchLeaderboard = true, skipFetchTops = true, skipFetchState = true })
            end
            return res
        end
        return origOpenLeaderboard()
    end

    C.openTournaments = function(focusId)
        if isParticipantInMatch() then return { ok = false, code = 'in_match' } end
        if NUI.isAvailable() then
            local preSession = NUI.state.sessionId
            local res = callWithoutShowingOxContext(origOpenTournaments, focusId)
            if type(res) == 'table' and res.ok and NUI.state.sessionId == preSession and not isParticipantInMatch() then
                NUI.open('tournaments', { focusTournamentId = focusId, skipFetchTournaments = true, skipFetchState = true })
            end
            return res
        end
        return origOpenTournaments(focusId)
    end

    -- Vendeur → boutique unique : l'onglet Boutique de l'interface Arena, avec ses catégories internes
    C.openShop = function(shopId, categoryKey)
        if isParticipantInMatch() then return { ok = false, code = 'in_match' } end
        local res = origOpenShop(shopId, categoryKey)
        if type(res) ~= 'table' or not res.ok then return res end
        local info = type(res.info) == 'table' and res.info or {}
        local point = type(res.point) == 'table' and res.point or {}
        NUI.state.shop = {
            id         = tonumber(res.id) or 0,
            label      = type(point.label) == 'string' and point.label or nil,
            categories = NUI.decorateShop(type(info.catalog) == 'table' and info.catalog or {}),
            money      = tonumber(info.money),
            category   = type(categoryKey) == 'string' and categoryKey or nil,
        }
        if NUI.isAvailable() then NUI.open('shop', { skipFetchTops = true, skipFetchState = true }) end
        return res
    end

    C.onChallengeEvent = function(payload)
        local handled = origChallengeEvent(payload)
        if handled and NUI.state.open then
            NUI.refresh({ skipFetchTops = true, skipFetchState = true })
        end
        return handled
    end

    if type(AddEventHandler) == 'function' then
        local P = SpinArena and SpinArena.Protocol
        local evMatch = (P and P.ev and P.ev.match) or 'spin_arena:cl:match'
        AddEventHandler(evMatch, function(payload)
            if type(payload) == 'table' and (payload.role == nil or payload.role == 'participant') then
                NUI.close('match_start')
            end
        end)

        AddEventHandler('ox_inventory:openedInventory', function()
            NUI.close('inventory_open')
        end)

        AddEventHandler('ox_inventory:openInventory', function()
            NUI.close('inventory_open')
        end)

        AddEventHandler('onResourceStop', function(resourceName)
            local current = (type(GetCurrentResourceName) == 'function') and GetCurrentResourceName() or nil
            if not current or resourceName == current then
                NUI.close('resource_stop')
            end
        end)
    end

    if type(AddStateBagChangeHandler) == 'function' then
        pcall(AddStateBagChangeHandler, 'invOpen', nil, function(_, _, value)
            if value == true then
                NUI.close('inventory_open')
            end
        end)
    end

    return true
end

NUI.registerCallbacks()
NUI.attachToClient()

return NUI
