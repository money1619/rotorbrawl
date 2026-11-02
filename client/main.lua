-- ROTORBRAWL — Phases 1 & 2 : Point d'entrée client, menus ox_lib, ciblage ox_target et événements
-- Fichier : client/main.lua
-- Écoute uniquement les événements serveur -> client autoritaires (spin_arena:cl:*)
-- et n'envoie que des intentions via lib.callback.await (spin_arena:*).

SpinArena = SpinArena or {}

local Client = {
    state = {
        incoming    = {},   -- liste ordonnée de défis entrants { id, from, fromName, top, station, expiresAtMs }
        outgoing    = nil,  -- défi sortant { id, to, target, toName, top, station, expiresAtMs }
        match       = nil,  -- match actif { matchId, role, side, round, arena }
        tops        = {},   -- dernières toupies reçues via spin_arena:tops
        topsEnabled = false,
        shop        = nil,  -- dernières infos boutique reçues via spin_arena:shop
        stations    = {},   -- stations fixes reçues du serveur
        opponents   = {},   -- adversaires proches reçus via spin_arena:state
        leaderboard = nil,  -- dernier classement reçu via spin_arena:leaderboard
        tournaments = nil,  -- dernier état des tournois reçu via spin_arena:tournament_status
    },
    arenaZoneId       = nil,
    shopZoneIds       = {},
    stationZoneIds    = {},
    stationBlips      = {},
    lastNotification  = nil,
    lastOpenedShop    = nil,
    allowTestProfiles = false,
}
SpinArena.Client = Client

local function getProtocol()
    return (SpinArena and SpinArena.Protocol) or {
        cb = {
            challenge        = 'spin_arena:challenge',
            respond          = 'spin_arena:respond',
            cancel           = 'spin_arena:cancel',
            forfeit          = 'spin_arena:forfeit',
            state            = 'spin_arena:state',
            leaderboard      = 'spin_arena:leaderboard',
            tops             = 'spin_arena:tops',
            workshop         = 'spin_arena:workshop',
            shop             = 'spin_arena:shop',
            tournamentCreate = 'spin_arena:tournament_create',
            tournamentJoin   = 'spin_arena:tournament_join',
            tournamentLeave  = 'spin_arena:tournament_leave',
            tournamentStatus = 'spin_arena:tournament_status',
        },
        ev = {
            challenge = 'spin_arena:cl:challenge',
            match     = 'spin_arena:cl:match',
            countdown = 'spin_arena:cl:countdown',
            frames    = 'spin_arena:cl:frames',
            roundEnd  = 'spin_arena:cl:roundEnd',
            matchEnd  = 'spin_arena:cl:matchEnd',
            cancel    = 'spin_arena:cl:cancel',
            unsub     = 'spin_arena:cl:unsub',
            notify    = 'spin_arena:cl:notify',
            stations  = 'spin_arena:cl:stations',
        },
    }
end

local function getRenderer()
    return SpinArena and SpinArena.Renderer
end

local function nowMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end
    return math.floor(os.clock() * 1000.0)
end

local function makeVec3(x, y, z)
    if type(vec3) == 'function' then
        return vec3(x, y, z)
    elseif type(vector3) == 'function' then
        return vector3(x, y, z)
    end
    return { x = x, y = y, z = z }
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Traduction avec repli sûr si locales/*.lua n'a pas encore été chargé dans un test unitaire isolé
local FALLBACK_FR = {
    home_title                = 'ROTORBRAWL',
    home_challenges           = 'Défis en cours',
    ok                        = 'Opération effectuée.',
    rate_limited              = 'Action trop rapide. Veuillez patienter un instant.',
    invalid                   = 'Requête ou paramètres invalides.',
    busy                      = 'Une opération est déjà en cours.',
    not_found                 = 'Défi ou match introuvable.',
    too_far                   = 'Le joueur ciblé est trop éloigné.',
    in_vehicle                = 'Impossible de combattre depuis un véhicule.',
    dead                      = 'Impossible de combattre dans cet état.',
    same_player               = 'Vous ne pouvez pas vous défier vous-même.',
    already_in_match          = 'Vous participez déjà à un match.',
    target_busy               = 'Ce joueur a déjà un défi en attente ou un match en cours.',
    no_arena                  = 'Aucun espace disponible ici pour déployer une arène.',
    no_zone                   = 'Le combat improvisé n\'est pas autorisé dans cette zone.',
    server_busy               = 'Nombre maximal de matchs simultanés atteint sur le serveur.',
    expired                   = 'Ce défi a expiré.',
    other_bucket              = 'Ce joueur ne se trouve pas dans la même instance.',
    offline                   = 'Le joueur ciblé n\'est plus connecté.',
    no_top                    = 'Cette toupie est introuvable dans votre inventaire.',
    no_launcher               = 'Il te faut un lanceur dans ton inventaire. Passe à la boutique ROTORBRAWL.',
    top_locked                = 'Cette toupie est déjà engagée dans un match ou à l\'atelier.',
    top_invalid               = 'L\'assemblage de cette toupie est invalide.',
    no_part                   = 'Pièce ou kit de réparation manquant dans votre inventaire.',
    inventory_full            = 'Votre inventaire est plein.',
    over_budget               = 'Cet assemblage dépasse le budget maximal de 100 points.',
    db_unavailable            = 'Base de données ou inventaire momentanément indisponible.',
    pro_only                  = 'Cette fonction fait partie de l\'édition Pro de ROTORBRAWL.',
    not_allowed               = 'Vous n\'avez pas la permission d\'effectuer cette action.',
    tournament_closed         = 'Les inscriptions à ce tournoi sont fermées.',
    tournament_full           = 'Ce tournoi est complet.',
    already_registered        = 'Vous êtes déjà inscrit à ce tournoi.',
    error                     = 'Une erreur interne est survenue.',
    leave_zone_warning        = 'Attention : retournez dans la zone sous {seconds} s sous peine d\'abandon.',
    tournament_created        = 'Tournoi « {tournament} » (#{id}, {size} joueurs) ouvert pendant {minutes} min !',
    tournament_started        = 'Le tournoi « {tournament} » démarre ({players} participants) !',
    tournament_match_ready    = 'Tournoi « {tournament} » : votre match contre {opponent} est prêt ({seconds} s) !',
    tournament_eliminated     = 'Vous avez été éliminé du tournoi « {tournament} » au tour {round}.',
    tournament_won            = '{name} remporte le tournoi « {tournament} » !',
    tournament_live           = 'Le tournoi « {tournament} » commence ({players} participants) : rendez-vous aux gradins !',
    tournament_reward_winner  = 'Victoire au tournoi « {tournament} » : {amount} $ versés.',
    tournament_reward_finalist = 'Finale du tournoi « {tournament} » : {amount} $ versés.',
    tournament_no_winner      = 'Le tournoi « {tournament} » s\'est terminé sans vainqueur.',
    tournament_cancelled      = 'Le tournoi « {tournament} » a été annulé ({reason}).',
    tournament_invalid_top    = 'Tournoi « {tournament} » : votre toupie inscrite est indisponible ({code}).',
    dialog_title              = 'ROTORBRAWL — Duel de toupies',
    dialog_select_top         = 'Choisir le profil de toupie',
    dialog_top_attack         = 'Prototype A (Attaque)',
    dialog_top_endurance      = 'Prototype E (Endurance)',
    target_challenge          = 'Défier à ROTORBRAWL',
    target_station_challenge  = 'Défier sur cette station',
    station_title             = 'Station ROTORBRAWL — {station}',
    station_no_opponents      = 'Aucun adversaire à proximité de la station.',
    station_opponent_desc     = 'Joueur #{id} ({distance} m)',
    target_accept             = 'Accepter le défi',
    target_decline            = 'Refuser le défi',
    target_cancel             = 'Annuler mon défi',
    target_forfeit            = 'Abandonner le match',
    target_workshop           = 'Atelier de toupies (Mes toupies)',
    target_shop               = 'Boutique ROTORBRAWL',
    target_leaderboard        = 'Classement ROTORBRAWL',
    target_tournaments        = 'Tournois ROTORBRAWL',
    shop_unavailable          = 'La boutique ROTORBRAWL est actuellement indisponible.',
    leaderboard_title         = 'Classement ROTORBRAWL — Saison {season}',
    leaderboard_me_title      = 'Mon classement : #{rank} ({rating} Elo)',
    leaderboard_me_unranked   = 'Mon classement : Non classé ({rating} Elo)',
    leaderboard_me_desc       = '{name} — Bilan : {w}V - {l}D - {d}N',
    leaderboard_row_title     = '#{rank} — {name} ({rating} Elo)',
    leaderboard_row_desc      = 'Bilan : {w}V - {l}D - {d}N',
    leaderboard_empty         = 'Aucun joueur classé pour cette saison.',
    tournaments_title         = 'Tournois ROTORBRAWL',
    tournaments_empty         = 'Aucun tournoi actif ou récent.',
    tournament_create_title   = 'Créer un tournoi',
    tournament_create_desc    = 'Ouvrir les inscriptions d\'un nouveau tournoi (4, 8 ou 16 joueurs)',
    tournament_input_name     = 'Nom du tournoi (3 à 32 caractères)',
    tournament_input_size     = 'Taille du tableau (4, 8 ou 16 joueurs)',
    tournament_input_minutes  = 'Durée des inscriptions (minutes, 1 à 60)',
    tournament_row_title      = '#{id} — {name} [{state}] ({players}/{size})',
    tournament_row_desc       = 'Organisateur : {organizer}{extra}',
    tournament_state_signup   = 'Inscriptions',
    tournament_state_running  = 'En cours',
    tournament_state_finished = 'Terminé',
    tournament_state_cancelled = 'Annulé',
    tournament_join_title     = 'Rejoindre ce tournoi (choisir ma toupie)',
    tournament_join_desc      = 'Inscrire une toupie possédée et complète ({players}/{size})',
    tournament_leave_title    = 'Se désinscrire du tournoi',
    tournament_leave_desc     = 'Retirer votre inscription tant que le tournoi n\'a pas démarré',
    tournament_mymatch_title  = 'Mon match (Tour {round}) : contre {opponent}',
    tournament_mymatch_desc   = 'État : {state} — Temps restant : {seconds} s',
    tournament_players_title  = 'Participants inscrits ({count}/{size})',
    tournament_round_header   = 'Tour {round} — {a} contre {b} [{state}]',
    tournament_round_winner   = 'Vainqueur : {winner}',
    tournament_created_ok     = 'Tournoi « {name} » (#{id}) créé avec succès.',
    tournament_joined_ok      = 'Inscription au tournoi #{id} confirmée ({players}/{size}).',
    tournament_left_ok        = 'Vous avez quitté le tournoi.',
    workshop_title            = 'ROTORBRAWL — Mes toupies',
    workshop_empty            = 'Aucune toupie dans votre inventaire.',
    workshop_top_desc         = '[{uid}] Famille : {family} | Peinture : {paint} | Budget : {cost}/{budget} | Usure : {wear} | Bilan : {w}V-{l}D-{d}N',
    workshop_stats_title      = 'Caractéristiques de combat',
    workshop_stats_desc       = 'ATQ {atk} | DÉF {def} | STAB {stab} | END {endurance} | MOB {mob}',
    workshop_slot_title       = '{slot} : {part} ({cost} pts)',
    workshop_slot_desc        = 'Pour la changer : glisse une pièce sur la toupie dans ton inventaire ({mods})',
    workshop_disassemble_title = 'Démonter la toupie',
    workshop_disassemble_again = 'Appuie de nouveau sur « Démonter » dans les 5 s pour confirmer.',
    workshop_disassemble_desc = 'Toutes ses pièces reviennent dans ton inventaire',
    workshop_disassemble_confirm = 'Démonter cette toupie ? Elle disparaît et toutes ses pièces reviennent dans ton inventaire.',
    workshop_part_equip       = '{label} ({cost} pts) — x{count}',
    workshop_part_equipped    = '{label} ({cost} pts) [Équipée]',
    workshop_no_parts_owned   = 'Aucune pièce compatible dans votre inventaire.',
    workshop_repair_title     = 'Réparer la toupie (Kit de réparation)',
    workshop_repair_desc      = 'Usure actuelle : {wear} — remet l\'usure à 0',
    workshop_rename_title     = 'Renommer la toupie',
    workshop_rename_desc      = 'Nom actuel : {name} (1 à 24 caractères)',
    workshop_rename_input     = 'Nouveau nom de la toupie',
    workshop_paint_title      = 'Changer la peinture',
    workshop_paint_desc       = 'Peinture actuelle : {paint}',
    workshop_equipped_ok      = 'Pièce équipée avec succès.',
    workshop_repaired_ok      = 'Toupie réparée avec succès.',
    workshop_renamed_ok       = 'Toupie renommée en « {name} ».',
    workshop_painted_ok       = 'Peinture appliquée avec succès.',
    select_top_real_desc      = 'Famille : {family} | Usure : {wear} | {w}V-{l}D',
    select_top_locked_suffix  = ' (Verrouillée)',
    select_top_invalid_suffix = ' (Incomplète)',
}

local function L(key, args)
    if SpinArena and type(SpinArena.L) == 'function' then
        return SpinArena.L(key, args)
    end
    local tpl = FALLBACK_FR[key] or tostring(key)
    if type(args) == 'table' then
        return (tpl:gsub('{([%w_]+)}', function(k)
            local v = args[k]
            return v ~= nil and tostring(v) or ('{' .. k .. '}')
        end))
    end
    return tpl
end

-- Notification unifiée (ox_lib si présent + repli chat/console)
function Client.notify(description, notifType, title)
    local msg = tostring(description or '')
    local kind = notifType or 'inform'
    local hdr = title or 'ROTORBRAWL'
    Client.lastNotification = { title = hdr, description = msg, type = kind, atMs = nowMs() }

    if type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({
            title       = hdr,
            description = msg,
            type        = kind,
            position    = 'top-right',
        })
        return
    end

    if type(TriggerEvent) == 'function' then
        pcall(TriggerEvent, 'chat:addMessage', { args = { hdr, msg } })
    end
end

local function notifyCodeError(code)
    local key = tostring(code or 'error')
    Client.notify(L(key), 'error')
end

local function normalizeTopChoice(raw)
    if type(raw) ~= 'string' then return nil end
    local trimmed = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed == '' then return nil end
    local up = trimmed:upper()
    if up:match('^ST[0-9A-Z]+$') then
        return up
    end
    local s = trimmed:lower()
    if s == 'attack' or s == 'atk' or s == 'a' or s == '1' then
        return 'attack'
    elseif s == 'endurance' or s == 'end' or s == 'e' or s == '2' then
        return 'endurance'
    elseif s == 'defense' or s == 'def' or s == 'balance' or s == 'mobility' then
        return s
    end
    return trimmed
end

-- Interroge la liste des toupies possédées par le joueur (spin_arena:tops)
function Client.fetchTops()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error', enabled = false, tops = {} }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.tops, false, {})
    if not ok or type(res) ~= 'table' then
        return { ok = false, code = 'error', enabled = false, tops = {} }
    end
    if res.ok then
        Client.state.topsEnabled = (res.enabled == true)
        Client.state.tops = type(res.tops) == 'table' and res.tops or {}
    end
    return res
end

local function getFamilyLabel(familyKey)
    local partsCfg = SpinArena and SpinArena.Parts
    if partsCfg and partsCfg.kits and partsCfg.kits[familyKey] and partsCfg.kits[familyKey].label then
        return partsCfg.kits[familyKey].label
    end
    return tostring(familyKey or 'balance')
end

local function getPaintLabel(paintKey)
    local partsCfg = SpinArena and SpinArena.Parts
    if partsCfg and partsCfg.paints and partsCfg.paints[paintKey] and partsCfg.paints[paintKey].label then
        return partsCfg.paints[paintKey].label
    end
    return tostring(paintKey or 'titanium')
end

local function isTopAssemblyComplete(top)
    if type(top) ~= 'table' then return false end
    local statsMod = SpinArena and SpinArena.Stats
    if statsMod and type(statsMod.validate) == 'function' then
        -- validate returns the numeric assembly cost, not a boolean.
        return statsMod.validate(top.parts) ~= nil
    end
    return type(top.parts) == 'table' and type(top.stats) == 'table'
end

-- Sélection de toupie via lib.inputDialog si disponible en repli de lib.registerContext
local function promptTopIfAvailable(defaultTop, choices)
    local opts = {}
    if type(choices) == 'table' and #choices > 0 then
        for i = 1, #choices do
            if not choices[i].disabled then
                opts[#opts + 1] = { value = choices[i].value, label = choices[i].title }
            end
        end
    end
    if #opts == 0 then
        return nil
    end
    if type(lib) == 'table' and type(lib.inputDialog) == 'function' then
        local defVal = (opts[1] and opts[1].value) or defaultTop or 'attack'
        local ok, res = pcall(lib.inputDialog, L('dialog_title'), {
            {
                type     = 'select',
                label    = L('dialog_select_top'),
                default  = defVal,
                required = true,
                options  = opts,
            },
        })
        if ok and type(res) == 'table' and type(res[1]) == 'string' then
            return normalizeTopChoice(res[1]) or defVal
        elseif ok and res == nil then
            return nil
        end
    end
    return (opts[1] and opts[1].value) or defaultTop or 'attack'
end

-- Construit la liste des toupies proposées au défi / à l'acceptation :
-- toupies possédées complètes et non verrouillées (top = uid).
-- Les profils de test restent réservés à une autorisation explicite de diagnostic ;
-- l'absence d'inventaire ou de toupie ne les active jamais.
-- Liste de choix d'une toupie (défis, tournois) : nom + identifiant court, icône et couleur de peinture, usure en barre
local FAMILY_ICONS = {
    attack = 'fa-solid fa-burst', defense = 'fa-solid fa-shield-halved', endurance = 'fa-solid fa-hourglass-half',
    balance = 'fa-solid fa-scale-balanced', mobility = 'fa-solid fa-wind',
}
local function topChoiceLook(t, idLen)
    local P = SpinArena and SpinArena.Parts or {}
    local paint = P.paints and P.paints[t.paint]
    local c = paint and paint.color
    local iconColor = type(c) == 'table' and ('#%02X%02X%02X'):format(c[1] or 0, c[2] or 0, c[3] or 0) or nil
    local wear, wearFree, wearMax = tonumber(t.wear) or 0, tonumber(P.wearFree) or 10, tonumber(P.wearMax) or 40
    local progress = math.floor(math.min(100, wear / math.max(1, wearMax) * 100) + 0.5)
    local scheme = wear > wearFree and 'red' or (wear > wearFree / 2 and 'orange' or 'green')
    local shortId = tostring(t.uid):sub(-(idLen or 4))
    return {
        title = ('%s · #%s'):format(tostring(t.name or t.uid), shortId),
        icon = FAMILY_ICONS[t.family] or 'fa-solid fa-compact-disc',
        iconColor = iconColor, progress = progress, colorScheme = scheme,
        needsRepair = wear > wearFree,
    }
end

local function buildTopSelectionChoices()
    local res = Client.fetchTops()
    local choices = {}
    local lockedChoices = {}
    local unlockedCount = 0
    local enabled = (type(res) == 'table' and res.ok and res.enabled == true)

    -- Identifiant court : 4 derniers caractères, allongé si deux toupies du joueur les partagent (jamais ambigu)
    local idLen = 4
    if type(res) == 'table' and type(res.tops) == 'table' then
        local function clash(n)
            local seen = {}
            for _, t in ipairs(res.tops) do
                local k = type(t) == 'table' and type(t.uid) == 'string' and t.uid:sub(-n)
                if k then if seen[k] then return true end seen[k] = true end
            end
            return false
        end
        while clash(idLen) and idLen < 24 do idLen = idLen + 2 end
    end
    if type(res) == 'table' and res.ok and type(res.tops) == 'table' then
        for i = 1, #res.tops do
            local t = res.tops[i]
            if type(t) == 'table' and type(t.uid) == 'string' then
                local famLabel = getFamilyLabel(t.family)
                local look = topChoiceLook(t, idLen)
                local desc = L('select_top_real_desc', {
                    family = famLabel,
                    paint  = getPaintLabel(t.paint),
                    wear   = tonumber(t.wear) or 0,
                    w      = tonumber(t.wins) or 0,
                    l      = tonumber(t.losses) or 0,
                    repair = look.needsRepair and L('select_top_repair') or '',
                })
                local complete = isTopAssemblyComplete(t)
                if t.locked then
                    lockedChoices[#lockedChoices + 1] = {
                        value       = t.uid,
                        title       = look.title .. L('select_top_locked_suffix'),
                        description = desc,
                        icon        = 'fa-solid fa-lock',
                        disabled    = true,
                    }
                elseif not complete then
                    lockedChoices[#lockedChoices + 1] = {
                        value       = t.uid,
                        title       = look.title .. L('select_top_invalid_suffix'),
                        description = desc,
                        icon        = 'fa-solid fa-triangle-exclamation',
                        disabled    = true,
                    }
                else
                    unlockedCount = unlockedCount + 1
                    choices[#choices + 1] = {
                        value       = t.uid,
                        title       = look.title,
                        description = desc,
                        icon        = look.icon,
                        iconColor   = look.iconColor,
                        progress    = look.progress,
                        colorScheme = look.colorScheme,
                        disabled    = false,
                    }
                end
            end
        end
    end

    local allowTest = (Client.allowTestProfiles == true)
        or (SpinArena and SpinArena.ServerConfig and SpinArena.ServerConfig.allowTestProfiles == true)
    if allowTest then
        choices[#choices + 1] = {
            value       = 'attack',
            title       = L('dialog_top_attack'),
            description = L('dialog_select_top'),
            icon        = 'fa-solid fa-burst',
            disabled    = false,
        }
        choices[#choices + 1] = {
            value       = 'endurance',
            title       = L('dialog_top_endurance'),
            description = L('dialog_select_top'),
            icon        = 'fa-solid fa-shield-halved',
            disabled    = false,
        }
        unlockedCount = unlockedCount + 2
    end

    for i = 1, #lockedChoices do
        choices[#choices + 1] = lockedChoices[i]
    end

    return choices, enabled, unlockedCount
end

-- Ouvre un menu contextuel ox_lib (toupies possédées complètes) ou refuse si aucune toupie complète n'est disponible
local function selectTopAndRun(contextId, defaultTop, callback)
    local choices, _, unlockedCount = buildTopSelectionChoices()

    if unlockedCount == 0 then
        notifyCodeError('no_top')
        if #choices == 0 then
            choices[#choices + 1] = {
                value       = '',
                title       = L('workshop_empty'),
                description = L('no_top'),
                icon        = 'fa-solid fa-circle-info',
                disabled    = true,
            }
        end
    end

    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        local options = {}
        for i = 1, #choices do
            local c = choices[i]
            options[#options + 1] = {
                title       = c.title,
                description = c.description,
                icon        = c.icon,
                iconColor   = c.iconColor,
                progress    = c.progress,
                colorScheme = c.colorScheme,
                disabled    = c.disabled,
                onSelect    = not c.disabled and function()
                    callback(c.value)
                end or nil,
            }
        end
        lib.registerContext({
            id      = contextId,
            title   = L('dialog_title'),
            options = options,
        })
        lib.showContext(contextId)
        return
    end

    local chosen = promptTopIfAvailable(defaultTop or 'attack', choices)
    if chosen then
        callback(chosen)
    end
end

local function removeIncomingById(id)
    local list = Client.state.incoming
    for i = #list, 1, -1 do
        if list[i].id == id then
            table.remove(list, i)
        end
    end
end

local function upsertIncoming(entry)
    removeIncomingById(entry.id)
    Client.state.incoming[#Client.state.incoming + 1] = entry
end

local function findIncomingFrom(serverId)
    local sid = tonumber(serverId)
    if not sid then return nil end
    local list = Client.state.incoming
    for i = #list, 1, -1 do
        local inc = list[i]
        if inc.from == sid then
            return inc
        end
    end
    return nil
end

local function hasOutgoingTo(serverId)
    local sid = tonumber(serverId)
    if not sid then return false end
    local out = Client.state.outgoing
    if not out then return false end
    return (out.to == sid or out.target == sid)
end

local function isParticipantInMatch()
    return Client.state.match ~= nil and Client.state.match.role == 'participant'
end

local function getLocalServerId()
    if type(PlayerId) == 'function' and type(GetPlayerServerId) == 'function' then
        local pid = PlayerId()
        if pid ~= nil then
            return tonumber(GetPlayerServerId(pid))
        end
    end
    return nil
end

local function resolveTargetServerId(entityOrData)
    local entity = entityOrData
    if type(entityOrData) == 'table' then
        if tonumber(entityOrData.serverId) then
            return tonumber(entityOrData.serverId)
        end
        entity = entityOrData.entity
    end
    if not entity or entity == 0 then return nil end
    if type(NetworkGetPlayerIndexFromPed) == 'function' and type(GetPlayerServerId) == 'function' then
        local playerIdx = NetworkGetPlayerIndexFromPed(entity)
        if playerIdx and playerIdx ~= -1 then
            return tonumber(GetPlayerServerId(playerIdx))
        end
    end
    return nil
end

-- Interroge l'état serveur (spin_arena:state) et synchronise Client.state
function Client.fetchState()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.state, false, {})
    if type(res) == 'table' and res.ok then
        local now = nowMs()
        Client.state.incoming = {}
        if type(res.incoming) == 'table' then
            for i = 1, #res.incoming do
                local inc = res.incoming[i]
                if type(inc) == 'table' and tonumber(inc.id) then
                    Client.state.incoming[#Client.state.incoming + 1] = {
                        id          = tonumber(inc.id),
                        from        = tonumber(inc.from),
                        fromName    = tostring(inc.fromName or '?'),
                        top         = tostring(inc.top or 'attack'),
                        station     = type(inc.station) == 'string' and inc.station or nil,
                        expiresAtMs = now + (tonumber(inc.expiresInMs) or 30000),
                    }
                end
            end
        end
        if type(res.outgoing) == 'table' and tonumber(res.outgoing.id) then
            local toSid = tonumber(res.outgoing.to or res.outgoing.target)
            Client.state.outgoing = {
                id          = tonumber(res.outgoing.id),
                to          = toSid,
                target      = toSid,
                toName      = tostring(res.outgoing.toName or '?'),
                top         = tostring(res.outgoing.top or 'attack'),
                station     = type(res.outgoing.station) == 'string' and res.outgoing.station or nil,
                expiresAtMs = now + (tonumber(res.outgoing.expiresInMs) or 30000),
            }
        else
            Client.state.outgoing = nil
        end
        if type(res.stations) == 'table' then
            Client.state.stations = res.stations
        end
        Client.state.opponents = type(res.opponents) == 'table' and res.opponents or {}
        Client.state.match = type(res.match) == 'table' and res.match or nil
    end
    return res
end

-- Envoie un défi à un joueur (spin_arena:challenge), optionnellement sur une station fixe nommée
function Client.challenge(targetServerId, topKey, stationName)
    local target = tonumber(targetServerId)
    if not target or target < 1 then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    local chosenTop = normalizeTopChoice(topKey) or 'attack'
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local payload = {
        target = math.floor(target),
        top    = chosenTop,
    }
    if type(stationName) == 'string' and stationName ~= '' then
        payload.station = stationName
    end
    local res = lib.callback.await(P.cb.challenge, false, payload)
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end

    local tSid = math.floor(target)
    Client.state.outgoing = {
        id          = tonumber(res.id),
        to          = tSid,
        target      = tSid,
        toName      = '#' .. tostring(tSid),
        top         = chosenTop,
        station     = payload.station,
        expiresAtMs = nowMs() + 30000,
    }
    Client.notify(L('challenge_sent', {
        id     = tostring(res.id or '?'),
        toName = '#' .. tostring(tSid),
        top    = chosenTop,
    }), 'success')
    return res
end

-- Répond à un défi entrant (spin_arena:respond)
function Client.respond(challengeId, accept, topKey)
    local id = tonumber(challengeId)
    if not id then
        local latest = Client.state.incoming[#Client.state.incoming]
        if latest then
            id = latest.id
        else
            local st = Client.fetchState()
            if st and st.ok and #Client.state.incoming > 0 then
                id = Client.state.incoming[#Client.state.incoming].id
            end
        end
    end
    if not id then
        Client.notify(L('cmd_no_incoming'), 'warning')
        return { ok = false, code = 'not_found' }
    end

    local isAccept = (accept == true)
    local payload = {
        id     = math.floor(id),
        accept = isAccept,
    }
    if isAccept then
        payload.top = normalizeTopChoice(topKey) or 'attack'
    end

    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local res = lib.callback.await(P.cb.respond, false, payload)
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end

    if not res.ok then
        if res.code == 'not_found' or res.code == 'expired' then
            removeIncomingById(math.floor(id))
        end
        notifyCodeError(res.code)
        return res
    end

    removeIncomingById(math.floor(id))
    if isAccept then
        Client.state.outgoing = nil
        Client.notify(L('challenge_accepted', { id = math.floor(id) }), 'success')
    else
        Client.notify(L('challenge_declined', { id = math.floor(id) }), 'inform')
    end
    return res
end

-- Annule un défi sortant en attente (spin_arena:cancel)
function Client.cancelChallenge(challengeId)
    local id = tonumber(challengeId) or (Client.state.outgoing and Client.state.outgoing.id)
    if not id then
        local st = Client.fetchState()
        if st and st.ok and Client.state.outgoing then
            id = Client.state.outgoing.id
        end
    end
    if not id then
        Client.notify(L('cmd_no_outgoing'), 'warning')
        return { ok = false, code = 'not_found' }
    end

    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local res = lib.callback.await(P.cb.cancel, false, { id = math.floor(id) })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        if res.code == 'not_found' or res.code == 'expired' then
            Client.state.outgoing = nil
        end
        notifyCodeError(res.code)
        return res
    end

    Client.state.outgoing = nil
    Client.notify(L('challenge_cancelled', { id = math.floor(id) }), 'inform')
    return res
end

-- Abandonne le match en cours (ou annule le défi sortant si pas encore en match)
function Client.forfeit()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local res = lib.callback.await(P.cb.forfeit, false, {})
    if type(res) == 'table' and res.ok then
        Client.notify(L('forfeit_confirmed'), 'warning')
        return res
    end

    if type(res) == 'table' and res.code == 'not_found' and Client.state.outgoing and Client.state.outgoing.id then
        return Client.cancelChallenge(Client.state.outgoing.id)
    end

    notifyCodeError(type(res) == 'table' and res.code or 'error')
    return res or { ok = false, code = 'error' }
end

-- Gestion de la zone ox_target sur l'arène pendant un match actif
function Client.removeArenaZone()
    local zid = Client.arenaZoneId
    Client.arenaZoneId = nil
    if not zid then return end
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then return end
    pcall(function()
        TargetCompat:removeZone(zid, true)
    end)
end

function Client.createArenaZone(arena)
    Client.removeArenaZone()
    if type(arena) ~= 'table' or not tonumber(arena.x) or not tonumber(arena.y) or not tonumber(arena.z) then
        return nil
    end
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then
        return nil
    end
    local ok, targetExport = pcall(function() return TargetCompat end)
    if not ok or not targetExport then
        return nil
    end

    local radius = (tonumber(arena.R) or 0.6) * (tonumber(arena.scale) or 1.0) + 0.5
    local coords = makeVec3(tonumber(arena.x), tonumber(arena.y), tonumber(arena.z))
    local addedOk, zoneId = pcall(function()
        return targetExport:addSphereZone({
            name    = 'spin_arena:arena_zone',
            coords  = coords,
            radius  = radius,
            options = {
                {
                    name        = 'spin_arena:forfeit',
                    icon        = 'fa-solid fa-flag',
                    label       = L('target_forfeit'),
                    distance    = 7.0,
                    canInteract = function()
                        return isParticipantInMatch()
                    end,
                    onSelect    = function()
                        Client.forfeit()
                    end,
                },
            },
        })
    end)
    if addedOk and zoneId then
        Client.arenaZoneId = zoneId
        return zoneId
    end
    return nil
end

-- Gestionnaire de l'événement serveur spin_arena:cl:challenge
function Client.onChallengeEvent(payload)
    if type(payload) ~= 'table' then return false end
    local kind = tostring(payload.kind or '')
    local id = tonumber(payload.id)
    local now = nowMs()

    if kind == 'incoming' and id then
        upsertIncoming({
            id          = id,
            from        = tonumber(payload.from),
            fromName    = tostring(payload.fromName or '?'),
            top         = tostring(payload.top or 'attack'),
            station     = type(payload.station) == 'string' and payload.station or nil,
            expiresAtMs = now + (tonumber(payload.expiresInMs) or 30000),
        })
        Client.notify(L('challenge_incoming', {
            id       = id,
            fromName = tostring(payload.fromName or '?'),
            top      = tostring(payload.top or 'attack'),
        }), 'inform')
        return true
    elseif kind == 'accepted' then
        if Client.state.outgoing and (not id or Client.state.outgoing.id == id) then
            Client.state.outgoing = nil
        end
        if id then removeIncomingById(id) end
        Client.notify(L('challenge_accepted', { id = id or '?' }), 'success')
        return true
    elseif kind == 'declined' then
        if Client.state.outgoing and (not id or Client.state.outgoing.id == id) then
            Client.state.outgoing = nil
        end
        if id then removeIncomingById(id) end
        Client.notify(L('challenge_declined', { id = id or '?' }), 'warning')
        return true
    elseif kind == 'expired' then
        if Client.state.outgoing and (not id or Client.state.outgoing.id == id) then
            Client.state.outgoing = nil
        end
        if id then removeIncomingById(id) end
        Client.notify(L('challenge_expired', { id = id or '?' }), 'warning')
        return true
    elseif kind == 'cancelled' then
        if Client.state.outgoing and (not id or Client.state.outgoing.id == id) then
            Client.state.outgoing = nil
        end
        if id then removeIncomingById(id) end
        Client.notify(L('challenge_cancelled', { id = id or '?' }), 'inform')
        return true
    end
    return false
end

-- Gestionnaire de l'événement serveur spin_arena:cl:notify
-- Résultats d'assemblage par glisser-déposer (ox_inventory) : succès en vert, le reste en avertissement
local NOTIFY_SUCCESS = { assemble_ok = true, assemble_new = true, repair_ok = true, owed_delivered = true }

-- File d'attente d'une table : inscription (toupie choisie) et départ ; le serveur revérifie tout
function Client.queueJoin(station, top)
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' then return nil end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.queueJoin or 'spin_arena:queue_join', false, { station = station, top = top })
    if type(res) == 'table' and res.ok then
        Client.state.queued = station
        Client.notify(L('queue_joined', { waiting = res.waiting or 1 }), 'success')
    else
        notifyCodeError(type(res) == 'table' and res.code or 'error')
    end
    return res
end

function Client.queueLeave()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' then return nil end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.queueLeave or 'spin_arena:queue_leave', false, {})
    Client.state.queued = nil
    if type(res) == 'table' and res.ok then Client.notify(L('queue_left_ok'), 'inform') end
    return res
end

function Client.onNotifyEvent(payload)
    if type(payload) ~= 'table' or not payload.code then return false end
    local code = tostring(payload.code)
    -- Arguments affichables : libellés du catalogue pour la pièce et l'emplacement (jamais l'identifiant brut)
    local args = {}
    if type(payload.args) == 'table' then for k, v in pairs(payload.args) do args[k] = v end end
    local P = SpinArena.Parts
    local def = P and P.catalog and type(args.part) == 'string' and P.catalog[args.part]
    if def then args.part = def.label or args.part end
    local slot = type(args.slot) == 'string' and args.slot or (def and def.slot)
    if slot then args.slot = (P and P.slotLabels and P.slotLabels[slot]) or slot end
    local msg = L(code, args)
    Client.notify(msg, NOTIFY_SUCCESS[code] and 'success' or 'warning')
    return true
end

local function terminalMatchesCurrent(payload)
    if type(payload) ~= 'table' or type(payload.matchId) ~= 'string' then return false end
    local current = Client.state.match
    if current ~= nil then
        return current.matchId == payload.matchId
    end
    local r = getRenderer()
    local scene = r and type(r.getActiveScene) == 'function' and r.getActiveScene() or nil
    if scene and scene.matchId then
        return scene.matchId == payload.matchId
    end
    return true
end

local function buildNetEvents()
    local P = getProtocol()
    return {
        [P.ev.challenge] = function(payload)
            Client.onChallengeEvent(payload)
        end,
        [P.ev.match] = function(payload)
            if type(payload) == 'table' and payload.matchId then
                local role = payload.role or 'participant'
                local inRound = tonumber(payload.round) or 1
                local inRev = tonumber(payload.revision or payload.rev) or 0
                local cur = Client.state.match
                -- Autre combat proche (tables voisines) : seulement affiché, l'état du joueur (son match) ne change pas
                if cur and cur.matchId ~= payload.matchId and role ~= 'participant' then
                    local r0 = getRenderer()
                    if r0 then r0.onMatch(payload) end
                    return
                end
                local r = getRenderer()
                local scene = r and (type(r.getScene) == 'function' and r.getScene(payload.matchId)
                    or (type(r.getActiveScene) == 'function' and r.getActiveScene())) or nil
                if scene and scene.matchId == payload.matchId then
                    if scene.state == 'match_ended' then
                        return
                    end
                    local scRound = tonumber(scene.round) or 1
                    local scRev = tonumber(scene.revision) or 0
                    if scene.state == 'ended' and (inRound < scRound or (inRound == scRound and inRev <= scRev)) then
                        return
                    end
                end
                if cur and cur.matchId == payload.matchId then
                    local curRound = tonumber(cur.round) or 1
                    local curRev = tonumber(cur.revision) or 0
                    if inRound < curRound or (inRound == curRound and inRev < curRev) then
                        return
                    end
                end
                local isSameMatch = (cur ~= nil and cur.matchId == payload.matchId)
                Client.state.match = {
                    matchId  = payload.matchId,
                    role     = role,
                    side     = payload.side ~= nil and payload.side or (isSameMatch and cur.side or nil),
                    round    = inRound,
                    revision = inRev,
                    bestOf   = tonumber(payload.bestOf) or (isSameMatch and cur.bestOf or nil),
                    arena    = payload.arena or (isSameMatch and cur.arena or nil),
                    -- Entraînement admin (/spin_test pratique) : côté 2 simulé par le serveur
                    practice = payload.practice == true or (isSameMatch and cur.practice) or nil,
                    names    = type(payload.names) == 'table' and payload.names or (isSameMatch and cur.names or nil),
                }
                if role == 'participant' then
                    Client.state.queued = nil
                    Client.state.outgoing = nil
                    Client.state.incoming = {}
                    if type(payload.arena) == 'table' and (not isSameMatch or not Client.arenaZoneId) then
                        Client.createArenaZone(payload.arena)
                    end
                end
            end
            local r = getRenderer()
            if r then r.onMatch(payload) end
        end,
        [P.ev.countdown] = function(payload)
            local r = getRenderer()
            if r then r.onCountdown(payload) end
        end,
        -- File d'attente d'une table : panneau (joueurs autour) ; mon inscription se termine au départ du match
        [P.ev.queue or 'spin_arena:cl:queue'] = function(payload)
            if type(payload) ~= 'table' then return end
            if Client.state.queued == payload.stationId and (tonumber(payload.waiting) or 0) == 0 then Client.state.queued = nil end
            local r = getRenderer()
            if r and type(r.onQueue) == 'function' then r.onQueue(payload) end
        end,
        -- Préparation du lancement manuel : entretient la scène (pas de nettoyage pour silence pendant l'attente)
        [P.ev.prepare or 'spin_arena:cl:prepare'] = function(payload)
            local r = getRenderer()
            if r and type(r.onPrepare) == 'function' then r.onPrepare(payload) end
        end,
        [P.ev.frames] = function(payload)
            local r = getRenderer()
            if r then r.onFrames(payload) end
        end,
        [P.ev.roundEnd] = function(payload)
            local r = getRenderer()
            if r then r.onRoundEnd(payload) end
            if type(payload) == 'table' and payload.matchId then
                local cur = Client.state.match
                local inRound = tonumber(payload.round) or 1
                local inRev = tonumber(payload.revision or payload.rev) or 0
                if cur and cur.matchId == payload.matchId
                    and inRound >= (tonumber(cur.round) or 1)
                    and inRev >= (tonumber(cur.revision) or 0)
                    and (cur.bestOf == 1 or tostring(payload.matchId):find('^debug%-') ~= nil) then
                    Client.state.match = nil
                    Client.removeArenaZone()
                end
            end
        end,
        [P.ev.matchEnd] = function(payload)
            if not terminalMatchesCurrent(payload) then
                -- Fin d'un autre combat proche : son affichage seulement (bannière, panneau), pas d'annonce au joueur
                local r0 = getRenderer()
                if r0 and type(r0.onMatchEnd) == 'function' then r0.onMatchEnd(payload) end
                return
            end
            local r = getRenderer()
            local scene = r and (type(r.getScene) == 'function' and type(payload) == 'table' and r.getScene(payload.matchId)
                or (type(r.getActiveScene) == 'function' and r.getActiveScene())) or nil
            if Client.state.match == nil and scene and scene.matchId == payload.matchId and scene.state == 'match_ended' then
                return
            end
            Client.state.match = nil
            Client.removeArenaZone()
            if r and type(r.onMatchEnd) == 'function' then
                r.onMatchEnd(payload)
            elseif r then
                r.onCancel(payload)
            end
            if type(payload) == 'table' then
                local sA = (type(payload.score) == 'table' and (payload.score[1] or payload.score.a)) or 0
                local sB = (type(payload.score) == 'table' and (payload.score[2] or payload.score.b)) or 0
                local reasonKey = 'reason_' .. tostring(payload.reason or 'rounds')
                local reasonTxt = L(reasonKey)
                if payload.winner and type(payload.names) == 'table' and payload.names[payload.winner] then
                    Client.notify(L('match_won', {
                        winner = tostring(payload.names[payload.winner]),
                        a      = sA,
                        b      = sB,
                        reason = reasonTxt,
                    }), 'success')
                elseif tostring(payload.reason) == 'no_contest' then
                    Client.notify(L('match_no_contest', { reason = reasonTxt }), 'warning')
                else
                    Client.notify(L('match_draw', { a = sA, b = sB, reason = reasonTxt }), 'inform')
                end
            end
        end,
        [P.ev.cancel] = function(payload)
            if not terminalMatchesCurrent(payload) then
                local r0 = getRenderer()
                if r0 then r0.onCancel(payload) end
                return
            end
            Client.state.match = nil
            Client.removeArenaZone()
            local r = getRenderer()
            if r then r.onCancel(payload) end
            if type(payload) == 'table' and payload.reason then
                Client.notify(L('match_cancelled', { reason = tostring(payload.reason) }), 'warning')
            end
        end,
        [P.ev.unsub] = function(payload)
            local r = getRenderer()
            local function unsub()
                if r and type(r.onUnsub) == 'function' then r.onUnsub(payload) elseif r then r.onCancel(payload) end
            end
            if not terminalMatchesCurrent(payload) then return unsub() end
            Client.state.match = nil
            Client.removeArenaZone()
            unsub()
        end,
        [P.ev.notify] = function(payload)
            Client.onNotifyEvent(payload)
        end,
        -- Arènes fixes modifiées par un administrateur : relire les stations (décor, cibles, vendeur) sans reconnexion
        [P.ev.stations or 'spin_arena:cl:stations'] = function()
            CreateThread(function() Client.fetchShop() end)
        end,
    }
end

-- ============================================================================
-- PHASE 4 : Atelier « Mes toupies » (ox_lib context + inputDialog + ox_inventory)
-- ============================================================================

local function makeBar(ratio, width)
    local w = width or 10
    local r = clamp(tonumber(ratio) or 0.0, 0.0, 1.0)
    local filled = math.floor(r * w + 0.5)
    return string.rep('█', filled) .. string.rep('░', math.max(0, w - filled))
end

local function formatModsSummary(mods)
    if type(mods) ~= 'table' or next(mods) == nil then
        return 'aucun modificateur'
    end
    local keys = {}
    for k in pairs(mods) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = tonumber(mods[k]) or 0
        local sign = v >= 0 and '+' or ''
        out[#out + 1] = ('%s %s%s'):format(k, sign, tostring(v))
    end
    return table.concat(out, ', ')
end

-- Calcule le coût total et les caractéristiques d'une toupie à partir de SpinArena.Stats / SpinArena.Parts
function Client.computeTopStatsAndCost(parts, wear)
    local partsCfg = SpinArena and SpinArena.Parts
    local statsMod = SpinArena and SpinArena.Stats
    local budget = (partsCfg and tonumber(partsCfg.budget)) or 100

    if statsMod and type(statsMod.compute) == 'function' and type(parts) == 'table' then
        local st, costOrErr = statsMod.compute(parts, tonumber(wear) or 0)
        if st then
            return st, tonumber(costOrErr) or 0, budget
        end
    end

    local cost = 0
    if partsCfg and type(partsCfg.catalog) == 'table' and type(parts) == 'table' then
        for _, slot in ipairs(partsCfg.slots or { 'core', 'ring', 'frame', 'tip' }) do
            local pDef = partsCfg.catalog[parts[slot]]
            if pDef and tonumber(pDef.cost) then
                cost = cost + tonumber(pDef.cost)
            end
        end
    end
    return nil, cost, budget
end

-- Formate les barres de caractéristiques d'une toupie :
-- atk, def, stab, endurance (inverse de tipFric), mob, plus wear et budget (cost / 100)
function Client.formatTopStats(top)
    if type(top) ~= 'table' then return nil end
    local computedStats, cost, budget = Client.computeTopStatsAndCost(top.parts, top.wear)
    local st = type(top.stats) == 'table' and top.stats or computedStats
    if type(st) ~= 'table' then return nil end
    local partsCfg = SpinArena and SpinArena.Parts
    local wearMax = (partsCfg and tonumber(partsCfg.wearMax)) or 40
    local wear = tonumber(top.wear) or 0

    local atkRatio = clamp(tonumber(st.atk) or 0.5, 0.0, 1.0)
    local defRatio = clamp(tonumber(st.def) or 0.5, 0.0, 1.0)
    local stabRatio = clamp(tonumber(st.stab) or 0.5, 0.0, 1.0)
    -- tipFric est borné dans [2.0, 7.0] : plus tipFric est faible, plus l'endurance est grande
    local tipFric = tonumber(st.tipFric) or 4.2
    local enduranceRatio = clamp((7.0 - tipFric) / (7.0 - 2.0), 0.0, 1.0)
    -- mob est borné dans [0.1, 1.8]
    local mob = tonumber(st.mob) or 0.7
    local mobRatio = clamp((mob - 0.1) / (1.8 - 0.1), 0.0, 1.0)
    local wearRatio = clamp(wear / wearMax, 0.0, 1.0)
    local budgetRatio = clamp(cost / math.max(1, budget), 0.0, 1.0)

    return {
        atk            = makeBar(atkRatio, 8),
        def            = makeBar(defRatio, 8),
        stab           = makeBar(stabRatio, 8),
        endurance      = makeBar(enduranceRatio, 8),
        mob            = makeBar(mobRatio, 8),
        wear           = ('%d/%d'):format(wear, wearMax),
        budget         = ('%d/%d'):format(cost, budget),
        cost           = cost,
        maxBudget      = budget,
        atkPct         = math.floor(atkRatio * 100 + 0.5),
        defPct         = math.floor(defRatio * 100 + 0.5),
        stabPct        = math.floor(stabRatio * 100 + 0.5),
        endurancePct   = math.floor(enduranceRatio * 100 + 0.5),
        mobPct         = math.floor(mobRatio * 100 + 0.5),
        wearPct        = math.floor(wearRatio * 100 + 0.5),
        budgetPct      = math.floor(budgetRatio * 100 + 0.5),
    }
end

function Client.buildTopMetadata(top)
    local f = Client.formatTopStats(top)
    if not f then return nil end
    return {
        { label = 'Attaque',   value = f.atk,       progress = f.atkPct },
        { label = 'Défense',   value = f.def,       progress = f.defPct },
        { label = 'Stabilité', value = f.stab,      progress = f.stabPct },
        { label = 'Endurance', value = f.endurance, progress = f.endurancePct },
        { label = 'Mobilité',  value = f.mob,       progress = f.mobPct },
        { label = 'Budget',    value = f.budget,    progress = f.budgetPct },
        { label = 'Usure',     value = f.wear,      progress = f.wearPct },
    }
end

-- Lit les pièces possédées (ox_inventory : Search('slots', 'spin_part') ; qb / qs : pont AEOM) filtrées par emplacement
function Client.getOwnedPartsBySlot(slotFilter)
    local partsCfg = SpinArena and SpinArena.Parts
    local catalog = (partsCfg and partsCfg.catalog) or {}
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then
        return {}
    end
    local okSearch, slots = pcall(function()
        if Inv.name == 'ox' then return exports.ox_inventory:Search('slots', 'spin_part') end
        local out = {}
        for _, s in ipairs(Inv.getItems()) do
            if s.name == 'spin_part' then out[#out + 1] = s end
        end
        return out
    end)
    if not okSearch or type(slots) ~= 'table' then
        return {}
    end

    local byPart = {}
    local order = {}
    for _, s in pairs(slots) do
        if type(s) == 'table' and type(s.metadata) == 'table' then
            local partId = s.metadata.part
            local count = tonumber(s.count) or 0
            local pDef = type(partId) == 'string' and catalog[partId] or nil
            if pDef and count > 0 and (not slotFilter or pDef.slot == slotFilter) then
                if not byPart[partId] then
                    byPart[partId] = {
                        part  = partId,
                        label = pDef.label or partId,
                        slot  = pDef.slot,
                        cost  = tonumber(pDef.cost) or 0,
                        mods  = pDef.mods or {},
                        count = 0,
                    }
                    order[#order + 1] = partId
                end
                byPart[partId].count = byPart[partId].count + count
            end
        end
    end

    table.sort(order)
    local result = {}
    for i = 1, #order do
        result[#result + 1] = byPart[order[i]]
    end
    return result
end

-- Action atelier : équiper une pièce ({ action = 'equip', uid = uid, part = partId })
function Client.workshopEquip(uid, partId)
    if type(uid) ~= 'string' or type(partId) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.workshop, false, {
        action = 'equip',
        uid    = uid,
        part   = partId,
    })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('workshop_equipped_ok'), 'success')
    return res
end

-- Action atelier : réparer une toupie ({ action = 'repair', uid = uid })
function Client.workshopRepair(uid)
    if type(uid) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.workshop, false, {
        action = 'repair',
        uid    = uid,
    })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('workshop_repaired_ok'), 'success')
    return res
end

-- Action atelier : renommer une toupie ({ action = 'rename', uid = uid, name = name })
function Client.workshopRename(uid, newName)
    if type(uid) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    local chosenName = newName
    if chosenName == nil and type(lib) == 'table' and type(lib.inputDialog) == 'function' then
        local ok, input = pcall(lib.inputDialog, L('workshop_rename_title'), {
            {
                type     = 'input',
                label    = L('workshop_rename_input'),
                required = true,
                min      = 1,
                max      = 24,
            },
        })
        if not ok or type(input) ~= 'table' or type(input[1]) ~= 'string' then
            return { ok = false, code = 'cancelled' }
        end
        chosenName = input[1]
    end
    if type(chosenName) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    chosenName = chosenName:gsub('^%s+', ''):gsub('%s+$', '')
    -- 24 caractères au plus (pas octets : « Élodie » compte 6) ; le serveur revalide l'UTF-8 et les caractères permis
    local chars = (utf8 and utf8.len and utf8.len(chosenName)) or #chosenName
    if not chars or chars < 1 or chars > 24 then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.workshop, false, {
        action = 'rename',
        uid    = uid,
        name   = chosenName,
    })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('workshop_renamed_ok', { name = chosenName }), 'success')
    return res
end

-- Action atelier : peindre une toupie ({ action = 'paint', uid = uid, paint = paintKey })
function Client.workshopPaint(uid, paintKey)
    if type(uid) ~= 'string' or type(paintKey) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.workshop, false, {
        action = 'paint',
        uid    = uid,
        paint  = paintKey,
    })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('workshop_painted_ok'), 'success')
    return res
end

-- Action atelier : démonter une toupie ({ action = 'disassemble', uid = uid }) ; toutes ses pièces reviennent
function Client.workshopDisassemble(uid)
    if type(uid) ~= 'string' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local res = lib.callback.await(P.cb.workshop, false, { action = 'disassemble', uid = uid })
    if type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('workshop_disassembled_ok', { count = type(res.parts) == 'table' and #res.parts or 0 }), 'success')
    return res
end

-- Sous-menu de sélection de la peinture (clés de SpinArena.Parts.paints)
function Client.openPaintMenu(top)
    if type(top) ~= 'table' then return end
    local partsCfg = SpinArena and SpinArena.Parts
    local paints = (partsCfg and partsCfg.paints) or {}
    local paintKeys = {}
    for k in pairs(paints) do paintKeys[#paintKeys + 1] = k end
    table.sort(paintKeys)

    local options = {}
    for i = 1, #paintKeys do
        local key = paintKeys[i]
        local pDef = paints[key]
        local isCurrent = (top.paint == key)
        options[#options + 1] = {
            title    = pDef.label or key,
            icon     = isCurrent and 'fa-solid fa-check' or 'fa-solid fa-palette',
            disabled = top.locked or isCurrent,
            onSelect = function()
                Client.workshopPaint(top.uid, key)
            end,
        }
    end

    local contextId = 'spin_arena:workshop_paint'
    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        lib.registerContext({
            id      = contextId,
            title   = ('%s — %s'):format(tostring(top.name or top.uid), L('workshop_paint_title')),
            options = options,
        })
        lib.showContext(contextId)
    end
    return options
end

-- « Mes toupies » retiré (décision de Money, 19/10/2026) : la gestion d'une toupie passe par les boutons de l'objet dans
-- ox_inventory (Démonter, Renommer, Peindre : Client.onDisassembleSlot / onRenameSlot / onPaintSlot plus bas),
-- l'assemblage et la réparation par glisser-déposer.

-- ============================================================================
-- STATIONS FIXES ROTORBRAWL (blips + ox_target + défi réservé exclusif, sans objet réseau)
-- ============================================================================

function Client.clearStations()
    local ids = Client.stationZoneIds or {}
    Client.stationZoneIds = {}
    if #ids > 0 and (type(exports) == 'table' or type(exports) == 'userdata') then
        for i = 1, #ids do
            local zid = ids[i]
            pcall(function()
                TargetCompat:removeZone(zid, true)
            end)
        end
    end
    local blips = Client.stationBlips or {}
    Client.stationBlips = {}
    for i = 1, #blips do
        pcall(RemoveBlip, blips[i])
    end
end

function Client.openStationChallenge(stationName, targetServerId)
    if type(stationName) ~= 'string' or stationName == '' then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if isParticipantInMatch() then
        notifyCodeError('already_in_match')
        return { ok = false, code = 'already_in_match' }
    end
    if tonumber(targetServerId) then
        local sid = math.floor(tonumber(targetServerId))
        local lastRes = nil
        selectTopAndRun('spin_arena:station_top_menu', 'attack', function(chosenTop)
            lastRes = Client.challenge(sid, chosenTop, stationName)
        end)
        return lastRes or { ok = true, code = 'selecting_top', station = stationName }
    end

    local state = Client.fetchState()
    if type(state) ~= 'table' or not state.ok then
        notifyCodeError(type(state) == 'table' and state.code or 'error')
        return state or { ok = false, code = 'error' }
    end

    local stations = type(Client.state.stations) == 'table' and Client.state.stations or {}
    for i = 1, #stations do
        local st = stations[i]
        if type(st) == 'table' and st.name == stationName and st.busy then
            notifyCodeError('no_arena')
            return { ok = false, code = 'no_arena' }
        end
    end

    local opponents = type(Client.state.opponents) == 'table' and Client.state.opponents or {}
    local options = {}
    if #opponents == 0 then
        options[#options + 1] = {
            title    = L('station_no_opponents'),
            icon     = 'fa-solid fa-user-slash',
            disabled = true,
        }
    else
        for i = 1, #opponents do
            local opp = opponents[i]
            local sid = tonumber(opp and opp.id)
            if sid then
                local distStr = string.format('%.1f', tonumber(opp.distance) or 0.0)
                options[#options + 1] = {
                    title       = tostring(opp.name or ('#' .. tostring(sid))),
                    description = L('station_opponent_desc', { id = sid, distance = distStr }),
                    icon        = 'fa-solid fa-burst',
                    onSelect    = function()
                        selectTopAndRun('spin_arena:station_top_menu', 'attack', function(chosenTop)
                            Client.challenge(sid, chosenTop, stationName)
                        end)
                    end,
                }
            end
        end
    end

    local contextId = 'spin_arena:station_opponents'
    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        lib.registerContext({
            id      = contextId,
            title   = L('station_title', { station = stationName }),
            options = options,
        })
        lib.showContext(contextId)
        return { ok = true, code = 'ok', station = stationName, opponents = opponents }
    end

    if #opponents > 0 and tonumber(opponents[1].id) then
        return Client.openStationChallenge(stationName, tonumber(opponents[1].id))
    end
    notifyCodeError('not_found')
    return { ok = false, code = 'not_found' }
end

-- Décor permanent des stations (cuvette locale) : synchronisé avec la liste reçue du serveur
local function syncStationProps(stations)
    local R = SpinArena and SpinArena.Renderer
    if R and type(R.syncStationProps) == 'function' then
        local model = SpinArena.Config and SpinArena.Config.testArena and SpinArena.Config.testArena.model
        pcall(R.syncStationProps, stations, model)
    end
end

function Client.syncStationTargets(stations)
    syncStationProps(stations)
    Client.clearStations()
    if type(stations) ~= 'table' or #stations == 0 then
        Client.state.stations = {}
        return 0
    end
    Client.state.stations = stations

    local targetExport = nil
    if type(exports) == 'table' or type(exports) == 'userdata' then
        local ok, oxTarget = pcall(function() return TargetCompat end)
        if ok and oxTarget then
            targetExport = oxTarget
        end
    end

    for i = 1, #stations do
        local st = stations[i]
        if type(st) == 'table' and type(st.name) == 'string'
            and tonumber(st.x) and tonumber(st.y) and tonumber(st.z) then
            local stationName = st.name
            local stationLabel = tostring(st.label or st.name)
            local sx, sy, sz = tonumber(st.x), tonumber(st.y), tonumber(st.z)

            -- Un seul blip par groupe de tables (moins de 15 m) : pas de bruit sur la carte
            local grouped = false
            for j = 1, i - 1 do
                local o = stations[j]
                if type(o) == 'table' and tonumber(o.x) and tonumber(o.y)
                    and (tonumber(o.x) - sx) ^ 2 + (tonumber(o.y) - sy) ^ 2 < 15.0 * 15.0 then grouped = true break end
            end
            -- Arène d'extension sans blip (ex. tables du Dôme, loin de la carte : le blip de sa porte suffit)
            if not grouped and not st.noBlip and type(AddBlipForCoord) == 'function' then
                local blip = AddBlipForCoord(sx, sy, sz + 0.5)
                if blip and blip ~= 0 then
                    Client.stationBlips[#Client.stationBlips + 1] = blip
                    -- Variante à blip propre (Colisée : config arenaVariants.<v>.blip) ; sinon blip de station
                    local variants = SpinArena.Config and SpinArena.Config.arenaVariants or {}
                    local own = variants[st.variant or 'standard'] and variants[st.variant or 'standard'].blip or {}
                    if type(SetBlipSprite) == 'function' then SetBlipSprite(blip, own.sprite or 310) end
                    if type(SetBlipDisplay) == 'function' then SetBlipDisplay(blip, 4) end
                    if type(SetBlipScale) == 'function' then SetBlipScale(blip, own.scale or 0.75) end
                    if type(SetBlipColour) == 'function' then SetBlipColour(blip, st.busy and 1 or (own.colour or 47)) end
                    if type(SetBlipAsShortRange) == 'function' then SetBlipAsShortRange(blip, own.shortRange ~= false) end
                    local blipText = own.label and 'SPIN_ARENA_STATION_' .. tostring(st.variant) or 'SPIN_ARENA_STATION'
                    if type(AddTextEntry) == 'function' then AddTextEntry(blipText, own.label or 'Station ROTORBRAWL') end
                    if type(BeginTextCommandSetBlipName) == 'function' then BeginTextCommandSetBlipName(blipText) end
                    if type(EndTextCommandSetBlipName) == 'function' then EndTextCommandSetBlipName(blip) end
                end
            end

            if targetExport then
                local coords = makeVec3(sx, sy, sz + 0.5)
                local addedOk, zoneId = pcall(function()
                    return targetExport:addSphereZone({
                        name    = ('spin_arena:station_%s'):format(stationName),
                        coords  = coords,
                        radius  = 1.6,
                        options = {
                            {
                                -- File d'attente : le match démarre dès qu'un 2e joueur rejoint (préparation, lancer manuel)
                                name        = 'spin_arena:station_queue_join',
                                icon        = 'fa-solid fa-user-plus',
                                label       = ('%s — %s'):format(L('target_queue_join'), stationLabel),
                                distance    = 3.5,
                                canInteract = function()
                                    if isParticipantInMatch() then return false end
                                    if Client.state.queued ~= nil then return false end
                                    return not st.busy
                                end,
                                onSelect    = function()
                                    selectTopAndRun('spin_arena:queue_top_menu', 'attack', function(chosenTop)
                                        Client.queueJoin(stationName, chosenTop)
                                    end)
                                end,
                            },
                            {
                                name        = 'spin_arena:station_queue_leave',
                                icon        = 'fa-solid fa-user-minus',
                                label       = L('target_queue_leave'),
                                distance    = 3.5,
                                canInteract = function() return Client.state.queued == stationName end,
                                onSelect    = function() Client.queueLeave() end,
                            },
                            {
                                name        = 'spin_arena:station_challenge',
                                icon        = 'fa-solid fa-burst',
                                label       = ('%s — %s'):format(L('target_station_challenge'), stationLabel),
                                distance    = 3.5,
                                canInteract = function()
                                    if isParticipantInMatch() then return false end
                                    if Client.state.outgoing ~= nil then return false end
                                    return not st.busy
                                end,
                                onSelect    = function()
                                    Client.openStationChallenge(stationName)
                                end,
                            },
                            {
                                name        = 'spin_arena:station_accept',
                                icon        = 'fa-solid fa-check',
                                label       = ('%s — %s'):format(L('target_accept'), stationLabel),
                                distance    = 3.5,
                                canInteract = function()
                                    if isParticipantInMatch() then return false end
                                    if st.busy then return false end
                                    return #Client.state.incoming > 0
                                end,
                                onSelect    = function()
                                    local latest = Client.state.incoming[#Client.state.incoming]
                                    if not latest then return end
                                    selectTopAndRun('spin_arena:station_accept_menu', 'attack', function(chosenTop)
                                        Client.respond(latest.id, true, chosenTop)
                                    end)
                                end,
                            },
                        },
                    })
                end)
                if addedOk and zoneId then
                    Client.stationZoneIds[#Client.stationZoneIds + 1] = zoneId
                end
            end
        end
    end
    return #Client.stationZoneIds
end

-- ============================================================================
-- BOUTIQUE ROTORBRAWL (spin_arena:shop + ox_target + ox_inventory:openInventory)
-- ============================================================================

function Client.removeShopZones()
    local ids = Client.shopZoneIds or {}
    Client.shopZoneIds = {}
    if #ids == 0 then return end
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then return end
    for i = 1, #ids do
        local zid = ids[i]
        pcall(function()
            TargetCompat:removeZone(zid, true)
        end)
    end
end

function Client.syncShopTargets(info)
    Client.removeShopZones()
    if type(info) == 'table' and info.enabled and type(info.stations) == 'table' then
        Client.syncStationTargets(info.stations)
    elseif type(info) ~= 'table' or not info.enabled then
        Client.clearStations()
        syncStationProps({})
    end
    if type(info) ~= 'table' or not info.enabled or type(info.points) ~= 'table' or #info.points == 0 then
        return 0
    end
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then
        return 0
    end
    local ok, targetExport = pcall(function() return TargetCompat end)
    if not ok or not targetExport then
        return 0
    end

    for i = 1, #info.points do
        local pt = info.points[i]
        -- Un point avec vendeur (ped) a déjà son interaction sur le PNJ (client/shop_vendor.lua) : pas de zone en double
        if type(pt) == 'table' and type(pt.ped) ~= 'string' and tonumber(pt.x) and tonumber(pt.y) and tonumber(pt.z) then
            local shopIdx = i
            local coords = makeVec3(tonumber(pt.x), tonumber(pt.y), tonumber(pt.z))
            local label = L('target_shop')
            if type(pt.label) == 'string' and pt.label ~= '' then
                label = ('%s — %s'):format(label, pt.label)
            end
            local addedOk, zoneId = pcall(function()
                return targetExport:addSphereZone({
                    name    = ('spin_arena:shop_%d'):format(shopIdx),
                    coords  = coords,
                    radius  = 1.5,
                    options = {
                        {
                            name        = 'spin_arena:shop',
                            icon        = 'fa-solid fa-cart-shopping',
                            label       = label,
                            distance    = 3.0,
                            canInteract = function()
                                return not isParticipantInMatch()
                            end,
                            onSelect    = function()
                                Client.openShop(shopIdx)
                            end,
                        },
                    },
                })
            end)
            if addedOk and zoneId then
                Client.shopZoneIds[#Client.shopZoneIds + 1] = zoneId
            end
        end
    end
    return #Client.shopZoneIds
end

function Client.fetchShop()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error', enabled = false }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.shop, false, {})
    if not ok or type(res) ~= 'table' then
        return { ok = false, code = 'error', enabled = false }
    end
    if res.ok then
        Client.state.shop = res
        Client.syncShopTargets(res)
    end
    return res
end

local DEFAULT_SHOP_CATEGORIES = {
    tops      = 'spinarena_tops',
    launchers = 'spinarena_launchers',
    parts     = 'spinarena_parts',
    repair    = 'spinarena_repair',
}

-- Achat dans la boutique unique : seuls l'identifiant d'article et la quantité partent ; le serveur fait le reste
function Client.buyShop(shopId, itemId, count)
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.shopBuy, false,
        { shopId = math.floor(tonumber(shopId) or 0), item = tostring(itemId or ''), count = math.floor(tonumber(count) or 1) })
    if not ok or type(res) ~= 'table' then return { ok = false, code = 'error' } end
    return res
end

function Client.openShop(shopId, categoryKey)
    local info = Client.fetchShop()
    if type(info) ~= 'table' or not info.ok or not info.enabled then
        Client.notify(L('shop_unavailable'), 'error')
        return { ok = false, code = 'shop_unavailable' }
    end

    local points = type(info.points) == 'table' and info.points or {}
    local resolvedId = tonumber(shopId)
    if resolvedId then
        resolvedId = math.floor(resolvedId)
        if resolvedId < 1 or resolvedId > #points then
            Client.notify(L('shop_unavailable'), 'error')
            return { ok = false, code = 'shop_unavailable' }
        end
    elseif #points > 0 then
        resolvedId = 1
        if type(PlayerPedId) == 'function' and type(GetEntityCoords) == 'function' then
            local okPed, ped = pcall(PlayerPedId)
            local okPos, pos = okPed and ped and pcall(GetEntityCoords, ped)
            if okPos and pos and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
                local bestDist2 = math.huge
                for i = 1, #points do
                    local pt = points[i]
                    local dx = (tonumber(pt.x) or 0) - pos.x
                    local dy = (tonumber(pt.y) or 0) - pos.y
                    local dz = (tonumber(pt.z) or 0) - pos.z
                    local d2 = dx * dx + dy * dy + dz * dz
                    if d2 < bestDist2 then
                        bestDist2 = d2
                        resolvedId = i
                    end
                end
            end
        end
    elseif not info.anywhere then
        Client.notify(L('shop_unavailable'), 'error')
        return { ok = false, code = 'shop_unavailable' }
    end

    local shopType = tostring(info.type or 'spinarena')
    if categoryKey ~= nil then
        local cats = (type(info.categories) == 'table') and info.categories or DEFAULT_SHOP_CATEGORIES
        local resolvedCatType = (type(categoryKey) == 'string') and cats[categoryKey] or nil
        if not resolvedCatType then
            Client.notify(L('shop_unavailable'), 'error')
            return { ok = false, code = 'shop_unavailable' }
        end
        shopType = tostring(resolvedCatType)
    end

    local shopPayload = { type = shopType, id = resolvedId }
    Client.lastOpenedShop = shopPayload
    -- L'affichage (onglet Boutique de l'interface Arena) est fait par client/nui.lua à partir de ce résultat

    return {
        ok       = true,
        code     = 'ok',
        type     = shopType,
        category = categoryKey,
        id       = resolvedId,
        point    = resolvedId and points[resolvedId] or nil,
        info     = info,
    }
end

-- ============================================================================
-- CLASSEMENT ELO (spin_arena:leaderboard) & TOURNOIS (spin_arena:tournament_*)
-- ============================================================================

function Client.fetchLeaderboard()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error', season = 1, top = {} }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.leaderboard, false, {})
    if not ok or type(res) ~= 'table' then
        return { ok = false, code = 'error', season = 1, top = {} }
    end
    if res.ok then
        Client.state.leaderboard = res
    end
    return res
end

function Client.openLeaderboard()
    local res = Client.fetchLeaderboard()
    if type(res) ~= 'table' or not res.ok then
        notifyCodeError(type(res) == 'table' and res.code or 'error')
        return res or { ok = false, code = 'error' }
    end

    local options = {}
    if type(res.me) == 'table' then
        local me = res.me
        local rank = tonumber(me.rank)
        local rating = math.floor((tonumber(me.rating) or 1000) + 0.5)
        local meTitle = rank
            and L('leaderboard_me_title', { rank = rank, rating = rating })
            or L('leaderboard_me_unranked', { rating = rating })
        options[#options + 1] = {
            title       = meTitle,
            description = L('leaderboard_me_desc', {
                name = tostring(me.name or '?'),
                w    = tonumber(me.wins) or 0,
                l    = tonumber(me.losses) or 0,
                d    = tonumber(me.draws) or 0,
            }),
            icon        = 'fa-solid fa-user-shield',
            readOnly    = true,
        }
    end

    local top = type(res.top) == 'table' and res.top or {}
    if #top == 0 then
        options[#options + 1] = {
            title    = L('leaderboard_empty'),
            icon     = 'fa-solid fa-circle-info',
            disabled = true,
        }
    else
        for i = 1, #top do
            local entry = top[i]
            if type(entry) == 'table' then
                local rk = tonumber(entry.rank) or i
                local rt = math.floor((tonumber(entry.rating) or 1000) + 0.5)
                local icon = (rk == 1 and 'fa-solid fa-crown')
                    or (rk <= 3 and 'fa-solid fa-medal')
                    or 'fa-solid fa-ranking-star'
                options[#options + 1] = {
                    title       = L('leaderboard_row_title', {
                        rank   = rk,
                        name   = tostring(entry.name or '?'),
                        rating = rt,
                    }),
                    description = L('leaderboard_row_desc', {
                        w = tonumber(entry.wins) or 0,
                        l = tonumber(entry.losses) or 0,
                        d = tonumber(entry.draws) or 0,
                    }),
                    icon        = icon,
                    readOnly    = true,
                }
            end
        end
    end

    local contextId = 'spin_arena:leaderboard_menu'
    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        lib.registerContext({
            id      = contextId,
            title   = L('leaderboard_title', { season = tonumber(res.season) or 1 }),
            options = options,
        })
        lib.showContext(contextId)
    end
    return res
end

local function formatTournamentStateLabel(st)
    local key = 'tournament_state_' .. tostring(st or 'signup')
    return L(key)
end

function Client.fetchTournaments()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error', tournaments = {} }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.tournamentStatus, false, {})
    if not ok or type(res) ~= 'table' then
        return { ok = false, code = 'error', tournaments = {} }
    end
    if res.ok then
        Client.state.tournaments = res
    end
    return res
end

function Client.createTournament(name, size, minutes)
    if name == nil and type(lib) == 'table' and type(lib.inputDialog) == 'function' then
        local ok, ans = pcall(lib.inputDialog, L('tournament_create_title'), {
            {
                type     = 'input',
                label    = L('tournament_input_name'),
                required = true,
                min      = 3,
                max      = 32,
            },
            {
                type     = 'select',
                label    = L('tournament_input_size'),
                required = true,
                default  = '4',
                options  = {
                    { value = '4', label = '4' },
                    { value = '8', label = '8' },
                    { value = '16', label = '16' },
                },
            },
            {
                type     = 'number',
                label    = L('tournament_input_minutes'),
                required = true,
                default  = 2,
                min      = 1,
                max      = 60,
            },
        })
        if not ok or type(ans) ~= 'table' then
            return { ok = false, code = 'cancelled' }
        end
        name = ans[1]
        size = tonumber(ans[2])
        minutes = tonumber(ans[3])
    end

    if type(name) ~= 'string' or not tonumber(size) or not tonumber(minutes) then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.tournamentCreate, false, {
        name    = name,
        size    = math.floor(tonumber(size)),
        minutes = math.floor(tonumber(minutes)),
    })
    if not ok or type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end

    Client.notify(L('tournament_created_ok', {
        name = name,
        id   = tostring(res.id or '?'),
    }), 'success')
    return res
end

function Client.joinTournament(id, topKey)
    local tid = tonumber(id)
    if not tid or tid < 1 then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end

    if topKey == nil then
        local lastRes = nil
        selectTopAndRun('spin_arena:tournament_top_menu', 'attack', function(chosenTop)
            lastRes = Client.joinTournament(tid, chosenTop)
        end)
        return lastRes or { ok = true, code = 'selecting_top' }
    end

    local chosenTop = normalizeTopChoice(topKey)
    if not chosenTop then
        notifyCodeError('invalid')
        return { ok = false, code = 'invalid' }
    end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end

    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.tournamentJoin, false, {
        id  = math.floor(tid),
        top = chosenTop,
    })
    if not ok or type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end

    Client.notify(L('tournament_joined_ok', {
        id      = tostring(res.id or math.floor(tid)),
        players = tostring(res.players or '?'),
        size    = tostring(res.size or '?'),
    }), 'success')
    return res
end

function Client.leaveTournament()
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return { ok = false, code = 'error' }
    end
    local P = getProtocol()
    local ok, res = pcall(lib.callback.await, P.cb.tournamentLeave, false, {})
    if not ok or type(res) ~= 'table' then
        notifyCodeError('error')
        return { ok = false, code = 'error' }
    end
    if not res.ok then
        notifyCodeError(res.code)
        return res
    end
    Client.notify(L('tournament_left_ok'), 'inform')
    return res
end

function Client.openTournamentDetail(t, mineId)
    if type(t) ~= 'table' then return nil end
    local tid = tonumber(t.id)
    local playersList = type(t.players) == 'table' and t.players or {}
    local size = tonumber(t.size) or 4
    local options = {}

    if t.state == 'signup' then
        if mineId ~= nil and tonumber(mineId) == tid then
            options[#options + 1] = {
                title       = L('tournament_leave_title'),
                description = L('tournament_leave_desc'),
                icon        = 'fa-solid fa-right-from-bracket',
                onSelect    = function()
                    local r = Client.leaveTournament()
                    if r and r.ok then
                        Client.openTournaments()
                    end
                end,
            }
        elseif mineId == nil then
            options[#options + 1] = {
                title       = L('tournament_join_title'),
                description = L('tournament_join_desc', {
                    players = #playersList,
                    size    = size,
                }),
                icon        = 'fa-solid fa-right-to-bracket',
                onSelect    = function()
                    selectTopAndRun('spin_arena:tournament_top_menu', 'attack', function(chosenTop)
                        local r = Client.joinTournament(tid, chosenTop)
                        if r and r.ok then
                            Client.openTournaments(tid)
                        end
                    end)
                end,
            }
        end
    end

    if type(t.myMatch) == 'table' then
        local mm = t.myMatch
        local secs = math.max(0, math.ceil((tonumber(mm.deadlineInMs) or 0) / 1000))
        options[#options + 1] = {
            title       = L('tournament_mymatch_title', {
                round    = tonumber(mm.round) or 1,
                opponent = tostring(mm.opponent or '?'),
            }),
            description = L('tournament_mymatch_desc', {
                state   = tostring(mm.state or 'pending'),
                seconds = secs,
            }),
            icon        = 'fa-solid fa-bolt',
            readOnly    = true,
        }
    end

    options[#options + 1] = {
        title       = L('tournament_players_title', {
            count = #playersList,
            size  = size,
        }),
        description = (#playersList > 0 and table.concat(playersList, ', ') or L('tournaments_empty')),
        icon        = 'fa-solid fa-users',
        readOnly    = true,
    }

    if type(t.rounds) == 'table' then
        for r = 1, #t.rounds do
            local rnd = t.rounds[r]
            if type(rnd) == 'table' then
                for m = 1, #rnd do
                    local enc = rnd[m]
                    if type(enc) == 'table' then
                        local nameA = (type(enc.a) == 'table' and enc.a.name) or '?'
                        local nameB = (type(enc.b) == 'table' and enc.b.name) or 'BYE'
                        local stLabel = tostring(enc.state or 'pending')
                        local desc = enc.winner and L('tournament_round_winner', { winner = tostring(enc.winner) }) or ''
                        options[#options + 1] = {
                            title       = L('tournament_round_header', {
                                round = r,
                                a     = tostring(nameA),
                                b     = tostring(nameB),
                                state = stLabel,
                            }),
                            description = desc,
                            icon        = 'fa-solid fa-trophy',
                            readOnly    = true,
                        }
                    end
                end
            end
        end
    end

    local contextId = 'spin_arena:tournament_detail'
    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        lib.registerContext({
            id      = contextId,
            title   = L('tournament_row_title', {
                id      = tid or '?',
                name    = tostring(t.name or '?'),
                state   = formatTournamentStateLabel(t.state),
                players = #playersList,
                size    = size,
            }),
            menu    = 'spin_arena:tournaments_menu',
            options = options,
        })
        lib.showContext(contextId)
    end
    return t
end

function Client.openTournaments(focusId)
    local res = Client.fetchTournaments()
    if type(res) ~= 'table' or not res.ok then
        notifyCodeError(type(res) == 'table' and res.code or 'error')
        return res or { ok = false, code = 'error' }
    end

    local options = {
        {
            title       = L('tournament_create_title'),
            description = L('tournament_create_desc'),
            icon        = 'fa-solid fa-plus',
            onSelect    = function()
                local r = Client.createTournament()
                if r and r.ok then
                    Client.openTournaments(r.id)
                end
            end,
        },
    }

    if res.mine ~= nil then
        options[#options + 1] = {
            title       = L('tournament_leave_title'),
            description = L('tournament_leave_desc'),
            icon        = 'fa-solid fa-right-from-bracket',
            onSelect    = function()
                local r = Client.leaveTournament()
                if r and r.ok then
                    Client.openTournaments()
                end
            end,
        }
    end

    local list = type(res.tournaments) == 'table' and res.tournaments or {}
    if #list == 0 then
        options[#options + 1] = {
            title    = L('tournaments_empty'),
            icon     = 'fa-solid fa-circle-info',
            disabled = true,
        }
    else
        for i = 1, #list do
            local t = list[i]
            if type(t) == 'table' then
                local pCount = type(t.players) == 'table' and #t.players or 0
                local extra = ''
                if t.winner then
                    extra = ' | ' .. L('tournament_round_winner', { winner = tostring(t.winner) })
                elseif tonumber(t.signupEndsInMs) and t.state == 'signup' then
                    local remS = math.max(0, math.ceil(tonumber(t.signupEndsInMs) / 1000))
                    extra = (' | %d s'):format(remS)
                end
                options[#options + 1] = {
                    title       = L('tournament_row_title', {
                        id      = tostring(t.id or '?'),
                        name    = tostring(t.name or '?'),
                        state   = formatTournamentStateLabel(t.state),
                        players = pCount,
                        size    = tonumber(t.size) or 4,
                    }),
                    description = L('tournament_row_desc', {
                        organizer = tostring(t.organizer or '?'),
                        extra     = extra,
                    }),
                    icon        = 'fa-solid fa-trophy',
                    onSelect    = function()
                        Client.openTournamentDetail(t, res.mine)
                    end,
                }
            end
        end
    end

    local contextId = 'spin_arena:tournaments_menu'
    if type(lib) == 'table' and type(lib.registerContext) == 'function' and type(lib.showContext) == 'function' then
        lib.registerContext({
            id      = contextId,
            title   = L('tournaments_title'),
            options = options,
        })
        if tonumber(focusId) then
            local fid = tonumber(focusId)
            for i = 1, #list do
                if tonumber(list[i].id) == fid then
                    Client.openTournamentDetail(list[i], res.mine)
                    return res
                end
            end
        end
        lib.showContext(contextId)
    end
    return res
end

function Client.openChallenges()
    local state = Client.fetchState()
    if type(state) ~= 'table' or not state.ok then
        notifyCodeError(type(state) == 'table' and state.code or 'error')
        return state
    end
    local options = {}
    for _, incoming in ipairs(Client.state.incoming) do
        local id, name = incoming.id, incoming.fromName
        options[#options + 1] = {
            title = L('target_accept') .. ' — ' .. tostring(name), icon = 'fa-solid fa-check',
            onSelect = function()
                selectTopAndRun('spin_arena:accept_menu', nil, function(uid) Client.respond(id, true, uid) end)
            end,
        }
        options[#options + 1] = {
            title = L('target_decline') .. ' — ' .. tostring(name), icon = 'fa-solid fa-xmark',
            onSelect = function() Client.respond(id, false) end,
        }
    end
    local outgoing = Client.state.outgoing
    if outgoing then
        local id = outgoing.id
        options[#options + 1] = {
            title = L('target_cancel') .. ' — ' .. tostring(outgoing.toName or outgoing.to), icon = 'fa-solid fa-ban',
            onSelect = function() Client.cancelChallenge(id) end,
        }
    end
    if #options == 0 then options[1] = { title = L('cmd_no_incoming'), disabled = true } end
    lib.registerContext({ id = 'spin_arena:challenges_menu', title = L('home_challenges'), menu = 'spin_arena:home', options = options })
    lib.showContext('spin_arena:challenges_menu')
    return state
end

function Client.openHome()
    if isParticipantInMatch() then return false end
    if type(lib) ~= 'table' or type(lib.registerContext) ~= 'function' or type(lib.showContext) ~= 'function' then return false end
    lib.registerContext({ id = 'spin_arena:home', title = L('home_title'), options = {
        { title = L('home_challenges'), icon = 'fa-solid fa-people-arrows', onSelect = function() Client.openChallenges() end },
        { title = L('target_shop'), icon = 'fa-solid fa-cart-shopping', onSelect = function() Client.openShop() end },
        { title = L('target_leaderboard'), icon = 'fa-solid fa-ranking-star', onSelect = function() Client.openLeaderboard() end },
        { title = L('target_tournaments'), icon = 'fa-solid fa-trophy', onSelect = function() Client.openTournaments() end },
    } })
    lib.showContext('spin_arena:home')
    return true
end

-- Interface principale ox_target sur les joueurs et menu d'accueil accessible sans viser une entité.
function Client.registerTarget()
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then
        return false
    end
    local ok, targetExport = pcall(function() return TargetCompat end)
    if not ok or not targetExport then
        return false
    end

    local added = pcall(function()
        targetExport:addGlobalPlayer({
            {
                name        = 'spin_arena:challenge',
                icon        = 'fa-solid fa-burst',
                label       = L('target_challenge'),
                distance    = 4.0,
                canInteract = function(entity)
                    if isParticipantInMatch() then return false end
                    if Client.state.outgoing ~= nil then return false end
                    local sid = resolveTargetServerId(entity)
                    if not sid then return false end
                    local mySid = getLocalServerId()
                    if mySid and sid == mySid then return false end
                    if findIncomingFrom(sid) ~= nil then return false end
                    return true
                end,
                onSelect    = function(data)
                    local sid = resolveTargetServerId(data)
                    if not sid then return end
                    selectTopAndRun('spin_arena:challenge_menu', 'attack', function(chosenTop)
                        Client.challenge(sid, chosenTop)
                    end)
                end,
            },
            {
                name        = 'spin_arena:accept',
                icon        = 'fa-solid fa-check',
                label       = L('target_accept'),
                distance    = 4.0,
                canInteract = function(entity)
                    if isParticipantInMatch() then return false end
                    local sid = resolveTargetServerId(entity)
                    if not sid then return false end
                    return findIncomingFrom(sid) ~= nil
                end,
                onSelect    = function(data)
                    local sid = resolveTargetServerId(data)
                    local inc = sid and findIncomingFrom(sid) or nil
                    if not inc then return end
                    selectTopAndRun('spin_arena:accept_menu', 'attack', function(chosenTop)
                        Client.respond(inc.id, true, chosenTop)
                    end)
                end,
            },
            {
                name        = 'spin_arena:decline',
                icon        = 'fa-solid fa-xmark',
                label       = L('target_decline'),
                distance    = 4.0,
                canInteract = function(entity)
                    if isParticipantInMatch() then return false end
                    local sid = resolveTargetServerId(entity)
                    if not sid then return false end
                    return findIncomingFrom(sid) ~= nil
                end,
                onSelect    = function(data)
                    local sid = resolveTargetServerId(data)
                    local inc = sid and findIncomingFrom(sid) or nil
                    if not inc then return end
                    Client.respond(inc.id, false)
                end,
            },
            {
                name        = 'spin_arena:cancel',
                icon        = 'fa-solid fa-ban',
                label       = L('target_cancel'),
                distance    = 4.0,
                canInteract = function(entity)
                    if isParticipantInMatch() then return false end
                    local sid = resolveTargetServerId(entity)
                    if not sid then return false end
                    return hasOutgoingTo(sid)
                end,
                onSelect    = function(data)
                    local sid = resolveTargetServerId(data)
                    if not sid or not hasOutgoingTo(sid) then return end
                    Client.cancelChallenge(Client.state.outgoing and Client.state.outgoing.id)
                end,
            },
        })
    end)

    -- Les menus sont accessibles uniquement auprès du PNJ Arena, sans raccourci F7.

    return added
end

function Client.removeTarget()
    Client.removeArenaZone()
    Client.removeShopZones()
    Client.clearStations()
    if type(exports) ~= 'table' and type(exports) ~= 'userdata' then
        return
    end
    pcall(function()
        TargetCompat:removeGlobalPlayer({
            'spin_arena:challenge',
            'spin_arena:accept',
            'spin_arena:decline',
            'spin_arena:cancel',
        })
    end)
    pcall(function()
        TargetCompat:removeGlobalOption({
            'spin_arena:menu',
            'spin_arena:workshop',
            'spin_arena:shop',
            'spin_arena:leaderboard',
            'spin_arena:tournaments',
        })
    end)
end

function Client.registerEvents()
    if type(RegisterNetEvent) ~= 'function' or type(AddEventHandler) ~= 'function' then
        return false
    end

    local events = buildNetEvents()
    for eventName, handler in pairs(events) do
        RegisterNetEvent(eventName)
        AddEventHandler(eventName, handler)
    end

    AddEventHandler('onResourceStop', function(resourceName)
        local current = (type(GetCurrentResourceName) == 'function') and GetCurrentResourceName() or nil
        if not current or resourceName == current then
            Client.removeTarget()
            local r = getRenderer()
            if r then
                r.cleanup('resource_stop')
            end
        end
    end)

    return true
end

-- Bouton « Démonter » d'ox_inventory sur spin_top (install/ox_inventory_items.lua, client.buttons) : événement LOCAL,
-- jamais RegisterNetEvent, donc impossible à déclencher depuis le réseau. Le serveur revalide tout (propriétaire,
-- verrou, match en cours). Confirmation obligatoire ; sans boîte ox_lib, deux appuis dans les 5 s.
-- Toupie posée dans un emplacement de l'inventaire du joueur (bouton d'objet ox_inventory) : uid ou nil
local function topUidInSlot(slot)
    slot = tonumber(slot)
    if not slot then return nil end
    local ok, items = pcall(function() return exports.ox_inventory:GetPlayerItems() end)
    local item = ok and type(items) == 'table' and items[slot] or nil
    local uid = item and item.name == 'spin_top' and type(item.metadata) == 'table' and item.metadata.uid or nil
    return type(uid) == 'string' and uid or nil, item
end

local DISASSEMBLE_CONFIRM_MS = 5000
local pendingDisassemble = nil
function Client.onDisassembleSlot(slot)
    slot = tonumber(slot)
    if not slot then return false end
    local inv = exports.ox_inventory
    local ok, items = pcall(function() return inv:GetPlayerItems() end)
    local item = ok and type(items) == 'table' and items[slot] or nil
    local uid = item and item.name == 'spin_top' and type(item.metadata) == 'table' and item.metadata.uid or nil
    if type(uid) ~= 'string' then notifyCodeError('no_top') return false end
    pcall(function() inv:closeInventory() end)
    if type(lib) == 'table' and type(lib.alertDialog) == 'function' then
        local answer = lib.alertDialog({ header = L('workshop_disassemble_title'), content = L('workshop_disassemble_confirm'),
            centered = true, cancel = true })
        if answer ~= 'confirm' then return false end
    else
        local now = GetGameTimer()
        if not (pendingDisassemble and pendingDisassemble.uid == uid and now - pendingDisassemble.at <= DISASSEMBLE_CONFIRM_MS) then
            pendingDisassemble = { uid = uid, at = now }
            Client.notify(L('workshop_disassemble_again'), 'inform')
            return false
        end
    end
    pendingDisassemble = nil
    local res = Client.workshopDisassemble(uid)
    return type(res) == 'table' and res.ok == true
end
-- Bouton « Renommer » : saisie du nom (ox_lib), le serveur revalide (UTF-8, 24 caractères, propriétaire, verrou)
function Client.onRenameSlot(slot)
    local uid = topUidInSlot(slot)
    if not uid then notifyCodeError('no_top') return false end
    pcall(function() exports.ox_inventory:closeInventory() end)
    local res = Client.workshopRename(uid)          -- sans nom : ouvre la saisie ox_lib
    return type(res) == 'table' and res.ok == true
end

-- Bouton « Peindre » : choix de la peinture dans une saisie ox_lib (liste), le serveur revalide
function Client.onPaintSlot(slot)
    local uid = topUidInSlot(slot)
    if not uid then notifyCodeError('no_top') return false end
    pcall(function() exports.ox_inventory:closeInventory() end)
    if type(lib) ~= 'table' or type(lib.inputDialog) ~= 'function' then return false end
    local paints = (SpinArena.Parts and SpinArena.Parts.paints) or {}
    local keys, options = {}, {}
    for k in pairs(paints) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do options[#options + 1] = { value = k, label = paints[k].label or k } end
    local ok, input = pcall(lib.inputDialog, L('workshop_paint_title'), {
        { type = 'select', label = L('workshop_paint_title'), options = options, required = true },
    })
    if not ok or type(input) ~= 'table' or type(input[1]) ~= 'string' then return false end   -- annulé
    local res = Client.workshopPaint(uid, input[1])
    return type(res) == 'table' and res.ok == true
end

if type(AddEventHandler) == 'function' then
    AddEventHandler('spin_arena:cl:disassembleSlot', function(slot)
        CreateThread(function() Client.onDisassembleSlot(slot) end)
    end)
    -- Événements LOCAUX (aucun RegisterNetEvent) : déclenchés seulement par les boutons de l'objet dans ox_inventory
    AddEventHandler('spin_arena:cl:renameSlot', function(slot)
        CreateThread(function() Client.onRenameSlot(slot) end)
    end)
    AddEventHandler('spin_arena:cl:paintSlot', function(slot)
        CreateThread(function() Client.onPaintSlot(slot) end)
    end)
end

Client.registerEvents()
Client.registerTarget()

return Client
