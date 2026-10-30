-- Limites de fréquence, validation des données reçues et verrous par joueur (docs/SECURITY.md §4 à §6).
SpinArena = SpinArena or {}

local Security = { buckets = {}, locks = {} }

local function now() return GetGameTimer() end

local function refill(bucket, cfg)
    local t = now()
    bucket.tokens = math.min(cfg.burst, bucket.tokens + (t - bucket.last) / 1000 * cfg.perSecond)
    bucket.last = t
end

-- Seau de jetons par joueur et par action, plus un seau global par joueur
function Security.allow(src, action)
    local limits = SpinArena.ServerConfig.rateLimits
    local cfg = limits[action]
    if not cfg then return false end
    local per = Security.buckets[src]
    if not per then
        per = {}
        Security.buckets[src] = per
    end
    for _, key in ipairs({ 'global', action }) do
        local c = limits[key]
        per[key] = per[key] or { tokens = c.burst, last = now() }
    end
    -- Les deux seaux doivent avoir un jeton ; un refus n'en consomme aucun
    refill(per.global, limits.global)
    refill(per[action], cfg)
    if per.global.tokens < 1 or per[action].tokens < 1 then return false end
    per.global.tokens = per.global.tokens - 1
    per[action].tokens = per[action].tokens - 1
    return true
end

-- Schéma : { champ = { 'integer', min, max } | { 'boolean' } | { 'string', longueurMax, motif? } | { 'enum', ensemble } ,
-- avec `optional = true` dans la règle si le champ peut manquer }. Tout champ inconnu est refusé.
function Security.check(value, schema)
    if value == nil then value = {} end
    if type(value) ~= 'table' then return false, '(payload)' end
    for key in pairs(value) do
        if type(key) ~= 'string' or not schema[key] then return false, tostring(key) end
    end
    for key, rule in pairs(schema) do
        local v = value[key]
        if v == nil then
            if not rule.optional then return false, key end
        else
            local kind = rule[1]
            if kind == 'integer' then
                if math.type(v) ~= 'integer' or v < rule[2] or v > rule[3] then return false, key end
            elseif kind == 'boolean' then
                if type(v) ~= 'boolean' then return false, key end
            elseif kind == 'string' then
                if type(v) ~= 'string' or #v > rule[2] or (rule[3] and not v:match(rule[3])) then return false, key end
            elseif kind == 'enum' then
                if type(v) ~= 'string' or not rule[2][v] then return false, key end
            else
                return false, key
            end
        end
    end
    return true
end

-- Une seule opération sensible à la fois par joueur : fn s'exécute verrou pris, le verrou est toujours rendu
function Security.withLock(src, fn)
    if Security.locks[src] then return { ok = false, code = SpinArena.Protocol.codes.busy } end
    Security.locks[src] = true
    local ok, res = pcall(fn)
    Security.locks[src] = nil
    if not ok then error(res, 0) end
    return res
end

function Security.isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, SpinArena.ServerConfig.adminAce)
end

function Security.forget(src)
    Security.buckets[src] = nil
    Security.locks[src] = nil
end

SpinArena.Security = Security
return Security
