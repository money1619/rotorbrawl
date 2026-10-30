-- SPIN ARENA — panneau d'administration en jeu (30/10) : /spin_panel (menu ox_lib).
-- Le serveur donne un instantané (matchs, tournois, arènes, achats non résolus) et exécute quelques actions, TOUJOURS après avoir
-- vérifié le droit d'administrateur (ACE spin_arena.admin) : le client ne décide de rien. Les actions réutilisent les fonctions des
-- commandes /spin_admin (mêmes règles, mêmes journaux).
SpinArena = SpinArena or {}

local Panel = { COOLDOWN_MS = 800, MAX_LIST = 25 }
SpinArena.AdminPanel = Panel

local lastAt = {}

local function isAdmin(src)
    return SpinArena.Security and SpinArena.Security.isAdmin(src) or false
end

-- Instantané lisible côté client (listes courtes, rien de sensible)
function Panel.snapshot()
    local snap = { matches = {}, tournaments = {}, arenas = {}, unresolved = 0 }
    local Matches = SpinArena.Matches
    for id, m in pairs(Matches and Matches.byId or {}) do
        if #snap.matches < Panel.MAX_LIST then
            local a, b = m.players and m.players[1], m.players and m.players[2]
            snap.matches[#snap.matches + 1] = {
                id = id, a = a and a.name or '?', b = b and b.name or '?', round = m.round or 0,
                score = ('%d-%d'):format(m.score and m.score[1] or 0, m.score and m.score[2] or 0), state = tostring(m.state),
                practice = m.practice and true or false,
            }
        end
    end
    table.sort(snap.matches, function(x, y) return x.id < y.id end)
    local T = SpinArena.Tournaments
    for id, t in pairs(T and type(T.byId) == 'table' and T.byId or {}) do
        if #snap.tournaments < Panel.MAX_LIST then
            local n = 0
            for _, e in ipairs(t.players or {}) do if not e.left then n = n + 1 end end
            snap.tournaments[#snap.tournaments + 1] = { id = tostring(id), name = tostring(t.name), state = tostring(t.state), players = n, size = t.size or 0 }
        end
    end
    table.sort(snap.tournaments, function(x, y) return x.id < y.id end)
    local A = SpinArena.Arenas
    for name, a in pairs(A and A.fixed or {}) do
        if #snap.arenas < Panel.MAX_LIST then
            snap.arenas[#snap.arenas + 1] = { name = name, variant = a.variant or 'standard', fromConfig = (a.fromConfig or a.fromExtension) and true or false }
        end
    end
    table.sort(snap.arenas, function(x, y) return x.name < y.name end)
    local Shop = SpinArena.Shop
    snap.unresolved = Shop and Shop.unresolved and #Shop.unresolved or 0
    return snap
end

-- Actions : { kind, id }. Renvoie ok, message.
function Panel.act(src, kind, id)
    if not isAdmin(src) then return false, 'droits insuffisants' end
    if type(id) ~= 'string' or #id > 48 or not id:match('^[%w_%-%.]+$') then return false, 'identifiant invalide' end
    local out
    local function reply(msg) out = msg end
    if kind == 'cancel_match' then
        local m = SpinArena.Matches and SpinArena.Matches.byId[id]
        if not m then return false, 'match introuvable' end
        SpinArena.Matches.cancel(m, 'admin')
        return true, 'match annulé'
    elseif kind == 'tournament_start' or kind == 'tournament_cancel' then
        local T = SpinArena.Tournaments
        if not (T and T.admin) then return false, 'tournois indisponibles' end
        T.admin(src, { 'tournoi', kind == 'tournament_start' and 'start' or 'cancel', id }, reply)
        return true, out or 'fait'
    elseif kind == 'arena_remove' then
        local A = SpinArena.Arenas
        if not (A and A.admin) then return false, 'arènes indisponibles' end
        A.admin(src, { 'arena', 'remove', id }, reply)
        if SpinArena.Shop and SpinArena.Shop.register then pcall(SpinArena.Shop.register) end
        return true, out or 'fait'
    end
    return false, 'action inconnue'
end

if type(lib) == 'table' and lib.callback and lib.callback.register then
    lib.callback.register('spin_arena:admin:snapshot', function(src)
        if not isAdmin(src) then return nil end
        return Panel.snapshot()
    end)
    lib.callback.register('spin_arena:admin:act', function(src, payload)
        local now = GetGameTimer()
        if lastAt[src] and now - lastAt[src] < Panel.COOLDOWN_MS then return { ok = false, message = 'trop rapide' } end
        lastAt[src] = now
        payload = type(payload) == 'table' and payload or {}
        local ok, msg = Panel.act(src, payload.kind, payload.id)
        return { ok = ok, message = msg }
    end)
end

return Panel
