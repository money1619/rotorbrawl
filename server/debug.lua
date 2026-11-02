-- ROTORBRAWL — commandes de test (administrateurs uniquement, ACE command.spin_test)
--   /spin_test pratique [table] [ma_toupie] [adversaire]    ENTRAÎNEMENT avec le vrai parcours : match réel sur une
--       table (nom de station, ou la plus proche libre, sinon devant l'admin), préparation volontaire du lanceur
--       (jauge, animation), adversaire SIMULÉ par le serveur qui lance seul, départ commun, combat visible des joueurs
--       autour, fin et nettoyage. Toupies du catalogue (attack, defense, endurance, balance, mobility), sans
--       inventaire : aucun classement, aucune usure, aucun objet. /spin_test stop l'arrête.
--   /spin_test [attack|endurance] [attack|endurance] [seed]  ancienne DÉMO à départ automatique, vue par l'admin seul
--   /spin_test stop                                          annule la manche affichée
--   spin_test bench [n]                                      n manches sans affichage, résumé dans la console
-- Préfigure le futur module matches (ARCHITECTURE.md §8) : calcul par tranches pendant le compte à rebours,
-- diffusion avec une avance limitée, tranche finale envoyée à son heure, fin publiée par l'horloge du serveur.
local Config, Engine = SpinArena.Config, SpinArena.Engine

local LEAD_MS = 500            -- avance de diffusion L
local COUNTDOWN_MS = 3000
local END_GRACE_MS = 500       -- marge après la fin calculée (tampon client 0,2 s + latence)
local MAX_ACTIVE = 4
local ARENA_DISTANCE = 2.0     -- distance de l'arène devant l'administrateur (m)
local PED_TO_GROUND = 0.98     -- hauteur approximative du ped au-dessus du sol (m)
local BENCH_MAX = 1000

local Runner = SpinArena.Runner
local simulate, buildChunks = Runner.simulate, Runner.buildChunks
local active, activeCount, nextId = {}, 0, 0

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function reply(src, msg)
    if src == 0 then
        log('%s', msg)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { 'ROTORBRAWL', msg } })
    end
end

local function newSeed()
    return (math.random(0, 0x7FFFFFFF) ~ (os.time() << 20) ~ GetGameTimer()) & 0x7FFFFFFFFFFF
end

local function topHeader(def)
    return {
        r = def.stats.r,
        label = def.label,
        color = def.color,
        dir = def.stats.dir,
        model = def.model or ('spin_top_' .. (def.family or 'balance')),
        parts = type(def.parts) == 'table' and { core = def.parts.core, ring = def.parts.ring, frame = def.parts.frame, tip = def.parts.tip } or nil,
    }
end

local function finish(src, match, reason)
    if active[src] ~= match then return end
    active[src] = nil
    activeCount = activeCount - 1
    if reason then
        TriggerClientEvent('spin_arena:cl:cancel', src, { matchId = match.id, reason = reason })
    end
end

local function runDisplayed(src, keyA, keyB, seed)
    local defA, defB = Config.testTops[keyA], Config.testTops[keyB]
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return reply(src, 'ped introuvable') end
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local rad = math.rad(heading)
    local arena = Config.testArena

    nextId = nextId + 1
    local match = { id = ('debug-%d'):format(nextId), cancelled = false }
    active[src] = match
    activeCount = activeCount + 1
    local goAt = GetGameTimer() + COUNTDOWN_MS
    local function startsIn()
        return math.max(0, goAt - GetGameTimer() - math.floor((GetPlayerPing(src) or 0) / 2))
    end

    -- Arène devant l'administrateur ; le cap du joueur oriente le repère local
    local center = {
        x = pos.x - math.sin(rad) * ARENA_DISTANCE,
        y = pos.y + math.cos(rad) * ARENA_DISTANCE,
        z = pos.z - PED_TO_GROUND,
    }
    -- L'en-tête porte aussi le délai de départ : le client n'a pas besoin du compte à rebours pour démarrer
    TriggerClientEvent('spin_arena:cl:match', src, {
        matchId = match.id, round = 1, bestOf = 1, startsInMs = startsIn(),
        role = 'participant', side = 1,
        arena = { x = center.x, y = center.y, z = center.z, heading = heading, scale = 1.0,
                  R = arena.R, h = arena.h, model = arena.model, floorHeight = arena.floorHeight,
                  pockets = arena.pockets },
        tops = { topHeader(defA), topHeader(defB) },
        dt = Config.dt, keyframeEvery = Config.keyframeEvery,
    })

    local function sendCountdown()
        TriggerClientEvent('spin_arena:cl:countdown', src, { matchId = match.id, round = 1, startsInMs = startsIn() })
    end
    sendCountdown()

    -- Toute erreur du calcul ou de la diffusion libère l'administrateur et prévient son client
    CreateThread(function()
        local ok, err = pcall(function()
            local params = Engine.paramsFromConfig(Config, defA.stats, defB.stats, seed)
            local outcome, frames, events, cpu = simulate(params, function() return match.cancelled end)
            if not outcome then
                log('manche %s non calculée : %s', match.id, tostring(frames))
                return finish(src, match, frames == 'cancelled' and nil or 'engine_error')
            end

            -- Calcul trop lent : on prolonge le compte à rebours plutôt que d'afficher une manche incomplète
            if GetGameTimer() > goAt - LEAD_MS then
                goAt = GetGameTimer() + 1000
                sendCountdown()
            end

            local chunks = buildChunks(frames, events, Config.dt, outcome.step)
            for i, chunk in ipairs(chunks) do
                local isLast = i == #chunks
                local sendAt = Runner.sendAt(goAt, chunk, Config.dt, LEAD_MS)
                while GetGameTimer() < sendAt do
                    if match.cancelled then return end
                    Wait(20)
                end
                if match.cancelled then return end
                TriggerClientEvent('spin_arena:cl:frames', src, {
                    matchId = match.id, round = 1, seq = i, fromStep = chunk.fromStep,
                    frames = chunk.frames, events = chunk.events, last = isLast,
                })
            end

            local endAt = goAt + math.floor(outcome.step * Config.dt * 1000) + END_GRACE_MS
            while GetGameTimer() < endAt do
                if match.cancelled then return end
                Wait(50)
            end
            TriggerClientEvent('spin_arena:cl:roundEnd', src, {
                matchId = match.id, round = 1, winner = outcome.winner, reason = outcome.reason, step = outcome.step,
            })
            log('%s seed=%d %s vs %s -> vainqueur=%s motif=%s durée=%.2fs keyframes=%d événements=%d tranches=%d calcul=%.1fms',
                match.id, seed, keyA, keyB, tostring(outcome.winner), outcome.reason, outcome.step * Config.dt,
                #frames, #events, #chunks, cpu * 1000)
            finish(src, match, nil)
        end)
        if not ok then
            log('manche %s interrompue par une erreur : %s', match.id, tostring(err))
            finish(src, match, 'engine_error')
        end
    end)

    reply(src, ('manche %s : %s contre %s, seed %d'):format(match.id, defA.label, defB.label, seed))
end

local benchRunning = false

local function runBench(src, n)
    if benchRunning then return reply(src, 'un banc est déjà en cours') end
    benchRunning = true
    CreateThread(function()
        local ok, err = pcall(function()
            local A, E = Config.testTops.attack.stats, Config.testTops.endurance.stats
            local winsA, draws, reasons, durations, cpus = 0, 0, {}, {}, {}
            local baseSeed = newSeed()
            for i = 1, n do
                local attackFirst = i % 2 == 1
                local params = Engine.paramsFromConfig(Config, attackFirst and A or E, attackFirst and E or A, baseSeed + i)
                local outcome, framesOrErr, _, cpu = simulate(params)
                if not outcome then
                    log('banc interrompu à la manche %d : %s', i, tostring(framesOrErr))
                    benchRunning = false
                    return
                end
                local attackSide = attackFirst and 1 or 2
                if outcome.winner == attackSide then winsA = winsA + 1 elseif not outcome.winner then draws = draws + 1 end
                reasons[outcome.reason] = (reasons[outcome.reason] or 0) + 1
                durations[#durations + 1] = outcome.step * Config.dt
                cpus[#cpus + 1] = cpu * 1000
                Wait(0)
            end
            table.sort(durations)
            table.sort(cpus)
            local parts = {}
            for _, key in ipairs({ 'ring_out', 'spin_out', 'double_out', 'time', 'max_steps' }) do
                if reasons[key] then parts[#parts + 1] = ('%s=%d'):format(key, reasons[key]) end
            end
            local function pct(t, p) return t[math.max(1, math.ceil(#t * p))] end
            log('banc %d manches attaque/endurance (côtés alternés), seeds %d..%d : attaque %d, endurance %d, nul %d | %s',
                n, baseSeed + 1, baseSeed + n, winsA, n - winsA - draws, draws, table.concat(parts, ' '))
            log('durée médiane %.1fs (min %.1f, max %.1f) | calcul par manche p50 %.2fms p95 %.2fms max %.2fms (CPU, %s)',
                pct(durations, 0.5), durations[1], durations[#durations], pct(cpus, 0.5), pct(cpus, 0.95), cpus[#cpus],
                os.clock and 'os.clock' or 'GetGameTimer')
            reply(src, ('banc terminé : %d manches, détails dans la console serveur'):format(n))
            benchRunning = false
        end)
        if not ok then
            log('banc interrompu par une erreur : %s', tostring(err))
            reply(src, 'banc interrompu par une erreur, voir la console serveur')
            benchRunning = false
        end
    end)
end

-- Toupie d'entraînement : assemblage de départ d'une famille du catalogue (aucun objet d'inventaire)
local function practiceDef(kitName, who, color)
    local kit = SpinArena.Parts.kits[kitName]
    if not kit then return nil end
    local stats = SpinArena.Stats.compute(kit.parts, 0)
    if not stats then return nil end
    return { label = ('%s · %s'):format(who, kit.label), color = color, stats = stats, family = kitName, parts = kit.parts }
end

local function startPractice(src, args)
    local M, A, B = SpinArena.Matches, SpinArena.Arenas, SpinArena.Bridge
    if M.byPlayer[src] then return reply(src, 'déjà dans un match (/spin_test stop pour un entraînement)') end
    local station, mine, other = args[2], args[3] or 'attack', args[4] or 'endurance'
    if station and SpinArena.Parts.kits[station] and not A.fixed[station] then
        station, mine, other = nil, args[2], args[3] or 'endurance'   -- /spin_test pratique <ma_toupie> [adversaire]
    end
    local defA = practiceDef(mine, 'Entraînement', { 255, 120, 30 })
    local defB = practiceDef(other, 'Simulé', { 40, 200, 230 })
    if not defA or not defB then return reply(src, 'toupies possibles : attack, defense, endurance, balance, mobility') end
    local ctx = B.context(src)
    if not ctx then return reply(src, 'ped introuvable') end
    local arena, code = A.place(ctx, station)
    if not arena then
        return reply(src, code == 'too_far' and 'table trop loin (15 m au plus)' or 'table introuvable ou occupée')
    end
    local match, err = M.create({
        players = { { src = src, top = mine, def = defA }, { bot = true, top = other, def = defB } },
        arena = arena, bucket = ctx.bucket, practice = true,
    })
    if not match then return reply(src, 'entraînement impossible : ' .. tostring(err)) end
    reply(src, ('entraînement sur la table %s (%s) : arme ton lanceur et vise (touche Lancer), l\'adversaire simulé lance seul ; /spin_test stop pour arrêter')
        :format(arena.fixedId or 'improvisée', (SpinArena.Config.arenaVariants[arena.variant or 'standard'] or {}).label or 'Standard'))
end

RegisterCommand('spin_test', function(src, args)
    local sub = args[1]
    if sub == 'pratique' or sub == 'practice' then
        if src == 0 then return log('depuis la console : seulement « spin_test bench [n] »') end
        return startPractice(src, args)
    end
    if sub == 'stop' and src ~= 0 then
        local m = SpinArena.Matches and SpinArena.Matches.byPlayer[src]
        if m and m.practice then
            if m.round > 1 or (m.current and m.current.goAt) then
                SpinArena.Matches.finish(m, nil, 'no_contest', { why = 'admin_stop' })
            else
                SpinArena.Matches.cancel(m, 'admin_stop')
            end
            return reply(src, 'entraînement arrêté')
        end
    end
    if sub == 'bench' then
        local n = math.tointeger(tonumber(args[2] or '100')) or 100
        return runBench(src, math.max(1, math.min(BENCH_MAX, n)))
    end
    if src == 0 then return log('depuis la console : seulement « spin_test bench [n] »') end
    if sub == 'stop' then
        local match = active[src]
        if not match then return reply(src, 'aucune manche en cours') end
        match.cancelled = true
        finish(src, match, 'admin_stop')
        return reply(src, 'manche annulée')
    end
    if active[src] then return reply(src, 'une manche est déjà en cours (/spin_test stop)') end
    if activeCount >= MAX_ACTIVE then return reply(src, 'trop de manches de test en cours') end

    local keyA, keyB = args[1] or 'attack', args[2] or 'endurance'
    if not Config.testTops[keyA] or not Config.testTops[keyB] then
        return reply(src, 'toupies possibles : attack, endurance')
    end
    local seed
    if args[3] then
        seed = math.tointeger(tonumber(args[3]))
        if not seed then return reply(src, 'seed invalide (entier attendu)') end
    else
        seed = newSeed()
    end
    runDisplayed(src, keyA, keyB, seed)
end, true)

AddEventHandler('playerDropped', function()
    local src = source
    local match = active[src]
    if match then
        match.cancelled = true
        finish(src, match, nil)
    end
end)

log('commandes admin : /spin_test pratique [table] [ma_toupie] [adversaire] (entraînement, vrai parcours) ; /spin_test <a> <b> [seed] (ancienne démo automatique)')
