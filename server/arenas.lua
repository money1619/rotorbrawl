-- Arènes : placement, réservation exclusive et audience (docs/ARCHITECTURE.md §12).
-- Phase 5 : arènes fixes posées en jeu par un administrateur et zones où les combats improvisés sont
-- autorisés, persistées en JSON dans la ressource (SaveResourceFile / LoadResourceFile).
SpinArena = SpinArena or {}

local Arenas = { active = {}, fixed = {}, zones = {} }

local NAME_PATTERN, NAME_MAX = '^[%w_%-]+$', 32
local ZONE_DZ = 30.0 -- écart vertical toléré entre un joueur et le centre d'une zone (m)

local function cfg() return SpinArena.ServerConfig.arena end
local function codes() return SpinArena.Protocol.codes end

local function log(fmt, ...)
    print(('[spin_arena] ' .. fmt):format(...))
end

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function finite(n)
    return type(n) == 'number' and n == n and n > -math.huge and n < math.huge
end

local function validName(name)
    return type(name) == 'string' and #name <= NAME_MAX and name:match(NAME_PATTERN) ~= nil
end

-- Variante de table connue (config/shared.lua arenaVariants) ; nil si le nom est inconnu
local function variantOf(name)
    return SpinArena.Config.arenaVariants[name or 'standard']
end
Arenas.variantOf = variantOf

-- « standard|compact|… » : les variantes de la configuration, dans l'ordre alphabétique (standard en premier)
function Arenas.variantNames()
    local names = {}
    for name in pairs(SpinArena.Config.arenaVariants) do if name ~= 'standard' then names[#names + 1] = name end end
    table.sort(names)
    table.insert(names, 1, 'standard')
    return table.concat(names, '|')
end

-- Rayon hors tout d'une table (modèle complet) pour les écarts entre tables : rOuter de la variante, sinon R + 0,10
local SKIRT = 0.10
local function outer(v)
    local o = tonumber(v.rOuter) or (v.R + SKIRT)
    -- Variante à gradins (Colisée) : l'emprise est celle des gradins (dernier rang + 0,5 m de garde-corps et de mât)
    local st = v.stands
    if type(st) == 'table' and tonumber(st.rIn) and tonumber(st.rings) and tonumber(st.ringW) then
        o = math.max(o, st.rIn + st.rings * st.ringW + 0.5)
    end
    return o
end

-- Géométrie simulée d'une table autour d'un centre posé au sol (standard par défaut)
local function shape(center, variant)
    local name = variantOf(variant) and variant or 'standard'
    local base = variantOf(name)
    return {
        x = center.x, y = center.y, z = center.z,
        heading = center.heading,
        -- échelle d'affichage : le moteur simule R et h, le client montre la cuvette `scale` fois plus grande (grande arène
        -- du Dôme : combat de table de tournoi, affiché deux fois plus grand, donc des toupies deux fois plus vives à l'œil)
        scale = tonumber(base.scale) or 1.0,
        variant = name, model = base.model, floorHeight = base.floorHeight,
        R = base.R, h = base.h, pockets = base.pockets,
        railBoost = base.railBoost,   -- rail turbo de la variante (nil = aucun)
        power = base.power,           -- mode puissance de la variante (nil = aucun)
        watchRadius = base.watchRadius, -- rayon du public de la variante (nil = arena.watchRadius de la config)
    }
end

-- Arène devant un joueur : le cap de son ped oriente le repère local
function Arenas.inFront(ctx)
    local rad = math.rad(ctx.heading)
    local d = cfg().distanceInFront
    local arena = shape({
        x = ctx.coords.x - math.sin(rad) * d,
        y = ctx.coords.y + math.cos(rad) * d,
        z = ctx.coords.z - cfg().pedToGround,
        heading = ctx.heading,
    }, ctx.portable)   -- ctx.portable : variante d'une arène transportable portée par le joueur (nil = table standard)
    arena.kind = ctx.portable and 'portable' or 'improvised'   -- homologation
    return arena
end

-- Arène fixe prête à réserver (copie : un match ne dépend pas de l'entrée enregistrée)
local function fromFixed(entry)
    local arena = shape(entry, entry.variant)
    arena.fixedId = entry.name
    arena.kind = 'fixed'   -- homologation : table fixe
    -- Nom lisible de la table (panneau au-dessus) : libellé enregistré, sinon « Table <variante> »
    arena.label = entry.label or ('Table %s'):format((variantOf(arena.variant) or variantOf('standard')).label)
    return arena
end

-- Distance horizontale entre une position et le centre de l'arène (m), avec un écart vertical borné
function Arenas.distance(arena, coords)
    if math.abs(coords.z - arena.z) > 10.0 then return math.huge end
    return dist2d(arena, coords)
end

local function overlaps(arena, bucket)
    for _, other in pairs(Arenas.active) do
        if other.bucket == bucket then
            local need = arena.R * arena.scale + other.arena.R * other.arena.scale + cfg().minGap
            if dist2d(arena, other.arena) < need then return true end
        end
    end
    return false
end

local function sorted(map)
    local list = {}
    for _, e in pairs(map) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Réserve une arène pour un match ; refuse si elle chevauche une arène active du même monde
function Arenas.reserve(matchId, arena, bucket)
    if overlaps(arena, bucket) then return nil, codes().no_arena end
    Arenas.active[matchId] = { arena = arena, bucket = bucket }
    return arena
end

function Arenas.release(matchId)
    Arenas.active[matchId] = nil
end

function Arenas.isReserved(entryOrName, bucket)
    local entry = type(entryOrName) == 'string' and Arenas.fixed[entryOrName] or entryOrName
    if type(entry) ~= 'table' then return false end
    local b = bucket ~= nil and math.tointeger(bucket) or entry.bucket or 0
    return overlaps(fromFixed(entry), b)
end

-- Liste triée des stations fixes (avec leur état d'occupation actuel) pour l'affichage client (blips / ox_target)
function Arenas.stations(bucket)
    local targetBucket = bucket ~= nil and math.tointeger(bucket) or nil
    local list = {}
    for _, e in ipairs(sorted(Arenas.fixed)) do
        if targetBucket == nil or e.bucket == targetBucket then
            list[#list + 1] = {
                name    = e.name,
                label   = e.label or ('Table %s · %s'):format((variantOf(e.variant) or variantOf('standard')).label, e.name),
                x       = e.x,
                y       = e.y,
                z       = e.z,
                heading = e.heading,
                bucket  = e.bucket,
                variant = e.variant or 'standard',
                model   = (variantOf(e.variant) or variantOf('standard')).model,
                busy    = overlaps(fromFixed(e), e.bucket),
                noBlip  = e.noBlip or nil,   -- arène d'extension sans blip (ex. tables du Dôme, loin de la carte)
            }
        end
    end
    return list
end

-- Position dans une zone autorisée du même monde
function Arenas.inZone(coords, bucket)
    for _, z in pairs(Arenas.zones) do
        if z.bucket == bucket and math.abs(coords.z - z.z) <= ZONE_DZ and dist2d(z, coords) <= z.radius then
            return true
        end
    end
    return false
end

-- Arène d'un nouveau match pour le joueur qui défie :
-- - si stationName est précisé, exige cette station fixe (proche, même monde, et libre : réservation exclusive) ;
-- - sinon l'arène fixe libre la plus proche (fixedRadius), ou une arène improvisée devant lui si permis.
function Arenas.place(ctx, stationName)
    local c = cfg()
    if type(stationName) == 'string' and stationName ~= '' then
        local entry = Arenas.fixed[stationName]
        if not entry or entry.bucket ~= ctx.bucket then
            return nil, codes().no_arena
        end
        if Arenas.distance(entry, ctx.coords) > c.fixedRadius then
            return nil, codes().too_far
        end
        local arena = fromFixed(entry)
        if overlaps(arena, ctx.bucket) then
            return nil, codes().no_arena
        end
        return arena
    end

    -- ctx.preferVariant (tournois : grande table du lieu) passe avant la distance, sans exclure les autres tables
    local best, bestD, bestPref
    for _, entry in pairs(Arenas.fixed) do
        if entry.bucket == ctx.bucket then
            local d = Arenas.distance(entry, ctx.coords)
            -- table de tournoi : la variante demandée, ou une variante marquée `tournament` (grande arène d'une extension)
            local pref = ctx.preferVariant ~= nil and (entry.variant == ctx.preferVariant or (variantOf(entry.variant) or {}).tournament == true)
            if d <= c.fixedRadius and (not bestD or (pref and not bestPref) or (pref == bestPref and d < bestD)) then
                local arena = fromFixed(entry)
                if not overlaps(arena, ctx.bucket) then best, bestD, bestPref = arena, d, pref end
            end
        end
    end
    if best then return best end

    if not (c.improvisedAnywhere or ctx.portable or Arenas.inZone(ctx.coords, ctx.bucket)) then   -- l'arène transportable s'installe partout
        return nil, codes().no_zone or codes().no_arena
    end
    local arena = Arenas.inFront(ctx)
    if overlaps(arena, ctx.bucket) then return nil, codes().no_arena end
    return arena
end

-- Joueurs qui reçoivent le match : les participants, puis les plus proches du même monde dans le rayon
function Arenas.audience(arena, bucket, participants)
    local list, seen = {}, {}
    for _, src in ipairs(participants) do
        list[#list + 1] = src
        seen[src] = true
    end
    local candidates = {}
    -- rayon du public : celui de la variante (grande arène d'un hall, écrans en direct jusque dans les coins), sinon la config
    local watch = tonumber(arena.watchRadius) or cfg().watchRadius
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and not seen[src] and GetPlayerRoutingBucket(src) == bucket then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local d = Arenas.distance(arena, GetEntityCoords(ped))
                if d <= watch then candidates[#candidates + 1] = { src = src, d = d } end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#candidates, cfg().maxSpectators) do list[#list + 1] = candidates[i].src end
    return list
end

-------------------------------------------------------------------------------
-- Persistance (data/arenas.json)
-------------------------------------------------------------------------------

local function validFixed(e)
    return type(e) == 'table' and validName(e.name) and finite(e.x) and finite(e.y) and finite(e.z)
        and finite(e.heading) and math.tointeger(e.bucket) ~= nil
        and (e.variant == nil or (type(e.variant) == 'string' and variantOf(e.variant) ~= nil))
end

local function validZone(e)
    return type(e) == 'table' and validName(e.name) and finite(e.x) and finite(e.y) and finite(e.z)
        and finite(e.radius) and e.radius > 0 and e.radius <= cfg().maxZoneRadius and math.tointeger(e.bucket) ~= nil
end

-- Lit le fichier ; une entrée invalide est ignorée (et signalée), jamais chargée à moitié
function Arenas.load()
    Arenas.fixed, Arenas.zones = {}, {}
    local raw = LoadResourceFile(GetCurrentResourceName(), cfg().dataFile)
    local ok, data = false, nil
    if raw and raw ~= '' then
        ok, data = pcall(json.decode, raw)
        if not ok or type(data) ~= 'table' then
            log('%s illisible : arènes du fichier et zones ignorées', cfg().dataFile)
        end
    end
    if not ok or type(data) ~= 'table' then data = {} end
    local nf, nz = 0, 0
    -- Arènes déclarées dans la config (config/server.lua arena.fixedList) : prioritaires sur le fichier, jamais réécrites dedans
    for _, e in ipairs(type(cfg().fixedList) == 'table' and cfg().fixedList or {}) do
        if validFixed(e) and not Arenas.fixed[e.name] then
            Arenas.fixed[e.name] = { name = e.name, x = e.x, y = e.y, z = e.z, heading = e.heading, bucket = math.tointeger(e.bucket),
                                     variant = e.variant, fromConfig = true }
            nf = nf + 1
        else
            log('arène de la config invalide ou en double ignorée : %s', tostring(type(e) == 'table' and e.name or e))
        end
    end
    -- Arènes des extensions (server/extensions.lua) : après la config, jamais réécrites dans le fichier ni supprimables en jeu
    local Ext = SpinArena.Extensions
    for _, item in ipairs(Ext and Ext.fixedArenas and Ext.fixedArenas() or {}) do
        local e = item.entry
        if validFixed(e) and not Arenas.fixed[e.name] then
            Arenas.fixed[e.name] = { name = e.name, x = e.x, y = e.y, z = e.z, heading = e.heading, bucket = math.tointeger(e.bucket),
                                     variant = e.variant, label = e.label, noBlip = e.noBlip, fromConfig = true, extension = item.owner }
            nf = nf + 1
        else
            log('arène de l\'extension %s invalide ou en double ignorée : %s', tostring(item.owner), tostring(e.name))
        end
    end
    for _, e in ipairs(type(data.arenas) == 'table' and data.arenas or {}) do
        if validFixed(e) and not Arenas.fixed[e.name] then
            Arenas.fixed[e.name] = { name = e.name, x = e.x, y = e.y, z = e.z, heading = e.heading, bucket = math.tointeger(e.bucket),
                                     variant = e.variant }
            nf = nf + 1
        else
            log('arène fixe invalide ignorée dans %s', cfg().dataFile)
        end
    end
    for _, e in ipairs(type(data.zones) == 'table' and data.zones or {}) do
        if validZone(e) and not Arenas.zones[e.name] then
            Arenas.zones[e.name] = { name = e.name, x = e.x, y = e.y, z = e.z, radius = e.radius, bucket = math.tointeger(e.bucket) }
            nz = nz + 1
        else
            log('zone invalide ignorée dans %s', cfg().dataFile)
        end
    end
    return nf, nz
end

function Arenas.save()
    local own = {}
    for _, e in ipairs(sorted(Arenas.fixed)) do
        if not e.fromConfig then own[#own + 1] = e end
    end
    local data = { version = 1, arenas = own, zones = sorted(Arenas.zones) }
    local ok, encoded = pcall(json.encode, data)
    if not ok then return false end
    local saved = SaveResourceFile(GetCurrentResourceName(), cfg().dataFile, encoded, -1)
    -- Selon la version du serveur, SaveResourceFile renvoie true ou 1 (le fichier est bien écrit) : tout sauf false/nil/0 est un succès
    return saved == true or (type(saved) == 'number' and saved ~= 0)
end

-------------------------------------------------------------------------------
-- /spin_admin arena|zone ... (appelé par server/main.lua, qui exige déjà l'ACE command.spin_admin)
-------------------------------------------------------------------------------

local function fmt(n) return ('%.2f'):format(n) end

-- Modifie la table puis enregistre ; en cas d'échec d'écriture, la modification est annulée
local function commit(map, name, value, reply)
    local previous = map[name]
    map[name] = value
    if Arenas.save() then return true end
    map[name] = previous
    reply('écriture de ' .. cfg().dataFile .. ' impossible : rien n\'a changé')
    return false
end

local function list(kind, reply)
    local map = kind == 'arena' and Arenas.fixed or Arenas.zones
    local entries = sorted(map)
    if #entries == 0 then return reply(kind == 'arena' and 'aucune arène fixe' or 'aucune zone') end
    for _, e in ipairs(entries) do
        if kind == 'arena' then
            reply(('arène %s (%s) : %s, %s, %s cap %s monde %d'):format(e.name, e.variant or 'standard', fmt(e.x), fmt(e.y), fmt(e.z), fmt(e.heading), e.bucket))
        else
            reply(('zone %s : %s, %s, %s rayon %s monde %d'):format(e.name, fmt(e.x), fmt(e.y), fmt(e.z), fmt(e.radius), e.bucket))
        end
    end
end

local function usage(reply)
    reply('usage : /spin_admin arena add <nom> [' .. Arenas.variantNames() .. '] | arena remove <nom> | arena list | zone add <nom> <rayon> | zone remove <nom> | zone list')
end

-- Écarts d'implantation d'une nouvelle table : autres tables (rayons hors tout + minGap) et points de vente
-- (3 m + rayon hors tout, pour laisser la zone ox_target et le passage). Renvoie un message, ou nil si la place va.
function Arenas.placementProblem(arena, bucket)
    for _, other in pairs(Arenas.fixed) do
        if other.bucket == bucket then
            local o = variantOf(other.variant) or variantOf('standard')
            local need = outer(variantOf(arena.variant) or arena) + outer(o) + cfg().minGap
            if dist2d(arena, other) < need then
                return ('trop près de la table %s (%.1f m, il faut %.1f m)'):format(other.name, dist2d(arena, other), need)
            end
        end
    end
    local shop = SpinArena.ServerConfig.shop
    for _, loc in ipairs(shop and shop.locations or {}) do
        local need = 3.0 + outer(variantOf(arena.variant) or arena)
        if dist2d(arena, loc) < need then
            return ('trop près du vendeur (%.1f m, il faut %.1f m)'):format(dist2d(arena, loc), need)
        end
    end
    return nil
end

function Arenas.admin(src, args, reply)
    local kind, sub, name = args[1], args[2], args[3]
    if kind ~= 'arena' and kind ~= 'zone' then return usage(reply) end
    if sub == 'list' or sub == nil then return list(kind, reply) end
    if sub ~= 'add' and sub ~= 'remove' then return usage(reply) end
    if not validName(name) then return reply('nom invalide : lettres, chiffres, _ ou -, 32 caractères au plus') end
    local map = kind == 'arena' and Arenas.fixed or Arenas.zones
    local who = src == 0 and 'la console' or SpinArena.Bridge.name(src)

    if sub == 'remove' then
        if not map[name] then return reply(name .. ' introuvable') end
        if map[name].extension then return reply(name .. ' vient de l\'extension ' .. tostring(map[name].extension) .. ' : à retirer dans sa configuration') end
        if map[name].fromConfig then return reply(name .. ' vient de config/server.lua (arena.fixedList) : à retirer dans ce fichier') end
        if commit(map, name, nil, reply) then
            log('%s %s supprimée par %s', kind, name, who)
            reply(name .. ' supprimée')
        end
        return
    end

    if src == 0 then return reply('à faire en jeu : la position et le cap de l\'administrateur sont utilisés') end
    if map[name] then return reply(name .. ' existe déjà : la supprimer d\'abord') end
    local ctx = SpinArena.Bridge.context(src)
    if not ctx then return reply('ped introuvable (OneSync ?)') end

    local entry
    if kind == 'arena' then
        local variant = args[4] or 'standard'
        if not variantOf(variant) then return reply('variante inconnue : ' .. Arenas.variantNames():gsub('|', ', ')) end
        local ground = { x = ctx.coords.x, y = ctx.coords.y, z = ctx.coords.z - cfg().pedToGround, heading = ctx.heading }
        local arena = shape(ground, variant)
        local why = Arenas.placementProblem(arena, ctx.bucket)
        if why then return reply(why) end
        entry = { name = name, x = ground.x, y = ground.y, z = ground.z, heading = ground.heading, bucket = ctx.bucket,
                  variant = variant ~= 'standard' and variant or nil }
    else
        local radius = tonumber(args[4])
        if not finite(radius) or radius < 1.0 or radius > cfg().maxZoneRadius then
            return reply(('rayon invalide : de 1 à %s m'):format(fmt(cfg().maxZoneRadius)))
        end
        entry = { name = name, x = ctx.coords.x, y = ctx.coords.y, z = ctx.coords.z, radius = radius + 0.0, bucket = ctx.bucket }
    end

    if commit(map, name, entry, reply) then
        log('%s %s ajoutée par %s : %s, %s, %s monde %d', kind, name, who, fmt(entry.x), fmt(entry.y), fmt(entry.z), entry.bucket)
        reply(name .. ' ajoutée')
    end
end

-- Un fichier illisible ne doit jamais empêcher les matchs : on repart sans arène fixe ni zone
local loaded, nf, nz = pcall(Arenas.load)
if not loaded then
    Arenas.fixed, Arenas.zones = {}, {}
    log('chargement de %s impossible : %s', cfg().dataFile, tostring(nf))
elseif nf > 0 or nz > 0 then
    log('%d arène(s) fixe(s) et %d zone(s) chargées', nf, nz)
end

SpinArena.Arenas = Arenas
return Arenas
