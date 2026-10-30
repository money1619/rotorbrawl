-- Toupies et atelier (phase 4, docs/ARCHITECTURE.md §14, docs/SECURITY.md §7 et §8).
-- La possession vient d'ox_inventory, la configuration de la base ; le client n'envoie que des identifiants.
SpinArena = SpinArena or {}

local Tops = {}

local Db, Inv, Stats, Bridge = SpinArena.Database, SpinArena.Inventory, SpinArena.Stats, SpinArena.Bridge
local function P() return SpinArena.Parts end
local function codes() return SpinArena.Protocol.codes end
local function fail(code) return { ok = false, code = code } end

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

-- Mode réel : inventaire et base disponibles et prêts
function Tops.enabled()
    return Inv.available() and Db.available() and Db.ready
end

local function paintColor(paint)
    local p = P().paints[paint] or P().paints.titanium
    return p.color
end

-- Ligne en base pour une toupie possédée ; créée avec l'assemblage de départ si elle n'existe pas encore
local function row(src, item)
    local top, err = Db.getTop(item.uid)
    if err then return nil, err end
    if not top then
        local kit = P().kits[item.metadata.kit] or P().kits.balance
        top, err = Db.ensureTop(item.uid, Bridge.identifier(src), kit.parts, kit.label)
        if err or not top then return nil, err or 'insert' end
    end
    if not top.parts then return nil, 'corrupt' end
    return top
end

-- Toupie possédée → définition de combat ; nil et code si refusée
local function definition(top)
    local stats, err = Stats.compute(top.parts, top.wear)
    if not stats then return nil, err end
    return {
        label = top.name, color = paintColor(top.paint), stats = stats,
        family = Stats.family(top.parts), model = Stats.model(top.parts), uid = top.uid, parts = top.parts,
    }
end

-- Liste des toupies du joueur pour l'interface (aucun identifiant de joueur)
function Tops.list(src)
    if not Tops.enabled() then return { ok = true, code = codes().ok, enabled = false, tops = {} } end
    local list = {}
    for _, item in ipairs(Inv.tops(src)) do
        local top = row(src, item)
        if top then
            local def = definition(top)
            list[#list + 1] = {
                uid = top.uid, name = top.name, paint = top.paint, parts = top.parts,
                family = def and def.family, wear = top.wear, wins = top.wins, losses = top.losses, draws = top.draws,
                locked = top.locked_match ~= nil or Inv.locked[top.uid] ~= nil,
                stats = def and def.stats,
            }
        end
    end
    return { ok = true, code = codes().ok, enabled = true, tops = list }
end

-------------------------------------------------------------------------------
-- Source des toupies pour les matchs
-------------------------------------------------------------------------------

local function isProfile(key)
    return SpinArena.ServerConfig.allowedTops[key] == true
end

-- Règle de jeu : un joueur ne combat qu'avec une toupie COMPLÈTE qu'il possède (les quatre pièces, valides et
-- dans le budget). Les profils de test ne sont acceptés que si allowTestProfiles est vrai (instance de test).
-- Lit la base : à appeler depuis un fil ; l'appelant revérifie son état après l'attente.
function Tops.check(src, key)
    if isProfile(key) then
        if SpinArena.ServerConfig.allowTestProfiles then return true end
        return false, codes().no_top
    end
    if type(key) ~= 'string' or not key:match(Inv.UID_PATTERN) then return false, codes().invalid end
    if not Tops.enabled() then return false, codes().db_unavailable end
    if SpinArena.RankingSQL and SpinArena.RankingSQL.blockedReason then return false, codes().db_unavailable end
    local identifier = Bridge.identifier(src)
    local item = Inv.findTop(src, key)
    if not item then return false, codes().no_top end
    if Inv.locked[key] then return false, codes().top_locked end
    if SpinArena.ServerConfig.requireLauncher ~= false and Inv.launcherCount(src) < 1 then return false, codes().no_launcher end
    local top, err = row(src, item)
    if not top then return false, err == 'db_unavailable' and codes().db_unavailable or codes().error end
    if top.locked_match then return false, codes().top_locked end
    if not Stats.validate(top.parts) then return false, codes().top_invalid end
    -- Pendant la lecture : la toupie a pu changer de mains, être verrouillée, ou le joueur changer de personnage
    if Bridge.identifier(src) ~= identifier then return false, codes().error end
    if Inv.locked[key] then return false, codes().top_locked end
    if not Inv.findTop(src, key) then return false, codes().no_top end
    if SpinArena.ServerConfig.requireLauncher ~= false and Inv.launcherCount(src) < 1 then return false, codes().no_launcher end
    return true
end

-- Résolution au moment de créer le match : relit tout, puis verrouille la toupie (mémoire et base)
function Tops.resolve(src, key, matchId)
    local ok, code = Tops.check(src, key)
    if not ok then return nil, code end
    if isProfile(key) then return SpinArena.Config.testTops[key] end
    local identifier = Bridge.identifier(src)
    local token = Inv.lock(key, matchId)
    local function unlock() Inv.unlock(key, token) end
    local item = Inv.findTop(src, key)
    if not item then
        unlock()
        return nil, codes().no_top
    end
    local top, err = row(src, item)
    if not top then
        unlock()
        return nil, err == 'db_unavailable' and codes().db_unavailable or codes().error
    end
    local locked = Db.lockTop(key, matchId)
    if not locked then
        unlock()
        return nil, codes().top_locked
    end
    -- La toupie a pu changer de mains pendant l'attente de la base
    if Bridge.identifier(src) ~= identifier or not Inv.findTop(src, key) then
        Db.unlockTop(key, matchId)
        unlock()
        return nil, codes().no_top
    end
    if SpinArena.ServerConfig.requireLauncher ~= false and Inv.launcherCount(src) < 1 then
        Db.unlockTop(key, matchId)
        unlock()
        return nil, codes().no_launcher
    end
    local def, derr = definition(top)
    if not def then
        Db.unlockTop(key, matchId)
        unlock()
        log('toupie %s inutilisable : %s', key, tostring(derr))
        return nil, codes().top_invalid
    end
    return def
end

-- Revalidation sans base pendant la préparation d'une manche : la toupie est toujours verrouillée par CE match,
-- toujours dans l'inventaire du joueur, et il a toujours un lanceur
function Tops.revalidate(src, key, matchId)
    if isProfile(key) then return true end
    local lock = Inv.locked[key]
    if not lock or lock.reason ~= matchId then return false, codes().top_locked end
    if not Inv.findTop(src, key) then return false, codes().no_top end
    if SpinArena.ServerConfig.requireLauncher ~= false and Inv.launcherCount(src) < 1 then return false, codes().no_launcher end
    return true
end

function Tops.release(key, matchId)
    if isProfile(key) or type(key) ~= 'string' then return end
    Inv.unlock(key)
    if Db.available() then CreateThread(function() Db.unlockTop(key, matchId) end) end
end

-- Fin de match : usure et compteurs des toupies réelles (écriture dans un fil, sans bloquer le match)
function Tops.onFinished(summary)
    if not summary.tops then return end
    CreateThread(function()
        for side, key in ipairs(summary.tops) do
            if not isProfile(key) and Db.available() then
                local outcome = summary.winner == nil and 'draw' or (summary.winner == side and 'win' or 'loss')
                if summary.reason ~= 'no_contest' then
                    Db.recordTopResult(key, outcome)
                    Tops.refreshDescription(key, summary.players and summary.players[side] and summary.players[side].identifier)
                end
            end
        end
    end)
end

-- Description de l'objet (« Famille : … — usure N ») relue en base après le match, pour le propriétaire s'il est en
-- ligne et possède toujours cette toupie (identifiant revalidé) ; sinon elle le sera à la prochaine opération
function Tops.refreshDescription(uid, identifier)
    if type(identifier) ~= 'string' or type(GetPlayers) ~= 'function' then return false end
    local top = Db.getTop(uid)
    if not top or not top.parts then return false end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and Bridge.identifier(src) == identifier and Inv.findTop(src, uid) then
            local fam = Stats.family(top.parts)
            Inv.describeTop(src, uid, top.name, ('Famille : %s — usure %d'):format(P().kits[fam].label, top.wear or 0))
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Atelier : chaque action relit la toupie, prend un verrou et journalise si l'inventaire bouge
-------------------------------------------------------------------------------

local Workshop = {}

-- Toupie possédée et libre en base ; l'appelant tient déjà le verrou mémoire
local function ownedTop(src, uid)
    local item = Inv.findTop(src, uid)
    if not item then return nil, codes().no_top end
    local top, err = row(src, item)
    if not top then return nil, err == 'db_unavailable' and codes().db_unavailable or codes().error end
    if top.locked_match then return nil, codes().top_locked end
    if not Inv.findTop(src, uid) then return nil, codes().no_top end
    return top
end

local function refreshLabel(src, top)
    local fam = Stats.family(top.parts)
    Inv.describeTop(src, top.uid, top.name, ('Famille : %s — usure %d'):format(P().kits[fam].label, top.wear or 0))
end

-- Erreur qui interrompt une opération : `review` = effet inconnu, l'opération part en revue et rien n'est rendu
local Abort = {}
local function abort(code, review) error(setmetatable({ code = code, review = review }, Abort), 0) end

-- Journal « owed » : copie du payload de l'opération + liste des objets dus ; identifiant marqué pour la livraison
local Owed = { pendingIds = {}, busy = {} }
local function oweJournal(opId, from, payload, list, identifier)
    local data = {}
    for k, v in pairs(type(payload) == 'table' and payload or {}) do data[k] = v end
    data.owed = list
    local ok = opId and Db.opOwe(opId, from, data)
    if ok then
        Owed.pendingIds[identifier] = true
        log('objets dus à %s (opération %s) : %s', tostring(identifier), tostring(opId), table.concat(list, ', '))
    end
    return ok
end

-- Fin d'une opération interrompue. Objets pris et AUCUNE écriture tentée (identité changée, déconnexion, etc.) :
-- état certain → dus au joueur. Écriture tentée sans réponse, journal bloqué : revue par un administrateur.
local function settle(ctx, res)
    if not ctx.opId or ctx.status == 'review' or ctx.status == 'owed' then return end
    -- Interrompue avant tout retrait (déconnexion pendant l'ouverture du journal) : rien n'a bougé, pas de revue
    if ctx.status == 'pending' and #ctx.held == 0 then
        pcall(Db.opMove, ctx.opId, 'pending', 'failed')
        return
    end
    if res.review and ctx.status == 'item_taken' and not ctx.written and #ctx.held > 0 then
        local called, owed = pcall(oweJournal, ctx.opId, 'item_taken', ctx.payload, ctx.held, ctx.identifier)
        if called and owed then return end
    end
    if res.review then pcall(Db.opMove, ctx.opId, ctx.status, 'review') end
end

-- Opération d'atelier (docs/SECURITY.md §8). Le verrou de la toupie et l'identité du joueur sont pris AVANT toute
-- attente ; `prepare(ctx)` relit la toupie, `steps(ctx)` fait les mouvements journalisés. L'identité est revérifiée
-- (ctx.same) avant chaque mouvement d'inventaire, compensations comprises. Seul ce verrou est rendu à la fin.
local function workshop(src, uid, op, prepare, steps)
    if not Tops.enabled() then return fail(codes().db_unavailable) end
    if Inv.locked[uid] then return fail(codes().top_locked) end
    local identifier = Bridge.identifier(src)
    local token = Inv.lock(uid, 'workshop')
    local ctx = { src = src, uid = uid, identifier = identifier, held = {}, written = false }
    function ctx.same()
        if Bridge.identifier(src) ~= identifier or Inv.locked[uid] ~= token then abort(codes().error, true) end
    end
    function ctx.move(from, to)
        local moved, err = Db.opMove(ctx.opId, from, to)
        if not moved then
            log('atelier : journal %s %s → %s impossible (%s), opération à revoir', tostring(ctx.opId), from, to, tostring(err))
            abort(codes().error, true)
        end
        ctx.status = to
    end
    -- Objets dus au joueur (état certain) : journal « owed » avec la liste, livrés plus tard (Owed.deliver)
    function ctx.owe(from, list)
        if not oweJournal(ctx.opId, from, ctx.payload, list, identifier) then abort(codes().error, true) end
        ctx.status = 'owed'
    end

    local ok, res = pcall(function()
        local top, code = ownedTop(src, uid)
        if not top then abort(code) end
        ctx.top = top
        local payload, early = prepare(ctx)
        if early then return early end
        ctx.payload = payload
        ctx.same()
        local opId, err = Db.opStart(identifier, uid, op, payload)
        if not opId then abort(err == 'db_unavailable' and codes().db_unavailable or codes().error) end
        ctx.opId, ctx.status = opId, 'pending'
        ctx.same()
        return steps(ctx)
    end)
    Inv.unlock(uid, token)
    if ok then return res end
    if getmetatable(res) ~= Abort then
        log('atelier : erreur inattendue (opération %s) : %s', tostring(ctx.opId), tostring(res))
        res = { code = codes().error, review = ctx.opId ~= nil }
    end
    settle(ctx, res)
    return fail(res.code)
end

-- Rend un objet pris si l'écriture a été refusée de façon certaine ; sinon il reste dû (liste au journal)
local function compensate(ctx, give, owed)
    ctx.same()
    if give() then ctx.move('item_taken', 'compensated') else ctx.owe('item_taken', owed) end
end

-- Remplace une pièce : la nouvelle sort de l'inventaire, l'ancienne y revient
function Workshop.equip(src, uid, partId)
    local part = P().catalog[partId]
    if not part then return fail(codes().invalid) end
    local parts, old
    return workshop(src, uid, 'equip', function(ctx)
        old = ctx.top.parts[part.slot]
        if old == partId then return nil, { ok = true, code = codes().ok } end
        parts = {}
        for k, v in pairs(ctx.top.parts) do parts[k] = v end
        parts[part.slot] = partId
        -- Toupie en montage (emplacements vides) : pièces connues, à leur place, dans le budget
        local okStats, why
        if Stats.isComplete(parts) then okStats, why = Stats.compute(parts, ctx.top.wear)
        else okStats, why = Stats.validatePartial(parts) end
        if not okStats then abort(why == 'over_budget' and codes().over_budget or codes().invalid) end
        if Inv.partCount(src, partId) < 1 then abort(codes().no_part) end
        if old and not Inv.canCarryPart(src, old) then abort(codes().inventory_full) end
        return { slot = part.slot, new = partId, old = old }
    end, function(ctx)
        if not Inv.takePart(src, partId) then
            ctx.move('pending', 'failed')
            return fail(codes().no_part)
        end
        ctx.held = { 'p:' .. partId }
        ctx.move('pending', 'item_taken')
        ctx.same()
        ctx.written = true
        local saved, err = Db.setParts(uid, parts, ctx.top.version)
        if err then
            -- Réponse incertaine (délai, connexion) : l'écriture a peut-être eu lieu, on ne rend rien
            log('atelier : écriture incertaine pour %s (%s), opération %s à revoir', uid, tostring(err), tostring(ctx.opId))
            abort(codes().error, true)
        end
        if not saved then
            compensate(ctx, function() return Inv.givePart(src, partId) end, { 'p:' .. partId })
            return fail(codes().busy)
        end
        if old == nil then
            ctx.move('item_taken', 'done')       -- emplacement vide : aucune pièce à rendre
        else
            ctx.move('item_taken', 'returning')
            ctx.same()
            if Inv.givePart(src, old) then
                ctx.move('returning', 'done')
            else
                ctx.owe('returning', { 'p:' .. old })
                log('atelier : pièce %s due à %s (opération %s)', old, ctx.identifier, tostring(ctx.opId))
            end
        end
        ctx.top.parts, ctx.top.version = parts, ctx.top.version + 1
        refreshLabel(src, ctx.top)
        return { ok = true, code = codes().ok }
    end)
end

-- Répare : un kit de réparation remet l'usure à zéro
function Workshop.repair(src, uid)
    return workshop(src, uid, 'repair', function(ctx)
        if (ctx.top.wear or 0) == 0 then return nil, { ok = true, code = codes().ok } end
        if Inv.repairCount(src) < 1 then abort(codes().no_part) end
        return { wear = ctx.top.wear }
    end, function(ctx)
        if not Inv.takeRepair(src) then
            ctx.move('pending', 'failed')
            return fail(codes().no_part)
        end
        ctx.held = { 'r' }
        ctx.move('pending', 'item_taken')
        ctx.same()
        ctx.written = true
        local saved, err = Db.setField(uid, 'wear', 0, ctx.top.version)
        if err then abort(codes().error, true) end
        if not saved then
            compensate(ctx, function() return Inv.giveRepair(src) end, { 'r' })
            return fail(codes().busy)
        end
        ctx.move('item_taken', 'done')
        ctx.top.wear, ctx.top.version = 0, ctx.top.version + 1
        refreshLabel(src, ctx.top)
        return { ok = true, code = codes().ok }
    end)
end

-- Démonte une toupie : l'objet sort de l'inventaire, la ligne est supprimée, toutes ses pièces reviennent.
-- Hors match et hors verrou (workshop). Écriture refusée de façon certaine → toupie rendue telle quelle ;
-- réponse incertaine → opération en revue, rien n'est rendu à l'aveugle ; pièce non rendue → due (journal).
function Workshop.disassemble(src, uid)
    local list, meta
    return workshop(src, uid, 'disassemble', function(ctx)
        list = {}
        for _, slot in ipairs(P().slots) do
            local id = ctx.top.parts[slot]
            if id then list[#list + 1] = id end
        end
        for _, id in ipairs(list) do
            if not Inv.canCarryPart(src, id) then abort(codes().inventory_full) end
        end
        return { parts = list }
    end, function(ctx)
        meta = Inv.takeTop(src, uid)
        if not meta then
            ctx.move('pending', 'failed')
            return fail(codes().no_top)
        end
        ctx.held = { 't:' .. uid }
        ctx.move('pending', 'item_taken')
        ctx.same()
        ctx.written = true
        local deleted, err = Db.deleteTop(uid, ctx.top.version)
        if err then
            log('démontage : suppression incertaine pour %s (%s), opération %s à revoir', uid, tostring(err), tostring(ctx.opId))
            abort(codes().error, true)
        end
        if not deleted then
            compensate(ctx, function() return Inv.giveTopBack(src, meta) end, { 't:' .. uid })
            return fail(codes().busy)
        end
        ctx.move('item_taken', 'returning')
        local owed = {}
        for _, id in ipairs(list) do
            ctx.same()
            if not Inv.givePart(src, id) then owed[#owed + 1] = id end
        end
        if #owed == 0 then
            ctx.move('returning', 'done')
        else
            local codesOwed = {}
            for i, id in ipairs(owed) do codesOwed[i] = 'p:' .. id end
            ctx.owe('returning', codesOwed)
            log('démontage : pièces %s dues à %s (opération %s)', table.concat(owed, ', '), ctx.identifier, tostring(ctx.opId))
        end
        return { ok = true, code = codes().ok, parts = list }
    end)
end

-- Modification sans mouvement d'inventaire : verrou et relecture, pas de journal
local function simpleEdit(src, uid, field, value)
    return workshop(src, uid, 'edit', function(ctx)
        local saved, err = Db.setField(uid, field, value, ctx.top.version)
        if err then abort(codes().error) end
        if not saved then abort(codes().busy) end
        ctx.top[field] = value
        if field == 'name' then refreshLabel(src, ctx.top) end
        return nil, { ok = true, code = codes().ok }
    end, function() end)
end

-- Nom d'une toupie : 1 à 24 CARACTÈRES (pas octets) en UTF-8 valide ; lettres et chiffres ASCII, espace, tiret,
-- apostrophe, et les lettres accentuées du français (minuscules et majuscules), avec au moins une lettre ou un
-- chiffre et sans espace en tête ni en fin. Tout autre caractère, une séquence
-- UTF-8 invalide ou tronquée, ou une forme trop longue (surlongue) est refusé.
local NAME_MAX_CHARS, NAME_MAX_BYTES = 24, 64
local NAME_EXTRA = {}
for _, cp in ipairs({ 0xE0, 0xE2, 0xE4, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEE, 0xEF, 0xF4, 0xF6, 0xF9, 0xFB, 0xFC, 0xFF,
                      0xC0, 0xC2, 0xC4, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCE, 0xCF, 0xD4, 0xD6, 0xD9, 0xDB, 0xDC, 0x178,
                      0x153, 0x152, 0xE6, 0xC6 }) do NAME_EXTRA[cp] = true end

local function validTopName(name)
    if type(name) ~= 'string' or #name < 1 or #name > NAME_MAX_BYTES then return false end
    if name:sub(1, 1) == ' ' or name:sub(-1) == ' ' then return false end   -- pas d'espace en tête ni en fin
    local i, n, count, letters = 1, #name, 0, 0
    while i <= n do
        local b = name:byte(i)
        local cp, len
        if b < 0x80 then cp, len = b, 1
        elseif b >= 0xC2 and b <= 0xDF then cp, len = b & 0x1F, 2
        elseif b >= 0xE0 and b <= 0xEF then cp, len = b & 0x0F, 3
        else return false end   -- octet de continuation seul, 0xC0/0xC1 (surlong) ou séquence de 4 octets
        if i + len - 1 > n then return false end
        for k = 1, len - 1 do
            local c = name:byte(i + k)
            if c < 0x80 or c > 0xBF then return false end
            cp = (cp << 6) | (c & 0x3F)
        end
        if len == 3 and cp < 0x800 then return false end
        local ok = (cp >= 0x30 and cp <= 0x39) or (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
            or cp == 0x20 or cp == 0x2D or cp == 0x27 or NAME_EXTRA[cp] == true
        if not ok then return false end
        if cp ~= 0x20 and cp ~= 0x2D and cp ~= 0x27 then letters = letters + 1 end
        count = count + 1
        i = i + len
    end
    return letters >= 1 and count <= NAME_MAX_CHARS   -- au moins une lettre ou un chiffre
end
Workshop.validTopName = validTopName

function Workshop.rename(src, uid, name)
    if not validTopName(name) then return fail(codes().invalid) end
    return simpleEdit(src, uid, 'name', name)
end

function Workshop.paint(src, uid, paint)
    if not P().paints[paint] then return fail(codes().invalid) end
    return simpleEdit(src, uid, 'paint', paint)
end

function Workshop.handle(src, d)
    if d.action == 'equip' then return Workshop.equip(src, d.uid, d.part) end
    if d.action == 'repair' then return Workshop.repair(src, d.uid) end
    if d.action == 'rename' then return Workshop.rename(src, d.uid, d.name) end
    if d.action == 'paint' then return Workshop.paint(src, d.uid, d.paint) end
    if d.action == 'disassemble' then return Workshop.disassemble(src, d.uid) end
    return fail(codes().invalid)
end

-- Nouvelle toupie en montage à partir de deux pièces d'emplacements différents (glisser-déposer). Même journal que
-- l'atelier : les deux pièces sortent, la ligne est écrite en base, puis la toupie entre dans l'inventaire.
-- Échec certain → pièces rendues ; réponse incertaine de la base → opération en revue, rien n'est rendu à l'aveugle.
function Workshop.create(src, partA, partB)
    if not Tops.enabled() then return fail(codes().db_unavailable) end
    local a, b = P().catalog[partA], P().catalog[partB]
    if not a or not b or a.slot == b.slot then return fail(codes().invalid) end
    local parts = { [a.slot] = partA, [b.slot] = partB }
    local okParts, why = Stats.validatePartial(parts)
    if not okParts then return fail(why == 'over_budget' and codes().over_budget or codes().invalid) end
    local identifier = Bridge.identifier(src)
    local uid = Inv.newUid()
    local token = Inv.lock(uid, 'workshop')
    local ctx = { identifier = identifier, held = {}, written = false, payload = { parts = parts } }
    local function same()
        if Bridge.identifier(src) ~= identifier or Inv.locked[uid] ~= token then abort(codes().error, true) end
    end
    local function move(from, to)
        local moved, err = Db.opMove(ctx.opId, from, to)
        if not moved then
            log('montage : journal %s %s → %s impossible (%s), opération à revoir', tostring(ctx.opId), from, to, tostring(err))
            abort(codes().error, true)
        end
        ctx.status = to
    end
    -- Rend les pièces prises (refus certain) ; celles qui ne passent pas restent dues, avec leur liste au journal
    local function restore()
        local failed = {}
        for i = #ctx.held, 1, -1 do
            same()
            local id = ctx.held[i]:sub(3)
            if Inv.givePart(src, id) then table.remove(ctx.held, i) else failed[#failed + 1] = ctx.held[i] end
        end
        if #failed == 0 then return move('item_taken', 'compensated') end
        if not oweJournal(ctx.opId, 'item_taken', ctx.payload, failed, identifier) then abort(codes().error, true) end
        ctx.status = 'owed'
    end
    local ok, res = pcall(function()
        if Inv.partCount(src, partA) < 1 or Inv.partCount(src, partB) < 1 then abort(codes().no_part) end
        if not Inv.canCarryTop(src) then abort(codes().inventory_full) end
        local opId, err = Db.opStart(identifier, uid, 'create', ctx.payload)
        if not opId then abort(err == 'db_unavailable' and codes().db_unavailable or codes().error) end
        ctx.opId, ctx.status = opId, 'pending'
        same()
        if not Inv.takePart(src, partA) then
            move('pending', 'failed')
            return fail(codes().no_part)
        end
        ctx.held[1] = 'p:' .. partA
        move('pending', 'item_taken')
        same()
        if not Inv.takePart(src, partB) then
            restore()
            return fail(codes().no_part)
        end
        ctx.held[2] = 'p:' .. partB
        same()
        ctx.written = true
        local top, derr = Db.ensureTop(uid, identifier, parts, 'Toupie en montage')
        if derr then
            log('montage : écriture incertaine pour %s (%s), opération %s à revoir', uid, tostring(derr), tostring(ctx.opId))
            abort(codes().error, true)
        end
        -- Identifiant déjà pris (INSERT IGNORE a relu une autre ligne) : jamais rattacher les pièces à une autre toupie
        if not top or top.owner ~= identifier or top.version ~= 1 then
            ctx.written = false   -- refus certain : aucune ligne à nous
            restore()
            return fail(codes().busy)
        end
        same()
        if not Inv.giveTop(src, uid, 'Toupie en montage') then
            -- La ligne reste sans objet (sans effet : la possession vient de l'inventaire) ; les pièces reviennent
            restore()
            return fail(codes().inventory_full)
        end
        ctx.held = {}
        move('item_taken', 'done')
        refreshLabel(src, top)
        return { ok = true, code = codes().ok, uid = uid }
    end)
    Inv.unlock(uid, token)
    if ok then return res end
    if getmetatable(res) ~= Abort then
        log('montage : erreur inattendue (opération %s) : %s', tostring(ctx.opId), tostring(res))
        res = { code = codes().error, review = ctx.opId ~= nil }
    end
    if not res.review and ctx.status == 'item_taken' then
        -- Refus certain après avoir pris des pièces (identité inchangée) : on les rend
        pcall(restore)
    end
    settle(ctx, res)
    return fail(res.code)
end

-------------------------------------------------------------------------------
-- Assemblage par glisser-déposer dans ox_inventory (hook swapItems, ox_inventory 2.45.0)
-------------------------------------------------------------------------------

local Assembly = { pending = {} }
local PART_ID = '^[%w_]+$'

local function notify(src, code, args)
    pcall(TriggerClientEvent, SpinArena.Protocol.ev.notify, src, { code = code, args = args or {} })
end

-- Lecture seule des deux objets : ce que le dépôt demande, ou nil (échange ox ordinaire)
local function intent(from, to)
    local fn, tn = from.name, to.name
    local function partOf(slot)
        local id = type(slot.metadata) == 'table' and slot.metadata.part
        return type(id) == 'string' and id:match(PART_ID) and P().catalog[id] and id or false
    end
    local function uidOf(slot)
        local uid = type(slot.metadata) == 'table' and slot.metadata.uid
        return type(uid) == 'string' and uid:match(Inv.UID_PATTERN) and uid or false
    end
    if (fn == Inv.ITEM_PART and tn == Inv.ITEM_TOP) or (fn == Inv.ITEM_TOP and tn == Inv.ITEM_PART) then
        local top, part = fn == Inv.ITEM_TOP and from or to, fn == Inv.ITEM_PART and from or to
        return { kind = 'equip', uid = uidOf(top), part = partOf(part) }
    end
    if (fn == Inv.ITEM_REPAIR and tn == Inv.ITEM_TOP) or (fn == Inv.ITEM_TOP and tn == Inv.ITEM_REPAIR) then
        return { kind = 'repair', uid = uidOf(fn == Inv.ITEM_TOP and from or to) }
    end
    if fn == Inv.ITEM_PART and tn == Inv.ITEM_PART then
        local a, b = partOf(from), partOf(to)
        -- Même emplacement (ou pièce inconnue) : simple rangement, ox_inventory échange les cases
        if not a or not b or P().catalog[a].slot == P().catalog[b].slot then return nil end
        return { kind = 'create', a = a, b = b }
    end
    return nil
end

-- Hook swapItems : renvoie true pour laisser ox_inventory faire, false pour annuler. Aucune attente ici.
function Assembly.onSwap(payload)
    if type(payload) ~= 'table' or payload.action ~= 'swap' then return true end
    local src = payload.source
    if type(src) ~= 'number' or payload.fromInventory ~= src or payload.toInventory ~= src
        or payload.fromType ~= 'player' or payload.toType ~= 'player' then return true end
    local from, to = payload.fromSlot, payload.toSlot
    if type(from) ~= 'table' or type(to) ~= 'table' then return true end
    local job = intent(from, to)
    if not job then return true end
    -- Données d'objet inutilisables : on refuse plutôt que de laisser échanger une pièce contre une toupie
    if job.uid == false or job.part == false then notify(src, codes().invalid) return false end
    if job.uid and Inv.locked[job.uid] then notify(src, codes().top_locked) return false end
    if Assembly.pending[src] then notify(src, codes().busy) return false end
    if not Tops.enabled() then notify(src, codes().db_unavailable) return false end
    Assembly.pending[src] = true
    CreateThread(function()
        Wait(0)   -- après la fin de l'échange annulé dans ox_inventory
        local ok, res = pcall(function()
            if job.kind == 'equip' then return Workshop.equip(src, job.uid, job.part) end
            if job.kind == 'repair' then return Workshop.repair(src, job.uid) end
            return Workshop.create(src, job.a, job.b)
        end)
        Assembly.pending[src] = nil
        if not ok then
            log('assemblage : erreur pour %s : %s', tostring(src), tostring(res))
            return notify(src, codes().error)
        end
        if res.ok then
            local done = { equip = 'assemble_ok', repair = 'repair_ok', create = 'assemble_new' }
            local part = job.part or job.a
            return notify(src, done[job.kind], { part = part, slot = part and P().catalog[part].slot or nil })
        end
        notify(src, res.code or codes().error)
    end)
    return false
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('playerDropped', function() Assembly.pending[source] = nil end)
end

SpinArena.Assembly = Assembly

-------------------------------------------------------------------------------
-- Livraison des objets dus (journal « owed ») : à la connexion du personnage et chaque minute pour les joueurs
-- en ligne dont l'identifiant a des dettes. owed → delivering est conditionnel : jamais deux livraisons.
-------------------------------------------------------------------------------

local function giveOwed(src, code)
    local kind, value = code:sub(1, 1), code:sub(3)
    if kind == 'p' and P().catalog[value] then return Inv.givePart(src, value) end
    if kind == 'r' then return Inv.giveRepair(src) end
    if kind == 't' and value:match(Inv.UID_PATTERN) then return Inv.giveTopBack(src, { uid = value }) end
    log('objet dû illisible ignoré : %s', tostring(code))
    return true
end

function Owed.deliver(src)
    if not Tops.enabled() then return 0 end
    local identifier = Bridge.identifier(src)
    if not identifier or Owed.busy[identifier] then return 0 end
    Owed.busy[identifier] = true
    local given, left = 0, 0
    local ok, err = pcall(function()
        local rows = Db.opsOwed(identifier)
        if not rows then return end
        for _, row in ipairs(rows) do
            local okp, payload = pcall(json.decode, row.payload or '')
            local list = okp and type(payload) == 'table' and type(payload.owed) == 'table' and payload.owed
            if list and Db.opMove(row.id, 'owed', 'delivering') then
                local rest = {}
                for _, code in ipairs(list) do
                    if Bridge.identifier(src) == identifier and giveOwed(src, code) then given = given + 1
                    else rest[#rest + 1] = code end
                end
                if #rest == 0 then
                    Db.opMove(row.id, 'delivering', 'delivered')
                else
                    payload.owed = rest
                    left = left + #rest
                    if not Db.opOwe(row.id, 'delivering', payload) then
                        log('livraison : opération %s bloquée en delivering, à revoir', tostring(row.id))
                    end
                end
            end
        end
    end)
    if not ok then log('livraison des objets dus à %s : %s', tostring(identifier), tostring(err)) end
    if ok and left == 0 then Owed.pendingIds[identifier] = nil end
    Owed.busy[identifier] = nil
    if given > 0 then notify(src, 'owed_delivered', { count = given }) end
    return given
end

if type(AddEventHandler) == 'function' and type(CreateThread) == 'function' then
    Bridge.onLoaded(function(src)
        CreateThread(function() Owed.deliver(src) end)
    end)
    CreateThread(function()
        while not Tops.enabled() do Wait(1000) end
        for _, r in ipairs(Db.owedIdentifiers() or {}) do Owed.pendingIds[r.identifier] = true end
        while true do
            Wait(60000)
            if next(Owed.pendingIds) then
                for _, id in ipairs(GetPlayers()) do
                    local src = tonumber(id)
                    if Owed.pendingIds[Bridge.identifier(src) or ''] then Owed.deliver(src) end
                end
            end
        end
    end)
end

SpinArena.Owed = Owed

-- Branchement dans les matchs : la source de test laisse la place à la source réelle
SpinArena.Matches.TopSource = {
    check = Tops.check,
    resolve = Tops.resolve,
    revalidate = Tops.revalidate,
    release = Tops.release,
}
SpinArena.Matches.onFinished(Tops.onFinished)

SpinArena.Tops = Tops
SpinArena.Workshop = Workshop
return Tops
