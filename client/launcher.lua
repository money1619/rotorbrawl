-- SPIN ARENA — Lanceur en main : props (lanceur à poignée pistolet, toupie suspendue sous ses griffes, cordon de
-- tirette) et animations. Fichier : client/launcher.lua
-- Seul le joueur qui lance voit ces props : ils sont locaux (CreateObject non réseau), comme ceux de la cuvette.
-- Déroulé d'une manche (chaque étape est annoncée par client/launch.lua et client/renderer.lua) :
--   préparation  lanceur dans la main droite, toupie accrochée sous les griffes, posture de préparation
--   prise        (ESPACE tenu) le cordon sort de la tirette arrière et se tend ; trop longtemps, il retombe
--   tirage       (ESPACE relâché) le cordon claque, la toupie s'emballe sur son support
--   GO           la toupie quitte les griffes et vole jusqu'à son point de départ dans la cuvette
-- Animations de personnage : uniquement des dictionnaires déjà utilisés par des ressources du serveur :
--   Préparation : dict = 'weapons@projectile@', clip = 'idle', flag = 49 (hotdogfart/config.lua)
--   Lancement   : dict = 'anim@heists@narcotics@trash', clip = 'throw_b', flag = 48 (geste de lancer vers l'avant et
--                 le bas : aeom_petitsboulots/jobs/eboueur.lua, uw_needs/client/util.lua), chargé dès la préparation ;
--                 repli : dict = 'mp_common', clip = 'givetake1_a' (l'ancien geste « donner ») si le premier manque
--   Os main droite : 28422 (PH_R_Hand)
-- Ces animations jouées sur son propre personnage sont vues des autres joueurs ; les props, eux, sont locaux :
-- client/launcher_rivals.lua affiche chez chacun le lanceur des AUTRES participants.
-- Le cordon est tracé par DrawLine (aucun modèle de cordon n'existe) ; l'orientation des props dans la main ne se
-- vérifie qu'en jeu : /spin_prop (voir plus bas) règle et rejoue tout sans lancer de match.

SpinArena = SpinArena or {}

local Launcher = {
    state        = 'idle', -- 'idle' | 'preparing' | 'launched'
    stage        = 'idle', -- 'idle' | 'ready' | 'tension' | 'pulled' | 'flying' | 'landed'
    matchId      = nil,
    round        = nil,
    handProp     = nil,    -- le lanceur (ou, avec PROPS.enabled = false, la toupie seule : ancien comportement)
    topProp      = nil,    -- la toupie accrochée sous les griffes
    animPlaying  = false,
    flying       = false,  -- la toupie vole vers la cuvette : le rendu masque alors celle de la cuvette
    topModelName = nil,
    loadedDicts  = {},
    loadedModels = {},
    history      = {},
    token        = 0,      -- change à chaque nettoyage : arrête les fils et minuteries d'une manche précédente
}
SpinArena.Launcher = Launcher

Launcher.ANIMS = {
    -- Pose à deux mains tendues devant (perceuse des braquages) : retenue après l'essai /spin_autotest anims
    prepare = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 49, duration = -1  },
    prepareFallback = { dict = 'weapons@projectile@', clip = 'idle', flag = 49, duration = -1 },
    launch  = { dict = 'anim@heists@narcotics@trash', clip = 'throw_b', flag = 48, duration = 1100 },
    launchFallback = { dict = 'mp_common',    clip = 'givetake1_a', flag = 48, duration = 900 },
}

Launcher.HAND_BONE = 28422

-- Réglages des props. Le modèle du lanceur (tools/models/build_launcher.py) a son origine au bas de la poignée,
-- l'avant vers +Y, l'axe du corps à z = 0,075 m, les griffes sous l'avant (y = 0,030 m) et la tirette arrière à
-- y = −0,0785 m. Le repère de l'os de la main ne se devine pas hors jeu : `hand` est à AFFINER avec /spin_prop.
Launcher.PROPS = {
    enabled       = true,   -- false : ancien comportement (la toupie seule dans la main, sans lanceur ni cordon)
    launcherModel = 'spin_launcher',
    hand  = { x = 0.02, y = 0.02, z = -0.02, rx = 0.0, ry = 0.0, rz = 180.0 },   -- 29/10 : trouvé par /spin_autotest calibrate en jeu dans la bonne pose (score 2,99 sur 3) : avant vers l'avant du ped, dessus vers le haut   -- décalage (m) et rotation (°) dans l'os
    mount = { y = 0.030, topZ = 0.030, topHeight = 0.045 },   -- sommet de la toupie sous les griffes ; hauteur de repli
    cord  = { length = 0.32, tabY = -0.0785, tabZ = 0.075, r = 255, g = 122, b = 26, snapMs = 120, sag = 0.03 },
    spin  = { maxRps = 14.0, friction = 0.55 },   -- tours/s visuels au meilleur lancer ; part de vitesse perdue par seconde
    shake = 0.0014,         -- tremblement du lanceur à pleine tension (m)
    kick  = { y = -0.030, z = 0.012, ms = 180 },   -- recul du lanceur au tirage (m, vers l'arrière et le haut)
    flightMs = 240, arc = 0.12,   -- envol vers la cuvette : durée et hauteur de l'arc (m), à courte distance
    flightPerMeterMs = 45.0, flightMaxMs = 1400.0,   -- plus loin : +45 ms par mètre, 1,4 s au plus
    -- Main gauche : tire le cordon par cinématique inverse (SetIkTarget), cible = poignée du cordon. index : 3 = bras gauche.
    ik = { enabled = true, index = 3, blendMs = 120 },
    keepLauncherMs = 900,
    keepPoseOnLaunch = true,   -- la pose à deux mains reste pendant l'envol (le geste de lancer balançait le bras de côté)   -- le lanceur reste en main le temps du geste de lancement
}

local GRADE_SPIN = { perfect = 1.0, good = 0.8, fair = 0.6, weak = 0.4 }

local function isTruthy(v)
    return v == true or v == 1
end

local function timer()
    return (type(GetGameTimer) == 'function' and GetGameTimer()) or 0
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function resolveModelHash(modelName)
    if type(modelName) == 'number' then return modelName end
    if type(modelName) ~= 'string' or modelName == '' then return nil end
    if type(joaat) == 'function' then return joaat(modelName) end
    if type(GetHashKey) == 'function' then return GetHashKey(modelName) end
    return nil
end

local function ensureAnimDict(dict)
    if type(RequestAnimDict) ~= 'function' then
        return false
    end
    if type(HasAnimDictLoaded) == 'function' and isTruthy(HasAnimDictLoaded(dict)) then
        Launcher.loadedDicts[dict] = true
        return true
    end
    pcall(RequestAnimDict, dict)
    Launcher.loadedDicts[dict] = true
    if type(HasAnimDictLoaded) == 'function' then
        return isTruthy(HasAnimDictLoaded(dict))
    end
    return true
end

local function deleteProp(prop)
    if not prop or prop == 0 then return end
    if SpinArena.TopModel then SpinArena.TopModel.dropChildren(prop) end   -- toupie assemblée : ses pièces d'abord
    if type(DoesEntityExist) == 'function' and not isTruthy(DoesEntityExist(prop)) then
        return
    end
    if type(DetachEntity) == 'function' then
        pcall(DetachEntity, prop, true, true)
    end
    if type(DeleteEntity) == 'function' then
        pcall(DeleteEntity, prop)
    elseif type(DeleteObject) == 'function' then
        pcall(DeleteObject, prop)
    end
end

local function detachAndDeleteHandProp()
    local prop, top = Launcher.handProp, Launcher.topProp
    Launcher.handProp, Launcher.topProp = nil, nil
    deleteProp(top)       -- la toupie d'abord : elle est attachée au lanceur
    deleteProp(prop)
end

local function pedId()
    return (type(PlayerPedId) == 'function') and PlayerPedId() or 0
end

-- Crée un prop local au niveau du joueur ; nil si le modèle n'est pas (encore) disponible : l'appelant réessaie
local function spawnProp(ped, modelName)
    if type(CreateObject) ~= 'function' or not ped or ped == 0 then
        return nil
    end
    local hash = resolveModelHash(modelName)
    if not hash or hash == 0 then return nil end

    if type(IsModelInCdimage) == 'function' and not isTruthy(IsModelInCdimage(hash)) then
        return nil
    end
    if type(RequestModel) == 'function' then
        pcall(RequestModel, hash)
        Launcher.loadedModels[hash] = true
    end
    if type(HasModelLoaded) == 'function' and not isTruthy(HasModelLoaded(hash)) then
        return nil
    end

    local cx, cy, cz = 0.0, 0.0, 0.0
    if type(GetEntityCoords) == 'function' then
        local c = GetEntityCoords(ped)
        if type(c) == 'table' or type(c) == 'userdata' then
            cx = tonumber(c.x or c[1]) or 0.0
            cy = tonumber(c.y or c[2]) or 0.0
            cz = tonumber(c.z or c[3]) or 0.0
        end
    end

    local ok, obj = pcall(CreateObject, hash, cx, cy, cz, false, false, false)
    if type(SetModelAsNoLongerNeeded) == 'function' then
        pcall(SetModelAsNoLongerNeeded, hash)
        Launcher.loadedModels[hash] = nil
    end
    if not ok or not obj or obj == 0 then
        return nil
    end
    if type(SetEntityCollision) == 'function' then
        pcall(SetEntityCollision, obj, false, false)
    end
    return obj
end

-- (Re)fixe le lanceur à la main droite ; jx, jy, jz : tremblement du moment (m)
local function attachLauncher(jx, jy, jz)
    local obj, ped = Launcher.handProp, pedId()
    if not obj or type(AttachEntityToEntity) ~= 'function' or not ped or ped == 0 then return end
    local boneIdx = Launcher.HAND_BONE
    if type(GetPedBoneIndex) == 'function' then
        boneIdx = GetPedBoneIndex(ped, Launcher.HAND_BONE) or Launcher.HAND_BONE
    end
    local H = Launcher.PROPS.hand
    pcall(
        AttachEntityToEntity,
        obj, ped, boneIdx,
        H.x + (jx or 0.0), H.y + (jy or 0.0), H.z + (jz or 0.0),
        H.rx, H.ry, H.rz,
        true, true, false, true, 1, true
    )
end

-- Fixe la toupie sous les griffes du lanceur, tournée de `ang` degrés autour de son axe
local function mountTop(ang)
    local top, launcher = Launcher.topProp, Launcher.handProp
    if not top or not launcher or type(AttachEntityToEntity) ~= 'function' then return end
    local M = Launcher.PROPS.mount
    pcall(
        AttachEntityToEntity,
        top, launcher, 0,
        0.0, M.y, M.topZ - (Launcher.topMaxZ or M.topHeight),
        0.0, 0.0, ang or 0.0,
        false, false, false, false, 2, true
    )
end

-- Hauteur du modèle de toupie : l'origine est la pointe (bas), le sommet du noyau est à max.z
local function readTopMaxZ(modelName)
    local hash = resolveModelHash(modelName)
    if hash and type(GetModelDimensions) == 'function' then
        local ok, mn, mx = pcall(GetModelDimensions, hash)
        local top = ok and mx and tonumber(mx.z or mx[3])
        if top and top > 0.01 and top < 0.2 then return top end
    end
    return Launcher.PROPS.mount.topHeight
end

-- Crée ce qui manque (le chargement des modèles est asynchrone : réessayé à chaque passage du fil d'animation)
local function ensureProps()
    local ped = pedId()
    if not ped or ped == 0 then return end
    local P = Launcher.PROPS
    if not P.enabled then
        if not Launcher.handProp then
            -- Ancien comportement : la toupie seule dans la main
            local obj = spawnProp(ped, Launcher.topModelName or 'spin_launcher')
            if obj then
                Launcher.handProp = obj
                if type(AttachEntityToEntity) == 'function' then
                    local boneIdx = Launcher.HAND_BONE
                    if type(GetPedBoneIndex) == 'function' then boneIdx = GetPedBoneIndex(ped, Launcher.HAND_BONE) or boneIdx end
                    pcall(AttachEntityToEntity, obj, ped, boneIdx, 0.02, 0.02, -0.02, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
                end
            end
        end
        return
    end
    if not Launcher.handProp then
        local obj = spawnProp(ped, P.launcherModel)
        if obj then
            Launcher.handProp = obj
            attachLauncher()
        end
    end
    if Launcher.handProp and not Launcher.topProp and Launcher.topModelName then
        local TM = SpinArena.TopModel
        local obj
        if TM then
            obj = TM.spawn({ model = Launcher.topModelName, parts = Launcher.topParts }, function(m) return spawnProp(ped, m) end)
        else
            obj = spawnProp(ped, Launcher.topModelName)
        end
        if obj then
            Launcher.topProp = obj
            Launcher.topMaxZ = (TM and Launcher.topParts and TM.height(Launcher.topParts)) or readTopMaxZ(Launcher.topModelName)
            Launcher.spinAng = Launcher.spinAng or 0.0
            mountTop(Launcher.spinAng)
        end
    end
end

-- Point du lanceur (repère local) en coordonnées du monde
local function launcherPoint(ox, oy, oz)
    local v = GetOffsetFromEntityInWorldCoords(Launcher.handProp, ox, oy, oz)
    return tonumber(v.x or v[1]) or 0.0, tonumber(v.y or v[2]) or 0.0, tonumber(v.z or v[3]) or 0.0
end

-- Cordon : deux brins parallèles de la tirette arrière à la poignée, mou quand la tension est faible
local function drawCord()
    if type(DrawLine) ~= 'function' or type(GetOffsetFromEntityInWorldCoords) ~= 'function' or not Launcher.handProp then return end
    local C, len = Launcher.PROPS.cord, Launcher.cordLen or 0.0
    if len < 0.002 then return end
    local sag = C.sag * (1.0 - clamp(Launcher.tension or 1.0, 0.0, 1.0))
    local segments = 6
    for _, dx in ipairs({ -0.0012, 0.0012 }) do
        local px, py, pz = launcherPoint(dx, C.tabY, C.tabZ)
        for i = 1, segments do
            local s = i / segments
            local x, y, z = launcherPoint(dx, C.tabY - len * s, C.tabZ - sag * 4.0 * s * (1.0 - s))
            DrawLine(px, py, pz, x, y, z, C.r, C.g, C.b, 255)
            px, py, pz = x, y, z
        end
    end
    if type(DrawMarker) == 'function' then   -- la poignée du cordon : petite sphère au bout
        local hx, hy, hz = launcherPoint(0.0, C.tabY - len, C.tabZ)
        DrawMarker(28, hx, hy, hz, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.016, 0.016, 0.016, C.r, C.g, C.b, 255,
            false, false, 2, false, nil, nil, false)
    end
end

-- La main gauche suit la poignée du cordon (renouvelé à chaque image : l'effet expire de lui-même)
local function pullWithLeftHand()
    local K = Launcher.PROPS.ik
    if not K or not K.enabled or type(SetIkTarget) ~= 'function' or not Launcher.handProp then return end
    local C, len = Launcher.PROPS.cord, Launcher.cordLen or 0.0
    local x, y, z = launcherPoint(0.0, C.tabY - len, C.tabZ)
    pcall(SetIkTarget, pedId(), K.index, 0, 0, x, y, z, 0, K.blendMs, K.blendMs)
end

local function finishFlight()
    deleteProp(Launcher.topProp)
    Launcher.topProp = nil
    Launcher.flying = false
    Launcher.flight = nil
    Launcher.stage = 'landed'
end

-- Une image d'animation : cordon, tremblement, rotation de la toupie, envol
local function frame(t, dt)
    local P = Launcher.PROPS
    if not P.enabled then return end
    -- Les props se recréent seulement avant le GO : après l'envol, les ranger est voulu
    if Launcher.state == 'preparing' then
        ensureProps()
        -- Le dictionnaire de la pose à deux mains se charge après la demande : tant que la pose de repli (grenade) joue,
        -- on réessaie, sinon la main et le lanceur ne sont pas dans la bonne pose (29/10 : calibration faussée)
        local prep = Launcher.ANIMS.prepare
        if Launcher.poseFallback and type(HasAnimDictLoaded) == 'function' and isTruthy(HasAnimDictLoaded(prep.dict))
            and type(TaskPlayAnim) == 'function' then
            Launcher.poseFallback = false
            pcall(TaskPlayAnim, pedId(), prep.dict, prep.clip, 8.0, -8.0, prep.duration, prep.flag, 0.0, false, false, false)
        end
    end
    local stage = Launcher.stage

    if stage == 'tension' then
        local pull = Launcher.pull or {}
        local maxMs, fadeMs = tonumber(pull.maxMs) or 450, tonumber(pull.fadeMs) or 600
        local held = t - (Launcher.gripAt or t)
        -- Même courbe que la jauge de tirage : le cordon se tend jusqu'à pullMaxMs, puis retombe
        local s
        if held <= maxMs then
            local k = clamp(held / maxMs, 0.0, 1.0)
            s = 1.0 - (1.0 - k) * (1.0 - k)
        else
            s = 1.0 - 0.45 * clamp((held - maxMs) / fadeMs, 0.0, 1.0)
        end
        Launcher.tension = s
        Launcher.cordLen = P.cord.length * s
        local amp = P.shake * s
        attachLauncher((math.random() - 0.5) * 2.0 * amp, (math.random() - 0.5) * 2.0 * amp, (math.random() - 0.5) * 2.0 * amp)
        drawCord()
        pullWithLeftHand()
    elseif stage == 'pulled' then
        local k = clamp((t - (Launcher.pullAt or t)) / P.cord.snapMs, 0.0, 1.0)
        Launcher.tension = 1.0
        Launcher.cordLen = (Launcher.cordFrom or 0.0) * (1.0 - k) * (1.0 - k)   -- le cordon se rembobine d'un coup
        -- Recul : le lanceur part en arrière d'un coup puis revient en place
        local r = 1.0 - clamp((t - (Launcher.pullAt or t)) / P.kick.ms, 0.0, 1.0)
        attachLauncher(0.0, P.kick.y * r * r, P.kick.z * r * r)
        drawCord()
        pullWithLeftHand()
    end

    -- La toupie tourne sur son support (ou en vol) ; la vitesse retombe par frottement
    if (stage == 'pulled' or stage == 'flying') and Launcher.topProp then
        Launcher.rps = (Launcher.rps or 0.0) * math.max(0.0, 1.0 - P.spin.friction * dt)
        Launcher.spinAng = ((Launcher.spinAng or 0.0) + (Launcher.spinDir or 1) * Launcher.rps * 360.0 * dt) % 360.0
        if stage == 'pulled' then mountTop(Launcher.spinAng) end
    end

    if stage == 'flying' and Launcher.flight and Launcher.topProp then
        local f = Launcher.flight
        local k = clamp((t - f.startAt) / (f.duration or P.flightMs), 0.0, 1.0)
        local tx, ty, tz = f.fx, f.fy, f.fz
        local target = f.targetFn and f.targetFn()
        if target and target ~= 0 and type(GetEntityCoords) == 'function' then
            local c = GetEntityCoords(target)
            tx, ty, tz = tonumber(c.x or c[1]) or tx, tonumber(c.y or c[2]) or ty, tonumber(c.z or c[3]) or tz
        end
        local e = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
        local x = f.sx + (tx - f.sx) * e
        local y = f.sy + (ty - f.sy) * e
        local z = f.sz + (tz - f.sz) * e + (f.arc or P.arc) * math.sin(math.pi * k)
        if type(SetEntityCoordsNoOffset) == 'function' then
            pcall(SetEntityCoordsNoOffset, Launcher.topProp, x, y, z, false, false, false)
        end
        if type(SetEntityRotation) == 'function' then
            pcall(SetEntityRotation, Launcher.topProp, 0.0, 0.0, Launcher.spinAng or 0.0, 2, true)
        end
        if k >= 1.0 then finishFlight() end
    end
end

-- Fil d'animation : tourne tant qu'une manche est en cours, à chaque image seulement quand quelque chose bouge
local function ensureThread()
    if Launcher.threadRunning or type(CreateThread) ~= 'function' then return end
    Launcher.threadRunning = true
    local token = Launcher.token
    CreateThread(function()
        local last = timer()
        while Launcher.token == token and Launcher.state ~= 'idle' do
            local t = timer()
            local dt = clamp((t - last) / 1000.0, 0.0, 0.1)
            last = t
            local ok, err = pcall(frame, t, dt)
            if not ok and type(print) == 'function' then print(('[spin_arena] animation du lanceur : %s'):format(tostring(err))) end
            local moving = Launcher.stage == 'tension' or Launcher.stage == 'pulled' or Launcher.stage == 'flying'
            Wait(moving and 0 or 120)
        end
        if Launcher.token == token then Launcher.threadRunning = false end
    end)
end

-- Démarre (ou reprend après chargement différé du modèle/dictionnaire) la posture de préparation
-- dir : sens de rotation de sa toupie (1, ou -1 avec l'anneau inversé), pour l'emballement sur le lanceur
function Launcher.onCountdownStart(matchId, round, role, topModelName, dir, topParts)
    if role ~= 'participant' then
        return false
    end
    Launcher.spinDir = (tonumber(dir) == -1) and -1 or 1
    local isSameRound = (Launcher.state == 'preparing' and Launcher.matchId == matchId and Launcher.round == round)
    if isSameRound and Launcher.handProp ~= nil and Launcher.animPlaying then
        return true
    end

    if not isSameRound then
        detachAndDeleteHandProp()
        Launcher.animPlaying  = false
        Launcher.matchId      = matchId
        Launcher.round        = round
        Launcher.state        = 'preparing'
        Launcher.stage        = 'ready'
        Launcher.topModelName = topModelName or Launcher.topModelName or 'spin_top_balance'
        Launcher.topParts     = topParts
        Launcher.cordLen, Launcher.tension, Launcher.rps, Launcher.spinAng, Launcher.pull = 0.0, 0.0, 0.0, 0.0, nil
        Launcher.history[#Launcher.history + 1] = {
            action  = 'prepare',
            matchId = matchId,
            round   = round,
            dict    = Launcher.ANIMS.prepare.dict,
            clip    = Launcher.ANIMS.prepare.clip,
        }
    elseif topModelName then
        Launcher.topModelName = topModelName
    end

    local ped = pedId()
    if ped and ped ~= 0 then
        ensureProps()
        ensureAnimDict(Launcher.ANIMS.launch.dict)   -- chargé d'avance : au GO, il n'y a pas d'image d'attente
        if not Launcher.animPlaying then
            local anim = Launcher.ANIMS.prepare
            Launcher.poseFallback = false
            if not ensureAnimDict(anim.dict) then anim = Launcher.ANIMS.prepareFallback; Launcher.poseFallback = true end
            if ensureAnimDict(anim.dict) and type(TaskPlayAnim) == 'function' then
                pcall(
                    TaskPlayAnim,
                    ped, anim.dict, anim.clip,
                    8.0, -8.0, anim.duration, anim.flag,
                    0.0, false, false, false
                )
                Launcher.animPlaying = true
            end
        end
    end
    ensureThread()
    return true
end

-- Tirette saisie (ESPACE tenu) : le cordon sort et se tend. pull = { minMs, maxMs, fadeMs } annoncé par le serveur.
function Launcher.onGrip(matchId, round, pull)
    -- Seulement pour la manche en préparation : une réponse tardive d'un match terminé ne doit rien recréer
    if Launcher.state ~= 'preparing' or Launcher.matchId ~= matchId or Launcher.round ~= round then return false end
    Launcher.history[#Launcher.history + 1] = { action = 'grip', matchId = matchId, round = round }
    Launcher.pull = type(pull) == 'table' and pull or nil
    Launcher.gripAt = timer()
    Launcher.stage = 'tension'
    ensureThread()
    return true
end

-- Tirage (ESPACE relâché) : le cordon claque, la toupie s'emballe sur son support ; la vitesse définitive suit
-- la qualité renvoyée par le serveur (onResult)
function Launcher.onPull(matchId, round)
    if Launcher.state ~= 'preparing' or Launcher.matchId ~= matchId or Launcher.round ~= round then return false end
    Launcher.history[#Launcher.history + 1] = { action = 'pull', matchId = matchId, round = round }
    Launcher.cordFrom = Launcher.cordLen or 0.0
    Launcher.pullAt = timer()
    Launcher.spinTarget = Launcher.spinTarget or 0.7
    Launcher.rps = Launcher.spinTarget * Launcher.PROPS.spin.maxRps
    Launcher.stage = 'pulled'
    ensureThread()
    return true
end

-- Qualité du lancer renvoyée par le serveur : règle la vitesse d'emballement de la toupie (affichage seulement)
function Launcher.onResult(grade)
    Launcher.spinTarget = GRADE_SPIN[grade] or 0.7
    if Launcher.stage == 'pulled' or Launcher.stage == 'flying' then
        Launcher.rps = Launcher.spinTarget * Launcher.PROPS.spin.maxRps
    end
    return true
end

-- Prise refusée ou réarmement : le cordon se rembobine, la manche reste en préparation
function Launcher.onReset(matchId, round)
    if Launcher.state ~= 'preparing' or Launcher.matchId ~= matchId or Launcher.round ~= round then return false end
    Launcher.stage, Launcher.cordLen, Launcher.tension, Launcher.rps = 'ready', 0.0, 0.0, 0.0
    return true
end

-- Envol de la toupie du support vers son point de départ dans la cuvette. targetFn() renvoie le prop de la cuvette
-- (créé par le rendu) ou nil : sans lui, la toupie retombe devant le joueur.
local function startFlight(targetFn)
    local top = Launcher.topProp
    if not top or type(GetEntityCoords) ~= 'function' then return false end
    local c = GetEntityCoords(top)
    local sx, sy, sz = tonumber(c.x or c[1]) or 0.0, tonumber(c.y or c[2]) or 0.0, tonumber(c.z or c[3]) or 0.0
    local fx, fy, fz = sx, sy, sz - 0.6
    local ped = pedId()
    if type(GetOffsetFromEntityInWorldCoords) == 'function' and ped and ped ~= 0 then
        local v = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, -0.6)
        fx, fy, fz = tonumber(v.x or v[1]) or fx, tonumber(v.y or v[2]) or fy, tonumber(v.z or v[3]) or fz
    end
    if type(DetachEntity) == 'function' then pcall(DetachEntity, top, true, false) end
    -- DetachEntity(…, collision = true) rendait la toupie solide : elle blessait le ped en traversant ses pieds (29/10)
    if type(SetEntityCollision) == 'function' then pcall(SetEntityCollision, top, false, false) end
    -- Loin de la table, l'envol dure plus longtemps et monte plus haut : la toupie traverse la distance au lieu de
    -- se téléporter en 240 ms (29/10 : « je suis loin de la table »)
    local P = Launcher.PROPS
    local tx, ty, tz = fx, fy, fz
    local tgt = targetFn and targetFn()
    if tgt and tgt ~= 0 and type(GetEntityCoords) == 'function' then
        local tc = GetEntityCoords(tgt)
        tx, ty, tz = tonumber(tc.x or tc[1]) or tx, tonumber(tc.y or tc[2]) or ty, tonumber(tc.z or tc[3]) or tz
    end
    local dist = math.sqrt((tx - sx) ^ 2 + (ty - sy) ^ 2 + (tz - sz) ^ 2)
    local duration = clamp(P.flightMs + dist * (P.flightPerMeterMs or 45.0), P.flightMs, P.flightMaxMs or 1400.0)
    local arc = clamp(P.arc + dist * 0.03, P.arc, 0.9)
    Launcher.flight = { startAt = timer(), sx = sx, sy = sy, sz = sz, fx = fx, fy = fy, fz = fz, targetFn = targetFn,
        duration = duration, arc = arc }
    Launcher.flying, Launcher.stage = true, 'flying'
    Launcher.rps = math.max(Launcher.rps or 0.0, 0.4 * Launcher.PROPS.spin.maxRps)   -- une toupie lancée tourne toujours
    return true
end

-- Déclenche le geste de lancement à l'instant GO : la toupie quitte les griffes, le lanceur reste en main le temps du geste
function Launcher.onLaunchGo(matchId, round, role, targetFn)
    if role ~= 'participant' and Launcher.state ~= 'preparing' then
        return false
    end
    if Launcher.state == 'launched' and Launcher.matchId == matchId and Launcher.round == round then
        return false
    end

    Launcher.animPlaying = false
    Launcher.matchId     = matchId or Launcher.matchId
    Launcher.round       = round or Launcher.round
    Launcher.state       = 'launched'
    Launcher.history[#Launcher.history + 1] = {
        action  = 'launch',
        matchId = Launcher.matchId,
        round   = Launcher.round,
        dict    = Launcher.ANIMS.launch.dict,
        clip    = Launcher.ANIMS.launch.clip,
    }

    local P = Launcher.PROPS
    if P.enabled and Launcher.topProp and startFlight(targetFn) then
        local token = Launcher.token
        if type(SetTimeout) == 'function' then
            SetTimeout(math.max(P.keepLauncherMs, math.floor((Launcher.flight and Launcher.flight.duration or 0) + 100)), function()
                if Launcher.token == token and Launcher.handProp then
                    deleteProp(Launcher.handProp)
                    Launcher.handProp = nil
                end
                if Launcher.token == token and P.keepPoseOnLaunch and type(StopAnimTask) == 'function' then
                    for _, a in pairs({ Launcher.ANIMS.prepare, Launcher.ANIMS.prepareFallback }) do
                        pcall(StopAnimTask, pedId(), a.dict, a.clip, 2.0)
                    end
                end
            end)
        end
    else
        detachAndDeleteHandProp()
        Launcher.stage = 'landed'
    end

    local ped = pedId()
    if ped and ped ~= 0 and not (P.enabled and P.keepPoseOnLaunch and Launcher.stage == 'flying') then
        local prep = Launcher.ANIMS.prepare
        if type(StopAnimTask) == 'function' then
            pcall(StopAnimTask, ped, prep.dict, prep.clip, 2.0)
        end
        local anim = Launcher.ANIMS.launch
        if not ensureAnimDict(anim.dict) then anim = Launcher.ANIMS.launchFallback end
        if ensureAnimDict(anim.dict) and type(TaskPlayAnim) == 'function' then
            pcall(
                TaskPlayAnim,
                ped, anim.dict, anim.clip,
                8.0, -8.0, anim.duration, anim.flag,
                0.0, false, false, false
            )
            Launcher.launchAnim = anim.dict
        end
    end
    ensureThread()
    return true
end

-- Nettoyage complet (fin de manche, fin de match, annulation, arrêt de ressource)
function Launcher.cleanup()
    local ownsAnimation = Launcher.state ~= 'idle' or Launcher.animPlaying == true
    Launcher.token = Launcher.token + 1
    Launcher.threadRunning = false
    detachAndDeleteHandProp()
    Launcher.animPlaying  = false
    Launcher.topModelName = nil
    Launcher.topParts = nil
    Launcher.flying, Launcher.flight, Launcher.pull = false, nil, nil
    Launcher.stage, Launcher.cordLen, Launcher.tension, Launcher.rps, Launcher.spinTarget = 'idle', 0.0, 0.0, 0.0, nil
    Launcher.spinDir = 1
    Launcher.poseFallback = false
    local ped = pedId()
    if ownsAnimation and ped and ped ~= 0 then
        if type(StopAnimTask) == 'function' then
            for _, anim in pairs(Launcher.ANIMS) do
                pcall(StopAnimTask, ped, anim.dict, anim.clip, 2.0)
            end
        end
    end
    if type(RemoveAnimDict) == 'function' then
        for dict in pairs(Launcher.loadedDicts) do
            pcall(RemoveAnimDict, dict)
        end
    end
    Launcher.loadedDicts = {}

    if type(SetModelAsNoLongerNeeded) == 'function' then
        for hash in pairs(Launcher.loadedModels) do
            pcall(SetModelAsNoLongerNeeded, hash)
        end
    end
    Launcher.loadedModels = {}
    Launcher.state   = 'idle'
    Launcher.matchId = nil
    Launcher.round   = nil
    return true
end

function Launcher.getState()
    return {
        active      = Launcher.state ~= 'idle',
        phase       = Launcher.state,
        stage       = Launcher.stage,
        matchId     = Launcher.matchId,
        round       = Launcher.round,
        handProp    = Launcher.handProp,
        topProp     = Launcher.topProp,
        animPlaying = Launcher.animPlaying,
        flying      = Launcher.flying,
        cordLen     = Launcher.cordLen,
    }
end

-- Partagé avec client/launcher_rivals.lua (lanceurs des autres participants) : mêmes modèles, mêmes réglages
Launcher.spawnProp = spawnProp
Launcher.deleteProp = deleteProp
Launcher.readTopMaxZ = readTopMaxZ

-- Démonstration hors match : rejoue prise, tirage et envol sur place (réglage des props, essai de l'animation).
-- Refusée pendant un vrai match. La toupie retombe devant le joueur, faute de cuvette.
function Launcher.demo(topModelName)
    if Launcher.state ~= 'idle' then return false end
    local id = 'demo'
    local token = Launcher.token   -- tout nettoyage (fin de la démonstration, vrai match) change le jeton et l'arrête
    Launcher.onCountdownStart(id, 0, 'participant', topModelName or 'spin_top_balance')
    local timeline = {
        { 900, function() Launcher.onGrip(id, 0, { minMs = 150, maxMs = 450, fadeMs = 600 }) end },
        { 430, function() Launcher.onPull(id, 0) end },
        { 350, function() Launcher.onResult('perfect') end },
        { 900, function() Launcher.onLaunchGo(id, 0, 'participant', nil) end },
        { 1700, function() if Launcher.matchId == id then Launcher.cleanup() end end },
    }
    if type(CreateThread) ~= 'function' then return true end
    CreateThread(function()
        for _, step in ipairs(timeline) do
            Wait(step[1])
            if Launcher.matchId ~= id or Launcher.token ~= token then return end   -- un vrai match ou un nettoyage a pris la main
            step[2]()
        end
    end)
    return true
end

-- /spin_prop : réglage des props en jeu, sans match.
--   /spin_prop demo               joue prise, tirage et envol
--   /spin_prop show | off         garde le lanceur en main, sans animation | le range
--   /spin_prop hand x y z rx ry rz   place le lanceur dans la main (m, °) et recolle tout de suite
--   /spin_prop mount y topZ       place la toupie sous les griffes (m, dans le repère du lanceur)
--   /spin_prop print              écrit les valeurs à recopier dans Launcher.PROPS (client/launcher.lua)
local function say(msg)
    if type(print) == 'function' then print('[spin_arena] ' .. msg) end
    if type(TriggerEvent) == 'function' then
        TriggerEvent('chat:addMessage', { args = { 'SPIN ARENA', msg } })
    end
end

local function numbers(args, from, count)
    local out = {}
    for i = 0, count - 1 do
        local v = tonumber(args[from + i])
        if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
        out[#out + 1] = v
    end
    return out
end

local function propCommand(args)
    local sub = args[1]
    if sub == 'demo' then
        if not Launcher.demo(args[2]) then return say('une manche est en cours : démonstration refusée') end
        return say('démonstration : prise, tirage puis envol')
    elseif sub == 'show' then
        if Launcher.state ~= 'idle' then return say('une manche est en cours') end
        Launcher.onCountdownStart('preview', 0, 'participant', args[2] or 'spin_top_balance')
        return say('lanceur en main (/spin_prop off pour le ranger)')
    elseif sub == 'off' then
        if Launcher.matchId == 'preview' or Launcher.matchId == 'demo' or Launcher.matchId == 'calib' then Launcher.cleanup() end
        return say('rangé')
    elseif sub == 'hand' then
        local n = numbers(args, 2, 6)
        if not n then return say('usage : /spin_prop hand x y z rx ry rz  (mètres et degrés)') end
        local H = Launcher.PROPS.hand
        H.x, H.y, H.z, H.rx, H.ry, H.rz = n[1], n[2], n[3], n[4], n[5], n[6]
        attachLauncher()
        return say('main : placé')
    elseif sub == 'rot' then
        local n = numbers(args, 2, 3)
        if not n then return say('usage : /spin_prop rot rx ry rz  (degrés, garde la position)') end
        local H = Launcher.PROPS.hand
        H.rx, H.ry, H.rz = n[1], n[2], n[3]
        attachLauncher()
        return say(('rotation : %.0f %.0f %.0f'):format(n[1], n[2], n[3]))
    elseif sub == 'flip' then
        -- Retourne le lanceur de 180° : rx (avant/arrière ET dessus/dessous), ry (dessus/dessous), rz (avant/arrière)
        local axis = args[2] or 'rx'
        local H = Launcher.PROPS.hand
        if axis ~= 'rx' and axis ~= 'ry' and axis ~= 'rz' then return say('usage : /spin_prop flip [rx|ry|rz]') end
        H[axis] = (H[axis] + 180.0) % 360.0
        attachLauncher()
        return say(('retourné : rx %.0f ry %.0f rz %.0f'):format(H.rx, H.ry, H.rz))
    elseif sub == 'mount' then
        local n = numbers(args, 2, 2)
        if not n then return say('usage : /spin_prop mount y topZ  (mètres, repère du lanceur)') end
        Launcher.PROPS.mount.y, Launcher.PROPS.mount.topZ = n[1], n[2]
        mountTop(Launcher.spinAng or 0.0)
        return say('toupie : placée')
    elseif sub == 'parts' then
        -- Essai A/B en jeu : toupie assemblée pièce par pièce (on) ou ancien modèle monobloc (off), au prochain lancer
        local TM = SpinArena.TopModel
        if not TM then return say('modèles de pièces indisponibles') end
        if args[2] == 'on' then TM.enabled = true elseif args[2] == 'off' then TM.enabled = false else return say('usage : /spin_prop parts on|off (actuellement ' .. (TM.enabled and 'on' or 'off') .. ')') end
        return say('toupie assemblée pièce par pièce : ' .. (TM.enabled and 'oui' or 'non (modèle monobloc)'))
    elseif sub == 'ik' then
        local K = Launcher.PROPS.ik
        if args[2] == 'off' then K.enabled = false return say('main gauche : cinématique inverse coupée') end
        local n = tonumber(args[2])
        if not n then return say('usage : /spin_prop ik <index du bras|off>  (essaie 3, puis 1, 2, 4 si le mauvais bras bouge)') end
        K.enabled, K.index = true, math.floor(n)
        return say('main gauche : index ' .. K.index)
    elseif sub == 'print' then
        local H, M = Launcher.PROPS.hand, Launcher.PROPS.mount
        say(('hand  = { x = %.3f, y = %.3f, z = %.3f, rx = %.1f, ry = %.1f, rz = %.1f },'):format(H.x, H.y, H.z, H.rx, H.ry, H.rz))
        return say(('mount = { y = %.3f, topZ = %.3f, topHeight = %.3f },'):format(M.y, M.topZ, M.topHeight))
    end
    say('/spin_prop demo | show | off | hand x y z rx ry rz | rot rx ry rz | flip [rx|ry|rz] | mount y topZ | ik n|off | parts on|off | print')
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('spin_prop', function(_, args) propCommand(args or {}) end, false)
end

-- /spin_autotest : essai automatique avec TON ped, sans toucher au clavier.
--   /spin_autotest        démonstration deux fois de suite (prise, tirage, claquement, envol), props relevés à 50 ms
--   /spin_autotest full   idem, puis un vrai entraînement (/spin_test pratique, droit ACE requis) joué par la vraie touche
-- Le rapport va dans le chat et la console F8 : une ligne OK / ECHEC par vérification.
local function exists(e)
    return e ~= nil and e ~= 0 and type(DoesEntityExist) == 'function' and isTruthy(DoesEntityExist(e))
end

-- Les natives renvoient true/false ou 1/0 selon la version : 0 est « vrai » en Lua, d'où isTruthy partout
local function modelInfo(name)
    local hash = resolveModelHash(name)
    return hash and type(IsModelInCdimage) == 'function' and isTruthy(IsModelInCdimage(hash)) or false
end

local function report(results)
    local bad = 0
    for _, r in ipairs(results) do
        if not r[2] then bad = bad + 1 end
        say((r[2] and 'OK    ' or 'ECHEC ') .. r[1])
    end
    say(bad == 0 and ('autotest : tout est bon (%d vérifications)'):format(#results)
        or ('autotest : %d échec(s) sur %d vérifications'):format(bad, #results))
end

local function observeDemo(label, results)
    local seen, maxCord, attached, topOk, flew, farFromHand, handStillThere = {}, 0.0, false, false, false, 0.0, false
    local ped = PlayerPedId()
    if not Launcher.demo() then
        results[#results + 1] = { label .. ' : démonstration refusée (manche en cours ?)', false }
        return
    end
    local untilAt = GetGameTimer() + 6500
    while GetGameTimer() < untilAt do
        Wait(50)
        local s = Launcher.getState()
        if s.stage then seen[s.stage] = true end
        if (s.cordLen or 0) > maxCord then maxCord = s.cordLen end
        if exists(s.handProp) and type(IsEntityAttachedToEntity) == 'function'
            and isTruthy(IsEntityAttachedToEntity(s.handProp, ped)) then attached = true end
        if s.handProp and exists(s.handProp) and type(GetEntityModel) == 'function' then
            Launcher.diag = Launcher.diag or {}
            Launcher.diag.handModel = GetEntityModel(s.handProp)
            if s.topProp and exists(s.topProp) then Launcher.diag.topModel = GetEntityModel(s.topProp) end
        end
        if exists(s.topProp) then topOk = true end
        if s.flying then
            flew = true
            if exists(s.topProp) then
                local a, b = GetEntityCoords(s.topProp), GetEntityCoords(ped)
                local d = #(a - b)
                if d > farFromHand then farFromHand = d end
            end
            if exists(s.handProp) then handStillThere = true end
        end
    end
    local after = Launcher.getState()
    results[#results + 1] = { label .. ' : lanceur attaché à la main du ped', attached }
    results[#results + 1] = { label .. ' : toupie présente sous les griffes', topOk }
    results[#results + 1] = { label .. ' : étapes tension et claquement vues', seen.tension == true and seen.pulled == true }
    results[#results + 1] = { label .. (' : cordon tendu (%.2f)'):format(maxCord), maxCord > 0.05 }
    results[#results + 1] = { label .. (' : toupie envolée (%.2f m de la main)'):format(farFromHand), flew and farFromHand > 0.2 }
    local d = Launcher.diag or {}
    say(('%s : modèle en main %s (lanceur = %s), modèle qui vole %s (toupie = %s), lanceur encore en main pendant envol : %s'):format(
        label, tostring(d.handModel), tostring(resolveModelHash(Launcher.PROPS.launcherModel)),
        tostring(d.topModel), tostring(resolveModelHash('spin_top_balance')), tostring(handStillThere)))
    results[#results + 1] = { label .. ' : tout est rangé à la fin', not after.active and not exists(after.handProp) and not exists(after.topProp) }
end

-- Candidats d'animation à deux mains : on ne sait pas lesquels existent chez toi, l'essai le dit.
-- /spin_autotest anims joue chacun 2,5 s sur ton ped : regarde lequel ressemble à « tenir un lanceur à deux mains ».
local ANIM_CANDIDATES = {
    { 'anim@heists@fleeca_bank@drilling', 'drill_straight_idle' },
    { 'amb@world_human_const_drill@male@drill@base', 'base' },
    { 'anim@heists@box_carry@', 'idle' },
    { 'anim@heists@ornate_bank@grab_cash', 'grab' },
    { 'mp_arresting', 'idle' },
    { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' },
    { 'weapons@projectile@', 'idle' },
}

local function probeAnims()
    local ped = PlayerPedId()
    local list = {}
    for _, c in ipairs(ANIM_CANDIDATES) do
        local dict, clip = c[1], c[2]
        local line = dict .. ' / ' .. clip
        if type(DoesAnimDictExist) == 'function' and not isTruthy(DoesAnimDictExist(dict)) then
            list[#list + 1] = { line .. ' : dictionnaire absent', false }
        else
            RequestAnimDict(dict)
            local w = 0
            while not isTruthy(HasAnimDictLoaded(dict)) and w < 1500 do Wait(50) w = w + 50 end
            if not isTruthy(HasAnimDictLoaded(dict)) then
                list[#list + 1] = { line .. ' : dictionnaire non chargé', false }
            else
                TaskPlayAnim(ped, dict, clip, 8.0, -8.0, 2500, 49, 0.0, false, false, false)
                Wait(600)
                local playing = isTruthy(IsEntityPlayingAnim(ped, dict, clip, 3))
                say('essai : ' .. line)
                Wait(1900)
                ClearPedTasks(ped)
                RemoveAnimDict(dict)
                list[#list + 1] = { line .. (playing and ' : jouée' or ' : clip absent'), playing }
                Wait(400)
            end
        end
    end
    return list
end

-- Calibration : essaie les 64 rotations par quarts de tour du lanceur dans la main, lit l'orientation réelle du prop
-- (GetEntityMatrix) et garde celle où l'avant du lanceur regarde devant le ped (à l'horizontale) et le dessus vers le haut.
-- Le dessus vers le haut = la toupie pend sous les griffes ; l'avant devant = le cordon se tire vers le corps.
local function calibrate()
    if type(GetEntityMatrix) ~= 'function' or type(GetEntityForwardVector) ~= 'function' then
        return { { 'calibration : natives GetEntityMatrix / GetEntityForwardVector absentes', false } }
    end
    local prep = Launcher.ANIMS.prepare
    local w = 0
    while not ensureAnimDict(prep.dict) and w < 3000 do Wait(50) w = w + 50 end
    Launcher.onCountdownStart('calib', 0, 'participant', 'spin_top_balance')
    Wait(1500)   -- le temps que la pose à deux mains s'installe et que les props existent
    if Launcher.poseFallback then
        Launcher.cleanup()
        return { { 'calibration : la pose à deux mains ne se charge pas, calibration annulée', false } }
    end
    if not exists(Launcher.handProp) then return { { 'calibration : lanceur absent de la main', false } } end
    local H = Launcher.PROPS.hand
    local pf = GetEntityForwardVector(pedId())
    local best, bestScore = nil, -9
    local q = { 0.0, 90.0, 180.0, 270.0 }
    for _, rx in ipairs(q) do for _, ry in ipairs(q) do for _, rz in ipairs(q) do
        H.rx, H.ry, H.rz = rx, ry, rz
        attachLauncher()
        Wait(90)
        local f, _, u = GetEntityMatrix(Launcher.handProp)
        local score = 2.0 * (f.x * pf.x + f.y * pf.y + f.z * pf.z) + u.z
        if score > bestScore then bestScore, best = score, { rx, ry, rz } end
    end end end
    H.rx, H.ry, H.rz = best[1], best[2], best[3]
    attachLauncher()
    say(('calibration : rx = %.0f, ry = %.0f, rz = %.0f (score %.2f sur 3)'):format(best[1], best[2], best[3], bestScore))
    say('lanceur laissé en main : /spin_prop off pour le ranger, /spin_prop print pour noter les valeurs')
    return { { ('calibration : meilleure rotation %.0f %.0f %.0f, score %.2f'):format(best[1], best[2], best[3], bestScore), bestScore > 2.0 } }
end

local function autotest(args)
    if Launcher.autotesting then return say('un autotest est déjà en cours') end
    if Launcher.state ~= 'idle' then return say('une manche est en cours : autotest refusé') end
    Launcher.autotesting = true
    CreateThread(function()
        local results = {}
        local ped = PlayerPedId()
        if args and args[1] == 'calibrate' then
            local res = calibrate()
            Launcher.autotesting = false
            return report(res)
        end
        if args and args[1] == 'anims' then
            say('autotest animations : chaque essai dure 2,5 s, regarde ton ped')
            local list = probeAnims()
            Launcher.autotesting = false
            return report(list)
        end
        results[#results + 1] = { 'ped valide et à pied', exists(ped) and not isTruthy(IsPedInAnyVehicle(ped, false)) }
        results[#results + 1] = { 'modèle du lanceur « ' .. tostring(Launcher.PROPS.launcherModel) .. ' » présent dans le jeu', modelInfo(Launcher.PROPS.launcherModel) }
        results[#results + 1] = { 'modèle de toupie « spin_top_balance » présent dans le jeu', modelInfo('spin_top_balance') }
        say('autotest : 2 démonstrations (~14 s), ne bouge pas la caméra')
        observeDemo('démo 1', results)
        Wait(500)
        observeDemo('démo 2', results)
        if args and args[1] == 'full' then
            say('autotest : entraînement réel (/spin_test pratique)')
            ExecuteCommand('spin_test pratique')
            local LC = SpinArena and SpinArena.LaunchClient
            local waited = 0
            while waited < 12000 and not (LC and LC.cur and LC.cur.nonce) do Wait(100) waited = waited + 100 end
            local armed = LC and LC.cur and LC.cur.nonce ~= nil
            results[#results + 1] = { 'entraînement : visée armée par le serveur (droit ACE spin_test ?)', armed == true }
            if armed then
                Wait(1500)
                ExecuteCommand('+spin_pull'); Wait(300); ExecuteCommand('-spin_pull')
                local seen, w = {}, 0
                while w < 4000 do
                    Wait(50) w = w + 50
                    local s = Launcher.getState()
                    if s.stage then seen[s.stage] = true end
                end
                results[#results + 1] = { 'entraînement : prise puis relâchement joués avec la vraie touche', seen.pulled == true or seen.flying == true or seen.landed == true }
                ExecuteCommand('spin_test stop')
                Wait(1500)
            end
        end
        Launcher.autotesting = false
        report(results)
    end)
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('spin_autotest', function(_, args) autotest(args or {}) end, false)
end

-- Arrêt ou redémarrage de la ressource : les props (lanceur, toupie) sont des objets locaux dont les modèles
-- sont dans le stream de la ressource ; s'ils existent encore quand elle se décharge, le client plante
-- (29/10 : crash au `ensure` pendant /spin_autotest calibrate, lanceur resté en main).
if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(res)
        if type(GetCurrentResourceName) == 'function' and res == GetCurrentResourceName() then Launcher.cleanup() end
    end)
end

return Launcher
