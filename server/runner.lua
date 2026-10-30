-- Exécution d'une manche sur le serveur (docs/ARCHITECTURE.md §8) : calcul par tranches et découpage en envois.
-- Partagé par la commande de test (server/debug.lua) et les matchs (server/matches.lua).
SpinArena = SpinArena or {}

local Runner = {}

-- Pas calculés entre deux Wait(0). 200 pas ≈ 3 ms de CPU d'après les journaux dev2 (~9 ms pour 600 pas) : le fil
-- serveur n'est pas bloqué longtemps quand plusieurs matchs démarrent ensemble. Nombre FIXE (et non un budget en
-- temps réel) : le découpage, donc l'horaire de diffusion, reste reproductible quelle que soit la charge.
Runner.STEPS_PER_SLICE = 200
Runner.CHUNK_S = 0.5           -- durée couverte par une tranche ordinaire
Runner.FINAL_PIECE_S = 0.1     -- la fin part en morceaux de 0,1 s, chacun à son heure

local clock = os.clock or function() return GetGameTimer() / 1000 end

-- Calcule une manche par tranches (jamais Tmax/dt pas d'un bloc).
-- Renvoie outcome, frames, events, cpu (s), stats { slices, maxSlice (s) } ; ou nil, erreur.
-- isCancelled() est consulté entre deux tranches.
function Runner.simulate(params, isCancelled)
    local Engine = SpinArena.Engine
    local round, err = Engine.newRound(params)
    if not round then return nil, err end
    local frames, events, cpu = { Engine.keyframe(round) }, {}, 0
    local slices, maxSlice = 0, 0
    while not round.done do
        local t0 = clock()
        for _ = 1, Runner.STEPS_PER_SLICE do
            Engine.record(round, frames, events, Engine.step(round))
            if round.done then break end
        end
        local spent = clock() - t0
        cpu = cpu + spent
        slices = slices + 1
        if spent > maxSlice then maxSlice = spent end
        if not round.done then
            Wait(0)
            if isCancelled and isCancelled() then return nil, 'cancelled' end
        end
    end
    return round.outcome, frames, events, cpu, { slices = slices, maxSlice = maxSlice }
end

-- Regroupe keyframes et événements en tranches de CHUNK_S secondes. Les CHUNK_S dernières secondes sont
-- redécoupées en morceaux de FINAL_PIECE_S envoyés sans avance : la fin n'est pas visible plus d'un morceau
-- à l'avance. Les autres tranches peuvent montrer jusqu'à avance + CHUNK_S.
function Runner.buildChunks(frames, events, dt, lastStep)
    local per = math.max(1, math.floor(Runner.CHUNK_S / dt + 0.5))
    local piece = math.max(1, math.floor(Runner.FINAL_PIECE_S / dt + 0.5))
    local finalFrom = math.max(0, lastStep - per)
    local chunks = {}
    for from = 0, finalFrom - 1, per do
        chunks[#chunks + 1] = { fromStep = from, frames = {}, events = {}, final = false }
    end
    for from = finalFrom, lastStep, piece do
        chunks[#chunks + 1] = { fromStep = from, frames = {}, events = {}, final = true }
    end
    local function find(step)
        local idx = 1
        for i = #chunks, 1, -1 do
            if chunks[i].fromStep <= step then idx = i break end
        end
        return chunks[idx]
    end
    for _, f in ipairs(frames) do
        local c = find(f[1])
        c.frames[#c.frames + 1] = f
    end
    for _, e in ipairs(events) do
        local c = find(e.s)
        c.events[#c.events + 1] = e
    end
    return chunks
end

-- Instant d'envoi d'une tranche (ms serveur) : avance `leadMs` pour les tranches ordinaires, aucune pour la fin
function Runner.sendAt(goAt, chunk, dt, leadMs)
    return goAt + math.floor(chunk.fromStep * dt * 1000) - (chunk.final and 0 or leadMs)
end

SpinArena.Runner = Runner
return Runner
