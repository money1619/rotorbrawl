-- SPIN ARENA — Spectacle du combat. Fichier : client/spectacle.lua
-- Affichage seulement : traînées lumineuses, lueur des toupies, éclairs des chocs, poches éclairées, vol d'une toupie
-- éjectée jusqu'au sol, chute d'une toupie arrêtée, inclinaison dans les virages et ralenti du coup final.
-- Tout part des positions déjà reçues du serveur (keyframes) : rien ici ne change le résultat ni n'envoie de message.
-- Réglages : SpinArena.Config.spectacle (config/shared.lua). Natives vérifiées dans natives_0193D0AF.lua :
-- DrawLine, DrawLightWithRange, DrawMarker.

SpinArena = SpinArena or {}

local Spectacle = {}
SpinArena.Spectacle = Spectacle

local math_cos, math_sin, math_sqrt = math.cos, math.sin, math.sqrt
local math_min, math_max, math_floor = math.min, math.max, math.floor
local math_abs, math_atan, math_pi, math_rad = math.abs, math.atan, math.pi, math.rad
local G = 9.81

-- Statuts des keyframes (client/renderer.lua, Renderer.STATUS)
local SPINNING, STOPPING, STOPPED, EJECTED = 0, 1, 2, 3

Spectacle.DEFAULTS = {
    trails = { enabled = true, ms = 320, stepMs = 16, glowRange = 0.30, glowIntensity = 1.6 },
    impactLight = { enabled = true, range = 0.9, intensity = 7.0 },
    pockets = { enabled = true, flashMs = 1600 },
    eject = { enabled = true, speed = 1.0, up = 0.5 },
    fallOver = { enabled = true, deg = 68, ms = 450 },
    lean = { enabled = true, maxDeg = 14 },
    replay = { enabled = true, windowS = 1.2, speed = 0.4, delayMs = 500 },
}
Spectacle.TRAIL_MAX_POINTS = 40
Spectacle.POCKET_COLOR = { r = 255, g = 170, b = 40 }
Spectacle.POCKET_FLASH_COLOR = { r = 239, g = 68, b = 68 }
Spectacle.SPARK_COLOR = { r = 255, g = 196, b = 110 }

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Réglage d'un bloc : valeur de la config si elle est valide, sinon valeur par défaut
function Spectacle.cfg(block)
    local def = Spectacle.DEFAULTS[block] or {}
    local all = SpinArena.Config and SpinArena.Config.spectacle
    local cur = type(all) == 'table' and type(all[block]) == 'table' and all[block] or {}
    local out = {}
    for k, v in pairs(def) do
        local c = cur[k]
        if type(v) == 'number' then
            c = tonumber(c)
            out[k] = (c and c == c and c > -1e6 and c < 1e6) and c or v
        elseif type(v) == 'boolean' then
            out[k] = (c == nil) and v or (c == true)
        else
            out[k] = v
        end
    end
    return out
end

local function renderer() return SpinArena.Renderer end

-- Hauteur du fond de la cuvette au-dessus du sol (m, avant échelle) : seulement si la table est affichée
local function floorOffset(scene)
    if scene.arenaProp and scene.arenaProp ~= 0 then
        return tonumber(scene.arena.floorHeight) or 0.75
    end
    return 0.0
end

-- Direction locale de l'arène (x, y) tournée du cap de la table : direction dans le monde
local function toWorldDir(arena, x, y)
    local rad = (tonumber(arena.heading) or 0.0) * (math_pi / 180.0)
    local c, s = math_cos(rad), math_sin(rad)
    return x * c - y * s, x * s + y * c
end

-- Inclinaison vers une direction du monde (dx, dy unitaire) : rotation X (pitch) et Y (roll) en degrés
-- (rotation X positive : l'axe de la toupie part vers −Y ; rotation Y positive : vers +X)
function Spectacle.tiltToward(deg, dx, dy)
    return -deg * dy, deg * dx
end

-------------------------------------------------------------------------------
-- Nouvelle manche, nouveau ralenti : état visuel remis à zéro
-------------------------------------------------------------------------------
function Spectacle.resetScene(scene, keepReplay)
    if type(scene) ~= 'table' then return end
    scene.trails, scene.ejectFlight, scene.fallState, scene.leanState = {}, {}, {}, {}
    scene.pocketFlash, scene.ejectInfo = {}, {}
    if not keepReplay then scene.replay = nil end
end

-------------------------------------------------------------------------------
-- Traînées lumineuses et lueur des toupies
-------------------------------------------------------------------------------
-- Niveau d'éclat d'une toupie (0..1) selon sa rotation : 0 à l'arrêt ou éjectée
function Spectacle.spinLevel(topState)
    if type(topState) ~= 'table' then return 0.0 end
    if topState.st == STOPPED or topState.st == EJECTED then return 0.0 end
    return clamp((tonumber(topState.w) or 0.0) / 220.0, 0.0, 1.0)
end

function Spectacle.trailPush(scene, i, x, y, z, level, now)
    scene.trails = scene.trails or {}
    local tr = scene.trails[i]
    if not tr then tr = {}; scene.trails[i] = tr end
    local C = Spectacle.cfg('trails')
    local last = tr[#tr]
    if last then
        local dx, dy, dz = x - last.x, y - last.y, z - last.z
        -- Saut (nouvelle manche, ralenti, toupie replacée) : on recommence la traînée au lieu de tirer un trait
        if dx * dx + dy * dy + dz * dz > 0.25 then
            for k = #tr, 1, -1 do tr[k] = nil end
        elseif now - last.t < C.stepMs then
            return tr
        end
    end
    tr[#tr + 1] = { x = x, y = y, z = z, t = now, l = level }
    while #tr > 0 and (now - tr[1].t > C.ms or #tr > Spectacle.TRAIL_MAX_POINTS) do table.remove(tr, 1) end
    return tr
end

function Spectacle.drawTrail(scene, i, color, now)
    local tr = scene.trails and scene.trails[i]
    if not tr or #tr < 2 or type(DrawLine) ~= 'function' then return 0 end
    local C = Spectacle.cfg('trails')
    local drawn = 0
    for k = 2, #tr do
        local a, b = tr[k - 1], tr[k]
        local fade = clamp(1.0 - (now - b.t) / C.ms, 0.0, 1.0)
        local alpha = math_floor(230 * fade * (b.l or 1.0))
        if alpha > 4 then
            -- Deux brins serrés : un trait de DrawLine fait un pixel, deux donnent un ruban lisible à quelques mètres
            DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, color.r, color.g, color.b, alpha)
            DrawLine(a.x, a.y, a.z + 0.006, b.x, b.y, b.z + 0.006, color.r, color.g, color.b, math_floor(alpha * 0.6))
            drawn = drawn + 1
        end
    end
    return drawn
end

-------------------------------------------------------------------------------
-- Chocs : éclair lumineux et poches
-------------------------------------------------------------------------------
-- Appelée à chaque image tant que le flash d'un choc est visible (progress 0 → 1)
function Spectacle.impactLight(ev, wx, wy, wz, progress, intensity)
    local C = Spectacle.cfg('impactLight')
    if not C.enabled or type(DrawLightWithRange) ~= 'function' then return false end
    local kind = type(ev) == 'table' and ev.t or 'hit'
    -- pas d'éclair sur spin_out / wobble ; 29/10 : éclatement (fort) et départ sur le rail (faible)
    if kind ~= 'hit' and kind ~= 'wall' and kind ~= 'ring_out' and kind ~= 'burst' and kind ~= 'dash' then return false end
    local K = { wall = 0.45, ring_out = 1.25, burst = 1.5, dash = 0.5 }
    local k = K[kind] or 1.0
    local power = C.intensity * k * clamp(intensity or 0.6, 0.25, 1.0) * (1.0 - clamp(progress or 0, 0, 1))
    if power <= 0.05 then return false end
    local col = (kind == 'ring_out' or kind == 'burst') and Spectacle.POCKET_FLASH_COLOR or Spectacle.SPARK_COLOR
    DrawLightWithRange(wx, wy, wz + 0.05, col.r, col.g, col.b, C.range * (0.6 + 0.4 * k), power)
    return true
end

-- Poche de la cuvette contenant la direction (x, y) locale, ou nil (sortie par-dessus la paroi)
function Spectacle.pocketAt(arena, x, y)
    local len = math_sqrt(x * x + y * y)
    if len < 1e-6 or type(arena.pockets) ~= 'table' then return nil end
    local ux, uy = x / len, y / len
    for n, p in ipairs(arena.pockets) do
        local a = math_rad(tonumber(p.angle) or 0)
        local half = math_rad(tonumber(p.width) or 0) / 2
        if ux * math_cos(a) + uy * math_sin(a) >= math_cos(half) then return n end
    end
    return nil
end

-- Une toupie sort (événement ring_out du serveur) : sa direction de sortie et l'éclair de sa poche
function Spectacle.onRingOut(scene, ev, now)
    if type(ev) ~= 'table' or not scene.arena then return end
    local x, y = (tonumber(ev.x) or 0) * 0.001, (tonumber(ev.y) or 0) * 0.001
    local side = tonumber(ev.a)
    scene.ejectInfo = scene.ejectInfo or {}
    if side then scene.ejectInfo[side] = { x = x, y = y } end
    local n = Spectacle.pocketAt(scene.arena, x, y)
    if n then
        scene.pocketFlash = scene.pocketFlash or {}
        scene.pocketFlash[n] = now
    end
    return n
end

function Spectacle.drawPockets(scene, now)
    local C = Spectacle.cfg('pockets')
    local R = renderer()
    if not C.enabled or not R or type(DrawLine) ~= 'function' or not scene.arena then return 0 end
    local arena = scene.arena
    if type(arena.pockets) ~= 'table' or #arena.pockets == 0 then return 0 end
    local scale = arena.scale or 1.0
    local rim = tonumber(arena.R) or 0.6
    local z0 = floorOffset(scene) + 0.006
    local pulse = 0.65 + 0.35 * math_sin(now * 0.006)
    local drawn = 0
    for n, p in ipairs(arena.pockets) do
        local flashAt = scene.pocketFlash and scene.pocketFlash[n]
        local flash = flashAt and (now - flashAt) <= C.flashMs
        local col = flash and Spectacle.POCKET_FLASH_COLOR or Spectacle.POCKET_COLOR
        local alpha = flash and math_floor(255 * (0.55 + 0.45 * math_sin(now * 0.03))) or math_floor(150 * pulse)
        local a = math_rad(tonumber(p.angle) or 0)
        local half = math_rad(tonumber(p.width) or 0) / 2
        local segs = 6
        local px, py, pz
        for s = 0, segs do
            local t = a - half + (2 * half) * s / segs
            local x, y, z = R.localToWorld(arena, rim * math_cos(t), rim * math_sin(t), 0.0)
            z = z + z0 * scale
            if px then
                DrawLine(px, py, pz, x, y, z, col.r, col.g, col.b, alpha)
                DrawLine(px, py, pz + 0.004, x, y, z + 0.004, col.r, col.g, col.b, math_floor(alpha * 0.5))
            end
            px, py, pz = x, y, z
        end
        if type(DrawLightWithRange) == 'function' then
            local lx, ly, lz = R.localToWorld(arena, rim * 0.97 * math_cos(a), rim * 0.97 * math_sin(a), 0.0)
            DrawLightWithRange(lx, ly, lz + (z0 + 0.03) * scale, col.r, col.g, col.b, flash and 0.5 or 0.22, flash and 5.0 or 1.2 * pulse)
        end
        drawn = drawn + 1
    end
    return drawn
end

-------------------------------------------------------------------------------
-- Éjection : la toupie vole hors de la table, tombe au sol et y reste couchée
-------------------------------------------------------------------------------
-- Pose d'une toupie éjectée à l'instant now : wx, wy, wz (monde), pitch, roll, yaw (°). nil = ancien comportement
-- (réglage coupé ou table absente : il n'y a alors pas de hauteur de sol connue).
function Spectacle.ejectPose(scene, i, topState, now)
    local C = Spectacle.cfg('eject')
    local R = renderer()
    if not C.enabled or not R or not scene.arena or not (scene.arenaProp and scene.arenaProp ~= 0) then return nil end
    local arena = scene.arena
    scene.ejectFlight = scene.ejectFlight or {}
    local f = scene.ejectFlight[i]
    if not f then
        local info = scene.ejectInfo and scene.ejectInfo[i]
        local x0, y0 = tonumber(topState.x) or 0.0, tonumber(topState.y) or 0.0
        local dx, dy = (info and info.x) or x0, (info and info.y) or y0
        local len = math_sqrt(dx * dx + dy * dy)
        if len < 1e-6 then dx, dy, len = 1.0, 0.0, 1.0 end
        local h = R.bowlLocalZ(arena, x0, y0)
        f = {
            startMs = now, x0 = x0, y0 = y0, ux = dx / len, uy = dy / len,
            z0 = floorOffset(scene) + h + 0.01,   -- départ : hauteur de la toupie au bord de la cuvette, depuis le sol
            yaw = ((scene.visualAngles and scene.visualAngles[i]) or 0.0) * 180.0 / math_pi,
            side = (i % 2 == 0) and 1 or -1,
        }
        -- Temps de chute jusqu'au sol (z = 0 sous la table) : z0 + up·t − g·t²/2 = 0
        f.tFall = (C.up + math_sqrt(C.up * C.up + 2.0 * G * f.z0)) / G
        scene.ejectFlight[i] = f
    end
    local t = math_max(0.0, (now - f.startMs) * 0.001)
    local dist, z, tilt, spin
    if t <= f.tFall then
        dist = C.speed * t
        z = f.z0 + C.up * t - 0.5 * G * t * t
        tilt = 25.0 * (t / f.tFall)
        spin = 720.0 * t
    else
        -- Au sol : glisse encore un peu en ralentissant, puis se couche
        local s = math_min(t - f.tFall, 0.45)
        dist = C.speed * f.tFall + C.speed * 0.5 * (s - s * s / 0.9)
        local k = clamp((t - f.tFall) / 0.35, 0.0, 1.0)
        z = 0.012 * math_abs(math_sin(k * math_pi)) * (1.0 - k)   -- petit rebond
        tilt = 25.0 + (80.0 - 25.0) * (1.0 - (1.0 - k) * (1.0 - k))
        spin = 720.0 * f.tFall + 240.0 * s
    end
    local lx, ly = f.x0 + f.ux * dist, f.y0 + f.uy * dist
    local wx, wy = R.localToWorld(arena, lx, ly, 0.0)
    local scale = arena.scale or 1.0
    local wz = (tonumber(arena.z) or 0.0) + scale * z
    local wdx, wdy = toWorldDir(arena, f.ux, f.uy)
    local pitch, roll = Spectacle.tiltToward(tilt, wdx, wdy)
    return wx, wy, wz, pitch, roll, (f.yaw + f.side * spin) % 360.0
end

-------------------------------------------------------------------------------
-- Arrêt et virages : inclinaison de la toupie (s'ajoute à l'oscillation calculée par le rendu)
-------------------------------------------------------------------------------
-- Toupie arrêtée : bascule sur le côté. Renvoie pitch, roll (°) ; nil si elle n'est pas arrêtée
function Spectacle.fallTilt(scene, i, topState, now, baseDeg)
    local C = Spectacle.cfg('fallOver')
    scene.fallState = scene.fallState or {}
    if not C.enabled or type(topState) ~= 'table' or topState.st ~= STOPPED then
        scene.fallState[i] = nil
        return nil
    end
    local f = scene.fallState[i]
    if not f then
        local ang = (scene.visualAngles and scene.visualAngles[i]) or 0.0
        f = { startMs = now, dx = math_cos(ang), dy = math_sin(ang), from = tonumber(baseDeg) or 0.0 }
        scene.fallState[i] = f
    end
    local k = clamp((now - f.startMs) / math_max(1, C.ms), 0.0, 1.0)
    -- Chute accélérée puis léger rebond sur la tranche
    local e = k * k
    if k >= 1.0 then e = 1.0 end
    local bounce = (k > 0.7) and (0.06 * math_sin((k - 0.7) / 0.3 * math_pi)) or 0.0
    local deg = f.from + (C.deg - f.from) * e - C.deg * bounce
    local wdx, wdy = toWorldDir(scene.arena or {}, f.dx, f.dy)
    return Spectacle.tiltToward(deg, wdx, wdy)
end

-- Virages : la toupie penche vers le centre de sa courbe (accélération lissée des positions affichées)
function Spectacle.leanTilt(scene, i, x, y, frameDt)
    local C = Spectacle.cfg('lean')
    if not C.enabled or not frameDt or frameDt < 0.001 then return 0.0, 0.0 end
    scene.leanState = scene.leanState or {}
    local s = scene.leanState[i]
    if not s or (x - s.x) ^ 2 + (y - s.y) ^ 2 > 0.04 then
        scene.leanState[i] = { x = x, y = y, vx = 0.0, vy = 0.0, ax = 0.0, ay = 0.0 }
        return 0.0, 0.0
    end
    local vx, vy = (x - s.x) / frameDt, (y - s.y) / frameDt
    local ax, ay = (vx - s.vx) / frameDt, (vy - s.vy) / frameDt
    local k = clamp(frameDt * 6.0, 0.02, 0.5)   -- lissage : les keyframes à 20 Hz donnent des accélérations hachées
    s.ax, s.ay = s.ax + (ax - s.ax) * k, s.ay + (ay - s.ay) * k
    s.vx, s.vy, s.x, s.y = s.vx + (vx - s.vx) * 0.5, s.vy + (vy - s.vy) * 0.5, x, y
    local a = math_sqrt(s.ax * s.ax + s.ay * s.ay)
    if a < 0.05 then return 0.0, 0.0 end
    local deg = math_min(C.maxDeg, math_atan(a / G) * 180.0 / math_pi)
    local wdx, wdy = toWorldDir(scene.arena or {}, s.ax / a, s.ay / a)
    return Spectacle.tiltToward(deg, wdx, wdy)
end

-------------------------------------------------------------------------------
-- Dessin par image d'une scène (appelé par le rendu après les props)
-------------------------------------------------------------------------------
function Spectacle.drawScene(scene, interp, now)
    if type(scene) ~= 'table' or type(interp) ~= 'table' or type(interp.tops) ~= 'table' then return end
    local R = renderer()
    if not R or not scene.arena then return end
    if scene.state == 'playing' or scene.state == 'countdown' or scene.state == 'preparing'
        or (scene.replay and scene.replay.state == 'playing') then
        Spectacle.drawPockets(scene, now)
    end
    local C = Spectacle.cfg('trails')
    if not C.enabled then return end
    local scale = scene.arena.scale or 1.0
    local lift = floorOffset(scene) * scale + 0.03 * scale   -- milieu de la toupie, au-dessus du fond de la cuvette
    for i = 1, 2 do
        local ts = interp.tops[i]
        local meta = scene.tops and scene.tops[i] or {}
        local color = meta.color or { r = 255, g = 255, b = 255 }
        local level = (scene.starving or scene.state == 'countdown' or scene.state == 'preparing') and 0.0 or Spectacle.spinLevel(ts)
        if level > 0.0 then
            local wx, wy, wz = R.localToWorld(scene.arena, ts.x or 0.0, ts.y or 0.0, 0.0)
            wz = wz + lift
            Spectacle.trailPush(scene, i, wx, wy, wz, level, now)
            if type(DrawLightWithRange) == 'function' and C.glowRange > 0 then
                DrawLightWithRange(wx, wy, wz + 0.03 * scale, color.r, color.g, color.b, C.glowRange * scale, C.glowIntensity * level)
            end
        elseif scene.trails and scene.trails[i] then
            -- La traînée s'éteint d'elle-même (plus de nouveaux points) : on laisse finir le fondu
            local tr = scene.trails[i]
            while #tr > 0 and now - tr[1].t > C.ms do table.remove(tr, 1) end
        end
        Spectacle.drawTrail(scene, i, color, now)
    end
end

-------------------------------------------------------------------------------
-- Ralenti du coup final : rejoue les dernières keyframes déjà reçues, sans aucun échange avec le serveur
-------------------------------------------------------------------------------
-- Fin de manche décisive (éjection ou arrêt) : le ralenti est armé, il démarrera quand la lecture atteindra la fin
function Spectacle.planReplay(scene)
    local C = Spectacle.cfg('replay')
    if not C.enabled or type(scene) ~= 'table' or type(scene.outcome) ~= 'table' then return false end
    local o = scene.outcome
    local decisive = { ring_out = true, spin_out = true, burst = true, turbo_out = true }
    if not decisive[o.reason] then return false end
    local endStep = tonumber(o.step) or 0
    if endStep <= 0 or not scene.frames or #scene.frames < 2 then return false end
    scene.replay = { state = 'armed', endStep = endStep }
    return true
end

-- Durée totale d'un ralenti (ms) : sert à prolonger le maintien de fin de manche
function Spectacle.replayDurationMs()
    local C = Spectacle.cfg('replay')
    return C.delayMs + (C.windowS / math_max(0.05, C.speed)) * 1000.0 + 600
end

local function startReplay(scene, now, C)
    local rp = scene.replay
    local dt = tonumber(scene.dt) or (1 / 120)
    local first = scene.frames[1] and scene.frames[1].step or 0
    rp.fromStep = math_max(first, rp.endStep - C.windowS / dt)
    rp.startMs, rp.state = now, 'playing'
    -- Les chocs du passage rejoué repartent (étincelles, sons, éclairs), les toupies reviennent dans la cuvette
    for _, ev in ipairs(scene.events or {}) do
        if (tonumber(ev.s) or 0) >= rp.fromStep then ev.triggeredAtMs = nil end
    end
    Spectacle.resetScene(scene, true)
    scene.ejectedState = {}
    if scene.topProps and scene.topPropsTried then
        for i = 1, 2 do if not scene.topProps[i] then scene.topPropsTried[i] = nil end end
    end
end

-- Pas de lecture à afficher : (pas, facteur de vitesse). Hors ralenti, renvoie la lecture normale inchangée.
function Spectacle.replayStep(scene, targetStep, now)
    local rp = type(scene) == 'table' and scene.replay
    if not rp then return targetStep, 1.0 end
    local C = Spectacle.cfg('replay')
    if rp.state == 'armed' then
        if targetStep >= rp.endStep then
            rp.reachedAt = rp.reachedAt or now
            if now - rp.reachedAt >= C.delayMs then startReplay(scene, now, C) else return targetStep, 1.0 end
        else
            return targetStep, 1.0
        end
    end
    if rp.state == 'playing' then
        local dt = tonumber(scene.dt) or (1 / 120)
        local s = rp.fromStep + (now - rp.startMs) * 0.001 * C.speed / dt
        if s >= rp.endStep then
            s = rp.endStep
            rp.doneAt = rp.doneAt or now
            if now - rp.doneAt >= 600 then rp.state = 'done' end
        end
        return s, C.speed
    end
    return targetStep, 1.0
end

function Spectacle.replayActive(scene)
    return type(scene) == 'table' and scene.replay ~= nil and (scene.replay.state == 'armed' or scene.replay.state == 'playing')
end

return Spectacle
