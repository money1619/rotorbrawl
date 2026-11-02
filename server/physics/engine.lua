-- Moteur de manche ROTORBRAWL (docs/PHYSICS.md) : état, pas fixe, fin de manche, keyframes.
-- Module pur en Lua 5.4 standard : aucune native FiveM, aucune horloge, aucun pairs() dans la boucle.
SpinArena = SpinArena or {}

local Engine = {}
local Collisions = SpinArena.Collisions
local Boundaries = SpinArena.Boundaries
local Rng = SpinArena.Rng
local sqrt, floor = math.sqrt, math.floor

local SPINNING, STOPPING, STOPPED, EJECTED = 0, 1, 2, 3
Engine.SPINNING, Engine.STOPPING, Engine.STOPPED, Engine.EJECTED = SPINNING, STOPPING, STOPPED, EJECTED

-- Bornes des caractéristiques (PHYSICS.md §4). En mode labo, les bornes basses tombent à 0 sauf m, r, kI.
local STAT_BOUNDS = {
    { 'm', 0.035, 0.065, true },
    { 'r', 0.040, 0.060, true },
    { 'kI', 0.45, 0.75, true },
    { 'atk', 0, 1 },
    { 'def', 0, 1 },
    { 'stab', 0, 1 },
    { 'tipFric', 2.0, 7.0 },
    { 'mob', 0.1, 1.8 },
    { 'trac', 0.5, 3.0 },
    { 'damp', 0.15, 0.8 },
    { 'w0', 200, 300 },
    { 'v0', 0.3, 0.9 },
}

-- Constantes physiques obligatoires et leurs bornes
local PHYSICS_BOUNDS = {
    { 'g', 0, 50 }, { 'beta', 0, 1 }, { 'kWob', 0, 10 }, { 'kWobUp', 0, 10 }, { 'kWobDown', 0, 10 },
    { 'wWobBase', 0, 400 }, { 'wWobStab', 0, 400 }, { 'wStop', 0, 200 }, { 'wRef', 1, 1000 },
    { 'kDrive', 0, 5 }, { 'driveFade', 0.001, 1 }, { 'sigma', 0, 5 }, { 'vMax', 0.1, 10 },
    { 'eBase', 0, 1 }, { 'eAtk', 0, 1 }, { 'eMin', 0, 1 }, { 'eMax', 0, 1 },
    { 'kSmash', 0, 1 }, { 'sigmaCap', 0, 200 }, { 'muC', 0, 2 }, { 'kW', 0, 5 }, { 'kImpWob', 0, 1 },
    { 'contactCooldown', 0, 2 }, { 'eWall', 0, 0.99 }, { 'muWall', 0, 2 }, { 'vPocket', 0, 10 },
    { 'vOver', 0, 20 }, { 'startRadius', 0, 0.95 }, { 'launchAngle', -90, 90 }, { 'launchJitter', 0, 45 },
    { 'w0Jitter', 0, 0.5 }, { 'flowerLean', 0, 20 }, { 'flowerFreq', 0, 10 },
    { 'flowerThreshold', 0, 0.95 },
}

-- Constantes facultatives (0 si absentes) : aléa du départ, désynchronisation du motif, recherche du contact
local OPTIONAL_PHYSICS = {
    { 'startSpread', 0, 90 }, { 'startRadiusJitter', 0, 0.5 }, { 'flowerJitter', 0, 0.9 },
    { 'kSeek', 0, 5 }, { 'stabNoise', 0, 1 }, { 'tiltAngle', 0, 60 },
    -- Éclatement (29/10) : réserve de verrou entamée par les chocs ; 0 = pas d'éclatement
    { 'burstLock', 0, 100 }, { 'burstSame', 0, 3 }, { 'burstSpin', 0, 3 },
    -- Rail turbo (29/10) : bande extérieure où l'embout accroche et accélère ; 0 = pas de rail
    { 'railInner', 0, 0.99 }, { 'railBoost', 0, 20 }, { 'railTime', 0, 2 }, { 'railCool', 0, 10 },
    { 'railSpinCost', 0, 2 }, { 'turboWindow', 0, 3 }, { 'railExit', 0, 2 },
}

-- Caractéristiques facultatives des pièces (29/10), neutres si absentes : résistance du verrou, accroche au rail
local OPTIONAL_STATS = { { 'burst', 0, 1 }, { 'dash', 0, 1 }, { 'tiltMul', 0, 3 } }

local function finite(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function inRange(v, lo, hi)
    return finite(v) and v >= lo and v <= hi
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function validateStats(stats, lab, k)
    if type(stats) ~= 'table' then return ('tops[%d]'):format(k) end
    for n = 1, #STAT_BOUNDS do
        local b = STAT_BOUNDS[n]
        local lo = (lab and not b[4]) and 0 or b[2]
        if not inRange(stats[b[1]], lo, b[3]) then
            return ('tops[%d].%s'):format(k, b[1])
        end
    end
    if stats.dir ~= 1 and stats.dir ~= -1 then return ('tops[%d].dir'):format(k) end
    for n = 1, #OPTIONAL_STATS do
        local b = OPTIONAL_STATS[n]
        if stats[b[1]] ~= nil and not inRange(stats[b[1]], b[2], b[3]) then return ('tops[%d].%s'):format(k, b[1]) end
    end
    -- Inclinaison du lanceur (facultative) : −1 vers le bord, 0 droit, 1 vers le centre
    if stats.tilt ~= nil and stats.tilt ~= -1 and stats.tilt ~= 0 and stats.tilt ~= 1 then return ('tops[%d].tilt'):format(k) end
    return nil
end

local function validate(params)
    if type(params) ~= 'table' then return 'params' end
    if not inRange(params.dt, 1e-4, 0.05) then return 'dt' end
    if math.type(params.seed) ~= 'integer' then return 'seed' end
    if math.type(params.keyframeEvery) ~= 'integer' or params.keyframeEvery < 1 or params.keyframeEvery > 120 then
        return 'keyframeEvery'
    end

    local arena = params.arena
    if type(arena) ~= 'table' then return 'arena' end
    if not inRange(arena.R, 0.2, 5) then return 'arena.R' end
    if not inRange(arena.h, 0, 0.5) then return 'arena.h' end
    if arena.railBoost ~= nil and not inRange(arena.railBoost, 0, 20) then return 'arena.railBoost' end
    -- Mode puissance d'une table (grande arène de tournoi) : les DEUX toupies sont lancées plus vite (v) et tournent plus fort (w)
    if arena.power ~= nil then
        if type(arena.power) ~= 'table' then return 'arena.power' end
        if not inRange(arena.power.v or 1, 1, 1.5) then return 'arena.power.v' end
        if not inRange(arena.power.w or 1, 1, 1.3) then return 'arena.power.w' end
    end
    if type(arena.pockets) ~= 'table' or #arena.pockets > 12 then return 'arena.pockets' end
    for i = 1, #arena.pockets do
        local p = arena.pockets[i]
        if type(p) ~= 'table' or not inRange(p.angle, -360, 360) or not inRange(p.width, 0.1, 120) then
            return ('arena.pockets[%d]'):format(i)
        end
    end

    local rules = params.rules
    if type(rules) ~= 'table' then return 'rules' end
    if not inRange(rules.Tmax, 0.1, 600) then return 'rules.Tmax' end
    if not inRange(rules.stopConfirm, 0, 10) then return 'rules.stopConfirm' end
    if not inRange(rules.tieEps, 0, 0.5) then return 'rules.tieEps' end

    local c = params.physics
    if type(c) ~= 'table' then return 'physics' end
    for n = 1, #PHYSICS_BOUNDS do
        local b = PHYSICS_BOUNDS[n]
        if not inRange(c[b[1]], b[2], b[3]) then return 'physics.' .. b[1] end
    end
    for n = 1, #OPTIONAL_PHYSICS do
        local b = OPTIONAL_PHYSICS[n]
        if c[b[1]] ~= nil and not inRange(c[b[1]], b[2], b[3]) then return 'physics.' .. b[1] end
    end
    if c.eMin > c.eMax then return 'physics.eMin' end

    if type(params.tops) ~= 'table' or #params.tops ~= 2 then return 'tops' end
    for k = 1, 2 do
        local err = validateStats(params.tops[k], params.lab == true, k)
        if err then return err end
        if params.tops[k].r * 2 >= arena.R then return ('tops[%d].r'):format(k) end
    end

    local initial = params.initial
    if initial ~= nil then
        if type(initial) ~= 'table' then return 'initial' end
        for k = 1, 2 do
            local s = initial[k]
            if s ~= nil then
                if type(s) ~= 'table' then return ('initial[%d]'):format(k) end
                local lim = arena.R - params.tops[k].r
                for _, key in ipairs({ 'x', 'y', 'vx', 'vy', 'w', 'wob', 'ang' }) do
                    if s[key] ~= nil and not finite(s[key]) then return ('initial[%d].%s'):format(k, key) end
                end
                local x, y = s.x or 0, s.y or 0
                if x * x + y * y > lim * lim then return ('initial[%d].position'):format(k) end
                local vx, vy = s.vx or 0, s.vy or 0
                if vx * vx + vy * vy > c.vMax * c.vMax then return ('initial[%d].velocity'):format(k) end
                if s.w ~= nil and not inRange(s.w, 0, 400) then return ('initial[%d].w'):format(k) end
                if s.wob ~= nil and not inRange(s.wob, 0, 1) then return ('initial[%d].wob'):format(k) end
            end
        end
    end
    return nil
end

-- Crée une manche. Renvoie round, ou nil et le nom du premier paramètre invalide.
function Engine.newRound(params)
    local err = validate(params)
    if err then return nil, 'invalid_param:' .. err end

    local c, arena, dt = params.physics, params.arena, params.dt
    local rng = Rng.new(params.seed)
    local round = {
        dt = dt,
        step = 0,
        done = false,
        outcome = nil,
        physics = c,
        arena = arena,
        rules = params.rules,
        rng = rng,
        pockets = Boundaries.prepare(arena),
        kBowl = 2 * c.g * arena.h / (arena.R * arena.R),
        tmaxSteps = math.ceil(params.rules.Tmax / dt - 1e-9),
        confirmSteps = math.ceil(params.rules.stopConfirm / dt - 1e-9),
        cooldownSteps = math.ceil(c.contactCooldown / dt - 1e-9),
        keyframeEvery = params.keyframeEvery,
        cooldown = {},
        tops = {},
    }
    round.maxSteps = round.tmaxSteps + 1
    round.railSteps = math.ceil((c.railTime or 0) / dt - 1e-9)
    round.railCoolSteps = math.ceil((c.railCool or 0) / dt - 1e-9)
    round.turboSteps = math.ceil((c.turboWindow or 0) / dt - 1e-9)
    local startSpread, radiusJitter = c.startSpread or 0, c.startRadiusJitter or 0
    local flowerJitter = c.flowerJitter or 0
    local pv, pw = arena.power and arena.power.v or 1, arena.power and arena.power.w or 1   -- mode puissance (même pour les deux)

    -- Départ : positions à peu près opposées, angle de départ tiré au sort ; chaque toupie reçoit son propre
    -- écart d'angle et de rayon (startSpread, startRadiusJitter) pour qu'aucune manche ne commence pareil
    local phi0 = rng:next() * 2 * math.pi
    for k = 1, 2 do
        local s = params.tops[k]
        local phi = phi0 + (k - 1) * math.pi
        if startSpread > 0 then phi = phi + math.rad(rng:range(-startSpread, startSpread)) end
        local ux, uy = math.cos(phi), math.sin(phi)
        local rad = c.startRadius * arena.R
        if radiusJitter > 0 then
            rad = math.min(rad * (1 + rng:range(-radiusJitter, radiusJitter)), 0.95 * (arena.R - s.r))
        end
        local alpha = math.rad(c.launchAngle + (s.tilt or 0) * (c.tiltAngle or 0) * (s.tiltMul or 1) + rng:range(-c.launchJitter, c.launchJitter))
        local tx, ty = -uy * s.dir, ux * s.dir
        local top = {
            m = s.m, r = s.r, kI = s.kI, atk = s.atk, def = s.def, stab = s.stab,
            tipFric = s.tipFric, mob = s.mob, trac = s.trac, damp = s.damp, dir = s.dir,
            x = ux * rad, y = uy * rad,
            vx = s.v0 * pv * (math.cos(alpha) * tx - math.sin(alpha) * ux),
            vy = s.v0 * pv * (math.cos(alpha) * ty - math.sin(alpha) * uy),
            w = s.w0 * pw * (1 + rng:range(-c.w0Jitter, c.w0Jitter)),
            ang = 0, wob = 0, status = SPINNING, stopSince = nil, wobFlag = false,
            burstRes = s.burst or 0.5, dash = s.dash or 0,
            dashUntil = -1, dashCool = -1, lastHitStep = nil, lastHitDash = false, burst = false,
        }
        -- Verrou : réserve entamée par les chocs (0,3 à 1,7 × burstLock selon la résistance de la pièce)
        top.lock = (c.burstLock or 0) * (0.3 + 1.4 * top.burstRes)
        local phase = rng:next() * 2 * math.pi
        top.fc, top.fs = math.cos(phase), math.sin(phase)
        -- Rythme du motif propre à chaque toupie : les plongées vers le centre ne sont plus synchronisées
        local freq = c.flowerFreq
        if flowerJitter > 0 then freq = freq * (1 + rng:range(-flowerJitter, flowerJitter)) end
        top.flowerCos, top.flowerSin = math.cos(freq * dt), math.sin(freq * dt)
        local init = params.initial and params.initial[k]
        if init then
            for _, key in ipairs({ 'x', 'y', 'vx', 'vy', 'w', 'wob', 'ang' }) do
                if init[key] ~= nil then top[key] = init[key] end
            end
        end
        top.px, top.py = top.x, top.y
        round.tops[k] = top
    end
    return round
end

local function integrate(round, top, other)
    local c, dt = round.physics, round.dt

    -- Rotation : frottement de pointe + air, aggravés par l'oscillation
    local w = top.w - (top.tipFric + c.beta * top.w) * (1 + c.kWob * top.wob) * dt
    top.w = w > 0 and w or 0

    -- Oscillation
    local wWob = c.wWobBase - c.wWobStab * top.stab
    if top.w < wWob and wWob > 0 then
        top.wob = top.wob + c.kWobUp * (1 - top.w / wWob) * dt
    else
        top.wob = top.wob - c.kWobDown * top.wob * dt
    end
    top.wob = clamp(top.wob, 0, 1)

    -- Motif en fleur : la direction d'entraînement penche périodiquement vers le centre puis vers le bord.
    -- Phase tournée par une matrice pré-calculée (pas de sin/cos dans la boucle), renormalisée à chaque pas.
    local fc = top.fc * top.flowerCos - top.fs * top.flowerSin
    local fs = top.fs * top.flowerCos + top.fc * top.flowerSin
    local fl = sqrt(fc * fc + fs * fs)
    top.fc, top.fs = fc / fl, fs / fl

    -- Forces : cuvette, entraînement par la pointe, amortissement, perturbation
    local x, y = top.x, top.y
    local ax, ay = -round.kBowl * x, -round.kBowl * y
    local rr = sqrt(x * x + y * y)
    if rr > 1e-9 and c.kDrive > 0 then
        -- Vitesse visée : tangentielle (orbite), penchée vers le centre pendant la phase haute du motif.
        -- La poursuite porte sur le vecteur complet : en plongée, la vitesse tangentielle est freinée,
        -- sinon le moment angulaire conservé par la cuvette empêcherait tout passage près du centre.
        local ux, uy = x / rr, y / rr
        local lean = top.fs - c.flowerThreshold
        lean = lean > 0 and c.flowerLean * lean / (1 - c.flowerThreshold) or 0
        local dx, dy = -uy * top.dir - lean * ux, ux * top.dir - lean * uy
        -- Recherche du contact : la direction visée penche vers l'adversaire, d'autant plus que l'attaque
        -- dépasse la défense (une toupie d'attaque chasse, une toupie de défense tient son orbite)
        local kSeek = c.kSeek or 0
        if kSeek > 0 and other and other.status ~= EJECTED then
            local seek = kSeek * (top.atk - 0.5 * top.def)
            if seek > 0 then
                local ox, oy = other.x - x, other.y - y
                local od = sqrt(ox * ox + oy * oy)
                if od > 1e-9 then dx, dy = dx + seek * ox / od, dy + seek * oy / od end
            end
        end
        local dl = sqrt(dx * dx + dy * dy)
        if dl < 1e-9 then dx, dy, dl = -uy * top.dir, ux * top.dir, 1 end
        local vOrb = top.mob * (top.w / c.wRef)
        local k = c.kDrive * top.trac * (rr < c.driveFade and rr / c.driveFade or 1)
        ax = ax + k * (vOrb * dx / dl - top.vx)
        ay = ay + k * (vOrb * dy / dl - top.vy)
    end
    -- Rail turbo : dans la bande extérieure, une toupie qui roule dans son sens de rotation accroche le rail avec
    -- son embout (dash) et part en accélération tangentielle pendant railTime, puis attend railCool
    -- Le rail est une pièce du stade : la variante d'arène le porte (arena.railBoost), sinon physics.railBoost
    local railBoost = round.arena.railBoost or c.railBoost or 0
    if railBoost > 0 and top.dash > 0 and rr > 1e-9 then
        local ux, uy = x / rr, y / rr
        local tx, ty = -uy * top.dir, ux * top.dir
        local s = round.step
        if s > top.dashUntil and s >= top.dashCool and rr >= (c.railInner or 0.8) * round.arena.R
            and top.vx * tx + top.vy * ty > 0.05 and top.w > c.wStop then
            top.dashUntil, top.dashCool, top.dashStart = s + round.railSteps, s + round.railCoolSteps, true
        end
        if s <= top.dashUntil then
            local wk = clamp(top.w / c.wRef, 0, 1.5)
            ax, ay = ax + railBoost * top.dash * wk * tx, ay + railBoost * top.dash * wk * ty
            top.w = top.w * (1 - (c.railSpinCost or 0) * dt)
        end
    end
    ax, ay = ax - top.damp * top.vx, ay - top.damp * top.vy
    -- Perturbation : plus forte quand la toupie oscille ; une toupie stable (stab) y résiste mieux
    local amp = c.sigma * (1 + 4 * top.wob) * (1 + (c.stabNoise or 0) * (1 - 2 * top.stab))
    ax = ax + amp * round.rng:normal()
    ay = ay + amp * round.rng:normal()

    -- Euler semi-implicite, vitesse plafonnée
    local vx, vy = top.vx + ax * dt, top.vy + ay * dt
    -- (Retenir la vitesse vers l'extérieur pendant l'accélération empêchait presque toute éjection : retiré au banc
    -- du 29/10. La paroi tient seulement un peu mieux la toupie sur le rail, server/physics/boundaries.lua.)
    if railBoost > 0 and rr > 1e-9 then
        local s = round.step
        if s == top.dashUntil and other and other.status ~= EJECTED then
            top.dashEnd = true   -- la sortie du rail change la vitesse d'un coup : un événement pose une keyframe
            -- Sortie du rail : relancée vers l'adversaire (60 %), vitesse augmentée de railExit (plafonnée par vMax)
            local ox, oy = other.x - x, other.y - y
            local od, sp = sqrt(ox * ox + oy * oy), sqrt(vx * vx + vy * vy)
            if od > 1e-9 and sp > 1e-9 then
                local dx, dy = 0.6 * ox / od + 0.4 * vx / sp, 0.6 * oy / od + 0.4 * vy / sp
                local dl = sqrt(dx * dx + dy * dy)
                sp = sp * (1 + (c.railExit or 0))
                if dl > 1e-9 then vx, vy = sp * dx / dl, sp * dy / dl end
            end
        end
    end
    local v2 = vx * vx + vy * vy
    if v2 > c.vMax * c.vMax then
        local f = c.vMax / sqrt(v2)
        vx, vy = vx * f, vy * f
    end
    top.vx, top.vy = vx, vy
    top.px, top.py = x, y
    top.x, top.y = x + vx * dt, y + vy * dt
    top.ang = (top.ang + top.dir * top.w * dt) % (2 * math.pi)
end

local function mm(v)
    return floor(v * 1000 + 0.5)
end

-- Format commun : { s, t, a, b?, x (mm), y (mm), k (0-255) } ; position de la toupie a si l'événement n'en a pas
local function pushEvent(events, round, ev)
    ev.s = round.step
    if not ev.x then
        local top = round.tops[ev.a]
        ev.x, ev.y = top.x, top.y
    end
    ev.x, ev.y = mm(ev.x), mm(ev.y)
    ev.k = ev.k or 0
    events[#events + 1] = ev
end

-- Finition d'une toupie hors jeu : éclatement, éjection turbo (frappée par une adversaire lancée sur le rail
-- dans les turboWindow secondes), éjection simple, arrêt de rotation
function Engine.finishOf(round, top)
    if top.burst then return 'burst' end
    if top.status == EJECTED then
        if round.turboSteps > 0 and top.lastHitDash and top.lastHitStep
            and round.step - top.lastHitStep <= round.turboSteps then
            return 'turbo_out'
        end
        return 'ring_out'
    end
    return 'spin_out'
end

local function decide(round)
    local A, B = round.tops[1], round.tops[2]
    local endA = A.status == EJECTED or A.status == STOPPED
    local endB = B.status == EJECTED or B.status == STOPPED
    local s = round.step

    if endA and endB then
        if A.status == STOPPED and B.status == STOPPED then
            local winner = nil
            if A.stopSince < B.stopSince then winner = 2 elseif B.stopSince < A.stopSince then winner = 1 end
            return { winner = winner, reason = 'spin_out', step = s }
        end
        return { winner = nil, reason = 'double_out', step = s }
    elseif endA then
        return { winner = 2, reason = Engine.finishOf(round, A), step = s }
    elseif endB then
        return { winner = 1, reason = Engine.finishOf(round, B), step = s }
    end

    local reason = (s >= round.tmaxSteps and 'time') or (s >= round.maxSteps and 'max_steps') or nil
    if not reason then return nil end
    local hi = math.max(A.w, B.w)
    local winner = nil
    if hi > 0 and math.abs(A.w - B.w) / hi > round.rules.tieEps then
        winner = A.w > B.w and 1 or 2
    end
    return { winner = winner, reason = reason, step = s }
end

-- Avance la manche d'un pas fixe. Renvoie les événements du pas ; après la fin, ne modifie plus rien.
function Engine.step(round)
    if round.done then return {} end
    local events = {}
    local tops = round.tops
    round.step = round.step + 1
    for k = 1, 2 do
        local top = tops[k]
        top.prevStatus, top.prevW, top.prevWob = top.status, top.w, top.wob
    end

    for k = 1, 2 do
        if tops[k].status ~= EJECTED then
            integrate(round, tops[k], tops[3 - k])
            if tops[k].dashStart then
                tops[k].dashStart = false
                pushEvent(events, round, { t = 'dash', a = k })
            end
            if tops[k].dashEnd then
                tops[k].dashEnd = false
                pushEvent(events, round, { t = 'dash_end', a = k })
            end
        end
    end

    if tops[1].status ~= EJECTED and tops[2].status ~= EJECTED then
        round.impact = nil
        local hit = Collisions.resolve(round, 1, 2)
        if hit then
            pushEvent(events, round, hit)
            Engine.applyImpact(round, events)
        end
    end

    -- Bords : on note les éjections, appliquées ensuite à toutes les toupies en même temps
    local ejected = {}
    for k = 1, 2 do
        if tops[k].status ~= EJECTED then
            local ev = Boundaries.resolve(round, k)
            if ev then
                if ev.t == 'ring_out' then ejected[k] = true end
                pushEvent(events, round, ev)
            end
        end
    end

    -- Statuts calculés pour toutes les toupies, puis appliqués ensemble
    local c = round.physics
    local newStatus = {}
    for k = 1, 2 do
        local top = tops[k]
        if top.status == EJECTED or ejected[k] then
            newStatus[k] = EJECTED
        elseif top.burst then
            newStatus[k] = STOPPED   -- éclatée : hors combat tout de suite
            top.w, top.stopSince = 0, top.stopSince or round.step
        else
            if top.w < c.wStop or top.wob >= 1 then
                if not top.stopSince then top.stopSince = round.step end
                newStatus[k] = (round.step - top.stopSince >= round.confirmSteps) and STOPPED or STOPPING
            else
                top.stopSince = nil
                newStatus[k] = SPINNING
            end
        end
    end
    for k = 1, 2 do
        local top = tops[k]
        if newStatus[k] == STOPPED and top.status ~= STOPPED and not top.burst then
            pushEvent(events, round, { t = 'spin_out', a = k, x = top.x, y = top.y })
        end
        if top.wob >= 0.5 and not top.wobFlag then
            top.wobFlag = true
            pushEvent(events, round, { t = 'wobble', a = k })
        elseif top.wob < 0.3 then
            top.wobFlag = false
        end
        top.status = newStatus[k]
    end

    local outcome = decide(round)
    if outcome then
        round.done = true
        round.outcome = outcome
    end
    return events
end

-- Après un choc : mémoire pour la finition turbo, et usure du verrou (seulement au premier instant d'un contact,
-- quand les bords tournants se percutent). Même sens de rotation : chocs frontaux, plus destructeurs (burstSame).
-- Une toupie qui ralentit tient moins bien son verrou (burstSpin).
function Engine.applyImpact(round, events)
    local imp = round.impact
    if not imp then return end
    local c, s = round.physics, round.step
    local A, B = round.tops[1], round.tops[2]
    -- Frappée par une adversaire en accélération sur le rail (ou qui en sort à peine) : candidate à la finition TURBO
    A.lastHitStep, A.lastHitDash = s, s <= B.dashUntil + round.turboSteps
    B.lastHitStep, B.lastHitDash = s, s <= A.dashUntil + round.turboSteps
    if not imp.smash or (c.burstLock or 0) <= 0 then return end
    local same = (A.dir == B.dir) and (c.burstSame or 1) or 1
    for k = 1, 2 do
        local X, O = round.tops[k], round.tops[3 - k]
        local spin = 1 + (c.burstSpin or 0) * (1 - clamp(X.w / c.wRef, 0, 1))
        X.lock = X.lock - (imp.jn / X.m) * (0.4 + O.atk) * same * spin
    end
    -- Un même choc ne fait éclater qu'une toupie : la plus entamée (l'autre garde un verrou à peine tenu)
    local bA, bB = A.lock <= 0, B.lock <= 0
    if bA and bB then
        if A.lock < B.lock then B.lock, bB = 1e-3, false elseif B.lock < A.lock then A.lock, bA = 1e-3, false end
    end
    for k, b in ipairs({ bA, bB }) do
        if b and not round.tops[k].burst then
            round.tops[k].burst = true
            pushEvent(events, round, { t = 'burst', a = k, k = 255 })
        end
    end
end

function Engine.result(round)
    return round.done, round.outcome
end

-- Keyframe compacte : { pas, x1 mm, y1 mm, w1 (0,1 rad/s), wob1 (0-255), statut1, x2, ... }
function Engine.keyframe(round)
    local f = { round.step }
    for k = 1, 2 do
        local top = round.tops[k]
        f[#f + 1] = mm(top.x)
        f[#f + 1] = mm(top.y)
        f[#f + 1] = floor(top.w * 10 + 0.5)
        f[#f + 1] = floor(top.wob * 255 + 0.5)
        f[#f + 1] = top.status
    end
    return f
end

-- Keyframe de la fin du pas précédent : état mémorisé au début du pas courant
-- (une toupie éjectée n'est plus intégrée : sa position courante est aussi la précédente)
function Engine.keyframeBefore(round)
    local f = { round.step - 1 }
    for k = 1, 2 do
        local top = round.tops[k]
        local moved = top.prevStatus ~= EJECTED
        f[#f + 1] = mm(moved and top.px or top.x)
        f[#f + 1] = mm(moved and top.py or top.y)
        f[#f + 1] = floor((top.prevW or top.w) * 10 + 0.5)
        f[#f + 1] = floor((top.prevWob or top.wob) * 255 + 0.5)
        f[#f + 1] = top.prevStatus or top.status
    end
    return f
end

-- Enregistre ce qu'un pas apporte : une keyframe tous les keyframeEvery pas, et autour de chaque événement
-- la keyframe du pas précédent puis celle du pas courant. Sans la première, l'interpolation linéaire
-- partirait vers la position d'après le choc avant que le choc ait eu lieu.
function Engine.record(round, frames, events, ev)
    if #ev > 0 then
        local last = frames[#frames]
        if round.step > 1 and (not last or last[1] < round.step - 1) then
            frames[#frames + 1] = Engine.keyframeBefore(round)
        end
        for n = 1, #ev do events[#events + 1] = ev[n] end
    end
    if round.step % round.keyframeEvery == 0 or #ev > 0 or round.done then
        frames[#frames + 1] = Engine.keyframe(round)
    end
end

-- Énergies pour les tests (J)
function Engine.energy(round)
    local rot, kin = {}, {}
    for k = 1, 2 do
        local top = round.tops[k]
        rot[k] = Collisions.spinEnergy(top)
        kin[k] = 0.5 * top.m * (top.vx * top.vx + top.vy * top.vy)
    end
    return { rot = rot, kin = kin }
end

-- Manche complète, bornée par maxSteps. Renvoie outcome, keyframes, événements, round ; ou nil, erreur.
function Engine.run(params)
    local round, err = Engine.newRound(params)
    if not round then return nil, err end
    local frames, events = { Engine.keyframe(round) }, {}
    while not round.done do
        Engine.record(round, frames, events, Engine.step(round))
    end
    return round.outcome, frames, events, round
end

-- Paramètres d'une manche à partir de la configuration (copie : le moteur ne garde aucune référence modifiable)
function Engine.paramsFromConfig(cfg, statsA, statsB, seed, arena)
    local function copy(t)
        local r = {}
        for key, v in pairs(t) do r[key] = type(v) == 'table' and copy(v) or v end
        return r
    end
    return {
        dt = cfg.dt,
        seed = seed,
        keyframeEvery = cfg.keyframeEvery,
        physics = copy(cfg.physics),
        rules = copy(cfg.rules),
        arena = copy(arena or cfg.testArena),
        tops = { copy(statsA), copy(statsB) },
    }
end

SpinArena.Engine = Engine
return Engine
