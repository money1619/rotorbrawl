-- Défis entre joueurs (docs/ARCHITECTURE.md §7, état pending) : envoi, réponse, annulation, expiration.
-- Toutes les vérifications sont refaites au moment de l'acceptation.
SpinArena = SpinArena or {}

-- Les numéros de défi partent d'une base tirée au hasard à chaque démarrage : une réponse d'avant un
-- redémarrage ne peut pas viser un nouveau défi
local Challenges = { byId = {}, outgoing = {}, incoming = {}, nextId = math.random(1, 0x3FFFFFFF) }

local P = SpinArena.Protocol
local codes = P.codes
local Bridge, Matches, Arenas = SpinArena.Bridge, SpinArena.Matches, SpinArena.Arenas

local function S() return SpinArena.ServerConfig end
local function now() return GetGameTimer() end
local function fail(code) return { ok = false, code = code } end

local function countIncoming(src)
    local n = 0
    for _ in pairs(Challenges.incoming[src] or {}) do n = n + 1 end
    return n
end

local function remove(c)
    Challenges.byId[c.id] = nil
    if Challenges.outgoing[c.from] == c.id then Challenges.outgoing[c.from] = nil end
    if Challenges.incoming[c.to] then Challenges.incoming[c.to][c.id] = nil end
end

-- Un envoi qui échoue ne doit pas laisser un défi orphelin
local function notify(src, payload)
    if Bridge.online(src) then
        local ok, err = pcall(TriggerClientEvent, P.ev.challenge, src, payload)
        if not ok then print(('[spin_arena] défi : envoi à %s impossible : %s'):format(tostring(src), tostring(err))) end
    end
end

-- Contexte commun aux deux joueurs : en ligne, même monde, proches, à pied, vivants
local function checkPair(a, b)
    local ca, cb = Bridge.context(a), Bridge.context(b)
    if not ca or not cb then return nil, codes.offline end
    if ca.bucket ~= cb.bucket then return nil, codes.other_bucket end
    local dx, dy, dz = ca.coords.x - cb.coords.x, ca.coords.y - cb.coords.y, ca.coords.z - cb.coords.z
    if math.sqrt(dx * dx + dy * dy + dz * dz) > S().challenge.maxDistance then return nil, codes.too_far end
    if ca.inVehicle or cb.inVehicle then return nil, codes.in_vehicle end
    if ca.dead or cb.dead then return nil, codes.dead end
    -- Arène transportable du challenger : sa table improvisée prend la variante de l'objet (seulement lui, pas la cible)
    local Inv = SpinArena.Inventory
    ca.portable = Inv and Inv.portableVariant and Inv.portableVariant(a) or nil
    return ca, cb
end

local function expire(id)
    local c = Challenges.byId[id]
    if not c then return end
    remove(c)
    notify(c.from, { kind = 'expired', id = id, toName = c.toName })
    notify(c.to, { kind = 'expired', id = id, fromName = c.fromName })
end

function Challenges.send(src, target, top, stationName)
    if target == src then return fail(codes.same_player) end
    if not Bridge.online(target) then return fail(codes.offline) end
    -- Toupie complète possédée (lecture en base : l'état est revérifié ci-dessous, après l'attente)
    local topOk, topCode = Matches.TopSource.check(src, top)
    if not topOk then return fail(topCode) end
    if not Bridge.online(target) then return fail(codes.offline) end
    if Matches.isBusy(src) then return fail(codes.already_in_match) end
    if Matches.isBusy(target) then return fail(codes.target_busy) end
    if Challenges.outgoing[src] then return fail(codes.busy) end
    if countIncoming(target) >= S().challenge.maxIncoming then return fail(codes.target_busy) end
    local ctx, targetCtxOrCode = checkPair(src, target)
    if not ctx then return fail(targetCtxOrCode) end
    -- Refus immédiat si aucune arène n'est possible ici (ou si la station fixe demandée est occupée/absente)
    local placeable, acode = Arenas.place(ctx, stationName)
    if not placeable then return fail(acode) end
    if stationName and type(targetCtxOrCode) == 'table' then
        if Arenas.distance(placeable, targetCtxOrCode.coords) > S().arena.fixedRadius then
            return fail(codes.too_far)
        end
    end

    Challenges.nextId = Challenges.nextId + 1
    local c = {
        id = Challenges.nextId, from = src, to = target, top = top, station = stationName,
        fromName = Bridge.name(src), toName = Bridge.name(target),
        expiresAt = now() + S().challenge.ttlMs,
    }
    Challenges.byId[c.id] = c
    Challenges.outgoing[src] = c.id
    Challenges.incoming[target] = Challenges.incoming[target] or {}
    Challenges.incoming[target][c.id] = true
    SetTimeout(S().challenge.ttlMs, function() expire(c.id) end)
    notify(target, {
        kind = 'incoming', id = c.id, from = src, fromName = c.fromName,
        top = top, station = stationName, expiresInMs = S().challenge.ttlMs,
    })
    return { ok = true, code = codes.ok, id = c.id, station = stationName }
end

function Challenges.respond(src, id, accept, top)
    local c = Challenges.byId[id]
    if not c or c.to ~= src then return fail(codes.not_found) end
    if now() > c.expiresAt then
        expire(id)
        return fail(codes.expired)
    end
    if not accept then
        remove(c)
        notify(c.from, { kind = 'declined', id = id, to = c.to, toName = c.toName })
        return { ok = true, code = codes.ok }
    end
    local topOk, topCode = Matches.TopSource.check(src, top)
    if not topOk then return fail(topCode) end
    -- Après l'attente : le défi a pu être annulé, refusé ou expirer
    if Challenges.byId[id] ~= c then return fail(codes.not_found) end
    if now() > c.expiresAt then
        expire(id)
        return fail(codes.expired)
    end
    if Matches.isBusy(src) then return fail(codes.already_in_match) end
    if Matches.isBusy(c.from) then return fail(codes.target_busy) end
    local challenger, targetCtxOrCode = checkPair(c.from, src)
    if not challenger then return fail(targetCtxOrCode) end

    local arena, acode = Arenas.place(challenger, c.station)
    if not arena then return fail(acode) end
    if c.station and type(targetCtxOrCode) == 'table' then
        if Arenas.distance(arena, targetCtxOrCode.coords) > S().arena.fixedRadius then
            return fail(codes.too_far)
        end
    end
    local match, err = Matches.create({
        players = { { src = c.from, top = c.top }, { src = src, top = top } },
        arena = arena,
        bucket = challenger.bucket,
    })
    if not match then return fail(err) end
    remove(c)
    -- Le joueur qui accepte ne peut plus avoir de défi sortant en attente
    local mine = Challenges.outgoing[src] and Challenges.byId[Challenges.outgoing[src]]
    if mine then
        remove(mine)
        notify(mine.to, { kind = 'cancelled', id = mine.id, fromName = mine.fromName })
    end
    notify(c.from, { kind = 'accepted', id = id, to = c.to, toName = c.toName, matchId = match.id })
    return { ok = true, code = codes.ok, matchId = match.id }
end

function Challenges.cancel(src, id)
    local c = Challenges.byId[id]
    if not c or c.from ~= src then return fail(codes.not_found) end
    remove(c)
    notify(c.to, { kind = 'cancelled', id = id, fromName = c.fromName })
    return { ok = true, code = codes.ok }
end

function Challenges.onPlayerLeft(src)
    local list = {}
    for _, c in pairs(Challenges.byId) do
        if c.from == src or c.to == src then list[#list + 1] = c end
    end
    for _, c in ipairs(list) do
        remove(c)
        if c.from == src then
            notify(c.to, { kind = 'cancelled', id = c.id, fromName = c.fromName })
        else
            notify(c.from, { kind = 'declined', id = c.id, toName = c.toName })
        end
    end
    Challenges.incoming[src] = nil
end

local function nearbyOpponents(src)
    local me = Bridge.context(src)
    if not me or type(GetPlayers) ~= 'function' then return {} end
    local maxD = S().challenge.maxDistance
    local list = {}
    for _, rawId in ipairs(GetPlayers()) do
        local other = tonumber(rawId)
        if other and other ~= src then
            local ctx = Bridge.context(other)
            if ctx and ctx.bucket == me.bucket and not ctx.inVehicle and not ctx.dead then
                local dx = me.coords.x - ctx.coords.x
                local dy = me.coords.y - ctx.coords.y
                local dz = me.coords.z - ctx.coords.z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d <= maxD then
                    list[#list + 1] = { id = other, name = Bridge.name(other), distance = d }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.id < b.id
    end)
    return list
end

function Challenges.stateFor(src)
    local incoming = {}
    for id in pairs(Challenges.incoming[src] or {}) do
        local c = Challenges.byId[id]
        if c then
            incoming[#incoming + 1] = {
                id = id, from = c.from, fromName = c.fromName, top = c.top,
                station = c.station, expiresInMs = math.max(0, c.expiresAt - now()),
            }
        end
    end
    table.sort(incoming, function(a, b) return a.id < b.id end)
    local out = Challenges.outgoing[src] and Challenges.byId[Challenges.outgoing[src]]
    local me = Bridge.context(src)
    local bucket = me and me.bucket or 0
    return {
        incoming  = incoming,
        outgoing  = out and {
            id = out.id, to = out.to, toName = out.toName, top = out.top,
            station = out.station, expiresInMs = math.max(0, out.expiresAt - now()),
        } or nil,
        stations  = Arenas.stations and Arenas.stations(bucket) or {},
        opponents = nearbyOpponents(src),
    }
end

SpinArena.Challenges = Challenges
return Challenges
