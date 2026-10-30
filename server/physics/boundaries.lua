-- Bords de l'arène, poches et éjections (docs/PHYSICS.md §9).
-- Module pur : aucune native FiveM, aucune horloge.
SpinArena = SpinArena or {}

local Boundaries = {}
local sqrt = math.sqrt

-- Directions des poches calculées une seule fois : la boucle de simulation n'appelle ni cos, ni sin, ni atan2
function Boundaries.prepare(arena)
    local pockets = {}
    for i = 1, #arena.pockets do
        local p = arena.pockets[i]
        local a = math.rad(p.angle)
        pockets[i] = { cx = math.cos(a), cy = math.sin(a), cosHalf = math.cos(math.rad(p.width) / 2) }
    end
    return pockets
end

local function inPocket(pockets, ux, uy)
    for i = 1, #pockets do
        local p = pockets[i]
        if ux * p.cx + uy * p.cy >= p.cosHalf then return true end
    end
    return false
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Traite la toupie d'indice k si elle a franchi la limite pendant le pas.
-- Renvoie un événement 'wall' ou 'ring_out' (coordonnées en mètres), ou nil.
function Boundaries.resolve(round, k)
    local c = round.physics
    local top = round.tops[k]
    local limit = round.arena.R - top.r
    local x, y = top.x, top.y
    if x * x + y * y <= limit * limit then return nil end

    -- Point de franchissement sur le segment parcouru pendant le pas
    local px, py = top.px, top.py
    local dx, dy = x - px, y - py
    local cx, cy = x, y
    local inside = px * px + py * py - limit * limit
    local a = dx * dx + dy * dy
    if inside < 0 and a > 0 then
        local b = 2 * (px * dx + py * dy)
        local t = (-b + sqrt(b * b - 4 * a * inside)) / (2 * a)
        t = clamp(t, 0, 1)
        cx, cy = px + dx * t, py + dy * t
    end
    local len = sqrt(cx * cx + cy * cy)
    local ux, uy = cx / len, cy / len
    local vOut = top.vx * ux + top.vy * uy

    -- Sur le rail turbo (accélération en cours), la toupie est guidée : il faut un choc plus fort pour la sortir
    local hold = (top.dashUntil ~= nil and round.step <= top.dashUntil) and 1.6 or 1
    if (vOut > c.vPocket * hold and inPocket(round.pockets, ux, uy)) or vOut > c.vOver * hold then
        return { t = 'ring_out', a = k, x = ux * round.arena.R, y = uy * round.arena.R }
    end

    -- Sur la paroi : la toupie est ramenée à la limite
    top.x, top.y = ux * limit, uy * limit
    if vOut <= 0 then return nil end

    -- Rebond : composante normale réfléchie (ne crée pas d'énergie, eWall < 1)
    local m = top.m
    local jn = (1 + c.eWall) * m * vOut
    top.vx, top.vy = top.vx - jn / m * ux, top.vy - jn / m * uy

    -- Frottement du bord tournant contre la paroi, borné par la rotation disponible avant application
    local tx, ty = -uy, ux
    local slide = top.vx * tx + top.vy * ty + top.dir * top.w * top.r
    local sgn = slide > 0 and 1 or (slide < 0 and -1 or 0)
    local jt = math.min(c.muWall * jn, math.abs(slide) * m)
    local K0 = 0.5 * m * (top.vx * top.vx + top.vy * top.vy)
    local function cost(j)
        local vx, vy = top.vx - sgn * j / m * tx, top.vy - sgn * j / m * ty
        local dK = 0.5 * m * (vx * vx + vy * vy) - K0
        return c.kW * j * math.abs(slide) + (dK > 0 and dK or 0), vx, vy
    end
    local available = SpinArena.Collisions.available(top, c)
    local need, vx, vy = cost(jt)
    if need > available then
        jt = jt * available / need
        need, vx, vy = cost(jt)
        if need > available then
            jt, need, vx, vy = 0, 0, top.vx, top.vy
        end
    end
    top.vx, top.vy = vx, vy
    SpinArena.Collisions.removeSpinEnergy(top, need)

    -- La paroi agit comme une attaque moyenne (0,5) sur l'oscillation
    top.wob = clamp(top.wob + c.kImpWob * (jn / m) * 0.5 / (0.5 + top.stab + top.def / 2), 0, 1)

    return {
        t = 'wall', a = k, x = ux * round.arena.R, y = uy * round.arena.R,
        k = clamp(math.floor(vOut / 3 * 255 + 0.5), 0, 255),
    }
end

SpinArena.Boundaries = Boundaries
return Boundaries
