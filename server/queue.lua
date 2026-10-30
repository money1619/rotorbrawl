-- File d'attente aux tables fixes (amélioration validée par Money) : « Rejoindre la table » ; dès que deux joueurs sont
-- inscrits sur la même table libre, le VRAI match commence (préparation, lancement manuel par chacun — jamais de
-- départ automatique). Toupie choisie et matériel revérifiés par le serveur (TopSource), comme pour un défi.
-- Les joueurs autour reçoivent l'état de la file (spin_arena:cl:queue) pour le panneau de la table.
SpinArena = SpinArena or {}

local Queue = { byStation = {}, byPlayer = {}, informed = {} }
local P = SpinArena.Protocol
local Bridge, Arenas, Matches = SpinArena.Bridge, SpinArena.Arenas, SpinArena.Matches

local JOIN_DISTANCE = 5.0     -- m du centre de la table pour s'inscrire (zone ox_target 3,5 m + marge)
local KEEP_DISTANCE = 12.0    -- au-delà, le joueur quitte la file
local REFRESH_MS = 2000       -- état renvoyé aux joueurs autour (arrivées et départs du voisinage)

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function fail(code) return { ok = false, code = code } end
local function now() return GetGameTimer() end

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- État de la file d'une table pour les joueurs autour (contrat du panneau : waiting, names.a)
local function payload(station)
    local entry = Arenas.fixed[station]
    local q = Queue.byStation[station] or {}
    local v = entry and Arenas.variantOf and Arenas.variantOf(entry.variant) or SpinArena.Config.testArena
    return {
        stationId = station,
        label = entry and (entry.label or ('Table %s'):format(v.label or 'Standard')) or station,
        x = entry and entry.x, y = entry and entry.y, z = entry and entry.z,
        floorHeight = v.floorHeight,
        waiting = #q,
        names = q[1] and { a = q[1].name } or nil,
    }
end

-- Envoie l'état aux joueurs à portée ; ceux qui ne sont plus à portée (ou file vide) reçoivent waiting = 0
function Queue.broadcast(station)
    local entry = Arenas.fixed[station]
    if not entry then return end
    local data = payload(station)
    local now_ = {}
    if data.waiting > 0 then
        for _, src in ipairs(Arenas.audience(entry, entry.bucket, {})) do now_[src] = true end
        for _, e in ipairs(Queue.byStation[station] or {}) do now_[e.src] = true end
    end
    local before = Queue.informed[station] or {}
    for src in pairs(now_) do pcall(TriggerClientEvent, P.ev.queue, src, data) end
    local cleared = { stationId = station, waiting = 0 }
    for src in pairs(before) do
        if not now_[src] and Bridge.online(src) then pcall(TriggerClientEvent, P.ev.queue, src, cleared) end
    end
    Queue.informed[station] = next(now_) and now_ or nil
end

local function remove(src)
    local station = Queue.byPlayer[src]
    if not station then return nil end
    Queue.byPlayer[src] = nil
    local q = Queue.byStation[station] or {}
    for i = #q, 1, -1 do
        if q[i].src == src then table.remove(q, i) end
    end
    if #q == 0 then Queue.byStation[station] = nil end
    return station
end

-- Deux joueurs inscrits : création du vrai match sur la table (réservation exclusive, toupies verrouillées)
local function start(station)
    local q = Queue.byStation[station]
    if not q or #q < 2 then return end
    local a, b = q[1], q[2]
    remove(a.src); remove(b.src)
    local ctx = Bridge.context(a.src)
    local entry = Arenas.fixed[station]
    local code
    if not ctx or not entry or not Bridge.online(b.src) then
        code = P.codes.offline
    elseif Matches.isBusy(a.src) or Matches.isBusy(b.src) then
        code = P.codes.already_in_match
    else
        local arena, acode = Arenas.place(ctx, station)
        if not arena then
            code = acode
        else
            local match, mcode = Matches.create({
                players = { { src = a.src, top = a.top }, { src = b.src, top = b.top } },
                arena = arena, bucket = ctx.bucket,
            })
            if match then
                log('file %s : match %s entre %s et %s', station, match.id, a.name or '?', b.name or '?')
            else
                code = mcode
            end
        end
    end
    if code then
        log('file %s : match impossible (%s), file libérée', station, tostring(code))
        for _, e in ipairs({ a, b }) do
            if Bridge.online(e.src) then
                pcall(TriggerClientEvent, P.ev.notify, e.src, { code = 'queue_failed', args = { reason = code } })
            end
        end
    end
    Queue.broadcast(station)
end

function Queue.join(src, station, top)
    local codes = P.codes
    if Queue.byPlayer[src] then return fail(codes.busy) end
    if Matches.isBusy(src) then return fail(codes.already_in_match) end
    if SpinArena.Challenges and SpinArena.Challenges.outgoing[src] then return fail(codes.busy) end
    local entry = Arenas.fixed[station]
    if not entry then return fail(codes.not_found) end
    local ctx = Bridge.context(src)
    if not ctx then return fail(codes.offline) end
    if ctx.dead then return fail(codes.dead) end
    if ctx.inVehicle then return fail(codes.in_vehicle) end
    if ctx.bucket ~= entry.bucket then return fail(codes.other_bucket) end
    if math.abs(ctx.coords.z - entry.z) > 3.0 or dist2d(ctx.coords, entry) > JOIN_DISTANCE then return fail(codes.too_far) end
    if Arenas.isReserved(entry, ctx.bucket) then return fail(codes.no_arena) end
    -- Toupie choisie : possédée, complète, libre, lanceur (lecture en base : attente possible)
    local ok, code = Matches.TopSource.check(src, top)
    if not ok then return fail(code or codes.invalid) end
    -- Revérifié après l'attente : rien n'a changé pour ce joueur ni pour la table
    if Queue.byPlayer[src] or Matches.isBusy(src) or not Bridge.online(src) then return fail(codes.busy) end
    if Arenas.isReserved(entry, ctx.bucket) then return fail(codes.no_arena) end
    local q = Queue.byStation[station] or {}
    Queue.byStation[station] = q
    q[#q + 1] = { src = src, top = top, name = Bridge.name(src), at = now() }
    Queue.byPlayer[src] = station
    local waiting = #q
    Queue.broadcast(station)
    if #q >= 2 then start(station) end
    return { ok = true, code = codes.ok, station = station, waiting = waiting }
end

function Queue.leave(src, why)
    local station = remove(src)
    if not station then return fail(P.codes.not_found) end
    if why then log('file %s : %s retiré (%s)', station, tostring(src), why) end
    Queue.broadcast(station)
    return { ok = true, code = P.codes.ok }
end

function Queue.stateFor(src)
    return Queue.byPlayer[src]
end

-- Surveillance : joueur parti, mort, en véhicule, trop loin, ou engagé ailleurs → retiré ; état renvoyé autour
function Queue.watch()
    for src, station in pairs(Queue.byPlayer) do
        local entry = Arenas.fixed[station]
        local ctx = Bridge.context(src)
        local why
        if not entry then why = 'table supprimée'
        elseif not ctx then why = 'déconnecté'
        elseif ctx.dead then why = 'mort'
        elseif ctx.inVehicle then why = 'véhicule'
        elseif ctx.bucket ~= entry.bucket or dist2d(ctx.coords, entry) > KEEP_DISTANCE then why = 'trop loin'
        elseif Matches.isBusy(src) then why = 'en match ailleurs'
        end
        if why then
            remove(src)
            if Bridge.online(src) then pcall(TriggerClientEvent, P.ev.notify, src, { code = 'queue_left', args = { reason = why } }) end
        end
    end
    for station in pairs(Queue.informed) do Queue.broadcast(station) end
    for station in pairs(Queue.byStation) do Queue.broadcast(station) end
end

if type(CreateThread) == 'function' then
    CreateThread(function()
        while true do
            Wait(REFRESH_MS)
            local ok, err = pcall(Queue.watch)
            if not ok then log('file d\'attente : surveillance en erreur : %s', tostring(err)) end
        end
    end)
end

SpinArena.Queue = Queue
return Queue
