-- Noms d'événements et codes de réponse partagés par le serveur et le client (docs/ARCHITECTURE.md §9).
-- Le préfixe est fixe : il ne dépend pas du nom du dossier de la ressource.
SpinArena = SpinArena or {}

SpinArena.Protocol = {
    -- Client → serveur : lib.callback, réponse { ok = booléen, code = chaîne, ... }
    cb = {
        challenge = 'spin_arena:challenge',
        respond = 'spin_arena:respond',
        cancel = 'spin_arena:cancel',
        forfeit = 'spin_arena:forfeit',
        state = 'spin_arena:state',
        leaderboard = 'spin_arena:leaderboard',
        tops = 'spin_arena:tops',
        workshop = 'spin_arena:workshop',
        shop = 'spin_arena:shop',
        shopBuy = 'spin_arena:shop_buy',      -- achat dans la boutique unique (NUI), prix et catalogue serveur
        queueJoin = 'spin_arena:queue_join',          -- rejoindre la file d'une table (toupie choisie)
        queueLeave = 'spin_arena:queue_leave',
        launchArm = 'spin_arena:launch_arm',          -- armer son lanceur : le serveur renvoie nonce et jauge
        launchGrip = 'spin_arena:launch_grip',        -- saisir la tirette : le serveur note l'instant et la prise sur la jauge
        launchRelease = 'spin_arena:launch_release',  -- tirer : nonce et inclinaison ; la qualité est calculée serveur
        tournamentCreate = 'spin_arena:tournament_create',
        tournamentJoin = 'spin_arena:tournament_join',
        tournamentLeave = 'spin_arena:tournament_leave',
        tournamentStatus = 'spin_arena:tournament_status',
    },
    -- Serveur → client : TriggerClientEvent ciblé
    ev = {
        challenge = 'spin_arena:cl:challenge',
        match = 'spin_arena:cl:match',
        countdown = 'spin_arena:cl:countdown',
        frames = 'spin_arena:cl:frames',
        roundEnd = 'spin_arena:cl:roundEnd',
        matchEnd = 'spin_arena:cl:matchEnd',
        cancel = 'spin_arena:cl:cancel',
        unsub = 'spin_arena:cl:unsub',
        notify = 'spin_arena:cl:notify',
        prepare = 'spin_arena:cl:prepare',
        seasonTop = 'spin_arena:cl:seasonTop',
        stations = 'spin_arena:cl:stations',  -- 29/10 : les arènes fixes ont changé (ajout/suppression par un administrateur) : relire la boutique
        queue = 'spin_arena:cl:queue',        -- état de la file d'une table (joueurs autour) : waiting, names.a -- 5 premiers de la saison (panneau de classement près des tables)    -- préparation de manche : délai, joueurs prêts, règle du délai
    },
    codes = {
        ok = 'ok',
        rate_limited = 'rate_limited',     -- trop de demandes
        invalid = 'invalid',               -- données refusées
        busy = 'busy',                     -- une autre opération du joueur est en cours
        not_found = 'not_found',           -- défi ou match inexistant
        too_far = 'too_far',               -- joueurs trop éloignés
        in_vehicle = 'in_vehicle',
        dead = 'dead',
        same_player = 'same_player',
        already_in_match = 'already_in_match',
        target_busy = 'target_busy',       -- la cible a déjà un défi ou un match
        no_arena = 'no_arena',             -- pas de place pour une arène ici
        no_zone = 'no_zone',               -- combat improvisé interdit ici
        server_busy = 'server_busy',       -- trop de matchs en cours
        expired = 'expired',
        other_bucket = 'other_bucket',     -- pas dans le même monde (routing bucket)
        offline = 'offline',
        no_top = 'no_top',                 -- toupie absente de l'inventaire
        no_launcher = 'no_launcher',       -- lanceur absent de l'inventaire
        top_locked = 'top_locked',         -- toupie déjà engagée (match ou atelier)
        top_invalid = 'top_invalid',       -- assemblage inutilisable
        no_part = 'no_part',               -- pièce ou kit absent de l'inventaire
        inventory_full = 'inventory_full',
        no_money = 'no_money',             -- argent insuffisant pour un achat
        shop_closed = 'shop_closed',       -- boutique désactivée ou sans point de vente
        over_budget = 'over_budget',       -- l'assemblage dépasse le budget de points
        db_unavailable = 'db_unavailable', -- base ou inventaire indisponible
        pro_only = 'pro_only',             -- fonction de l'édition Pro (tournois), absente de l'édition gratuite
        not_allowed = 'not_allowed',       -- droit d'organisateur manquant
        tournament_closed = 'tournament_closed',
        tournament_full = 'tournament_full',
        already_registered = 'already_registered',
        not_preparing = 'not_preparing',   -- la manche n'attend pas de lancement
        bad_nonce = 'bad_nonce',           -- armement inconnu, déjà utilisé ou d'un autre joueur/manche
        already_launched = 'already_launched',
        already_gripped = 'already_gripped',   -- tirette déjà saisie : le geste suivant est le tirage
        too_early = 'too_early',           -- relâché avant minHoldMs : réarmer
        error = 'error',
    },
}

return SpinArena.Protocol
