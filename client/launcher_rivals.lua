-- SPIN ARENA — Lanceurs des AUTRES participants. Fichier : client/launcher_rivals.lua
-- Les props du lanceur (client/launcher.lua) sont locaux : sans ce module, seul le joueur qui lance voit son lanceur.
-- Ici, chaque client crée ses propres copies locales (non réseau) du lanceur et de la toupie accrochée, fixées à la
-- main du personnage de chaque autre participant (adversaire, ou les deux duellistes pour un spectateur) :
--   préparation   lanceur en main, toupie sous les griffes, immobile
--   prêt          (le serveur annonce le lancer de ce côté) la toupie s'emballe sur son support
--   GO            la toupie quitte les griffes et vole vers sa place dans la cuvette ; le lanceur est rangé peu après
-- Le geste du personnage (animation) est déjà vu par tous : il est joué par le client du participant lui-même.
-- Le cordon n'est pas tracé : la prise et le tirage d'un autre joueur ne sont pas transmis (aucun message de plus).
-- Natives vérifiées dans natives_0193D0AF.lua : GetPlayerFromServerId, GetPlayerPed, GetPedBoneIndex,
-- AttachEntityToEntity, DetachEntity, DoesEntityExist, GetEntityCoords, SetEntityCoordsNoOffset, SetEntityRotation.

SpinArena = SpinArena or {}

local Rivals = {
    byScene = {},   -- [matchId] = { [côté] = { src, ped, round, launcher, top, ang, rps, flight, removeAt } }
}
SpinArena.LauncherRivals = Rivals

Rivals.ENABLED = true
Rivals.READY_RPS = 10.0   -- tours/s visuels d'une toupie prête sur le lanceur d'un autre joueur

local function isTruthy(v) return v == true or v == 1 end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function launcherMod() return SpinArena.Launcher end

local function coords(ent)
    if type(GetEntityCoords) ~= 'function' then return nil end
    local c = GetEntityCoords(ent)
    if type(c) ~= 'table' and type(c) ~= 'userdata' then return nil end
    return tonumber(c.x or c[1]) or 0.0, tonumber(c.y or c[2]) or 0.0, tonumber(c.z or c[3]) or 0.0
end

local function exists(ent)
    if not ent or ent == 0 then return false end
    if type(DoesEntityExist) ~= 'function' then return true end
    return isTruthy(DoesEntityExist(ent))
end

local function remove(ent)
    local L = launcherMod()
    if ent and L and type(L.deleteProp) == 'function' then L.deleteProp(ent) end
end

local function releaseSide(entry)
    if not entry then return end
    remove(entry.top)
    remove(entry.launcher)
    entry.top, entry.launcher, entry.flight = nil, nil, nil
end

-- Personnage d'un autre participant, s'il est chargé chez ce client ; nil pour soi-même ou un joueur absent
function Rivals.pedOf(src)
    src = tonumber(src)
    if not src or src < 1 then return nil end
    if type(GetPlayerFromServerId) ~= 'function' or type(GetPlayerPed) ~= 'function' then return nil end
    local player = GetPlayerFromServerId(src)
    if player == nil or player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if not exists(ped) then return nil end
    if type(PlayerPedId) == 'function' and ped == PlayerPedId() then return nil end
    return ped
end

local function attachLauncher(entry)
    local L = launcherMod()
    if not entry.launcher or type(AttachEntityToEntity) ~= 'function' then return end
    local bone = L.HAND_BONE
    if type(GetPedBoneIndex) == 'function' then bone = GetPedBoneIndex(entry.ped, L.HAND_BONE) or bone end
    local H = L.PROPS.hand
    pcall(AttachEntityToEntity, entry.launcher, entry.ped, bone, H.x, H.y, H.z, H.rx, H.ry, H.rz,
        true, true, false, true, 1, true)
end

local function mountTop(entry)
    local L = launcherMod()
    if not entry.top or not entry.launcher or type(AttachEntityToEntity) ~= 'function' then return end
    local M = L.PROPS.mount
    pcall(AttachEntityToEntity, entry.top, entry.launcher, 0, 0.0, M.y, M.topZ - (entry.topMaxZ or M.topHeight),
        0.0, 0.0, entry.ang or 0.0, false, false, false, false, 2, true)
end

-- Crée ce qui manque (modèles chargés de façon asynchrone : réessayé à chaque image)
local function ensureProps(entry, topModel, topParts, launcherType)
    local L = launcherMod()
    if not entry.launcher then
        entry.launcher = L.spawnProp(entry.ped, L.modelFor(launcherType))
        if entry.launcher then attachLauncher(entry) end
    end
    if entry.launcher and not entry.top and not entry.flight and topModel then
        local TM = SpinArena.TopModel
        if TM then
            entry.top = TM.spawn({ model = topModel, parts = topParts }, function(m) return L.spawnProp(entry.ped, m) end)
        else
            entry.top = L.spawnProp(entry.ped, topModel)
        end
        if entry.top then
            entry.topMaxZ = (TM and topParts and TM.height(topParts)) or L.readTopMaxZ(topModel)
            mountTop(entry)
        end
    end
end

-- Envol vers la toupie de la cuvette (même courbe que client/launcher.lua)
local function flightFrame(entry, scene, i, t)
    local L = launcherMod()
    local f = entry.flight
    local k = clamp((t - f.startAt) / L.PROPS.flightMs, 0.0, 1.0)
    local tx, ty, tz = f.sx, f.sy, f.sz - 0.6
    local target = scene.topProps and scene.topProps[i]
    if exists(target) then
        local x, y, z = coords(target)
        if x then tx, ty, tz = x, y, z end
    end
    local e = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
    local x = f.sx + (tx - f.sx) * e
    local y = f.sy + (ty - f.sy) * e
    local z = f.sz + (tz - f.sz) * e + L.PROPS.arc * math.sin(math.pi * k)
    if type(SetEntityCoordsNoOffset) == 'function' then pcall(SetEntityCoordsNoOffset, entry.top, x, y, z, false, false, false) end
    if type(SetEntityRotation) == 'function' then pcall(SetEntityRotation, entry.top, 0.0, 0.0, entry.ang or 0.0, 2, true) end
    if k >= 1.0 then
        remove(entry.top)
        entry.top, entry.flight = nil, nil
        entry.landed = true
    end
end

-- Une image : appelée par le rendu pour chaque scène affichée
function Rivals.sync(scene, now, dt)
    local L = launcherMod()
    if not Rivals.ENABLED or type(scene) ~= 'table' or not scene.matchId or not L or not L.PROPS or not L.PROPS.enabled
        or type(L.spawnProp) ~= 'function' then
        return
    end
    local active = scene.state == 'preparing' or scene.state == 'countdown' or scene.state == 'playing'
    local per = Rivals.byScene[scene.matchId]
    if not active then
        if per then Rivals.release(scene) end
        return
    end
    if not per then per = {}; Rivals.byScene[scene.matchId] = per end
    dt = clamp(tonumber(dt) or 0.0, 0.0, 0.1)
    local mySide = scene.role == 'participant' and tonumber(scene.side) or nil
    for i = 1, 2 do
        local src = scene.srcs and scene.srcs[i] or 0
        local entry = per[i]
        -- Nouvelle manche, autre joueur, joueur parti ou soi-même : on repart de zéro
        if entry and (entry.round ~= scene.round or entry.src ~= src or not exists(entry.ped)) then
            releaseSide(entry)
            per[i], entry = nil, nil
        end
        local ped = (i ~= mySide) and Rivals.pedOf(src) or nil
        if ped and not entry then
            entry = { src = src, ped = ped, round = scene.round, ang = 0.0, rps = 0.0 }
            per[i] = entry
        end
        if entry and not entry.landed then
            local meta = scene.tops and scene.tops[i] or {}
            local dir = (tonumber(meta.dir) == -1) and -1 or 1
            if scene.state ~= 'playing' then
                ensureProps(entry, meta.model or ('spin_top_' .. tostring(meta.family or 'balance')), meta.parts, meta.launcher)
                local ready = type(scene.ready) == 'table' and scene.ready[i] == true
                entry.rps = entry.rps + ((ready and Rivals.READY_RPS or 0.0) - entry.rps) * clamp(dt * 3.0, 0.0, 1.0)
                if entry.rps > 0.05 then
                    entry.ang = ((entry.ang or 0.0) + dir * entry.rps * 360.0 * dt) % 360.0
                    mountTop(entry)
                end
            else
                -- GO : la toupie part vers la cuvette, le lanceur reste en main le temps du geste
                if entry.top and not entry.flight then
                    local x, y, z = coords(entry.top)
                    if type(DetachEntity) == 'function' then pcall(DetachEntity, entry.top, true, true) end
                    entry.flight = { startAt = now, sx = x or 0.0, sy = y or 0.0, sz = z or 0.0 }
                    entry.removeAt = now + (L.PROPS.keepLauncherMs or 900)
                elseif not entry.top and not entry.flight then
                    entry.landed = true   -- GO avant que les modèles aient chargé : rien à faire voler
                    entry.removeAt = entry.removeAt or now
                end
                if entry.flight and entry.top then
                    entry.ang = ((entry.ang or 0.0) + dir * math.max(entry.rps, 4.0) * 360.0 * dt) % 360.0
                    flightFrame(entry, scene, i, now)
                end
            end
        end
        if entry and entry.removeAt and now >= entry.removeAt and entry.launcher then
            remove(entry.launcher)
            entry.launcher = nil
        end
    end
end

-- La toupie de ce côté est en vol depuis le lanceur d'un autre participant (le rendu masque alors celle de la cuvette)
function Rivals.isFlying(scene, i)
    local per = type(scene) == 'table' and scene.matchId and Rivals.byScene[scene.matchId] or nil
    return (per and per[i] and per[i].flight ~= nil) == true
end

function Rivals.release(scene)
    local id = type(scene) == 'table' and scene.matchId or scene
    local per = id and Rivals.byScene[id]
    if not per then return end
    for i = 1, 2 do releaseSide(per[i]) end
    Rivals.byScene[id] = nil
end

function Rivals.cleanupAll()
    for id in pairs(Rivals.byScene) do Rivals.release(id) end
    Rivals.byScene = {}
end

-- Nombre de props créés (tests)
function Rivals.count()
    local n = 0
    for _, per in pairs(Rivals.byScene) do
        for i = 1, 2 do
            local e = per[i]
            if e then
                if e.launcher then n = n + 1 end
                if e.top then n = n + 1 end
            end
        end
    end
    return n
end

if type(AddEventHandler) == 'function' and type(GetCurrentResourceName) == 'function' then
    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() then Rivals.cleanupAll() end
    end)
end

return Rivals
