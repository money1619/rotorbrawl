-- Classement (phase 6) : cote Elo par identifiant et par saison, alimentée par les fins de match.
-- Le stockage passe par une interface Store remplaçable : en mémoire par défaut, SQL (oxmysql) plus tard.
SpinArena = SpinArena or {}

local Ranking = {}

local DEFAULTS = { season = 1, k = 24, start = 1000, minForfeitMs = 30000, top = 20 }

local function cfg()
    local c = SpinArena.ServerConfig and SpinArena.ServerConfig.ranking or {}
    return setmetatable({}, { __index = function(_, key)
        if c[key] ~= nil then return c[key] end
        return DEFAULTS[key]
    end })
end

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function round(x) return math.floor(x + 0.5) end

-- Tri du classement : cote, puis victoires, puis identifiant (ordre stable entre deux appels)
local function better(a, b)
    if a.rating ~= b.rating then return a.rating > b.rating end
    if a.wins ~= b.wins then return a.wins > b.wins end
    return a.identifier < b.identifier
end

-------------------------------------------------------------------------------
-- Store en mémoire. Interface attendue de tout Store :
--   get(season, identifier) -> ligne | nil
--   put(season, ligne)                         (crée ou remplace)
--   top(season, n) -> lignes triées (n au plus)
--   rank(season, identifier) -> position (1 = premier) | nil
-- Ligne : { identifier, name, rating, wins, losses, draws, updatedAt }
-------------------------------------------------------------------------------

function Ranking.MemoryStore()
    local seasons, recorded = {}, {}
    local function rows(season)
        seasons[season] = seasons[season] or {}
        return seasons[season]
    end
    local function sorted(season)
        local list = {}
        for _, r in pairs(rows(season)) do list[#list + 1] = r end
        table.sort(list, better)
        return list
    end
    local store = {}
    function store.get(season, identifier)
        local r = rows(season)[identifier]
        if not r then return nil end
        return { identifier = r.identifier, name = r.name, rating = r.rating, wins = r.wins, losses = r.losses,
            draws = r.draws, updatedAt = r.updatedAt }
    end
    function store.put(season, row)
        rows(season)[row.identifier] = { identifier = row.identifier, name = row.name, rating = row.rating,
            wins = row.wins, losses = row.losses, draws = row.draws, updatedAt = row.updatedAt }
    end
    function store.hasMatch(season, id)
        return recorded[season] and recorded[season][id] or false
    end
    function store.putPair(season, a, b, id)
        if id and store.hasMatch(season, id) then return false, 'duplicate' end
        store.put(season, a); store.put(season, b)
        if id then recorded[season] = recorded[season] or {}; recorded[season][id] = true end
        return true
    end
    function store.top(season, n)
        local list, out = sorted(season), {}
        for i = 1, math.min(n, #list) do out[i] = list[i] end
        return out
    end
    function store.rank(season, identifier)
        for i, r in ipairs(sorted(season)) do
            if r.identifier == identifier then return i end
        end
        return nil
    end
    return store
end

Ranking.store = Ranking.MemoryStore()

function Ranking.setStore(store)
    Ranking.store = store
end

-------------------------------------------------------------------------------
-- Cote Elo
-------------------------------------------------------------------------------

-- Probabilité de victoire de a contre b
function Ranking.expected(a, b)
    return 1 / (1 + 10 ^ ((b - a) / 400))
end

-- Variation entière pour le joueur a (le joueur b reçoit l'opposé : somme nulle)
function Ranking.delta(a, b, scoreA, k)
    return round(k * (scoreA - Ranking.expected(a, b)))
end

local function load(season, player)
    local row = Ranking.store.get(season, player.identifier)
    if not row then
        row = { identifier = player.identifier, rating = cfg().start, wins = 0, losses = 0, draws = 0 }
    end
    row.name = player.name or row.name
    return row
end

-- Pourquoi un match ne compte pas (nil = il compte)
function Ranking.unratedReason(summary)
    if type(summary) ~= 'table' or type(summary.players) ~= 'table' then return 'invalid' end
    local p1, p2 = summary.players[1], summary.players[2]
    if not p1 or not p2 or type(p1.identifier) ~= 'string' or type(p2.identifier) ~= 'string' then return 'invalid' end
    if p1.identifier == p2.identifier then return 'same_identity' end
    if summary.reason == 'no_contest' then return 'no_contest' end
    -- Homologation : sans certificat valide (ou match amical), le match ne compte pas
    local H = SpinArena.Homologation
    if H then
        local problem = H.problem(summary)
        if problem then return problem end
    end
    if summary.reason == 'forfeit' then
        local duration = (summary.endedAt or 0) - (summary.startedAt or 0)
        if duration < cfg().minForfeitMs then return 'early_forfeit' end
    end
    if summary.winner ~= 1 and summary.winner ~= 2 and summary.reason ~= 'draw' then return 'no_result' end
    return nil
end

-- Abonné à Matches.onFinished : met à jour les deux joueurs ; renvoie les deux lignes, ou nil et le motif
function Ranking.record(summary, capturedSeason)
    local why = Ranking.unratedReason(summary)
    if why then
        if why ~= 'no_contest' and why ~= 'friendly' then log('%s non classé : %s', tostring(summary and summary.id), why) end
        return nil, why
    end
    local c = cfg()
    local season = capturedSeason or c.season
    if Ranking.store.hasMatch and summary.id and Ranking.store.hasMatch(season, summary.id) then
        return nil, 'duplicate'
    end
    local a, b = load(season, summary.players[1]), load(season, summary.players[2])
    local scoreA = summary.winner == 1 and 1 or summary.winner == 2 and 0 or 0.5
    local d = Ranking.delta(a.rating, b.rating, scoreA, c.k)
    a.rating, b.rating = a.rating + d, b.rating - d

    if scoreA == 1 then a.wins, b.losses = a.wins + 1, b.losses + 1
    elseif scoreA == 0 then a.losses, b.wins = a.losses + 1, b.wins + 1
    else a.draws, b.draws = a.draws + 1, b.draws + 1 end

    local at = summary.endedAt
    a.updatedAt, b.updatedAt = at, at
    if Ranking.store.putPair then
        local saved, problem = Ranking.store.putPair(season, a, b, summary.id)
        if not saved then return nil, problem or 'db_unavailable' end
    else
        Ranking.store.put(season, a)
        Ranking.store.put(season, b)
    end
    log('%s classé (saison %s) : %s %+d -> %d, %s %+d -> %d', tostring(summary.id), tostring(season),
        a.name or '?', d, a.rating, b.name or '?', -d, b.rating)
    Ranking.pushTop(-1)
    return a, b
end

-------------------------------------------------------------------------------
-- Classement envoyé au client : noms et chiffres seulement, jamais les identifiants
-------------------------------------------------------------------------------

local function public(row, rank)
    return { rank = rank, name = row.name, rating = row.rating, wins = row.wins, losses = row.losses, draws = row.draws }
end

-- Réponse du callback 'spin_arena:leaderboard' : top N + la ligne du joueur (même s'il n'est pas classé)
function Ranking.leaderboard(src)
    if SpinArena.RankingSQL and SpinArena.RankingSQL.blockedReason then
        return { ok = false, code = SpinArena.Protocol.codes.db_unavailable }
    end
    local c = cfg()
    local season = c.season
    local top = {}
    for i, row in ipairs(Ranking.store.top(season, c.top)) do top[i] = public(row, i) end
    local identifier = SpinArena.Bridge.identifier(src)
    local mine = identifier and Ranking.store.get(season, identifier)
    local me
    if mine then
        me = public(mine, Ranking.store.rank(season, identifier))
    else
        me = { rank = nil, name = SpinArena.Bridge.name(src), rating = c.start, wins = 0, losses = 0, draws = 0 }
    end
    return { ok = true, code = SpinArena.Protocol.codes.ok, season = season, top = top, me = me }
end

-- 5 premiers de la saison EN COURS (config ranking.season) pour le panneau près des tables ; aucun identifiant
function Ranking.seasonTop(n)
    local season = cfg().season
    local top = {}
    for i, row in ipairs(Ranking.store.top(season, n or 5)) do top[i] = public(row, i) end
    return { season = season, updatedAt = os.time(), top = top }
end

-- Envoi à un joueur (src) ou à tous (-1) : à la connexion, au démarrage, après chaque match classé
function Ranking.pushTop(target)
    if SpinArena.RankingSQL and SpinArena.RankingSQL.blockedReason then return false end
    if type(TriggerClientEvent) ~= 'function' then return false end
    local ok = pcall(function()
        TriggerClientEvent(SpinArena.Protocol.ev.seasonTop, target or -1, Ranking.seasonTop(5))
    end)
    return ok
end

if type(AddEventHandler) == 'function' and type(CreateThread) == 'function' then
    SpinArena.Bridge.onLoaded(function(src)
        CreateThread(function() Ranking.pushTop(src) end)
    end)
    CreateThread(function()
        Wait(5000)   -- classement chargé (SQL) avant le premier envoi à tous
        Ranking.pushTop(-1)
    end)
end

function Ranking.onFinished(summary)
    if SpinArena.RankingSQL and SpinArena.RankingSQL.blockedReason == 'journal_invalid' then return nil, 'db_unavailable' end
    if Ranking.store.persistent and SpinArena.RankingSQL then
        return SpinArena.RankingSQL.enqueue(summary)
    end
    return Ranking.record(summary)
end

if SpinArena.Matches and SpinArena.Matches.onFinished then
    SpinArena.Matches.onFinished(Ranking.onFinished)
end

SpinArena.Ranking = Ranking
return Ranking
