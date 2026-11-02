-- ROTORBRAWL — panneau lumineux au-dessus de chaque table, visible dans le monde par les joueurs autour.
-- Lecture seule des scènes du rendu (contrat d'Archimedes : SpinArena.Renderer.scenes() / onScenesChanged) :
-- tout vient des événements serveur (préparation, compte à rebours, score, fin) ; rien n'est calculé ici sauf
-- l'affichage du décompte jusqu'à goAt (GetGameTimer local, fixé par le rendu à partir de startsInMs).
-- Technique : texte ancré dans le monde (SetDrawOrigin + texte + fond DrawRect). Pas de page web, pas de scaleform.
SpinArena = SpinArena or {}

local H = { panels = {}, near = {} }
local function cfg()
    local c = SpinArena.Config and SpinArena.Config.hologram or {}
    return {
        enabled = c.enabled ~= false, height = tonumber(c.height) or 0.85, maxDistance = tonumber(c.maxDistance) or 25.0,
        fadeFrom = tonumber(c.fadeFrom) or 15.0, scale = tonumber(c.scale) or 0.34, maxPanels = tonumber(c.maxPanels) or 4,
        topMargin = tonumber(c.topMargin) or 0.16,
    }
end

local CYAN, ORANGE, WHITE, GREY = { 89, 178, 255 }, { 255, 122, 26 }, { 240, 246, 255 }, { 154, 166, 184 }
local NAME_MAX = 16   -- un nom trop long élargit le panneau : on le coupe (UTF-8 sûr)
local function shorten(str)
    if utf8 and utf8.len and (utf8.len(str) or 0) > NAME_MAX then
        return str:sub(1, (utf8.offset(str, NAME_MAX) or (NAME_MAX + 1)) - 1) .. '…'
    end
    return str
end
local function name(scene, side)
    local n = type(scene.names) == 'table' and scene.names[side == 1 and 'a' or 'b'] or nil
    if n == nil and type(scene.names) == 'table' then n = scene.names[side] end
    return shorten(tostring(n or ('Joueur ' .. side)))
end
local function scoreOf(scene, side)
    local s = type(scene.score) == 'table' and (scene.score[side == 1 and 'a' or 'b'] or scene.score[side]) or 0
    return tonumber(s) or 0
end

-- Lignes à afficher pour une scène à l'instant nowMs (pur, testable) : { title, lines = { {text, color} }, accent }
function H.lines(scene, nowMs)
    if type(scene) ~= 'table' then return nil end
    -- Nom de la table : libellé de la station, sinon son identifiant (« legion_compact » → « Legion compact »)
    local title = scene.label
    if not title and type(scene.stationId) == 'string' then
        title = scene.stationId:gsub('_', ' '):gsub('^%l', string.upper)
    end
    title = tostring(title or 'ROTORBRAWL')
    if scene.practice then title = title .. ' · Entraînement' end
    local st = scene.state
    local L = {}
    if st == 'board' then
        -- Classement de saison (données Ranking du serveur, événement seasonTop) : 5 lignes au plus
        for i, r in ipairs(type(scene.top) == 'table' and scene.top or {}) do
            if i > 5 then break end
            L[#L + 1] = { ('%d. %s  %d'):format(i, shorten(tostring(r.name or '?')), math.floor(tonumber(r.rating) or 0)), i == 1 and ORANGE or WHITE }
        end
        if #L == 0 then L[1] = { 'Aucun match classé pour l\'instant', GREY } end
        return { title = ('Classement · saison %s'):format(tostring(scene.season or '—')), lines = L, accent = ORANGE }
    end
    if st == 'queue' then
        -- File d'attente de la table (Archimedes) : un joueur inscrit attend un adversaire
        local n = math.max(0, math.min(2, tonumber(scene.waiting) or 0))
        local who = type(scene.names) == 'table' and (scene.names.a or scene.names[1]) or nil
        L[#L + 1] = { ('En attente d\'un adversaire (%d/2)'):format(n), WHITE }
        L[#L + 1] = { who and ('%s attend'):format(shorten(tostring(who))) or 'Regarde la table pour rejoindre', GREY }
        return { title = title, lines = L, accent = CYAN }
    elseif st == 'preparing' then
        local n = 0
        for _, r in ipairs(type(scene.ready) == 'table' and scene.ready or {}) do if r then n = n + 1 end end
        L[#L + 1] = { ('En attente des lanceurs (%d/2)'):format(n), WHITE }
        if tonumber(scene.deadlineAt) then
            L[#L + 1] = { ('%d s'):format(math.max(0, math.ceil((scene.deadlineAt - nowMs) / 1000))), GREY }
        end
        return { title = title, lines = L, accent = CYAN }
    elseif st == 'countdown' then
        local goAt = tonumber(scene.goAt)
        if goAt and nowMs < goAt then
            L[#L + 1] = { ('%d'):format(math.ceil((goAt - nowMs) / 1000)), ORANGE }
        else
            L[#L + 1] = { 'LANCEZ !', ORANGE }
        end
        L[#L + 1] = { ('%s  vs  %s'):format(name(scene, 1), name(scene, 2)), WHITE }
        return { title = title, lines = L, accent = ORANGE }
    elseif st == 'playing' or st == 'round_over' then
        L[#L + 1] = { ('%s  %d - %d  %s'):format(name(scene, 1), scoreOf(scene, 1), scoreOf(scene, 2), name(scene, 2)), WHITE }
        if st == 'round_over' then
            local w = tonumber(scene.roundWinner)
            -- Finition et points gagnés (envoyés par le serveur) : « SORTIE Sam +2 », « ÉCLAT … », « TURBO … »
            local FINISH = { ring_out = 'SORTIE', spin_out = 'ARRÊT', burst = 'ÉCLAT', turbo_out = 'TURBO' }
            local fin = FINISH[scene.roundReason]
            local pts = tonumber(scene.roundPoints)
            if w and fin then
                L[#L + 1] = { ('%s  %s%s'):format(fin, name(scene, w), pts and (' +' .. pts) or ''), CYAN }
            else
                L[#L + 1] = { w and ('Manche pour %s'):format(name(scene, w)) or 'Manche nulle', CYAN }
            end
        else
            if tonumber(scene.target) then
                L[#L + 1] = { ('Manche %d · premier à %d points'):format(tonumber(scene.round) or 1, tonumber(scene.target)), GREY }
            else
                L[#L + 1] = { ('Manche %d / BO%d'):format(tonumber(scene.round) or 1, tonumber(scene.bestOf) or 3), GREY }
            end
        end
        return { title = title, lines = L, accent = CYAN }
    elseif st == 'finished' then
        local w = tonumber(scene.winner)
        L[#L + 1] = { w and ('Victoire : %s'):format(name(scene, w)) or 'Égalité', ORANGE }
        L[#L + 1] = { ('%s  %d - %d  %s'):format(name(scene, 1), scoreOf(scene, 1), scoreOf(scene, 2), name(scene, 2)), WHITE }
        return { title = title, lines = L, accent = ORANGE }
    elseif st == 'cancelled' then
        L[#L + 1] = { 'Match annulé', ORANGE }
        if scene.reason == 'prepare_timeout' then L[#L + 1] = { 'Personne n\'a lancé à temps', GREY } end
        return { title = title, lines = L, accent = GREY }
    end
    return nil
end

-- Panneaux à dessiner : scènes reçues (copies), ancrées au-dessus de leur table, les plus proches d'abord
function H.refresh(list)
    local c = cfg()
    local out = {}
    for _, s in ipairs(type(list) == 'table' and list or {}) do
        if type(s) == 'table' and type(s.center) == 'table' and #out < c.maxPanels then
            out[#out + 1] = { scene = s, x = tonumber(s.center.x) or 0, y = tonumber(s.center.y) or 0,
                              z = (tonumber(s.topZ) or tonumber(s.center.z) or 0) + c.height }
        end
    end
    -- Panneau du classement de saison, s'il a un ancrage en config et des données reçues
    local b = SpinArena.Config and SpinArena.Config.leaderboardBoard
    if H.board and type(b) == 'table' and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) then
        out[#out + 1] = { scene = H.board, x = b.x, y = b.y, z = b.z + (tonumber(b.height) or 0) }
    end
    H.panels = out
    -- Changement d'état pris en compte tout de suite (sans attendre le prochain tri par distance)
    if H.lastPos then H.nearby(H.lastPos[1], H.lastPos[2], H.lastPos[3]) end
    return out
end

-- Tri par distance (toutes les 250 ms, pas à chaque image) ; renvoie les panneaux à portée avec leur opacité
function H.nearby(px, py, pz)
    local c = cfg()
    H.lastPos = { px, py, pz }
    local near = {}
    for _, p in ipairs(H.panels) do
        local dx, dy, dz = p.x - px, p.y - py, p.z - pz
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d <= c.maxDistance then
            local a = 1.0
            if d > c.fadeFrom then a = math.max(0, 1 - (d - c.fadeFrom) / math.max(0.01, c.maxDistance - c.fadeFrom)) end
            near[#near + 1] = { panel = p, dist = d, alpha = a }
        end
    end
    table.sort(near, function(a, b) return a.dist < b.dist end)
    H.near = near
    return near
end

local function text(str, x, y, scale, col, alpha)
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(col[1], col[2], col[3], math.floor(255 * alpha))
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
end

-- Natives de dessin présentes (toujours dans GTA ; absentes d'un environnement de test) : sinon, rien n'est dessiné
function H.canDraw()
    local f = 'function'
    return type(SetDrawOrigin) == f and type(ClearDrawOrigin) == f and type(DrawRect) == f and type(SetTextScale) == f
        and type(SetTextFont) == f and type(SetTextProportional) == f and type(SetTextColour) == f
        and type(SetTextOutline) == f and type(SetTextCentre) == f and type(BeginTextCommandDisplayText) == f
        and type(AddTextComponentSubstringPlayerName) == f and type(EndTextCommandDisplayText) == f
end

-- Le point d'ancrage est-il à l'écran, et pas dans la bande du haut (où vivent le HUD et les messages) ?
-- Sans la native de projection (environnement de test), on dessine.
function H.onScreen(x, y, z, topMargin)
    if type(GetScreenCoordFromWorldCoord) ~= 'function' then return true end
    local ok, on, sx, sy = pcall(GetScreenCoordFromWorldCoord, x, y, z)
    if not ok or not on then return false end
    return type(sx) == 'number' and type(sy) == 'number' and sy >= (topMargin or 0) and sy <= 0.98 and sx >= 0.02 and sx <= 0.98
end

function H.draw(nowMs)
    if not H.canDraw() then return end
    local c = cfg()
    for _, n in ipairs(H.near) do
        local p, a = n.panel, n.alpha
        local view = H.lines(p.scene, nowMs)
        if view and a > 0.02 and H.onScreen(p.x, p.y, p.z, c.topMargin) then
            local k = c.scale * math.max(0.55, math.min(1.4, 10.0 / math.max(1.0, n.dist)))
            local lh = 0.032 * k / 0.42
            SetDrawOrigin(p.x, p.y, p.z, 0)
            DrawRect(0.0, lh * 0.9, 0.16 * k / 0.42, lh * (#view.lines + 1) + 0.012, 6, 12, 22, math.floor(170 * a))
            DrawRect(0.0, -0.004, 0.16 * k / 0.42, 0.003, view.accent[1], view.accent[2], view.accent[3], math.floor(230 * a))
            text(view.title, 0.0, 0.0, k * 0.75, CYAN, a)
            for i, l in ipairs(view.lines) do text(l[1], 0.0, lh * i, k, l[2], a) end
            ClearDrawOrigin()
        end
    end
end

-- Données du classement (spin_arena:cl:seasonTop, contrat proposé à Archimedes) : { season, updatedAt, top = { ... } }
function H.setBoard(payload)
    if type(payload) ~= 'table' or type(payload.top) ~= 'table' then return false end
    H.board = { state = 'board', season = payload.season, top = payload.top }
    local R = SpinArena.Renderer
    H.refresh(R and type(R.scenes) == 'function' and R.scenes() or {})
    return true
end

function H.start()
    if H.running or not cfg().enabled then return end
    local R = SpinArena.Renderer
    if not (R and type(R.scenes) == 'function') then return end   -- multi-scènes absent : aucun panneau
    H.running = true
    if type(R.onScenesChanged) == 'function' then R.onScenesChanged(function(list) H.refresh(list) end) end
    H.refresh(R.scenes())
    -- Distances toutes les 250 ms
    CreateThread(function()
        while H.running do
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            H.nearby(pos.x, pos.y, pos.z)
            Wait(250)
        end
    end)
    -- Une seule boucle de dessin, active seulement si un panneau est à portée
    CreateThread(function()
        while H.running do
            if #H.near > 0 then
                H.draw(GetGameTimer())
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end

function H.stop()
    H.running = false
    H.panels, H.near, H.lastPos = {}, {}, nil
end

if type(RegisterNetEvent) == 'function' and type(AddEventHandler) == 'function' then
    RegisterNetEvent('spin_arena:cl:seasonTop')
    AddEventHandler('spin_arena:cl:seasonTop', function(payload) H.setBoard(payload) end)
end
if type(AddEventHandler) == 'function' then
    AddEventHandler('onClientResourceStart', function(res)
        if res == (GetCurrentResourceName and GetCurrentResourceName()) then CreateThread(function() Wait(1000) H.start() end) end
    end)
    AddEventHandler('onResourceStop', function(res)
        if res == (GetCurrentResourceName and GetCurrentResourceName()) then H.stop() end
    end)
end

SpinArena.Hologram = H
return H
