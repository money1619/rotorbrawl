-- ROTORBRAWL — toupie assemblée à partir des modèles de ses pièces (29/10).
-- Chaque pièce du catalogue a son modèle (stream/spin_pt_<identifiant>.ydr : tools/models/build_parts.py), tous dessinés
-- dans le repère de la toupie assemblée (origine = pointe de l'embout, axe = Z). Une toupie à l'écran = quatre objets
-- locaux : l'EMBOUT est la racine, le verrou, la lame et le noyau y sont attachés sans décalage. Tout le reste du client
-- (placement, inclinaison, vol, masquage, suppression) continue de ne voir que la racine.
-- Si un modèle de pièce manque (ressource incomplète), la toupie retombe sur son modèle monobloc spin_top_<forme>.
SpinArena = SpinArena or {}

local TM = { reg = {}, enabled = true }   -- reg[racine] = { enfants } ; enabled = false : toujours le modèle monobloc (/spin_prop parts off)
SpinArena.TopModel = TM

TM.ORDER = { 'tip', 'frame', 'ring', 'core' }   -- le premier est la racine
TM.DEFAULT_HEIGHT = 0.058                        -- hauteur hors tout d'une toupie assemblée (m), si les dimensions manquent

local function isTruthy(v) return v == true or v == 1 end

local function hashOf(name)
    if type(joaat) == 'function' then return joaat(name) end
    if type(GetHashKey) == 'function' then return GetHashKey(name) end
    return nil
end

-- Noms des quatre modèles (dans l'ordre racine d'abord), ou nil : pièces inconnues ou modèle absent du jeu
function TM.names(parts)
    if not TM.enabled or type(parts) ~= 'table' then return nil end
    local names = {}
    for _, slot in ipairs(TM.ORDER) do
        local id = parts[slot]
        if type(id) ~= 'string' or id:sub(1, #slot + 1) ~= slot .. '_' or not id:match('^[%w_]+$') or #id > 40 then return nil end
        local name = 'spin_pt_' .. id
        if type(IsModelInCdimage) == 'function' then
            local h = hashOf(name)
            if not h or not isTruthy(IsModelInCdimage(h)) then return nil end
        end
        names[#names + 1] = name
    end
    return names
end

local function rawDelete(ent)
    if not ent or ent == 0 then return end
    if type(DoesEntityExist) == 'function' and not isTruthy(DoesEntityExist(ent)) then return end
    if type(DeleteEntity) == 'function' then pcall(DeleteEntity, ent) end
end

-- Crée la toupie. create(nomDeModèle) → entité, fini (même contrat que spawnLocalProp : nil et fini = faux → réessayer plus
-- tard, le modèle se charge). Renvoie racine, vrai ; ou nil, faux (réessayer) ; ou, sans modèles de pièces, celui du modèle monobloc.
-- Les quatre modèles doivent être en mémoire EN MÊME TEMPS avant de créer quoi que ce soit : sinon la création d'une pièce
-- libère son modèle (SetModelAsNoLongerNeeded), la pièce suivante n'est pas encore chargée, tout est repris et la toupie
-- n'apparaît jamais. Au-delà de LOAD_TIMEOUT_MS sans y arriver, repli sur le modèle monobloc.
TM.LOAD_TIMEOUT_MS = 3000
local waitingSince = {}

local function nowMs()
    return (type(GetGameTimer) == 'function' and GetGameTimer()) or 0
end

local function allLoaded(names)
    if type(RequestModel) ~= 'function' or type(HasModelLoaded) ~= 'function' then return true end
    local ready = true
    for _, name in ipairs(names) do
        local h = hashOf(name)
        if not h then return true end
        pcall(RequestModel, h)
        if not isTruthy(HasModelLoaded(h)) then ready = false end
    end
    return ready
end

function TM.spawn(spec, create)
    local names = TM.names(spec.parts)
    if not names then return create(spec.model) end
    local key = table.concat(names, '|')
    if not allLoaded(names) then
        local since = waitingSince[key] or nowMs()
        waitingSince[key] = since
        if nowMs() - since > TM.LOAD_TIMEOUT_MS then
            TM.timedOut = (TM.timedOut or 0) + 1
            return create(spec.model)   -- modèles de pièces introuvables : toupie monobloc
        end
        return nil, false
    end
    waitingSince[key] = nil
    local ents = {}
    for i, name in ipairs(names) do
        local e = create(name)
        if not e or e == 0 then
            for _, x in ipairs(ents) do rawDelete(x) end   -- partielle : tout est repris à la prochaine image
            return nil, false
        end
        ents[i] = e
    end
    local root, kids = ents[1], {}
    for i = 2, #ents do
        local c = ents[i]
        if type(FreezeEntityPosition) == 'function' then pcall(FreezeEntityPosition, c, false) end
        if type(AttachEntityToEntity) == 'function' then
            pcall(AttachEntityToEntity, c, root, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        end
        if type(SetEntityCollision) == 'function' then pcall(SetEntityCollision, c, false, false) end
        kids[#kids + 1] = c
    end
    TM.reg[root] = kids
    return root, true
end

-- Supprime les pièces attachées à cette racine (la racine elle-même est supprimée par l'appelant, comme avant)
function TM.dropChildren(root)
    local kids = TM.reg[root]
    if not kids then return false end
    TM.reg[root] = nil
    for _, c in ipairs(kids) do
        if type(DetachEntity) == 'function' then pcall(DetachEntity, c, true, false) end
        rawDelete(c)
    end
    return true
end

function TM.setVisible(root, visible)
    local kids = TM.reg[root]
    if not kids or type(SetEntityVisible) ~= 'function' then return end
    for _, c in ipairs(kids) do pcall(SetEntityVisible, c, visible, false) end
end

-- Hauteur hors tout (m) : le haut du noyau, lu sur son modèle
function TM.height(parts)
    if type(parts) ~= 'table' or type(parts.core) ~= 'string' or type(GetModelDimensions) ~= 'function' then return nil end
    local h = hashOf('spin_pt_' .. parts.core)
    if not h then return nil end
    local ok, _, mx = pcall(GetModelDimensions, h)
    local z = ok and mx and tonumber(mx.z or mx[3])
    if z and z > 0.02 and z < 0.2 then return z end
    return nil
end

-- Pièces d'une toupie reçues du serveur : quatre identifiants du catalogue ou rien
function TM.normalize(parts)
    if type(parts) ~= 'table' then return nil end
    local out = {}
    for _, slot in ipairs(TM.ORDER) do
        local id = parts[slot]
        if type(id) ~= 'string' or id:sub(1, #slot + 1) ~= slot .. '_' or not id:match('^[%w_]+$') or #id > 40 then return nil end
        out[slot] = id
    end
    out.core = parts.core
    return out
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(res)
        if type(GetCurrentResourceName) == 'function' and res == GetCurrentResourceName() then
            for root in pairs(TM.reg) do TM.dropChildren(root) end
        end
    end)
end

return TM
