-- Vendeurs locaux : une seule interaction ox_target par vendeur ouvre la boutique unique (onglet Boutique de
-- l'interface Arena, catégories internes). Le serveur valide et facture chaque achat.
local Client = SpinArena.Client
local Vendor = { entities = {}, blips = {}, generation = 0, signature = nil }
Vendor.OPTION = { name = 'spin_arena:vendor', icon = 'fa-solid fa-cart-shopping', label = 'Ouvrir la boutique' }   -- libellé de la maquette de Money
-- Anciens noms d'options (versions à 4 catégories) : retirés aussi au nettoyage
local VENDOR_OPTION_NAMES = {
    'spin_arena:vendor_tops',
    'spin_arena:vendor_launchers',
    'spin_arena:vendor_parts',
    'spin_arena:vendor_repair',
    'spin_arena:vendor',
}
SpinArena.ShopVendor = Vendor

function Vendor.clear()
    Vendor.generation = Vendor.generation + 1
    for _, ped in ipairs(Vendor.entities) do
        pcall(function() TargetCompat:removeLocalEntity(ped, VENDOR_OPTION_NAMES) end)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    for _, blip in ipairs(Vendor.blips) do
        pcall(RemoveBlip, blip)
    end
    Vendor.blips = {}
    Vendor.entities = {}
    Vendor.signature = nil
end

function Vendor.sync(info)
    local points = type(info) == 'table' and info.enabled and info.points or {}
    if type(points) ~= 'table' then points = {} end
    local keys = {}
    for i, pt in ipairs(points) do
        if type(pt) == 'table' and type(pt.ped) == 'string' then
            keys[#keys + 1] = table.concat({i, pt.ped, tostring(pt.x), tostring(pt.y), tostring(pt.z), tostring(pt.heading)}, ':')
        end
    end
    local signature = table.concat(keys, '|')
    if Vendor.signature == signature then return end
    Vendor.clear()
    Vendor.signature = signature
    local generation = Vendor.generation
    for index, pt in ipairs(points) do
        if type(pt) == 'table' and type(pt.ped) == 'string'
            and tonumber(pt.x) and tonumber(pt.y) and tonumber(pt.z) then
            local shopId, point = index, pt
            if type(AddBlipForCoord) == 'function' then
                local blip = AddBlipForCoord(point.x, point.y, point.z)
                if blip and blip ~= 0 then
                    Vendor.blips[#Vendor.blips + 1] = blip
                    SetBlipSprite(blip, 52)
                    SetBlipDisplay(blip, 4)
                    SetBlipScale(blip, 0.75)
                    SetBlipColour(blip, 3)
                    SetBlipAsShortRange(blip, true)
                    AddTextEntry('SPIN_ARENA_SHOP', 'Boutique ROTORBRAWL')
                    BeginTextCommandSetBlipName('SPIN_ARENA_SHOP')
                    EndTextCommandSetBlipName(blip)
                end
            end
            CreateThread(function()
                local hash = GetHashKey(point.ped)
                local ok = pcall(lib.requestModel, hash, 5000)
                if not ok then return end -- La zone existante reste utilisable si le modèle échoue.
                if generation ~= Vendor.generation then SetModelAsNoLongerNeeded(hash); return end
                local ped = CreatePed(4, hash, point.x, point.y, point.z - 1.0, tonumber(point.heading) or 0.0, false, false)
                SetModelAsNoLongerNeeded(hash)
                if not ped or ped == 0 then return end
                Vendor.entities[#Vendor.entities + 1] = ped
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                if not TargetCompat then return end -- aucun script de ciblage : vendeur sans option (client/target_compat.lua)
                local canUseVendor = function()
                    return not (Client.state.match and Client.state.match.role == 'participant')
                end
                TargetCompat:addLocalEntity(ped, { {
                    name        = Vendor.OPTION.name,
                    icon        = Vendor.OPTION.icon,
                    label       = Vendor.OPTION.label,
                    distance    = 2.0,
                    canInteract = canUseVendor,
                    onSelect    = function() Client.openShop(shopId) end,
                } })
            end)
        end
    end
end

local syncTargets = Client.syncShopTargets
Client.syncShopTargets = function(info)
    local count = syncTargets(info)
    Vendor.sync(info)
    return count
end
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then Vendor.clear() end
end)

CreateThread(function()
    Wait(1500)
    Client.fetchShop()
end)
