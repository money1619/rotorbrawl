-- Accès à la base (oxmysql 2.12.0) : toutes les requêtes SQL de la ressource sont ici.
-- oxmysql est facultatif : sans lui, la ressource fonctionne avec les profils de test (phase 2).
-- Les appels passent par les exports d'oxmysql en mode promesse (comme son lib/MySQL.lua) et attendent la
-- réponse en cédant la main : ils doivent être faits depuis un fil (callback, CreateThread).
SpinArena = SpinArena or {}

local Db = { ready = false }

local TIMEOUT_MS = 10000

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

function Db.available()
    return GetResourceState('oxmysql') == 'started'
end

-- Exécute une requête et attend le résultat. Renvoie le résultat, ou nil et l'erreur.
local function run(method, query, params)
    if not Db.available() then return nil, 'db_unavailable' end
    local done, result, err = false, nil, nil
    local ok, callErr = pcall(function()
        exports.oxmysql[method](nil, query, params or {}, function(r, e)
            result, err, done = r, e, true
        end, GetCurrentResourceName(), true)
    end)
    if not ok then return nil, tostring(callErr) end
    local deadline = GetGameTimer() + TIMEOUT_MS
    while not done do
        if GetGameTimer() > deadline then return nil, 'db_timeout' end
        Wait(0)
    end
    if err then return nil, tostring(err) end
    return result
end

function Db.query(q, p) return run('query', q, p) end
function Db.single(q, p) return run('single', q, p) end
function Db.scalar(q, p) return run('scalar', q, p) end
function Db.insert(q, p) return run('insert', q, p) end
function Db.update(q, p) return run('update', q, p) end
function Db.transaction(queries) return run('transaction', queries) end

-- Crée les tables si besoin (sql/install.sql), une instruction à la fois : les DDL ne sont pas transactionnelles
function Db.init()
    if not Db.available() then
        log('oxmysql absent : toupies et atelier désactivés, profils de test seulement')
        return false
    end
    local sql = LoadResourceFile(GetCurrentResourceName(), 'sql/install.sql')
    if not sql then
        log('sql/install.sql introuvable')
        return false
    end
    sql = sql:gsub('%-%-[^\n]*', '')
    for statement in sql:gmatch('[^;]+') do
        if statement:match('%S') then
            local _, err = run('query', statement)
            if err then
                log('création du schéma impossible : %s', err)
                return false
            end
        end
    end
    -- Après un redémarrage, aucun match n'est actif : verrous levés, opérations interrompues en revue
    local unlocked = Db.update('UPDATE spin_tops SET locked_match = NULL WHERE locked_match IS NOT NULL') or 0
    local review = Db.update("UPDATE spin_ops SET status = 'review' WHERE status IN ('pending', 'item_taken', 'returning', 'delivering')") or 0
    if unlocked > 0 or review > 0 then
        log('reprise : %d verrou(s) levé(s), %d opération(s) à revoir (spin_ops.status = review)', unlocked, review)
    end
    Db.ready = true
    return true
end

-------------------------------------------------------------------------------
-- Toupies
-------------------------------------------------------------------------------

local function decodeTop(row)
    if not row then return nil end
    local ok, parts = pcall(json.decode, row.parts)
    row.parts = ok and type(parts) == 'table' and parts or nil
    return row
end

function Db.getTop(uid)
    local row, err = Db.single('SELECT * FROM spin_tops WHERE uid = ?', { uid })
    if err then return nil, err end
    return decodeTop(row)
end

-- Crée la ligne si elle n'existe pas encore (uid attribué par le hook createItem)
function Db.ensureTop(uid, owner, parts, name)
    local _, err = Db.insert('INSERT IGNORE INTO spin_tops (uid, owner, name, parts) VALUES (?, ?, ?, ?)',
        { uid, owner, name or 'Toupie', json.encode(parts) })
    if err then return nil, err end
    return Db.getTop(uid)
end

-- Verrou conditionnel : réussit seulement si la toupie n'est engagée dans aucun match
function Db.lockTop(uid, matchId)
    local n, err = Db.update('UPDATE spin_tops SET locked_match = ? WHERE uid = ? AND locked_match IS NULL', { matchId, uid })
    if err then return false, err end
    return n == 1
end

function Db.unlockTop(uid, matchId)
    return Db.update('UPDATE spin_tops SET locked_match = NULL WHERE uid = ? AND locked_match = ?', { uid, matchId })
end

-- Mise à jour optimiste : échoue si la ligne a changé depuis la lecture (version)
function Db.setParts(uid, parts, version)
    local n, err = Db.update('UPDATE spin_tops SET parts = ?, version = version + 1 WHERE uid = ? AND version = ? AND locked_match IS NULL',
        { json.encode(parts), uid, version })
    if err then return false, err end
    return n == 1
end

-- Démontage : supprime la ligne seulement si elle n'a pas changé depuis la lecture et n'est engagée dans aucun match
function Db.deleteTop(uid, version)
    local n, err = Db.update('DELETE FROM spin_tops WHERE uid = ? AND version = ? AND locked_match IS NULL', { uid, version })
    if err then return false, err end
    return n == 1
end

function Db.setField(uid, field, value, version)
    local allowed = { name = true, paint = true, wear = true }
    assert(allowed[field], 'champ non modifiable : ' .. tostring(field))
    local n, err = Db.update(('UPDATE spin_tops SET %s = ?, version = version + 1 WHERE uid = ? AND version = ? AND locked_match IS NULL'):format(field),
        { value, uid, version })
    if err then return false, err end
    return n == 1
end

-- Fin de match : usure et compteurs (outcome = 'win', 'loss' ou 'draw')
function Db.recordTopResult(uid, outcome)
    local column = outcome == 'win' and 'wins' or outcome == 'loss' and 'losses' or 'draws'
    return Db.update(('UPDATE spin_tops SET wear = LEAST(wear + 1, 1000), %s = %s + 1 WHERE uid = ?'):format(column, column), { uid })
end

-------------------------------------------------------------------------------
-- Journal des opérations (atelier)
-------------------------------------------------------------------------------

function Db.opStart(identifier, uid, op, payload)
    return Db.insert("INSERT INTO spin_ops (identifier, uid, op, payload, status) VALUES (?, ?, ?, ?, 'pending')",
        { identifier, uid, op, payload and json.encode(payload) or nil })
end

-- Objets dus au joueur (état certain) : statut « owed » et liste exacte dans le payload (VARCHAR 255)
function Db.opOwe(id, from, payload)
    local ok, encoded = pcall(json.encode, payload)
    if not ok then return false, 'encode' end
    if #encoded > 255 then encoded = json.encode({ owed = payload.owed }) end
    if #encoded > 255 then return false, 'too_long' end
    local n, err = Db.update("UPDATE spin_ops SET status = 'owed', payload = ? WHERE id = ? AND status = ?", { encoded, id, from })
    if err then return false, err end
    return n == 1
end

function Db.opsOwed(identifier)
    return Db.query("SELECT id, payload FROM spin_ops WHERE identifier = ? AND status = 'owed' ORDER BY id", { identifier })
end

function Db.owedIdentifiers()
    return Db.query("SELECT DISTINCT identifier FROM spin_ops WHERE status = 'owed'", {})
end

-- Transition conditionnelle : from → to ; renvoie true si la ligne était bien dans l'état attendu
function Db.opMove(id, from, to)
    local n, err = Db.update('UPDATE spin_ops SET status = ? WHERE id = ? AND status = ?', { to, id, from })
    if err then return false, err end
    return n == 1
end

SpinArena.Database = Db
return Db
