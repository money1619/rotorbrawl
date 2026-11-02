-- Ciblage de ROTORBRAWL : même API qu'ox_target (appels avec « : »), quel que soit le script de ciblage.
--   ox_target : TargetCompat = exports.ox_target (comportement d'origine, inchangé)
--   qb-target : traduction par le pont AEOM (bridge/client.lua, Target.*)
--   aucun     : TargetCompat = nil (les interactions passent par le menu F7)
-- Options globales sans entité (addGlobalOption) : ox_target seulement ; avec qb-target, menu F7.

if Target.name == 'ox' then
    TargetCompat = exports.ox_target
elseif Target.name == 'qb' then
    TargetCompat = {
        addSphereZone = function(_, data) return Target.addSphere(data.coords, data.radius, data.options, data.debug) end,
        addBoxZone = function(_, data) return Target.addBox(data.coords, data.size, data.rotation, data.options, data.debug) end,
        removeZone = function(_, id) Target.removeZone(id) end,
        addLocalEntity = function(_, entity, options) Target.addLocalEntity(entity, options) end,
        removeLocalEntity = function(_, entity, names)
            if type(names) == 'string' then names = { names } end
            local opts
            if names then
                opts = {}
                for i, n in ipairs(names) do opts[i] = { name = n, label = n } end
            end
            Target.removeLocalEntity(entity, opts)
        end,
        addGlobalPlayer = function(_, options) Target.addGlobalPlayer(options) end,
        removeGlobalPlayer = function(_, names)
            local opts = {}
            for i, n in ipairs(names or {}) do opts[i] = { name = n, label = n } end
            Target.removeGlobalPlayer(opts)
        end,
        addGlobalOption = function() end,
        removeGlobalOption = function() end,
    }
else
    TargetCompat = nil
end
