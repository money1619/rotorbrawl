-- Accueil Arena : présentation locale ; l'accès aux matchs/objets reste validé serveur.
local Concierge = { ped = nil, generation = 0 }
SpinArena.Concierge = Concierge
function Concierge.cleanup()
    Concierge.generation = Concierge.generation + 1
    local ped = Concierge.ped
    Concierge.ped = nil
    if ped then
        pcall(function() TargetCompat:removeLocalEntity(ped, 'spin_arena:concierge') end)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end
function Concierge.spawn()
    Concierge.cleanup()
    local point = SpinArena.Config and SpinArena.Config.concierge
    if not point or type(CreatePed) ~= 'function' then return end
    local generation = Concierge.generation
    CreateThread(function()
        local model = GetHashKey(point.model)
        local ok = pcall(lib.requestModel, model, 5000)
        if not ok then return end
        if generation ~= Concierge.generation then SetModelAsNoLongerNeeded(model);return end
        local ped = CreatePed(4, model, point.x, point.y, point.z - 1.0, point.heading, false, false)
        SetModelAsNoLongerNeeded(model)
        if not ped or ped == 0 then return end
        Concierge.ped = ped
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        if not TargetCompat then return end -- aucun script de ciblage : accueil sans option (client/target_compat.lua)
        TargetCompat:addLocalEntity(ped, {{
            name = 'spin_arena:concierge', icon = 'fa-solid fa-circle-dot', label = 'Accueil ROTORBRAWL', distance = 2.0,
            canInteract = function()
                local match = SpinArena.Client.state.match
                return not (match and match.role == 'participant')
            end,
            onSelect = function() SpinArena.Client.openHome() end,
        }})
    end)
end
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then Concierge.cleanup() end
end)
Concierge.spawn()
return Concierge
