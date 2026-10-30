-- Persistent ranking adapter and restart-safe pending journal. Server only.
-- Both ratings and the match marker commit together; replaying a pending entry is safe.
SpinArena = SpinArena or {}
local SQL = { pending = {}, busy = false, enabled = false }
local Db, Ranking = SpinArena.Database, SpinArena.Ranking
local FILE = 'data/ranking_pending.json'
local function log(message) print('[spin_arena] classement SQL : ' .. message) end
local function result(value, err)
    if err then error('ranking database request failed: ' .. tostring(err), 0) end
    return value
end
local function persist()
    if not SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(SQL.pending), -1) then
        if SQL.blockedReason ~= 'journal_write' then log('journal non écrit ; nouveaux combats suspendus, vérifier espace et permissions') end
        SQL.blockedReason = 'journal_write'
        return false
    end
    if SQL.blockedReason == 'journal_write' then SQL.blockedReason = nil; log('journal de nouveau disponible') end
    return true
end

function SQL.Store()
    local store = { persistent = true }
    function store.get(season, identifier)
        return result(Db.single('SELECT identifier, name, rating, wins, losses, draws FROM spin_ratings WHERE identifier = ? AND season = ?', { identifier, season }))
    end
    function store.hasMatch(season, id)
        return result(Db.scalar('SELECT 1 FROM spin_rating_matches WHERE match_id = ? AND season = ?', { id, season })) ~= nil
    end
    function store.putPair(season, a, b, id)
        if type(id) ~= 'string' or #id < 1 or #id > 64 then return false, 'invalid' end
        local queries = {{ query = 'INSERT INTO spin_rating_matches (match_id, season) VALUES (?, ?)', values = { id, season } }}
        for _, row in ipairs({ a, b }) do
            queries[#queries + 1] = {
                query = 'INSERT INTO spin_ratings (identifier, season, name, rating, wins, losses, draws) VALUES (?, ?, ?, ?, ?, ?, ?) '
                    .. 'ON DUPLICATE KEY UPDATE name = VALUES(name), rating = VALUES(rating), wins = VALUES(wins), losses = VALUES(losses), draws = VALUES(draws)',
                values = { row.identifier, season, row.name or '', row.rating, row.wins, row.losses, row.draws },
            }
        end
        local saved, err = Db.transaction(queries)
        return saved == true, err
    end
    function store.top(season, n)
        return result(Db.query('SELECT identifier, name, rating, wins, losses, draws FROM spin_ratings WHERE season = ? ORDER BY rating DESC, wins DESC, identifier ASC LIMIT ?', { season, n })) or {}
    end
    function store.rank(season, identifier)
        local row = store.get(season, identifier)
        if not row then return nil end
        local ahead = result(Db.scalar('SELECT COUNT(*) FROM spin_ratings WHERE season = ? AND (rating > ? OR (rating = ? AND wins > ?) OR (rating = ? AND wins = ? AND identifier < ?))',
            { season, row.rating, row.rating, row.wins, row.rating, row.wins, identifier }))
        return (tonumber(ahead) or 0) + 1
    end
    return store
end

function SQL.enqueue(summary)
    if SQL.blockedReason == 'journal_invalid' then return nil, 'db_unavailable' end
    local why = Ranking.unratedReason(summary)
    if why then return nil, why end
    if type(summary.id) ~= 'string' or #summary.id < 1 or #summary.id > 64 then return nil, 'invalid' end
    local season = SpinArena.ServerConfig.ranking.season
    for _, entry in ipairs(SQL.pending) do
        if entry.summary.id == summary.id and entry.season == season then return nil, 'duplicate' end
    end
    -- Copy only ranking input; caller mutations cannot change a queued result.
    SQL.pending[#SQL.pending + 1] = { season = season, summary = json.decode(json.encode({
        id = summary.id, players = summary.players, winner = summary.winner, reason = summary.reason,
        startedAt = summary.startedAt, endedAt = summary.endedAt, homologation = summary.homologation,
    })) }
    return persist() or nil, SQL.blockedReason and 'db_unavailable' or nil
end

function SQL.flush()
    if SQL.busy or not SQL.enabled or not Db.available() then return false end
    SQL.busy = true
    local ok, err = pcall(function()
        if #SQL.pending == 0 and SQL.blockedReason == 'journal_write' then persist() end
        while #SQL.pending > 0 do
            local entry = SQL.pending[1]
            local a, why = Ranking.record(entry.summary, entry.season)
            if not a and why ~= 'duplicate' then
                log('résultat en attente conservé (' .. tostring(why) .. ')')
                break
            end
            table.remove(SQL.pending, 1)
            persist() -- A stale on-disk entry is harmless: the SQL marker prevents duplicate application.
        end
    end)
    SQL.busy = false
    if not ok then log('reprise différée : ' .. tostring(err)) end
    return ok
end

function SQL.init()
    if not Db.ready or not Db.available() then return false end
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    if raw and raw ~= '' then
        local ok, pending = pcall(json.decode, raw)
        if not ok or type(pending) ~= 'table' then
            SQL.blockedReason = 'journal_invalid'
            log('journal illisible, conservé pour récupération ; activation refusée')
            return false
        end
        for _, entry in ipairs(pending) do
            if type(entry) ~= 'table' or type(entry.season) ~= 'number' or type(entry.summary) ~= 'table'
                or Ranking.unratedReason(entry.summary) or type(entry.summary.id) ~= 'string' then
                log('entrée du journal invalide ; activation refusée pour conserver la preuve')
                SQL.blockedReason = 'journal_invalid'
                return false
            end
        end
        SQL.pending = pending
    end
    Ranking.setStore(SQL.Store())
    SQL.enabled = true
    CreateThread(function()
        while SQL.enabled do SQL.flush(); Wait(5000) end
    end)
    log('actif, ' .. tostring(#SQL.pending) .. ' résultat(s) à reprendre')
    return true
end

SpinArena.RankingSQL = SQL
return SQL
