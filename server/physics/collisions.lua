-- Collisions entre toupies (docs/PHYSICS.md §8) et outils d'énergie de rotation.
-- Module pur : aucune native FiveM, aucune horloge.
SpinArena = SpinArena or {}

local Collisions = {}
local sqrt = math.sqrt

-- Énergie de rotation E = 0,5 · kI · m · r² · w²
function Collisions.spinEnergy(top, w)
    w = w or top.w
    return 0.5 * top.kI * top.m * top.r * top.r * w * w
end

-- Énergie de rotation disponible au-dessus du seuil d'arrêt : seule réserve que les chocs peuvent consommer
function Collisions.available(top, c)
    local floor = top.w > c.wStop and Collisions.spinEnergy(top, c.wStop) or Collisions.spinEnergy(top)
    local e = Collisions.spinEnergy(top) - floor
    return e > 0 and e or 0
end

function Collisions.removeSpinEnergy(top, loss)
    if loss <= 0 then return end
    local e = Collisions.spinEnergy(top) - loss
    if e <= 0 then
        top.w = 0
    else
        top.w = sqrt(2 * e / (top.kI * top.m * top.r * top.r))
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function kinetic(m, vx, vy)
    return 0.5 * m * (vx * vx + vy * vy)
end

-- Instant de contact dans le pas (0 à 1) par détection continue, ou nil.
-- Résout |d0 + t · (d1 − d0)| = S, d étant le vecteur de A vers B.
local function contactTime(A, B, S)
    local d0x, d0y = B.px - A.px, B.py - A.py
    local mx, my = (B.x - A.x) - d0x, (B.y - A.y) - d0y
    local qc = d0x * d0x + d0y * d0y - S * S
    if qc <= 0 then return 0 end
    local qa = mx * mx + my * my
    if qa <= 0 then return nil end
    local qb = 2 * (d0x * mx + d0y * my)
    local disc = qb * qb - 4 * qa * qc
    if disc < 0 then return nil end
    local t = (-qb - sqrt(disc)) / (2 * qa)
    if t < 0 or t > 1 then return nil end
    return t
end

-- Résout le contact entre les toupies d'indices i et j pendant le pas courant.
-- Renvoie un événement 'hit' (coordonnées en mètres) ou nil.
function Collisions.resolve(round, i, j)
    local c, dt = round.physics, round.dt
    local A, B = round.tops[i], round.tops[j]
    local S = A.r + B.r

    local t = contactTime(A, B, S)
    if not t then return nil end

    -- Positions à l'instant du contact
    local ax, ay = A.px + (A.x - A.px) * t, A.py + (A.y - A.py) * t
    local bx, by = B.px + (B.x - B.px) * t, B.py + (B.y - B.py) * t

    -- Normale de A vers B ; jamais de division par zéro
    local nx, ny = bx - ax, by - ay
    local d = sqrt(nx * nx + ny * ny)
    if d > 1e-9 then
        nx, ny = nx / d, ny / d
    else
        local rx, ry = A.vx - B.vx, A.vy - B.vy
        local rl = sqrt(rx * rx + ry * ry)
        if rl > 1e-9 then
            nx, ny = rx / rl, ry / rl
        else
            local a = round.rng:next() * 2 * math.pi
            nx, ny = math.cos(a), math.sin(a)
        end
    end
    local tx, ty = -ny, nx

    local mA, mB = A.m, B.m
    local invM = 1 / mA + 1 / mB
    local mRed = 1 / invM

    -- 1. Impulsion de rebond, seulement si les disques se rapprochent
    local vn = (B.vx - A.vx) * nx + (B.vy - A.vy) * ny
    local jb = 0
    if vn < 0 then
        local e = clamp(c.eBase + c.eAtk * (A.atk + B.atk) / 2, c.eMin, c.eMax)
        jb = -(1 + e) * vn / invM
    end

    -- 2. Impulsion des bords tournants, au début d'un contact seulement
    local sigma = math.abs(A.dir * A.w * A.r + B.dir * B.w * B.r)
    local js = 0
    local pairKey = i * 64 + j
    local cooling = (round.cooldown[pairKey] or -1) > round.step
    if jb > 0 and not cooling then
        js = c.kSmash * math.min(sigma, c.sigmaCap) * mRed * (0.5 + (A.atk + B.atk) / 2)
    end

    -- 3. Frottement tangentiel, opposé au glissement de la surface de A par rapport à B
    local slide = (A.vx - B.vx) * tx + (A.vy - B.vy) * ty + A.dir * A.w * A.r + B.dir * B.w * B.r
    local sgn = slide > 0 and 1 or (slide < 0 and -1 or 0)
    local function tangential(jn)
        return math.min(c.muC * jn, math.abs(slide) * mRed)
    end

    -- Bilan d'énergie calculé AVANT application : Js et Jt réduits si la rotation ne suffit pas
    local K0 = kinetic(mA, A.vx, A.vy) + kinetic(mB, B.vx, B.vy)
    local available = Collisions.available(A, c) + Collisions.available(B, c)
    local function outcome(jsUsed)
        local jn = jb + jsUsed
        local jt = tangential(jn)
        local avx = A.vx - (jn * nx + sgn * jt * tx) / mA
        local avy = A.vy - (jn * ny + sgn * jt * ty) / mA
        local bvx = B.vx + (jn * nx + sgn * jt * tx) / mB
        local bvy = B.vy + (jn * ny + sgn * jt * ty) / mB
        local dK = kinetic(mA, avx, avy) + kinetic(mB, bvx, bvy) - K0
        local work = c.kW * jt * math.abs(slide)
        local need = work + (dK > 0 and dK or 0)
        return need, jn, jt, avx, avy, bvx, bvy
    end

    local need, jn, jt, avx, avy, bvx, bvy = outcome(js)
    if need > available and js > 0 then
        local f = available / need
        need, jn, jt, avx, avy, bvx, bvy = outcome(js * f)
    end
    if need > available then
        -- Dernier recours : rebond seul (ne crée jamais d'énergie), sans frottement ni choc des bords
        jn, jt = jb, 0
        avx, avy = A.vx - jb * nx / mA, A.vy - jb * ny / mA
        bvx, bvy = B.vx + jb * nx / mB, B.vy + jb * ny / mB
        local dK = kinetic(mA, avx, avy) + kinetic(mB, bvx, bvy) - K0
        need = dK > 0 and dK or 0
    end

    A.vx, A.vy, B.vx, B.vy = avx, avy, bvx, bvy
    if js > 0 then
        round.cooldown[pairKey] = round.step + round.cooldownSteps
    end

    -- 4. Perte de rotation partagée selon l'attaque reçue et la défense
    if need > 0 then
        local shareA = clamp(0.5 + 0.5 * (B.atk - A.def), 0.15, 0.85)
        local shareB = clamp(0.5 + 0.5 * (A.atk - B.def), 0.15, 0.85)
        -- Rail turbo : une toupie lancée par le rail (ou qui en sort) frappe avec son élan et perd moins de rotation
        local win = round.turboSteps or 0
        if A.dashUntil and round.step <= A.dashUntil + win then shareA = shareA * 0.5 end
        if B.dashUntil and round.step <= B.dashUntil + win then shareB = shareB * 0.5 end
        local lossA = need * shareA / (shareA + shareB)
        local lossB = need - lossA
        -- Une toupie ne perd pas plus que sa réserve ; le reste passe à l'autre
        local availA, availB = Collisions.available(A, c), Collisions.available(B, c)
        if lossA > availA then lossB, lossA = lossB + (lossA - availA), availA end
        if lossB > availB then lossA, lossB = math.min(availA, lossA + (lossB - availB)), availB end
        Collisions.removeSpinEnergy(A, lossA)
        Collisions.removeSpinEnergy(B, lossB)
    end

    -- 5. Oscillation due au choc
    A.wob = clamp(A.wob + c.kImpWob * (jn / mA) * B.atk / (0.5 + A.stab + A.def / 2), 0, 1)
    B.wob = clamp(B.wob + c.kImpWob * (jn / mB) * A.atk / (0.5 + B.stab + B.def / 2), 0, 1)

    -- Fin du pas avec les nouvelles vitesses, puis séparation si un recouvrement subsiste
    local rest = (1 - t) * dt
    A.x, A.y = ax + A.vx * rest, ay + A.vy * rest
    B.x, B.y = bx + B.vx * rest, by + B.vy * rest

    local ox, oy = B.x - A.x, B.y - A.y
    local od = sqrt(ox * ox + oy * oy)
    if od < S then
        local sx, sy = nx, ny
        if od > 1e-9 then sx, sy = ox / od, oy / od end
        local push = S - od + 1e-5
        local wA, wB = (1 / mA) / invM, (1 / mB) / invM
        A.x, A.y = A.x - sx * push * wA, A.y - sy * push * wA
        B.x, B.y = B.x + sx * push * wB, B.y + sy * push * wB
    end

    if jn <= 0 then return nil end
    round.impact = { jn = jn, smash = js > 0 }
    return {
        t = 'hit', a = i, b = j,
        x = (ax + bx) / 2, y = (ay + by) / 2,
        k = clamp(math.floor(jn / mRed / 3 * 255 + 0.5), 0, 255),
    }
end

SpinArena.Collisions = Collisions
return Collisions
