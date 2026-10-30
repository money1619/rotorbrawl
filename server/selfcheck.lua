-- SPIN ARENA — vérification guidée de l'installation (30/10).
-- Au démarrage (et avec la commande /spin_check, console ou administrateur), liste ce qui manque pour que le script marche :
-- ressources non démarrées, objets ox_inventory absents, droits (ACE) non donnés. Ne bloque rien : elle informe seulement.
-- collect(env) est pur (tout ce qui vient du serveur passe par `env`) pour pouvoir être testé hors jeu.
SpinArena = SpinArena or {}

local Check = {}
SpinArena.SelfCheck = Check

local REQUIRED = {
    { res = 'oxmysql', hint = 'ensure oxmysql avant Chaos_Arena (base de données des toupies et du classement)' },
    { res = 'ox_lib', hint = 'ensure ox_lib avant Chaos_Arena' },
    { res = 'ox_inventory', hint = 'ensure ox_inventory avant Chaos_Arena (objets, boutique, atelier)' },
    { res = 'ox_target', hint = 'ensure ox_target avant Chaos_Arena (défis, PNJ, stations)' },
}
local FRAMEWORKS = { 'es_extended', 'qb-core', 'qbx_core' }
local ITEMS = { 'spin_top', 'spin_launcher', 'spin_part', 'spin_repair_kit' }

-- env : state(res) -> 'started'..., hasItem(name) -> bool|nil (nil = inventaire illisible), principalAce(principal, ace) -> bool,
--       cfg = SpinArena.ServerConfig, extensions = nombre d'extensions chargées (ou nil)
function Check.collect(env)
    local out = {}
    local function add(level, text) out[#out + 1] = { level = level, text = text } end
    for _, r in ipairs(REQUIRED) do
        if env.state(r.res) == 'started' then add('ok', r.res .. ' démarré')
        else add('error', r.res .. ' n\'est pas démarré : ' .. r.hint) end
    end
    local fw
    for _, name in ipairs(FRAMEWORKS) do
        if env.state(name) == 'started' then fw = name break end
    end
    if fw then add('ok', 'framework : ' .. fw)
    else add('error', 'aucun framework démarré (es_extended, qb-core ou qbx_core) : le script ne peut pas lire les joueurs') end

    if env.state('ox_inventory') == 'started' then
        local missing = {}
        for _, item in ipairs(ITEMS) do
            local has = env.hasItem(item)
            if has == false then missing[#missing + 1] = item end
        end
        if #missing == 0 then add('ok', 'objets ox_inventory : ' .. table.concat(ITEMS, ', '))
        else add('error', 'objets absents d\'ox_inventory : ' .. table.concat(missing, ', ')
            .. ' → ajoute les définitions de install/ox_inventory_items.lua dans ox_inventory/data/items.lua puis redémarre ox_inventory') end
    end

    local cfg = env.cfg or {}
    local adminAce = cfg.adminAce or 'spin_arena.admin'
    if env.principalAce('group.admin', adminAce) and env.principalAce('group.admin', 'command.spin_admin') then
        add('ok', 'droits administrateur donnés au groupe group.admin')
    else
        add('warn', 'le groupe group.admin n\'a pas tous les droits SPIN ARENA : ajoute dans server.cfg « add_ace group.admin '
            .. adminAce .. ' allow » et « add_ace group.admin command.spin_admin allow » (sinon /spin_admin est refusée)')
    end
    if cfg.allowTestProfiles then
        add('warn', 'allowTestProfiles = true : les joueurs peuvent combattre avec des toupies de test gratuites (réserver aux essais)')
    end
    if env.extensions and env.extensions > 0 then add('ok', env.extensions .. ' extension(s) chargée(s) (API d\'extension)') end
    return out
end

local COLORS = { ok = '^2', warn = '^3', error = '^1' }
local TAGS = { ok = 'OK    ', warn = 'ATTENTION', error = 'MANQUE' }

function Check.summary(list)
    local e, w = 0, 0
    for _, l in ipairs(list) do
        if l.level == 'error' then e = e + 1 elseif l.level == 'warn' then w = w + 1 end
    end
    return e, w
end

local function liveEnv()
    return {
        state = function(res) return GetResourceState(res) end,
        hasItem = function(name)
            local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
            if not ok then return nil end
            return item ~= nil
        end,
        principalAce = function(principal, ace)
            return type(IsPrincipalAceAllowed) == 'function' and IsPrincipalAceAllowed(principal, ace) or false
        end,
        cfg = SpinArena.ServerConfig,
        extensions = SpinArena.Extensions and SpinArena.Extensions.count and SpinArena.Extensions.count() or nil,
    }
end

function Check.run(print_)
    local say = print_ or print
    local list = Check.collect(liveEnv())
    say('^5[spin_arena] vérification de l\'installation^7')
    for _, l in ipairs(list) do say(('%s  %s %s^7'):format(COLORS[l.level], TAGS[l.level], l.text)) end
    local e, w = Check.summary(list)
    say(e == 0 and w == 0 and '^2[spin_arena] tout est en ordre^7'
        or ('^3[spin_arena] %d point(s) bloquant(s), %d avertissement(s) : voir ci-dessus (commande /spin_check pour recommencer)^7'):format(e, w))
    return list
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('spin_check', function(src)
        if src == 0 then return Check.run() end
        local lines = {}
        Check.run(function(t) lines[#lines + 1] = (t:gsub('%^%d', '')) end)
        TriggerClientEvent('chat:addMessage', src, { args = { 'SPIN ARENA', table.concat(lines, '\n') } })
    end, true)
end

if type(CreateThread) == 'function' and type(GetResourceState) == 'function' then
    CreateThread(function()
        Wait(6000)          -- laisse démarrer ox_inventory, oxmysql et le framework avant de vérifier
        Check.run()
    end)
end

return Check
