-- SPIN ARENA — Effets visuels GTA et sons mécaniques originaux synthétisés dans la NUI.
-- Fichier : client/effects.lua
-- Particules natives déjà présentes dans les ressources installées. Sons originaux Web Audio ;
-- sons natifs historiques en repli lorsque la NUI est indisponible.

SpinArena = SpinArena or {}

local Effects = {
    enabled       = true,
    activeHandles = {},
    loadedAssets  = {},
    history       = {},
    maxHistory    = 64,
}
SpinArena.Effects = Effects

local math_min = math.min
local math_max = math.max
local math_floor = math.floor

-- Noms d'effets et de sons vérifiés dans resources/ :
-- Particules : asset 'core' -> 'ent_brk_sparks' (aeom_mechanic/client/main.lua, échelle 0,5 pour un outil à main),
--   'veh_backfire' & 'ent_sht_flame' (hotdogfart/config.lua)
-- Sons : 'HUD_FRONTEND_DEFAULT_SOUNDSET', 'HUD_MINI_GAME_SOUNDSET', 'MP_LOBBY_SOUNDS', 'HUD_AMMO_SHOP_SOUNDSET'
-- Contacts : gerbes d'étincelles métalliques (28/10) au lieu de la bouffée de flamme d'échappement (veh_backfire).
-- Taille à vérifier en jeu : une toupie fait 10 cm. Retour arrière : name = 'veh_backfire', baseScale 0,65 / 0,45 / 0,35.
Effects.PTFX = {
    hit      = { asset = 'core', name = 'ent_brk_sparks', baseScale = 0.30 },
    wall     = { asset = 'core', name = 'ent_brk_sparks', baseScale = 0.18 },
    -- Éjection : gerbe un peu plus forte (l'ancien jet ent_sht_flame à 0,85 montait à ~1 m pour une toupie de
    -- 10 cm — capture de Money, 19/10)
    ring_out = { asset = 'core', name = 'ent_brk_sparks', baseScale = 0.40 },
    -- 29/10 : éclatement du verrou (grosse gerbe) et départ sur le rail turbo (petite traînée d'étincelles)
    burst    = { asset = 'core', name = 'ent_brk_sparks', baseScale = 0.55 },
    dash     = { asset = 'core', name = 'ent_brk_sparks', baseScale = 0.15 },
}

Effects.SOUNDS = {
    hit            = { name = 'ATM_WINDOW',              set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    wall           = { name = 'SELECT',                  set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    ring_out       = { name = 'BOATS_PLANES_HELIS_BOOM', set = 'MP_LOBBY_SOUNDS' },
    burst          = { name = 'BOATS_PLANES_HELIS_BOOM', set = 'MP_LOBBY_SOUNDS' },
    countdown_tick = { name = 'SELECT',                  set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    launch_go      = { name = 'TIMER_STOP',              set = 'HUD_MINI_GAME_SOUNDSET' },
    round_end      = { name = 'WEAPON_PURCHASE',         set = 'HUD_AMMO_SHOP_SOUNDSET' },
}

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

local function recordHistory(entry)
    local h = Effects.history
    h[#h + 1] = entry
    if #h > Effects.maxHistory then
        table.remove(h, 1)
    end
end

local function ensurePtfxAsset(asset)
    if type(RequestNamedPtfxAsset) ~= 'function' then
        return false
    end
    if type(HasNamedPtfxAssetLoaded) == 'function' then
        local loaded = HasNamedPtfxAssetLoaded(asset)
        if loaded == true or loaded == 1 then
            Effects.loadedAssets[asset] = true
            return true
        end
    end
    pcall(RequestNamedPtfxAsset, asset)
    Effects.loadedAssets[asset] = true
    if type(HasNamedPtfxAssetLoaded) == 'function' then
        local loaded = HasNamedPtfxAssetLoaded(asset)
        return loaded == true or loaded == 1
    end
    return true
end

function Effects.playSound(key, intensity)
    if not Effects.enabled then return false end
    local def = Effects.SOUNDS[key]
    if not def then return false end

    recordHistory({
        kind = 'sound',
        key  = key,
        name = def.name,
        set  = def.set,
        atMs = nowMs(),
    })

    local cfg = SpinArena.Config and SpinArena.Config.combatAudio or {}
    if cfg.enabled == false then return false end
    if type(SendNUIMessage) == 'function' then
        local ok = pcall(SendNUIMessage, {
            type = 'spin_arena_audio', key = key,
            volume = clamp(tonumber(cfg.volume) or 0.35, 0, 1),
            intensity = clamp(tonumber(intensity) or 0.65, 0.15, 1),
        })
        if ok then return true end
    end
    if type(PlaySoundFrontend) == 'function' then
        pcall(PlaySoundFrontend, -1, def.name, def.set, false)
        return true
    end
    return false
end

-- Déclenche étincelles et son d'impact sur un événement physique (hit, wall, ring_out)
function Effects.onImpact(ev, wx, wy, wz, arenaScale)
    if not Effects.enabled or type(ev) ~= 'table' then return false end
    local kind = tostring(ev.t or 'hit')
    -- Seuls les contacts font des étincelles : spin_out et wobble ne sont pas des chocs (ils en faisaient avant le 28/10)
    if not Effects.PTFX[kind] then return false end
    local ptfxDef = Effects.PTFX[kind]
    local intensity = clamp((tonumber(ev.k) or 128) / 255.0, 0.25, 1.0)
    local scale = ptfxDef.baseScale * (0.65 + 0.70 * intensity) * (tonumber(arenaScale) or 1.0)
    local x = tonumber(wx) or 0.0
    local y = tonumber(wy) or 0.0
    local z = tonumber(wz) or 0.0

    Effects.playSound(Effects.SOUNDS[kind] and kind or 'hit', intensity)

    recordHistory({
        kind      = 'ptfx',
        eventType = kind,
        asset     = ptfxDef.asset,
        effect    = ptfxDef.name,
        x         = x,
        y         = y,
        z         = z,
        scale     = scale,
        intensity = intensity,
        step      = tonumber(ev.s) or 0,
        atMs      = nowMs(),
    })

    if ensurePtfxAsset(ptfxDef.asset)
        and type(UseParticleFxAssetNextCall) == 'function'
        and type(StartParticleFxNonLoopedAtCoord) == 'function'
    then
        pcall(function()
            UseParticleFxAssetNextCall(ptfxDef.asset)
            StartParticleFxNonLoopedAtCoord(
                ptfxDef.name,
                x, y, z,
                0.0, 0.0, 0.0,
                scale,
                false, false, false
            )
        end)
        return true
    end

    return false
end

-- Sifflement de rotation (NUI) : suit la rotation de la toupie suivie, 0 = silence. Envoyé seulement quand le niveau
-- change nettement ou toutes les 400 ms (le son s'éteint de lui-même sans nouvelle pendant 1,5 s).
Effects.spinSent = { level = 0.0, atMs = 0 }
function Effects.spinLevel(level)
    if not Effects.enabled then return false end
    local cfg = SpinArena.Config and SpinArena.Config.combatAudio or {}
    if cfg.enabled == false or type(SendNUIMessage) ~= 'function' then return false end
    local l = clamp(tonumber(level) or 0.0, 0.0, 1.0)
    local now, last = nowMs(), Effects.spinSent
    if math.abs(l - last.level) < 0.04 and now - last.atMs < 400 then return false end
    if l == 0.0 and last.level == 0.0 then return false end
    Effects.spinSent = { level = l, atMs = now }
    pcall(SendNUIMessage, { type = 'spin_arena_audio', key = 'spin', level = l,
        volume = clamp(tonumber(cfg.volume) or 0.35, 0, 1) })
    return true
end

function Effects.onCountdownTick(secondsLeft)
    return Effects.playSound('countdown_tick')
end

function Effects.onLaunchGo()
    return Effects.playSound('launch_go')
end

local function stopCombatAudio()
    Effects.spinSent = { level = 0.0, atMs = 0 }
    if type(SendNUIMessage) == 'function' then
        pcall(SendNUIMessage, { type = 'spin_arena_audio', key = 'stop' })
    end
end

function Effects.onRoundEnd()
    stopCombatAudio()
    return Effects.playSound('round_end')
end

function Effects.cleanup()
    stopCombatAudio()
    if type(StopParticleFxLooped) == 'function' then
        for handle in pairs(Effects.activeHandles) do
            pcall(StopParticleFxLooped, handle, false)
        end
    end
    Effects.activeHandles = {}

    if type(RemoveNamedPtfxAsset) == 'function' then
        for asset in pairs(Effects.loadedAssets) do
            pcall(RemoveNamedPtfxAsset, asset)
        end
    end
    Effects.loadedAssets = {}
    return true
end

return Effects
