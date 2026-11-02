-- Point d'entrée serveur : enregistre les callbacks et câble le cycle de vie des joueurs et de la ressource.
-- Chaque requête suit le même ordre : fréquence → schéma → verrou du joueur → module (docs/SECURITY.md §4).
local P = SpinArena.Protocol
local S = SpinArena.ServerConfig
local Security, Challenges, Matches, Bridge = SpinArena.Security, SpinArena.Challenges, SpinArena.Matches, SpinArena.Bridge

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local INT_MAX = 0x7FFFFFFF
local TOP = { 'string', 24, '^[%w_]+$' }   -- profil de test ou uid de toupie (vérifié ensuite par TopSource)
local schemas = {
    challenge = { target = { 'integer', 1, 65535 }, top = TOP, station = { 'string', 32, '^[%w_%-]+$', optional = true } },
    respond = { id = { 'integer', 1, INT_MAX }, accept = { 'boolean' }, top = { 'string', 24, '^[%w_]+$', optional = true } },
    cancel = { id = { 'integer', 1, INT_MAX } },
    forfeit = {},
    state = {},
    leaderboard = {},
    tops = {},
    shop = {},
    shopBuy = { shopId = { 'integer', 0, 64 }, item = { 'string', 48, '^[%w_]+:[%w_]+$' }, count = { 'integer', 1, 10 } },
    queueJoin = { station = { 'string', 32, '^[%w_%-]+$' }, top = TOP },
    queueLeave = {},
    launchArm = { matchId = { 'string', 64, '^[%w%-]+$' }, round = { 'integer', 1, 99 } },
    launchGrip = { matchId = { 'string', 64, '^[%w%-]+$' }, round = { 'integer', 1, 99 }, nonce = { 'string', 32, '^%x+$' } },
    launchRelease = { matchId = { 'string', 64, '^[%w%-]+$' }, round = { 'integer', 1, 99 }, nonce = { 'string', 32, '^%x+$' },
                      tilt = { 'integer', -1, 1, optional = true } },
    tournamentCreate = { name = { 'string', 32, nil }, size = { 'integer', 4, 16 }, minutes = { 'integer', 1, 60 } },
    tournamentJoin = { id = { 'integer', 1, INT_MAX }, top = TOP },
    tournamentLeave = {},
    tournamentStatus = {},
    workshop = {
        action = { 'enum', { equip = true, repair = true, rename = true, paint = true, disassemble = true } },
        uid = { 'string', 24, '^ST[0-9A-Z]+$' },
        part = { 'string', 32, '^[%w_]+$', optional = true },
        name = { 'string', 48, nil, optional = true },
        paint = { 'string', 16, '^[%w_]+$', optional = true },
    },
}

local actions = {
    challenge = function(src, d) return Challenges.send(src, d.target, d.top, d.station) end,
    respond = function(src, d) return Challenges.respond(src, d.id, d.accept, d.top) end,
    cancel = function(src, d) return Challenges.cancel(src, d.id) end,
    forfeit = function(src) return Matches.forfeit(src) end,
    leaderboard = function(src) return SpinArena.Ranking.leaderboard(src) end,
    tops = function(src) return SpinArena.Tops.list(src) end,
    shop = function(src) return SpinArena.Shop.info(src) end,
    shopBuy = function(src, d) return SpinArena.Shop.buy(src, d.shopId, d.item, d.count) end,
    queueJoin = function(src, d) return SpinArena.Queue.join(src, d.station, d.top) end,
    queueLeave = function(src) return SpinArena.Queue.leave(src, 'demande du joueur') end,
    launchArm = function(src, d) return Matches.launchArm(src, d.matchId, d.round) end,
    launchGrip = function(src, d) return Matches.launchGrip(src, d.matchId, d.round, d.nonce) end,
    launchRelease = function(src, d) return Matches.launchRelease(src, d.matchId, d.round, d.nonce, d.tilt) end,
    tournamentCreate = function(src, d) return SpinArena.Tournaments.create(src, d) end,
    tournamentJoin = function(src, d) return SpinArena.Tournaments.join(src, d) end,
    tournamentLeave = function(src) return SpinArena.Tournaments.leave(src) end,
    tournamentStatus = function(src) return SpinArena.Tournaments.status(src) end,
    workshop = function(src, d) return SpinArena.Workshop.handle(src, d) end,
    state = function(src)
        local r = Challenges.stateFor(src)
        r.ok, r.code, r.match = true, P.codes.ok, Matches.stateFor(src)
        r.queued = SpinArena.Queue and SpinArena.Queue.stateFor(src) or nil
        return r
    end,
}

for action, name in pairs(P.cb) do
    lib.callback.register(name, function(src, payload)
        if not Security.allow(src, action) then return { ok = false, code = P.codes.rate_limited } end
        local valid, field = Security.check(payload, schemas[action])
        if not valid then
            if S.debugLog then log('requête %s refusée de %s : champ %s', action, src, tostring(field)) end
            return { ok = false, code = P.codes.invalid }
        end
        local ok, res = pcall(Security.withLock, src, function() return actions[action](src, payload or {}) end)
        if not ok then
            log('erreur dans %s pour %s : %s', action, src, tostring(res))
            return { ok = false, code = P.codes.error }
        end
        return res
    end)
end

Bridge.onLeave(function(src, why)
    Challenges.onPlayerLeft(src)
    if SpinArena.Queue then SpinArena.Queue.leave(src, 'déconnexion') end
    Matches.onPlayerLeft(src, why)
    Security.forget(src)
end)

Bridge.onDeath(function(src)
    Matches.onDeath(src)
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then Matches.stopAll('resource_stop') end
end)

-- /spin_admin list | cancel <matchId> : réservé aux administrateurs (ACE command.spin_admin)
RegisterCommand('spin_admin', function(src, args)
    local function reply(msg)
        if src == 0 then log('%s', msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'ROTORBRAWL', msg } }) end
    end
    if args[1] == 'arena' or args[1] == 'zone' then
        SpinArena.Arenas.admin(src, args, reply)
        -- Les points de vente suivent les arènes fixes
        if args[1] == 'arena' and (args[2] == 'add' or args[2] == 'remove') then
            SpinArena.Shop.register()
            -- Les clients ne relisaient les stations qu'au chargement : prévenus joueur par joueur (jamais en diffusion -1)
            for _, id in ipairs(GetPlayers()) do TriggerClientEvent(SpinArena.Protocol.ev.stations, tonumber(id)) end
        end
        return
    end
    if args[1] == 'achats' then
        -- Achats incertains ou ni livrés ni remboursés (Shop.buy, aussi dans data/shop_unresolved.log) : à régulariser
        local list = SpinArena.Shop.unresolved or {}
        if #list == 0 then return reply('aucun achat non résolu') end
        for i, u in ipairs(list) do
            reply(('#%d joueur %s (%s) : %d pour %s ×%d, étape %s — %s (%s)'):format(i, tostring(u.src),
                tostring(u.identifier or '?'), u.amount, tostring(u.item), u.count, tostring(u.stage), tostring(u.error),
                tostring(u.detail or '')))
        end
        return
    end
    if args[1] == 'tournoi' then
        return SpinArena.Tournaments.admin(src, args, reply)
    end
    if args[1] == 'cancel' and args[2] then
        local match = Matches.byId[args[2]]
        if not match then return reply('match introuvable') end
        Matches.cancel(match, 'admin')
        log('%s annulé par %s', match.id, src == 0 and 'la console' or Bridge.name(src))
        return reply('match annulé')
    end
    local n = 0
    for id, m in pairs(Matches.byId) do
        n = n + 1
        reply(('%s : %s contre %s, manche %d, score %d-%d, état %s'):format(id, m.players[1].name, m.players[2].name,
            m.round, m.score[1], m.score[2], m.state))
    end
    if n == 0 then reply('aucun match en cours') end
end, true)

-- ox_inventory redémarré pendant que Chaos_Arena tourne : ses hooks (identifiants, verrou des toupies en match,
-- glisser-déposer, icônes) et ceux de la boutique disparaissent avec lui ; on les réenregistre dès qu'il est prêt
AddEventHandler('onResourceStart', function(name)
    if name ~= 'ox_inventory' then return end
    CreateThread(function()
        local waited = 0
        while GetResourceState('ox_inventory') ~= 'started' and waited < 30000 do Wait(250); waited = waited + 250 end
        Wait(500)
        local ok, err = pcall(function()
            SpinArena.Inventory.hooks = {}
            SpinArena.Shop.hooks = nil
            SpinArena.Inventory.registerHooks()
            SpinArena.Shop.register()
        end)
        log('ox_inventory redémarré : hooks d\'inventaire et boutique %s', ok and 'réenregistrés' or ('en erreur : ' .. tostring(err)))
    end)
end)

-- Base et inventaire : schéma, reprise après redémarrage, hooks (en arrière-plan : la base répond en différé)
CreateThread(function()
    local ok, err = pcall(function()
        SpinArena.Database.init()
        SpinArena.RankingSQL.init()
        -- Hooks d'inventaire dès qu'ox_inventory est là, même sans base (identifiants, toupies verrouillées)
        SpinArena.Inventory.registerHooks()
        SpinArena.Shop.register()
    end)
    if not ok then log('initialisation base/inventaire en erreur : %s', tostring(err)) end
    log('toupies réelles et atelier : %s', SpinArena.Tops.enabled() and 'actifs' or 'désactivés (profils de test)')
end)

local fixedCount, zoneCount = SpinArena.Arenas.load()
log('arènes fixes : %d, zones autorisées : %d', fixedCount, zoneCount)
-- Extensions déjà démarrées (Chaos_Arena relancé) : elles se réenregistrent sur cet événement (server/extensions.lua)
if SpinArena.Extensions then SpinArena.Extensions.announceReady() end

log('chargé : défis, matchs, arènes, classement, toupies et atelier')
