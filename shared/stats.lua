-- Pièces → caractéristiques de combat (docs/ARCHITECTURE.md §14). Pur : utilisable par le serveur (autorité)
-- et par le client (aperçu seulement, jamais renvoyé au serveur).
SpinArena = SpinArena or {}

local Stats = {}

-- Bornes de jeu (identiques au moteur, docs/PHYSICS.md §4)
Stats.BOUNDS = {
    m = { 0.035, 0.065 }, r = { 0.040, 0.060 }, kI = { 0.45, 0.75 },
    atk = { 0, 1 }, def = { 0, 1 }, stab = { 0, 1 },
    tipFric = { 2.0, 7.0 }, mob = { 0.1, 1.8 }, trac = { 0.5, 3.0 }, damp = { 0.15, 0.8 },
    w0 = { 200, 300 }, v0 = { 0.3, 0.9 },
    burst = { 0, 1 }, dash = { 0, 1 },   -- 29/10 : verrou et rail turbo
}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Vérifie un assemblage { core = id, ring = id, frame = id, tip = id }. Renvoie le coût total, ou nil et la raison.
function Stats.validate(parts)
    local P = SpinArena.Parts
    if type(parts) ~= 'table' then return nil, 'parts' end
    local cost = 0
    for _, slot in ipairs(P.slots) do
        local id = parts[slot]
        local def = type(id) == 'string' and P.catalog[id]
        if not def then return nil, 'missing:' .. slot end
        if def.slot ~= slot then return nil, 'wrong_slot:' .. slot end
        cost = cost + def.cost
    end
    for key in pairs(parts) do
        local known = false
        for _, slot in ipairs(P.slots) do if slot == key then known = true end end
        if not known then return nil, 'unknown_slot:' .. tostring(key) end
    end
    if cost > P.budget then return nil, 'over_budget' end
    return cost
end

-- Assemblage en cours (glisser-déposer dans l'inventaire) : chaque pièce présente est connue, à sa place, et le
-- total reste dans le budget ; des emplacements peuvent manquer. Renvoie le coût, ou nil et la raison.
function Stats.validatePartial(parts)
    local P = SpinArena.Parts
    if type(parts) ~= 'table' then return nil, 'parts' end
    local cost, known = 0, {}
    for _, slot in ipairs(P.slots) do known[slot] = true end
    for key, id in pairs(parts) do
        if not known[key] then return nil, 'unknown_slot:' .. tostring(key) end
        local def = type(id) == 'string' and P.catalog[id]
        if not def then return nil, 'missing:' .. key end
        if def.slot ~= key then return nil, 'wrong_slot:' .. key end
        cost = cost + def.cost
    end
    if cost > P.budget then return nil, 'over_budget' end
    return cost
end

-- Les quatre emplacements sont remplis (seule une toupie complète peut combattre)
function Stats.isComplete(parts)
    if type(parts) ~= 'table' then return false end
    for _, slot in ipairs(SpinArena.Parts.slots) do
        if parts[slot] == nil then return false end
    end
    return true
end

-- Calcule les caractéristiques bornées. wear = usure (matchs joués). Renvoie stats, coût ; ou nil, raison.
function Stats.compute(parts, wear)
    local P = SpinArena.Parts
    local cost, err = Stats.validate(parts)
    if not cost then return nil, err end
    local s = {}
    for k, v in pairs(P.base) do s[k] = v end
    for _, slot in ipairs(P.slots) do
        for k, delta in pairs(P.catalog[parts[slot]].mods) do s[k] = s[k] + delta end
    end
    local over = math.max(0, math.min(wear or 0, P.wearMax) - P.wearFree)
    s.w0 = s.w0 * (1 - over * P.wearPenalty)
    for k, b in pairs(Stats.BOUNDS) do s[k] = clamp(s[k], b[1], b[2]) end
    -- Sens de rotation : une pièce marquée dir = -1 (anneau inversé) fait tourner la toupie à gauche
    s.dir = 1
    for _, slot in ipairs(P.slots) do
        if P.catalog[parts[slot]].dir == -1 then s.dir = -1 end
    end
    return s, cost
end

-- Silhouette 3D affichée (stream/spin_top_<nom>.ydr) : elle suit l'anneau monté, la pièce la plus visible, et non
-- l'assemblage de départ le plus proche. Purement visuel. Anneau standard ou inversé : volant lisse (endurance),
-- ou cadre ajouré (mobilité) sur une pointe d'adhérence.
Stats.RING_MODEL = { ring_smash = 'attack', ring_guard = 'defense', ring_round = 'balance' }
Stats.GRIP_TIPS = { tip_rubber = true, tip_flat = true }

function Stats.model(parts)
    if type(parts) ~= 'table' then return 'spin_top_balance' end
    local shape = Stats.RING_MODEL[parts.ring]
    if not shape then
        shape = Stats.GRIP_TIPS[parts.tip] and 'mobility' or 'endurance'
    end
    return 'spin_top_' .. shape
end

-- Famille affichée : la plus proche des assemblages de départ (purement indicatif)
function Stats.family(parts)
    local P = SpinArena.Parts
    local best, bestScore = 'balance', -1
    for key, kit in pairs(P.kits) do
        local score = 0
        for _, slot in ipairs(P.slots) do if kit.parts[slot] == parts[slot] then score = score + 1 end end
        if score > bestScore or (score == bestScore and key < best) then best, bestScore = key, score end
    end
    return best
end

SpinArena.Stats = Stats
return Stats
