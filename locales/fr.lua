-- SPIN ARENA — Traductions françaises (Phase 2 : duel multijoueur)
-- Fichier : locales/fr.lua

SpinArena = SpinArena or {}
SpinArena.Locales = SpinArena.Locales or {}

local FR = {
    home_title           = 'SPIN ARENA',
    home_challenges      = 'Défis en cours',
    -- Codes de retour serveur (SpinArena.Protocol.codes)
    ok                   = 'Opération effectuée.',
    rate_limited         = 'Action trop rapide. Veuillez patienter un instant.',
    invalid              = 'Requête ou paramètres invalides.',
    busy                 = 'Une opération est déjà en cours.',
    not_found            = 'Défi ou match introuvable.',
    too_far              = 'Le joueur ciblé est trop éloigné.',
    in_vehicle           = 'Impossible de combattre depuis un véhicule.',
    dead                 = 'Impossible de combattre dans cet état.',
    same_player          = 'Vous ne pouvez pas vous défier vous-même.',
    already_in_match     = 'Vous participez déjà à un match.',
    target_busy          = 'Ce joueur a déjà un défi en attente ou un match en cours.',
    no_arena             = 'Aucun espace disponible ici pour déployer une arène.',
    no_zone              = 'Les combats improvisés ne sont pas autorisés dans cette zone.',
    server_busy          = 'Nombre maximal de matchs simultanés atteint sur le serveur.',
    expired              = 'Ce défi a expiré.',
    other_bucket         = 'Ce joueur ne se trouve pas dans la même instance.',
    offline              = 'Le joueur ciblé n\'est plus connecté.',
    no_top               = 'Toupie introuvable dans votre inventaire.',
    no_launcher          = 'Il te faut un lanceur dans ton inventaire. Passe à la boutique SPIN ARENA.',
    top_locked           = 'Cette toupie est déjà engagée dans un match ou à l\'atelier.',
    -- Assemblage par glisser-déposer dans l'inventaire
    assemble_ok          = 'Pièce montée : {part}. L\'ancienne pièce revient dans ton inventaire.',
    assemble_new         = 'Nouvelle toupie en montage. Ajoute les pièces manquantes pour pouvoir combattre.',
    repair_ok            = 'Toupie réparée.',
    owed_delivered       = '{count} objet(s) dû(s) rendu(s) dans ton inventaire.',
    top_invalid          = 'L\'assemblage de cette toupie est invalide.',
    no_part              = 'Pièce ou kit de réparation manquant dans votre inventaire.',
    inventory_full       = 'Votre inventaire est plein.',
    over_budget          = 'Cet assemblage dépasse le budget maximal de points.',
    pro_only             = 'Cette fonction fait partie de l\'édition Pro de SPIN ARENA.',
    db_unavailable       = 'Le service d\'atelier ou d\'inventaire est temporairement indisponible.',
    not_allowed          = 'Vous n\'avez pas la permission d\'effectuer cette action.',
    tournament_closed    = 'Les inscriptions à ce tournoi sont fermées.',
    tournament_full      = 'Ce tournoi est complet.',
    already_registered   = 'Vous êtes déjà inscrit à ce tournoi.',
    error                = 'Une erreur interne est survenue.',

    -- Alias préfixés err_* pour compatibilité directe
    err_rate_limited     = 'Action trop rapide. Veuillez patienter un instant.',
    err_invalid          = 'Requête ou paramètres invalides.',
    err_busy             = 'Une opération est déjà en cours.',
    err_not_found        = 'Défi ou match introuvable.',
    err_too_far          = 'Le joueur ciblé est trop éloigné.',
    err_in_vehicle       = 'Impossible de combattre depuis un véhicule.',
    err_dead             = 'Impossible de combattre dans cet état.',
    err_same_player      = 'Vous ne pouvez pas vous défier vous-même.',
    err_already_in_match = 'Vous participez déjà à un match.',
    err_target_busy      = 'Ce joueur a déjà un défi en attente ou un match en cours.',
    err_no_arena         = 'Aucun espace disponible ici pour déployer une arène.',
    err_no_zone          = 'Les combats improvisés ne sont pas autorisés dans cette zone.',
    err_server_busy      = 'Nombre maximal de matchs simultanés atteint sur le serveur.',
    err_expired          = 'Ce défi a expiré.',
    err_other_bucket     = 'Ce joueur ne se trouve pas dans la même instance.',
    err_offline          = 'Le joueur ciblé n\'est plus connecté.',
    err_no_top           = 'Toupie introuvable dans votre inventaire.',
    err_no_launcher      = 'Il te faut un lanceur dans ton inventaire. Passe à la boutique SPIN ARENA.',
    err_top_locked       = 'Cette toupie est déjà engagée dans un match ou à l\'atelier.',
    err_top_invalid      = 'L\'assemblage de cette toupie est invalide.',
    err_no_part          = 'Pièce ou kit de réparation manquant dans votre inventaire.',
    err_inventory_full   = 'Votre inventaire est plein.',
    err_over_budget      = 'Cet assemblage dépasse le budget maximal de points.',
    err_db_unavailable   = 'Le service d\'atelier ou d\'inventaire est temporairement indisponible.',
    err_not_allowed      = 'Vous n\'avez pas la permission d\'effectuer cette action.',
    err_tournament_closed = 'Les inscriptions à ce tournoi sont fermées.',
    err_tournament_full  = 'Ce tournoi est complet.',
    err_already_registered = 'Vous êtes déjà inscrit à ce tournoi.',
    err_error            = 'Une erreur interne est survenue.',

    -- Événements de défi (spin_arena:cl:challenge)
    challenge_sent       = 'Défi envoyé à {toName} (#{id}) avec le profil {top}.',
    challenge_incoming   = '{fromName} vous défie (#{id}, profil {top}) ! Ciblez-le pour accepter ou refuser.',
    challenge_accepted   = 'Défi #{id} accepté ! Préparation de l\'arène...',
    challenge_declined   = 'Défi #{id} refusé.',
    challenge_expired    = 'Le défi #{id} a expiré.',
    challenge_cancelled  = 'Le défi #{id} a été annulé.',

    -- Notifications serveur (spin_arena:cl:notify)
    leave_zone_warning   = 'Attention : vous êtes hors de la zone d\'arène ! Retournez-y sous {seconds} s sous peine d\'abandon.',
    leave_zone_forfeit   = 'Match perdu par sortie de la zone d\'arène.',
    spectator_joined     = 'Mode spectateur activé sur ce duel.',
    spectator_left       = 'Vous avez quitté la zone d\'observation de l\'arène.',
    tournament_created     = 'Tournoi « {tournament} » (#{id}, {size} joueurs) ouvert pendant {minutes} min !',
    tournament_started     = 'Le tournoi « {tournament} » démarre ({players} participants) !',
    tournament_match_ready = 'Tournoi « {tournament} » : votre match contre {opponent} est prêt ({seconds} s) !',
    tournament_eliminated  = 'Vous avez été éliminé du tournoi « {tournament} » au tour {round}.',
    tournament_won         = '{name} remporte le tournoi « {tournament} » !',
    tournament_no_winner   = 'Le tournoi « {tournament} » s\'est terminé sans vainqueur.',
    tournament_cancelled   = 'Le tournoi « {tournament} » a été annulé ({reason}).',
    tournament_invalid_top = 'Tournoi « {tournament} » : votre toupie inscrite est indisponible ({code}).',

    -- Fins de manche et de match
    reason_spin_out      = 'arrêt de rotation',
    reason_ring_out      = 'éjection hors arène',
    reason_time          = 'décision au temps',
    reason_rounds        = 'majorité des manches',
    reason_forfeit       = 'abandon',
    reason_no_contest    = 'sans résultat',
    reason_draw          = 'égalité',
    reason_cancel        = 'annulé',

    match_won            = 'Victoire de {winner} ({a} - {b}, {reason}) !',
    match_draw           = 'Match nul ({a} - {b}, {reason}).',
    match_no_contest     = 'Match interrompu sans vainqueur ({reason}).',
    match_cancelled      = 'Match annulé ({reason}).',
    forfeit_confirmed    = 'Vous avez abandonné le match.',

    -- Menus, atelier, boutique et ciblage (ox_lib / ox_target)
    cmd_no_incoming      = 'Aucun défi entrant en attente.',
    cmd_no_outgoing      = 'Aucun défi sortant à annuler.',
    cmd_not_in_match     = 'Aucun match ou défi actif.',
    dialog_title         = 'SPIN ARENA — Duel de toupies',
    dialog_select_top    = 'Choisir le profil de toupie',
    dialog_top_attack    = 'Prototype A (Attaque)',
    dialog_top_endurance = 'Prototype E (Endurance)',
    dialog_incoming_hdr  = 'Défi reçu de {fromName}',
    dialog_incoming_desc = 'Profil adverse : {top}. Voulez-vous relever le défi ?',
    target_challenge     = 'Défier à SPIN ARENA',
    target_station_challenge = 'Défier sur cette station',
    target_queue_join        = 'Rejoindre la table',
    target_queue_leave       = 'Quitter la file d\'attente',
    queue_joined             = 'Inscrit à la table ({waiting}/2) : le match commence dès qu\'un adversaire rejoint.',
    queue_left_ok            = 'Tu as quitté la file d\'attente.',
    queue_left               = 'Retiré de la file d\'attente ({reason}).',
    queue_failed             = 'Le match n\'a pas pu commencer ({reason}) : rejoins à nouveau la table.',
    station_title        = 'Station SPIN ARENA — {station}',
    station_no_opponents = 'Aucun adversaire à proximité de la station.',
    station_opponent_desc = 'Joueur #{id} ({distance} m)',
    target_accept        = 'Accepter le défi',
    target_decline       = 'Refuser le défi',
    target_cancel        = 'Annuler mon défi',
    target_forfeit       = 'Abandonner le match',
    target_challenge_atk = 'Défier à Spin Arena (Attaque)',
    target_challenge_end = 'Défier à Spin Arena (Endurance)',
    target_workshop      = 'Mes toupies',
    target_shop          = 'Boutique SPIN ARENA',
    target_leaderboard   = 'Classement SPIN ARENA',
    target_tournaments   = 'Tournois SPIN ARENA',
    shop_unavailable     = 'La boutique SPIN ARENA est actuellement indisponible.',
    leaderboard_title       = 'Classement SPIN ARENA — Saison {season}',
    leaderboard_me_title    = 'Mon classement : #{rank} ({rating} Elo)',
    leaderboard_me_unranked = 'Mon classement : Non classé ({rating} Elo)',
    leaderboard_me_desc     = '{name} — Bilan : {w}V - {l}D - {d}N',
    leaderboard_row_title   = '#{rank} — {name} ({rating} Elo)',
    leaderboard_row_desc    = 'Bilan : {w}V - {l}D - {d}N',
    leaderboard_empty       = 'Aucun joueur classé pour cette saison.',
    tournaments_title       = 'Tournois SPIN ARENA',
    tournaments_empty       = 'Aucun tournoi actif ou récent.',
    tournament_create_title = 'Créer un tournoi',
    tournament_create_desc  = 'Ouvrir les inscriptions d\'un nouveau tournoi (4, 8 ou 16 joueurs)',
    tournament_input_name   = 'Nom du tournoi (3 à 32 caractères)',
    tournament_input_size   = 'Taille du tableau (4, 8 ou 16 joueurs)',
    tournament_input_minutes = 'Durée des inscriptions (minutes, 1 à 60)',
    tournament_row_title    = '#{id} — {name} [{state}] ({players}/{size})',
    tournament_row_desc     = 'Organisateur : {organizer}{extra}',
    tournament_state_signup = 'Inscriptions',
    tournament_state_running = 'En cours',
    tournament_state_finished = 'Terminé',
    tournament_state_cancelled = 'Annulé',
    tournament_join_title   = 'Rejoindre ce tournoi (choisir ma toupie)',
    tournament_join_desc    = 'Inscrire une toupie possédée et complète ({players}/{size})',
    tournament_leave_title  = 'Se désinscrire du tournoi',
    tournament_leave_desc   = 'Retirer votre inscription tant que le tournoi n\'a pas démarré',
    tournament_mymatch_title = 'Mon match (Tour {round}) : contre {opponent}',
    tournament_mymatch_desc = 'État : {state} — Temps restant : {seconds} s',
    tournament_players_title = 'Participants inscrits ({count}/{size})',
    tournament_round_header = 'Tour {round} — {a} contre {b} [{state}]',
    tournament_round_winner = 'Vainqueur : {winner}',
    tournament_created_ok   = 'Tournoi « {name} » (#{id}) créé avec succès.',
    tournament_joined_ok    = 'Inscription au tournoi #{id} confirmée ({players}/{size}).',
    tournament_left_ok      = 'Vous avez quitté le tournoi.',
    workshop_title       = 'Mes toupies',
    workshop_empty       = 'Vous ne possédez aucune toupie dans votre inventaire.',
    workshop_top_desc    = '[{uid}] Famille : {family} | Peinture : {paint} | Budget : {cost}/{budget} | Usure : {wear} | Bilan : {w}V-{l}D-{d}N',
    workshop_stats_title = 'Caractéristiques de combat',
    workshop_stats_desc  = 'ATQ {atk} | DÉF {def} | STAB {stab} | END {endurance} | MOB {mob}',
    workshop_slot_title  = '{slot} : {part} ({cost} pts)',
    workshop_slot_desc   = 'Pour la changer : glisse une pièce sur la toupie dans ton inventaire ({mods})',
    workshop_disassemble_title = 'Démonter la toupie',
    workshop_disassemble_again = 'Appuie de nouveau sur « Démonter » dans les 5 s pour confirmer.',
    workshop_disassemble_desc = 'Toutes ses pièces reviennent dans ton inventaire',
    workshop_disassemble_confirm = 'Démonter cette toupie ? Elle disparaît et toutes ses pièces reviennent dans ton inventaire.',
    workshop_part_equip  = '{label} ({cost} pts) — x{count}',
    workshop_part_equipped = '{label} ({cost} pts) [Équipée]',
    workshop_no_parts_owned = 'Aucune pièce compatible dans votre inventaire.',
    workshop_repair_title = 'Réparer la toupie (Kit de réparation)',
    workshop_repair_desc = 'Usure actuelle : {wear} — remet l\'usure à 0',
    workshop_rename_title = 'Renommer la toupie',
    workshop_rename_desc = 'Nom actuel : {name} (1 à 24 caractères)',
    workshop_rename_input = 'Nouveau nom de la toupie',
    workshop_paint_title = 'Changer la peinture',
    workshop_paint_desc  = 'Peinture actuelle : {paint}',
    workshop_equip_ok    = 'Pièce équipée avec succès.',
    workshop_repair_ok   = 'Toupie réparée à neuf.',
    workshop_rename_ok   = 'Toupie renommée en « {name} ».',
    workshop_paint_ok    = 'Peinture appliquée avec succès.',
    workshop_equipped_ok = 'Pièce équipée avec succès.',
    workshop_repaired_ok = 'Toupie réparée avec succès.',
    workshop_renamed_ok  = 'Toupie renommée en « {name} ».',
    workshop_disassembled_ok = 'Toupie démontée : {count} pièce(s) rendue(s) dans ton inventaire.',
    workshop_painted_ok  = 'Peinture appliquée avec succès.',
    workshop_rename_lbl  = 'Nouveau nom (1 à 24 caractères)',
    select_top_real_desc = 'Famille : {family} | Peinture : {paint} | Usure : {wear} | {w}V-{l}D{repair}',
    select_top_repair    = ' | À réparer (kit)',
    select_top_locked_suffix = ' (Verrouillée)',
    select_top_invalid_suffix = ' (Incomplète)',

    -- Bandeaux HUD (client/renderer.lua)
    hud_spectator_tag    = '[SPECTATEUR] ',
    hud_header_score     = '{spectator}{nameA}  {scoreA} - {scoreB}  {nameB} (Manche {round}/{bestOf})',
    hud_countdown        = 'SPIN ARENA — MANCHE {round} — LANCEMENT DANS {seconds} s',
    hud_preparing        = 'SPIN ARENA — MANCHE {round} — PRÉPARATION...',
    hud_playing          = 'SPIN ARENA — MANCHE {round} — {elapsed} s{sync}',
    hud_sync_warn        = ' [SYNCHRONISATION...]',
    hud_round_end        = 'SPIN ARENA — FIN MANCHE {round} — {winner} ({reason})',
    hud_match_end_win    = 'SPIN ARENA — VICTOIRE : {winner} ({scoreA} - {scoreB}) [{reason}]',
    hud_match_end_draw   = 'SPIN ARENA — ÉGALITÉ FINALE ({scoreA} - {scoreB}) [{reason}]',
    hud_match_end_nc     = 'SPIN ARENA — MATCH SANS RÉSULTAT [{reason}]',
}

SpinArena.Locales.fr = FR
if not SpinArena.Locale then
    SpinArena.Locale = 'fr'
end

function SpinArena.L(key, args, ...)
    local lang = SpinArena.Locale or 'fr'
    local dict = (SpinArena.Locales and SpinArena.Locales[lang])
        or (SpinArena.Locales and SpinArena.Locales.fr)
        or FR
    local tpl = dict[key] or (SpinArena.Locales.fr and SpinArena.Locales.fr[key]) or tostring(key)
    if args == nil then
        return tpl
    end
    if type(args) == 'table' then
        local out = tpl:gsub('{([%w_]+)}', function(k)
            local v = args[k]
            if v == nil then
                local idx = tonumber(k)
                if idx then v = args[idx] end
            end
            return v ~= nil and tostring(v) or ('{' .. k .. '}')
        end)
        if out == tpl and args[1] ~= nil and tpl:find('%%', 1, true) then
            local ok, formatted = pcall(string.format, tpl, table.unpack(args))
            if ok then return formatted end
        end
        return out
    end
    local packed = { args, ... }
    if tpl:find('{', 1, true) then
        tpl = tpl:gsub('{(%d+)}', function(d)
            local v = packed[tonumber(d)]
            return v ~= nil and tostring(v) or ('{' .. d .. '}')
        end)
    end
    if tpl:find('%%', 1, true) then
        local ok, formatted = pcall(string.format, tpl, args, ...)
        if ok then return formatted end
    end
    return tpl
end

return FR
