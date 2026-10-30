-- SPIN ARENA — Phases 1 & 2 : Rendu géométrique temporaire, interpolation et HUD multijoueur
-- Fichier : client/renderer.lua
-- Autorité : serveur uniquement. Aucun calcul physique d'autorité côté client.
-- Compatible Lua 5.4 hors jeu (fonctions pures d'interpolation/décodage testables) et runtime CfxLua FiveM.

SpinArena = SpinArena or {}

local Renderer = {}
SpinArena.Renderer = Renderer

local math_cos = math.cos
local math_sin = math.sin
local math_sqrt = math.sqrt
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_abs = math.abs
local math_pi = math.pi
local TWO_PI = 2.0 * math_pi

-- Constantes de lecture et d'affichage (ARCHITECTURE.md §9-10 & PHYSICS.md §15)
Renderer.BUFFER_DELAY_S            = 0.20   -- Tampon de lecture D = 0,2 s
Renderer.STARVATION_TIMEOUT_MS     = 5000   -- Nettoyage après 5 s sans données
Renderer.PREPARE_TIMEOUT_MS        = 60000  -- Préparation (lancement manuel, 30 s serveur) : nettoyage après 60 s sans nouvelle
Renderer.ROUND_END_HOLD_MS         = 3500   -- Maintien visuel de fin de manche (manche unique /spin_test)
Renderer.ROUND_INTERMISSION_HOLD_MS = 5500  -- Maintien inter-manches en match multi-manches (pause serveur 4 s)
Renderer.MATCH_END_HOLD_MS         = 5000   -- Maintien de la bannière finale de match (~5 s)
Renderer.VISUAL_W_CAP              = 45.0   -- Plafond visuel anti-stroboscopique (rad/s)
Renderer.EVENT_FLASH_MS            = 380    -- Durée d'affichage d'un flash d'impact (ms)
Renderer.EJECT_VISUAL_S            = 0.65   -- Durée de la sortie visuelle après éjection (s)

-- Statuts numériques des keyframes (ARCHITECTURE.md §9)
Renderer.STATUS = {
    SPINNING = 0,
    STOPPING = 1,
    STOPPED  = 2,
    EJECTED  = 3,
}

Renderer.STATUS_LABEL = {
    [0] = 'EN ROTATION',
    [1] = 'INSTABLE',
    [2] = 'ARRÊTÉE',
    [3] = 'ÉJECTÉE',
}

-- Palette de référence industrielle futuriste (ART_AND_UI.md §3.1)
local DEFAULT_TOP_COLORS = {
    [1] = { r = 0,   g = 229, b = 255 }, -- Cyan électrique (#00E5FF)
    [2] = { r = 255, g = 85,  b = 0   }, -- Orange impact (#FF5500)
}

local COLOR_GRAPHITE = { r = 26,  g = 30,  b = 36  }
local COLOR_TITANE   = { r = 140, g = 150, b = 164 }
local COLOR_DANGER   = { r = 239, g = 68,  b = 68  }
local COLOR_SUCCESS  = { r = 16,  g = 185, b = 129 }
local COLOR_GOLD     = { r = 245, g = 158, b = 11  }

-- État interne de la scène active (nil au repos -> 0.00 ms)
local activeScene = nil
local pendingCountdown = nil
local loopRunning = false

-- Plusieurs combats proches (tables voisines) : une scène par match. Les traitements historiques travaillent sur
-- `activeScene` / `pendingCountdown` ; withScene() les fait pointer sur la scène du match concerné le temps d'un
-- traitement. Hors traitement, getActiveScene() renvoie la scène principale (son propre match, sinon la plus proche).
Renderer.MAX_SCENES = 4          -- scènes rendues en entier ; au-delà (plus lointaines) : état seulement, sans toupies
Renderer.GHOST_MS = 5000         -- annonce « annulé » gardée pour les panneaux (contrat scenes())
local scenes, pendings, ghosts, queues = {}, {}, {}, {}
local selectedId, primaryId = nil, nil
local sceneListeners, lastBoardSignature = {}, nil

local function nowMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end
    return math_floor(os.clock() * 1000.0)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Normalise une couleur {r,g,b} ou {1,2,3}
local function normalizeColor(c, fallback)
    if type(c) ~= 'table' then return fallback end
    local r = tonumber(c.r or c[1]) or fallback.r
    local g = tonumber(c.g or c[2]) or fallback.g
    local b = tonumber(c.b or c[3]) or fallback.b
    return {
        r = clamp(math_floor(r), 0, 255),
        g = clamp(math_floor(g), 0, 255),
        b = clamp(math_floor(b), 0, 255),
    }
end

-- Normalise un tableau de score { a, b } ou { [1], [2] }
local function normalizeScore(s, fallback)
    if type(s) ~= 'table' then
        if fallback then return fallback end
        return nil
    end
    local a = tonumber(s[1] or s.a) or (fallback and fallback[1]) or 0
    local b = tonumber(s[2] or s.b) or (fallback and fallback[2]) or 0
    return { [1] = a, [2] = b, a = a, b = b }
end

-- Normalise les noms des joueurs { nom1, nom2 }
local function normalizeNames(names, tops, fallback)
    if type(names) ~= 'table' then
        return fallback
    end
    local n1 = names[1] or names.a or (fallback and fallback[1]) or (tops and tops[1] and tops[1].label) or 'Joueur 1'
    local n2 = names[2] or names.b or (fallback and fallback[2]) or (tops and tops[2] and tops[2].label) or 'Joueur 2'
    return { [1] = tostring(n1), [2] = tostring(n2) }
end

-- Identifiants serveur des deux participants (lanceurs affichés dans leur main) : entiers positifs, 0 = aucun joueur
local function normalizeSrcs(srcs, fallback)
    if type(srcs) ~= 'table' then return fallback or { 0, 0 } end
    local out = {}
    for i = 1, 2 do
        local v = tonumber(srcs[i])
        out[i] = (v and v >= 1 and v <= 65535 and v == math_floor(v)) and v or 0
    end
    return out
end

-- Décode une keyframe plate { step, x1mm, y1mm, w1_dec, wob1_255, st1, x2mm, y2mm, w2_dec, wob2_255, st2 }
-- vers une structure en unités SI (m, rad/s, [0,1]).
function Renderer.decodeKeyframe(raw)
    if type(raw) ~= 'table' then return nil end
    local step = tonumber(raw[1] or raw.step)
    if not step or step < 0 then return nil end

    if raw.tops and type(raw.tops) == 'table' then
        local t1 = raw.tops[1] or {}
        local t2 = raw.tops[2] or {}
        return {
            step = step,
            tops = {
                [1] = {
                    x   = tonumber(t1.x) or 0.0,
                    y   = tonumber(t1.y) or 0.0,
                    w   = math_max(0.0, tonumber(t1.w) or 0.0),
                    wob = clamp(tonumber(t1.wob) or 0.0, 0.0, 1.0),
                    st  = tonumber(t1.st) or 0,
                },
                [2] = {
                    x   = tonumber(t2.x) or 0.0,
                    y   = tonumber(t2.y) or 0.0,
                    w   = math_max(0.0, tonumber(t2.w) or 0.0),
                    wob = clamp(tonumber(t2.wob) or 0.0, 0.0, 1.0),
                    st  = tonumber(t2.st) or 0,
                },
            },
        }
    end

    local x1mm = tonumber(raw[2]) or 0
    local y1mm = tonumber(raw[3]) or 0
    local w1d  = tonumber(raw[4]) or 0
    local wb1  = tonumber(raw[5]) or 0
    local st1  = tonumber(raw[6]) or 0

    local x2mm = tonumber(raw[7]) or 0
    local y2mm = tonumber(raw[8]) or 0
    local w2d  = tonumber(raw[9]) or 0
    local wb2  = tonumber(raw[10]) or 0
    local st2  = tonumber(raw[11]) or 0

    return {
        step = step,
        tops = {
            [1] = {
                x   = x1mm * 0.001,
                y   = y1mm * 0.001,
                w   = math_max(0.0, w1d * 0.1),
                wob = clamp(wb1 / 255.0, 0.0, 1.0),
                st  = st1,
            },
            [2] = {
                x   = x2mm * 0.001,
                y   = y2mm * 0.001,
                w   = math_max(0.0, w2d * 0.1),
                wob = clamp(wb2 / 255.0, 0.0, 1.0),
                st  = st2,
            },
        },
    }
end

-- Hauteur locale z(x, y) de la cuvette parabolique (PHYSICS.md §7 : z = h * (r / R)^2)
function Renderer.bowlLocalZ(arena, x, y)
    local R = (arena and tonumber(arena.R)) or 0.60
    local h = (arena and tonumber(arena.h)) or 0.05
    if R <= 0.0001 then return 0.0 end
    local r2 = x * x + y * y
    local ratio2 = clamp(r2 / (R * R), 0.0, 1.35)
    return h * ratio2
end

-- Convertit une coordonnée locale d'arène (x, y en m) en coordonnée monde GTA (X, Y, Z)
-- selon ARCHITECTURE.md §9 : centre + rotation(cap) * (x, y) * échelle
function Renderer.localToWorld(arena, x, y, extraZ)
    local cx = (arena and tonumber(arena.x)) or 0.0
    local cy = (arena and tonumber(arena.y)) or 0.0
    local cz = (arena and tonumber(arena.z)) or 0.0
    local scale = (arena and tonumber(arena.scale)) or 1.0
    local headingDeg = (arena and tonumber(arena.heading)) or 0.0
    local rad = headingDeg * (math_pi / 180.0)
    local c = math_cos(rad)
    local s = math_sin(rad)

    local wx = cx + scale * (x * c - y * s)
    local wy = cy + scale * (x * s + y * c)
    local wz = cz + scale * (Renderer.bowlLocalZ(arena, x, y) + (tonumber(extraZ) or 0.0))
    return wx, wy, wz
end

-- Recherche binaire de la paire de keyframes encadrant targetStep et interpolation linéaire.
-- Si targetStep dépasse la dernière keyframe reçue, ou tombe dans un trou de tranche manquante (> maxGapSteps),
-- gèle sur la dernière keyframe contiguë sans lisser à travers une collision inconnue.
function Renderer.interpolateAtStep(frames, targetStep, receivedLast, maxGapSteps)
    local count = type(frames) == 'table' and #frames or 0
    if count == 0 then
        return nil, true
    end

    if targetStep <= frames[1].step then
        local f = frames[1]
        return {
            step = f.step,
            starving = false,
            tops = {
                [1] = { x = f.tops[1].x, y = f.tops[1].y, w = f.tops[1].w, wob = f.tops[1].wob, st = f.tops[1].st },
                [2] = { x = f.tops[2].x, y = f.tops[2].y, w = f.tops[2].w, wob = f.tops[2].wob, st = f.tops[2].st },
            },
        }, false
    end

    local lastFrame = frames[count]
    if targetStep >= lastFrame.step then
        local starving = not receivedLast
        return {
            step = lastFrame.step,
            starving = starving,
            tops = {
                [1] = {
                    x = lastFrame.tops[1].x,
                    y = lastFrame.tops[1].y,
                    w = lastFrame.tops[1].w,
                    wob = lastFrame.tops[1].wob,
                    st = lastFrame.tops[1].st,
                },
                [2] = {
                    x = lastFrame.tops[2].x,
                    y = lastFrame.tops[2].y,
                    w = lastFrame.tops[2].w,
                    wob = lastFrame.tops[2].wob,
                    st = lastFrame.tops[2].st,
                },
            },
        }, starving
    end

    -- Recherche binaire de l'indice lo tel que frames[lo].step <= targetStep < frames[lo+1].step
    local lo, hi = 1, count
    while lo + 1 < hi do
        local mid = math_floor((lo + hi) * 0.5)
        if frames[mid].step <= targetStep then
            lo = mid
        else
            hi = mid
        end
    end

    local a = frames[lo]
    local b = frames[hi]
    local span = b.step - a.step

    -- Détection de tranche manquante (D05) : si l'écart entre deux keyframes consécutives dépasse maxGapSteps,
    -- on ne lisse pas à travers le trou (qui peut contenir des rebonds) et on gèle sur la trame a.
    local gapLimit = tonumber(maxGapSteps) or 24
    if span > gapLimit and targetStep > a.step then
        return {
            step = a.step,
            starving = true,
            tops = {
                [1] = { x = a.tops[1].x, y = a.tops[1].y, w = a.tops[1].w, wob = a.tops[1].wob, st = a.tops[1].st },
                [2] = { x = a.tops[2].x, y = a.tops[2].y, w = a.tops[2].w, wob = a.tops[2].wob, st = a.tops[2].st },
            },
        }, true
    end

    local alpha = 0.0
    if span > 0 then
        alpha = clamp((targetStep - a.step) / span, 0.0, 1.0)
    end

    local out = {
        step = targetStep,
        starving = false,
        tops = {},
    }

    for i = 1, 2 do
        local ta = a.tops[i]
        local tb = b.tops[i]
        -- Tant que targetStep < b.step (alpha < 1.0), le pas autoritaire b.step n'est pas atteint :
        -- on conserve strictement le statut ta.st pour ne jamais afficher STOPPED/EJECTED en avance.
        out.tops[i] = {
            x   = ta.x + (tb.x - ta.x) * alpha,
            y   = ta.y + (tb.y - ta.y) * alpha,
            w   = math_max(0.0, ta.w + (tb.w - ta.w) * alpha),
            wob = clamp(ta.wob + (tb.wob - ta.wob) * alpha, 0.0, 1.0),
            st  = (alpha >= 1.0) and tb.st or ta.st,
        }
    end

    return out, false
end

-- Texte 2D compact à l'écran (uniquement pendant le match actif)
local function drawOverlayText(x, y, scale, text, r, g, b, a, center)
    if type(SetTextFont) ~= 'function' then return end
    SetTextFont(4)
    SetTextProportional(true)
    SetTextScale(scale, scale)
    SetTextColour(r or 216, g or 222, b or 233, a or 235)
    SetTextDropshadow(1, 0, 0, 0, 200)
    SetTextOutline()
    if center then
        SetTextCentre(true)
    end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text))
    EndTextCommandDisplayText(x, y)
end

-- Dessine l'arène temporaire (anneau extérieur, cuvette, centre et secteurs de poches) avec DrawMarker
local function drawTemporaryArena(scene)
    if type(DrawMarker) ~= 'function' or not scene.arena then return end
    -- La cuvette réelle est en place : pas de seconde arène dessinée au sol
    if scene.arenaProp and scene.arenaProp ~= 0 then return end
    local arena = scene.arena
    local scale = arena.scale or 1.0
    local diam = 2.0 * arena.R * scale

    -- Anneau extérieur de l'arène (cylindre plat gris graphite / titane)
    DrawMarker(
        1,
        arena.x, arena.y, arena.z - 0.01,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        diam, diam, 0.06 * scale,
        COLOR_TITANE.r, COLOR_TITANE.g, COLOR_TITANE.b, 150,
        false, false, 2, false, nil, nil, false
    )

    -- Zone centrale de la cuvette
    local innerDiam = diam * 0.45
    DrawMarker(
        1,
        arena.x, arena.y, arena.z - 0.005,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        innerDiam, innerDiam, 0.02 * scale,
        COLOR_GRAPHITE.r, COLOR_GRAPHITE.g, COLOR_GRAPHITE.b, 130,
        false, false, 2, false, nil, nil, false
    )

    -- Repères des poches d'éjection sur le bord de l'arène
    local pockets = arena.pockets
    if type(pockets) == 'table' then
        for i = 1, #pockets do
            local p = pockets[i]
            local angDeg = tonumber(p.angle) or 0.0
            local widthDeg = tonumber(p.width) or 24.0
            local angRad = angDeg * (math_pi / 180.0)
            local px = arena.R * math_cos(angRad)
            local py = arena.R * math_sin(angRad)
            local wx, wy, wz = Renderer.localToWorld(arena, px, py, 0.01)
            local arcLen = math_max(0.08, arena.R * (widthDeg * math_pi / 180.0) * scale)
            DrawMarker(
                1,
                wx, wy, wz,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                arcLen, arcLen, 0.07 * scale,
                COLOR_DANGER.r, COLOR_DANGER.g, COLOR_DANGER.b, 175,
                false, false, 2, false, nil, nil, false
            )
        end
    end
end

-- Dessine une toupie avec des formes géométriques temporaires (DrawMarker) :
-- disque de couronne, noyau lumineux central, indicateur d'angle de rotation et inclinaison d'oscillation (wob).
local function drawTemporaryTop(scene, index, topState, now)
    if type(DrawMarker) ~= 'function' or not scene.arena then return end
    local arena = scene.arena
    local scale = arena.scale or 1.0
    local meta = scene.tops[index] or {}
    local r = (tonumber(meta.r) or 0.05) * scale
    local color = meta.color or DEFAULT_TOP_COLORS[index] or DEFAULT_TOP_COLORS[1]

    local drawX = topState.x
    local drawY = topState.y
    local extraZ = 0.0
    local alpha = 230

    -- Trajectoire visuelle de sortie après éjection (PHYSICS.md §9)
    if topState.st == Renderer.STATUS.EJECTED then
        local ej = scene.ejectedState[index]
        if not ej then
            local norm = math_sqrt(drawX * drawX + drawY * drawY)
            local ux, uy = 1.0, 0.0
            if norm > 0.001 then
                ux, uy = drawX / norm, drawY / norm
            end
            ej = {
                startMs = now,
                x0 = drawX,
                y0 = drawY,
                vx = ux * 0.85,
                vy = uy * 0.85,
            }
            scene.ejectedState[index] = ej
        end
        local dtEj = math_max(0.0, (now - ej.startMs) * 0.001)
        if dtEj > Renderer.EJECT_VISUAL_S then
            return
        end
        drawX = ej.x0 + ej.vx * dtEj
        drawY = ej.y0 + ej.vy * dtEj
        extraZ = 0.04 * dtEj - 0.35 * dtEj * dtEj
        alpha = math_floor(230 * (1.0 - dtEj / Renderer.EJECT_VISUAL_S))
    else
        scene.ejectedState[index] = nil
    end

    -- Toupie réelle affichée : l'état d'éjection ci-dessus sert à son vol, rien n'est dessiné en double
    if scene.topProps and scene.topProps[index] then return end
    -- Repli géométrique (modèle de toupie absent) : posé sur le fond de la cuvette quand elle est là
    local bowlOffset = (scene.arenaProp and scene.arenaProp ~= 0) and ((tonumber(arena.floorHeight) or Renderer.BOWL_FLOOR_Z) * scale) or 0.0
    local wx, wy, wz = Renderer.localToWorld(arena, drawX, drawY, extraZ + bowlOffset)
    local diam = math_max(0.08, 2.0 * r)
    local ang = scene.visualAngles[index] or 0.0

    -- Inclinaison d'oscillation (précession visuelle basée sur wob)
    local tiltDeg = (topState.wob or 0.0) * 18.0
    local pitch = tiltDeg * math_cos(ang)
    local roll  = tiltDeg * math_sin(ang)

    -- Corps principal (cylindre métallique)
    DrawMarker(
        1,
        wx, wy, wz,
        0.0, 0.0, 0.0,
        pitch, roll, 0.0,
        diam, diam, 0.035 * scale,
        color.r, color.g, color.b, alpha,
        false, false, 2, false, nil, nil, false
    )

    -- Noyau gyroscopique central (sphère lumineuse ; vire à l'orange/rouge si wob élevé ou arrêt)
    local coreColor = color
    if topState.st == Renderer.STATUS.STOPPED or topState.st == Renderer.STATUS.EJECTED then
        coreColor = COLOR_DANGER
    elseif (topState.wob or 0.0) > 0.45 or topState.st == Renderer.STATUS.STOPPING then
        coreColor = DEFAULT_TOP_COLORS[2]
    end

    DrawMarker(
        28,
        wx, wy, wz + 0.022 * scale,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        diam * 0.32, diam * 0.32, diam * 0.32,
        coreColor.r, coreColor.g, coreColor.b, alpha,
        false, false, 2, false, nil, nil, false
    )

    -- Repère d'angle sur la couronne pour rendre la vitesse de rotation visible
    local tipDist = r * 0.72
    local rx = drawX + (tipDist / scale) * math_cos(ang)
    local ry = drawY + (tipDist / scale) * math_sin(ang)
    local rwx, rwy, rwz = Renderer.localToWorld(arena, rx, ry, extraZ + 0.024 + bowlOffset)
    DrawMarker(
        28,
        rwx, rwy, rwz,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        diam * 0.16, diam * 0.16, diam * 0.16,
        240, 245, 255, alpha,
        false, false, 2, false, nil, nil, false
    )
end

-- Dessine les flashs temporaires d'impact / rebond (événements hit, wall, ring_out)
-- et déclenche les particules/sons Phase 3 via SpinArena.Effects
local function drawTemporaryEvents(scene, currentStep, now)
    if not scene.arena then return end
    local events = scene.events
    local scale = scene.arena.scale or 1.0
    local bowlOffset = (scene.arenaProp and scene.arenaProp ~= 0) and ((tonumber(scene.arena.floorHeight) or 0.750) * scale) or 0.0
    local fx = SpinArena and SpinArena.Effects

    for i = 1, #events do
        local ev = events[i]
        if not ev.triggeredAtMs and ev.s <= currentStep then
            ev.triggeredAtMs = now
            local spectacle = SpinArena and SpinArena.Spectacle
            if ev.t == 'ring_out' and spectacle then spectacle.onRingOut(scene, ev, now) end
            if fx and type(fx.onImpact) == 'function' then
                local ewx, ewy, ewz = Renderer.localToWorld(scene.arena, (ev.x or 0) * 0.001, (ev.y or 0) * 0.001, 0.025)
                fx.onImpact(ev, ewx, ewy, ewz + bowlOffset, scale)
            end
        end
        if ev.triggeredAtMs and type(DrawMarker) == 'function' then
            local age = now - ev.triggeredAtMs
            if age >= 0 and age <= Renderer.EVENT_FLASH_MS then
                local progress = age / Renderer.EVENT_FLASH_MS
                local intensity = clamp((tonumber(ev.k) or 128) / 255.0, 0.25, 1.0)
                local radius = (0.04 + 0.14 * progress) * (0.6 + 0.6 * intensity) * scale
                local alpha = math_floor((1.0 - progress) * 220 * intensity)
                local wx, wy, wz = Renderer.localToWorld(scene.arena, (ev.x or 0) * 0.001, (ev.y or 0) * 0.001, 0.025 + bowlOffset)
                local spectacle = SpinArena and SpinArena.Spectacle
                if spectacle then spectacle.impactLight(ev, wx, wy, wz, progress, intensity) end   -- éclaire la cuvette
                local col = (ev.t == 'ring_out') and COLOR_DANGER or DEFAULT_TOP_COLORS[2]
                DrawMarker(
                    28,
                    wx, wy, wz,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    radius, radius, radius,
                    col.r, col.g, col.b, alpha,
                    false, false, 2, false, nil, nil, false
                )
            end
        end
    end
end

-- Gestion des props locaux non-réseau (Phase 3 : CreateObject(..., false, false, false))
Renderer.BOWL_FLOOR_Z = 0.750 -- Hauteur du fond de cuvette de spin_arena_bowl au-dessus du sol (build_bowl.py)

local function isTruthy(v)
    return v == true or v == 1
end

local function resolveModelHash(modelName)
    if type(modelName) == 'number' then return modelName end
    if type(modelName) ~= 'string' or modelName == '' then return nil end
    if type(joaat) == 'function' then return joaat(modelName) end
    if type(GetHashKey) == 'function' then return GetHashKey(modelName) end
    return nil
end

local function safeDeleteObject(ent)
    if not ent or ent == 0 then return end
    if SpinArena and SpinArena.TopModel then SpinArena.TopModel.dropChildren(ent) end   -- pièces attachées d'une toupie assemblée
    if type(DoesEntityExist) == 'function' and not isTruthy(DoesEntityExist(ent)) then
        return
    end
    if type(DeleteEntity) == 'function' then
        pcall(DeleteEntity, ent)
    elseif type(DeleteObject) == 'function' then
        pcall(DeleteObject, ent)
    end
end

local function spawnLocalProp(modelName, x, y, z, heading)
    if type(CreateObject) ~= 'function' then return nil, true end
    local hash = resolveModelHash(modelName)
    if not hash or hash == 0 then return nil, true end
    if type(IsModelInCdimage) == 'function' and not isTruthy(IsModelInCdimage(hash)) then
        return nil, true
    end
    if type(RequestModel) == 'function' then
        pcall(RequestModel, hash)
    end
    if type(HasModelLoaded) == 'function' and not isTruthy(HasModelLoaded(hash)) then
        return nil, false
    end

    local ok, obj = pcall(CreateObject, hash, x, y, z, false, false, false)
    if type(SetModelAsNoLongerNeeded) == 'function' then
        pcall(SetModelAsNoLongerNeeded, hash)
    end
    if not ok or not obj or obj == 0 then
        return nil, false
    end

    if type(SetEntityCoordsNoOffset) == 'function' then
        pcall(SetEntityCoordsNoOffset, obj, x, y, z, false, false, false)
    end
    if heading and type(SetEntityHeading) == 'function' then
        pcall(SetEntityHeading, obj, heading)
    end
    if type(FreezeEntityPosition) == 'function' then
        pcall(FreezeEntityPosition, obj, true)
    end
    if type(SetEntityCollision) == 'function' then
        pcall(SetEntityCollision, obj, false, false)
    end
    if type(SetEntityInvincible) == 'function' then
        pcall(SetEntityInvincible, obj, true)
    end
    return obj, true
end

-- Décor permanent des stations fixes : une cuvette locale figée par station, présente hors combat. Recréée seulement
-- si la liste des stations change (signature) ; le combat qui se joue sur une station réutilise sa cuvette.
Renderer.stationProps = Renderer.stationProps or {}   -- [nom] = { ent, x, y, z }
local stationSignature, stationGeneration = nil, 0

local function clearStationProps()
    stationGeneration = stationGeneration + 1
    for name, sp in pairs(Renderer.stationProps) do
        local scene = nil
        for _, sc in pairs(scenes) do
            if sc.arenaPropBorrowed and sc.arenaProp == sp.ent then scene = sc end
        end
        if activeScene and activeScene.arenaPropBorrowed and activeScene.arenaProp == sp.ent then scene = activeScene end
        if scene then
            -- Cuvette empruntée par le combat en cours : elle reste en place et le combat la supprimera à sa fin
            scene.arenaPropBorrowed = false
        else
            safeDeleteObject(sp.ent)
        end
        Renderer.stationProps[name] = nil
    end
    stationSignature = nil
end
Renderer.clearStationProps = clearStationProps
if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(name)
        if type(GetCurrentResourceName) == 'function' and name == GetCurrentResourceName() then clearStationProps() end
    end)
end

function Renderer.syncStationProps(stations, model)
    stations = type(stations) == 'table' and stations or {}
    local keys = {}
    for _, st in ipairs(stations) do
        if type(st) == 'table' and type(st.name) == 'string' and tonumber(st.x) and tonumber(st.y) and tonumber(st.z) then
            local stModel = (type(st.model) == 'string' and st.model ~= '' and st.model)
                or (type(st.arena) == 'table' and type(st.arena.model) == 'string' and st.arena.model ~= '' and st.arena.model)
                or model or 'spin_arena_bowl'
            keys[#keys + 1] = table.concat({ st.name, tostring(st.x), tostring(st.y), tostring(st.z), tostring(st.heading), stModel }, ':')
        end
    end
    local signature = table.concat(keys, '|')
    if signature == stationSignature then return end
    clearStationProps()
    stationSignature = signature
    local generation = stationGeneration
    for _, st in ipairs(stations) do
        if type(st) == 'table' and type(st.name) == 'string' and tonumber(st.x) and tonumber(st.y) and tonumber(st.z) then
            local name, x, y, z, heading = st.name, tonumber(st.x), tonumber(st.y), tonumber(st.z), tonumber(st.heading) or 0.0
            local stModel = (type(st.model) == 'string' and st.model ~= '' and st.model)
                or (type(st.arena) == 'table' and type(st.arena.model) == 'string' and st.arena.model ~= '' and st.arena.model)
                or model or 'spin_arena_bowl'
            local function attempt(tries)
                if generation ~= stationGeneration then return end
                local obj, done = spawnLocalProp(stModel, x, y, z, heading)
                if generation ~= stationGeneration then safeDeleteObject(obj) return end
                if obj then
                    -- Cuvette de station : solide (collision embarquée dans spin_arena_bowl*.ydr) ; les cuvettes des
                    -- combats improvisés restent sans collision car elles apparaissent sous les joueurs
                    if type(SetEntityCollision) == 'function' then pcall(SetEntityCollision, obj, true, true) end
                    Renderer.stationProps[name] = { ent = obj, x = x, y = y, z = z, model = stModel }
                elseif not done and tries < 50 and type(SetTimeout) == 'function' then
                    SetTimeout(100, function() attempt(tries + 1) end) -- modèle en cours de chargement
                end
            end
            attempt(0)
        end
    end
end

-- Cuvette de station au centre de l'arène du combat (à 0,5 m près), réutilisable par la scène si même modèle
local function stationPropAt(arena)
    local wantedModel = (arena and type(arena.model) == 'string' and arena.model ~= '' and arena.model) or 'spin_arena_bowl'
    for _, sp in pairs(Renderer.stationProps) do
        if math.abs(sp.x - arena.x) <= 0.5 and math.abs(sp.y - arena.y) <= 0.5 and math.abs(sp.z - arena.z) <= 2.0
            and (not sp.model or sp.model == wantedModel) then
            return sp.ent
        end
    end
end

local function cleanupSceneProps(scene)
    if not scene then return end
    local rivals = SpinArena and SpinArena.LauncherRivals
    if rivals and type(rivals.release) == 'function' then pcall(rivals.release, scene) end
    if scene.arenaProp then
        if not scene.arenaPropBorrowed then safeDeleteObject(scene.arenaProp) end
        scene.arenaProp = nil
        scene.arenaPropBorrowed = nil
    end
    if type(scene.topProps) == 'table' then
        for i = 1, 2 do
            if scene.topProps[i] then
                safeDeleteObject(scene.topProps[i])
                scene.topProps[i] = nil
            end
        end
    end
end

local function updateSceneProps(scene, interp, now)
    if type(CreateObject) ~= 'function' or not scene or not scene.arena then
        return
    end
    local arena = scene.arena
    local scale = arena.scale or 1.0

    if not scene.arenaProp and not scene.arenaPropTried then
        local borrowed = stationPropAt(arena)
        if borrowed then
            scene.arenaProp, scene.arenaPropBorrowed, scene.arenaPropTried = borrowed, true, true
        end
    end
    if not scene.arenaProp and not scene.arenaPropTried then
        local arenaModel = arena.model or 'spin_arena_bowl'
        local obj, done = spawnLocalProp(arenaModel, arena.x, arena.y, arena.z, arena.heading or 0.0)
        scene.arenaProp = obj
        if done then scene.arenaPropTried = true end
    end

    scene.topProps = scene.topProps or {}
    scene.topPropsTried = scene.topPropsTried or {}
    local bowlOffset = (scene.arenaProp and scene.arenaProp ~= 0) and ((tonumber(arena.floorHeight) or Renderer.BOWL_FLOOR_Z) * scale) or 0.0

    for i = 1, 2 do
        local topState = interp and interp.tops and interp.tops[i]
        if topState then
            local meta = scene.tops[i] or {}
            local drawX = topState.x
            local drawY = topState.y
            local extraZ = 0.0
            local ejectedDone = false
            local spectacle = SpinArena and SpinArena.Spectacle
            -- Éjectée avec la table affichée : vole hors de la table et reste couchée au sol (client/spectacle.lua)
            local ejectPose = nil
            if topState.st == Renderer.STATUS.EJECTED and spectacle then
                local ex, ey, ez, ep, er, eyaw = spectacle.ejectPose(scene, i, topState, now)
                if ex then ejectPose = { ex, ey, ez, ep, er, eyaw } end
            elseif scene.ejectFlight then
                scene.ejectFlight[i] = nil
            end

            if ejectPose then
                -- pose complète calculée plus bas
            elseif topState.st == Renderer.STATUS.EJECTED then
                local ej = scene.ejectedState[i]
                if ej then
                    local dtEj = math_max(0.0, (now - ej.startMs) * 0.001)
                    if dtEj > Renderer.EJECT_VISUAL_S then
                        ejectedDone = true
                    else
                        drawX = ej.x0 + ej.vx * dtEj
                        drawY = ej.y0 + ej.vy * dtEj
                        extraZ = 0.04 * dtEj - 0.35 * dtEj * dtEj
                    end
                end
            end

            -- Avant le GO (préparation, compte à rebours), la toupie est dans la main du lanceur : rien sur la table.
            -- Elle n'apparaît qu'au départ (29/10 : « les toupies sont déjà sur la table avant d'être lancées »).
            local preGo = scene.state == 'preparing' or scene.state == 'countdown'
            if ejectedDone or preGo then
                if scene.topProps[i] then
                    safeDeleteObject(scene.topProps[i])
                    scene.topProps[i] = nil
                end
            else
                local wx, wy, wz = Renderer.localToWorld(arena, drawX, drawY, extraZ)
                local propZ = wz + bowlOffset
                if ejectPose then wx, wy, propZ = ejectPose[1], ejectPose[2], ejectPose[3] end
                if not scene.topProps[i] and not scene.topPropsTried[i] then
                    local topModel = meta.model or ('spin_top_' .. tostring(meta.family or 'balance'))
                    local TM = SpinArena and SpinArena.TopModel
                    local obj, done
                    if TM then
                        obj, done = TM.spawn({ model = topModel, parts = meta.parts },
                            function(m) return spawnLocalProp(m, wx, wy, propZ, 0.0) end)
                    else
                        obj, done = spawnLocalProp(topModel, wx, wy, propZ, 0.0)
                    end
                    scene.topProps[i] = obj
                    if done then scene.topPropsTried[i] = true end
                end
                local prop = scene.topProps[i]
                if prop and prop ~= 0 then
                    -- Pendant l'envol de la toupie tenue en main (Launcher.flying), celle de la cuvette reste masquée :
                    -- sinon on verrait deux toupies. Seulement chez le lanceur, pour sa propre toupie.
                    local launcher = SpinArena and SpinArena.Launcher
                    local hide = launcher ~= nil and launcher.flying == true and scene.role == 'participant'
                        and i == (tonumber(scene.side) or 1)
                    -- Idem pour la toupie qui vole du lanceur d'un autre participant (client/launcher_rivals.lua)
                    local rivals = SpinArena and SpinArena.LauncherRivals
                    if not hide and rivals and type(rivals.isFlying) == 'function' then hide = rivals.isFlying(scene, i) end
                    scene.topHidden = scene.topHidden or {}
                    if (scene.topHidden[i] or false) ~= hide and type(SetEntityVisible) == 'function' then
                        pcall(SetEntityVisible, prop, not hide, false)
                        if SpinArena and SpinArena.TopModel then SpinArena.TopModel.setVisible(prop, not hide) end
                        scene.topHidden[i] = hide
                    end
                    local ang = scene.visualAngles[i] or 0.0
                    local tiltDeg = (topState.wob or 0.0) * 18.0
                    local pitch = tiltDeg * math_cos(ang)
                    local roll  = tiltDeg * math_sin(ang)
                    local yawDeg = (ang * 180.0 / math_pi) % 360.0
                    if ejectPose then
                        pitch, roll, yawDeg = ejectPose[4], ejectPose[5], ejectPose[6]
                    elseif spectacle then
                        -- Arrêtée : bascule sur le côté ; en mouvement : penche vers l'intérieur des virages
                        local fp, fr = spectacle.fallTilt(scene, i, topState, now, tiltDeg)
                        if fp then
                            pitch, roll = fp, fr
                        elseif topState.st ~= Renderer.STATUS.STOPPED and not scene.starving then
                            local lp, lr = spectacle.leanTilt(scene, i, drawX, drawY, scene.frameDt)
                            pitch, roll = pitch + lp, roll + lr
                        end
                    end
                    if type(SetEntityCoordsNoOffset) == 'function' then
                        pcall(SetEntityCoordsNoOffset, prop, wx, wy, propZ, false, false, false)
                    end
                    if type(SetEntityRotation) == 'function' then
                        pcall(SetEntityRotation, prop, pitch, roll, yawDeg, 2, true)
                    end
                end
            end
        end
    end
end

function Renderer.getSpawnedProps()
    local activeScene = selectedId and activeScene or (primaryId and scenes[primaryId]) or nil
    if not activeScene then
        return { arena = nil, bowl = nil, tops = {} }
    end
    return {
        arena = activeScene.arenaProp,
        bowl  = activeScene.arenaProp,
        tops  = {
            [1] = activeScene.topProps and activeScene.topProps[1] or nil,
            [2] = activeScene.topProps and activeScene.topProps[2] or nil,
        },
    }
end

local function winnerDisplayName(scene, winnerSide)
    if not winnerSide then return nil end
    if scene.names and scene.names[winnerSide] then
        return scene.names[winnerSide]
    end
    if scene.tops and scene.tops[winnerSide] and scene.tops[winnerSide].label then
        return scene.tops[winnerSide].label
    end
    return 'TOUPIE #' .. tostring(winnerSide)
end

-- Dessine le bandeau télémétrique et de score (lignes bien séparées : 0.050, 0.080, 0.120, 0.152)
local function drawTemporaryTelemetry(scene, interp, now)
    local roundNum = scene.round or 1
    local bestOf = scene.bestOf or 1

    -- Ligne supérieure (y = 0.050) : score du match, noms des joueurs et rôle (participant / spectateur)
    if scene.score or scene.names or scene.role == 'spectator' then
        local sA = (scene.score and (scene.score[1] or scene.score.a)) or 0
        local sB = (scene.score and (scene.score[2] or scene.score.b)) or 0
        local nA = (scene.names and scene.names[1]) or (scene.tops[1] and scene.tops[1].label) or 'Joueur 1'
        local nB = (scene.names and scene.names[2]) or (scene.tops[2] and scene.tops[2].label) or 'Joueur 2'
        local rolePrefix = ''
        if scene.role == 'spectator' then
            rolePrefix = '[SPECTATEUR] '
        elseif scene.side == 1 or scene.side == 2 then
            rolePrefix = string.format('[CÔTÉ %d] ', scene.side)
        end
        drawOverlayText(
            0.5, 0.050, 0.37,
            string.format('%s%s  %d - %d  %s  (Manche %d / BO%d)', rolePrefix, nA, sA, sB, nB, roundNum, bestOf),
            216, 222, 233, 240, true
        )
    end

    -- Ligne principale d'état (y = 0.080) : aucun chevauchement avec la télémétrie toupie #1 (y = 0.120)
    if scene.state == 'match_ended' and scene.matchOutcome then
        local mo = scene.matchOutcome
        local sA = (mo.score and (mo.score[1] or mo.score.a)) or (scene.score and scene.score[1]) or 0
        local sB = (mo.score and (mo.score[2] or mo.score.b)) or (scene.score and scene.score[2]) or 0
        local reasonStr = tostring(mo.reason or 'rounds')
        if mo.winner then
            local wName = winnerDisplayName(scene, mo.winner)
            drawOverlayText(
                0.5, 0.080, 0.50,
                string.format('SPIN ARENA — VICTOIRE FINALE : %s (%d - %d) [%s]', tostring(wName), sA, sB, reasonStr),
                COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 250, true
            )
        elseif reasonStr == 'no_contest' then
            drawOverlayText(
                0.5, 0.080, 0.48,
                string.format('SPIN ARENA — MATCH SANS RÉSULTAT (%s)', tostring((mo.detail and mo.detail.why) or reasonStr)),
                COLOR_DANGER.r, COLOR_DANGER.g, COLOR_DANGER.b, 245, true
            )
        else
            drawOverlayText(
                0.5, 0.080, 0.48,
                string.format('SPIN ARENA — ÉGALITÉ FINALE (%d - %d) [%s]', sA, sB, reasonStr),
                COLOR_SUCCESS.r, COLOR_SUCCESS.g, COLOR_SUCCESS.b, 245, true
            )
        end
    elseif scene.state == 'countdown' then
        if scene.t0 ~= nil then
            local rem = math_max(0.0, (scene.t0 - now) * 0.001)
            drawOverlayText(
                0.5, 0.080, 0.46,
                string.format('SPIN ARENA — MANCHE %d — LANCEMENT DANS %.1f s', roundNum, rem),
                0, 229, 255, 245, true
            )
        else
            drawOverlayText(
                0.5, 0.080, 0.46,
                string.format('SPIN ARENA — MANCHE %d — PRÉPARATION...', roundNum),
                0, 229, 255, 245, true
            )
        end
    elseif scene.state == 'ended' and scene.outcome then
        local out = scene.outcome
        local winTxt = out.winner and string.format('VAINQUEUR : %s', tostring(winnerDisplayName(scene, out.winner))) or 'ÉGALITÉ'
        drawOverlayText(
            0.5, 0.080, 0.48,
            string.format('SPIN ARENA — FIN MANCHE %d — %s (%s)', roundNum, winTxt, tostring(out.reason or 'time')),
            COLOR_SUCCESS.r, COLOR_SUCCESS.g, COLOR_SUCCESS.b, 245, true
        )
    elseif interp then
        local tElapsed = (interp.step or 0) * scene.dt
        local syncWarn = interp.starving and ' [SYNCHRONISATION...]' or ''
        drawOverlayText(
            0.5, 0.080, 0.40,
            string.format('SPIN ARENA — MANCHE %d — %.1f s%s', roundNum, tElapsed, syncWarn),
            216, 222, 233, 235, true
        )
    end

    -- Lignes télémétriques par toupie (y = 0.120 et y = 0.152)
    if interp and interp.tops then
        for i = 1, 2 do
            local ts = interp.tops[i]
            local meta = scene.tops[i] or {}
            local col = meta.color or DEFAULT_TOP_COLORS[i]
            local stLabel = Renderer.STATUS_LABEL[ts.st] or 'EN ROTATION'
            local yPos = 0.120 + (i - 1) * 0.032
            local pName = (scene.names and scene.names[i]) and (scene.names[i] .. ' (' .. tostring(meta.label or ('#' .. i)) .. ')') or tostring(meta.label or ('Toupie #' .. i))
            drawOverlayText(
                0.5, yPos, 0.34,
                string.format(
                    '%s : w = %5.1f rad/s | wob = %3.0f%% | %s',
                    pName,
                    ts.w or 0.0,
                    (ts.wob or 0.0) * 100.0,
                    stLabel
                ),
                col.r, col.g, col.b, 235, true
            )
        end
    end
end

-- Nettoyage complet et immédiat de la scène active (ARCHITECTURE.md §10 & §12)
local function cleanupOne(reason)
    pendingCountdown = nil
    -- Effets et lanceur sont globaux au joueur : on ne les coupe que pour SON match, ou s'il ne reste aucune autre scène
    local others = false
    for id in pairs(scenes) do if id ~= selectedId then others = true end end
    if not others or (activeScene and activeScene.role == 'participant') then
        local fx = SpinArena and SpinArena.Effects
        if fx and type(fx.cleanup) == 'function' then
            fx.cleanup()
        end
        local launcher = SpinArena and SpinArena.Launcher
        if launcher and type(launcher.cleanup) == 'function' then
            launcher.cleanup()
        end
    end
    if not activeScene then
        return false
    end
    cleanupSceneProps(activeScene)
    activeScene.cleanedReason = reason or 'cleanup'
    activeScene = nil
    return true
end

function Renderer.getActiveScene()
    if selectedId then return activeScene end
    return primaryId and scenes[primaryId] or nil
end

function Renderer.getScene(matchId)
    if selectedId == matchId then return activeScene end
    return matchId and scenes[matchId] or nil
end

local function notifyCountdownPreparation(scene)
    -- Le lanceur est en main dès la préparation (le joueur vise pendant le mini-jeu), puis pendant le compte à rebours
    if not scene or (scene.state ~= 'countdown' and scene.state ~= 'preparing') then return end
    local launcher = SpinArena and SpinArena.Launcher
    if launcher and type(launcher.onCountdownStart) == 'function' then
        local mySide = tonumber(scene.side) or 1
        local myTop = scene.tops and scene.tops[mySide]
        local modelName = myTop and (myTop.model or ('spin_top_' .. tostring(myTop.family or 'balance'))) or 'spin_top_balance'
        launcher.onCountdownStart(scene.matchId, scene.round, scene.role, modelName, myTop and myTop.dir, myTop and myTop.parts)
    end
end

-- Un pas de rendu appelé par la boucle active (ou par un test)
local function tickOne(nowOverride)
    local scene = activeScene
    if not scene then return false end

    local now = tonumber(nowOverride) or nowMs()
    local frameDt = math_min(0.10, math_max(0.0, (now - (scene.lastRenderMs or now)) * 0.001))
    scene.lastRenderMs = now

    -- Transition countdown -> playing à t0 + BUFFER_DELAY_S (uniquement lorsque t0 est connu)
    local playTimeS = -Renderer.BUFFER_DELAY_S
    if scene.t0 ~= nil then
        playTimeS = ((now - scene.t0) * 0.001) - Renderer.BUFFER_DELAY_S
        if scene.state == 'countdown' then
            notifyCountdownPreparation(scene)
            local remSec = math.ceil(math_max(0.0, (scene.t0 - now) * 0.001))
            if remSec >= 1 and remSec <= 3 and scene.lastCountdownBeepSec ~= remSec then
                scene.lastCountdownBeepSec = remSec
                local fx = SpinArena and SpinArena.Effects
                if fx and type(fx.onCountdownTick) == 'function' and scene.matchId == primaryId then
                    fx.onCountdownTick(remSec)
                end
            end
            if playTimeS >= 0.0 then
                scene.state = 'playing'
                local launcher = SpinArena and SpinArena.Launcher
                if launcher and type(launcher.onLaunchGo) == 'function' then
                    -- La toupie tenue en main vole vers sa toupie de la cuvette (créée par le rendu juste après)
                    local mySide = tonumber(scene.side) or 1
                    launcher.onLaunchGo(scene.matchId, scene.round, scene.role, function()
                        return scene.topProps and scene.topProps[mySide]
                    end)
                end
                local fx = SpinArena and SpinArena.Effects
                if fx and type(fx.onLaunchGo) == 'function' and scene.matchId == primaryId then
                    fx.onLaunchGo()
                end
            end
        end
    end

    local targetStep = 0.0
    if (scene.state == 'playing' or scene.state == 'ended' or scene.state == 'match_ended') and scene.t0 ~= nil then
        targetStep = math_max(0.0, playTimeS / scene.dt)
    end

    -- Ralenti du coup final (client/spectacle.lua) : pendant le maintien de fin, rejoue au ralenti les dernières
    -- keyframes déjà reçues. Le maintien est prolongé de la durée du ralenti, borné.
    local playSpeed, replayExtraMs = 1.0, 0
    local spectacle = SpinArena and SpinArena.Spectacle
    if spectacle and (scene.state == 'ended' or scene.state == 'match_ended') then
        targetStep, playSpeed = spectacle.replayStep(scene, targetStep, now)
        if spectacle.replayActive(scene) then replayExtraMs = spectacle.replayDurationMs() end
    end
    scene.frameDt = frameDt * playSpeed

    -- 1) Fin de match affichée pendant MATCH_END_HOLD_MS (~5 s) puis nettoyée
    if scene.state == 'match_ended' then
        if now - (scene.matchEndedAtMs or now) >= Renderer.MATCH_END_HOLD_MS + replayExtraMs then
            Renderer.cleanup('match_end_hold_complete')
            return false
        end
    -- 2) Fin de manche affichée pendant ROUND_END_HOLD_MS (ou ROUND_INTERMISSION_HOLD_MS en BO3)
    elseif scene.state == 'ended' then
        local holdMs = (scene.bestOf and scene.bestOf > 1) and Renderer.ROUND_INTERMISSION_HOLD_MS or Renderer.ROUND_END_HOLD_MS
        if now - (scene.endedAtMs or now) >= holdMs + replayExtraMs then
            Renderer.cleanup('round_end_hold_complete')
            return false
        end
    elseif scene.state == 'preparing' then
        -- 3a) Préparation : silence normal (les joueurs visent) ; seule une absence prolongée nettoie
        if (now - (scene.lastPacketMs or now)) > Renderer.PREPARE_TIMEOUT_MS then
            Renderer.cleanup('prepare_timeout')
            return false
        end
    else
        -- 3) Tant que last=true n'est pas reçu : timeout de 5 s sans paquet (ARCHITECTURE.md §10)
        if not scene.receivedLast then
            if (now - (scene.lastPacketMs or now)) > Renderer.STARVATION_TIMEOUT_MS then
                Renderer.cleanup('timeout_5s')
                return false
            end
        else
            -- 4) Si last=true a été reçu mais que roundEnd/cancel est perdu :
            -- dès que la lecture atteint la dernière keyframe reçue, on arme un délai terminal de 5 s.
            local nFrames = #scene.frames
            local lastStep = (nFrames > 0) and scene.frames[nFrames].step or 0
            if scene.state == 'playing' and targetStep >= lastStep then
                if not scene.lastFrameReachedAtMs then
                    scene.lastFrameReachedAtMs = now
                elseif (now - scene.lastFrameReachedAtMs) > Renderer.STARVATION_TIMEOUT_MS then
                    Renderer.cleanup('missing_round_end_timeout')
                    return false
                end
            else
                scene.lastFrameReachedAtMs = nil
            end
        end
    end

    local maxGapSteps = (scene.keyframeEvery or 6) * 4
    local interp, starving = nil, false
    if scene.state == 'playing' or scene.state == 'ended' or scene.state == 'match_ended' then
        interp, starving = Renderer.interpolateAtStep(scene.frames, targetStep, scene.receivedLast, maxGapSteps)
    elseif #scene.frames > 0 then
        interp = Renderer.interpolateAtStep(scene.frames, 0.0, true, maxGapSteps)
    end
    scene.starving = starving

    -- Si aucune keyframe n'est encore arrivée pendant le compte à rebours, afficher la pose de départ opposée (0.6 * R)
    if not interp then
        local rStart = 0.60 * ((scene.arena and scene.arena.R) or 0.60)
        interp = {
            step = 0,
            starving = false,
            tops = {
                [1] = { x = -rStart, y = 0.0, w = 0.0, wob = 0.0, st = Renderer.STATUS.SPINNING },
                [2] = { x =  rStart, y = 0.0, w = 0.0, wob = 0.0, st = Renderer.STATUS.SPINNING },
            },
        }
    end

    -- Intégration locale de l'angle visuel à partir de w (PHYSICS.md §15 : ang non transmis sur le réseau)
    for i = 1, 2 do
        local ts = interp.tops[i]
        local dir = (scene.tops[i] and tonumber(scene.tops[i].dir)) or 1
        if dir >= 0 then dir = 1 else dir = -1 end
        if not scene.starving and ts.st ~= Renderer.STATUS.STOPPED and ts.st ~= Renderer.STATUS.EJECTED then
            local wVis = math_min(ts.w or 0.0, Renderer.VISUAL_W_CAP)
            scene.visualAngles[i] = ((scene.visualAngles[i] or 0.0) + dir * wVis * frameDt * playSpeed) % TWO_PI
        end
    end

    -- Scène réduite (au-delà de MAX_SCENES, la plus lointaine) : état tenu à jour, mais ni toupies ni formes
    if scene.reduced then
        if scene.topProps then
            for i = 1, 2 do
                if scene.topProps[i] then
                    safeDeleteObject(scene.topProps[i])
                    scene.topProps[i] = nil
                end
            end
        end
        scene.topPropsTried = {}
        local rivals = SpinArena and SpinArena.LauncherRivals
        if rivals and type(rivals.release) == 'function' then rivals.release(scene) end
        return true
    end

    -- Props d'abord : les formes géométriques ne servent que de repli quand un modèle manque
    updateSceneProps(scene, interp, now)
    -- Lanceurs des autres participants, dans leur main (client/launcher_rivals.lua)
    local rivals = SpinArena and SpinArena.LauncherRivals
    if rivals and type(rivals.sync) == 'function' then
        local ok, err = pcall(rivals.sync, scene, now, frameDt)
        if not ok and type(print) == 'function' then print(('[spin_arena] lanceurs des participants : %s'):format(tostring(err))) end
    end
    drawTemporaryArena(scene)
    if scene.state ~= 'preparing' and scene.state ~= 'countdown' then
        for i = 1, 2 do
            drawTemporaryTop(scene, i, interp.tops[i], now)
        end
    end
    drawTemporaryEvents(scene, interp.step or 0, now)
    if spectacle then
        -- Traînées, lueurs et poches (client/spectacle.lua) ; une erreur d'affichage n'arrête jamais le rendu du match
        local ok, err = pcall(spectacle.drawScene, scene, interp, now)
        if not ok and type(print) == 'function' then print(('[spin_arena] spectacle : %s'):format(tostring(err))) end
        if scene.matchId == primaryId then
            if scene.replay and scene.replay.state == 'playing' then
                drawOverlayText(0.5, 0.11, 0.55, 'RALENTI', COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, 230, true)
            end
            -- Sifflement de rotation : sa propre toupie (participant) ou la plus rapide des deux (spectateur)
            local fx = SpinArena and SpinArena.Effects
            if fx and type(fx.spinLevel) == 'function' then
                local level = 0.0
                if scene.state == 'playing' and not scene.starving then
                    local mySide = scene.role == 'participant' and tonumber(scene.side) or nil
                    for i = 1, 2 do
                        if not mySide or mySide == i then level = math_max(level, spectacle.spinLevel(interp.tops[i])) end
                    end
                end
                fx.spinLevel(level)
            end
        end
    end
    -- Texte à l'écran : seulement pour la scène principale (les autres tables ont leur panneau dans le monde)
    -- Pendant la préparation, la jauge et le panneau de la table disent tout : pas de télémétrie (elle chevauchait le
    -- panneau et affichait une rotation « EN ROTATION w = 0 » avant tout lancer — capture de Money, 19/10)
    -- Texte de télémétrie à l'écran : désactivé par défaut (il passait par-dessus le panneau de la table, qui montre déjà
    -- noms, score et manche — captures de Money, 19/10) ; Config.debugTelemetry = true pour le débogage
    local debugTelemetry = SpinArena and SpinArena.Config and SpinArena.Config.debugTelemetry == true
    if debugTelemetry and scene.matchId == primaryId and scene.state ~= 'preparing' then drawTemporaryTelemetry(scene, interp, now) end

    return true
end

local function ensureRenderLoop()
    if loopRunning or type(CreateThread) ~= 'function' then
        return
    end
    loopRunning = true
    CreateThread(function()
        while next(scenes) ~= nil do
            Renderer.tick()
            Wait(0)
        end
        loopRunning = false
    end)
end

local function computeInitialTiming(payload, now)
    -- Lancement manuel : la manche attend que les deux joueurs lancent ; aucun départ n'est fixé (le délai
    -- indiqué est celui de la préparation). Le départ arrive par spin_arena:cl:countdown (révision suivante).
    if payload.preparing then
        return nil, nil, 'preparing'
    end
    local elapsedMs = tonumber(payload.elapsedMs)
    if elapsedMs and elapsedMs > 0 then
        return now - clamp(elapsedMs, 0, 120000), 0, 'playing'
    end
    local rawStarts = tonumber(payload.startsInMs)
    if rawStarts ~= nil then
        local clamped = clamp(rawStarts, 0, 15000)
        return now + clamped, clamped, 'countdown'
    end
    -- Si un spin_arena:cl:countdown est arrivé juste avant l'en-tête (D05)
    local reqRound = tonumber(payload.round) or 1
    if pendingCountdown
        and pendingCountdown.matchId == payload.matchId
        and pendingCountdown.round == reqRound
        and (now - pendingCountdown.atMs) <= 5000
    then
        return pendingCountdown.t0, pendingCountdown.startsInMs, 'countdown'
    end
    return nil, nil, 'countdown'
end

-- Démarre ou met à jour l'en-tête d'un match ou d'une nouvelle manche (spin_arena:cl:match)
local function onMatchOne(payload)
    if type(payload) ~= 'table' or not payload.matchId then
        return false
    end
    if activeScene
        and activeScene.matchId ~= payload.matchId
        and activeScene.role == 'participant'
        and activeScene.state ~= 'match_ended'
        and tostring(payload.role or '') ~= 'participant'
    then
        return false
    end
    local now = nowMs()
    local inRound = tonumber(payload.round) or 1
    local inRev = tonumber(payload.revision or payload.rev) or 0

    if activeScene and activeScene.matchId == payload.matchId then
        -- Si le match est déjà en bannière finale (match_ended), on ignore tout ancien en-tête de manche
        if activeScene.state == 'match_ended' then
            return false
        end
        -- Rejet d'une ancienne manche arrivée en retard (D05)
        if inRound < activeScene.round then
            return false
        end
        -- Même (matchId, round) : doublon réseau ou nouvelle révision de la même manche
        if inRound == activeScene.round then
            local curRev = activeScene.revision or 0
            if inRev < curRev then
                return false
            end
            local isNewRev = (inRev > curRev)
            if not isNewRev and activeScene.state == 'ended' then
                return false
            end
            activeScene.revision = inRev
            if payload.score and (isNewRev or activeScene.outcome == nil) then
                activeScene.score = normalizeScore(payload.score, activeScene.score)
            end
            if payload.names then
                activeScene.names = normalizeNames(payload.names, activeScene.tops, activeScene.names)
            end
            if payload.role then activeScene.role = tostring(payload.role) end
            if payload.side ~= nil then activeScene.side = tonumber(payload.side) end
            if payload.srcs then activeScene.srcs = normalizeSrcs(payload.srcs, activeScene.srcs) end
            if isNewRev then
                local initT0, initStarts, initState = computeInitialTiming(payload, now)
                activeScene.t0 = initT0
                activeScene.lastStartsInMs = initStarts
                activeScene.state = initState
                activeScene.lastCountdownBeepSec = nil
                activeScene.lastFrameReachedAtMs = nil
                activeScene.lastSeq = 0
                activeScene.seenSeq = {}
                activeScene.receivedLast = false
                activeScene.starving = false
                activeScene.frames = {}
                activeScene.events = {}
                activeScene.ejectedState = {}
                activeScene.outcome = nil
                if SpinArena.Spectacle then SpinArena.Spectacle.resetScene(activeScene) end
                notifyCountdownPreparation(activeScene)
                activeScene.lastPacketMs = now
                ensureRenderLoop()
                return true
            elseif activeScene.t0 == nil then
                local initT0, initStarts, initState = computeInitialTiming(payload, now)
                if initT0 ~= nil then
                    activeScene.t0 = initT0
                    activeScene.lastStartsInMs = initStarts
                    activeScene.state = initState
                end
            end
            activeScene.lastPacketMs = now
            return false
        end

        -- Nouvelle manche (inRound > activeScene.round) du même match :
        -- on réinitialise les buffers de manche sans perdre le score ni recréer toute la structure
        local initT0, initStarts, initState = computeInitialTiming(payload, now)
        if activeScene.topProps then
            for i = 1, 2 do
                if activeScene.topProps[i] then
                    safeDeleteObject(activeScene.topProps[i])
                    activeScene.topProps[i] = nil
                end
            end
        end
        activeScene.topPropsTried        = {}
        activeScene.round                = inRound
        activeScene.revision             = inRev
        activeScene.bestOf               = tonumber(payload.bestOf) or activeScene.bestOf or 1
        activeScene.target               = tonumber(payload.target) or activeScene.target
        activeScene.score                = normalizeScore(payload.score, activeScene.score)
        activeScene.names                = normalizeNames(payload.names, activeScene.tops, activeScene.names)
        activeScene.role                 = payload.role and tostring(payload.role) or activeScene.role
        if payload.side ~= nil then activeScene.side = tonumber(payload.side) end
        if payload.srcs then activeScene.srcs = normalizeSrcs(payload.srcs, activeScene.srcs) end
        activeScene.state                = initState
        activeScene.t0                   = initT0
        activeScene.lastStartsInMs       = initStarts
        activeScene.lastCountdownBeepSec = nil
        activeScene.lastPacketMs         = now
        activeScene.lastRenderMs         = now
        activeScene.lastFrameReachedAtMs = nil
        activeScene.lastSeq              = 0
        activeScene.seenSeq              = {}
        activeScene.receivedLast         = false
        activeScene.starving             = false
        activeScene.frames               = {}
        activeScene.events               = {}
        activeScene.visualAngles         = { [1] = 0.0, [2] = math_pi }
        activeScene.ejectedState         = {}
        activeScene.outcome              = nil
        if SpinArena.Spectacle then SpinArena.Spectacle.resetScene(activeScene) end
        notifyCountdownPreparation(activeScene)
        ensureRenderLoop()
        return true
    end

    if activeScene then
        cleanupSceneProps(activeScene)
    end

    local arenaIn = type(payload.arena) == 'table' and payload.arena or {}
    local topsIn = type(payload.tops) == 'table' and payload.tops or {}

    local tops = {}
    for i = 1, 2 do
        local t = type(topsIn[i]) == 'table' and topsIn[i] or {}
        tops[i] = {
            r      = clamp(tonumber(t.r) or 0.05, 0.030, 0.100),
            label  = tostring(t.label or ('Toupie #' .. i)),
            color  = normalizeColor(t.color, DEFAULT_TOP_COLORS[i]),
            dir    = (tonumber(t.dir) == -1) and -1 or 1,
            family = t.family and tostring(t.family) or nil,
            model  = t.model and tostring(t.model) or nil,
            parts  = SpinArena and SpinArena.TopModel and SpinArena.TopModel.normalize(t.parts) or nil,   -- pièces → modèles assemblés
        }
    end

    local initialT0, initialStarts, initialState = computeInitialTiming(payload, now)

    activeScene = {
        matchId              = payload.matchId,
        epoch                = payload.epoch,
        round                = inRound,
        revision             = inRev,
        bestOf               = tonumber(payload.bestOf) or 1,
        target               = tonumber(payload.target),
        score                = normalizeScore(payload.score, nil),
        role                 = payload.role and tostring(payload.role) or nil,
        side                 = tonumber(payload.side),
        names                = normalizeNames(payload.names, tops, nil),
        srcs                 = normalizeSrcs(payload.srcs, nil),
        dt                   = clamp(tonumber(payload.dt) or (1.0 / 120.0), 1.0 / 240.0, 0.1),
        keyframeEvery        = math_max(1, math_floor(tonumber(payload.keyframeEvery) or 6)),
        arena = {
            x       = tonumber(arenaIn.x) or 0.0,
            y       = tonumber(arenaIn.y) or 0.0,
            z       = tonumber(arenaIn.z) or 0.0,
            heading = tonumber(arenaIn.heading) or 0.0,
            scale   = clamp(tonumber(arenaIn.scale) or 1.0, 0.25, 5.0),
            R       = clamp(tonumber(arenaIn.R) or 0.60, 0.20, 3.00),
            h       = clamp(tonumber(arenaIn.h) or 0.05, 0.00, 0.50),
            pockets     = type(arenaIn.pockets) == 'table' and arenaIn.pockets or {},
            model       = arenaIn.model and tostring(arenaIn.model) or nil,
            floorHeight = tonumber(arenaIn.floorHeight) or Renderer.BOWL_FLOOR_Z,
        },
        tops                 = tops,
        state                = initialState,
        t0                   = initialT0,
        lastStartsInMs       = initialStarts,
        lastCountdownBeepSec = nil,
        lastPacketMs         = now,
        lastRenderMs         = now,
        lastFrameReachedAtMs = nil,
        lastSeq              = 0,
        seenSeq              = {},
        receivedLast         = false,
        starving             = false,
        frames               = {},
        events               = {},
        visualAngles         = { [1] = 0.0, [2] = math_pi },
        ejectedState         = {},
        arenaProp            = nil,
        arenaPropTried       = false,
        topProps             = {},
        topPropsTried        = {},
        outcome              = nil,
        matchOutcome         = nil,
    }

    if pendingCountdown and pendingCountdown.matchId == payload.matchId then
        pendingCountdown = nil
    end

    notifyCountdownPreparation(activeScene)
    ensureRenderLoop()
    return true
end

-- Réception du compte à rebours synchronisé (spin_arena:cl:countdown)
local function onCountdownOne(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    local now = nowMs()
    local startsInMs = clamp(tonumber(payload.startsInMs) or 0, 0, 15000)
    local newRound = tonumber(payload.round) or (activeScene and activeScene.round) or 1
    local inRev = tonumber(payload.revision or payload.rev)

    -- Si countdown arrive avant spin_arena:cl:match (D05), on le mémorise pour l'en-tête imminent
    if not activeScene or payload.matchId ~= activeScene.matchId then
        if not pendingCountdown
            or pendingCountdown.matchId ~= payload.matchId
            or newRound > pendingCountdown.round
            or (newRound == pendingCountdown.round and (inRev or 0) >= (pendingCountdown.revision or 0))
        then
            pendingCountdown = {
                matchId    = payload.matchId,
                round      = newRound,
                revision   = inRev or 0,
                startsInMs = startsInMs,
                t0         = now + startsInMs,
                atMs       = now,
            }
        end
        return false
    end

    if activeScene.state == 'match_ended' then
        return false
    end

    -- Jamais de retour en arrière sur une manche antérieure (D05)
    if newRound < activeScene.round then
        return false
    end

    local isNewRound = (newRound > activeScene.round)
    local isNewRev = false
    if isNewRound then
        if activeScene.topProps then
            for i = 1, 2 do
                if activeScene.topProps[i] then
                    safeDeleteObject(activeScene.topProps[i])
                    activeScene.topProps[i] = nil
                end
            end
        end
        activeScene.topPropsTried = {}
        activeScene.round = newRound
        activeScene.revision = inRev or 0
        activeScene.frames = {}
        activeScene.events = {}
        activeScene.lastSeq = 0
        activeScene.seenSeq = {}
        activeScene.receivedLast = false
        activeScene.lastFrameReachedAtMs = nil
        activeScene.lastStartsInMs = nil
        activeScene.lastCountdownBeepSec = nil
        activeScene.t0 = nil
        activeScene.outcome = nil
        activeScene.ejectedState = {}
    else
        -- Rejet d'une révision antérieure arrivée en retard pour la même manche
        local curRev = activeScene.revision or 0
        if inRev ~= nil then
            if inRev < curRev then
                return false
            end
            isNewRev = (inRev > curRev)
            activeScene.revision = inRev
        end
        -- Si la manche est déjà en cours (playing) ou terminée (ended) sans nouvelle révision,
        -- un paquet countdown retardé ne doit jamais ramener la manche en compte à rebours
        if not isNewRev and activeScene.state ~= 'countdown' and activeScene.state ~= 'preparing' then
            return false
        end
        if isNewRev then
            activeScene.frames = {}
            activeScene.events = {}
            activeScene.lastSeq = 0
            activeScene.seenSeq = {}
            activeScene.receivedLast = false
            activeScene.lastFrameReachedAtMs = nil
            activeScene.lastStartsInMs = nil
            activeScene.lastCountdownBeepSec = nil
            activeScene.t0 = nil
            activeScene.outcome = nil
            activeScene.ejectedState = {}
        end
    end

    local candT0 = now + startsInMs
    if activeScene.t0 == nil or isNewRound or isNewRev or activeScene.lastStartsInMs == nil or math_abs(startsInMs - activeScene.lastStartsInMs) > 5 then
        activeScene.t0 = candT0
        activeScene.lastStartsInMs = startsInMs
        activeScene.state = 'countdown'
        notifyCountdownPreparation(activeScene)
    elseif candT0 < activeScene.t0 and activeScene.state == 'countdown' then
        activeScene.t0 = candT0
    end
    activeScene.lastPacketMs = now
    activeScene.lastFrameReachedAtMs = nil
    ensureRenderLoop()
    return true
end

-- Insertion triée d'une keyframe par step (remplace si même step)
local function insertKeyframeSorted(dst, decoded)
    local n = #dst
    if n == 0 or decoded.step > dst[n].step then
        dst[n + 1] = decoded
        return
    elseif decoded.step == dst[n].step then
        dst[n] = decoded
        return
    end
    local lo, hi = 1, n
    while lo <= hi do
        local mid = math_floor((lo + hi) * 0.5)
        local s = dst[mid].step
        if s == decoded.step then
            dst[mid] = decoded
            return
        elseif s < decoded.step then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    table.insert(dst, lo, decoded)
end

-- Réception d'une tranche de keyframes et d'événements (spin_arena:cl:frames)
local function onFramesOne(payload)
    if type(payload) ~= 'table' or not activeScene then return false end
    if payload.matchId ~= activeScene.matchId then return false end
    if activeScene.state == 'match_ended' then return false end

    local round = tonumber(payload.round) or activeScene.round
    if round ~= activeScene.round then return false end
    local inRev = tonumber(payload.revision or payload.rev)
    if inRev ~= nil and inRev < (activeScene.revision or 0) then return false end

    local seq = tonumber(payload.seq)
    if seq then
        if seq < 1 or activeScene.seenSeq[seq] then
            -- Doublon exact ou numéro de séquence invalide rejeté
            return false
        end
        activeScene.seenSeq[seq] = true
        if seq > activeScene.lastSeq then
            activeScene.lastSeq = seq
        end
    end

    activeScene.lastPacketMs = nowMs()

    local rawFrames = payload.frames
    if type(rawFrames) == 'table' then
        local dst = activeScene.frames
        for i = 1, #rawFrames do
            local decoded = Renderer.decodeKeyframe(rawFrames[i])
            if decoded then
                insertKeyframeSorted(dst, decoded)
            end
        end
    end

    local rawEvents = payload.events
    if type(rawEvents) == 'table' then
        local evDst = activeScene.events
        for i = 1, #rawEvents do
            local ev = rawEvents[i]
            if type(ev) == 'table' and tonumber(ev.s) then
                local entry = {
                    s = tonumber(ev.s),
                    t = tostring(ev.t or 'hit'),
                    a = tonumber(ev.a) or 1,
                    b = tonumber(ev.b),
                    x = tonumber(ev.x) or 0,
                    y = tonumber(ev.y) or 0,
                    k = clamp(tonumber(ev.k) or 128, 0, 255),
                }
                local m = #evDst
                if m == 0 or entry.s >= evDst[m].s then
                    evDst[m + 1] = entry
                else
                    local pos = m
                    while pos > 1 and evDst[pos - 1].s > entry.s do
                        pos = pos - 1
                    end
                    table.insert(evDst, pos, entry)
                end
            end
        end
    end

    if payload.last == true then
        activeScene.receivedLast = true
    end

    ensureRenderLoop()
    return true
end

-- Fin de manche autoritaire envoyée par le serveur (spin_arena:cl:roundEnd)
local function onRoundEndOne(payload)
    if type(payload) ~= 'table' or not activeScene then return false end
    if payload.matchId ~= activeScene.matchId then return false end
    if activeScene.state == 'match_ended' then return false end
    local round = tonumber(payload.round) or activeScene.round
    if round ~= activeScene.round then return false end
    local inRev = tonumber(payload.revision or payload.rev)
    if inRev ~= nil and inRev < (activeScene.revision or 0) then return false end

    if payload.score then
        activeScene.score = normalizeScore(payload.score, activeScene.score)
    end

    activeScene.outcome = {
        winner = payload.winner,
        reason = tostring(payload.reason or 'time'),
        step   = tonumber(payload.step) or 0,
        score  = activeScene.score,
        points = tonumber(payload.points),
    }
    activeScene.receivedLast = true
    if activeScene.state ~= 'match_ended' then
        activeScene.state = 'ended'
    end
    activeScene.endedAtMs = nowMs()
    activeScene.lastPacketMs = activeScene.endedAtMs
    local spectacle = SpinArena and SpinArena.Spectacle
    if spectacle then spectacle.planReplay(activeScene) end   -- ralenti du coup final (éjection ou arrêt)
    local launcher = SpinArena and SpinArena.Launcher
    if launcher and type(launcher.cleanup) == 'function' then
        launcher.cleanup()
    end
    local fx = SpinArena and SpinArena.Effects
    if fx and type(fx.onRoundEnd) == 'function' then
        fx.onRoundEnd()
    end
    return true
end

-- Fin de match autoritaire envoyée par le serveur (spin_arena:cl:matchEnd) :
-- affiche la bannière finale pendant MATCH_END_HOLD_MS (~5 s) puis nettoie.
local function onMatchEndOne(payload)
    if type(payload) ~= 'table' then return false end
    if not activeScene then return false end
    if payload.matchId and payload.matchId ~= activeScene.matchId then
        return false
    end
    if activeScene.state == 'match_ended' then
        return false
    end

    local now = nowMs()
    if payload.score then
        activeScene.score = normalizeScore(payload.score, activeScene.score)
    end
    if payload.names then
        activeScene.names = normalizeNames(payload.names, activeScene.tops, activeScene.names)
    end

    activeScene.matchOutcome = {
        winner = payload.winner,
        reason = tostring(payload.reason or 'rounds'),
        detail = payload.detail,
        score  = activeScene.score,
        names  = activeScene.names,
    }
    local launcher = SpinArena and SpinArena.Launcher
    if launcher and type(launcher.cleanup) == 'function' then
        launcher.cleanup()
    end
    activeScene.receivedLast = true
    activeScene.state = 'match_ended'
    activeScene.matchEndedAtMs = now
    activeScene.lastPacketMs = now
    ensureRenderLoop()
    return true
end

-- Préparation du lancement manuel (spin_arena:cl:prepare) : la scène de ce match reste vivante
local function onPrepareOne(payload)
    if type(payload) ~= 'table' or not activeScene or payload.matchId ~= activeScene.matchId then return false end
    if activeScene.state ~= 'preparing' then return false end
    activeScene.lastPacketMs = nowMs()
    activeScene.ready = type(payload.ready) == 'table' and { payload.ready[1] == true, payload.ready[2] == true } or activeScene.ready
    return true
end

-- Annulation ou désabonnement immédiat (spin_arena:cl:cancel / spin_arena:cl:unsub)
local function onCancelOne(payload)
    if not activeScene then return false end
    if type(payload) == 'table' and payload.matchId and payload.matchId ~= activeScene.matchId then
        return false
    end
    return Renderer.cleanup((type(payload) == 'table' and payload.reason) or 'cancel')
end

-------------------------------------------------------------------------------
-- Plusieurs scènes : sélection, scène principale, budget de rendu, panneaux (contrat scenes())
-------------------------------------------------------------------------------

-- Exécute fn sur la scène de matchId (activeScene/pendingCountdown pointent dessus) ; réentrant
local function withScene(matchId, fn, ...)
    if matchId == nil then return false end
    if selectedId == matchId then return fn(...) end
    local prevId, prevScene, prevPending = selectedId, activeScene, pendingCountdown
    selectedId, activeScene, pendingCountdown = matchId, scenes[matchId], pendings[matchId]
    local ok, res = pcall(fn, ...)
    scenes[matchId], pendings[matchId] = activeScene, pendingCountdown
    selectedId, activeScene, pendingCountdown = prevId, prevScene, prevPending
    if not ok then error(res, 0) end
    return res
end

local function playerCoords()
    if type(PlayerPedId) ~= 'function' or type(GetEntityCoords) ~= 'function' then return nil end
    local ok, c = pcall(function() return GetEntityCoords(PlayerPedId()) end)
    if not ok or c == nil then return nil end
    local x, y, z = tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3])
    if not x then return nil end
    return { x = x, y = y, z = z }
end

local function sceneDistance(sc, me)
    if not me or not sc.arena then return 0.0 end
    local dx, dy = (sc.arena.x or 0) - me.x, (sc.arena.y or 0) - me.y
    return math_sqrt(dx * dx + dy * dy)
end

-- Scène principale (son propre match, sinon la plus proche) et scènes réduites au-delà de MAX_SCENES
local function arrangeScenes()
    local me = playerCoords()
    local list = {}
    for id, sc in pairs(scenes) do
        sc.distance = sceneDistance(sc, me)
        list[#list + 1] = sc
    end
    table.sort(list, function(a, b)
        local ownA, ownB = a.role == 'participant', b.role == 'participant'
        if ownA ~= ownB then return ownA end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return tostring(a.matchId) < tostring(b.matchId)
    end)
    primaryId = list[1] and list[1].matchId or nil
    for i, sc in ipairs(list) do sc.reduced = (i > Renderer.MAX_SCENES) or nil end
    return list
end

local STATE_NAMES = { preparing = 'preparing', countdown = 'countdown', playing = 'playing', ended = 'round_over',
                      match_ended = 'finished' }

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Instantané d'une scène pour les panneaux (copie : aucune modification ne remonte dans le rendu)
local function snapshot(sc)
    local a = sc.arena or {}
    local outcome = sc.matchOutcome
    return {
        matchId = sc.matchId, stationId = a.fixedId, label = a.label,
        center = { x = a.x, y = a.y, z = a.z },
        topZ = (a.z or 0) + (tonumber(a.floorHeight) or Renderer.BOWL_FLOOR_Z) + 0.15,
        variant = a.variant, model = a.model,
        state = STATE_NAMES[sc.state] or tostring(sc.state),
        revision = sc.revision, goAt = sc.t0, round = sc.round, bestOf = sc.bestOf, target = sc.target,
        score = copy(sc.score), names = copy(sc.names),
        ready = sc.state == 'preparing' and copy(sc.ready) or nil,
        deadlineAt = sc.state == 'preparing' and sc.deadlineAt or nil,
        roundWinner = sc.state == 'ended' and sc.outcome and sc.outcome.winner or nil,
        roundReason = sc.state == 'ended' and sc.outcome and sc.outcome.reason or nil,
        roundPoints = sc.state == 'ended' and sc.outcome and sc.outcome.points or nil,
        winner = outcome and outcome.winner or nil, reason = outcome and outcome.reason or nil,
        own = sc.role == 'participant', reduced = sc.reduced == true, practice = sc.practice == true,
        distance = sc.distance,
    }
end

-- Liste lisible des combats suivis, triée par distance (copies) ; scènes annulées gardées GHOST_MS
function Renderer.scenes()
    local now = nowMs()
    for id, g in pairs(ghosts) do
        if now >= g.untilMs then ghosts[id] = nil end
    end
    local list = {}
    for _, sc in ipairs(arrangeScenes()) do list[#list + 1] = snapshot(sc) end
    for _, g in pairs(ghosts) do list[#list + 1] = copy(g.view) end
    -- Files d'attente, sauf si un combat de la même table est déjà suivi (la scène du match prend le relais)
    local busyStations = {}
    for _, v in ipairs(list) do if v.stationId then busyStations[v.stationId] = true end end
    local me = playerCoords()
    for _, qv in pairs(queues) do
        if not busyStations[qv.stationId] then
            local v = copy(qv)
            v.distance = me and math_sqrt((v.center.x - me.x) ^ 2 + (v.center.y - me.y) ^ 2) or 0
            list[#list + 1] = v
        end
    end
    table.sort(list, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
    return list
end

function Renderer.onScenesChanged(cb)
    if type(cb) == 'function' then sceneListeners[#sceneListeners + 1] = cb end
end

local function boardChanged()
    local parts = {}
    for id, sc in pairs(scenes) do
        local sa, sb = 0, 0
        if type(sc.score) == 'table' then sa, sb = sc.score[1] or sc.score.a or 0, sc.score[2] or sc.score.b or 0 end
        parts[#parts + 1] = table.concat({ tostring(id), tostring(sc.state), tostring(sc.round), tostring(sc.revision),
            tostring(sa), tostring(sb), tostring(sc.reduced), tostring(sc.ready and sc.ready[1]), tostring(sc.ready and sc.ready[2]) }, ':')
    end
    for id in pairs(ghosts) do parts[#parts + 1] = 'ghost:' .. tostring(id) end
    for id, q in pairs(queues) do parts[#parts + 1] = id .. ':' .. tostring(q.waiting) .. ':' .. tostring(q.names and q.names.a) end
    table.sort(parts)
    local sig = table.concat(parts, '|')
    if sig == lastBoardSignature then return end
    lastBoardSignature = sig
    if #sceneListeners == 0 then return end
    local list = Renderer.scenes()
    for _, cb in ipairs(sceneListeners) do pcall(cb, copy(list)) end
end

-- File d'attente d'une table (spin_arena:cl:queue) : « queue:<stationId> » dans scenes() tant que waiting > 0
function Renderer.onQueue(payload)
    if type(payload) ~= 'table' or type(payload.stationId) ~= 'string' then return false end
    local id = 'queue:' .. payload.stationId
    local waiting = tonumber(payload.waiting) or 0
    if waiting <= 0 then
        queues[id] = nil
    else
        local z, fh = tonumber(payload.z) or 0, tonumber(payload.floorHeight) or Renderer.BOWL_FLOOR_Z
        queues[id] = {
            matchId = id, stationId = payload.stationId, label = payload.label, state = 'queue',
            center = { x = tonumber(payload.x) or 0, y = tonumber(payload.y) or 0, z = z },
            topZ = z + fh + 0.15, waiting = waiting,
            names = type(payload.names) == 'table' and { a = payload.names.a } or nil,
        }
    end
    lastBoardSignature = nil
    boardChanged()
    return true
end


local function after(res)
    arrangeScenes()
    boardChanged()
    if next(scenes) ~= nil then ensureRenderLoop() end
    return res
end

function Renderer.onMatch(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    local res = withScene(payload.matchId, function()
        local r = onMatchOne(payload)
        if activeScene and activeScene.matchId == payload.matchId then
            activeScene.practice = payload.practice == true or activeScene.practice
            if type(payload.arena) == 'table' then
                activeScene.arena.fixedId = payload.arena.fixedId
                activeScene.arena.variant = payload.arena.variant
                activeScene.arena.label = payload.arena.label
            end
            if activeScene.state == 'preparing' and tonumber(payload.startsInMs) then
                activeScene.deadlineAt = nowMs() + clamp(tonumber(payload.startsInMs), 0, 120000)
            end
        end
        return r
    end)
    ghosts[payload.matchId] = nil
    return after(res)
end

function Renderer.onCountdown(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    return after(withScene(payload.matchId, onCountdownOne, payload))
end

function Renderer.onFrames(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    return after(withScene(payload.matchId, onFramesOne, payload))
end

function Renderer.onRoundEnd(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    return after(withScene(payload.matchId, onRoundEndOne, payload))
end

function Renderer.onMatchEnd(payload)
    if type(payload) ~= 'table' then return false end
    return after(withScene(payload.matchId or primaryId, onMatchEndOne, payload))
end

function Renderer.onPrepare(payload)
    if type(payload) ~= 'table' or not payload.matchId then return false end
    return after(withScene(payload.matchId, function()
        local r = onPrepareOne(payload)
        if r and tonumber(payload.deadlineInMs) then activeScene.deadlineAt = nowMs() + tonumber(payload.deadlineInMs) end
        return r
    end))
end

-- Annulation : la scène disparaît du rendu, mais son panneau annonce « annulé » pendant GHOST_MS
function Renderer.onCancel(payload)
    local id = type(payload) == 'table' and payload.matchId or primaryId
    local sc = id and scenes[id]
    if sc and not (type(payload) == 'table' and payload.unsub) then
        local view = snapshot(sc)
        view.state, view.reason = 'cancelled', type(payload) == 'table' and payload.reason or 'cancel'
        ghosts[id] = { view = view, untilMs = nowMs() + Renderer.GHOST_MS }
        -- Fin de l'annonce : prévenir les panneaux même si plus aucune scène ne fait tourner la boucle
        if type(SetTimeout) == 'function' then
            SetTimeout(Renderer.GHOST_MS + 50, function() Renderer.scenes() boardChanged() end)
        end
    end
    return after(withScene(id, onCancelOne, payload))
end

-- Désabonnement (le joueur s'éloigne) : retrait immédiat, sans annonce
function Renderer.onUnsub(payload)
    local p = type(payload) == 'table' and copy(payload) or {}
    p.unsub = true
    return Renderer.onCancel(p)
end

function Renderer.cleanup(reason)
    if selectedId then return cleanupOne(reason) end
    local any = false
    local ids = {}
    for id in pairs(scenes) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        if withScene(id, cleanupOne, reason) then any = true end
    end
    pendings, ghosts = {}, {}
    pendingCountdown = nil
    after(nil)
    return any
end

function Renderer.tick(nowOverride)
    if selectedId then return tickOne(nowOverride) end
    local now = tonumber(nowOverride) or nowMs()
    for id, g in pairs(ghosts) do
        if now >= g.untilMs then ghosts[id] = nil end
    end
    arrangeScenes()
    local any = false
    local ids = {}
    for id in pairs(scenes) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return a == primaryId or (b ~= primaryId and tostring(a) < tostring(b)) end)
    for _, id in ipairs(ids) do
        if withScene(id, tickOne, nowOverride) then any = true end
    end
    boardChanged()
    return any
end

-- Suite de tests unitaires reproductibles hors jeu (exécutable avec `lua5.4`)
function Renderer.selfTest()
    Renderer.cleanup('selftest_init')

    -- 1. Décodage des keyframes quantifiées
    local kf = Renderer.decodeKeyframe({ 0, -360, 0, 2500, 0, 0, 360, 0, 2400, 51, 0 })
    assert(kf and math.abs(kf.tops[1].x - (-0.36)) < 1e-9, 'decodeKeyframe x1')
    assert(math.abs(kf.tops[1].w - 250.0) < 1e-9, 'decodeKeyframe w1')
    assert(math.abs(kf.tops[2].wob - 0.2) < 1e-6, 'decodeKeyframe wob2')

    -- 2. Transformation repère local -> monde et hauteur parabolique de cuvette
    local arena = { x = 100.0, y = 200.0, z = 30.0, heading = 90.0, scale = 1.0, R = 0.60, h = 0.05 }
    local wx, wy, wz = Renderer.localToWorld(arena, 0.60, 0.0, 0.0)
    assert(math.abs(wx - 100.0) < 1e-6, 'localToWorld wx')
    assert(math.abs(wy - 200.60) < 1e-6, 'localToWorld wy')
    assert(math.abs(wz - 30.05) < 1e-6, 'localToWorld wz')

    -- 3. Conservation stricte du statut ta.st tant que targetStep < b.step (pas d'état terminal anticipé)
    local framesStatus = {
        Renderer.decodeKeyframe({ 0, -300, 0, 2000, 0, Renderer.STATUS.SPINNING, 300, 0, 2000, 0, Renderer.STATUS.STOPPING }),
        Renderer.decodeKeyframe({ 6, -600, 0, 0, 255, Renderer.STATUS.EJECTED, 300, 0, 0, 255, Renderer.STATUS.STOPPED }),
    }
    for _, stepProbe in ipairs({ 0.1, 3.0, 4.5, 5.999 }) do
        local stInterp = Renderer.interpolateAtStep(framesStatus, stepProbe, true)
        assert(stInterp.tops[1].st == Renderer.STATUS.SPINNING, 'status must stay SPINNING before step 6 at step=' .. stepProbe)
        assert(stInterp.tops[2].st == Renderer.STATUS.STOPPING, 'status must stay STOPPING before step 6 at step=' .. stepProbe)
    end
    local stAt6 = Renderer.interpolateAtStep(framesStatus, 6.0, true)
    assert(stAt6.tops[1].st == Renderer.STATUS.EJECTED, 'status becomes EJECTED at step 6')
    assert(stAt6.tops[2].st == Renderer.STATUS.STOPPED, 'status becomes STOPPED at step 6')

    -- 4. Rejet seq dupliqué, gel sur famine (last=false) et nettoyage automatique à 5 s
    assert(Renderer.onMatch({
        matchId = 'm-starve',
        dt = 1.0 / 120.0,
        keyframeEvery = 6,
        arena = arena,
        tops = { { r = 0.05, label = 'Alpha', dir = 1 }, { r = 0.05, label = 'Beta', dir = -1 } },
    }))
    assert(Renderer.onCountdown({ matchId = 'm-starve', round = 1, startsInMs = 0 }))
    local s1 = Renderer.getActiveScene()
    local t0 = s1.t0
    assert(Renderer.onFrames({
        matchId = 'm-starve', round = 1, seq = 1, last = false,
        frames = {
            { 0, -300, 0, 2500, 0, 0, 300, 0, 2500, 0, 0 },
            { 6, -200, 0, 2440, 25, 0, 200, 0, 2440, 25, 0 },
        },
    }))
    assert(Renderer.onFrames({ matchId = 'm-starve', round = 1, seq = 1, frames = {} }) == false, 'duplicate seq rejected')
    assert(Renderer.tick(t0 + 225) == true)
    assert(s1.starving == false)
    assert(Renderer.tick(t0 + 300) == true)
    assert(s1.starving == true, 'must freeze/starve past last frame when last=false')
    assert(Renderer.tick(t0 + 5500) == false, 'must cleanup after 5s starvation')
    assert(Renderer.getActiveScene() == nil)

    -- 5. Régression : onFrames(last=true) suivi de la perte de roundEnd/cancel -> nettoyage terminal garanti
    assert(Renderer.onMatch({
        matchId = 'm-lost-end',
        dt = 1.0 / 120.0,
        keyframeEvery = 6,
        arena = arena,
        tops = { { r = 0.05, label = 'Alpha', dir = 1 }, { r = 0.05, label = 'Beta', dir = -1 } },
    }))
    assert(Renderer.onCountdown({ matchId = 'm-lost-end', round = 1, startsInMs = 0 }))
    local s2 = Renderer.getActiveScene()
    local t2 = s2.t0
    assert(Renderer.onFrames({
        matchId = 'm-lost-end', round = 1, seq = 1, last = true,
        frames = {
            { 0, -300, 0, 2500, 0, 0, 300, 0, 2500, 0, 0 },
            { 6, -100, 0, 0, 255, Renderer.STATUS.STOPPED, 100, 0, 1800, 10, Renderer.STATUS.SPINNING },
        },
    }))
    assert(Renderer.tick(t2 + 300) == true)
    assert(s2.lastFrameReachedAtMs == t2 + 300)
    assert(Renderer.tick(t2 + 5400) == false, 'must cleanup when roundEnd is lost after last=true')
    assert(Renderer.getActiveScene() == nil)

    -- 6. Réception hors ordre (seq=2 puis seq=1) et gel sur trou de tranche manquante (D05)
    assert(Renderer.onMatch({
        matchId = 'm-ooo',
        dt = 1.0 / 120.0,
        keyframeEvery = 6,
        arena = arena,
        tops = { { r = 0.05, label = 'Alpha', dir = 1 }, { r = 0.05, label = 'Beta', dir = -1 } },
    }))
    assert(Renderer.onCountdown({ matchId = 'm-ooo', round = 1, startsInMs = 0 }))
    assert(Renderer.onFrames({
        matchId = 'm-ooo', round = 1, seq = 1, last = false,
        frames = {
            { 0, -300, 0, 2500, 0, 0, 300, 0, 2500, 0, 0 },
            { 6, -200, 0, 2400, 5, 0, 200, 0, 2400, 5, 0 },
        },
        events = { { s = 5, t = 'hit', a = 1, b = 2, x = 0, y = 0, k = 80 } },
    }) == true)
    assert(Renderer.onFrames({
        matchId = 'm-ooo', round = 1, seq = 3, last = false,
        frames = {
            { 66, -100, 0, 2300, 10, 0, 100, 0, 2300, 10, 0 },
            { 72,  -50, 0, 2200, 20, 0,  50, 0, 2200, 20, 0 },
        },
        events = { { s = 68, t = 'hit', a = 1, b = 2, x = 0, y = 0, k = 120 } },
    }) == true)
    local s3 = Renderer.getActiveScene()
    -- Tant que la tranche seq=2 (pas 12..60) manque, une lecture au pas 30 gèle au pas 6 (starving=true)
    local gapInterp, gapStarving = Renderer.interpolateAtStep(s3.frames, 30.0, false, 24)
    assert(gapStarving == true and gapInterp.step == 6, 'must freeze at step 6 across missing slice gap')
    Renderer.cleanup('selftest_ooo_done')

    -- 7. Phase 2 : multi-manches, rejet ancienne manche, countdown avant en-tête, spectateur en cours et matchEnd 5s
    assert(Renderer.onCountdown({ matchId = 'm-bo3', round = 1, startsInMs = 2500 }) == false, 'countdown before match cached')
    assert(Renderer.onMatch({
        matchId = 'm-bo3', round = 1, bestOf = 3, score = { 0, 0 },
        role = 'participant', side = 1, names = { 'Alice', 'Bob' },
        arena = arena, tops = { { r = 0.05, label = 'Alpha', dir = 1 }, { r = 0.05, label = 'Beta', dir = 1 } },
    }) == true)
    local sm = Renderer.getActiveScene()
    assert(sm.t0 ~= nil and sm.round == 1 and sm.score[1] == 0 and sm.names[1] == 'Alice', 'adopted cached countdown & metadata')
    assert(Renderer.onRoundEnd({ matchId = 'm-bo3', round = 1, winner = 1, reason = 'spin_out', step = 120, score = { 1, 0 } }) == true)
    assert(sm.score[1] == 1 and sm.state == 'ended')
    -- Manche 2 : nouvel en-tête réinitialise les buffers mais conserve le match et met à jour le score
    assert(Renderer.onMatch({
        matchId = 'm-bo3', round = 2, bestOf = 3, score = { 1, 0 }, startsInMs = 3000,
        role = 'participant', side = 1, names = { 'Alice', 'Bob' },
        arena = arena, tops = { { r = 0.05, label = 'Alpha', dir = 1 }, { r = 0.05, label = 'Beta', dir = 1 } },
    }) == true)
    assert(sm.round == 2 and sm.state == 'countdown' and #sm.frames == 0 and sm.score[1] == 1)
    -- Une ancienne manche 1 arrivée en retard est rejetée
    assert(Renderer.onMatch({ matchId = 'm-bo3', round = 1, startsInMs = 1000, arena = arena }) == false, 'stale round 1 rejected')
    assert(Renderer.onCountdown({ matchId = 'm-bo3', round = 1, startsInMs = 1000 }) == false, 'stale round 1 countdown rejected')
    -- Fin du match : bannière maintenue 5 s puis nettoyée
    assert(Renderer.onMatchEnd({ matchId = 'm-bo3', winner = 1, reason = 'rounds', score = { 2, 0 }, names = { 'Alice', 'Bob' } }) == true)
    assert(sm.state == 'match_ended' and sm.score[1] == 2)
    local endMs = sm.matchEndedAtMs
    assert(Renderer.tick(endMs + 4000) == true, 'banner still visible at 4s')
    assert(Renderer.tick(endMs + 5100) == false, 'cleaned up after 5s matchEnd hold')
    assert(Renderer.getActiveScene() == nil)

    return true
end

return Renderer
