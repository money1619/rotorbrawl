-- ROTORBRAWL — lancement manuel, côté joueur (jauge web/launch_gauge.js). Serveur : server/matches.lua (Archimedes).
--   serveur → client  P.ev.prepare { matchId, round, revision, deadlineInMs, ready = { bool, bool }, rules }
--   client  → serveur P.cb.launchArm     { matchId, round }        → { ok, code, nonce, gauge, expiresInMs, minHoldMs, deadlineInMs }
--   client  → serveur P.cb.launchRelease { matchId, round, nonce } → { ok, code, grade }
-- Lanceur à tirette : ← / → incline le lanceur (bord · droit · centre), ESPACE tenu saisit la tirette (launchGrip :
-- le serveur note l'instant et la prise sur la jauge), ESPACE relâché tire (launchRelease : nonce et inclinaison).
-- La commande « spin_launch » reste un appui rapide sans tirage : le serveur plafonne alors la qualité.
-- Règles : seul un PARTICIPANT ouvre la jauge (les joueurs autour regardent le combat dans le monde, sans écran ni
-- focus) ; le nonce reste ici, jamais dans la page ; un seul lancer accepté par manche, toujours par geste volontaire
-- (touche « Lancer », ESPACE par défaut) ; rien n'est envoyé au délai ; aucune force, aucun score, aucune heure.
-- Réarmement : une seule fois après expired / too_early / bad_nonce (le nonce est consommé côté serveur), ou au
-- geste suivant si l'armement a expiré ici ou a été refusé (rate_limited). Jamais en boucle sans geste.
-- SpinArena.Launch est le module partagé (shared/launch.lua) : ce contrôleur est SpinArena.LaunchClient.
SpinArena = SpinArena or {}

local LC = { cur = nil }
local P = SpinArena.Protocol or {}
local CB_ARM = (P.cb and P.cb.launchArm) or 'spin_arena:launch_arm'
local CB_RELEASE = (P.cb and P.cb.launchRelease) or 'spin_arena:launch_release'
local CB_GRIP = (P.cb and P.cb.launchGrip) or 'spin_arena:launch_grip'
local EV_PREPARE = (P.ev and P.ev.prepare) or 'spin_arena:cl:prepare'
local REARM = { expired = true, too_early = true, bad_nonce = true }
local CLOSE = { already_launched = true, not_preparing = true, not_found = true }

local function client() return SpinArena.Client end
-- Animation en jeu (client/launcher.lua) : une panne de ce côté ne doit jamais empêcher le lancer
local function launcher(name, ...)
    local L = SpinArena.Launcher
    if L and type(L[name]) == 'function' then pcall(L[name], ...) end
end
local function nui(msg) if type(SendNUIMessage) == 'function' then SendNUIMessage(msg) end end

local function isParticipantOf(matchId)
    local C = client()
    local m = C and C.state and C.state.match
    return m ~= nil and m.role == 'participant' and m.matchId == matchId
end

-- Entraînement : indiqué par l'en-tête du match (practice = true) ; l'adversaire est le nom de l'autre côté
local function practiceOf(matchId)
    local C = client()
    local m = C and C.state and C.state.match
    return m ~= nil and m.matchId == matchId and m.practice == true
end
local function opponentOf(matchId)
    local C = client()
    local m = C and C.state and C.state.match
    if not (m and m.matchId == matchId and type(m.names) == 'table') then return nil end
    local other = (tonumber(m.side) or 1) == 1 and 2 or 1
    local n = m.names[other]
    return type(n) == 'string' and n:sub(1, 32) or nil
end

function LC.close(reason)
    if LC.cur then nui({ action = 'launchClose', reason = reason }) end
    LC.cur = nil
end

-- ESPACE est aussi le saut de GTA : tant que la jauge d'un participant est ouverte, le saut est désactivé
-- (la touche « Lancer » passe par RegisterKeyMapping et reste active ; à confirmer en jeu)
local JUMP = 22   -- INPUT_JUMP
local function holdJump()
    if LC.jumpThread or type(DisableControlAction) ~= 'function' then return end
    LC.jumpThread = true
    CreateThread(function()
        while LC.cur do
            DisableControlAction(0, JUMP, true)
            Wait(0)
        end
        LC.jumpThread = nil
    end)
end

-- Demande une jauge au serveur et l'ouvre (le nonce reste dans cur). notice : raison d'un réarmement, affichée.
local function arm(cur, notice)
    if cur.arming then return end
    cur.arming, cur.needArm, cur.nonce = true, false, nil
    cur.gripped, cur.gripping, cur.keyDown = false, false, false             -- un réarmement annule une prise en cours
    launcher('onReset', cur.matchId, cur.round)
    local ok, res = pcall(lib.callback.await, CB_ARM, false, { matchId = cur.matchId, round = cur.round })
    if LC.cur ~= cur then return end                  -- fin, annulation ou manche suivante pendant l'attente
    cur.arming = false
    if not ok or type(res) ~= 'table' or not res.ok or type(res.nonce) ~= 'string' or type(res.gauge) ~= 'table' then
        local code = type(res) == 'table' and res.code or 'error'
        if CLOSE[code] then return LC.close(code) end
        cur.needArm = true                            -- refus passager (rate_limited…) : le geste suivant réessaie
        nui({ action = 'launchNotice', code = code })
        return
    end
    local now = GetGameTimer()
    cur.nonce = res.nonce
    cur.armedAt = now
    cur.expiresAt = now + (tonumber(res.expiresInMs) or 0)
    cur.minHoldMs = tonumber(res.minHoldMs) or 0
    if type(res.pull) == 'table' then
        cur.pull = { minMs = tonumber(res.pull.minMs), maxMs = tonumber(res.pull.maxMs), fadeMs = tonumber(res.pull.fadeMs) }
    end
    if tonumber(res.deadlineInMs) then cur.deadlineAt = now + tonumber(res.deadlineInMs) end
    -- Lanceur de ce joueur (effets décidés par le serveur ; le client ne fait que les afficher)
    if type(res.launcher) == 'table' and type(res.launcher.id) == 'string' then
        local L = SpinArena.Launch
        local mods = L and L.mods and L.mods(res.launcher.id) or {}
        cur.launcher = { id = res.launcher.id, label = tostring(res.launcher.label or ''),
                         effects = L and L.describe and L.describe(mods) or {} }
    end
    nui({ action = 'launchOpen', round = cur.round, notice = notice, rules = cur.rules, tilt = cur.tilt, pull = cur.pull,
          launcher = cur.launcher,
          practice = cur.practice or nil, opponent = cur.practice and cur.opponent or nil,
          deadlineInMs = math.max(0, (cur.deadlineAt or now) - now),
          gauge = { periodMs = res.gauge.periodMs, phase = res.gauge.phase, target = res.gauge.target, width = res.gauge.width } })
    if cur.ready then nui({ action = 'launchReady', ready = cur.ready }) end
end

-- Préparation d'une manche (reçue aussi par les joueurs autour de la table : ils l'ignorent ici)
function LC.onPrepare(payload)
    if type(payload) ~= 'table' or type(payload.matchId) ~= 'string' then return end
    local round = tonumber(payload.round)
    if not round then return end
    if not isParticipantOf(payload.matchId) then return end
    local cur = LC.cur
    if cur and cur.matchId == payload.matchId and cur.round == round then
        -- Même manche : seulement l'état « prêts » (pas de nouvel arm, qui remplacerait le nonce)
        if type(payload.ready) == 'table' then cur.ready = payload.ready; nui({ action = 'launchReady', ready = payload.ready }) end
        return
    end
    local now = GetGameTimer()
    LC.cur = { matchId = payload.matchId, round = round, sent = false, launched = false, tilt = LC.lastTilt or 0,
               rules = type(payload.rules) == 'table' and payload.rules or nil,
               -- Entraînement admin (/spin_test) : adversaire simulé par le serveur, affiché comme tel
               practice = payload.practice == true or practiceOf(payload.matchId),
               opponent = opponentOf(payload.matchId),
               ready = type(payload.ready) == 'table' and payload.ready or nil,
               deadlineAt = now + (tonumber(payload.deadlineInMs) or 0) }
    holdJump()
    arm(LC.cur, nil)
end

-- Vérifications communes aux gestes (appui rapide, prise) : false si rien ne doit partir.
local function gestureReady(cur)
    if not isParticipantOf(cur.matchId) then LC.close('not_participant'); return false end
    local now = GetGameTimer()
    if cur.deadlineAt and now > cur.deadlineAt then return false end              -- délai de la manche : rien
    if cur.needArm or not cur.nonce or (cur.expiresAt and now > cur.expiresAt) then
        CreateThread(function() arm(cur, cur.nonce and 'expired' or nil) end)    -- ce geste réarme, il ne lance pas
        return false
    end
    if now - (cur.armedAt or now) < (cur.minHoldMs or 0) then                      -- trop tôt : le serveur refuserait
        nui({ action = 'launchNotice', code = 'too_early' })
        return false
    end
    return true
end

-- Envoie le tirage (avec ou sans prise préalable) : le nonce part, l'inclinaison choisie aussi
local function sendRelease(cur)
    cur.sent = true
    local nonce = cur.nonce
    cur.nonce = nil                                                               -- usage unique, avant l'appel
    cur.gripped = false
    nui({ action = 'launchSent' })
    CreateThread(function()
        local ok, res = pcall(lib.callback.await, CB_RELEASE, false,
            { matchId = cur.matchId, round = cur.round, nonce = nonce, tilt = cur.tilt })
        if LC.cur ~= cur then return end
        cur.sent = false
        if ok and type(res) == 'table' and res.ok then
            cur.launched = true
            launcher('onResult', res.grade)                                       -- vitesse d'emballement de la toupie
            return nui({ action = 'launchResult', grade = res.grade, grip = res.grip, pull = res.pull })
        end
        launcher('onReset', cur.matchId, cur.round)                               -- le cordon se rembobine, on réessaie
        local code = type(res) == 'table' and res.code or 'error'
        if REARM[code] then return arm(cur, code) end
        if CLOSE[code] then return LC.close(code) end
        cur.needArm = true
        nui({ action = 'launchNotice', code = code })
    end)
    return true
end

-- Appui rapide (commande « spin_launch », clic sur la jauge) : lancer sans tirage, plafonné par le serveur.
-- Renvoie true si un lancer est parti.
function LC.release()
    local cur = LC.cur
    if not cur or cur.launched or cur.sent or cur.arming or cur.gripped or cur.gripping then return false end
    if not gestureReady(cur) then return false end
    return sendRelease(cur)
end

-- Inclinaison du lanceur avant la prise : −1 vers le bord, 0 droit, 1 vers le centre. Mémorisée d'une manche à l'autre.
function LC.setTilt(delta)
    local cur = LC.cur
    if not cur or cur.launched or cur.sent or cur.arming or cur.gripped or cur.gripping then return false end
    local tilt = math.max(-1, math.min(1, cur.tilt + delta))
    if tilt == cur.tilt then return false end
    cur.tilt, LC.lastTilt = tilt, tilt
    nui({ action = 'launchTilt', tilt = tilt })
    return true
end

-- Tirage : relâchement de la touche tenue. Le serveur mesure la durée entre la prise et ce message.
function LC.pull()
    local cur = LC.cur
    if not cur or cur.launched or cur.sent or not cur.gripped then return false end
    launcher('onPull', cur.matchId, cur.round)
    return sendRelease(cur)
end

-- Touche « Lancer » pressée : saisit la tirette (le serveur note l'instant et la prise sur la jauge).
-- Le tirage part au relâchement (LC.keyUp) ; jamais automatiquement.
function LC.press()
    local cur = LC.cur
    if not cur or cur.launched or cur.sent or cur.arming or cur.gripped or cur.gripping then return false end
    if not gestureReady(cur) then return false end
    cur.keyDown, cur.gripping = true, true
    local nonce = cur.nonce
    CreateThread(function()
        local ok, res = pcall(lib.callback.await, CB_GRIP, false, { matchId = cur.matchId, round = cur.round, nonce = nonce })
        if LC.cur ~= cur then return end
        cur.gripping = false
        local code = type(res) == 'table' and res.code or 'error'
        if ok and type(res) == 'table' and (res.ok or code == 'already_gripped') then
            cur.gripped = true
            nui({ action = 'launchGrip', grade = res.grade, pull = cur.pull })
            launcher('onGrip', cur.matchId, cur.round, cur.pull)
            if not cur.keyDown then LC.pull() end                                 -- relâchée pendant l'aller-retour
            return
        end
        cur.keyDown = false
        launcher('onReset', cur.matchId, cur.round)
        if REARM[code] then return arm(cur, code) end
        if CLOSE[code] then return LC.close(code) end
        cur.needArm = true
        nui({ action = 'launchNotice', code = code })
    end)
    return true
end

-- Touche « Lancer » relâchée : tire si la tirette est saisie (sinon la prise en vol tirera à son retour)
function LC.keyUp()
    local cur = LC.cur
    if not cur then return false end
    cur.keyDown = false
    if cur.gripped then return LC.pull() end
    return false
end

-- Compte à rebours du serveur : « Départ dans 3, 2, 1 » puis GO à l'heure du départ (startsInMs), jamais avant.
-- Un départ repoussé par le serveur arrive avec une révision plus haute : il remplace le précédent.
local GO_HOLD_MS = 1000   -- le GO reste affiché 1 s après le départ, puis la jauge se ferme
function LC.onCountdown(payload)
    local cur = LC.cur
    if type(payload) ~= 'table' or not cur or payload.matchId ~= cur.matchId then return end
    local rev = tonumber(payload.revision) or 0
    if cur.goRevision and rev <= cur.goRevision then return end
    local inMs = math.max(0, tonumber(payload.startsInMs) or 0)
    cur.goRevision = rev
    nui({ action = 'launchCountdown', startsInMs = inMs })
    SetTimeout(inMs + GO_HOLD_MS, function()
        if LC.cur == cur and cur.goRevision == rev then LC.close('go') end
    end)
end


local function onTerminal(payload)
    if type(payload) == 'table' and LC.cur and payload.matchId == LC.cur.matchId then LC.close('end') end
end

if type(RegisterNetEvent) == 'function' and type(AddEventHandler) == 'function' then
    RegisterNetEvent(EV_PREPARE)
    AddEventHandler(EV_PREPARE, function(payload) CreateThread(function() LC.onPrepare(payload) end) end)
    local ev = P.ev or {}
    for _, name in ipairs({ ev.matchEnd or 'spin_arena:cl:matchEnd', ev.cancel or 'spin_arena:cl:cancel', ev.unsub or 'spin_arena:cl:unsub' }) do
        AddEventHandler(name, onTerminal)
    end
    AddEventHandler(ev.countdown or 'spin_arena:cl:countdown', LC.onCountdown)
end
if type(RegisterCommand) == 'function' then
    RegisterCommand('spin_launch', function() LC.release() end, false)   -- appui rapide : lancer sans tirage (plafonné)
    RegisterCommand('+spin_pull', function() LC.press() end, false)      -- ESPACE tenu : saisir la tirette
    RegisterCommand('-spin_pull', function() LC.keyUp() end, false)      -- ESPACE relâché : tirer
    RegisterCommand('spin_tilt_edge', function() LC.setTilt(-1) end, false)
    RegisterCommand('spin_tilt_center', function() LC.setTilt(1) end, false)
    if type(RegisterKeyMapping) == 'function' then
        RegisterKeyMapping('+spin_pull', 'ROTORBRAWL · Lanceur : saisir (tenir) puis tirer (relâcher)', 'keyboard', 'SPACE')
        RegisterKeyMapping('spin_tilt_edge', 'ROTORBRAWL · Lanceur : incliner vers le bord', 'keyboard', 'LEFT')
        RegisterKeyMapping('spin_tilt_center', 'ROTORBRAWL · Lanceur : incliner vers le centre', 'keyboard', 'RIGHT')
    end
end
if type(RegisterNUICallback) == 'function' then
    RegisterNUICallback('nui:launchRelease', function(_, cb) cb({ ok = LC.release() }) end)
end
AddEventHandler('onResourceStop', function(name)
    if name == (GetCurrentResourceName and GetCurrentResourceName()) then LC.close('stop') end
end)

SpinArena.LaunchClient = LC
return LC
