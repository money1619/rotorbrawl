-- Lancement manuel (jauge de timing). Pur : le client s'en sert pour animer la jauge reçue du serveur,
-- seul le serveur calcule la qualité, à partir de SON horloge (aucune valeur du client n'est acceptée).
SpinArena = SpinArena or {}

local Launch = {}
local TWO_PI = 2 * math.pi

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Effets du type de lanceur (config/parts.lua, Parts.launchers) ; un identifiant inconnu vaut le lanceur de base
function Launch.mods(id)
    local L = SpinArena.Parts and SpinArena.Parts.launchers
    if not L then return {}, 'cord' end
    local def = L.catalog[id]
    if def then return def, id end
    return L.catalog[L.default] or {}, L.default
end

-- Réglages de jauge d'un lanceur : largeur de zone et fenêtre de tirage (copie, la configuration n'est jamais modifiée)
function Launch.cfgFor(cfg, mods)
    local out = {}
    for k, v in pairs(cfg) do out[k] = v end
    mods = mods or {}
    out.width = cfg.width * (mods.width or 1)
    out.pullMaxMs = (cfg.pullMaxMs or 450) + (mods.pullMaxMs or 0)
    return out
end

-- Effets lisibles (écran de boutique, jauge) : { { label, text, good } }
function Launch.describe(mods)
    local out = {}
    local function pct(v) return ('%s%d %%'):format(v >= 0 and '+' or '−', math.floor(math.abs(v) * 100 + 0.5)) end
    mods = mods or {}
    if mods.spin then out[#out + 1] = { label = 'Rotation de départ', text = pct(mods.spin), good = mods.spin > 0 } end
    if mods.atk then out[#out + 1] = { label = 'Attaque', text = pct(mods.atk), good = mods.atk > 0 } end
    if mods.speed then out[#out + 1] = { label = 'Vitesse de départ', text = pct(mods.speed), good = mods.speed > 0 } end
    if mods.width then out[#out + 1] = { label = 'Zone de la jauge', text = pct(mods.width - 1), good = mods.width > 1 } end
    if mods.pullMaxMs then out[#out + 1] = { label = 'Tirage tolérant', text = '+' .. mods.pullMaxMs .. ' ms', good = true } end
    if mods.tilt then out[#out + 1] = { label = 'Inclinaison', text = pct(mods.tilt - 1), good = mods.tilt > 1 } end
    if mods.dash then out[#out + 1] = { label = 'Accroche du rail', text = pct(mods.dash), good = true } end
    return out
end

-- Position de l'aiguille (0..1) à t ms après l'émission de la jauge
function Launch.position(gauge, tMs)
    return 0.5 + 0.5 * math.sin(TWO_PI * tMs / gauge.periodMs + gauge.phase)
end

-- Qualité 0..1 : 1 sur la cible, 0 à `width` ou plus de la cible
function Launch.quality(gauge, tMs)
    local d = math.abs(Launch.position(gauge, tMs) - gauge.target)
    return clamp(1 - d / gauge.width, 0, 1)
end

-- Tirage de la tirette : durée (ms) entre la prise et le relâchement, mesurée par le serveur entre les deux
-- réceptions (même latence aux deux bouts). Idéal entre pullMinMs et pullMaxMs ; trop bref, le tirage est mou
-- (proportionnel) ; trop long, la tirette retombe (0 après pullFadeMs de plus).
function Launch.pullQuality(ms, cfg)
    local lo, hi, fade = cfg.pullMinMs or 150, cfg.pullMaxMs or 450, cfg.pullFadeMs or 600
    if type(ms) ~= 'number' or ms ~= ms or ms < 0 then return 0 end
    if ms < lo then return ms / lo end
    if ms <= hi then return 1 end
    return clamp(1 - (ms - hi) / fade, 0, 1)
end

-- Qualité du lancer = prise (jauge) et tirage, pondérés par cfg.gripWeight (0,55 par défaut)
function Launch.combine(gripQ, pullQ, cfg)
    local w = cfg.gripWeight or 0.55
    return clamp(w * gripQ + (1 - w) * pullQ, 0, 1)
end

-- Libellé affiché au joueur (aucune valeur numérique renvoyée)
function Launch.grade(q)
    if q >= 0.85 then return 'perfect' elseif q >= 0.55 then return 'good' elseif q >= 0.2 then return 'fair' end
    return 'weak'
end

-- Copie des caractéristiques avec la vitesse de rotation (w0) et la vitesse de départ (v0) modulées par q :
-- facteur 1 + gain·(2q − 1), donc ±gain, puis bornage aux bornes du moteur. Aucune autre caractéristique,
-- sauf l'inclinaison du lanceur (tilt −1 vers le bord, 1 vers le centre) que le moteur lit au départ ; 0 = absente.
function Launch.apply(stats, q, cfg, tilt, mods)
    assert(type(q) == 'number' and q == q and q >= 0 and q <= 1, 'launch quality must be in [0, 1]')
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    if tilt == -1 or tilt == 1 then out.tilt = tilt end
    local B = SpinArena.Stats.BOUNDS
    local s = 2 * q - 1
    mods = mods or {}
    out.w0 = clamp(stats.w0 * (1 + (cfg.spinGain or 0) * s + (mods.spin or 0)), B.w0[1], B.w0[2])
    out.v0 = clamp(stats.v0 * (1 + (cfg.speedGain or 0) * s + (mods.speed or 0)), B.v0[1], B.v0[2])
    -- Lanceur à rail : accroche ajoutée à celle de l'embout ; lanceur de précision : inclinaison plus marquée
    if (mods.dash or 0) > 0 then out.dash = clamp((stats.dash or 0) + mods.dash, 0, 1) end
    if mods.atk then out.atk = clamp(stats.atk + mods.atk, 0, 1) end   -- départ mordant (Ressort)
    if mods.tilt and (out.tilt == -1 or out.tilt == 1) then out.tiltMul = mods.tilt end
    return out
end

-- Jauge tirée par le serveur pour une tentative d'armement
function Launch.newGauge(cfg, rand)
    rand = rand or math.random
    return {
        periodMs = math.floor(cfg.periodMinMs + (cfg.periodMaxMs - cfg.periodMinMs) * rand()),
        phase = TWO_PI * rand(),
        target = 0.25 + 0.5 * rand(),
        width = cfg.width,
    }
end

SpinArena.Launch = Launch
return Launch
