-- Matchs partagés (docs/ARCHITECTURE.md §7, §8, §11) : machine à états, manches, diffusion à l'audience,
-- abandons et déconnexions traités en temps réel (ils priment sur le résultat calculé).
-- Phase 2 : les toupies sont des profils de test (TopSource). Aucune récompense ni écriture en base.
SpinArena = SpinArena or {}

local Matches = { byId = {}, byPlayer = {}, count = 0, nextId = 0, listeners = {} }

-- Époque propre à ce démarrage de la ressource : un identifiant de match n'est jamais réutilisé après un
-- redémarrage, et un message d'avant le redémarrage ne peut pas viser un nouveau match
Matches.epoch = ('%x%06x'):format(os.time() & 0xFFFFFF, math.random(0, 0xFFFFFF))

local P = SpinArena.Protocol
local Bridge, Arenas, Runner, Launch = SpinArena.Bridge, SpinArena.Arenas, SpinArena.Runner, SpinArena.Launch

local function S() return SpinArena.ServerConfig end
local function now() return GetGameTimer() end

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function newSeed()
    return (math.random(0, 0x7FFFFFFF) ~ (os.time() << 20) ~ GetGameTimer()) & 0x7FFFFFFFFFFF
end

-- Source des toupies : profils de test par défaut ; server/parts.lua la remplace (inventaire et base)
Matches.TopSource = {
    check = function(_, key)
        if SpinArena.ServerConfig.allowedTops[key] then return true end
        return false, P.codes.invalid
    end,
    resolve = function(_, key) return SpinArena.Config.testTops[key] end,
    revalidate = function() return true end,
    release = function() end,
}

local function setState(match, state)
    match.state = state
    match.stateSince = now()
end

-- Ce que le client affiche d'une toupie ; `model` = objet 3D choisi d'après l'anneau monté (Stats.model), sinon
-- celui de sa famille (toupies de test) : stream/spin_top_<forme>.ydr
local function topHeader(def)
    local parts
    if type(def.parts) == 'table' then   -- les quatre identifiants du catalogue : le client assemble la toupie pièce par pièce
        parts = { core = def.parts.core, ring = def.parts.ring, frame = def.parts.frame, tip = def.parts.tip }
    end
    return { r = def.stats.r, label = def.label, color = def.color, dir = def.stats.dir,
             model = def.model or ('spin_top_' .. (def.family or 'balance')), parts = parts }
end

-- Joueurs réels du match (l'adversaire simulé d'un entraînement n'a pas de client)
local function participants(match)
    local list = {}
    for _, p in ipairs(match.players) do
        if not p.bot then list[#list + 1] = p.src end
    end
    return list
end

-- Un envoi qui échoue ne doit jamais interrompre la logique du match
local function emit(match, name, payload)
    for src in pairs(match.audience) do
        local ok, err = pcall(TriggerClientEvent, name, src, payload)
        if not ok then log('%s : envoi de %s à %s impossible : %s', match.id, name, tostring(src), tostring(err)) end
    end
end

local function started(match)
    local round = match.current
    return match.round > 1 or (round ~= nil and round.goAt ~= nil and now() >= round.goAt)
end

-- Arène vue par le client : géométrie simulée du match, avec l'objet 3D et la hauteur du fond de SA table
local function arenaPayload(arena)
    local base = SpinArena.Config.testArena
    local out = {}
    for k, v in pairs(arena) do out[k] = v end
    out.model, out.floorHeight = arena.model or base.model, arena.floorHeight or base.floorHeight
    return out
end

-- Géométrie passée au moteur : celle de la table réservée (variante), jamais une valeur du client
local function simArena(arena)
    local base = SpinArena.Config.testArena
    return { R = arena.R or base.R, h = arena.h or base.h, pockets = arena.pockets or base.pockets,
             model = arena.model or base.model, floorHeight = arena.floorHeight or base.floorHeight,
             railBoost = arena.railBoost }
end

-- En-tête de manche adapté au destinataire (rôle, côté, délai de départ ou temps déjà écoulé)
local function header(match, src)
    local round = match.current
    local half = math.floor((GetPlayerPing(src) or 0) / 2)
    -- En préparation, aucun départ n'est fixé : le délai indiqué est celui de la préparation
    local startsIn = (round.goAt or round.deadline) - now() - half
    local side = match.sideOf[src]
    local p1, p2 = match.players[1], match.players[2]
    return {
        matchId = match.id, round = round.n, revision = round.revision, bestOf = S().match.winsNeeded * 2 - 1,
        target = (S().match.scoring and S().match.scoring.mode == 'points') and S().match.scoring.target or nil,
        score = { match.score[1], match.score[2] },
        startsInMs = math.max(0, startsIn),
        elapsedMs = (round.goAt and startsIn < 0) and -startsIn or nil,
        preparing = match.state == 'preparing' or nil,
        role = side and 'participant' or 'spectator', side = side,
        names = { p1.name, p2.name },
        -- Identifiants serveur des deux joueurs (0 = adversaire simulé) : chaque client affiche le lanceur des
        -- autres participants dans leur main (client/launcher_rivals.lua). Purement visuel.
        srcs = { p1.bot and 0 or (tonumber(p1.src) or 0), p2.bot and 0 or (tonumber(p2.src) or 0) },
        practice = match.practice or nil,
        arena = arenaPayload(match.arena),
        tops = { topHeader(p1.def), topHeader(p2.def) },
        dt = SpinArena.Config.dt, keyframeEvery = SpinArena.Config.keyframeEvery,
    }
end

local function framesPayload(match, round, index)
    local chunk = round.chunks[index]
    return {
        matchId = match.id, round = round.n, seq = index, fromStep = chunk.fromStep,
        frames = chunk.frames, events = chunk.events, last = index == #round.chunks,
    }
end

-- Fait entrer un joueur dans l'audience : en-tête, puis les tranches déjà envoyées utiles à la lecture
local function join(match, src)
    match.audience[src] = true
    -- Pendant la pause entre deux manches, il recevra l'en-tête de la suivante avec les autres
    if match.state == 'round_over' then return end
    TriggerClientEvent(P.ev.match, src, header(match, src))
    if match.state == 'preparing' then TriggerClientEvent(P.ev.prepare, src, Matches.preparePayload(match)) end
    local round = match.current
    if round.chunks and round.sent > 0 then
        local dt = SpinArena.Config.dt
        local playStep = math.max(0, (now() - round.goAt) / 1000 / dt - 1 / dt)
        local first = 1
        for i = 1, round.sent do
            if round.chunks[i].fromStep <= playStep then first = i end
        end
        for i = first, round.sent do TriggerClientEvent(P.ev.frames, src, framesPayload(match, round, i)) end
    end
end

local function cleanup(match)
    Arenas.release(match.id)
    for _, p in ipairs(match.players) do
        if Matches.byPlayer[p.src] == match then Matches.byPlayer[p.src] = nil end
        if p.def and not match.practice then pcall(Matches.TopSource.release, p.top, match.id) end
    end
    if Matches.byId[match.id] then
        Matches.byId[match.id] = nil
        Matches.count = Matches.count - 1
    end
end

local function notifyListeners(summary)
    for _, cb in ipairs(Matches.listeners) do
        local ok, err = pcall(cb, summary)
        if not ok then log('écouteur de fin de match en erreur : %s', tostring(err)) end
    end
end

-- Fin avec résultat : vainqueur (côté 1 ou 2) ou nil ; reason = 'rounds', 'draw', 'forfeit', 'no_contest'
function Matches.finish(match, winner, reason, detail)
    if match.done then return end
    match.done = true
    match.gen = match.gen + 1
    setState(match, 'finished')
    cleanup(match)
    local p1, p2 = match.players[1], match.players[2]
    -- Résumé (données serveur seulement) : manches, éjections subies, usure ajoutée (règle de Tops.onFinished :
    -- +1 par match terminé avec résultat, jamais en « sans résultat », ni à l'entraînement, ni pour un profil de test)
    local rounds, ej = {}, { 0, 0 }
    for i, h in ipairs(match.history) do
        rounds[i] = { winner = h.winner, reason = h.reason, points = h.points, durationS = math.floor((h.step or 0) * SpinArena.Config.dt * 10 + 0.5) / 10 }
        local e = h.ejections or { 0, 0 }
        ej[1], ej[2] = ej[1] + (e[1] or 0), ej[2] + (e[2] or 0)
    end
    local function wearOf(p)
        if match.practice or reason == 'no_contest' or p.bot or S().allowedTops[p.top] then return 0 end
        return 1
    end
    local summary = { rounds = rounds, ejections = { a = ej[1], b = ej[2] }, wear = { a = wearOf(p1), b = wearOf(p2) },
                      practice = match.practice == true }
    -- Résumé destiné aux écouteurs (classement, tournois) ; homologué ici, AVANT l'envoi aux clients, pour afficher le statut
    local final
    if not match.practice then
        final = {
            id = match.id, winner = winner, reason = reason, detail = detail, score = { match.score[1], match.score[2] },
            players = { { identifier = p1.identifier, name = p1.name, top = p1.top },
                        { identifier = p2.identifier, name = p2.name, top = p2.top } },
            rounds = match.history, startedAt = match.createdAt, endedAt = now(), tops = { p1.top, p2.top },
        }
        local H = SpinArena.Homologation
        if H then
            local ok, h = pcall(H.certify, final, {
                arenaKind = match.arena and match.arena.kind, arenaVariant = match.arena and match.arena.variant,
                testTop = S().allowedTops[p1.top] or S().allowedTops[p2.top] or false,
                season = SpinArena.ServerConfig.ranking and SpinArena.ServerConfig.ranking.season,
            })
            if ok then
                summary.homologation = { status = h.status, reason = h.reason, certId = h.cert and h.cert.sig and h.cert.sig:sub(1, 12) or nil }
            else
                log('%s : homologation en erreur : %s', match.id, tostring(h))
            end
        end
    end
    for src in pairs(match.audience) do
        local ok, err = pcall(TriggerClientEvent, P.ev.matchEnd, src, {
            matchId = match.id, winner = winner, reason = reason, detail = detail,
            score = { match.score[1], match.score[2] }, names = { p1.name, p2.name },
            side = match.sideOf[src], summary = summary,
        })
        if not ok then log('%s : envoi de matchEnd à %s impossible : %s', match.id, tostring(src), tostring(err)) end
    end
    log('%s terminé : vainqueur=%s motif=%s score=%d-%d %s', match.id, tostring(winner), reason,
        match.score[1], match.score[2], detail and detail.why or '')
    -- Entraînement admin : ni classement, ni usure, ni tournoi
    if match.practice then return end
    notifyListeners(final)
end

-- Fin sans résultat (avant le premier départ, ou arrêt de la ressource)
function Matches.cancel(match, reason)
    if match.done then return end
    match.done = true
    match.gen = match.gen + 1
    setState(match, 'cancelled')
    cleanup(match)
    emit(match, P.ev.cancel, { matchId = match.id, reason = reason })
    log('%s annulé : %s', match.id, reason)
end

-- Erreur interne : jamais de vainqueur inventé
function Matches.fail(match, err)
    log('%s en erreur (état %s, manche %d) : %s', match.id, tostring(match.state), match.round, tostring(err))
    if started(match) then
        Matches.finish(match, nil, 'no_contest', { why = 'error' })
    else
        Matches.cancel(match, 'error')
    end
end

local startRound

-- Règles de points : { target, maxRounds, points(reason) } ; nil en mode 'rounds' (une manche = un point, `winsNeeded`)
local function pointRules()
    local sc = S().match.scoring
    if type(sc) ~= 'table' or sc.mode ~= 'points' then return nil end
    return {
        target = sc.target, maxRounds = sc.maxRounds or S().match.maxRounds,
        pointsFor = function(reason)
            local pts = sc.points or {}
            return tonumber(pts[reason]) or tonumber(pts.default) or 1
        end,
    }
end

local function endRound(match, round, gen)
    if match.gen ~= gen or match.done then return end
    local o = round.outcome
    local cfg = S().match
    local rules = pointRules()
    local gained = o.winner and (rules and rules.pointsFor(o.reason) or 1) or 0
    if o.winner then match.score[o.winner] = match.score[o.winner] + gained end
    match.history[#match.history + 1] = { round = round.n, winner = o.winner, reason = o.reason, step = o.step, seed = round.seed,
        ejections = round.ejections or { 0, 0 }, points = rules and gained or nil }
    emit(match, P.ev.roundEnd, {
        matchId = match.id, round = round.n, winner = o.winner, reason = o.reason, step = o.step,
        score = { match.score[1], match.score[2] }, points = rules and gained or nil,
    })
    local a, b = match.score[1], match.score[2]
    local needed = rules and rules.target or cfg.winsNeeded
    local maxRounds = rules and rules.maxRounds or cfg.maxRounds
    if a >= needed then return Matches.finish(match, 1, 'rounds') end
    if b >= needed then return Matches.finish(match, 2, 'rounds') end
    if round.n >= maxRounds then
        if a == b then return Matches.finish(match, nil, 'draw') end
        return Matches.finish(match, a > b and 1 or 2, 'rounds')
    end
    setState(match, 'round_over')
    SetTimeout(cfg.intermissionMs, function()
        if match.gen == gen and not match.done then startRound(match, round.n + 1) end
    end)
end

-- Calcul de la manche pendant le compte à rebours, puis diffusion à l'heure du serveur
local function runRound(match, round, gen)
    local cfg, dt = S().match, SpinArena.Config.dt
    local p1, p2 = match.players[1], match.players[2]
    local sa, sb = p1.def.stats, p2.def.stats
    if round.launch[1] then sa = Launch.apply(sa, round.launch[1].q, cfg.launch, round.launch[1].tilt, (Launch.mods(p1.launcher))) end
    if round.launch[2] then sb = Launch.apply(sb, round.launch[2].q, cfg.launch, round.launch[2].tilt, (Launch.mods(p2.launcher))) end
    local params = SpinArena.Engine.paramsFromConfig(SpinArena.Config, sa, sb, round.seed, simArena(match.arena))
    local outcome, frames, events, cpu, perf = Runner.simulate(params, function() return match.gen ~= gen end)
    if match.gen ~= gen then return end
    if not outcome then error(frames, 0) end
    -- Mesure réelle (journal serveur) : coût du calcul et plus longue tranche bloquante du fil serveur
    if perf then
        log('%s manche %d calculée : %.2f s de combat, CPU %.1f ms en %d tranches, tranche max %.2f ms',
            match.id, round.n, outcome.step * dt, (cpu or 0) * 1000, perf.slices, perf.maxSlice * 1000)
    end

    -- Calcul trop lent : on repousse le départ plutôt que d'afficher une manche incomplète. La révision
    -- augmente pour que le client ignore un ancien compte à rebours arrivé en retard.
    if now() > round.goAt - cfg.leadMs then
        round.goAt = now() + 1000
        round.revision = round.revision + 1
        for src in pairs(match.audience) do
            pcall(TriggerClientEvent, P.ev.countdown, src, { matchId = match.id, round = round.n,
                revision = round.revision, startsInMs = header(match, src).startsInMs })
        end
    end

    round.outcome = outcome
    -- Éjections subies par côté (résumé de fin de match) : événements ring_out du moteur
    round.ejections = { 0, 0 }
    for _, ev in ipairs(events) do
        if ev.t == 'ring_out' and (ev.a == 1 or ev.a == 2) then round.ejections[ev.a] = round.ejections[ev.a] + 1 end
    end
    round.chunks = Runner.buildChunks(frames, events, dt, outcome.step)
    for i, chunk in ipairs(round.chunks) do
        local at = Runner.sendAt(round.goAt, chunk, dt, cfg.leadMs)
        while now() < at do
            if match.gen ~= gen then return end
            if match.state == 'countdown' and now() >= round.goAt then setState(match, 'playing') end
            Wait(20)
        end
        if match.gen ~= gen then return end
        if match.state == 'countdown' and now() >= round.goAt then setState(match, 'playing') end
        round.sent = i
        local payload = framesPayload(match, round, i)
        for src in pairs(match.audience) do TriggerClientEvent(P.ev.frames, src, payload) end
    end

    local endAt = round.goAt + math.floor(outcome.step * dt * 1000) + cfg.endGraceMs
    while now() < endAt do
        if match.gen ~= gen then return end
        if match.state == 'countdown' and now() >= round.goAt then setState(match, 'playing') end
        Wait(50)
    end
    endRound(match, round, gen)
end

-- Départ commun : compte à rebours fixé par le serveur, puis calcul et diffusion de la manche
local function beginCountdown(match, round, gen, sendHeader)
    round.goAt = now() + S().match.countdownMs
    round.revision = round.revision + (sendHeader and 0 or 1)
    setState(match, 'countdown')
    for src in pairs(match.audience) do
        local h = header(match, src)
        if sendHeader then pcall(TriggerClientEvent, P.ev.match, src, h) end
        pcall(TriggerClientEvent, P.ev.countdown, src, { matchId = match.id, round = round.n, revision = round.revision, startsInMs = h.startsInMs })
    end
    CreateThread(function()
        local ok, err = pcall(runRound, match, round, gen)
        if not ok and match.gen == gen then Matches.fail(match, err) end
    end)
end

-- État de préparation diffusé à toute l'audience (participants et spectateurs) : jamais de nonce ni de jauge
function Matches.preparePayload(match)
    local round, cfg = match.current, S().match
    return {
        matchId = match.id, round = round.n, revision = round.revision,
        deadlineInMs = math.max(0, round.deadline - now()),
        ready = { round.launch[1] ~= nil, round.launch[2] ~= nil },
        rules = { prepareMs = cfg.prepareMs, firstRound = 'cancel', later = cfg.prepareTimeout },
    }
end

local function emitPrepare(match)
    emit(match, P.ev.prepare, Matches.preparePayload(match))
end

-- Délai de préparation dépassé : jamais de lancement automatique
local function prepareTimeout(match, round, gen)
    if match.gen ~= gen or match.done or match.state ~= 'preparing' or match.current ~= round then return end
    local missing = {}
    for side = 1, 2 do
        if not round.launch[side] then missing[#missing + 1] = side end
    end
    if #missing == 0 then return end
    log('%s manche %d : préparation non terminée par %s', match.id, round.n, table.concat(missing, ' et '))
    if round.n == 1 then return Matches.cancel(match, 'prepare_timeout') end
    if #missing == 2 or S().match.prepareTimeout ~= 'forfeit_round' then
        return Matches.finish(match, nil, 'no_contest', { why = 'prepare_timeout' })
    end
    round.outcome = { winner = 3 - missing[1], reason = 'prepare_timeout', step = 0 }
    endRound(match, round, gen)
end

function startRound(match, n)
    match.gen = match.gen + 1
    local gen = match.gen
    local cfg = S().match
    local round = { n = n, seed = newSeed(), sent = 0, revision = 1, launch = {}, arms = {} }
    match.round, match.current = n, round
    if cfg.manualLaunch == false then return beginCountdown(match, round, gen, true) end
    round.deadline = now() + cfg.prepareMs
    setState(match, 'preparing')
    for src in pairs(match.audience) do pcall(TriggerClientEvent, P.ev.match, src, header(match, src)) end
    emitPrepare(match)
    -- Entraînement : l'adversaire simulé lance seul après un court délai, avec une qualité fixée par le serveur
    for side, p in ipairs(match.players) do
        if p.bot then
            local pc = cfg.practice or {}
            SetTimeout(pc.botLaunchMs or 2500, function()
                if match.gen ~= gen or match.done or match.state ~= 'preparing' or match.current ~= round then return end
                round.launch[side] = { q = pc.botQuality or 0.5, at = now(), bot = true }
                emitPrepare(match)
                if round.launch[1] and round.launch[2] then beginCountdown(match, round, gen, false) end
            end)
        end
    end
    SetTimeout(cfg.prepareMs, function()
        local ok, err = pcall(prepareTimeout, match, round, gen)
        if not ok and match.gen == gen then Matches.fail(match, err) end
    end)
end

local function newNonce()
    local t = {}
    for i = 1, 8 do t[i] = ('%04x'):format(math.random(0, 0xFFFF)) end
    return table.concat(t)
end

local function fail(code) return { ok = false, code = code } end

-- Effets du lanceur du joueur du côté `side` et réglages de jauge/tirage qui en résultent
local function launcherOf(match, side)
    local mods, id = Launch.mods(match.players[side].launcher)
    return mods, id, Launch.cfgFor(S().match.launch, mods)
end

-- Manche en préparation de CE joueur, encore valide : participant, bon match, bonne manche, même personnage,
-- toupie toujours verrouillée par le match, toujours possédée, lanceur toujours présent
local function preparingFor(src, matchId, roundN)
    local match = Matches.byPlayer[src]
    if not match or match.done or match.id ~= matchId then return nil, P.codes.not_found end
    if match.state ~= 'preparing' or match.current.n ~= roundN then return nil, P.codes.not_preparing end
    local side = match.sideOf[src]
    local p = match.players[side]
    if Bridge.identifier(src) ~= p.identifier then return nil, P.codes.error end
    -- Entraînement : toupie du catalogue, sans objet d'inventaire à revalider
    local ok, code = true, nil
    if not match.practice then ok, code = Matches.TopSource.revalidate(src, p.top, match.id) end
    if not ok then return nil, code or P.codes.no_top end
    return match, side
end

function Matches.launchArm(src, matchId, roundN)
    local match, side = preparingFor(src, matchId, roundN)
    if not match then return fail(side) end
    local round = match.current
    if round.launch[side] then return fail(P.codes.already_launched) end
    local mods, lid, cfg = launcherOf(match, side)
    local arm = { nonce = newNonce(), src = src, issuedAt = now(), gauge = Launch.newGauge(cfg) }
    arm.expiresAt = arm.issuedAt + cfg.armTtlMs
    round.arms[side] = arm   -- remplace un armement précédent : l'ancien nonce ne vaut plus rien
    return {
        ok = true, code = P.codes.ok, nonce = arm.nonce, gauge = arm.gauge, expiresInMs = cfg.armTtlMs,
        minHoldMs = cfg.minHoldMs, deadlineInMs = math.max(0, round.deadline - now()),
        pull = { minMs = cfg.pullMinMs, maxMs = cfg.pullMaxMs, fadeMs = cfg.pullFadeMs },   -- affichage seulement
        launcher = { id = lid, label = mods.label },
    }
end

-- Prise de la tirette : le serveur note l'instant (heure de RÉCEPTION) et la qualité de prise sur la jauge, moins
-- le ping mesuré par le serveur (plafonné). Le nonce reste valable pour le tirage ; une prise refusée le consomme.
function Matches.launchGrip(src, matchId, roundN, nonce)
    local match, side = preparingFor(src, matchId, roundN)
    if not match then return fail(side) end
    local round = match.current
    if round.launch[side] then return fail(P.codes.already_launched) end
    local arm = round.arms[side]
    if not arm or arm.src ~= src or arm.nonce ~= nonce then return fail(P.codes.bad_nonce) end
    if arm.gripAt then return fail(P.codes.already_gripped) end   -- double appui : l'armement reste intact
    local _, _, cfg = launcherOf(match, side)
    local t = now()
    if t > arm.expiresAt then round.arms[side] = nil; return fail(P.codes.expired) end
    if t - arm.issuedAt < cfg.minHoldMs then round.arms[side] = nil; return fail(P.codes.too_early) end
    local comp = math.max(0, math.min(GetPlayerPing(src) or 0, cfg.maxLatencyCompMs))
    arm.gripAt = t
    arm.gripQ = Launch.quality(arm.gauge, t - arm.issuedAt - comp)
    return { ok = true, code = P.codes.ok, grade = Launch.grade(arm.gripQ) }
end

-- Tirage (ou appui rapide sans prise : le tirage compte alors 0). tilt : −1 vers le bord, 0 droit, 1 vers le centre.
function Matches.launchRelease(src, matchId, roundN, nonce, tilt)
    local match, side = preparingFor(src, matchId, roundN)
    if not match then return fail(side) end
    local round = match.current
    if round.launch[side] then return fail(P.codes.already_launched) end
    local arm = round.arms[side]
    if not arm or arm.src ~= src or arm.nonce ~= nonce then return fail(P.codes.bad_nonce) end
    round.arms[side] = nil   -- usage unique, avant tout calcul
    local _, _, cfg = launcherOf(match, side)
    local t = now()
    if t > arm.expiresAt then return fail(P.codes.expired) end
    if t - arm.issuedAt < cfg.minHoldMs then return fail(P.codes.too_early) end
    local gripQ, pullQ
    if arm.gripAt then
        gripQ, pullQ = arm.gripQ, Launch.pullQuality(t - arm.gripAt, cfg)
    else
        -- Heure de RÉCEPTION serveur, moins le ping mesuré par le serveur (plafonné) : aucune donnée du client
        local comp = math.max(0, math.min(GetPlayerPing(src) or 0, cfg.maxLatencyCompMs))
        gripQ, pullQ = Launch.quality(arm.gauge, t - arm.issuedAt - comp), 0
    end
    local q = Launch.combine(gripQ, pullQ, cfg)
    round.launch[side] = { q = q, at = t, tilt = (tilt == -1 or tilt == 1) and tilt or 0 }
    emitPrepare(match)
    if round.launch[1] and round.launch[2] then beginCountdown(match, round, match.gen, false) end
    return { ok = true, code = P.codes.ok, grade = Launch.grade(q), grip = Launch.grade(gripQ), pull = Launch.grade(pullQ) }
end

-- Abandon d'un participant (commande, déconnexion, mort, sortie de zone, véhicule)
function Matches.abandon(src, why)
    local match = Matches.byPlayer[src]
    if not match or match.done then return false end
    local side = match.sideOf[src]
    match.players[side].left = why
    if not started(match) then
        Matches.cancel(match, why)
        return true
    end
    local other = match.players[3 - side]
    if other.left or not Bridge.online(other.src) then
        Matches.finish(match, nil, 'no_contest', { why = why, by = side })
    elseif why == 'death' and S().rules.onDeath == 'no_contest' then
        Matches.finish(match, nil, 'no_contest', { why = why, by = side })
    else
        Matches.finish(match, 3 - side, 'forfeit', { why = why, by = side })
    end
    return true
end

-- Surveillance : participants dans la zone, audience à jour, aucun état bloqué
local function watchdog(match)
    local cfg = S()
    while not match.done do
        Wait(cfg.arena.audienceRefreshMs)
        if match.done then return end
        for _, p in ipairs(match.players) do
            if match.done then return end
            local ctx = not p.bot and Bridge.context(p.src)
            if p.bot then
                -- adversaire simulé d'un entraînement : rien à surveiller
            elseif not ctx then
                Matches.abandon(p.src, 'disconnect')
            elseif ctx.dead then
                Matches.abandon(p.src, 'death')
            else
                local away = ctx.inVehicle or ctx.bucket ~= match.bucket
                    or Arenas.distance(match.arena, ctx.coords) > cfg.arena.watchRadius
                if away then
                    if not p.awaySince then
                        p.awaySince = now()
                        TriggerClientEvent(P.ev.notify, p.src, {
                            code = 'leave_zone_warning', args = { seconds = math.floor(cfg.rules.leaveGraceMs / 1000) },
                        })
                    elseif now() - p.awaySince >= cfg.rules.leaveGraceMs then
                        Matches.abandon(p.src, ctx.inVehicle and 'vehicle' or 'left_zone')
                    end
                else
                    p.awaySince = nil
                end
            end
        end
        if match.done then return end
        Matches.refreshAudience(match)
        if now() - match.stateSince > cfg.match.stateTimeoutMs then
            Matches.fail(match, 'state_timeout')
        end
    end
end

-- Plafond de matchs suivis par un joueur (arena.maxWatched, son propre match compris) : au-delà, il n'est pas
-- ajouté à une audience de plus (il ne reçoit rien de ce match). 1 = ancien comportement (un seul combat visible).
local function watchingOther(match, src)
    local n = 0
    local own = Matches.byPlayer[src]
    if own and own ~= match then n = n + 1 end
    for _, m in pairs(Matches.byId) do
        if m ~= match and m ~= own and m.audience[src] then n = n + 1 end
    end
    return n >= (S().arena.maxWatched or 1)
end

function Matches.refreshAudience(match)
    local want = {}
    for _, src in ipairs(Arenas.audience(match.arena, match.bucket, participants(match))) do
        if match.sideOf[src] or not watchingOther(match, src) then want[src] = true end
    end
    for src in pairs(want) do
        if not match.audience[src] and Bridge.online(src) then join(match, src) end
    end
    for src in pairs(match.audience) do
        if not want[src] and not match.sideOf[src] then
            match.audience[src] = nil
            if Bridge.online(src) then TriggerClientEvent(P.ev.unsub, src, { matchId = match.id }) end
        end
    end
end

function Matches.isBusy(src)
    return Matches.byPlayer[src] ~= nil
end

-- Crée un match : def = { players = { { src, top }, { src, top } }, arena, bucket }
function Matches.create(def)
    local codes = P.codes
    if Matches.count >= S().match.maxConcurrent then return nil, codes.server_busy end
    for _, p in ipairs(def.players) do
        if not p.bot and Matches.byPlayer[p.src] then return nil, codes.already_in_match end
    end
    Matches.nextId = Matches.nextId + 1
    local id = ('m%s-%d'):format(Matches.epoch, Matches.nextId)
    local arena, code = Arenas.reserve(id, def.arena, def.bucket)
    if not arena then return nil, code end

    local match = {
        id = id, gen = 0, round = 0, score = { 0, 0 }, history = {}, players = {}, sideOf = {},
        audience = {}, arena = arena, bucket = def.bucket, createdAt = now(), done = false,
        practice = def.practice == true or nil,
    }
    -- Joueurs réservés AVANT toute attente (base) : une autre demande simultanée les voit occupés.
    -- Entraînement : le côté bot = adversaire simulé par le serveur (aucun client, aucun src réel).
    for side, p in ipairs(def.players) do
        if p.bot then
            match.players[side] = { src = -(1000000 + Matches.nextId), side = side, top = p.top, bot = true, launcher = 'cord',
                                    name = 'Simulé', def = p.def }   -- court : le panneau de table est étroit (titre « Entraînement »)
        else
            match.players[side] = {
                src = p.src, side = side, top = p.top, def = p.def,
                name = Bridge.name(p.src), identifier = Bridge.identifier(p.src),
                -- Lanceur utilisé pendant tout le match (celui de l'inventaire à l'ouverture du match)
                launcher = SpinArena.Inventory.launcherType(p.src),
            }
            match.sideOf[p.src] = side
            Matches.byPlayer[p.src] = match
        end
    end
    Matches.byId[id] = match
    Matches.count = Matches.count + 1
    setState(match, 'locking')
    for _, p in ipairs(match.players) do
        -- Entraînement : définition fournie (catalogue, sans inventaire) ; sinon toupie réelle verrouillée
        local topDef, terr = p.def, nil
        if not topDef then topDef, terr = Matches.TopSource.resolve(p.src, p.top, id) end
        if not topDef or match.done or (not p.bot and not Bridge.online(p.src)) then
            if match.done then
                -- Annulé pendant l'attente : cleanup a déjà tourné sans voir cette toupie, verrouillée depuis
                if topDef and not p.def and not match.practice then pcall(Matches.TopSource.release, p.top, id) end
            else
                match.done = true
                p.def = p.def or topDef   -- toupie verrouillée mais joueur parti : cleanup la libère
                cleanup(match)
            end
            return nil, terr or codes.offline
        end
        p.def = topDef
    end
    for _, p in ipairs(match.players) do
        if not p.bot then match.audience[p.src] = true end
    end
    log('%s créé : %s (%s) contre %s (%s)', id, match.players[1].name, match.players[1].top,
        match.players[2].name, match.players[2].top)
    local ok, err = pcall(startRound, match, 1)
    if not ok then
        log('%s : démarrage impossible : %s', id, tostring(err))
        match.done = true
        cleanup(match)
        return nil, codes.error
    end
    CreateThread(function()
        local ok, err = pcall(watchdog, match)
        if not ok then Matches.fail(match, err) end
    end)
    return match
end

function Matches.forfeit(src)
    if not Matches.byPlayer[src] then return { ok = false, code = P.codes.not_found } end
    Matches.abandon(src, 'forfeit')
    return { ok = true, code = P.codes.ok }
end

function Matches.onPlayerLeft(src, why)
    Matches.abandon(src, why)
    for _, match in pairs(Matches.byId) do match.audience[src] = nil end
end

function Matches.onDeath(src)
    if Matches.byPlayer[src] then Matches.abandon(src, 'death') end
end

function Matches.stateFor(src)
    local match = Matches.byPlayer[src]
    if match then return { matchId = match.id, role = 'participant', side = match.sideOf[src] } end
    for _, m in pairs(Matches.byId) do
        if m.audience[src] then return { matchId = m.id, role = 'spectator' } end
    end
    return nil
end

function Matches.stopAll(reason)
    local list = {}
    for _, m in pairs(Matches.byId) do list[#list + 1] = m end
    for _, m in ipairs(list) do Matches.cancel(m, reason) end
end

-- Abonnement aux fins de match (classement et tournois en phase 6)
function Matches.onFinished(cb)
    Matches.listeners[#Matches.listeners + 1] = cb
end

SpinArena.Matches = Matches
return Matches
